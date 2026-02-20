defmodule LucaGymappWeb.EmailConfirmationRequestController do
  use LucaGymappWeb, :controller

  alias LucaGymapp.Accounts
  alias LucaGymapp.Security.RateLimiter

  def new(conn, _params) do
    form = Phoenix.Component.to_form(%{"email" => ""}, as: :confirmation)
    render(conn, :new, form: form)
  end

  def create(conn, %{"confirmation" => %{"email" => email}}) do
    case RateLimiter.allow_request(conn, :email_confirmation_request, email: email) do
      :ok ->
        Accounts.deliver_confirmation_instructions_for_email(email)

        conn
        |> put_flash(
          :info,
          "Ha létezik fiók, új megerősítő e-mailt küldtünk erre a címre: #{email}"
        )
        |> redirect(to: ~p"/confirm-email/new")

      {:error, :rate_limited} ->
        conn
        |> put_flash(:error, RateLimiter.rate_limited_message())
        |> redirect(to: ~p"/confirm-email/new")
    end
  end

  def create(conn, _params) do
    case RateLimiter.allow_request(conn, :email_confirmation_request) do
      :ok ->
        conn
        |> put_flash(:info, "Ha létezik fiók, új megerősítő e-mailt küldtünk.")
        |> redirect(to: ~p"/confirm-email/new")

      {:error, :rate_limited} ->
        conn
        |> put_flash(:error, RateLimiter.rate_limited_message())
        |> redirect(to: ~p"/confirm-email/new")
    end
  end
end
