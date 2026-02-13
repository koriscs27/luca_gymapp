defmodule LucaGymapp.Accounts.UserEmail do
  import Swoosh.Email

  alias LucaGymappWeb.Endpoint

  def confirmation_email(user, token) do
    from_address = mail_from()
    confirmation_url = Endpoint.url() <> "/confirm-email?token=" <> token

    new()
    |> to({user.name || user.email, user.email})
    |> from(from_address)
    |> subject("Email megerősítés")
    |> text_body("""
    Szia!

    Kérjük, erősítsd meg az e-mail címedet az alábbi linken:
    #{confirmation_url}

    A link 1 óráig érvényes.
    """)
  end

  def password_reset_email(user, token) do
    from_address = mail_from()
    reset_url = Endpoint.url() <> "/password/reset?token=" <> token

    new()
    |> to({user.name || user.email, user.email})
    |> from(from_address)
    |> subject("Jelszó visszaállítás")
    |> text_body("""
    Szia!

    A jelszó visszaállításához kattints az alábbi linkre:
    #{reset_url}

    A link 1 óráig érvényes.

    Ha nem te kérted, hagyd figyelmen kívül ezt az e-mailt.
    """)
  end

  def booking_cancelled_by_admin_email(user, type, booking) do
    from_address = mail_from()

    new()
    |> to({user.name || user.email, user.email})
    |> from(from_address)
    |> subject("Foglalas torolve: #{humanize_booking_type(type)}")
    |> text_body("""
    Szia!

    A kovetkezo foglalasodat a coach torolte:
    #{format_booking_window(booking)}

    Ha kerdesed van, valaszolj erre az e-mailre.
    """)
  end

  defp mail_from do
    Application.get_env(:luca_gymapp, LucaGymapp.Mailer)[:default_from] || "no-reply@localhost"
  end

  defp format_booking_window(booking) do
    start_time = format_datetime(booking.start_time)
    end_time = format_datetime(booking.end_time)
    "#{start_time} - #{end_time}"
  end

  defp format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
  end

  defp format_datetime(_), do: "-"

  defp humanize_booking_type(:personal), do: "Szemelyi edzes"
  defp humanize_booking_type(:cross), do: "Cross trening"
  defp humanize_booking_type(value) when is_binary(value), do: String.capitalize(value)
  defp humanize_booking_type(_), do: "Edzes"
end
