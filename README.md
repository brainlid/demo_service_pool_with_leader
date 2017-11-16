# ServicePoolLeader

Demo project that shows how to create a pool of services across multiple nodes
in a cluster where only one is a "Leader" at a time. When the Leader node goes
down, a different node's service takes over as the Leader.

Using only built-in Elixir/Erlang features.

## Usage

You can start multiple nodes on a single machine (each in a different terminal
window).

Start 3 named nodes. Use these same names since the `join/0` function assumes
they are named this way to make it easy for playing with it.

```bash
iex --sname a@localhost -S mix
iex --sname b@localhost -S mix
iex --sname c@localhost -S mix
```

In one of the IEx terminals, run `join/0` to link up the nodes as a cluster.

```elixir
ServicePoolLeader.join()
```

Perform some work using the simple/naive approach. Try it from different nodes.
Who does the work?

```elixir
ServicePoolLeader.simple_work()
ServicePoolLeader.simple_work(10)
ServicePoolLeader.simple_work(5)
```

The other primary example is the `ServicePoolLeader.Coordinator` module. It
coordinates the `TrackedService`.

The design decisions were to keep the complexity in the `Coordinator` and out
of the services being managed.

Experiment with those examples using the following:

```elixir
ServicePoolLeader.tracked_work()
ServicePoolLeader.tracked_work("a")
ServicePoolLeader.tracked_work(10)
```

What happens when you kill one of the services? (Can use `:observer.start` to
explore and kill it.)

What happens when you kill one of the nodes? (`ctrl+c, ctrl+c`)

Some things to experiment with:

* Start multiple nodes that join as a cluster.
* Use `:observer.start` to see how it's running, inspect ETS tables and kill things.
* Kill the leader node. What happens?
* Restart that node and rejoin the cluster.
* Kill a non-leader node, what happened? Rejoin.
* Do a kind shutdown on the leader node, what happened?, Rejoin.

## Leadership Election Options

There are a number of Leader Election strategies and options you might consider.

* Hardware differences? Prefer to run on the "big" machine?
* Other services running? Prefer to run on a different node than service Y.
  * May want to avoid two IO intensive services from thrashing the disk on the same node.
  * Allows it to still run together in a single-node setup.
* Oldest running assumes all else is equal.

This demo project uses the "longest running" service as to how a leader is
elected.

## Ideas for future experiments

* Provide a function or MFA to call when new leader should be appointed
because the current leader left or went down. Externally define the function
that selects the leader.
