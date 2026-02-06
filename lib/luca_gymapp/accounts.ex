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

  def register_user(attrs) when is_map(attrs) do
    password = get_in(attrs, ["password"]) || get_in(attrs, [:password])
    password = if is_binary(password), do: String.trim(password), else: nil

    attrs =
      attrs
      |> Map.delete("password")
      |> Map.delete(:password)
      |> maybe_put_password_hash(password)

    create_user(attrs)
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

  defp maybe_put_password_hash(attrs, password) do
    key = if has_string_keys?(attrs), do: "password_hash", else: :password_hash
    Map.put(attrs, key, password_hash_or_nil(password))
  end

  defp password_hash_or_nil(nil), do: nil
  defp password_hash_or_nil(""), do: nil
  defp password_hash_or_nil(password), do: hash_password(password)

  defp has_string_keys?(attrs) do
    attrs
    |> Map.keys()
    |> Enum.any?(&is_binary/1)
  end
end
