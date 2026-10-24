defmodule LucaGymappWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use LucaGymappWeb, :html
  alias LucaGymapp.SeasonPasses

  embed_templates "page_html/*"

  def format_huf(amount) when is_integer(amount) do
    amount
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(...)(?=.)/, "\\1 ")
    |> String.reverse()
  end

  def format_huf(_amount), do: "0"

  def format_date(%Date{} = date) do
    Calendar.strftime(date, "%Y.%m.%d")
  end

  def format_date(_date), do: "-"

  def season_pass_label(type) when is_binary(type) do
    SeasonPasses.display_name(type)
  end

  def season_pass_label(type) when is_atom(type) do
    SeasonPasses.display_name(type)
  end

  attr :pass, :map, required: true

  def payment_modal(assigns) do
    ~H"""
    <div
      id={"purchase-#{@pass.key}"}
      class="booking-confirm-modal"
      role="dialog"
      aria-modal="true"
      aria-labelledby={"payment-title-#{@pass.key}"}
    >
      <a href="#" class="booking-confirm-modal__overlay" aria-label="Bezárás"></a>
      <div class="booking-confirm-modal__panel">
        <div class="flex items-start justify-between gap-4">
          <div>
            <p class="text-xs uppercase tracking-[0.3em] text-neutral-500">Bérlet vásárlás</p>

            <h3 id={"payment-title-#{@pass.key}"} class="mt-1 text-xl font-semibold text-neutral-900">
              Fizetési mód
            </h3>
          </div>

          <.link
            href="#"
            class="inline-flex h-9 w-9 items-center justify-center rounded-full border border-neutral-200 text-neutral-500 transition hover:border-neutral-300 hover:text-neutral-700"
            aria-label="Bezárás"
          >
            <.icon name="hero-x-mark" class="h-4 w-4" />
          </.link>
        </div>

        <div class="mt-4 rounded-xl border border-neutral-200 bg-neutral-50 px-4 py-3">
          <p class="text-sm font-semibold text-neutral-900">{@pass.name}</p>

          <div class="mt-2 flex flex-wrap gap-3 text-xs text-neutral-600">
            <span
              id={"purchase-price-#{@pass.key}"}
              data-original-price={@pass.price_huf}
              class="rounded-full bg-white px-3 py-1 text-neutral-700 shadow-sm"
            >
              Ár: {format_huf(@pass.price_huf)} Ft
            </span>
            <%= if @pass.occasions > 0 do %>
              <span class="rounded-full bg-white px-3 py-1 text-neutral-700 shadow-sm">
                Alkalmak: {@pass.occasions}
              </span>
            <% else %>
              <span class="rounded-full bg-white px-3 py-1 text-neutral-700 shadow-sm">
                Időtartam: 3 hónap
              </span>
            <% end %>
          </div>
        </div>

        <div class="mt-6 space-y-3">
          <.form
            for={%{}}
            id={"confirm-purchase-barion-#{@pass.key}"}
            action={~p"/berletek/purchase"}
            method="post"
            class="purchase-terms-form space-y-3"
          >
            <.input type="hidden" name="pass_name" value={@pass.type} />
            <.input type="hidden" name="payment_method" value="barion" />
            <div class="flex items-end gap-2">
              <div class="min-w-0 flex-1">
                <.input
                  id={"coupon-code-#{@pass.key}"}
                  name="coupon_code"
                  type="text"
                  value=""
                  label="Kuponkód"
                  autocomplete="off"
                  data-coupon-code
                  class="w-full rounded-xl border border-neutral-300 bg-white px-3 py-2 text-sm text-neutral-900 focus:border-neutral-700 focus:outline-none focus:ring-2 focus:ring-neutral-200"
                />
              </div>
              <button
                type="button"
                data-verify-coupon
                data-pass-name={@pass.type}
                class="mb-2 rounded-xl border border-neutral-300 px-4 py-2 text-sm font-semibold text-neutral-800 transition hover:bg-neutral-100"
              >
                Ellenőrzés
              </button>
            </div>
            <p data-coupon-message aria-live="polite" class="min-h-5 text-sm text-neutral-600"></p>
            <label
              for={"accept-aszf-#{@pass.key}"}
              class="flex items-start gap-2 rounded-lg border border-neutral-200 bg-neutral-50 px-3 py-2 text-sm text-neutral-700"
            >
              <input
                id={"accept-aszf-#{@pass.key}"}
                name="accept_aszf"
                type="checkbox"
                value="true"
                required
                data-aszf-checkbox
                class="mt-0.5 h-4 w-4 rounded border-neutral-300 text-neutral-900"
              />
              <span>
                Elolvastam és elfogadom az <.link
                  href={
                    "/aszf?return_to=" <>
                      URI.encode_www_form("/berletek#purchase-#{@pass.key}")
                  }
                  class="font-semibold underline underline-offset-2"
                >
                  ÁSZF-et
                </.link>.
              </span>
            </label>
            <p class="text-xs text-neutral-600">
              Az
              <.link
                href={
                  "/adatkezelesi-tajekoztato?return_to=" <>
                    URI.encode_www_form("/berletek#purchase-#{@pass.key}")
                }
                class="font-semibold underline underline-offset-2"
              >
                Adatkezelési Tájékoztató
              </.link>
              itt bármikor megtekinthető.
            </p>
            <button
              type="submit"
              data-aszf-submit
              disabled
              class="inline-flex w-full cursor-pointer items-center justify-center rounded-xl border border-neutral-900 bg-neutral-900 px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition-all duration-150 hover:-translate-y-0.5 hover:border-neutral-700 hover:bg-neutral-800 hover:shadow-lg active:translate-y-0 active:shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-neutral-900 focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:border-neutral-200 disabled:bg-neutral-100 disabled:text-neutral-500 disabled:opacity-100 disabled:shadow-none disabled:hover:translate-y-0 disabled:hover:border-neutral-200 disabled:hover:bg-neutral-100 disabled:hover:shadow-none"
              aria-label="Fizetés Barionnal"
            >
              Fizetes Barionnal
            </button>
          </.form>
          <img
            src={~p"/images/barion-smart-banner-light.svg"}
            alt="Barion Smart Banner"
            class="mx-auto mt-1.5 w-full max-w-[340px]"
            loading="lazy"
          />
        </div>

        <.link
          href="#"
          class="mt-3 inline-flex w-full justify-center rounded-full border border-neutral-200 px-4 py-2 text-sm font-semibold text-neutral-600 transition hover:border-neutral-300"
        >
          Mégse
        </.link>
      </div>
    </div>
    """
  end
end
