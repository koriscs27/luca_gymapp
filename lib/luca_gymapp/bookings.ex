defmodule LucaGymapp.Bookings do
  import Ecto.Query, warn: false

  alias LucaGymapp.Accounts.User
  alias LucaGymapp.Bookings.CrossBooking
  alias LucaGymapp.Bookings.PersonalBooking
  alias LucaGymapp.Repo
  alias LucaGymapp.SeasonPasses.SeasonPass

  def book_personal_training(%User{} = user, %DateTime{} = start_time, %DateTime{} = end_time) do
    Repo.transaction(fn ->
      pass = get_valid_personal_pass!(user.id)
      booking = create_personal_booking!(user, pass, start_time, end_time)
      decrement_pass_occasions!(pass)
      booking
    end)
  end

  def book_cross_training(%User{} = user, %DateTime{} = start_time, %DateTime{} = end_time) do
    Repo.transaction(fn ->
      pass = get_valid_cross_pass!(user.id)
      enforce_cross_capacity!(start_time, end_time)
      booking = create_cross_booking!(user, pass, start_time, end_time)
      decrement_pass_occasions!(pass)
      booking
    end)
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

      enforce_cancellation_window!(booking.start_time)

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

      enforce_cancellation_window!(booking.start_time)

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
    max_overlap =
      Application.get_env(:luca_gymapp, :booking_schedule, %{})
      |> Map.get(:cross, %{})
      |> Map.get(:max_overlap, 0)

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

  defp enforce_cancellation_window!(%DateTime{} = start_time) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    seconds_until_start = DateTime.diff(start_time, now, :second)

    if seconds_until_start < 12 * 60 * 60 do
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
