defmodule LucaGymappWeb.PasswordResetController do
  use LucaGymappWeb, :controller

  alias LucaGymapp.Accounts
  alias LucaGymapp.Security.RateLimiter

  def new(conn, _params) do
    form = Phoenix.Component.to_form(%{"email" => ""}, as: :password_reset)
    render(conn, :new, form: form)
  end

  def create(conn, %{"password_reset" => %{"email" => email}}) do
    case RateLimiter.allow_request(conn, :password_reset_request, email: email) do
      :ok ->
        Accounts.deliver_password_reset_instructions(email)

        conn
        |> put_flash(:info, "Ha létezik fiók, e-mailt küldtünk erre a címre: #{email}")
        |> redirect(to: ~p"/password/forgot")

      {:error, :rate_limited} ->
        conn
        |> put_flash(:error, RateLimiter.rate_limited_message())
        |> redirect(to: ~p"/password/forgot")
    end
  end

  def create(conn, _params) do
    case RateLimiter.allow_request(conn, :password_reset_request) do
      :ok ->
        conn
        |> put_flash(:info, "Ha létezik fiók, e-mailt küldtünk a megadott címre.")
        |> redirect(to: ~p"/password/forgot")

      {:error, :rate_limited} ->
        conn
        |> put_flash(:error, RateLimiter.rate_limited_message())
        |> redirect(to: ~p"/password/forgot")
    end
  end

  def edit(conn, %{"token" => token}) do
    if Accounts.password_reset_token_valid?(token) do
      form = Phoenix.Component.to_form(%{}, as: :password_reset)
      render(conn, :edit, form: form, token: token)
    else
      conn
      |> put_flash(:error, "A link érvénytelen vagy lejárt.")
      |> redirect(to: ~p"/password/forgot")
    end
  end

  def edit(conn, _params) do
    conn
    |> put_flash(:error, "A link érvénytelen vagy lejárt.")
    |> redirect(to: ~p"/password/forgot")
  end

  def update(conn, %{"password_reset" => params}) do
    token = Map.get(params, "token", "")
    new_password = Map.get(params, "new_password")
    new_password_confirmation = Map.get(params, "new_password_confirmation")

    case Accounts.reset_password_with_token(token, new_password, new_password_confirmation) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "A jelszó frissítve. Jelentkezz be az új jelszóval.")
        |> redirect(to: "/#login-modal")

      {:error, :invalid} ->
        conn
        |> put_flash(:error, "A link érvénytelen vagy lejárt.")
        |> redirect(to: ~p"/password/forgot")

      {:error, changeset} ->
        form = Phoenix.Component.to_form(changeset, as: :password_reset)

        conn
        |> put_flash(:error, "Nem sikerült frissíteni a jelszót.")
        |> render(:edit, form: form, token: token)
    end
  end

  def update(conn, _params) do
    conn
    |> put_flash(:error, "Nem sikerült frissíteni a jelszót.")
    |> redirect(to: ~p"/password/forgot")
  end
end
