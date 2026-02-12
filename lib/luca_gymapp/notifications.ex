defmodule LucaGymapp.Notifications do
  require Logger

  def deliver_booking_notification(user, type, booking) do
    mailgun = Application.get_env(:luca_gymapp, :mailgun, [])
    coach_email = Application.get_env(:luca_gymapp, :coach_email)
    api_key = Keyword.get(mailgun, :api_key)
    domain = Keyword.get(mailgun, :domain)
    base_url = Keyword.get(mailgun, :base_url)
    from = Keyword.get(mailgun, :from)

    cond do
      is_nil(coach_email) or coach_email == "" ->
        :skipped

      is_nil(api_key) or api_key == "" ->
        :skipped

      is_nil(domain) or domain == "" ->
        :skipped

      true ->
        send_mailgun_booking_email(
          base_url,
          domain,
          api_key,
          from,
          coach_email,
          user,
          type,
          booking
        )
    end
  end

  defp send_mailgun_booking_email(base_url, domain, api_key, from, to, user, type, booking) do
    subject = "New booking: #{humanize_type(type)}"
    text = booking_text(user, type, booking)

    req = Req.new(base_url: base_url, auth: {:basic, "api", api_key})

    case Req.post(req,
           url: "/#{domain}/messages",
           form: [
             from: from,
             to: to,
             subject: subject,
             text: text
           ]
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        Logger.error("Mailgun booking email failed",
          status: status,
          body: inspect(body)
        )

        {:error, :mailgun_failed}

      {:error, reason} ->
        Logger.error("Mailgun booking email error", reason: inspect(reason))
        {:error, :mailgun_failed}
    end
  end

  defp booking_text(user, type, booking) do
    start_time = format_datetime(booking.start_time)
    end_time = format_datetime(booking.end_time)
    name = user.name || ""
    name = if name == "", do: "-", else: name

    [
      "Class type: #{humanize_type(type)}",
      "Date: #{start_time} - #{end_time}",
      "User email: #{user.email}",
      "User name: #{name}"
    ]
    |> Enum.join("\n")
  end

  defp format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
  end

  defp format_datetime(_), do: "-"

  defp humanize_type(:personal), do: "Personal"
  defp humanize_type(:cross), do: "Cross"
  defp humanize_type(value) when is_binary(value), do: String.capitalize(value)
  defp humanize_type(_), do: "Unknown"
end
