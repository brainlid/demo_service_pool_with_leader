defmodule ServicePoolLeader.Coordinator do
  @moduledoc """
  Simple Coordinator service. Separates registration and inter-service coordination from the
  services that do actual application work.
  """
  use GenServer
  require Logger
  
  @name :coordinator_service
  @pg2_group :coordinated_services
  @ets_table :coordinated_services_ets_cache

  ###
  ### CLIENT
  ###

  @doc """
  Start the SimpleService GenServer that receives work requests.
  """
  def start_link() do
    GenServer.start_link(__MODULE__, %{}, [name: @name])
  end

  @doc """
  Supports registering a service.
  """
  def register(service_pid, metadata) when is_pid(service_pid) and is_map(metadata) do
    # Register the service with all coordinators in the cluster.
    {results, _bad_nodes} = GenServer.multi_call(@name, {:register, service_pid, metadata})
    # Catastrophic failure if we fail to register with *any* coordinators
    if length(results) == 0 do
      raise "Failed to register service with any coordinators"
    end
  end

  @doc """
  Return the leader's pid for sending requests to.
  """
  def get_leader() do
    # get the members of the group
    members = :pg2.get_members(@pg2_group)
    # get the metadata for the member services
    member_metadata = services_with_metadata(members)
    # if any members don't have metadata, coordinators need to sync up.
    service_list = 
      if Enum.any?(member_metadata, &is_nil/1) do
        Logger.info("Detected missing metadata, requesting sync")
        # blocking call, once completed, can use that set of data
        local_coordinator = Process.whereis(@name)
        send(local_coordinator, {:sync, self()})
        receive do
          :synced -> 
            services_with_metadata(members)
        after
          5_000 -> 
            Logger.warn("Local coordinator :sync timed out. Using existing cache")
            member_metadata
        end
      else
        # nothing needs to be updated
        member_metadata
      end
    # select the leader from the queried (or re-queried) metadata
    select_leader(service_list)
  end
  
  @doc """
  Determine the leader and send the message to it.
  """
  def leader_call(request, timeout \\ 5_000) do
    # lookup the leader
    case get_leader() do
      nil -> {:error, :no_leader}
      pid when is_pid(pid) -> 
        # send the request to the leader. returns the result
        GenServer.call(pid, request, timeout)
    end
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
  
  # TODO: check pg2 membership and compare with known cache. If there are pg2 members that we don't have metadata for, need to sync with other coordinators first.
  #       This happens when nodes are joined to cluster after having started up. So no registration events were received except the local one only.
  
  ###
  ### SERVER CALLBACKS
  ###

  def init(state) when is_map(state) do
    # setup PG2 for tracking the services
    {:ok, _pid} = :pg2.start()
    :ok = :pg2.create(@pg2_group)
    # setup ETS table for caching the processes metadata
    :ets.new(@ets_table, [:set, :named_table, :protected])
    # send self a message after starting up to attempt an initial :sync with any other coordinators
    Process.send_after(self(), {:sync, nil}, 100)
    # setup the initial state
    new_state = Map.merge(state, %{registered: []})
    {:ok, new_state}
  end

  @doc """
  Register a service with the Coordinator.
  """
  def handle_call({:register, service_pid, metadata}, _from, %{registered: registered} = state) do
    # If this is the service_pid's local node, register it with the PG2 group.
    # The same pid can be joined to the group multiple times and 
    # will have multiple listings which we don't want.
    new_state = 
      if node(service_pid) == node() do
        # join the PG2 group
        :ok = :pg2.join(@pg2_group, service_pid)
        Logger.info("Service #{inspect service_pid} added to group #{inspect @pg2_group}")
        # track which services are directly registered by this coordinator
        Map.put(state, :registered, [service_pid | registered])
      else
        state
      end
    Logger.info("Registered #{inspect service_pid} with data #{inspect metadata}")

    # monitor the newly registered pid
    _ref = Process.monitor(service_pid)

    # cache the metadata in ETS
    add_to_cache(service_pid, metadata)
    {:reply, :ok, new_state}
  end

  @doc """
  Respond to a status request for known service entries.
  """
  def handle_call(:status, _from, %{registered: registered} = state) do
    # Lookup the metadata for the registered processes and return the list
    # as [{service_pid, metadata}]
    results = 
      Enum.map registered, fn(service) -> 
        {service, lookup_metadata(service)}
      end
    {:reply, results, state}
  end
  def handle_call(request, from, state) do
    super(request, from, state)    
  end

  @doc """
  Handle other messages like DOWN notifications for monitored processes.
  """
  def handle_info({:DOWN, _ref, :process, service_pid, _reason}, state) do
    # remove the DOWNed pid from the cache (received message by monitoring it)
    remove_from_cache(service_pid)
    {:noreply, state}
  end

  @doc """
  Request to sync up status with the other Coordinators in the cluster.
  """
  def handle_info({:sync, sender}, state) do
    # request status from all *other* nodes in the cluster (not asking self)
    {results, _bad_nodes} = GenServer.multi_call(Node.list(), @name, :status)

    # TODO: process the results to update local ETS
    IO.inspect results, label: "Yet to process"

    if sender do
      Logger.info("Notifying #{inspect sender} that sync completed")
      send(sender, :synced)
    end
    
    {:noreply, state}
  end
  def handle_info(request, state) do
    super(request, state)
  end

  ###
  ### PRIVATE
  ###

  # Add a service's pid and metadata to the ETS table to have an available cache.
  defp add_to_cache(service_pid, metadata) do
    :ets.insert(@ets_table, {service_pid, metadata})
    Logger.info("Cache updated with new service entry. pid: #{inspect service_pid}")
    :ok
  end

  # Remove a service entry from the ETS cache table.
  defp remove_from_cache(service_pid) do
    :ets.delete(@ets_table, service_pid)
    Logger.info("Cache updated and service entry removed. pid: #{inspect service_pid}")
    :ok
  end
  
  # Lookup the metadata for the service fromt the ETS cache table.
  # Returns {pid, metadata}
  defp lookup_metadata(service_pid) do
    :ets.lookup(@ets_table, service_pid)
  end
  
  # Given the list of services, return the metadata with it.
  defp services_with_metadata(pid_list) do
    Enum.map pid_list, fn(pid) -> 
      case lookup_metadata(pid) do
        [] -> nil
        [match] -> match
        _ -> 
          Logger.error("Unexpectedly received multiple ETS lookup matches for key #{inspect pid}")
          nil
      end
    end
  end
  
  # Given the member-metadata results, select who the leader is.
  defp select_leader(members_metadata) when is_list(members_metadata) do
    # choosing simply by "longest lived" member. Assuming all else is equal.
    members_metadata
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(fn({_pid, metadata}) -> Map.get(metadata, :started) end)
    |> List.first()
    |> case do
      nil -> nil
      {pid, _metadata} -> pid
    end
  end

end
