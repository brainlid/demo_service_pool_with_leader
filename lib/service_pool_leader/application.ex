defmodule ServicePoolLeader.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias ServicePoolLeader.SimpleService
  alias ServicePoolLeader.RegistryService

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    # List all child processes to be supervised
    children = [
      # Starts a worker by calling: ServicePoolLeader.Worker.start_link(arg)
      # {ServicePoolLeader.Worker, arg},
      worker(SimpleService, []),
      
      # # If you want to try it using a Registry... (does not work in cluster across nodes, local-only)
      # supervisor(Registry, [:duplicate, RegistryService.registry_name]),
      # worker(RegistryService, []),
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ServicePoolLeader.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
