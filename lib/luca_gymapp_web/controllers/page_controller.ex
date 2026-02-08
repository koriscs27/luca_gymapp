defmodule LucaGymappWeb.PageController do
  use LucaGymappWeb, :controller

  alias LucaGymapp.Accounts
  alias LucaGymapp.Booking
  alias LucaGymapp.Bookings
  alias LucaGymapp.Payments
  alias LucaGymapp.SeasonPasses
  require Logger

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
         {:ok, booking} <- Bookings.book_personal_training(user, start_dt, end_dt) do
      Logger.info(
        "booking_success type=personal email=#{user.email} name=#{user.name} pass_id=#{booking.pass_id} booking_id=#{booking.id}"
      )

      conn
      |> put_flash(:info, "Sikeres személyi edzés foglalás.")
      |> redirect(to: ~p"/foglalas?type=personal&view=week")
    else
      false ->
        Logger.warning("booking_error_unauthorized type=personal")
        generic_error(conn, ~p"/foglalas?type=personal&view=week")

      {:error, :unauthorized} ->
        Logger.warning("booking_error_unauthorized type=personal")
        generic_error(conn, ~p"/foglalas?type=personal&view=week")

      {:error, :no_valid_pass} ->
        log_booking_error("personal", current_user_id, :no_valid_pass)
        generic_error(conn, ~p"/foglalas?type=personal&view=week")

      {:error, :capacity_reached} ->
        log_booking_error("personal", current_user_id, :capacity_reached)
        generic_error(conn, ~p"/foglalas?type=personal&view=week")

      {:error, %Ecto.Changeset{}} ->
        log_booking_error("personal", current_user_id, :changeset)
        generic_error(conn, ~p"/foglalas?type=personal&view=week")

      {:error, :slot_not_available} ->
        log_booking_error("personal", current_user_id, :slot_not_available)
        generic_error(conn, ~p"/foglalas?type=personal&view=week")

      _ ->
        log_booking_error("personal", current_user_id, :unknown)
        generic_error(conn, ~p"/foglalas?type=personal&view=week")
    end
  end

  def create_cross_booking(conn, %{"start_time" => start_time, "end_time" => end_time}) do
    current_user_id = get_session(conn, :user_id)

    with true <- current_user_id != nil,
         {:ok, user} <- fetch_user(current_user_id),
         {:ok, start_dt, _} <- DateTime.from_iso8601(start_time),
         {:ok, end_dt, _} <- DateTime.from_iso8601(end_time),
         {:ok, booking} <- Bookings.book_cross_training(user, start_dt, end_dt) do
      Logger.info(
        "booking_success type=cross email=#{user.email} name=#{user.name} pass_id=#{booking.pass_id} booking_id=#{booking.id}"
      )

      conn
      |> put_flash(:info, "Sikeres cross edzés foglalás.")
      |> redirect(to: ~p"/foglalas?type=cross&view=week")
    else
      false ->
        Logger.warning("booking_error_unauthorized type=cross")
        generic_error(conn, ~p"/foglalas?type=cross&view=week")

      {:error, :unauthorized} ->
        Logger.warning("booking_error_unauthorized type=cross")
        generic_error(conn, ~p"/foglalas?type=cross&view=week")

      {:error, :no_valid_pass} ->
        log_booking_error("cross", current_user_id, :no_valid_pass)
        generic_error(conn, ~p"/foglalas?type=cross&view=week")

      {:error, :capacity_reached} ->
        log_booking_error("cross", current_user_id, :capacity_reached)
        generic_error(conn, ~p"/foglalas?type=cross&view=week")

      {:error, %Ecto.Changeset{}} ->
        log_booking_error("cross", current_user_id, :changeset)
        generic_error(conn, ~p"/foglalas?type=cross&view=week")

      {:error, :slot_not_available} ->
        log_booking_error("cross", current_user_id, :slot_not_available)
        generic_error(conn, ~p"/foglalas?type=cross&view=week")

      _ ->
        log_booking_error("cross", current_user_id, :unknown)
        generic_error(conn, ~p"/foglalas?type=cross&view=week")
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
        Logger.warning("booking_cancel_error type=personal reason=not_found user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas?type=personal&view=week")

      {:error, :too_late_to_cancel} ->
        Logger.warning("booking_cancel_error type=personal reason=too_late user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas?type=personal&view=week")

      _ ->
        Logger.error("booking_cancel_error type=personal reason=unknown user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas?type=personal&view=week")
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
        Logger.warning("booking_cancel_error type=cross reason=not_found user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas?type=cross&view=week")

      {:error, :too_late_to_cancel} ->
        Logger.warning("booking_cancel_error type=cross reason=too_late user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas?type=cross&view=week")

      _ ->
        Logger.error("booking_cancel_error type=cross reason=unknown user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas?type=cross&view=week")
    end
  end

  defp fetch_user(nil), do: {:error, :unauthorized}
  defp fetch_user(user_id), do: {:ok, Accounts.get_user!(user_id)}

  def purchase_season_pass(conn, %{"pass_name" => pass_name} = params) do
    current_user_id = get_session(conn, :user_id)

    if current_user_id do
      user = Accounts.get_user!(current_user_id)
      payment_method = Map.get(params, "payment_method", "barion")

      case Payments.ensure_payment(%{
             user: user,
             pass_name: pass_name,
             payment_method: payment_method
           }) do
        {:ok, _payment} ->
          case SeasonPasses.purchase_season_pass(user, pass_name) do
            {:ok, pass} ->
              Logger.info(
                "purchase_success email=#{user.email} name=#{user.name} pass_id=#{pass.pass_id} pass_name=#{pass_name}"
              )

              conn
              |> put_flash(:info, "Sikeres foglalás. E-mailt küldtünk a részletekkel.")
              |> redirect(to: ~p"/berletek")

            {:error, :once_per_user} ->
              Logger.warning("purchase_error email=#{user.email} name=#{user.name} reason=once_per_user pass_name=#{pass_name}")
              generic_error(conn, ~p"/berletek")

            {:error, :active_pass_exists} ->
              Logger.warning(
                "purchase_error email=#{user.email} name=#{user.name} reason=active_pass_exists pass_name=#{pass_name}"
              )
              generic_error(conn, ~p"/berletek")

            {:error, :invalid_type} ->
              Logger.warning(
                "purchase_error email=#{user.email} name=#{user.name} reason=invalid_type pass_name=#{pass_name}"
              )
              generic_error(conn, ~p"/berletek")

            {:error, _reason} ->
              Logger.error("purchase_error email=#{user.email} name=#{user.name} reason=unknown pass_name=#{pass_name}")
              generic_error(conn, ~p"/berletek")
          end

        {:error, _reason} ->
          Logger.error("payment_error email=#{user.email} name=#{user.name} pass_name=#{pass_name}")
          generic_error(conn, ~p"/berletek")
      end
    else
      Logger.warning("purchase_error_unauthorized")

      conn
      |> put_flash(:error, "A művelet nem sikerült. Próbáld újra.")
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
        Logger.warning("admin_purchase_error reason=unauthorized admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/berletek")

      {:error, :once_per_user} ->
        Logger.warning("admin_purchase_error reason=once_per_user admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/berletek")

      {:error, :active_pass_exists} ->
        Logger.warning("admin_purchase_error reason=active_pass_exists admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/berletek")

      {:error, :invalid_type} ->
        Logger.warning("admin_purchase_error reason=invalid_type admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/berletek")

      _ ->
        Logger.error("admin_purchase_error reason=unknown admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/berletek")
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
        Logger.warning("admin_publish_error reason=unauthorized admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas")

      _ ->
        Logger.error("admin_publish_error reason=unknown admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas")
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
        Logger.warning("admin_create_slot_error reason=unauthorized admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas")

      {:error, :invalid_time_range} ->
        Logger.warning("admin_create_slot_error reason=invalid_time_range admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas")

      {:error, %Ecto.Changeset{}} ->
        Logger.warning("admin_create_slot_error reason=changeset admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas")

      _ ->
        Logger.error("admin_create_slot_error reason=unknown admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas")
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
        Logger.warning("admin_delete_slot_error reason=unauthorized admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas")

      {:error, :slot_has_bookings} ->
        Logger.warning("admin_delete_slot_error reason=slot_has_bookings admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas?type=#{type}&view=week")

      _ ->
        Logger.error("admin_delete_slot_error reason=unknown admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas?type=#{type}&view=week")
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

  defp generic_error(conn, redirect_path) do
    conn
    |> put_flash(:error, "A művelet nem sikerült. Próbáld újra.")
    |> redirect(to: redirect_path)
  end

  defp log_booking_error(type, user_id, reason) do
    case user_id do
      nil ->
        Logger.warning("booking_error type=#{type} reason=#{reason} user_id=nil")

      id ->
        Logger.warning("booking_error type=#{type} reason=#{reason} user_id=#{id}")
    end
  end
end
