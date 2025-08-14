defmodule Flashwars.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FlashwarsWeb.Telemetry,
      Flashwars.Repo,
      {DNSCluster, query: Application.get_env(:flashwars, :dns_cluster_query) || :ignore},
      {Oban,
       AshOban.config(
         Application.fetch_env!(:flashwars, :ash_domains),
         Application.fetch_env!(:flashwars, Oban)
       )},
      {Phoenix.PubSub, name: Flashwars.PubSub},
      {Registry, keys: :unique, name: Flashwars.Registry},
      {DynamicSupervisor, name: Flashwars.GameTickerSupervisor, strategy: :one_for_one},
      # Start a worker by calling: Flashwars.Worker.start_link(arg)
      # {Flashwars.Worker, arg},
      # Start to serve requests, typically the last entry
      FlashwarsWeb.Endpoint,
      {Absinthe.Subscription, FlashwarsWeb.Endpoint},
      AshGraphql.Subscription.Batcher,
      {AshAuthentication.Supervisor, [otp_app: :flashwars]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Flashwars.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FlashwarsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
