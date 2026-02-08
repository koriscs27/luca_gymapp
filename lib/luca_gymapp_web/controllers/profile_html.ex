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

  def format_booking_type("personal"), do: "Személyi"
  def format_booking_type("cross"), do: "Cross"
  def format_booking_type(_type), do: "Egyéb"
end
