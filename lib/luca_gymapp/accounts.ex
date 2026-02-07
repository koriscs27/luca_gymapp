defmodule LucaGymapp.Accounts do
  require Logger
  import Ecto.Query, warn: false

  alias LucaGymapp.Repo
  alias LucaGymapp.Accounts.User
  alias LucaGymapp.Accounts.UserEmail
  alias LucaGymapp.Mailer

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

    password_confirmation =
      get_in(attrs, ["password_confirmation"]) || get_in(attrs, [:password_confirmation])

    password_confirmation =
      if is_binary(password_confirmation), do: String.trim(password_confirmation), else: nil

    email = get_in(attrs, ["email"]) || get_in(attrs, [:email])

    attrs =
      attrs
      |> Map.delete("password")
      |> Map.delete(:password)
      |> Map.delete("password_confirmation")
      |> Map.delete(:password_confirmation)
      |> maybe_put_password_hash(password)

    password_present? = is_binary(password) and password != ""

    result =
      cond do
        not password_present? ->
          changeset =
            %User{}
            |> User.changeset(attrs)
            |> Ecto.Changeset.add_error(:password, "A jelszó kötelező.")

          {:error, changeset}

        not password_confirmation_matches?(password, password_confirmation) ->
          changeset =
            %User{}
            |> User.changeset(attrs)
            |> Ecto.Changeset.add_error(:password_confirmation, "Nem egyezik a jelszóval.")

          {:error, changeset}

        true ->
          upsert_unconfirmed_user(email, attrs)
      end

    case result do
      {:ok, user} ->
        {:ok, user}

      {:error, :email_taken} ->
        changeset =
          %User{}
          |> User.changeset(attrs)
          |> Ecto.Changeset.add_error(:email, "mĂˇr regisztrĂˇlva van", constraint: :unique)

        {:error, changeset}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def deliver_confirmation_instructions(%User{} = user) do
    token = generate_token()
    token_hash = token_hash(token)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    user =
      user
      |> Ecto.Changeset.change(%{
        email_confirmation_token_hash: token_hash,
        email_confirmation_sent_at: now
      })
      |> Repo.update!()

    email = UserEmail.confirmation_email(user, token)

    Logger.info("Sending confirmation email",
      user_id: user.id,
      to: user.email,
      subject: email.subject
    )

    case Mailer.deliver(email) do
      {:ok, _} = ok ->
        Logger.info("Confirmation email sent", user_id: user.id, to: user.email)
        ok

      {:error, reason} = error ->
        Logger.error("Confirmation email failed",
          user_id: user.id,
          to: user.email,
          reason: inspect(reason)
        )

        error
    end
  end

  def deliver_confirmation_instructions_for_email(email) when is_binary(email) do
    email = String.trim(email)

    if email != "" do
      case Repo.get_by(User, email: email) do
        %User{email_confirmed_at: nil} = user ->
          deliver_confirmation_instructions(user)

        _ ->
          :ok
      end
    else
      :ok
    end

    :ok
  end

  def deliver_password_reset_instructions(email) when is_binary(email) do
    email = String.trim(email)

    if email != "" do
      case Repo.get_by(User, email: email) do
        %User{} = user ->
          token = generate_token()
          token_hash = token_hash(token)
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          user =
            user
            |> Ecto.Changeset.change(%{
              password_reset_token_hash: token_hash,
              password_reset_sent_at: now
            })
            |> Repo.update!()

          email_message = UserEmail.password_reset_email(user, token)

          Logger.info("Sending password reset email",
            user_id: user.id,
            to: user.email,
            subject: email_message.subject
          )

          case Mailer.deliver(email_message) do
            {:ok, _} = ok ->
              Logger.info("Password reset email sent", user_id: user.id, to: user.email)
              ok

            {:error, reason} = error ->
              Logger.error("Password reset email failed",
                user_id: user.id,
                to: user.email,
                reason: inspect(reason)
              )

              error
          end

        nil ->
          :ok
      end
    else
      :ok
    end

    :ok
  end

  def reset_password_with_token(token, new_password, new_password_confirmation)
      when is_binary(token) do
    case get_user_by_reset_token(token) do
      {:ok, user} ->
        case set_user_password(user, new_password, new_password_confirmation) do
          {:ok, user} ->
            user
            |> Ecto.Changeset.change(%{
              password_reset_token_hash: nil,
              password_reset_sent_at: nil
            })
            |> Repo.update()

          {:error, changeset} ->
            {:error, changeset}
        end

      {:error, :invalid} ->
        {:error, :invalid}
    end
  end

  def password_reset_token_valid?(token) when is_binary(token) do
    case get_user_by_reset_token(token) do
      {:ok, _user} -> true
      {:error, :invalid} -> false
    end
  end

  def confirm_user_email(token) when is_binary(token) do
    token_hash = token_hash(token)

    user =
      from(u in User,
        where: u.email_confirmation_token_hash == ^token_hash,
        where: is_nil(u.email_confirmed_at)
      )
      |> Repo.one()

    cond do
      user == nil ->
        {:error, :invalid}

      confirmation_expired?(user) ->
        {:error, :expired}

      true ->
        user
        |> Ecto.Changeset.change(%{
          email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second),
          email_confirmation_token_hash: nil,
          email_confirmation_sent_at: nil
        })
        |> Repo.update()
    end
  end

  def get_or_create_user_from_oauth(%Ueberauth.Auth{} = auth) do
    email = auth.info.email
    name = oauth_name(auth)

    cond do
      is_nil(email) or email == "" ->
        {:error, :missing_email}

      user = Repo.get_by(User, email: email) ->
        user =
          if email_confirmed?(user) do
            user
          else
            user
            |> Ecto.Changeset.change(%{
              email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second),
              email_confirmation_token_hash: nil,
              email_confirmation_sent_at: nil
            })
            |> Repo.update!()
          end

        {:ok, user}

      true ->
        attrs = %{
          email: email,
          name: name
        }

        %User{}
        |> User.changeset(attrs)
        |> Ecto.Changeset.put_change(
          :email_confirmed_at,
          DateTime.utc_now() |> DateTime.truncate(:second)
        )
        |> Repo.insert()
    end
  end

  def authenticate_user(email, password) when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)

    cond do
      user == nil ->
        :error

      not email_confirmed?(user) ->
        {:error, :unconfirmed}

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

  def set_user_password(%User{} = user, new_password, new_password_confirmation) do
    new_password = if is_binary(new_password), do: String.trim(new_password), else: nil

    new_password_confirmation =
      if is_binary(new_password_confirmation),
        do: String.trim(new_password_confirmation),
        else: nil

    cond do
      not is_binary(new_password) or new_password == "" ->
        changeset =
          user
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.add_error(:new_password, "A jelszó kötelező.")

        {:error, changeset}

      not password_confirmation_matches?(new_password, new_password_confirmation) ->
        changeset =
          user
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.add_error(:new_password_confirmation, "Nem egyezik a jelszóval.")

        {:error, changeset}

      true ->
        user
        |> Ecto.Changeset.change(password_hash: hash_password(new_password))
        |> Repo.update()
    end
  end

  def change_user_password(
        %User{} = user,
        current_password,
        new_password,
        new_password_confirmation
      ) do
    current_password =
      if is_binary(current_password), do: String.trim(current_password), else: nil

    cond do
      is_nil(user.password_hash) ->
        set_user_password(user, new_password, new_password_confirmation)

      not is_binary(current_password) or current_password == "" ->
        changeset =
          user
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.add_error(:current_password, "Add meg a jelenlegi jelszót.")

        {:error, changeset}

      not valid_password?(user, current_password) ->
        changeset =
          user
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.add_error(:current_password, "Hibás jelenlegi jelszó.")

        {:error, changeset}

      true ->
        set_user_password(user, new_password, new_password_confirmation)
    end
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

  defp password_confirmation_matches?(nil, _confirmation), do: false
  defp password_confirmation_matches?("", _confirmation), do: false
  defp password_confirmation_matches?(password, confirmation), do: password == confirmation

  defp upsert_unconfirmed_user(email, attrs) do
    if is_binary(email) do
      case Repo.get_by(User, email: email) do
        %User{email_confirmed_at: nil} = user ->
          user
          |> User.changeset(attrs)
          |> Repo.update()

        %User{} ->
          {:error, :email_taken}

        nil ->
          create_user(attrs)
      end
    else
      create_user(attrs)
    end
  end

  defp email_confirmed?(%User{email_confirmed_at: %DateTime{}}), do: true
  defp email_confirmed?(_user), do: false

  defp generate_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  defp token_hash(token) do
    :crypto.hash(:sha256, token)
  end

  defp confirmation_expired?(%User{email_confirmation_sent_at: nil}), do: true

  defp confirmation_expired?(%User{email_confirmation_sent_at: sent_at}) do
    DateTime.diff(DateTime.utc_now(), sent_at, :second) > 3600
  end

  defp get_user_by_reset_token(token) do
    token_hash = token_hash(token)

    user =
      from(u in User,
        where: u.password_reset_token_hash == ^token_hash
      )
      |> Repo.one()

    cond do
      user == nil ->
        {:error, :invalid}

      reset_token_expired?(user) ->
        {:error, :invalid}

      true ->
        {:ok, user}
    end
  end

  defp reset_token_expired?(%User{password_reset_sent_at: nil}), do: true

  defp reset_token_expired?(%User{password_reset_sent_at: sent_at}) do
    DateTime.diff(DateTime.utc_now(), sent_at, :second) > 3600
  end

  defp oauth_name(%Ueberauth.Auth{info: info}) do
    info.name
    |> name_from_parts(info.first_name, info.last_name)
  end

  defp name_from_parts(nil, first_name, last_name) do
    [first_name, last_name]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp name_from_parts(name, _first_name, _last_name), do: name
end
