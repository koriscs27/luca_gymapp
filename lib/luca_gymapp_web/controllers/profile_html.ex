defmodule LucaGymappWeb.ProfileHTML do
  @moduledoc """
  This module contains profile templates.
  """
  use LucaGymappWeb, :html

  embed_templates "profile_html/*"

  def format_date(%Date{} = date) do
    Calendar.strftime(date, "%Y.%m.%d")
  end

  def format_date(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_date()
    |> format_date()
  end

  def format_date(_date), do: "-"

  def format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y.%m.%d %H:%M")
  end

  def format_datetime(_), do: "-"

  def format_booking_type("personal"), do: "Személyi"
  def format_booking_type("cross"), do: "Cross"
  def format_booking_type(_type), do: "Egyéb"

  def format_payment_method("barion"), do: "Barion"
  def format_payment_method("dummy"), do: "Dummy"
  def format_payment_method("cash"), do: "Készpénz"
  def format_payment_method(_), do: "Ismeretlen"

  def format_payment_status("pending"), do: "Folyamatban"
  def format_payment_status("authorized"), do: "Jóváhagyva"
  def format_payment_status("paid"), do: "Sikeres"
  def format_payment_status("failed"), do: "Sikertelen"
  def format_payment_status(_), do: "Ismeretlen"

  def format_huf(amount) when is_integer(amount) do
    amount
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(...)(?=.)/, "\\1 ")
    |> String.reverse()
  end

  def format_huf(_), do: "0"

  def season_pass_label(type) when is_binary(type) do
    type
    |> String.trim()
    |> String.split("_", trim: true)
    |> List.last()
    |> case do
      nil -> "-"
      value -> String.capitalize(value)
    end
  end

  def season_pass_label(_), do: "-"
end
