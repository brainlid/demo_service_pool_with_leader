defmodule ServicePoolLeader.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias ServicePoolLeader.SimpleService
  alias ServicePoolLeader.Coordinator
  alias ServicePoolLeader.TrackedService
  alias ServicePoolLeader.RegistryService

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    # List all child processes to be supervised
    children = [
      # Starts a worker by calling: ServicePoolLeader.Worker.start_link(arg)
      # {ServicePoolLeader.Worker, arg},
      worker(SimpleService, []),
      
      # Starts a coordinator service that can manage tracking the registered services.
      worker(Coordinator, []),
      
      # Starts the service that uses the Coordinator and registers itself with it.
      worker(TrackedService, []),

      # # If you want to try it using a Registry... (does not work in cluster across nodes, local-only)
      # # Commented out by default as it clutters the :observer.start Application view and doesn't 
      # # work for our goals.
      # supervisor(Registry, [:duplicate, RegistryService.registry_name]),
      # worker(RegistryService, []),
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ServicePoolLeader.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
