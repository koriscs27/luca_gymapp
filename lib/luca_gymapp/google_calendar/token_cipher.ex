defmodule LucaGymapp.GoogleCalendar.TokenCipher do
  alias LucaGymappWeb.Endpoint

  @encrypt_salt "google-calendar-refresh-token"
  @sign_salt "google-calendar-refresh-token-sign"

  def encrypt(nil), do: nil

  def encrypt(value) when is_binary(value) do
    secret = secret_key_base()

    Plug.Crypto.MessageEncryptor.encrypt(
      value,
      Plug.Crypto.KeyGenerator.generate(secret, @encrypt_salt, length: 32),
      Plug.Crypto.KeyGenerator.generate(secret, @sign_salt, length: 32)
    )
  end

  def decrypt(nil), do: nil

  def decrypt(value) when is_binary(value) do
    secret = secret_key_base()

    Plug.Crypto.MessageEncryptor.decrypt(
      value,
      Plug.Crypto.KeyGenerator.generate(secret, @encrypt_salt, length: 32),
      Plug.Crypto.KeyGenerator.generate(secret, @sign_salt, length: 32)
    )
  end

  defp secret_key_base do
    Endpoint.config(:secret_key_base) ||
      raise "secret_key_base is required for Google Calendar token encryption"
  end
end
