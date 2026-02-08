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

  def season_pass_email(user, pass) do
    from_address = mail_from()

    new()
    |> to({user.name || user.email, user.email})
    |> from(from_address)
    |> subject("Berlet vasarlas megerositese")
    |> text_body("""
    Szia!

    A berleted sikeresen letrehoztuk. A reszletek:
    - Tipus: #{pass.pass_name}
    - Kategoria: #{pass.pass_type}
    - Ar: #{pass.purchase_price} Ft
    - Vasarlas ideje: #{pass.purchase_timestamp}
    - Lejarat: #{pass.expiry_date}
    - Azonosito: #{pass.pass_id}

    Koszonjuk!
    """)
  end

  defp mail_from do
    Application.get_env(:luca_gymapp, LucaGymapp.Mailer)[:default_from] || "no-reply@localhost"
  end
end
