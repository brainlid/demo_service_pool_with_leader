defmodule ServicePoolLeader.TrackedService do
  @moduledoc """
  A service that uses a Coordinator to track and coordinate leadership
  across nodes.
  """
  use GenServer
  require Logger
  alias ServicePoolLeader.Coordinator

  ###
  ### CLIENT
  ###

  @doc """
  Start the TrackedService GenServer that receives work requests.
  """
  def start_link() do
    GenServer.start_link(__MODULE__, %{}, [name: :tracked_service])
  end

  @doc """
  Client interface that requests work to be done. Defers leader tracking to the
  Coordinator.
  """
  def request_work(payload) do
    Coordinator.leader_call({:work, payload})
  end

  ###
  ### SERVER CALLBACKS
  ###

  def init(state) when is_map(state) do
    metadata = %{started: DateTime.to_unix(DateTime.utc_now, :microsecond)}
    Coordinator.register(self(), metadata)
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

end
