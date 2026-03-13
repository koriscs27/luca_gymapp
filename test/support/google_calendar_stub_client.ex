defmodule LucaGymapp.GoogleCalendar.StubClient do
  def exchange_code(_code, _redirect_uri, _client_id, _client_secret) do
    Map.get(stub_config(), :exchange_code) ||
      {:ok, %{access_token: "access-token", refresh_token: "refresh-token"}}
  end

  def refresh_access_token(_refresh_token, _client_id, _client_secret) do
    Map.get(stub_config(), :refresh_access_token) || {:ok, "access-token"}
  end

  def fetch_user_profile(_access_token) do
    Map.get(stub_config(), :fetch_user_profile) || {:ok, %{email: "coach@example.com"}}
  end

  def create_event(_access_token, calendar_id, attrs) do
    notify({:google_calendar_create_event, calendar_id, attrs})
    Map.get(stub_config(), :create_event) || {:ok, attrs.id}
  end

  def delete_event(_access_token, calendar_id, event_id) do
    notify({:google_calendar_delete_event, calendar_id, event_id})
    Map.get(stub_config(), :delete_event) || :ok
  end

  defp stub_config do
    Application.get_env(:luca_gymapp, :google_calendar_stub, %{})
  end

  defp notify(message) do
    if pid = stub_config()[:notify_pid] do
      send(pid, message)
    end
  end
end
