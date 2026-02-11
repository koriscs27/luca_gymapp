defmodule LucaGymapp.SeasonPasses do
  import Ecto.Query, warn: false

  alias LucaGymapp.Accounts
  alias LucaGymapp.Accounts.User
  alias LucaGymapp.Repo
  alias LucaGymapp.SeasonPasses.SeasonPass

  def season_pass_types do
    Application.get_env(:luca_gymapp, :season_pass_types, %{})
  end

  def list_type_definitions do
    season_pass_types()
    |> Enum.map(fn {key, config} ->
      type = Atom.to_string(key)

      %{
        key: key,
        type: type,
        name: humanize_type(type),
        category: category_for_type(type),
        price_huf: Map.fetch!(config, :price_huf),
        occasions: Map.get(config, :occasions, 0),
        once_per_user: Map.get(config, :once_per_user, false)
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  def validate_purchase(%User{} = user, pass_name) do
    with {:ok, type_def} <- fetch_type_definition(pass_name),
         :ok <- enforce_once_per_user(user.id, type_def),
         :ok <- enforce_no_active_pass(user.id, type_def) do
      {:ok, type_def}
    end
  end

  def group_by_category(type_definitions) do
    Enum.group_by(type_definitions, & &1.category)
  end

  def list_recent_passes(user_id, limit \\ 3) do
    SeasonPass
    |> where([pass], pass.user_id == ^user_id)
    |> order_by([pass], desc: pass.purchase_timestamp)
    |> limit(^limit)
    |> Repo.all()
  end

  def list_user_passes(user_id) do
    SeasonPass
    |> where([pass], pass.user_id == ^user_id)
    |> order_by([pass], desc: pass.purchase_timestamp)
    |> Repo.all()
  end

  def latest_pass_by_type(user_id, pass_type) when is_binary(pass_type) do
    SeasonPass
    |> where([pass], pass.user_id == ^user_id)
    |> where([pass], pass.pass_type == ^pass_type)
    |> order_by([pass], desc: pass.purchase_timestamp)
    |> limit(1)
    |> Repo.one()
  end

  def latest_passes_by_type(user_id) do
    %{
      personal: latest_pass_by_type(user_id, "personal"),
      cross: latest_pass_by_type(user_id, "cross"),
      other: latest_pass_by_type(user_id, "other")
    }
  end

  def purchase_season_pass(%User{} = user, pass_name) do
    Repo.transaction(fn ->
      with {:ok, type_def} <- fetch_type_definition(pass_name),
           :ok <- enforce_once_per_user(user.id, type_def),
           :ok <- enforce_no_active_pass(user.id, type_def) do
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        expiry_date = now |> DateTime.add(60 * 24 * 60 * 60, :second) |> DateTime.to_date()

        attrs = %{
          pass_id: Ecto.UUID.generate(),
          pass_name: type_def.type,
          pass_type: pass_type_for_category(type_def.category),
          occasions: type_def.occasions,
          purchase_timestamp: now,
          purchase_price: type_def.price_huf,
          expiry_date: expiry_date,
          user_id: user.id
        }

        %SeasonPass{}
        |> SeasonPass.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, pass} ->
            _ = Accounts.deliver_season_pass_details(user, pass)
            pass

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, pass} -> {:ok, pass}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_type_definition(pass_name) when is_binary(pass_name) do
    type = String.trim(pass_name)

    list_type_definitions()
    |> Enum.find(fn item -> item.type == type end)
    |> case do
      nil -> {:error, :invalid_type}
      type_def -> {:ok, type_def}
    end
  end

  defp fetch_type_definition(pass_name) when is_atom(pass_name) do
    pass_name
    |> Atom.to_string()
    |> fetch_type_definition()
  end

  defp enforce_once_per_user(user_id, %{once_per_user: true, type: type}) do
    exists? =
      SeasonPass
      |> where([pass], pass.user_id == ^user_id)
      |> where([pass], pass.pass_name == ^type)
      |> Repo.exists?()

    if exists? do
      {:error, :once_per_user}
    else
      :ok
    end
  end

  defp enforce_once_per_user(_user_id, _type_def), do: :ok

  defp enforce_no_active_pass(user_id, %{category: category}) do
    pass_type = pass_type_for_category(category)

    if pass_type in ["personal", "cross"] do
      today = Date.utc_today()

      active_exists? =
        SeasonPass
        |> where([pass], pass.user_id == ^user_id)
        |> where([pass], pass.occasions > 0)
        |> where([pass], pass.expiry_date >= ^today)
        |> lock("FOR UPDATE")
        |> Repo.all()
        |> Enum.any?(&same_category_active_pass?(&1, category, pass_type))

      if active_exists? do
        {:error, :active_pass_exists}
      else
        :ok
      end
    else
      :ok
    end
  end

  defp same_category_active_pass?(%SeasonPass{} = pass, category, pass_type) do
    pass.pass_type == pass_type or category_for_type(pass.pass_name) == category
  end

  defp category_for_type(type) do
    cond do
      String.contains?(type, "cross") -> :cross
      String.contains?(type, "alkalmas") -> :szemelyi_edzes
      true -> :egyeb
    end
  end

  defp pass_type_for_category(category) do
    case category do
      :cross -> "cross"
      :szemelyi_edzes -> "personal"
      _ -> "other"
    end
  end

  defp humanize_type(type) do
    type
    |> String.replace("_", " ")
    |> String.replace_prefix("cross ", "Cross ")
    |> String.trim()
    |> String.capitalize()
  end
end
