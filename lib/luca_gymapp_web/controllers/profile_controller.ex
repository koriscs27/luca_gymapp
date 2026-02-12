defmodule LucaGymappWeb.ProfileController do
  use LucaGymappWeb, :controller

  alias LucaGymapp.Accounts
  require Logger

  plug :require_user

  def show(conn, _params) do
    user = current_user(conn)
    profile_form = user |> Accounts.change_user() |> Phoenix.Component.to_form()
    password_form = Phoenix.Component.to_form(%{}, as: :password)

    render(conn, :profile, build_profile_assigns(user, profile_form, password_form))
  end

  def update_profile(conn, %{"user" => user_params}) do
    user = current_user(conn)
    attrs = Map.take(user_params, ["name", "phone_number", "age", "sex", "birth_date"])

    case Accounts.update_user(user, attrs) do
      {:ok, user} ->
        Logger.info(
          "profile_update_success user_id=#{user.id} email=#{user.email} name=#{user.name} fields=#{Enum.join(Map.keys(attrs), ",")}"
        )

        profile_form = user |> Accounts.change_user() |> Phoenix.Component.to_form()
        password_form = Phoenix.Component.to_form(%{}, as: :password)

        conn
        |> put_flash(:info, "Profil frissítve.")
        |> render(:profile, build_profile_assigns(user, profile_form, password_form))

      {:error, changeset} ->
        Logger.warning(
          "profile_update_error user_id=#{user.id} email=#{user.email} name=#{user.name} fields=#{Enum.join(Map.keys(attrs), ",")}"
        )

        password_form = Phoenix.Component.to_form(%{}, as: :password)

        conn
        |> put_flash(:error, "Nem sikerült frissíteni a profilt.")
        |> render(
          :profile,
          build_profile_assigns(user, Phoenix.Component.to_form(changeset), password_form)
        )
    end
  end

  def update_password(conn, %{"password" => password_params}) do
    user = current_user(conn)
    current_password = Map.get(password_params, "current_password")
    new_password = Map.get(password_params, "new_password")
    new_password_confirmation = Map.get(password_params, "new_password_confirmation")

    result =
      if is_nil(user.password_hash) do
        Accounts.set_user_password(user, new_password, new_password_confirmation)
      else
        Accounts.change_user_password(
          user,
          current_password,
          new_password,
          new_password_confirmation
        )
      end

    case result do
      {:ok, user} ->
        Logger.info(
          "password_update_success user_id=#{user.id} email=#{user.email} name=#{user.name}"
        )

        profile_form = user |> Accounts.change_user() |> Phoenix.Component.to_form()
        password_form = Phoenix.Component.to_form(%{}, as: :password)

        conn
        |> put_flash(:info, "Jelszó frissítve.")
        |> render(:profile, build_profile_assigns(user, profile_form, password_form))

      {:error, changeset} ->
        Logger.warning(
          "password_update_error user_id=#{user.id} email=#{user.email} name=#{user.name}"
        )

        profile_form = user |> Accounts.change_user() |> Phoenix.Component.to_form()

        conn
        |> put_flash(:error, "Nem sikerült frissíteni a jelszót.")
        |> render(
          :profile,
          build_profile_assigns(
            user,
            profile_form,
            Phoenix.Component.to_form(changeset, as: :password)
          )
        )
    end
  end

  def update_password(conn, _params) do
    conn
    |> put_flash(:error, "Nem sikerült frissíteni a jelszót.")
    |> redirect(to: ~p"/profile")
  end

  defp require_user(conn, _opts) do
    case get_session(conn, :user_id) do
      nil ->
        conn
        |> put_flash(:error, "Jelentkezz be a profil megtekintéséhez.")
        |> redirect(to: "/#login-modal")
        |> halt()

      user_id ->
        case Accounts.get_user(user_id) do
          nil ->
            conn
            |> delete_session(:user_id)
            |> put_flash(:error, "A munkamenet lejárt. Jelentkezz be újra.")
            |> redirect(to: "/#login-modal")
            |> halt()

          user ->
            assign(conn, :current_user, user)
        end
    end
  end

  defp current_user(conn), do: conn.assigns.current_user

  defp build_profile_assigns(user, profile_form, password_form) do
    %{
      user: user,
      profile_form: profile_form,
      password_form: password_form
    }
  end
end
