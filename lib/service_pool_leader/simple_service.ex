defmodule ServicePoolLeader.SimpleService do
  @moduledoc """
  Simplistic GenServer that includes both processing of work and the task
  of coordination.

  ## Issues

  There are several issues with this approach and your applications needs will
  dictate if they are acceptible as-is.

  * For every work request, the :simple_service on each node in the cluster is
    queried for it's metadata. That adds network overhead and inter-node
    chatter overhead just to figure out who the "leader" is.
  * There is no caching or local-copy of the metadata for making the decision
    locally.
  * This mixes coordination management with the business logic for the purpose
    of the service. Those can be better separated.


  ## Changes??

  * Create a ServiceCoordinator that runs on each node. In the Application setup
    just say which service(s) it is coordinating for.
  * Provide the coordinator a function for MFA to call to evaluate the metadata
    responses.
  * Coordinated services need to respond to a metadata query.
  * Coordinator can locally (to the node) ping the Service on some pre-configured
    interval to collect metadata. If the metadata doesn't change from startup,
    then it only ever calls it once.
  * If the metadata changes (based on your application), the Coordinator can
    notify the other Coordinators with the updated metadata.
  * Coordinator stores the metadata in a local ETS table for fast local lookups.
  * Coordinator can ping to sync data among other Coordinators on other nodes.
  * Can be extracted out to a library.


  """

  use GenServer
  require Logger

  ###
  ### CLIENT
  ###

  @doc """
  Client interface that requests work to be done. Queries services, once all
  respond (or it times out), it selects the preferred "leader" and send the
  work to it.
  """
  def request_work(payload) do
    # ask all of the :simple_service instances in the cluster on each node to
    # give their "metadata" information so we can choose who the leader is
    # (ie. longest running)
    {multi_response, _bad_nodes} = GenServer.multi_call(:simple_service, :query)
    # re-write the responses to a simpler format
    responses = Enum.map(multi_response, fn({_node, reply}) -> reply end)
    # IO.inspect(responses, label: "Query Responses")
    # determine the leader/preferred
    case select_leader(responses) do
      nil ->
        message = "No available service found!"
        Logger.error(message)
        {:error, message}
      leader when is_pid(leader) ->
        # IO.inspect(leader, label: "Selected Leader")
        # send to the leader
        result = GenServer.call(leader, {:work, payload})
        {:ok, result}
    end
  end

  @doc """
  Logic for choosing how a leader is selected.
  """
  def select_leader(list) when is_list(list) do
    list
    |> Enum.sort_by(fn({_pid, metadata}) -> Map.get(metadata, :started) end)
    |> List.first()
    |> case do
      nil -> nil
      {pid, _metadata} -> pid
    end
  end

  @doc """
  Start the SimpleService GenServer that receives work requests.
  """
  def start_link() do
    GenServer.start_link(__MODULE__, %{}, [name: :simple_service])
  end

  ###
  ### SERVER CALLBACKS
  ###

  def init(state) when is_map(state) do
    # # "trap exits" so the `terminate` callback will fire and we can cleanup
    # Process.flag(:trap_exit, true)
    start_and_register_with_pg2()
    metadata = %{started: DateTime.to_unix(DateTime.utc_now, :microsecond)}
    {:ok, Map.merge(state, %{metadata: metadata})}
  end

  @doc """
  Respond to a request to perform work.
  """
  def handle_call({:work, payload}, _from, state) do
    # NOTE: This is where you'd farm work off to a separate Task,
    # poolboy workers, or GenStage Consumers.

    # Here we just say we've handled the work.
    Logger.info("#{inspect __MODULE__} performed work on node #{inspect node()}. Payload: #{inspect payload}")
    {:reply, payload, state}
  end

  @doc """
  Respond to a query for metadata to determine the leader.
  """
  def handle_call(:query, _from, %{metadata: metadata} = state) do
    {:reply, {self(), metadata}, state}
  end

  # @doc """
  # Callback that fires during a controlled shutdown.
  # """
  # def terminate(reason, _state) do
  #   # Unregister from the :pg2 group
  #   :pg2.leave(:simple_services, self())
  #   Logger.info("Terminating GenServer #{inspect self()}. Left group :simple_services")
  #   reason
  # end

  ###
  ### PRIVATE
  ###

  # ensure PG2 is started and register this GenServer with it.
  defp start_and_register_with_pg2() do
    {:ok, _pid} = :pg2.start()
    :ok = :pg2.create(:simple_services)
    :ok = :pg2.join(:simple_services, self())
    Logger.info("Joined :simple_services group")
  end
end
