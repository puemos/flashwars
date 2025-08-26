defmodule FlashwarsWeb.Router do
  use FlashwarsWeb, :router

  import Oban.Web.Router
  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :graphql do
    plug :load_from_bearer
    plug :set_actor, :user
    plug AshGraphql.Plug
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FlashwarsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
    plug FlashwarsWeb.Plugs.GuestId
  end

  pipeline :api do
    plug :accepts, ["json"]

    plug AshAuthentication.Strategy.ApiKey.Plug,
      resource: Flashwars.Accounts.User,
      # if you want to require an api key to be supplied, set `required?` to true
      required?: false

    plug :load_from_bearer
    plug :set_actor, :user
  end

  scope "/", FlashwarsWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes do
      # in each liveview, add one of the following at the top of the module:
      #
      # If an authenticated user must be present:
      # on_mount {FlashwarsWeb.LiveUserAuth, :live_user_required}
      #
      # If an authenticated user *may* be present:
      # on_mount {FlashwarsWeb.LiveUserAuth, :live_user_optional}
      #
      # If an authenticated user must *not* be present:
      # on_mount {FlashwarsWeb.LiveUserAuth, :live_no_user}

      # Authenticated org-scoped study set flow
      # Org selector and org home
      live "/orgs", OrgSelectLive, :index
      live "/orgs/:org_id", OrgHomeLive, :home

      scope "/orgs/:org_id" do
        live "/study_sets", StudySetLive.Index, :index
        live "/study_sets/new", StudySetLive.New, :new
        live "/study_sets/:id", StudySetLive.Show, :show
        live "/study_sets/:id/learn", StudySetLive.Learn, :learn
        live "/study_sets/:id/flashcards", StudySetLive.Flashcards, :flashcards
        live "/study_sets/:id/test", StudySetLive.Test, :test
      end
    end
  end

  scope "/gql" do
    pipe_through [:graphql]

    forward "/playground", Absinthe.Plug.GraphiQL,
      schema: Module.concat(["FlashwarsWeb.GraphqlSchema"]),
      socket: Module.concat(["FlashwarsWeb.GraphqlSocket"]),
      interface: :simple

    forward "/", Absinthe.Plug, schema: Module.concat(["FlashwarsWeb.GraphqlSchema"])
  end

  scope "/", FlashwarsWeb do
    pipe_through :browser

    get "/", PageController, :home
    auth_routes AuthController, Flashwars.Accounts.User, path: "/auth"
    sign_out_route AuthController

    # Remove these if you'd like to use your own authentication views
    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{FlashwarsWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    FlashwarsWeb.AuthOverrides,
                    AshAuthentication.Phoenix.Overrides.Default
                  ]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [
                  FlashwarsWeb.AuthOverrides,
                  AshAuthentication.Phoenix.Overrides.Default
                ]

    # Remove this if you do not use the confirmation strategy
    confirm_route Flashwars.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [FlashwarsWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(Flashwars.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [FlashwarsWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]
    )

    # Game rooms (public/link/private via policies); optional auth via LiveView on_mount
    live "/games/r/:id", GameRoomLive.Duel, :show
    live "/games/t/:token", GameRoomLive.Duel, :token

    # Study set sharing (link-only) — anonymous access via token
    live "/s/t/:token", StudySetLive.Token, :token
  end

  # Other scopes may use custom stacks.
  # scope "/api", FlashwarsWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:flashwars, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FlashwarsWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/" do
      pipe_through :browser

      oban_dashboard("/oban")
    end
  end

  if Application.compile_env(:flashwars, :dev_routes) do
    import AshAdmin.Router

    scope "/admin" do
      pipe_through :browser

      ash_admin "/"
    end
  end
end
