defmodule LucaGymappWeb.RegistrationController do
  use LucaGymappWeb, :controller

  alias LucaGymapp.Accounts

  def new(conn, _params) do
    form = Phoenix.Component.to_form(%{}, as: :user)
    render(conn, :register, form: form)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        Accounts.deliver_confirmation_instructions(user)

        conn
        |> put_flash(:info, "Sikeres regisztráció. Küldtünk egy megerősítő e-mailt.")
        |> redirect(to: ~p"/")

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

        form = Phoenix.Component.to_form(user_params, as: :user)

        conn
        |> put_flash(:error, error_message)
        |> render(:register, form: form)
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
end
