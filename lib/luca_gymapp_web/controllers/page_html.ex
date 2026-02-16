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
      <a href="#" class="booking-confirm-modal__overlay" aria-label="BezĂˇrĂˇs"></a>
      <div class="booking-confirm-modal__panel">
        <div class="flex items-start justify-between gap-4">
          <div>
            <p class="text-xs uppercase tracking-[0.3em] text-neutral-500">BĂ©rlet vĂˇsĂˇrlĂˇs</p>

            <h3 id={"payment-title-#{@pass.key}"} class="mt-1 text-xl font-semibold text-neutral-900">
              FizetĂ©si mĂłd
            </h3>
          </div>

          <.link
            href="#"
            class="inline-flex h-9 w-9 items-center justify-center rounded-full border border-neutral-200 text-neutral-500 transition hover:border-neutral-300 hover:text-neutral-700"
            aria-label="BezĂˇrĂˇs"
          >
            <.icon name="hero-x-mark" class="h-4 w-4" />
          </.link>
        </div>

        <div class="mt-4 rounded-xl border border-neutral-200 bg-neutral-50 px-4 py-3">
          <p class="text-sm font-semibold text-neutral-900">{@pass.name}</p>

          <div class="mt-2 flex flex-wrap gap-3 text-xs text-neutral-600">
            <span class="rounded-full bg-white px-3 py-1 text-neutral-700 shadow-sm">
              Ăr: {format_huf(@pass.price_huf)} Ft
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
          >
            <.input type="hidden" name="pass_name" value={@pass.type} />
            <.input type="hidden" name="payment_method" value="barion" />
            <button
              type="submit"
              class="inline-flex w-full cursor-pointer items-center justify-center rounded-xl border border-neutral-200 bg-white px-4 py-2.5 text-sm font-semibold text-neutral-900 shadow-sm transition duration-150 hover:-translate-y-px hover:border-neutral-300 hover:bg-neutral-50 hover:shadow-md active:translate-y-0 active:shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-neutral-900 focus-visible:ring-offset-2"
              aria-label="FizetĂ©s Barionnal"
            >
              <img
                src={~p"/images/Barion_official_logo.png"}
                alt="Barion"
                class="h-5 w-auto"
                loading="lazy"
              />
            </button>
          </.form>
          <div
            class="mt-1.5 flex items-center justify-center gap-1.5"
            aria-label="Elfogadott kĂˇrtyĂˇk"
          >
            <span class="inline-flex h-5 items-center rounded border border-neutral-200 bg-white px-1">
              <img
                src="https://upload.wikimedia.org/wikipedia/commons/thumb/1/16/Former_Visa_%28company%29_logo.svg/960px-Former_Visa_%28company%29_logo.svg.png"
                alt="Visa"
                class="h-3.5 w-auto"
                loading="lazy"
              />
            </span>
            <span class="inline-flex h-5 items-center rounded border border-neutral-200 bg-white px-1">
              <img
                src="https://upload.wikimedia.org/wikipedia/commons/thumb/2/2a/Mastercard-logo.svg/750px-Mastercard-logo.svg.png"
                alt="Mastercard"
                class="h-3.5 w-auto"
                loading="lazy"
              />
            </span>
            <span class="inline-flex h-5 items-center rounded border border-neutral-200 bg-white px-1">
              <img
                src="https://upload.wikimedia.org/wikipedia/commons/thumb/8/80/Maestro_2016.svg/440px-Maestro_2016.svg.png"
                alt="Maestro"
                class="h-3.5 w-auto"
                loading="lazy"
              />
            </span>
          </div>
        </div>

        <.link
          href="#"
          class="mt-3 inline-flex w-full justify-center rounded-full border border-neutral-200 px-4 py-2 text-sm font-semibold text-neutral-600 transition hover:border-neutral-300"
        >
          MĂ©gse
        </.link>
      </div>
    </div>
    """
  end
end
