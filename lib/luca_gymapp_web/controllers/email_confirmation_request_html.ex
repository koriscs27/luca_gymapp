defmodule LucaGymappWeb.EmailConfirmationRequestHTML do
  @moduledoc """
  This module contains confirmation request templates.
  """
  use LucaGymappWeb, :html

  embed_templates "email_confirmation_request_html/*"
end
