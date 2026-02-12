defmodule LucaGymapp.BookingsTest do
  use LucaGymapp.DataCase

  alias LucaGymapp.Accounts
  alias LucaGymapp.Bookings
  alias LucaGymapp.Bookings.CalendarSlot
  alias LucaGymapp.Repo
  alias LucaGymapp.SeasonPasses.SeasonPass

  test "overlapping personal bookings: 15 concurrent rounds allow only 1 success and no extra deduction" do
    user = create_user()

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    base_time = DateTime.add(now, 2 * 60 * 60, :second)
    step_seconds = 30 * 60

    parent = self()

    Enum.each(0..14, fn round ->
      pass = create_personal_pass(user, 1)
      start_time = DateTime.add(base_time, round * step_seconds, :second)
      end_time = DateTime.add(start_time, 30 * 60, :second)
      :ok = ensure_slot("personal", start_time, end_time)

      results =
        1..3
        |> Enum.map(fn _ ->
          Task.async(fn ->
            Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), parent)
            Bookings.book_personal_training(user, start_time, end_time)
          end)
        end)
        |> Enum.map(&Task.await/1)

      success_count = Enum.count(results, &match?({:ok, _}, &1))
      error_count = Enum.count(results, &match?({:error, _}, &1))

      assert success_count == 1
      assert error_count == 2

      pass = Repo.get_by!(SeasonPass, pass_id: pass.pass_id)
      assert pass.occasions == 0
    end)
  end

  test "personal booking fails with wrong pass type" do
    user = create_user()
    _pass = create_pass(user, "cross", 2, Date.add(Date.utc_today(), 30))

    start_time =
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(60 * 60, :second)

    end_time = DateTime.add(start_time, 60 * 60, :second)
    :ok = ensure_slot("personal", start_time, end_time)

    assert {:error, :no_valid_pass} = Bookings.book_personal_training(user, start_time, end_time)
  end

  test "personal booking fails with no occasions left" do
    user = create_user()
    _pass = create_pass(user, "personal", 0, Date.add(Date.utc_today(), 30))

    start_time =
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(60 * 60, :second)

    end_time = DateTime.add(start_time, 60 * 60, :second)
    :ok = ensure_slot("personal", start_time, end_time)

    assert {:error, :no_valid_pass} = Bookings.book_personal_training(user, start_time, end_time)
  end

  test "personal booking fails with expired pass" do
    user = create_user()
    _pass = create_pass(user, "personal", 2, Date.add(Date.utc_today(), -1))

    start_time =
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(60 * 60, :second)

    end_time = DateTime.add(start_time, 60 * 60, :second)
    :ok = ensure_slot("personal", start_time, end_time)

    assert {:error, :no_valid_pass} = Bookings.book_personal_training(user, start_time, end_time)
  end

  test "cross booking fails with wrong pass type" do
    user = create_user()
    _pass = create_pass(user, "personal", 2, Date.add(Date.utc_today(), 30))

    start_time =
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(60 * 60, :second)

    end_time = DateTime.add(start_time, 60 * 60, :second)
    :ok = ensure_slot("cross", start_time, end_time)

    assert {:error, :no_valid_pass} = Bookings.book_cross_training(user, start_time, end_time)
  end

  test "cross booking fails with no occasions left" do
    user = create_user()
    _pass = create_pass(user, "cross", 0, Date.add(Date.utc_today(), 30))

    start_time =
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(60 * 60, :second)

    end_time = DateTime.add(start_time, 60 * 60, :second)
    :ok = ensure_slot("cross", start_time, end_time)

    assert {:error, :no_valid_pass} = Bookings.book_cross_training(user, start_time, end_time)
  end

  test "cross booking fails with expired pass" do
    user = create_user()
    _pass = create_pass(user, "cross", 2, Date.add(Date.utc_today(), -1))

    start_time =
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(60 * 60, :second)

    end_time = DateTime.add(start_time, 60 * 60, :second)
    :ok = ensure_slot("cross", start_time, end_time)

    assert {:error, :no_valid_pass} = Bookings.book_cross_training(user, start_time, end_time)
  end

  test "cross bookings reject when max overlap exceeded" do
    start_time =
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(60 * 60, :second)

    end_time = DateTime.add(start_time, 60 * 60, :second)
    :ok = ensure_slot("cross", start_time, end_time)

    users =
      1..10
      |> Enum.map(fn _ -> create_user() end)

    passes =
      Enum.map(users, fn user ->
        create_pass(user, "cross", 1, Date.add(Date.utc_today(), 30))
      end)

    results =
      Enum.map(users, fn user ->
        Bookings.book_cross_training(user, start_time, end_time)
      end)

    success_count = Enum.count(results, &match?({:ok, _}, &1))
    error_count = Enum.count(results, &match?({:error, :capacity_reached}, &1))

    assert success_count == 8
    assert error_count == 2

    remaining_occasions =
      Enum.map(passes, fn pass ->
        pass = Repo.get_by!(SeasonPass, pass_id: pass.pass_id)
        pass.occasions
      end)

    assert Enum.count(remaining_occasions, &(&1 == 0)) == 8
    assert Enum.count(remaining_occasions, &(&1 == 1)) == 2
  end

  defp create_user do
    email = "booking-user-#{System.unique_integer([:positive])}@example.com"
    {:ok, user} = Accounts.create_user(%{email: email, name: "Booking User"})
    user
  end

  defp create_personal_pass(user, occasions) do
    create_pass(user, "personal", occasions, Date.add(Date.utc_today(), 30))
  end

  defp create_pass(user, pass_type, occasions, expiry_date) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %SeasonPass{}
    |> Ecto.Changeset.change(%{
      pass_id: Ecto.UUID.generate(),
      pass_name: "test_pass_#{pass_type}",
      pass_type: pass_type,
      occasions: occasions,
      purchase_timestamp: now,
      purchase_price: 45_000,
      expiry_date: expiry_date,
      user_id: user.id
    })
    |> Repo.insert!()
  end

  defp ensure_slot(type, %DateTime{} = start_time, %DateTime{} = end_time) do
    slot = %CalendarSlot{slot_type: type, start_time: start_time, end_time: end_time}

    case Bookings.insert_calendar_slots([slot]) do
      {0, _} -> :ok
      {_count, _} -> :ok
    end
  end
end
