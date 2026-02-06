defmodule LucaGymapp.Accounts do
  import Ecto.Query, warn: false

  alias LucaGymapp.Repo
  alias LucaGymapp.Accounts.User

  def list_users do
    Repo.all(User)
  end

  def get_user!(id), do: Repo.get!(User, id)

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def authenticate_user(email, password) when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)

    cond do
      user == nil ->
        :error

      valid_password?(user, password) ->
        {:ok, user}

      true ->
        :error
    end
  end

  def authenticate_user(_, _), do: :error

  def hash_password(password) when is_binary(password) do
    :crypto.hash(:sha256, password)
    |> Base.encode16(case: :lower)
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  defp valid_password?(%User{password_hash: nil}, _password), do: false

  defp valid_password?(%User{password_hash: password_hash}, password) do
    password_hash
    |> Plug.Crypto.secure_compare(hash_password(password))
  end
end
