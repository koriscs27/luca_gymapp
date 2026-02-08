defmodule LucaGymapp.Booking do
  @day_order [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]

  def schedule_for(type) when is_atom(type) do
    config = Application.get_env(:luca_gymapp, :booking_schedule, %{})
    type_config = Map.get(config, type, %{})

    %{
      default_view: Map.get(type_config, :default_view, :week),
      availability: Map.get(type_config, :availability, %{})
    }
  end

  def ordered_days(availability, base_date \\ Date.utc_today()) when is_map(availability) do
    today = base_date

    @day_order
    |> Enum.map(fn day ->
      date = date_for_week_day(day, today)
      slots = Map.get(availability, day, [])

      %{
        day: day,
        label: day_label(day),
        date: date,
        slots: slots,
        hour_slots: expand_hour_slots(slots, date)
      }
    end)
  end

  def default_day(availability) when is_map(availability) do
    availability
    |> Map.keys()
    |> Enum.filter(&(&1 in @day_order))
    |> case do
      [] -> :monday
      days -> Enum.min_by(days, &day_index/1)
    end
  end

  def format_time(%Time{} = time) do
    Calendar.strftime(time, "%H:%M")
  end

  def format_date(%Date{} = date) do
    Calendar.strftime(date, "%Y.%m.%d")
  end

  def week_range(date) do
    start_date = Date.beginning_of_week(date, :monday)
    end_date = Date.end_of_week(date, :monday)
    {start_date, end_date}
  end

  def day_label(day) do
    case day do
      :monday -> "Hétfő"
      :tuesday -> "Kedd"
      :wednesday -> "Szerda"
      :thursday -> "Csütörtök"
      :friday -> "Péntek"
      :saturday -> "Szombat"
      :sunday -> "Vasárnap"
      _ -> "Ismeretlen"
    end
  end

  defp day_index(day) do
    Enum.find_index(@day_order, &(&1 == day)) || 0
  end

  defp expand_hour_slots(slots, date) do
    slots
    |> Enum.flat_map(&expand_range(&1, date))
  end

  defp expand_range(%{from: %Time{} = from, to: %Time{} = to}, date) do
    step = 60 * 60

    Stream.iterate(from, &Time.add(&1, step, :second))
    |> Enum.take_while(&(Time.compare(&1, to) == :lt))
    |> Enum.map(fn start_time ->
      finish_time = Time.add(start_time, step, :second)
      start_datetime = DateTime.new!(date, start_time, "Etc/UTC")
      end_datetime = DateTime.new!(date, finish_time, "Etc/UTC")

      %{
        from: start_time,
        to: finish_time,
        start_datetime: start_datetime,
        end_datetime: end_datetime,
        label: "#{format_time(start_time)}-#{format_time(finish_time)}",
        key: slot_key(start_datetime, end_datetime)
      }
    end)
  end

  defp slot_key(%DateTime{} = start_datetime, %DateTime{} = end_datetime) do
    DateTime.to_iso8601(start_datetime) <> "|" <> DateTime.to_iso8601(end_datetime)
  end

  defp date_for_week_day(day, date) do
    monday = Date.beginning_of_week(date, :monday)
    Date.add(monday, day_of_week(day) - 1)
  end

  defp day_of_week(day) do
    case day do
      :monday -> 1
      :tuesday -> 2
      :wednesday -> 3
      :thursday -> 4
      :friday -> 5
      :saturday -> 6
      :sunday -> 7
      _ -> 1
    end
  end
end
