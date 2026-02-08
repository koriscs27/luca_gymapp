defmodule LucaGymappWeb.PageController do
  use LucaGymappWeb, :controller

  alias LucaGymapp.Accounts
  alias LucaGymapp.Booking
  alias LucaGymapp.Bookings
  alias LucaGymapp.SeasonPasses

  def home(conn, _params) do
    form = Phoenix.Component.to_form(%{"email" => "", "password" => ""}, as: :user)
    render(conn, :home, form: form, current_user: get_session(conn, :user_id))
  end

  def berletek(conn, _params) do
    form = Phoenix.Component.to_form(%{"email" => "", "password" => ""}, as: :user)
    current_user_id = get_session(conn, :user_id)
    season_passes = SeasonPasses.list_type_definitions()
    season_pass_categories = SeasonPasses.group_by_category(season_passes)

    recent_passes =
      if current_user_id do
        SeasonPasses.list_recent_passes(current_user_id, 3)
      else
        []
      end

    render(conn, :berletek,
      form: form,
      current_user: current_user_id,
      season_pass_categories: season_pass_categories,
      recent_passes: recent_passes
    )
  end

  def booking(conn, params) do
    current_user_id = get_session(conn, :user_id)

    type =
      case params["type"] do
        "cross" -> :cross
        _ -> :personal
      end

    schedule = Booking.schedule_for(type)

    view = :week

    week_offset =
      case params["week"] do
        value when is_binary(value) ->
          case Integer.parse(value) do
            {int, _} -> int
            :error -> 0
          end

        _ ->
          0
      end

    base_date = Date.add(Date.utc_today(), week_offset * 7)
    {week_start, week_end} = Booking.week_range(base_date)

    ordered_days = Booking.ordered_days(schedule.availability, base_date)

    booked_slot_keys =
      if current_user_id do
        case type do
          :personal -> Bookings.list_personal_booked_slot_keys(current_user_id)
          :cross -> Bookings.list_cross_booked_slot_keys(current_user_id)
        end
      else
        MapSet.new()
      end

    render(conn, :booking,
      current_user: current_user_id,
      booking_type: type,
      booking_view: view,
      booking_days: ordered_days,
      booking_availability: schedule.availability,
      booked_slot_keys: booked_slot_keys,
      week_offset: week_offset,
      week_start: week_start,
      week_end: week_end
    )
  end

  def create_personal_booking(conn, %{"start_time" => start_time, "end_time" => end_time}) do
    current_user_id = get_session(conn, :user_id)

    with true <- current_user_id != nil,
         {:ok, user} <- fetch_user(current_user_id),
         {:ok, start_dt, _} <- DateTime.from_iso8601(start_time),
         {:ok, end_dt, _} <- DateTime.from_iso8601(end_time),
         {:ok, _booking} <- Bookings.book_personal_training(user, start_dt, end_dt) do
      conn
      |> put_flash(:info, "Sikeres személyi edzés foglalás.")
      |> redirect(to: ~p"/foglalas?type=personal&view=week")
    else
      {:error, :no_valid_pass} ->
        conn
        |> put_flash(:error, "Nincs érvényes személyi bérleted ehhez a foglaláshoz.")
        |> redirect(to: ~p"/foglalas?type=personal&view=week")

      {:error, :capacity_reached} ->
        conn
        |> put_flash(:error, "Ez az időpont már tele van.")
        |> redirect(to: ~p"/foglalas?type=personal&view=week")

      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_flash(:error, "Ez az időpont már foglalt.")
        |> redirect(to: ~p"/foglalas?type=personal&view=week")

      _ ->
        conn
        |> put_flash(:error, "A foglalás nem sikerült.")
        |> redirect(to: ~p"/foglalas?type=personal&view=week")
    end
  end

  def create_cross_booking(conn, %{"start_time" => start_time, "end_time" => end_time}) do
    current_user_id = get_session(conn, :user_id)

    with true <- current_user_id != nil,
         {:ok, user} <- fetch_user(current_user_id),
         {:ok, start_dt, _} <- DateTime.from_iso8601(start_time),
         {:ok, end_dt, _} <- DateTime.from_iso8601(end_time),
         {:ok, _booking} <- Bookings.book_cross_training(user, start_dt, end_dt) do
      conn
      |> put_flash(:info, "Sikeres cross edzés foglalás.")
      |> redirect(to: ~p"/foglalas?type=cross&view=week")
    else
      {:error, :no_valid_pass} ->
        conn
        |> put_flash(:error, "Nincs érvényes cross bérleted ehhez a foglaláshoz.")
        |> redirect(to: ~p"/foglalas?type=cross&view=week")

      {:error, :capacity_reached} ->
        conn
        |> put_flash(:error, "Ez az időpont már tele van.")
        |> redirect(to: ~p"/foglalas?type=cross&view=week")

      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_flash(:error, "Ez az időpont már foglalt.")
        |> redirect(to: ~p"/foglalas?type=cross&view=week")

      _ ->
        conn
        |> put_flash(:error, "A foglalás nem sikerült.")
        |> redirect(to: ~p"/foglalas?type=cross&view=week")
    end
  end

  def cancel_personal_booking(conn, %{"start_time" => start_time, "end_time" => end_time}) do
    current_user_id = get_session(conn, :user_id)

    with true <- current_user_id != nil,
         {:ok, user} <- fetch_user(current_user_id),
         {:ok, start_dt, _} <- DateTime.from_iso8601(start_time),
         {:ok, end_dt, _} <- DateTime.from_iso8601(end_time),
         {:ok, _booking} <- Bookings.cancel_personal_booking(user, start_dt, end_dt) do
      conn
      |> put_flash(:info, "A személyi edzés foglalás törölve lett.")
      |> redirect(to: ~p"/foglalas?type=personal&view=week")
    else
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Nem található ilyen foglalás.")
        |> redirect(to: ~p"/foglalas?type=personal&view=week")

      {:error, :too_late_to_cancel} ->
        conn
        |> put_flash(:error, "A foglalás csak legkésőbb 12 órával kezdés előtt mondható le.")
        |> redirect(to: ~p"/foglalas?type=personal&view=week")

      _ ->
        conn
        |> put_flash(:error, "A foglalás törlése nem sikerült.")
        |> redirect(to: ~p"/foglalas?type=personal&view=week")
    end
  end

  def cancel_cross_booking(conn, %{"start_time" => start_time, "end_time" => end_time}) do
    current_user_id = get_session(conn, :user_id)

    with true <- current_user_id != nil,
         {:ok, user} <- fetch_user(current_user_id),
         {:ok, start_dt, _} <- DateTime.from_iso8601(start_time),
         {:ok, end_dt, _} <- DateTime.from_iso8601(end_time),
         {:ok, _booking} <- Bookings.cancel_cross_booking(user, start_dt, end_dt) do
      conn
      |> put_flash(:info, "A cross edzés foglalás törölve lett.")
      |> redirect(to: ~p"/foglalas?type=cross&view=week")
    else
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Nem található ilyen foglalás.")
        |> redirect(to: ~p"/foglalas?type=cross&view=week")

      {:error, :too_late_to_cancel} ->
        conn
        |> put_flash(:error, "A foglalás csak legkésőbb 12 órával kezdés előtt mondható le.")
        |> redirect(to: ~p"/foglalas?type=cross&view=week")

      _ ->
        conn
        |> put_flash(:error, "A foglalás törlése nem sikerült.")
        |> redirect(to: ~p"/foglalas?type=cross&view=week")
    end
  end

  defp fetch_user(nil), do: {:error, :unauthorized}
  defp fetch_user(user_id), do: {:ok, Accounts.get_user!(user_id)}

  def purchase_season_pass(conn, %{"pass_name" => pass_name}) do
    current_user_id = get_session(conn, :user_id)

    if current_user_id do
      user = Accounts.get_user!(current_user_id)

      case SeasonPasses.purchase_season_pass(user, pass_name) do
        {:ok, _pass} ->
          conn
          |> put_flash(:info, "Sikeres foglalás. E-mailt küldtünk a részletekkel.")
          |> redirect(to: ~p"/berletek")

        {:error, :once_per_user} ->
          conn
          |> put_flash(:error, "Ez a bérlet csak egyszer vásárolható meg.")
          |> redirect(to: ~p"/berletek")

        {:error, :active_pass_exists} ->
          conn
          |> put_flash(
            :error,
            "Már van aktív bérleted ebből a típusból. Előbb használd fel vagy várd meg a lejáratot."
          )
          |> redirect(to: ~p"/berletek")

        {:error, :invalid_type} ->
          conn
          |> put_flash(:error, "Ismeretlen bérlet típus.")
          |> redirect(to: ~p"/berletek")

        {:error, _reason} ->
          conn
          |> put_flash(:error, "Nem sikerült a bérletet létrehozni.")
          |> redirect(to: ~p"/berletek")
      end
    else
      conn
      |> put_flash(:error, "A vásárláshoz be kell jelentkezned.")
      |> redirect(to: ~p"/berletek")
    end
  end
end
