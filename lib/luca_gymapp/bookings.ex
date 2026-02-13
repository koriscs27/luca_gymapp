defmodule LucaGymapp.Bookings do
  import Ecto.Query, warn: false

  alias LucaGymapp.Accounts.User
  alias LucaGymapp.Booking
  alias LucaGymapp.Bookings.CalendarSlot
  alias LucaGymapp.Bookings.CrossBooking
  alias LucaGymapp.Bookings.PersonalBooking
  alias LucaGymapp.Notifications
  alias LucaGymapp.Repo
  alias LucaGymapp.SeasonPasses.SeasonPass

  def book_personal_training(%User{} = user, %DateTime{} = start_time, %DateTime{} = end_time) do
    Repo.transaction(fn ->
      enforce_booking_window!(:personal, start_time, end_time)
      enforce_slot_exists!("personal", start_time, end_time)
      lock_personal_bookings_table!()
      pass = get_valid_personal_pass!(user.id)
      booking = create_personal_booking!(user, pass, start_time, end_time)
      decrement_pass_occasions!(pass)
      booking
    end)
    |> case do
      {:ok, booking} = ok ->
        _ = Notifications.deliver_booking_notification(user, :personal, booking)
        ok

      {:error, _} = error ->
        error
    end
  end

  def book_cross_training(%User{} = user, %DateTime{} = start_time, %DateTime{} = end_time) do
    Repo.transaction(fn ->
      enforce_booking_window!(:cross, start_time, end_time)
      enforce_slot_exists!("cross", start_time, end_time)
      pass = get_valid_cross_pass!(user.id)
      enforce_cross_capacity!(start_time, end_time)
      booking = create_cross_booking!(user, pass, start_time, end_time)
      decrement_pass_occasions!(pass)
      booking
    end)
    |> case do
      {:ok, booking} = ok ->
        _ = Notifications.deliver_booking_notification(user, :cross, booking)
        ok

      {:error, _} = error ->
        error
    end
  end

  def list_personal_booked_slot_keys(user_id) do
    PersonalBooking
    |> where([booking], booking.user_id == ^user_id)
    |> where([booking], booking.status == "booked")
    |> select([booking], {booking.start_time, booking.end_time})
    |> Repo.all()
    |> slot_keys_from_ranges()
  end

  def list_cross_booked_slot_keys(user_id) do
    CrossBooking
    |> where([booking], booking.user_id == ^user_id)
    |> where([booking], booking.status == "booked")
    |> select([booking], {booking.start_time, booking.end_time})
    |> Repo.all()
    |> slot_keys_from_ranges()
  end

  def list_cross_full_slot_keys(%Date{} = week_start, %Date{} = week_end) do
    max_overlap = Application.get_env(:luca_gymapp, :cross_max_overlap, 8)

    if max_overlap <= 0 do
      MapSet.new()
    else
      week_start_dt = DateTime.new!(week_start, ~T[00:00:00], "Etc/UTC")
      week_end_dt = DateTime.new!(Date.add(week_end, 1), ~T[00:00:00], "Etc/UTC")

      CrossBooking
      |> where([booking], booking.status == "booked")
      |> where([booking], booking.start_time >= ^week_start_dt)
      |> where([booking], booking.start_time < ^week_end_dt)
      |> group_by([booking], [booking.start_time, booking.end_time])
      |> having([booking], count(booking.id) >= ^max_overlap)
      |> select([booking], {booking.start_time, booking.end_time})
      |> Repo.all()
      |> slot_keys_from_ranges()
    end
  end

  def list_personal_taken_slot_keys(%Date{} = week_start, %Date{} = week_end) do
    week_start_dt = DateTime.new!(week_start, ~T[00:00:00], "Etc/UTC")
    week_end_dt = DateTime.new!(Date.add(week_end, 1), ~T[00:00:00], "Etc/UTC")

    PersonalBooking
    |> where([booking], booking.status == "booked")
    |> where([booking], booking.start_time >= ^week_start_dt)
    |> where([booking], booking.start_time < ^week_end_dt)
    |> select([booking], {booking.start_time, booking.end_time})
    |> Repo.all()
    |> slot_keys_from_ranges()
  end

  def list_user_appointments(user_id) do
    personal =
      PersonalBooking
      |> where([booking], booking.user_id == ^user_id)
      |> where([booking], booking.status == "booked")
      |> select([booking], %{type: "personal", start_time: booking.start_time})
      |> Repo.all()

    cross =
      CrossBooking
      |> where([booking], booking.user_id == ^user_id)
      |> where([booking], booking.status == "booked")
      |> select([booking], %{type: "cross", start_time: booking.start_time})
      |> Repo.all()

    (personal ++ cross)
    |> Enum.sort_by(& &1.start_time, {:desc, DateTime})
  end

  def cancel_personal_booking(%User{} = user, %DateTime{} = start_time, %DateTime{} = end_time) do
    Repo.transaction(fn ->
      booking =
        PersonalBooking
        |> where([booking], booking.user_id == ^user.id)
        |> where([booking], booking.status == "booked")
        |> where([booking], booking.start_time == ^start_time)
        |> where([booking], booking.end_time == ^end_time)
        |> lock("FOR UPDATE")
        |> Repo.one()
        |> case do
          nil -> Repo.rollback(:not_found)
          booking -> booking
        end

      enforce_cancellation_window!(:personal, booking.start_time)

      booking =
        booking
        |> Ecto.Changeset.change(status: "cancelled")
        |> Repo.update()
        |> case do
          {:ok, booking} -> booking
          {:error, changeset} -> Repo.rollback(changeset)
        end

      increment_pass_occasions!(booking.pass_id)
      booking
    end)
    |> case do
      {:ok, booking} = ok ->
        _ = Notifications.deliver_booking_cancellation_notification(user, :personal, booking)
        ok

      {:error, _} = error ->
        error
    end
  end

  def cancel_cross_booking(%User{} = user, %DateTime{} = start_time, %DateTime{} = end_time) do
    Repo.transaction(fn ->
      booking =
        CrossBooking
        |> where([booking], booking.user_id == ^user.id)
        |> where([booking], booking.status == "booked")
        |> where([booking], booking.start_time == ^start_time)
        |> where([booking], booking.end_time == ^end_time)
        |> lock("FOR UPDATE")
        |> Repo.one()
        |> case do
          nil -> Repo.rollback(:not_found)
          booking -> booking
        end

      enforce_cancellation_window!(:cross, booking.start_time)

      booking =
        booking
        |> Ecto.Changeset.change(status: "cancelled")
        |> Repo.update()
        |> case do
          {:ok, booking} -> booking
          {:error, changeset} -> Repo.rollback(changeset)
        end

      increment_pass_occasions!(booking.pass_id)
      booking
    end)
    |> case do
      {:ok, booking} = ok ->
        _ = Notifications.deliver_booking_cancellation_notification(user, :cross, booking)
        ok

      {:error, _} = error ->
        error
    end
  end

  def list_calendar_slots_for_week(type, %Date{} = week_start, %Date{} = week_end) do
    slot_type = slot_type_from_booking(type)
    week_start_dt = DateTime.new!(week_start, ~T[00:00:00], "Etc/UTC")
    week_end_dt = DateTime.new!(Date.add(week_end, 1), ~T[00:00:00], "Etc/UTC")

    CalendarSlot
    |> where([slot], slot.slot_type == ^slot_type)
    |> where([slot], slot.start_time >= ^week_start_dt)
    |> where([slot], slot.start_time < ^week_end_dt)
    |> order_by([slot], asc: slot.start_time)
    |> Repo.all()
  end

  def list_bookings_for_week(type, %Date{} = week_start, %Date{} = week_end) do
    week_start_dt = DateTime.new!(week_start, ~T[00:00:00], "Etc/UTC")
    week_end_dt = DateTime.new!(Date.add(week_end, 1), ~T[00:00:00], "Etc/UTC")

    case slot_type_from_booking(type) do
      "personal" ->
        PersonalBooking
        |> where([booking], booking.status == "booked")
        |> where([booking], booking.start_time >= ^week_start_dt)
        |> where([booking], booking.start_time < ^week_end_dt)
        |> preload(:user)
        |> order_by([booking], asc: booking.start_time)
        |> Repo.all()

      "cross" ->
        CrossBooking
        |> where([booking], booking.status == "booked")
        |> where([booking], booking.start_time >= ^week_start_dt)
        |> where([booking], booking.start_time < ^week_end_dt)
        |> preload(:user)
        |> order_by([booking], asc: booking.start_time)
        |> Repo.all()
    end
  end

  def publish_default_week(type, %Date{} = week_start) do
    schedule = Booking.schedule_for(type)
    {monday, _week_end} = Booking.week_range(week_start)
    days = Booking.ordered_days(schedule.availability, monday)
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_naive()
    slot_type = slot_type_from_booking(type)

    slots =
      days
      |> Enum.flat_map(fn day ->
        Enum.map(day.hour_slots, fn slot ->
          %{
            slot_type: slot_type,
            start_time: slot.start_datetime,
            end_time: slot.end_datetime,
            inserted_at: now,
            updated_at: now
          }
        end)
      end)

    Repo.insert_all(CalendarSlot, slots,
      on_conflict: :nothing,
      conflict_target: [:slot_type, :start_time, :end_time]
    )
  end

  def build_default_week_slots(type, %Date{} = week_start) do
    schedule = Booking.schedule_for(type)
    {monday, _week_end} = Booking.week_range(week_start)
    days = Booking.ordered_days(schedule.availability, monday)
    slot_type = slot_type_from_booking(type)

    days
    |> Enum.flat_map(fn day ->
      Enum.map(day.hour_slots, fn slot ->
        %CalendarSlot{
          slot_type: slot_type,
          start_time: slot.start_datetime,
          end_time: slot.end_datetime
        }
      end)
    end)
  end

  def insert_calendar_slots(slots) when is_list(slots) do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_naive()

    attrs =
      Enum.map(slots, fn slot ->
        %{
          slot_type: slot.slot_type,
          start_time: slot.start_time,
          end_time: slot.end_time,
          inserted_at: now,
          updated_at: now
        }
      end)

    if attrs == [] do
      {0, nil}
    else
      Repo.insert_all(CalendarSlot, attrs,
        on_conflict: :nothing,
        conflict_target: [:slot_type, :start_time, :end_time]
      )
    end
  end

  def apply_admin_draft_changes(additions, deletions) when is_list(additions) do
    Repo.transaction(fn ->
      Enum.each(deletions, fn slot_id ->
        case delete_calendar_slot(slot_id) do
          {:ok, _slot} -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

      _ = insert_calendar_slots(additions)
      :ok
    end)
  end

  def create_calendar_slot(type, %Date{} = date, %Time{} = start_time, %Time{} = end_time) do
    slot_type = slot_type_from_booking(type)
    start_dt = DateTime.new!(date, start_time, "Etc/UTC")
    end_dt = DateTime.new!(date, end_time, "Etc/UTC")

    if DateTime.compare(end_dt, start_dt) != :gt do
      {:error, :invalid_time_range}
    else
      %CalendarSlot{}
      |> CalendarSlot.changeset(%{
        slot_type: slot_type,
        start_time: start_dt,
        end_time: end_dt
      })
      |> Repo.insert()
      |> case do
        {:ok, slot} -> {:ok, slot}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  def delete_calendar_slot(slot_id) do
    slot =
      CalendarSlot
      |> where([slot], slot.id == ^slot_id)
      |> Repo.one()
      |> case do
        nil -> {:error, :not_found}
        slot -> {:ok, slot}
      end

    with {:ok, slot} <- slot,
         :ok <- ensure_slot_has_no_bookings(slot) do
      Repo.delete(slot)
    end
  end

  defp slot_type_from_booking(:personal), do: "personal"
  defp slot_type_from_booking(:cross), do: "cross"
  defp slot_type_from_booking(value) when is_binary(value), do: value

  defp enforce_slot_exists!(slot_type, %DateTime{} = start_time, %DateTime{} = end_time) do
    exists? =
      CalendarSlot
      |> where([slot], slot.slot_type == ^slot_type)
      |> where([slot], slot.start_time == ^start_time)
      |> where([slot], slot.end_time == ^end_time)
      |> Repo.exists?()

    if exists? do
      :ok
    else
      Repo.rollback(:slot_not_available)
    end
  end

  defp ensure_slot_has_no_bookings(%CalendarSlot{} = slot) do
    case slot.slot_type do
      "personal" ->
        exists? =
          PersonalBooking
          |> where([booking], booking.status == "booked")
          |> where([booking], booking.start_time == ^slot.start_time)
          |> where([booking], booking.end_time == ^slot.end_time)
          |> Repo.exists?()

        if exists?, do: {:error, :slot_has_bookings}, else: :ok

      "cross" ->
        exists? =
          CrossBooking
          |> where([booking], booking.status == "booked")
          |> where([booking], booking.start_time == ^slot.start_time)
          |> where([booking], booking.end_time == ^slot.end_time)
          |> Repo.exists?()

        if exists?, do: {:error, :slot_has_bookings}, else: :ok

      _ ->
        :ok
    end
  end

  defp lock_personal_bookings_table! do
    case Repo.query("LOCK TABLE personal_bookings IN ACCESS EXCLUSIVE MODE") do
      {:ok, _result} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp get_valid_personal_pass!(user_id) do
    today = Date.utc_today()

    SeasonPass
    |> where([pass], pass.user_id == ^user_id)
    |> where([pass], pass.pass_type == "personal")
    |> where([pass], pass.occasions > 0)
    |> where([pass], pass.expiry_date >= ^today)
    |> order_by([pass], asc: pass.expiry_date, asc: pass.purchase_timestamp)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil -> Repo.rollback(:no_valid_pass)
      pass -> pass
    end
  end

  defp get_valid_cross_pass!(user_id) do
    today = Date.utc_today()

    SeasonPass
    |> where([pass], pass.user_id == ^user_id)
    |> where([pass], pass.pass_type == "cross")
    |> where([pass], pass.occasions > 0)
    |> where([pass], pass.expiry_date >= ^today)
    |> order_by([pass], asc: pass.expiry_date, asc: pass.purchase_timestamp)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil -> Repo.rollback(:no_valid_pass)
      pass -> pass
    end
  end

  defp create_personal_booking!(%User{} = user, %SeasonPass{} = pass, start_time, end_time) do
    attrs = %{
      user_name: user.name || user.email,
      start_time: start_time,
      end_time: end_time,
      booking_timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
      status: "booked",
      pass_id: pass.pass_id
    }

    %PersonalBooking{}
    |> PersonalBooking.changeset(attrs)
    |> Ecto.Changeset.put_change(:user_id, user.id)
    |> Repo.insert()
    |> case do
      {:ok, booking} -> booking
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp create_cross_booking!(%User{} = user, %SeasonPass{} = pass, start_time, end_time) do
    attrs = %{
      user_name: user.name || user.email,
      start_time: start_time,
      end_time: end_time,
      booking_timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
      status: "booked",
      pass_id: pass.pass_id
    }

    %CrossBooking{}
    |> CrossBooking.changeset(attrs)
    |> Ecto.Changeset.put_change(:user_id, user.id)
    |> Repo.insert()
    |> case do
      {:ok, booking} -> booking
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp enforce_cross_capacity!(%DateTime{} = start_time, %DateTime{} = end_time) do
    max_overlap = Application.get_env(:luca_gymapp, :cross_max_overlap, 8)

    count =
      CrossBooking
      |> where([booking], booking.status == "booked")
      |> where(
        [booking],
        fragment(
          "tsrange(?, ?, '[)') && tsrange(?, ?, '[)')",
          booking.start_time,
          booking.end_time,
          ^start_time,
          ^end_time
        )
      )
      |> select([booking], booking.id)
      |> lock("FOR UPDATE")
      |> Repo.all()
      |> length()

    if count >= max_overlap do
      Repo.rollback(:capacity_reached)
    else
      :ok
    end
  end

  defp decrement_pass_occasions!(%SeasonPass{} = pass) do
    pass
    |> Ecto.Changeset.change(occasions: pass.occasions - 1)
    |> Repo.update()
    |> case do
      {:ok, _pass} -> :ok
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp enforce_booking_window!(:personal, %DateTime{} = start_time, %DateTime{} = _end_time) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    seconds_until_start = DateTime.diff(start_time, now, :second)

    cond do
      seconds_until_start <= 0 ->
        Repo.rollback(:booking_closed)

      seconds_until_start < 6 * 60 * 60 ->
        Repo.rollback(:too_early_to_book)

      true ->
        :ok
    end
  end

  defp enforce_booking_window!(:cross, %DateTime{} = _start_time, %DateTime{} = end_time) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    if DateTime.compare(end_time, now) == :gt do
      :ok
    else
      Repo.rollback(:booking_closed)
    end
  end

  defp enforce_cancellation_window!(:personal, %DateTime{} = start_time) do
    enforce_cancellation_window_seconds!(start_time, 6 * 60 * 60)
  end

  defp enforce_cancellation_window!(:cross, %DateTime{} = start_time) do
    enforce_cancellation_window_seconds!(start_time, 1 * 60 * 60)
  end

  defp enforce_cancellation_window_seconds!(%DateTime{} = start_time, required_seconds) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    seconds_until_start = DateTime.diff(start_time, now, :second)

    if seconds_until_start < required_seconds do
      Repo.rollback(:too_late_to_cancel)
    end

    :ok
  end

  defp slot_keys_from_ranges(ranges) do
    ranges
    |> Enum.map(fn {start_time, end_time} ->
      DateTime.to_iso8601(start_time) <> "|" <> DateTime.to_iso8601(end_time)
    end)
    |> MapSet.new()
  end

  defp increment_pass_occasions!(pass_id) when is_binary(pass_id) do
    pass =
      SeasonPass
      |> where([pass], pass.pass_id == ^pass_id)
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> case do
        nil -> Repo.rollback(:pass_not_found)
        pass -> pass
      end

    pass
    |> Ecto.Changeset.change(occasions: pass.occasions + 1)
    |> Repo.update()
    |> case do
      {:ok, _pass} -> :ok
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end
end
