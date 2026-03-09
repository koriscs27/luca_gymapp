defmodule LucaGymapp.SeasonPasses do
  import Ecto.Query, warn: false

  alias LucaGymapp.Accounts.User
  alias LucaGymapp.Repo
  alias LucaGymapp.SeasonPasses.SeasonPass

  @token_replacements %{
    "berlet" => "bérlet",
    "kezdo" => "kezdő",
    "honapos" => "hónapos",
    "etrend" => "étrend",
    "paros" => "páros"
  }

  def season_pass_types do
    Application.get_env(:luca_gymapp, :season_pass_types, %{})
  end

  def display_name(type) when is_atom(type) do
    type
    |> Atom.to_string()
    |> display_name()
  end

  def display_name(type) when is_binary(type) do
    normalized_type = String.trim(type)

    case normalized_type do
      "" ->
        "-"

      _ ->
        normalized_type
        |> String.split("_", trim: true)
        |> Enum.map(&replace_token/1)
        |> Enum.join(" ")
        |> maybe_capitalize()
    end
  end

  def display_name(_), do: "-"

  def list_type_definitions do
    season_pass_types()
    |> Enum.map(fn {key, config} ->
      type = Atom.to_string(key)
      category = definition_category(type, config)
      booking_pass_type = definition_booking_pass_type(type, config, category)

      %{
        key: key,
        type: type,
        name: display_name(type),
        category: category,
        booking_pass_type: booking_pass_type,
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

  def list_recent_user_passes(user_id, limit \\ 20) do
    SeasonPass
    |> where([pass], pass.user_id == ^user_id)
    |> order_by([pass], desc: pass.purchase_timestamp)
    |> limit(^limit)
    |> Repo.all()
  end

  def latest_pass_by_type(user_id, pass_type) when is_binary(pass_type) do
    today = Date.utc_today()

    SeasonPass
    |> where([pass], pass.user_id == ^user_id)
    |> where([pass], pass.pass_type == ^pass_type)
    |> where([pass], pass.expiry_date >= ^today)
    |> where([pass], pass.pass_type == "other" or pass.occasions > 0)
    |> order_by([pass], desc: pass.purchase_timestamp)
    |> limit(1)
    |> Repo.one()
  end

  def active_passes_by_type(user_id, pass_type) when is_binary(pass_type) do
    today = Date.utc_today()

    SeasonPass
    |> where([pass], pass.user_id == ^user_id)
    |> where([pass], pass.pass_type == ^pass_type)
    |> where([pass], pass.expiry_date >= ^today)
    |> where([pass], pass.occasions > 0)
    |> order_by([pass], desc: pass.purchase_timestamp)
    |> Repo.all()
  end

  def active_passes_for_booking_type(user_id, "personal") do
    active_passes_by_types(user_id, ["personal", "paros"])
  end

  def active_passes_for_booking_type(user_id, pass_type) when is_binary(pass_type) do
    active_passes_by_types(user_id, [pass_type])
  end

  def latest_passes_by_type(user_id) do
    %{
      personal: latest_pass_by_type(user_id, "personal"),
      paros: latest_pass_by_type(user_id, "paros"),
      cross: latest_pass_by_type(user_id, "cross"),
      other: latest_pass_by_type(user_id, "other")
    }
  end

  def purchase_season_pass(%User{} = user, pass_name, opts \\ []) do
    Repo.transaction(fn ->
      with {:ok, type_def} <- fetch_type_definition(pass_name),
           :ok <- enforce_once_per_user(user.id, type_def),
           :ok <- enforce_no_active_pass(user.id, type_def) do
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        expiry_date = now |> DateTime.to_date() |> add_months(3)
        payment_id = Keyword.get(opts, :payment_id)
        payment_method = Keyword.get(opts, :payment_method, "cash")

        attrs = %{
          pass_id: Ecto.UUID.generate(),
          pass_name: type_def.type,
          pass_type: type_def.booking_pass_type,
          payment_id: payment_id,
          payment_method: payment_method,
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
          {:ok, pass} -> pass
          {:error, changeset} -> Repo.rollback(changeset)
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

  defp enforce_no_active_pass(user_id, %{booking_pass_type: pass_type}) do
    if pass_type in ["personal", "cross", "paros"] do
      today = Date.utc_today()

      active_exists? =
        SeasonPass
        |> where([pass], pass.user_id == ^user_id)
        |> where(^active_pass_type_filter(pass_type))
        |> where([pass], pass.occasions > 0)
        |> where([pass], pass.expiry_date >= ^today)
        |> lock("FOR UPDATE")
        |> Repo.exists?()

      if active_exists? do
        {:error, :active_pass_exists}
      else
        :ok
      end
    else
      :ok
    end
  end

  defp active_passes_by_types(user_id, pass_types) when is_list(pass_types) do
    today = Date.utc_today()

    SeasonPass
    |> where([pass], pass.user_id == ^user_id)
    |> where([pass], pass.pass_type in ^pass_types)
    |> where([pass], pass.expiry_date >= ^today)
    |> where([pass], pass.occasions > 0)
    |> order_by([pass], desc: pass.purchase_timestamp)
    |> Repo.all()
  end

  defp definition_category(type, config) do
    case Map.get(config, :display_category) do
      value when value in [:cross, :szemelyi_edzes, :egyeb] ->
        value

      _ ->
        inferred_category_for_type(type)
    end
  end

  defp definition_booking_pass_type(type, config, category) do
    case Map.get(config, :booking_pass_type) do
      value when value in ["cross", "personal", "paros", "other"] ->
        value

      _ ->
        inferred_booking_pass_type(type, category)
    end
  end

  defp inferred_category_for_type(type) do
    cond do
      String.contains?(type, "cross") -> :cross
      String.contains?(type, "paros") -> :szemelyi_edzes
      String.contains?(type, "alkalmas") -> :szemelyi_edzes
      true -> :egyeb
    end
  end

  defp inferred_booking_pass_type(type, category) do
    cond do
      String.contains?(type, "cross") -> "cross"
      String.contains?(type, "paros") -> "paros"
      category == :szemelyi_edzes -> "personal"
      true -> "other"
    end
  end

  defp active_pass_type_filter("cross") do
    dynamic([pass], pass.pass_type == "cross" or like(pass.pass_type, "cross_%"))
  end

  defp active_pass_type_filter(pass_type) when is_binary(pass_type) do
    dynamic([pass], pass.pass_type == ^pass_type)
  end

  defp add_months(%Date{} = date, months) when is_integer(months) and months >= 0 do
    month_index = date.month - 1 + months
    year = date.year + div(month_index, 12)
    month = rem(month_index, 12) + 1
    day = min(date.day, Calendar.ISO.days_in_month(year, month))

    Date.new!(year, month, day)
  end

  defp replace_token("cross"), do: "Cross"

  defp replace_token(token) do
    Map.get(@token_replacements, token, token)
  end

  defp maybe_capitalize(""), do: "-"

  defp maybe_capitalize(value) do
    if String.match?(value, ~r/^[[:digit:]]/u) do
      value
    else
      String.capitalize(value)
    end
  end
end
