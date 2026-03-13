defmodule LucaGymapp.GoogleCalendar do
  import Ecto.Query, warn: false

  alias LucaGymapp.GoogleCalendar.Connection
  alias LucaGymapp.GoogleCalendar.TokenCipher
  alias LucaGymapp.Repo

  @scope "openid email https://www.googleapis.com/auth/calendar"

  def current_oauth_mode do
    Application.get_env(:luca_gymapp, :google_calendar, [])
    |> Keyword.get(:oauth_mode, "test")
  end

  def default_calendar_id do
    Application.get_env(:luca_gymapp, :google_calendar, [])
    |> Keyword.get(:default_calendar_id, "primary")
  end

  def configured_client_id do
    Application.get_env(:luca_gymapp, :google_calendar, [])
    |> Keyword.get(:client_id)
  end

  def configured_client_secret do
    Application.get_env(:luca_gymapp, :google_calendar, [])
    |> Keyword.get(:client_secret)
  end

  def configured_redirect_uri do
    Application.get_env(:luca_gymapp, :google_calendar, [])
    |> Keyword.get(:redirect_uri)
  end

  def oauth_scope, do: @scope

  def missing_config_fields do
    [
      {"GOOGLE_CALENDAR_CLIENT_ID", configured_client_id()},
      {"GOOGLE_CALENDAR_CLIENT_SECRET", configured_client_secret()},
      {"GOOGLE_CALENDAR_REDIRECT_URI", configured_redirect_uri()}
    ]
    |> Enum.reduce([], fn
      {name, value}, acc when value in [nil, ""] -> [name | acc]
      _, acc -> acc
    end)
    |> Enum.reverse()
  end

  def config_ready?, do: missing_config_fields() == []

  def authorize_url(state) when is_binary(state) do
    query =
      URI.encode_query(%{
        client_id: configured_client_id(),
        redirect_uri: configured_redirect_uri(),
        response_type: "code",
        access_type: "offline",
        include_granted_scopes: "true",
        prompt: "consent",
        scope: @scope,
        state: state
      })

    "https://accounts.google.com/o/oauth2/v2/auth?" <> query
  end

  def get_connection_for_user(user_id) when is_integer(user_id) do
    Repo.get_by(Connection, user_id: user_id)
  end

  def get_active_connection do
    Connection
    |> where([connection], connection.sync_enabled == true)
    |> where([connection], connection.oauth_mode == ^current_oauth_mode())
    |> where([connection], not is_nil(connection.refresh_token_encrypted))
    |> order_by([connection], desc: connection.updated_at)
    |> limit(1)
    |> Repo.one()
  end

  def connect_admin_user(user, code) do
    with :ok <- ensure_config_ready(),
         {:ok, token_data} <-
           client().exchange_code(
             code,
             configured_redirect_uri(),
             configured_client_id(),
             configured_client_secret()
           ),
         refresh_token when is_binary(refresh_token) and refresh_token != "" <-
           token_data.refresh_token,
         {:ok, profile} <- client().fetch_user_profile(token_data.access_token) do
      upsert_connection(user.id, %{
        google_email: profile.email,
        refresh_token_encrypted: TokenCipher.encrypt(refresh_token),
        oauth_mode: current_oauth_mode(),
        sync_enabled: true,
        last_sync_error: nil,
        last_synced_at: nil
      })
    else
      nil ->
        {:error, :missing_refresh_token}

      {:error, _} = error ->
        error

      _ ->
        {:error, :invalid_google_response}
    end
  end

  def disconnect_connection(user_id) when is_integer(user_id) do
    case get_connection_for_user(user_id) do
      nil ->
        {:ok, :already_disconnected}

      connection ->
        connection
        |> Connection.changeset(%{
          refresh_token_encrypted: nil,
          sync_enabled: false,
          last_sync_error: nil,
          last_synced_at: nil
        })
        |> Repo.update()
    end
  end

  def effective_calendar_id(%Connection{} = connection) do
    connection.calendar_id || default_calendar_id()
  end

  def refresh_access_token(%Connection{} = connection) do
    with {:ok, refresh_token} when is_binary(refresh_token) <-
           decrypted_refresh_token(connection),
         {:ok, access_token} <-
           client().refresh_access_token(
             refresh_token,
             configured_client_id(),
             configured_client_secret()
           ) do
      {:ok, access_token}
    else
      :error -> {:error, :missing_refresh_token}
      nil -> {:error, :missing_refresh_token}
      {:error, _} = error -> error
    end
  end

  def create_booking_event(%Connection{} = connection, event_id, attrs) do
    with {:ok, access_token} <- refresh_access_token(connection),
         {:ok, event_id} <-
           client().create_event(
             access_token,
             effective_calendar_id(connection),
             Map.put(attrs, :id, event_id)
           ) do
      mark_sync_success(connection)
      {:ok, event_id}
    else
      {:error, reason} = error ->
        mark_sync_error(connection, inspect(reason))
        error
    end
  end

  def delete_booking_event(%Connection{} = connection, event_id) when is_binary(event_id) do
    with {:ok, access_token} <- refresh_access_token(connection),
         :ok <- client().delete_event(access_token, effective_calendar_id(connection), event_id) do
      mark_sync_success(connection)
      :ok
    else
      {:error, reason} = error ->
        mark_sync_error(connection, inspect(reason))
        error
    end
  end

  def mark_sync_success(%Connection{} = connection) do
    connection
    |> Connection.changeset(%{
      last_sync_error: nil,
      last_synced_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  def mark_sync_error(%Connection{} = connection, message) when is_binary(message) do
    connection
    |> Connection.changeset(%{last_sync_error: message})
    |> Repo.update()
  end

  defp upsert_connection(user_id, attrs) do
    case get_connection_for_user(user_id) do
      nil ->
        %Connection{}
        |> Connection.changeset(Map.put(attrs, :user_id, user_id))
        |> Repo.insert()

      connection ->
        connection
        |> Connection.changeset(attrs)
        |> Repo.update()
    end
  end

  defp ensure_config_ready do
    if config_ready?(), do: :ok, else: {:error, :missing_config}
  end

  defp decrypted_refresh_token(%Connection{} = connection) do
    case TokenCipher.decrypt(connection.refresh_token_encrypted) do
      {:ok, refresh_token} when is_binary(refresh_token) -> {:ok, refresh_token}
      refresh_token when is_binary(refresh_token) -> {:ok, refresh_token}
      _ -> :error
    end
  end

  defp client do
    Application.get_env(:luca_gymapp, :google_calendar_client, LucaGymapp.GoogleCalendar.Client)
  end
end
