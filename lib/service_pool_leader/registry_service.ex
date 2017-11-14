defmodule ServicePoolLeader.RegistryService do
  @moduledoc """
  The service that belongs to a Registry pool and has one active leader in the
  pool. Other non-leader services in the pool sit idle but are available as a
  quick fail-over backup.
  """

  use GenServer
  require Logger

  @registry :special_service_registry
  def registry_name do
    @registry
  end

  ###
  ### CLIENT
  ###

  @doc """
  Start the GenServer that receives work requests.

  ## Options

  * name - defaults to use `:registry_service`. Overridable for testing.

  """
  def start_link(opts \\ []) when is_list(opts) do
    name = Keyword.get(opts, :name, :registry_service)
    GenServer.start_link(__MODULE__, %{}, [name: name])
  end

  @doc """
  Client interface that requests work to be done. Processes on any node call
  their local service's client function and it directs it appropriately.
  """
  def request_work(payload) do
    # lookup the services
    found = Registry.lookup(@registry, __MODULE__)
    IO.inspect found
    # determine the leader/preferred
    case select_leader(found) do
      nil ->
        message = "No available service found!"
        Logger.error(message)
        {:error, message}
      leader when is_pid(leader) ->
        IO.inspect leader
        # send to the leader
        result = GenServer.call(leader, {:work, payload})
        {:ok, result}
    end
  end

  @doc """
  Logic for choosing how a leader is selected.
  """
  def select_leader(list) when is_list(list) do
    sorted = Enum.sort_by(list, fn({_pid, metadata}) -> Map.get(metadata, :started) end)
    case List.first(sorted) do
      nil -> nil
      {pid, _metadata} -> pid
    end
  end

  ###
  ### SERVER CALLBACKS
  ###

  def init(state) when is_map(state) do
    # register this GenServer in the registry
    # The "key" used in the registry is this module. The "value" is not used.
    # This would otherwise be available metadata or whatever we wanted to track.
    # Since it is unused, setting it to `nil`.
    metadata = %{started: DateTime.to_unix(DateTime.utc_now, :microsecond)}
    Registry.register(@registry, __MODULE__, metadata)
    {:ok, Map.merge(state, %{metadata: metadata})}
  end

  def handle_call({:work, payload}, _from, state) do
    # NOTE: This is where you'd farm work off to a separate Task,
    # poolboy workers, or GenStage Consumers.

    # Here we just say we've handled the work.
    Logger.info("Performed work on node #{inspect node()}. Payload: #{inspect payload}")
    {:reply, payload, state}
  end

end
