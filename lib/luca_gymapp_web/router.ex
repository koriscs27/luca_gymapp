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
    get "/berletek", PageController, :berletek
    get "/foglalas", PageController, :booking
    post "/foglalas/personal", PageController, :create_personal_booking
    post "/foglalas/cross", PageController, :create_cross_booking
    post "/foglalas/personal/cancel", PageController, :cancel_personal_booking
    post "/foglalas/cross/cancel", PageController, :cancel_cross_booking
    post "/berletek/purchase", PageController, :purchase_season_pass
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
