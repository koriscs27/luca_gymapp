defmodule LucaGymapp.Bookings.AdminDraftStore do
  use GenServer

  alias LucaGymapp.Bookings.CalendarSlot

  @type slot_key :: String.t()

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state), do: {:ok, state}

  def list(admin_id, type) when is_integer(admin_id) do
    GenServer.call(__MODULE__, {:list, admin_id, normalize_type(type)})
  end

  def add_slots(admin_id, type, slots) when is_integer(admin_id) and is_list(slots) do
    GenServer.call(__MODULE__, {:add_slots, admin_id, normalize_type(type), slots})
  end

  def add_slot(admin_id, type, %CalendarSlot{} = slot) when is_integer(admin_id) do
    add_slots(admin_id, type, [slot])
  end

  def remove_draft_slot(admin_id, type, slot_key)
      when is_integer(admin_id) and is_binary(slot_key) do
    GenServer.call(__MODULE__, {:remove_draft, admin_id, normalize_type(type), slot_key})
  end

  def mark_delete(admin_id, type, slot_id, slot_key \\ nil)
      when is_integer(admin_id) and is_integer(slot_id) do
    GenServer.call(__MODULE__, {:mark_delete, admin_id, normalize_type(type), slot_id, slot_key})
  end

  def clear(admin_id, type) when is_integer(admin_id) do
    GenServer.call(__MODULE__, {:clear, admin_id, normalize_type(type)})
  end

  def slot_key(%CalendarSlot{} = slot) do
    slot_key(slot.start_time, slot.end_time)
  end

  def slot_key(%DateTime{} = start_time, %DateTime{} = end_time) do
    DateTime.to_iso8601(start_time) <> "|" <> DateTime.to_iso8601(end_time)
  end

  @impl true
  def handle_call({:list, admin_id, type}, _from, state) do
    {:reply, get_type_state(state, admin_id, type), state}
  end

  @impl true
  def handle_call({:add_slots, admin_id, type, slots}, _from, state) do
    type_state = get_type_state(state, admin_id, type)

    updated_adds =
      Enum.reduce(slots, type_state.adds, fn slot, acc ->
        Map.put(acc, slot_key(slot), slot)
      end)

    updated_state =
      put_type_state(state, admin_id, type, %{type_state | adds: updated_adds})

    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call({:remove_draft, admin_id, type, slot_key}, _from, state) do
    type_state = get_type_state(state, admin_id, type)
    updated_adds = Map.delete(type_state.adds, slot_key)
    updated_state = put_type_state(state, admin_id, type, %{type_state | adds: updated_adds})
    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call({:mark_delete, admin_id, type, slot_id, slot_key}, _from, state) do
    type_state = get_type_state(state, admin_id, type)
    updated_adds = if slot_key, do: Map.delete(type_state.adds, slot_key), else: type_state.adds
    updated_deletes = MapSet.put(type_state.deletes, slot_id)

    updated_state =
      put_type_state(state, admin_id, type, %{
        type_state
        | adds: updated_adds,
          deletes: updated_deletes
      })

    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call({:clear, admin_id, type}, _from, state) do
    updated_state = put_type_state(state, admin_id, type, empty_type_state())
    {:reply, :ok, updated_state}
  end

  defp get_type_state(state, admin_id, type) do
    state
    |> Map.get(admin_id, %{})
    |> Map.get(type, empty_type_state())
    |> normalize_type_state()
  end

  defp put_type_state(state, admin_id, type, type_state) do
    admin_state = Map.get(state, admin_id, %{})
    Map.put(state, admin_id, Map.put(admin_state, type, normalize_type_state(type_state)))
  end

  defp empty_type_state do
    %{adds: %{}, deletes: MapSet.new()}
  end

  defp normalize_type_state(type_state) do
    %{
      adds: Map.get(type_state, :adds, %{}),
      deletes: Map.get(type_state, :deletes, MapSet.new())
    }
  end

  defp normalize_type(type) when is_atom(type), do: type

  defp normalize_type(type) when is_binary(type) do
    case type do
      "personal" -> :personal
      "cross" -> :cross
      _ -> :personal
    end
  end
end
