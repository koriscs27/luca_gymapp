defmodule LucaGymappWeb.PageController do
  use LucaGymappWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
