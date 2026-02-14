defmodule LucaGymappWeb.Router do
  use LucaGymappWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LucaGymappWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LucaGymappWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/rolam", PageController, :rolam
    get "/berletek", PageController, :berletek
    get "/foglalas", PageController, :booking
    get "/barion/return", BarionController, :return
    get "/barion/check/:payment_id", BarionController, :check
    get "/admin/foglalas", PageController, :admin_bookings
    post "/foglalas/personal", PageController, :create_personal_booking
    post "/foglalas/cross", PageController, :create_cross_booking
    post "/foglalas/personal/cancel", PageController, :cancel_personal_booking
    post "/foglalas/cross/cancel", PageController, :cancel_cross_booking
    post "/foglalas/admin/publish", PageController, :admin_publish_week
    post "/foglalas/admin/slot", PageController, :admin_create_slot
    post "/foglalas/admin/slot/delete", PageController, :admin_delete_slot
    post "/foglalas/admin/booking/delete", PageController, :admin_cancel_booking
    post "/foglalas/admin/upload", PageController, :admin_upload_changes
    post "/berletek/purchase", PageController, :purchase_season_pass
    post "/berletek/admin/purchase", PageController, :admin_purchase_season_pass
    get "/auth/:provider", OAuthController, :request
    get "/auth/:provider/callback", OAuthController, :callback
    get "/confirm-email", EmailConfirmationController, :show
    get "/confirm-email/new", EmailConfirmationRequestController, :new
    post "/confirm-email", EmailConfirmationRequestController, :create
    get "/password/forgot", PasswordResetController, :new
    post "/password/forgot", PasswordResetController, :create
    get "/password/reset", PasswordResetController, :edit
    patch "/password/reset", PasswordResetController, :update
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
    get "/register", RegistrationController, :new
    post "/register", RegistrationController, :create
    get "/profile", ProfileController, :show
    patch "/profile", ProfileController, :update_profile
    patch "/profile/password", ProfileController, :update_password
    patch "/profile/payments/:payment_id/refresh", ProfileController, :refresh_payment
  end

  scope "/barion", LucaGymappWeb do
    pipe_through :api

    post "/callback", BarionController, :callback
  end

  # Other scopes may use custom stacks.
  # scope "/api", LucaGymappWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:luca_gymapp, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LucaGymappWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
