defmodule ServicePoolLeader do
  @moduledoc """
  Documentation for ServicePoolLeader.
  """

  alias ServicePoolLeader.SimpleService
  alias ServicePoolLeader.SpecialService

  @doc """
  Request work to be performed by the leader.
  """
  def request_work(), do: request_work(nil)
  def request_work(work) do
    SpecialService.request_work(work)
  end

  @doc """
  A simplistic and naive approach that demonstrates the basic concept working.
  """
  def naive(), do: naive(nil)
  def naive(work) do
    SimpleService.request_work(work)
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
