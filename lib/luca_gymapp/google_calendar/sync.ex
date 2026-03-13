defmodule LucaGymapp.GoogleCalendar.Sync do
  require Logger

  alias LucaGymapp.Bookings
  alias LucaGymapp.GoogleCalendar

  @max_attempts 3
  @retry_base_ms 100

  def enqueue_booking_created(type, booking) do
    runner().async(fn -> sync_create(type, booking.id, 1) end)
    :ok
  end

  def enqueue_booking_cancelled(type, booking) do
    runner().async(fn -> sync_delete(type, booking.id, 1) end)
    :ok
  end

  defp sync_create(type, booking_id, attempt) do
    case do_sync_create(type, booking_id) do
      :ok ->
        :ok

      {:retry, _reason} when attempt < @max_attempts ->
        Process.sleep(@retry_base_ms * attempt)
        sync_create(type, booking_id, attempt + 1)

      {:retry, reason} ->
        Logger.error(
          "google_calendar_create_failed type=#{type} booking_id=#{booking_id} reason=#{inspect(reason)}"
        )

        :error

      :skip ->
        :ok
    end
  end

  defp sync_delete(type, booking_id, attempt) do
    case do_sync_delete(type, booking_id) do
      :ok ->
        :ok

      {:retry, _reason} when attempt < @max_attempts ->
        Process.sleep(@retry_base_ms * attempt)
        sync_delete(type, booking_id, attempt + 1)

      {:retry, reason} ->
        Logger.error(
          "google_calendar_delete_failed type=#{type} booking_id=#{booking_id} reason=#{inspect(reason)}"
        )

        :error

      :skip ->
        :ok
    end
  end

  defp do_sync_create(type, booking_id) do
    with %{} = connection <- GoogleCalendar.get_active_connection(),
         {:ok, booking} <- Bookings.get_google_sync_booking(type, booking_id),
         true <- is_nil(booking.google_event_id),
         event_id <- build_event_id(type, booking.id),
         attrs <- build_event_attributes(type, booking, event_id),
         {:ok, event_id} <- GoogleCalendar.create_booking_event(connection, event_id, attrs),
         {:ok, _booking} <- Bookings.set_google_event_id(type, booking.id, event_id) do
      :ok
    else
      nil -> :skip
      false -> :skip
      {:error, :not_found} -> :skip
      {:error, reason} -> {:retry, reason}
    end
  end

  defp do_sync_delete(type, booking_id) do
    with %{} = connection <- GoogleCalendar.get_active_connection(),
         {:ok, booking} <- Bookings.get_google_sync_booking(type, booking_id),
         event_id when is_binary(event_id) and event_id != "" <- booking.google_event_id,
         :ok <- GoogleCalendar.delete_booking_event(connection, event_id) do
      :ok
    else
      nil -> :skip
      {:error, :not_found} -> :skip
      event_id when event_id in [nil, ""] -> :skip
      {:error, reason} -> {:retry, reason}
    end
  end

  defp build_event_id(type, booking_id) do
    suffix =
      case type do
        :personal -> "p"
        :cross -> "c"
        "personal" -> "p"
        "cross" -> "c"
        _ -> "u"
      end

    "lg#{suffix}#{Integer.to_string(booking_id, 32)}"
  end

  defp build_event_attributes(type, booking, event_id) do
    user = booking.user

    type_label =
      if type in [:personal, "personal"], do: "Personal training", else: "Cross training"

    user_label =
      booking.user_name || (user && user.name) || (user && user.email) || "Unknown user"

    user_email = if user, do: user.email, else: "-"

    %{
      id: event_id,
      summary: "#{type_label} - #{user_label}",
      description: "Booking type: #{type_label}\nUser email: #{user_email}",
      start: %{
        dateTime: DateTime.to_iso8601(booking.start_time),
        timeZone: "Etc/UTC"
      },
      end: %{
        dateTime: DateTime.to_iso8601(booking.end_time),
        timeZone: "Etc/UTC"
      }
    }
  end

  defp runner do
    Application.get_env(
      :luca_gymapp,
      :google_calendar_sync_runner,
      LucaGymapp.GoogleCalendar.TaskRunner
    )
  end
end
