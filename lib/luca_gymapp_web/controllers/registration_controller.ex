defmodule LucaGymappWeb.RegistrationController do
  use LucaGymappWeb, :controller

  alias LucaGymapp.Accounts

  def new(conn, _params) do
    form = Phoenix.Component.to_form(%{}, as: :user)
    render(conn, :register, form: form)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Sikeres regisztráció.")
        |> redirect(to: ~p"/")

      {:error, _changeset} ->
        form = Phoenix.Component.to_form(user_params, as: :user)

        conn
        |> put_flash(:error, "A regisztráció sikertelen. Ellenőrizd az adatokat.")
        |> render(:register, form: form)
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "A regisztráció sikertelen. Ellenőrizd az adatokat.")
    |> redirect(to: ~p"/register")
  end
end
