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
end
