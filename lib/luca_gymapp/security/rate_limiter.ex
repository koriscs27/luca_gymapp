defmodule LucaGymapp.Security.RateLimiter do
  @moduledoc false

  @table :luca_gymapp_rate_limiter
  @default_limit 30
  @default_window_seconds 300

  def allow_request(conn, action, opts \\ []) when is_atom(action) do
    ensure_table!()

    limit = Keyword.get(opts, :limit, configured_limit())
    window_seconds = Keyword.get(opts, :window_seconds, configured_window_seconds())
    email = Keyword.get(opts, :email)
    ip = ip_to_string(conn.remote_ip)
    bucket = div(System.system_time(:second), window_seconds)

    keys =
      [{"ip", ip}]
      |> maybe_add_email(email)
      |> Enum.map(fn {scope, value} -> {action, scope, value, bucket} end)

    if Enum.any?(keys, &(counter_value(&1) >= limit)) do
      {:error, :rate_limited}
    else
      Enum.each(keys, &increment_counter/1)
      :ok
    end
  end

  def rate_limited_message do
    "Túl sok próbálkozás történt. Kérlek, próbáld újra 5 perc múlva."
  end

  def reset! do
    ensure_table!()
    :ets.delete_all_objects(@table)
    :ok
  end

  defp configured_limit do
    Application.get_env(:luca_gymapp, :rate_limit, [])
    |> Keyword.get(:limit, @default_limit)
  end

  defp configured_window_seconds do
    Application.get_env(:luca_gymapp, :rate_limit, [])
    |> Keyword.get(:window_seconds, @default_window_seconds)
  end

  defp maybe_add_email(scopes, email) when is_binary(email) do
    normalized = email |> String.trim() |> String.downcase()
    if normalized == "", do: scopes, else: [{"email", normalized} | scopes]
  end

  defp maybe_add_email(scopes, _email), do: scopes

  defp ip_to_string({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp ip_to_string(other), do: to_string(:inet.ntoa(other))

  defp increment_counter(key) do
    :ets.update_counter(@table, key, {2, 1}, {key, 0})
  end

  defp counter_value(key) do
    case :ets.lookup(@table, key) do
      [{^key, value}] when is_integer(value) -> value
      _ -> 0
    end
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
        rescue
          ArgumentError -> :ok
        end

      _ ->
        :ok
    end
  end
end
