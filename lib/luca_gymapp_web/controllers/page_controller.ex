defmodule LucaGymappWeb.PageController do
  use LucaGymappWeb, :controller

  def home(conn, _params) do
    form = Phoenix.Component.to_form(%{"email" => "", "password" => ""}, as: :user)
    render(conn, :home, form: form)
  end
end
