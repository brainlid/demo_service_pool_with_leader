defmodule ServicePoolLeader do
  @moduledoc """
  Documentation for ServicePoolLeader.
  """

  alias ServicePoolLeader.SimpleService
  alias ServicePoolLeader.TrackedService
  alias ServicePoolLeader.RegistryService

  @doc """
  Request work to be performed by the leader.
  """
  def registry_work(), do: registry_work(nil)
  def registry_work(work) do
    RegistryService.request_work(work)
  end

  @doc """
  A simplistic and naive approach that demonstrates the basic concept working.
  """
  def simple_work(), do: simple_work(nil)
  def simple_work(work) do
    SimpleService.request_work(work)
  end
  
  def tracked_work(), do: tracked_work(nil)
  def tracked_work(work) do
    TrackedService.request_work(work)
  end

  @doc """
  Join the cluster.
  """
  def join() do
    # Try to connect to the other example nodes
    Node.connect(:a@localhost)
    Node.connect(:b@localhost)
    Node.connect(:c@localhost)
    Node.list()
  end

  @doc """
  Controlled shutdown of this node.
  """
  def shutdown do
    :init.stop()
  end

end
