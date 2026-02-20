defmodule LucaGymappWeb.RegistrationController do
  use LucaGymappWeb, :controller

  alias LucaGymapp.Accounts
  require Logger

  def new(conn, _params) do
    form = Phoenix.Component.to_form(%{}, as: :user)
    render(conn, :register, form: form, turnstile_site_key: turnstile_site_key())
  end

  def create(conn, %{"user" => user_params} = params) do
    turnstile_token = Map.get(params, "cf-turnstile-response")
    accept_adatkezelesi = Map.get(params, "accept_adatkezelesi")

    with :ok <- verify_turnstile(conn, turnstile_token),
         :ok <- verify_adatkezelesi_acceptance(accept_adatkezelesi),
         {:ok, user} <- Accounts.register_user(user_params) do
      Accounts.deliver_confirmation_instructions(user)

      conn
      |> put_flash(:info, "Sikeres regisztráció. Küldtünk egy megerősítő e-mailt.")
      |> redirect(to: "/#registration-success")
    else
      {:error, :turnstile_missing} ->
        render_register_error(conn, user_params, "Kérlek igazold, hogy nem vagy robot.")

      {:error, :turnstile_failed} ->
        render_register_error(conn, user_params, "A robotellenőrzés sikertelen. Próbáld újra.")

      {:error, :turnstile_unavailable} ->
        render_register_error(
          conn,
          user_params,
          "A robotellenőrzés most nem elérhető. Próbáld később."
        )

      {:error, :turnstile_not_configured} ->
        render_register_error(conn, user_params, "A robotellenőrzés nincs beállítva.")

      {:error, :adatkezelesi_not_accepted} ->
        render_register_error(
          conn,
          user_params,
          "A regisztrációhoz el kell fogadnod az Adatkezelési Tájékoztatót."
        )

      {:error, changeset} ->
        error_message =
          cond do
            email_already_registered?(changeset) ->
              "Ez az e-mail cím már regisztrálva van."

            password_confirmation_error?(changeset) ->
              "A megadott jelszavak nem egyeznek."

            true ->
              "A regisztráció sikertelen. Ellenőrizd az adatokat."
          end

        render_register_error(conn, user_params, error_message)
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "A regisztráció sikertelen. Ellenőrizd az adatokat.")
    |> redirect(to: ~p"/register")
  end

  defp email_already_registered?(changeset) do
    Enum.any?(changeset.errors, fn
      {:email, {_message, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end

  defp password_confirmation_error?(changeset) do
    Enum.any?(changeset.errors, fn
      {:password_confirmation, {_message, _opts}} -> true
      _ -> false
    end)
  end

  defp render_register_error(conn, user_params, message) do
    form = Phoenix.Component.to_form(user_params, as: :user)

    conn
    |> put_flash(:error, message)
    |> render(:register, form: form, turnstile_site_key: turnstile_site_key())
  end

  defp verify_turnstile(conn, token) do
    if turnstile_required?() do
      do_verify_turnstile(conn, token)
    else
      :ok
    end
  end

  defp turnstile_required?, do: Application.get_env(:luca_gymapp, :turnstile_required, true)

  defp do_verify_turnstile(_conn, token) when token in [nil, ""] do
    {:error, :turnstile_missing}
  end

  defp do_verify_turnstile(conn, token) do
    secret_key = turnstile_secret_key()

    if secret_key in [nil, ""] do
      {:error, :turnstile_not_configured}
    else
      remote_ip =
        conn.remote_ip
        |> :inet.ntoa()
        |> to_string()

      response =
        safe_turnstile_request(%{
          secret: secret_key,
          response: token,
          remoteip: remote_ip
        })

      case response do
        {:ok, %{status: 200, body: %{"success" => true}}} ->
          :ok

        {:ok, %{status: 200, body: %{"success" => false}}} ->
          {:error, :turnstile_failed}

        {:ok, %{status: 200, body: body}} when is_binary(body) ->
          case Jason.decode(body) do
            {:ok, %{"success" => true}} -> :ok
            {:ok, %{"success" => false}} -> {:error, :turnstile_failed}
            _ -> {:error, :turnstile_unavailable}
          end

        _ ->
          {:error, :turnstile_unavailable}
      end
    end
  end

  defp verify_adatkezelesi_acceptance(value) when value in ["true", "on", "1"], do: :ok
  defp verify_adatkezelesi_acceptance(_), do: {:error, :adatkezelesi_not_accepted}

  defp safe_turnstile_request(form) do
    Req.post(
      "https://challenges.cloudflare.com/turnstile/v0/siteverify",
      form: form,
      receive_timeout: 10_000
    )
  rescue
    exception ->
      Logger.warning("turnstile_request_exception reason=#{Exception.message(exception)}")
      {:error, :turnstile_unavailable}
  catch
    kind, reason ->
      Logger.warning("turnstile_request_exception kind=#{kind} reason=#{inspect(reason)}")
      {:error, :turnstile_unavailable}
  end

  defp turnstile_site_key do
    Application.get_env(:luca_gymapp, :turnstile, [])
    |> Keyword.get(:site_key)
  end

  defp turnstile_secret_key do
    Application.get_env(:luca_gymapp, :turnstile, [])
    |> Keyword.get(:secret_key)
  end
end
