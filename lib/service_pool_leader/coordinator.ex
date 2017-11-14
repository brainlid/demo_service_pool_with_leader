defmodule ServicePoolLeader.Coordinator do
  @moduledoc """
  Simple Coordinator service. Separates registration and inter-service coordination from the
  services that do actual application work.
  """
  use GenServer
  require Logger

  @pg2_group :coordinated_services
  @ets_table :coordinated_services_ets_cache

  ###
  ### CLIENT
  ###

  @doc """
  Start the SimpleService GenServer that receives work requests.
  """
  def start_link() do
    GenServer.start_link(__MODULE__, %{}, [name: :coordinator_service])
  end

  @doc """
  Supports registering a service.
  """
  def register(service_pid, metadata) when is_pid(service_pid) and is_map(metadata) do
    GenServer.call(:coordinator_service, {:register, service_pid, metadata})
  end

  @doc """
  Notify Coordinators to update their tracked memberships. Meaning we have
  reason to believe the membership list has changed. (DO THIS? CAN JUST DO IT
  WHEN A NEW REGISTER HAPPENS?)
  """
  def update_memberships() do
    GenServer.multi_call(:coordinator_service, :update_memberships)
    # TODO: log it? what to return?
  end

  @doc """
  Determine the leader and send the message to it.
  """
  def leader_call(request, timeout \\ 5_000) do
    # TODO: lookup the leader

    # TODO: sending it to all!!
    GenServer.multi_call([node() | Node.list], :tracked_service, request, timeout)
  end

  # TODO: periodically, use the :pg2.members to remove ETS entries for PIDs that
  #       no longer exist.
  # TODO: Coordinator can broadcast to other Coordinators when a new registration
  #       takes place. Coordinator could Monitor it's local service. When local
  #       service is replaced or goes down, can broadcast to other's to update
  #       their membership tables.
  # TODO: On registration, broadcast to other coordinators the metadata of the
  #       new service.
  # TODO: metadata update function could be created as well.

  # TODO: problem is dealing with 2nd and 3rd Coordinator to start (staggered node startup)
  #       and they don't have the previously registered nodes.
  #       On startup, could lookup PG2 membership and if there are unknown entries,
  #       perform a multi_call sync? Could require the service to answer a metadata query. Don't like that.
  #       The Coordinator sync could just be on startup of the coord service that
  #       it queries all nodes (all other nodes?) for their caches?
  # TODO: inter-coordinator request for copy of cache values
  # TODO: register can be multi_call to all. Monitoring cross-node DOWN, etc.
  # TODO: on sending the request to the leader, could check Process.is_alive?.
  #       better option is to attempt send, if it fails, send to next and update
  #       the cache (via message to local coord service to sync cache to PG2 membership)

  ###
  ### SERVER CALLBACKS
  ###

  def init(state) when is_map(state) do
    # setup PG2 for tracking the services
    {:ok, _pid} = :pg2.start()
    :ok = :pg2.create(@pg2_group)
    # setup ETS table for caching the processes metadata
    :ets.new(@ets_table, [:set, :named_table, :protected])
    # new_state = %{services: []}
    {:ok, state}
  end

  @doc """
  Register a service with the Coordinator.
  """
  def handle_call({:register, service_pid, metadata}, _from, state) do
    # join the PG2 group
    :ok = :pg2.join(@pg2_group, service_pid)
    Logger.info("Registered #{inspect service_pid} with data #{inspect metadata}")

    # monitor the newly registered pid
    _ref = Process.monitor(service_pid)

    # cache the metadata in ETS
    add_to_cache(service_pid, metadata)
    {:reply, :ok, state}
  end

  @doc """
  Respond to a query for metadata to determine the leader.
  """
  def handle_call(:query, _from, %{metadata: metadata} = state) do
    {:reply, {self(), metadata}, state}
  end

  def handle_info({:DOWN, _ref, :process, service_pid, _reason}, state) do
    # remove the DOWNed pid from the cache
    remove_from_cache(service_pid)
    {:noreply, state}
  end
  def handle_info(message, state) do
    # Do the desired work here
    IO.inspect message, label: "handle_info message"
    {:noreply, state}
  end

  ###
  ### PRIVATE
  ###

  # TODO: setup ETS table

  defp add_to_cache(service_pid, metadata) do
    :ets.insert(@ets_table, {service_pid, metadata})
    Logger.info("Cache updated with new service entry. pid: #{inspect service_pid}")
    :ok
  end

  defp remove_from_cache(service_pid) do
    :ets.delete(@ets_table, service_pid)
    Logger.info("Cache updated and service entry removed. pid: #{inspect service_pid}")
    :ok
  end

end
