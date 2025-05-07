defmodule PodcastMcpWeb.Router do
  use PodcastMcpWeb, :router

  import PodcastMcpWeb.UserAuth # Assuming your UserAuth plugs are here

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PodcastMcpWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user # Your plug to fetch user scope/info
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PodcastMcpWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", PodcastMcpWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:podcast_mcp, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PodcastMcpWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview # If you use Swoosh
    end
  end

  ## Authentication routes
  # This scope handles routes that REQUIRE a user to be authenticated.
  scope "/", PodcastMcpWeb do
    # This pipeline ensures that if a user is not authenticated, they are redirected
    # (e.g., to the login page). Your :require_authenticated_user plug handles this.
    pipe_through [:browser, :require_authenticated_user]

    # This live_session block is for LiveViews that require an authenticated user.
    # The on_mount hook is critical for loading user data into the LiveView socket.
    live_session :require_authenticated_user, # Name of the session configuration
      on_mount: [{PodcastMcpWeb.UserAuth, :require_authenticated}] do # Hook to run on mount

      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/episodes/new", EpisodeLive.New, :new

      # New route for showing an individual episode:
      # Placed here to ensure it requires authentication and runs the same on_mount hooks.
      live "/podcasts/:podcast_id/episodes/:id", EpisodeLive.Show, :show
    end

    # Standard controller actions that also require authentication
    post "/users/update-password", UserSessionController, :update_password
  end

  # This scope handles routes for users who might NOT be authenticated yet (e.g., login, register).
  scope "/", PodcastMcpWeb do
    pipe_through [:browser] # Uses the basic browser pipeline

    # This live_session is for LiveViews like registration or login.
    # The on_mount hook here might load the current user if one exists (e.g., to redirect
    # from login if already logged in) or prepare the socket for an unauthenticated user.
    live_session :current_user, # Name of this session configuration
      on_mount: [{PodcastMcpWeb.UserAuth, :mount_current_scope}] do # Hook to run on mount

      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new # Assuming this is for email confirmation link
      # Note: Phoenix's phx.gen.auth usually has /users/confirm/:token for confirmation
    end

    # Standard controller actions for login/logout
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete # Logout should clear session
  end
end
