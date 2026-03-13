defmodule LucaGymappWeb.GoogleCalendarController do
  use LucaGymappWeb, :controller

  alias LucaGymapp.Accounts
  alias LucaGymapp.GoogleCalendar

  def show(conn, _params) do
    with {:ok, admin_user} <- require_admin(conn) do
      render(conn, :show,
        current_user: admin_user,
        current_user_is_admin: true,
        connection: GoogleCalendar.get_connection_for_user(admin_user.id),
        oauth_mode: GoogleCalendar.current_oauth_mode(),
        effective_calendar_id: GoogleCalendar.default_calendar_id(),
        missing_config_fields: GoogleCalendar.missing_config_fields()
      )
    else
      {:error, redirected_conn} -> redirected_conn
    end
  end

  def connect(conn, _params) do
    with {:ok, admin_user} <- require_admin(conn),
         true <- GoogleCalendar.config_ready?() do
      state =
        Phoenix.Token.sign(
          conn,
          "google-calendar-oauth",
          "#{admin_user.id}:#{System.unique_integer([:positive])}"
        )

      conn
      |> put_session(:google_calendar_oauth_state, state)
      |> redirect(external: GoogleCalendar.authorize_url(state))
    else
      false ->
        conn
        |> put_flash(:error, "A Google Calendar kapcsolat nincs rendesen beallitva.")
        |> redirect(to: ~p"/admin/google-calendar")

      {:error, redirected_conn} ->
        redirected_conn
    end
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    case require_admin(conn) do
      {:ok, admin_user} ->
        with ^state <- get_session(conn, :google_calendar_oauth_state),
             {:ok, _connection} <- GoogleCalendar.connect_admin_user(admin_user, code) do
          conn
          |> delete_session(:google_calendar_oauth_state)
          |> put_flash(:info, "A Google Calendar kapcsolat aktiv.")
          |> redirect(to: ~p"/admin/google-calendar")
        else
          nil ->
            invalid_state(conn)

          {:error, :missing_config} ->
            callback_error(conn, "A Google Calendar kapcsolat nincs rendesen beallitva.")

          {:error, :missing_refresh_token} ->
            callback_error(
              conn,
              "A Google nem adott uj refresh tokent. Probald ujra a kapcsolatot."
            )

          {:error, _reason} ->
            callback_error(conn, "A Google Calendar kapcsolat sikertelen volt.")

          _ ->
            invalid_state(conn)
        end

      {:error, redirected_conn} ->
        redirected_conn
    end
  end

  def callback(conn, _params),
    do: callback_error(conn, "A Google Calendar kapcsolat sikertelen volt.")

  def disconnect(conn, _params) do
    with {:ok, admin_user} <- require_admin(conn),
         {:ok, _result} <- GoogleCalendar.disconnect_connection(admin_user.id) do
      conn
      |> put_flash(:info, "A Google Calendar kapcsolat kikapcsolva.")
      |> redirect(to: ~p"/admin/google-calendar")
    else
      {:error, redirected_conn} ->
        redirected_conn

      _ ->
        conn
        |> put_flash(:error, "A Google Calendar kapcsolatot nem sikerult kikapcsolni.")
        |> redirect(to: ~p"/admin/google-calendar")
    end
  end

  defp require_admin(conn) do
    case get_session(conn, :user_id) do
      nil ->
        {:error,
         conn
         |> put_flash(:error, "Ez az oldal csak adminoknak erheto el.")
         |> redirect(to: ~p"/")}

      user_id ->
        case Accounts.get_user(user_id) do
          %{admin: true} = user ->
            {:ok, user}

          _ ->
            {:error,
             conn
             |> put_flash(:error, "Ez az oldal csak adminoknak erheto el.")
             |> redirect(to: ~p"/")}
        end
    end
  end

  defp invalid_state(conn) do
    callback_error(conn, "A Google Calendar kapcsolati allapot ervenytelen vagy lejart.")
  end

  defp callback_error(conn, message) do
    conn
    |> delete_session(:google_calendar_oauth_state)
    |> put_flash(:error, message)
    |> redirect(to: ~p"/admin/google-calendar")
  end
end
