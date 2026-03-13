defmodule LucaGymappWeb.GoogleCalendarControllerTest do
  use LucaGymappWeb.ConnCase

  alias LucaGymapp.Accounts.User
  alias LucaGymapp.GoogleCalendar
  alias LucaGymapp.GoogleCalendar.Connection
  alias LucaGymapp.Repo

  test "admin page rejects guests", %{conn: conn} do
    conn = get(conn, ~p"/admin/google-calendar")

    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error)
  end

  test "admin page rejects non-admin users", %{conn: conn} do
    user =
      %User{
        email: "member@example.com",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    conn =
      conn
      |> init_test_session(%{user_id: user.id})
      |> get(~p"/admin/google-calendar")

    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error)
  end

  test "admin page is visible to admins and home nav shows menu entry", %{conn: conn} do
    admin_user =
      %User{
        email: "admin-calendar@example.com",
        admin: true,
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    page_conn =
      conn
      |> init_test_session(%{user_id: admin_user.id})
      |> get(~p"/admin/google-calendar")

    assert html_response(page_conn, 200) =~ "Google Calendar Sync"

    home_conn =
      build_conn()
      |> init_test_session(%{user_id: admin_user.id})
      |> get(~p"/")

    html = html_response(home_conn, 200)

    assert html =~ ~s(href="/admin/google-calendar")
  end

  test "home nav hides google calendar entry from non-admin users", %{conn: conn} do
    user =
      %User{
        email: "member-home@example.com",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    conn =
      conn
      |> init_test_session(%{user_id: user.id})
      |> get(~p"/")

    html = html_response(conn, 200)

    refute html =~ ~s(href="/admin/google-calendar")
  end

  test "google calendar connection can be stored for an admin", %{conn: _conn} do
    previous_stub = Application.get_env(:luca_gymapp, :google_calendar_stub, %{})
    previous_google_calendar = Application.get_env(:luca_gymapp, :google_calendar, [])

    on_exit(fn ->
      Application.put_env(:luca_gymapp, :google_calendar_stub, previous_stub)
      Application.put_env(:luca_gymapp, :google_calendar, previous_google_calendar)
    end)

    Application.put_env(:luca_gymapp, :google_calendar_stub, %{
      exchange_code: {:ok, %{access_token: "access", refresh_token: "refresh"}},
      fetch_user_profile: {:ok, %{email: "coach@example.com"}}
    })

    Application.put_env(:luca_gymapp, :google_calendar,
      oauth_mode: "test",
      default_calendar_id: "primary",
      client_id: "test-google-calendar-client-id",
      client_secret: "test-google-calendar-client-secret",
      redirect_uri: "http://www.example.com/admin/google-calendar/callback"
    )

    admin_user =
      %User{
        email: "callback-admin@example.com",
        admin: true,
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    assert {:ok, _connection} = GoogleCalendar.connect_admin_user(admin_user, "test-code")

    connection = Repo.get_by!(Connection, user_id: admin_user.id)

    assert connection.google_email == "coach@example.com"
    assert connection.sync_enabled
    assert is_binary(connection.refresh_token_encrypted)
  end
end
