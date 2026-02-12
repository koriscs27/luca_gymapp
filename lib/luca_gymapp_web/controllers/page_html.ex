defmodule LucaGymappWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use LucaGymappWeb, :html

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
    type
    |> String.replace("_", " ")
    |> String.replace_prefix("cross ", "Cross ")
    |> String.trim()
    |> String.capitalize()
  end

  def season_pass_label(type) when is_atom(type) do
    type
    |> Atom.to_string()
    |> season_pass_label()
  end

  def dummy_payment_available? do
    Application.get_env(:luca_gymapp, :dummy_payment_enabled, false)
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
            <span class="rounded-full bg-white px-3 py-1 text-neutral-700 shadow-sm">
              Ár: {format_huf(@pass.price_huf)} Ft
            </span>
            <%= if @pass.occasions > 0 do %>
              <span class="rounded-full bg-white px-3 py-1 text-neutral-700 shadow-sm">
                Alkalmak: {@pass.occasions}
              </span>
            <% else %>
              <span class="rounded-full bg-white px-3 py-1 text-neutral-700 shadow-sm">
                Időtartam: 1 hónap
              </span>
            <% end %>
          </div>
        </div>

        <div class="mt-5">
          <p class="text-xs uppercase tracking-[0.3em] text-neutral-500">Elérhető fizetések</p>

          <div class="mt-3 space-y-3" id={"payment-methods-#{@pass.key}"}>
            <div class="flex items-center justify-between gap-3 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 shadow-sm">
              <div class="flex items-center gap-3">
                <span class="inline-flex h-10 w-10 items-center justify-center rounded-full bg-emerald-600 text-sm font-semibold text-white">
                  B
                </span>
                <div>
                  <p class="text-sm font-semibold text-emerald-900">Barion</p>

                  <p class="text-xs text-emerald-700">Aktív fizetés</p>
                </div>
              </div>

              <span class="rounded-full bg-white px-3 py-1 text-xs font-semibold text-emerald-700">
                Ajánlott
              </span>
            </div>

            <img
              src="https://docs.barion.com/images/5/5b/Barion-card-strip-intl_large.png"
              alt="Barion accepted payment methods"
              class="h-11 w-auto max-w-full rounded-lg border border-neutral-200 bg-white p-2"
              loading="lazy"
            />

            <%= if dummy_payment_available?() do %>
              <div class="flex items-center justify-between gap-3 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 shadow-sm">
                <div class="flex items-center gap-3">
                  <span class="inline-flex h-10 w-10 items-center justify-center rounded-full bg-amber-600 text-sm font-semibold text-white">
                    D
                  </span>

                  <div>
                    <p class="text-sm font-semibold text-amber-900">Dummy</p>
                    <p class="text-xs text-amber-700">Csak fejlesztéshez és teszthez</p>
                  </div>
                </div>

                <span class="rounded-full bg-white px-3 py-1 text-xs font-semibold text-amber-700">
                  Dev/Test
                </span>
              </div>
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
              class="w-full rounded-full bg-[#00AEEF] px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-[#0098d6]"
            >
              Fizetés Barionnal
            </button>
          </.form>

          <%= if dummy_payment_available?() do %>
            <.form
              for={%{}}
              id={"confirm-purchase-dummy-#{@pass.key}"}
              action={~p"/berletek/purchase"}
              method="post"
            >
              <.input type="hidden" name="pass_name" value={@pass.type} />
              <.input type="hidden" name="payment_method" value="dummy" />
              <button
                type="submit"
                class="w-full rounded-full bg-amber-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-amber-500"
              >
                Dummy fizetés (dev/test)
              </button>
            </.form>
          <% end %>
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
