defmodule Mix.Tasks.MailgunTest do
  use Mix.Task

  @shortdoc "Send a one-off Mailgun test email (guarded by env vars)"

  @moduledoc """
  Sends a single email via the configured Swoosh Mailgun adapter.

  This task is intentionally guarded and will only run when:
  - MAILGUN_TEST=true
  - MAILGUN_TEST_TO is set (recipient)

  Example:
      MAILGUN_TEST=true MAILGUN_TEST_TO=koriscs@gmail.com mix mailgun_test
  """

  def run(_args) do
    Mix.Task.run("app.start")

    if System.get_env("MAILGUN_TEST") != "true" do
      Mix.raise("""
      Refusing to send test email.
      Set MAILGUN_TEST=true to allow it.
      """)
    end

    to = System.get_env("MAILGUN_TEST_TO") || "koriscs@gmail.com"
    config = Application.get_env(:luca_gymapp, LucaGymapp.Mailer, [])
    base_url = config[:base_url]
    domain = config[:domain]
    api_key = config[:api_key]

    if is_nil(base_url) or base_url == "" do
      Mix.raise("MAILGUN_BASE_URL is missing in config.")
    end

    if is_nil(domain) or domain == "" do
      Mix.raise("MAILGUN_DOMAIN is missing in config.")
    end

    if is_nil(api_key) or api_key == "" do
      Mix.raise("MAILGUN_API_KEY is missing in config.")
    end

    Mix.shell().info("Mailgun base_url: #{base_url}")
    Mix.shell().info("Mailgun domain: #{domain}")

    if String.ends_with?(base_url, "/") do
      Mix.shell().info("Warning: MAILGUN_BASE_URL has a trailing slash.")
    end

    preflight_check!(base_url, domain, api_key)

    email =
      Swoosh.Email.new()
      |> Swoosh.Email.to({"Test Recipient", to})
      |> Swoosh.Email.from(default_from())
      |> Swoosh.Email.subject("Mailgun API test")
      |> Swoosh.Email.text_body(test_body())

    case LucaGymapp.Mailer.deliver(email) do
      {:ok, response} ->
        Mix.shell().info("Mailgun test email sent to #{to}.")
        Mix.shell().info("Response: #{inspect(response)}")

      {:error, reason} ->
        Mix.raise("Mailgun test email failed: #{inspect(reason)}")
    end
  end

  defp default_from do
    Application.get_env(:luca_gymapp, LucaGymapp.Mailer)[:default_from] ||
      {"LucaGymapp", "no-reply@localhost"}
  end

  defp test_body do
    """
    This is a manual Mailgun API test from LucaGymapp.

    Time (UTC): #{DateTime.utc_now() |> DateTime.truncate(:second)}
    """
  end

  defp preflight_check!(base_url, domain, api_key) do
    url =
      base_url
      |> String.trim_trailing("/")
      |> Kernel.<>("/domains/#{domain}")

    case Req.get(url, auth: {:basic, "api:#{api_key}"}) do
      {:ok, %Req.Response{status: 200}} ->
        Mix.shell().info("Mailgun domain lookup OK.")

      {:ok, %Req.Response{status: 401}} ->
        Mix.raise("Mailgun auth failed (401). Check MAILGUN_API_KEY.")

      {:ok, %Req.Response{status: 404}} ->
        Mix.raise("""
        Mailgun domain not found (404). This usually means region mismatch.
        Verify the domain's region in Mailgun and set MAILGUN_BASE_URL accordingly.
        """)

      {:ok, %Req.Response{status: status, body: body}} ->
        Mix.raise("Mailgun domain lookup failed (#{status}): #{inspect(body)}")

      {:error, reason} ->
        Mix.raise("Mailgun domain lookup error: #{inspect(reason)}")
    end
  end
end
