defmodule LucaGymapp.Notifications do
  require Logger

  alias LucaGymapp.Accounts.UserEmail
  alias LucaGymapp.Mailer

  def deliver_booking_notification(user, type, booking) do
    deliver_coach_email(user, type, booking, "New booking", "Booked")
  end

  def deliver_booking_cancellation_notification(user, type, booking) do
    deliver_coach_email(user, type, booking, "Booking cancelled", "Cancelled")
  end

  def deliver_user_booking_cancellation_by_admin_notification(user, type, booking) do
    email = UserEmail.booking_cancelled_by_admin_email(user, type, booking)

    case Mailer.deliver(email) do
      {:ok, _} = ok ->
        ok

      {:error, reason} = error ->
        Logger.error("Admin cancellation email failed reason=#{inspect(reason)}",
          user_id: user.id
        )

        error
    end
  end

  defp deliver_coach_email(user, type, booking, subject_prefix, status_label) do
    mailgun = Application.get_env(:luca_gymapp, :mailgun, [])
    coach_email = Application.get_env(:luca_gymapp, :coach_email)
    api_key = Keyword.get(mailgun, :api_key)
    domain = Keyword.get(mailgun, :domain)
    base_url = Keyword.get(mailgun, :base_url)
    from = Keyword.get(mailgun, :from)

    Logger.warning("coach_email_debug cancellation trigger",
      coach_email: coach_email,
      type: type,
      user_id: user.id,
      start_time: inspect(booking.start_time),
      end_time: inspect(booking.end_time)
    )

    cond do
      is_nil(coach_email) or coach_email == "" ->
        Logger.warning("coach_email_debug skipped: missing coach_email")
        :skipped

      is_nil(api_key) or api_key == "" ->
        Logger.warning("coach_email_debug skipped: missing mailgun api_key")
        :skipped

      is_nil(domain) or domain == "" ->
        Logger.warning("coach_email_debug skipped: missing mailgun domain")
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
          booking,
          subject_prefix,
          status_label
        )
    end
  end

  defp send_mailgun_booking_email(
         base_url,
         domain,
         api_key,
         from,
         to,
         user,
         type,
         booking,
         subject_prefix,
         status_label
       ) do
    subject = "#{subject_prefix}: #{humanize_type(type)}"
    text = booking_text(user, type, booking, status_label)

    Logger.warning("coach_email_debug outgoing mail",
      to: to,
      subject: subject,
      user_id: user.id
    )

    req = Req.new(base_url: base_url, auth: {:basic, "api:" <> api_key})

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

      {:ok, %{status: status, body: _body}} ->
        Logger.error(
          "Mailgun booking email failed reason=:mailgun_http_error",
          status: status
        )

        {:error, :mailgun_failed}

      {:error, reason} ->
        Logger.error("Mailgun booking email error reason=#{inspect(reason)}")
        {:error, :mailgun_failed}
    end
  end

  defp booking_text(user, type, booking, status_label) do
    start_time = format_datetime(booking.start_time)
    end_time = format_datetime(booking.end_time)
    name = user.name || ""
    name = if name == "", do: "-", else: name

    [
      "Status: #{status_label}",
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
