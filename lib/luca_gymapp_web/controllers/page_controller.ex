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
    current_user = if current_user_id, do: Accounts.get_user!(current_user_id), else: nil
    is_admin = current_user && current_user.admin
    season_passes = SeasonPasses.list_type_definitions()
    season_pass_categories = SeasonPasses.group_by_category(season_passes)

    recent_passes =
      if current_user_id do
        SeasonPasses.latest_passes_by_type(current_user_id)
      else
        %{personal: nil, cross: nil, other: nil}
      end

    admin_users =
      if is_admin do
        Accounts.list_users_for_admin_select()
      else
        []
      end

    admin_pass_options = Enum.map(season_passes, fn pass -> {pass.name, pass.type} end)
    admin_form = Phoenix.Component.to_form(%{}, as: :admin_purchase)

    render(conn, :berletek,
      form: form,
      current_user: current_user_id,
      current_user_is_admin: is_admin,
      season_pass_categories: season_pass_categories,
      recent_passes: recent_passes,
      admin_users: admin_users,
      admin_pass_options: admin_pass_options,
      admin_form: admin_form
    )
  end

  def booking(conn, params) do
    current_user_id = get_session(conn, :user_id)
    current_user = if current_user_id, do: Accounts.get_user!(current_user_id), else: nil
    is_admin = current_user && current_user.admin

    type =
      case params["type"] do
        "cross" -> :cross
        _ -> :personal
      end

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

    slots = Bookings.list_calendar_slots_for_week(type, week_start, week_end)
    ordered_days = Booking.ordered_days_from_slots(slots, week_start)

    booked_slot_keys =
      if current_user_id do
        case type do
          :personal -> Bookings.list_personal_booked_slot_keys(current_user_id)
          :cross -> Bookings.list_cross_booked_slot_keys(current_user_id)
        end
      else
        MapSet.new()
      end

    admin_slot_form = Phoenix.Component.to_form(%{}, as: :admin_slot)
    admin_publish_form = Phoenix.Component.to_form(%{}, as: :admin_publish)
    admin_delete_form = Phoenix.Component.to_form(%{}, as: :admin_delete)

    current_pass =
      if current_user_id do
        case type do
          :personal -> SeasonPasses.latest_pass_by_type(current_user_id, "personal")
          :cross -> SeasonPasses.latest_pass_by_type(current_user_id, "cross")
        end
      end

    render(conn, :booking,
      current_user: current_user_id,
      current_user_is_admin: is_admin,
      booking_type: type,
      booking_view: view,
      booking_days: ordered_days,
      booking_availability: %{},
      booked_slot_keys: booked_slot_keys,
      week_offset: week_offset,
      week_start: week_start,
      week_end: week_end,
      admin_slot_form: admin_slot_form,
      admin_publish_form: admin_publish_form,
      admin_delete_form: admin_delete_form,
      current_pass: current_pass
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

      {:error, :slot_not_available} ->
        conn
        |> put_flash(:error, "Ez az időpont már nem elérhető.")
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

      {:error, :slot_not_available} ->
        conn
        |> put_flash(:error, "Ez az időpont már nem elérhető.")
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

  def admin_purchase_season_pass(
        conn,
        %{"admin_purchase" => %{"user_id" => user_id, "pass_name" => pass_name}}
      ) do
    current_user_id = get_session(conn, :user_id)

    with true <- current_user_id != nil,
         {:ok, admin_user} <- fetch_user(current_user_id),
         true <- admin_user.admin,
         target_user <- Accounts.get_user!(user_id),
         {:ok, _pass} <- SeasonPasses.purchase_season_pass(target_user, pass_name) do
      conn
      |> put_flash(:info, "A bérlet sikeresen létrejött a kiválasztott felhasználónak.")
      |> redirect(to: ~p"/berletek")
    else
      false ->
        conn
        |> put_flash(:error, "Nincs jogosultságod ehhez a művelethez.")
        |> redirect(to: ~p"/berletek")

      {:error, :once_per_user} ->
        conn
        |> put_flash(:error, "Ez a bérlet csak egyszer vásárolható meg.")
        |> redirect(to: ~p"/berletek")

      {:error, :active_pass_exists} ->
        conn
        |> put_flash(
          :error,
          "A felhasználónak már van aktív bérlete ebből a típusból."
        )
        |> redirect(to: ~p"/berletek")

      {:error, :invalid_type} ->
        conn
        |> put_flash(:error, "Ismeretlen bérlet típus.")
        |> redirect(to: ~p"/berletek")

      _ ->
        conn
        |> put_flash(:error, "Nem sikerült a bérletet létrehozni.")
        |> redirect(to: ~p"/berletek")
    end
  end

  def admin_publish_week(conn, %{"admin_publish" => %{"type" => type, "week_start" => week_start}}) do
    current_user_id = get_session(conn, :user_id)

    with true <- current_user_id != nil,
         {:ok, admin_user} <- fetch_user(current_user_id),
         true <- admin_user.admin,
         {:ok, date} <- Date.from_iso8601(week_start),
         {type, _} <- parse_booking_type(type) do
      _ = Bookings.publish_default_week(type, date)

      conn
      |> put_flash(:info, "Az alapértelmezett heti naptár feltöltve.")
      |> redirect(to: ~p"/foglalas?type=#{type}&view=week&week=#{week_offset_from_date(date)}")
    else
      false ->
        conn
        |> put_flash(:error, "Nincs jogosultságod ehhez a művelethez.")
        |> redirect(to: ~p"/foglalas")

      _ ->
        conn
        |> put_flash(:error, "Nem sikerült feltölteni a heti naptárat.")
        |> redirect(to: ~p"/foglalas")
    end
  end

  def admin_create_slot(conn, %{
        "admin_slot" => %{
          "type" => type,
          "date" => date,
          "start_time" => start_time,
          "end_time" => end_time
        }
      }) do
    current_user_id = get_session(conn, :user_id)

    with true <- current_user_id != nil,
         {:ok, admin_user} <- fetch_user(current_user_id),
         true <- admin_user.admin,
         {type, _} <- parse_booking_type(type),
         {:ok, date} <- Date.from_iso8601(date),
         {:ok, start_time} <- parse_time_param(start_time),
         {:ok, end_time} <- parse_time_param(end_time),
         {:ok, _slot} <- Bookings.create_calendar_slot(type, date, start_time, end_time) do
      conn
      |> put_flash(:info, "Időpont hozzáadva.")
      |> redirect(to: ~p"/foglalas?type=#{type}&view=week&week=#{week_offset_from_date(date)}")
    else
      false ->
        conn
        |> put_flash(:error, "Nincs jogosultságod ehhez a művelethez.")
        |> redirect(to: ~p"/foglalas")

      {:error, :invalid_time_range} ->
        conn
        |> put_flash(:error, "Az időpont tartománya érvénytelen.")
        |> redirect(to: ~p"/foglalas")

      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_flash(:error, "Ez az időpont már létezik.")
        |> redirect(to: ~p"/foglalas")

      _ ->
        conn
        |> put_flash(:error, "Nem sikerült létrehozni az időpontot.")
        |> redirect(to: ~p"/foglalas")
    end
  end

  def admin_delete_slot(conn, %{"admin_delete" => %{"slot_id" => slot_id, "type" => type}}) do
    current_user_id = get_session(conn, :user_id)

    with true <- current_user_id != nil,
         {:ok, admin_user} <- fetch_user(current_user_id),
         true <- admin_user.admin,
         {type, _} <- parse_booking_type(type),
         {slot_id, _} <- Integer.parse(slot_id),
         {:ok, _slot} <- Bookings.delete_calendar_slot(slot_id) do
      conn
      |> put_flash(:info, "Időpont törölve.")
      |> redirect(to: ~p"/foglalas?type=#{type}&view=week")
    else
      false ->
        conn
        |> put_flash(:error, "Nincs jogosultságod ehhez a művelethez.")
        |> redirect(to: ~p"/foglalas")

      {:error, :slot_has_bookings} ->
        conn
        |> put_flash(:error, "Nem törölhető, mert már van foglalás ezen az időponton.")
        |> redirect(to: ~p"/foglalas?type=#{type}&view=week")

      _ ->
        conn
        |> put_flash(:error, "Nem sikerült törölni az időpontot.")
        |> redirect(to: ~p"/foglalas?type=#{type}&view=week")
    end
  end

  defp parse_booking_type("cross"), do: {:cross, :cross}
  defp parse_booking_type(_), do: {:personal, :personal}

  defp week_offset_from_date(%Date{} = date) do
    today = Date.utc_today()
    diff = Date.diff(date, today)
    div(diff, 7)
  end

  defp parse_time_param(value) when is_binary(value) do
    value =
      case String.length(value) do
        5 -> value <> ":00"
        _ -> value
      end

    Time.from_iso8601(value)
  end
end
