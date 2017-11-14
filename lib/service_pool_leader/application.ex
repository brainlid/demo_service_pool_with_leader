defmodule ServicePoolLeader.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias ServicePoolLeader.SimpleService
  # alias ServicePoolLeader.SpecialService

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    # List all child processes to be supervised
    children = [
      # Starts a worker by calling: ServicePoolLeader.Worker.start_link(arg)
      # {ServicePoolLeader.Worker, arg},
      worker(SimpleService, [])
      # supervisor(Registry, [:duplicate, SpecialService.registry_name]),
      # worker(SpecialService, []),
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ServicePoolLeader.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
