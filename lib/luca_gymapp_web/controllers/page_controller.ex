defmodule LucaGymappWeb.PageController do
  use LucaGymappWeb, :controller

  alias LucaGymapp.Accounts
  alias LucaGymapp.Booking
  alias LucaGymapp.Bookings
  alias LucaGymapp.Notifications
  alias LucaGymapp.Payments
  alias LucaGymapp.SeasonPasses
  require Logger

  def home(conn, _params) do
    form = Phoenix.Component.to_form(%{"email" => "", "password" => ""}, as: :user)
    {conn, current_user} = current_user_from_session(conn)
    current_user_is_admin = current_user && current_user.admin

    render(conn, :home,
      form: form,
      current_user: current_user,
      current_user_is_admin: current_user_is_admin
    )
  end

  def rolam(conn, _params) do
    {conn, current_user} = current_user_from_session(conn)
    current_user_is_admin = !!(current_user && current_user.admin)

    render(conn, :rolam,
      current_user: current_user,
      current_user_is_admin: current_user_is_admin
    )
  end

  def berletek(conn, _params) do
    form = Phoenix.Component.to_form(%{"email" => "", "password" => ""}, as: :user)
    {conn, current_user} = current_user_from_session(conn)
    current_user_id = current_user && current_user.id
    is_admin = !!(current_user && current_user.admin)
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
    {conn, current_user} = current_user_from_session(conn)
    current_user_id = current_user && current_user.id
    is_admin = !!(current_user && current_user.admin)

    type =
      case params["type"] do
        "cross" -> :cross
        _ -> :personal
      end

    view = :week

    today = Date.utc_today()
    week_offset = params["week"] |> parse_week_offset() |> normalize_week_offset(is_admin)
    base_date = Date.add(today, week_offset * 7)
    {week_start, week_end} = Booking.week_range(base_date)

    slots = Bookings.list_calendar_slots_for_week(type, week_start, week_end)

    {slots, draft_add_keys, draft_change_count} =
      if is_admin && current_user_id do
        draft = Bookings.AdminDraftStore.list(current_user_id, type)
        filtered_slots = Enum.reject(slots, &MapSet.member?(draft.deletes, &1.id))

        week_start_dt = DateTime.new!(week_start, ~T[00:00:00], "Etc/UTC")
        week_end_dt = DateTime.new!(Date.add(week_end, 1), ~T[00:00:00], "Etc/UTC")

        existing_keys =
          filtered_slots
          |> Enum.map(&slot_key_from_slot/1)
          |> MapSet.new()

        draft_adds =
          draft.adds
          |> Map.values()
          |> Enum.filter(fn slot ->
            DateTime.compare(slot.start_time, week_start_dt) != :lt and
              DateTime.compare(slot.start_time, week_end_dt) == :lt
          end)
          |> Enum.reject(fn slot -> MapSet.member?(existing_keys, slot_key_from_slot(slot)) end)

        draft_keys =
          draft_adds
          |> Enum.map(&slot_key_from_slot/1)
          |> MapSet.new()

        changes_count = map_size(draft.adds) + MapSet.size(draft.deletes)

        {filtered_slots ++ draft_adds, draft_keys, changes_count}
      else
        {slots, MapSet.new(), 0}
      end

    ordered_days =
      slots
      |> Booking.ordered_days_from_slots(week_start)
      |> filter_visible_booking_days(today, week_offset, is_admin)

    booked_slot_keys =
      if current_user_id do
        case type do
          :personal -> Bookings.list_personal_booked_slot_keys(current_user_id)
          :cross -> Bookings.list_cross_booked_slot_keys(current_user_id)
        end
      else
        MapSet.new()
      end

    full_slot_keys =
      case type do
        :cross -> Bookings.list_cross_full_slot_keys(week_start, week_end)
        :personal -> Bookings.list_personal_taken_slot_keys(week_start, week_end)
        _ -> MapSet.new()
      end

    admin_slot_form = Phoenix.Component.to_form(%{}, as: :admin_slot)
    admin_publish_form = Phoenix.Component.to_form(%{}, as: :admin_publish)
    admin_delete_form = Phoenix.Component.to_form(%{}, as: :admin_delete)
    admin_upload_form = Phoenix.Component.to_form(%{}, as: :admin_upload)

    current_passes =
      if current_user_id do
        case type do
          :personal -> SeasonPasses.active_passes_by_type(current_user_id, "personal")
          :cross -> SeasonPasses.active_passes_by_type(current_user_id, "cross")
        end
      else
        []
      end

    render(conn, :booking,
      current_user: current_user_id,
      current_user_is_admin: is_admin,
      booking_type: type,
      booking_view: view,
      booking_days: ordered_days,
      booking_availability: %{},
      booked_slot_keys: booked_slot_keys,
      full_slot_keys: full_slot_keys,
      can_go_previous_week: is_admin or week_offset > 0,
      week_offset: week_offset,
      week_start: week_start,
      week_end: week_end,
      admin_slot_form: admin_slot_form,
      admin_publish_form: admin_publish_form,
      admin_delete_form: admin_delete_form,
      admin_upload_form: admin_upload_form,
      current_passes: current_passes,
      draft_add_keys: draft_add_keys,
      admin_draft_changes: draft_change_count
    )
  end

  def aszf(conn, params) do
    return_to = params |> Map.get("return_to") |> normalize_return_to()
    aszf_content = load_aszf_draft_content()

    render(conn, :aszf, aszf_content: aszf_content, return_to: return_to)
  end

  def admin_bookings(conn, params) do
    current_user_id = get_session(conn, :user_id)

    with true <- current_user_id != nil,
         {:ok, admin_user} <- fetch_user(current_user_id),
         true <- admin_user.admin do
      week_offset = parse_week_offset(params["week"])
      base_date = Date.add(Date.utc_today(), week_offset * 7)
      {week_start, week_end} = Booking.week_range(base_date)

      personal_calendar = build_admin_calendar(:personal, week_start, week_end)
      cross_calendar = build_admin_calendar(:cross, week_start, week_end)
      admin_booking_delete_form = Phoenix.Component.to_form(%{}, as: :admin_booking_delete)

      render(conn, :admin_bookings,
        current_user: current_user_id,
        current_user_is_admin: true,
        week_offset: week_offset,
        week_start: week_start,
        week_end: week_end,
        personal_calendar: personal_calendar,
        cross_calendar: cross_calendar,
        admin_booking_delete_form: admin_booking_delete_form
      )
    else
      false ->
        Logger.warning(
          "admin_bookings_error reason=unauthorized admin_user_id=#{current_user_id}"
        )

        generic_error(conn, ~p"/")

      _ ->
        Logger.error("admin_bookings_error reason=unknown admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/")
    end
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
        booking_error(conn, :no_valid_pass, ~p"/foglalas?type=personal&view=week")

      {:error, :capacity_reached} ->
        log_booking_error("personal", current_user_id, :capacity_reached)
        generic_error(conn, ~p"/foglalas?type=personal&view=week")

      {:error, %Ecto.Changeset{}} ->
        log_booking_error("personal", current_user_id, :changeset)
        generic_error(conn, ~p"/foglalas?type=personal&view=week")

      {:error, :slot_not_available} ->
        log_booking_error("personal", current_user_id, :slot_not_available)
        generic_error(conn, ~p"/foglalas?type=personal&view=week")

      {:error, :booking_closed} ->
        log_booking_error("personal", current_user_id, :booking_closed)
        booking_error(conn, :booking_closed, ~p"/foglalas?type=personal&view=week")

      {:error, :too_early_to_book} ->
        log_booking_error("personal", current_user_id, :too_early_to_book)
        booking_error(conn, :too_early_to_book, ~p"/foglalas?type=personal&view=week")

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
        booking_error(conn, :no_valid_pass, ~p"/foglalas?type=cross&view=week")

      {:error, :capacity_reached} ->
        log_booking_error("cross", current_user_id, :capacity_reached)
        generic_error(conn, ~p"/foglalas?type=cross&view=week")

      {:error, %Ecto.Changeset{}} ->
        log_booking_error("cross", current_user_id, :changeset)
        generic_error(conn, ~p"/foglalas?type=cross&view=week")

      {:error, :slot_not_available} ->
        log_booking_error("cross", current_user_id, :slot_not_available)
        generic_error(conn, ~p"/foglalas?type=cross&view=week")

      {:error, :booking_closed} ->
        log_booking_error("cross", current_user_id, :booking_closed)
        booking_error(conn, :booking_closed, ~p"/foglalas?type=cross&view=week")

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
        Logger.warning(
          "booking_cancel_error type=personal reason=not_found user_id=#{current_user_id}"
        )

        generic_error(conn, ~p"/foglalas?type=personal&view=week")

      {:error, :too_late_to_cancel} ->
        Logger.warning(
          "booking_cancel_error type=personal reason=too_late user_id=#{current_user_id}"
        )

        cancellation_error(
          conn,
          :too_late_to_cancel,
          :personal,
          ~p"/foglalas?type=personal&view=week"
        )

      _ ->
        Logger.error(
          "booking_cancel_error type=personal reason=unknown user_id=#{current_user_id}"
        )

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
        Logger.warning(
          "booking_cancel_error type=cross reason=not_found user_id=#{current_user_id}"
        )

        generic_error(conn, ~p"/foglalas?type=cross&view=week")

      {:error, :too_late_to_cancel} ->
        Logger.warning(
          "booking_cancel_error type=cross reason=too_late user_id=#{current_user_id}"
        )

        cancellation_error(conn, :too_late_to_cancel, :cross, ~p"/foglalas?type=cross&view=week")

      _ ->
        Logger.error("booking_cancel_error type=cross reason=unknown user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas?type=cross&view=week")
    end
  end

  defp fetch_user(nil), do: {:error, :unauthorized}

  defp fetch_user(user_id) do
    case Accounts.get_user(user_id) do
      nil -> {:error, :unauthorized}
      user -> {:ok, user}
    end
  end

  def purchase_season_pass(conn, %{"pass_name" => pass_name}) do
    current_user_id = get_session(conn, :user_id)

    if current_user_id do
      case fetch_user(current_user_id) do
        {:ok, user} ->
          case SeasonPasses.validate_purchase(user, pass_name) do
            {:ok, _type_def} ->
              redirect_url = LucaGymappWeb.Endpoint.url() <> ~p"/barion/return"
              callback_url = LucaGymappWeb.Endpoint.url() <> ~p"/barion/callback"

              case Payments.start_season_pass_payment(
                     user,
                     pass_name,
                     redirect_url,
                     callback_url
                   ) do
                {:ok, :skipped} ->
                  complete_pass_purchase(conn, user, pass_name)

                {:ok, %{gateway_url: gateway_url}} when is_binary(gateway_url) ->
                  redirect(conn, external: gateway_url)

                {:error, :missing_barion_payee_email} ->
                  Logger.error("payment_error reason=missing_payee_email pass_name=#{pass_name}")

                  generic_error(conn, ~p"/berletek")

                {:error, reason} ->
                  Logger.error(
                    "payment_error email=#{user.email} name=#{user.name} pass_name=#{pass_name} reason=#{inspect(reason)}"
                  )

                  pass_purchase_error(conn, reason, ~p"/berletek")
              end

            {:error, :active_pass_exists} ->
              Logger.warning(
                "purchase_error email=#{user.email} name=#{user.name} reason=active_pass_exists pass_name=#{pass_name}"
              )

              pass_purchase_error(conn, :active_pass_exists, ~p"/berletek")

            {:error, :once_per_user} ->
              Logger.warning(
                "purchase_error email=#{user.email} name=#{user.name} reason=once_per_user pass_name=#{pass_name}"
              )

              pass_purchase_error(conn, :once_per_user, ~p"/berletek")

            {:error, :invalid_type} ->
              Logger.warning(
                "purchase_error email=#{user.email} name=#{user.name} reason=invalid_type pass_name=#{pass_name}"
              )

              generic_error(conn, ~p"/berletek")

            {:error, _reason} ->
              generic_error(conn, ~p"/berletek")
          end

        {:error, :unauthorized} ->
          Logger.warning("purchase_error_unauthorized")
          generic_error(conn, ~p"/berletek")
      end
    else
      Logger.warning("purchase_error_unauthorized")

      conn
      |> put_flash(:error, "A művelet nem sikerült. Próbáld újra.")
      |> redirect(to: ~p"/berletek")
    end
  end

  defp complete_pass_purchase(conn, user, pass_name) do
    case SeasonPasses.purchase_season_pass(user, pass_name) do
      {:ok, pass} ->
        Logger.info(
          "purchase_success email=#{user.email} name=#{user.name} pass_id=#{pass.pass_id} pass_name=#{pass_name}"
        )

        conn
        |> put_flash(:info, "Sikeres foglalás. E-mailt küldtünk a részletekkel.")
        |> redirect(to: ~p"/berletek")

      {:error, :once_per_user} ->
        Logger.warning(
          "purchase_error email=#{user.email} name=#{user.name} reason=once_per_user pass_name=#{pass_name}"
        )

        pass_purchase_error(conn, :once_per_user, ~p"/berletek")

      {:error, :active_pass_exists} ->
        Logger.warning(
          "purchase_error email=#{user.email} name=#{user.name} reason=active_pass_exists pass_name=#{pass_name}"
        )

        pass_purchase_error(conn, :active_pass_exists, ~p"/berletek")

      {:error, :invalid_type} ->
        Logger.warning(
          "purchase_error email=#{user.email} name=#{user.name} reason=invalid_type pass_name=#{pass_name}"
        )

        generic_error(conn, ~p"/berletek")

      {:error, _reason} ->
        Logger.error(
          "purchase_error email=#{user.email} name=#{user.name} reason=unknown pass_name=#{pass_name}"
        )

        generic_error(conn, ~p"/berletek")
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
         {:ok, target_user} <- fetch_user(user_id),
         {:ok, _payment} <- Payments.grant_cash_season_pass(target_user, pass_name) do
      conn
      |> put_flash(:info, "A bérlet sikeresen létrejött a kiválasztott felhasználónak.")
      |> redirect(to: ~p"/berletek")
    else
      false ->
        Logger.warning(
          "admin_purchase_error reason=unauthorized admin_user_id=#{current_user_id}"
        )

        generic_error(conn, ~p"/berletek")

      {:error, :once_per_user} ->
        Logger.warning(
          "admin_purchase_error reason=once_per_user admin_user_id=#{current_user_id}"
        )

        admin_pass_purchase_error(conn, :once_per_user, ~p"/berletek")

      {:error, :active_pass_exists} ->
        Logger.warning(
          "admin_purchase_error reason=active_pass_exists admin_user_id=#{current_user_id}"
        )

        admin_pass_purchase_error(conn, :active_pass_exists, ~p"/berletek")

      {:error, :invalid_type} ->
        Logger.warning(
          "admin_purchase_error reason=invalid_type admin_user_id=#{current_user_id}"
        )

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
      slots = Bookings.build_default_week_slots(type, date)
      :ok = Bookings.AdminDraftStore.add_slots(current_user_id, type, slots)

      conn
      |> put_flash(:info, "Az alap időpontok piszkozatként elmentve.")
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
         {:ok, slot} <- build_draft_slot(type, date, start_time, end_time) do
      :ok = Bookings.AdminDraftStore.add_slot(current_user_id, type, slot)

      conn
      |> put_flash(:info, "Időpont piszkozatként elmentve.")
      |> redirect(to: ~p"/foglalas?type=#{type}&view=week&week=#{week_offset_from_date(date)}")
    else
      false ->
        Logger.warning(
          "admin_create_slot_error reason=unauthorized admin_user_id=#{current_user_id}"
        )

        generic_error(conn, ~p"/foglalas")

      {:error, :invalid_time_range} ->
        Logger.warning(
          "admin_create_slot_error reason=invalid_time_range admin_user_id=#{current_user_id}"
        )

        generic_error(conn, ~p"/foglalas")

      {:error, %Ecto.Changeset{}} ->
        Logger.warning(
          "admin_create_slot_error reason=changeset admin_user_id=#{current_user_id}"
        )

        generic_error(conn, ~p"/foglalas")

      _ ->
        Logger.error("admin_create_slot_error reason=unknown admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas")
    end
  end

  def admin_delete_slot(
        conn,
        %{"admin_delete" => %{"slot_id" => slot_id, "type" => type} = params}
      ) do
    current_user_id = get_session(conn, :user_id)
    slot_key = Map.get(params, "slot_key")

    with true <- current_user_id != nil,
         {:ok, admin_user} <- fetch_user(current_user_id),
         true <- admin_user.admin,
         {type, _} <- parse_booking_type(type),
         {slot_id, _} <- Integer.parse(slot_id) do
      :ok = Bookings.AdminDraftStore.mark_delete(current_user_id, type, slot_id, slot_key)

      conn
      |> put_flash(:info, "Időpont piszkozat törlésre jelölve.")
      |> redirect(to: ~p"/foglalas?type=#{type}&view=week")
    else
      false ->
        Logger.warning(
          "admin_delete_slot_error reason=unauthorized admin_user_id=#{current_user_id}"
        )

        generic_error(conn, ~p"/foglalas")

      _ ->
        Logger.error("admin_delete_slot_error reason=unknown admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas?type=#{type}&view=week")
    end
  end

  def admin_delete_slot(conn, %{"admin_delete" => %{"draft_key" => draft_key, "type" => type}}) do
    current_user_id = get_session(conn, :user_id)

    with true <- current_user_id != nil,
         {:ok, admin_user} <- fetch_user(current_user_id),
         true <- admin_user.admin,
         {type, _} <- parse_booking_type(type) do
      :ok = Bookings.AdminDraftStore.remove_draft_slot(current_user_id, type, draft_key)

      conn
      |> put_flash(:info, "Piszkozat időpont törölve.")
      |> redirect(to: ~p"/foglalas?type=#{type}&view=week")
    else
      false ->
        Logger.warning(
          "admin_delete_slot_error reason=unauthorized admin_user_id=#{current_user_id}"
        )

        generic_error(conn, ~p"/foglalas")

      _ ->
        Logger.error("admin_delete_slot_error reason=unknown admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas?type=#{type}&view=week")
    end
  end

  def admin_upload_changes(conn, %{"admin_upload" => %{"type" => type, "week" => week}}) do
    current_user_id = get_session(conn, :user_id)

    with true <- current_user_id != nil,
         {:ok, admin_user} <- fetch_user(current_user_id),
         true <- admin_user.admin,
         {type, _} <- parse_booking_type(type) do
      draft = Bookings.AdminDraftStore.list(current_user_id, type)

      result =
        Bookings.apply_admin_draft_changes(Map.values(draft.adds), draft.deletes)

      case result do
        {:ok, :ok} ->
          _ = GenServer.stop(Bookings.AdminDraftStore, :normal)

          conn
          |> put_flash(:info, "A piszkozat időpontok feltöltve.")
          |> redirect(to: ~p"/admin/foglalas?week=#{week}")

        {:error, :slot_has_bookings} ->
          Logger.warning(
            "admin_upload_error reason=slot_has_bookings admin_user_id=#{current_user_id}"
          )

          generic_error(conn, ~p"/foglalas?type=#{type}&view=week")

        {:error, reason} ->
          Logger.error(
            "admin_upload_error reason=#{inspect(reason)} admin_user_id=#{current_user_id}"
          )

          generic_error(conn, ~p"/foglalas?type=#{type}&view=week")
      end
    else
      false ->
        Logger.warning("admin_upload_error reason=unauthorized admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas")

      _ ->
        Logger.error("admin_upload_error reason=unknown admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/foglalas")
    end
  end

  def admin_cancel_booking(
        conn,
        %{"admin_booking_delete" => %{"type" => type, "booking_id" => booking_id, "week" => week}}
      ) do
    current_user_id = get_session(conn, :user_id)

    with true <- current_user_id != nil,
         {:ok, admin_user} <- fetch_user(current_user_id),
         true <- admin_user.admin,
         {type, _} <- parse_booking_type(type),
         {booking_id, _} <- Integer.parse(booking_id),
         {:ok, booking} <- Bookings.admin_cancel_booking(type, booking_id) do
      if booking.user do
        _ =
          Notifications.deliver_user_booking_cancellation_by_admin_notification(
            booking.user,
            type,
            booking
          )
      end

      conn
      |> put_flash(:info, "A foglalas torolve lett.")
      |> redirect(to: ~p"/admin/foglalas?week=#{week}")
    else
      false ->
        Logger.warning(
          "admin_cancel_booking_error reason=unauthorized admin_user_id=#{current_user_id}"
        )

        generic_error(conn, ~p"/admin/foglalas")

      {:error, :not_found} ->
        Logger.warning(
          "admin_cancel_booking_error reason=not_found admin_user_id=#{current_user_id}"
        )

        generic_error(conn, ~p"/admin/foglalas?week=#{week}")

      _ ->
        Logger.error("admin_cancel_booking_error reason=unknown admin_user_id=#{current_user_id}")
        generic_error(conn, ~p"/admin/foglalas?week=#{week}")
    end
  end

  defp current_user_from_session(conn) do
    case get_session(conn, :user_id) do
      nil ->
        {conn, nil}

      user_id ->
        case Accounts.get_user(user_id) do
          nil -> {delete_session(conn, :user_id), nil}
          user -> {conn, user}
        end
    end
  end

  defp normalize_return_to(path) when is_binary(path) do
    decoded_path = URI.decode(path)
    parsed = URI.parse(decoded_path)

    cond do
      parsed.scheme != nil or parsed.host != nil ->
        "/berletek"

      is_binary(parsed.path) and String.starts_with?(parsed.path, "/") ->
        case parsed.fragment do
          nil -> parsed.path
          fragment -> parsed.path <> "#" <> fragment
        end

      true ->
        "/berletek"
    end
  end

  defp normalize_return_to(_), do: "/berletek"

  defp load_aszf_draft_content do
    path = Path.join(:code.priv_dir(:luca_gymapp), "legal/aszf_draft.md")

    case File.read(path) do
      {:ok, content} -> content
      {:error, _reason} -> "Az ÁSZF tervezet jelenleg nem elérhető."
    end
  end

  defp parse_booking_type("cross"), do: {:cross, :cross}
  defp parse_booking_type(_), do: {:personal, :personal}

  defp week_offset_from_date(%Date{} = date) do
    today = Date.utc_today()
    diff = Date.diff(date, today)
    div(diff, 7)
  end

  defp parse_week_offset(value) do
    case value do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, _} -> int
          :error -> 0
        end

      _ ->
        0
    end
  end

  defp normalize_week_offset(week_offset, true), do: week_offset
  defp normalize_week_offset(week_offset, false), do: max(week_offset, 0)
  defp normalize_week_offset(week_offset, _), do: max(week_offset, 0)

  defp filter_visible_booking_days(days, _today, _week_offset, true), do: days

  defp filter_visible_booking_days(days, today, 0, false) do
    Enum.reject(days, &(Date.compare(&1.date, today) == :lt))
  end

  defp filter_visible_booking_days(days, _today, _week_offset, false), do: days
  defp filter_visible_booking_days(days, _today, _week_offset, _), do: days

  defp parse_time_param(value) when is_binary(value) do
    value =
      case String.length(value) do
        5 -> value <> ":00"
        _ -> value
      end

    Time.from_iso8601(value)
  end

  defp build_admin_calendar(type, %Date{} = week_start, %Date{} = week_end) do
    slots = Bookings.list_calendar_slots_for_week(type, week_start, week_end)
    days = Booking.ordered_days_from_slots(slots, week_start)
    bookings = Bookings.list_bookings_for_week(type, week_start, week_end)
    bookings_by_key = Enum.group_by(bookings, &slot_key_from_booking/1)
    capacity = calendar_capacity(type)

    days =
      Enum.map(days, fn day ->
        hour_slots =
          Enum.map(day.hour_slots, fn slot ->
            slot_bookings = Map.get(bookings_by_key, slot.key, [])
            remaining = max(capacity - length(slot_bookings), 0)

            %{
              slot: slot,
              bookings: Enum.map(slot_bookings, &booking_entry/1),
              remaining: remaining
            }
          end)

        %{day | hour_slots: hour_slots}
      end)

    %{
      type: type,
      days: days,
      capacity: capacity
    }
  end

  defp calendar_capacity(:personal) do
    Application.get_env(:luca_gymapp, :personal_max_overlap, 1)
  end

  defp calendar_capacity(:cross) do
    Application.get_env(:luca_gymapp, :cross_max_overlap, 8)
  end

  defp calendar_capacity(_), do: 1

  defp booking_display_name(booking) do
    cond do
      booking.user && is_binary(booking.user.name) && booking.user.name != "" ->
        booking.user.name

      is_binary(booking.user_name) and booking.user_name != "" ->
        booking.user_name

      booking.user && is_binary(booking.user.email) ->
        booking.user.email

      true ->
        "Ismeretlen"
    end
  end

  defp booking_entry(booking) do
    %{
      id: booking.id,
      display_name: booking_display_name(booking)
    }
  end

  defp slot_key_from_booking(booking) do
    DateTime.to_iso8601(booking.start_time) <> "|" <> DateTime.to_iso8601(booking.end_time)
  end

  defp build_draft_slot(type, %Date{} = date, %Time{} = start_time, %Time{} = end_time) do
    start_dt = DateTime.new!(date, start_time, "Etc/UTC")
    end_dt = DateTime.new!(date, end_time, "Etc/UTC")

    if DateTime.compare(end_dt, start_dt) != :gt do
      {:error, :invalid_time_range}
    else
      slot_type =
        case type do
          :cross -> "cross"
          _ -> "personal"
        end

      {:ok,
       %LucaGymapp.Bookings.CalendarSlot{
         slot_type: slot_type,
         start_time: start_dt,
         end_time: end_dt
       }}
    end
  end

  defp slot_key_from_slot(slot) do
    DateTime.to_iso8601(slot.start_time) <> "|" <> DateTime.to_iso8601(slot.end_time)
  end

  defp generic_error(conn, redirect_path) do
    conn
    |> put_flash(:error, "A művelet nem sikerült. Próbáld újra.")
    |> redirect(to: redirect_path)
  end

  defp booking_error(conn, :booking_closed, redirect_path) do
    conn
    |> put_flash(:error, "Erre az időpontra már nem lehet foglalni, mert elmúlt.")
    |> redirect(to: redirect_path)
  end

  defp booking_error(conn, :too_early_to_book, redirect_path) do
    conn
    |> put_flash(
      :error,
      "A személyi edzést legalább 6 óráva az edzés kezdete előtt kell lefoglalni."
    )
    |> redirect(to: redirect_path)
  end

  defp booking_error(conn, :no_valid_pass, redirect_path) do
    conn
    |> put_flash(:error, "Ehhez a foglaláshoz nincs érvényes bérleted.")
    |> redirect(to: redirect_path)
  end

  defp booking_error(conn, _reason, redirect_path), do: generic_error(conn, redirect_path)

  defp cancellation_error(conn, :too_late_to_cancel, :personal, redirect_path) do
    conn
    |> put_flash(
      :error,
      "A személyi edzést legalább 6 órával az edzés kezdete előtt lehet lemondani."
    )
    |> redirect(to: redirect_path)
  end

  defp cancellation_error(conn, :too_late_to_cancel, :cross, redirect_path) do
    conn
    |> put_flash(
      :error,
      "A cross edzést legalább 1 órával az edzés kezdete előtt lehet lemondani."
    )
    |> redirect(to: redirect_path)
  end

  defp cancellation_error(conn, _reason, _type, redirect_path),
    do: generic_error(conn, redirect_path)

  defp pass_purchase_error(conn, :active_pass_exists, redirect_path) do
    conn
    |> put_flash(:error, "Már van aktív bérleted ebben a kategóriában.")
    |> redirect(to: redirect_path)
  end

  defp pass_purchase_error(conn, :once_per_user, redirect_path) do
    conn
    |> put_flash(:error, "Ezt a bérletet csak egyszer lehet megvásárolni.")
    |> redirect(to: redirect_path)
  end

  defp pass_purchase_error(conn, _reason, redirect_path), do: generic_error(conn, redirect_path)

  defp admin_pass_purchase_error(conn, :active_pass_exists, redirect_path) do
    conn
    |> put_flash(
      :error,
      "A kiválasztott felhasználónak már van aktív bérlete ebben a kategóriában."
    )
    |> redirect(to: redirect_path)
  end

  defp admin_pass_purchase_error(conn, :once_per_user, redirect_path) do
    conn
    |> put_flash(
      :error,
      "A kiválasztott felhasználó ezt a bérletet csak egyszer vásárolhatja meg."
    )
    |> redirect(to: redirect_path)
  end

  defp admin_pass_purchase_error(conn, _reason, redirect_path),
    do: generic_error(conn, redirect_path)

  defp log_booking_error(type, user_id, reason) do
    case user_id do
      nil ->
        Logger.warning("booking_error type=#{type} reason=#{reason} user_id=nil")

      id ->
        Logger.warning("booking_error type=#{type} reason=#{reason} user_id=#{id}")
    end
  end
end
