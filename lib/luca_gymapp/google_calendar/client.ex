defmodule LucaGymapp.GoogleCalendar.Client do
  @token_url "https://oauth2.googleapis.com/token"
  @userinfo_url "https://openidconnect.googleapis.com/v1/userinfo"
  @calendar_base_url "https://www.googleapis.com/calendar/v3"

  def exchange_code(code, redirect_uri, client_id, client_secret) do
    case Req.post(@token_url,
           form: [
             code: code,
             client_id: client_id,
             client_secret: client_secret,
             redirect_uri: redirect_uri,
             grant_type: "authorization_code"
           ]
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok,
         %{
           access_token: body["access_token"],
           refresh_token: body["refresh_token"]
         }}

      {:ok, %{status: status, body: body}} ->
        {:error, {:token_exchange_failed, status, body}}

      {:error, reason} ->
        {:error, {:token_exchange_failed, reason}}
    end
  end

  def refresh_access_token(refresh_token, client_id, client_secret) do
    case Req.post(@token_url,
           form: [
             refresh_token: refresh_token,
             client_id: client_id,
             client_secret: client_secret,
             grant_type: "refresh_token"
           ]
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body["access_token"]}

      {:ok, %{status: status, body: body}} ->
        {:error, {:refresh_failed, status, body}}

      {:error, reason} ->
        {:error, {:refresh_failed, reason}}
    end
  end

  def fetch_user_profile(access_token) do
    case Req.get(@userinfo_url, auth: {:bearer, access_token}) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, %{email: body["email"]}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:userinfo_failed, status, body}}

      {:error, reason} ->
        {:error, {:userinfo_failed, reason}}
    end
  end

  def create_event(access_token, calendar_id, attrs) do
    url = "#{@calendar_base_url}/calendars/#{URI.encode(calendar_id)}/events"

    case Req.post(url, auth: {:bearer, access_token}, json: attrs) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, attrs.id}

      {:ok, %{status: 409}} ->
        {:ok, attrs.id}

      {:ok, %{status: status, body: body}} ->
        {:error, {:create_event_failed, status, body}}

      {:error, reason} ->
        {:error, {:create_event_failed, reason}}
    end
  end

  def delete_event(access_token, calendar_id, event_id) do
    url =
      "#{@calendar_base_url}/calendars/#{URI.encode(calendar_id)}/events/#{URI.encode(event_id)}"

    case Req.delete(url, auth: {:bearer, access_token}) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: 404}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:delete_event_failed, status, body}}

      {:error, reason} ->
        {:error, {:delete_event_failed, reason}}
    end
  end
end
