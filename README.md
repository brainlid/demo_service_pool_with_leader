# ServicePoolLeader

Demo project that shows how to use Registry to connect a pool of services across
multiple nodes where only one is a Leader at a time. When the Leader node goes
down, a different node's service takes over as the Leader.

## Usage

* starting multiple nodes that join as a cluster
* use observer to see how it's running
* hard kill the leader node
* what happens?
* restart that node and rejoin the cluster
* hard kill a non-leader node, what happened?, rejoin
* kind-shutdown a leader node, what happened?, rejoin

Talk about leadership election considerations

* hardware differences?
* oldest running
* other services running? Weighted value to discourage running on same node as Service X. Allows it to still work in a single-node setup.
* removing self from the pool


## Background

* [Registry is Local Only](https://elixirforum.com/t/why-is-registry-local-only/6781/10) - response by Jose Valim
> A very quick rundown of your options:
>
> * registry is local only
> * gproc has a global mode but the consensus is that it is unreliable. so consider it local only.
> * you can use :pg2 (part of OTP) if you need a distributed process group (duplicate keys)
> * you can use :global (part of OTP) if you need a distributed process registry (unique keys)
> * you can also use syn - you seem to already be aware of its cons (extra: both syn and gproc both need all of the nodes before they are started)
> * you can also use Phoenix.Tracker, which is part of the phoenix_pubsub project, as a distributed process group (duplicate keys)
* [PG2 Documentation](http://erldocs.com/current/kernel/pg2.html) - doesn't have metadata support built-in like Registry does.
* [Phoenix.Tracker](https://hexdocs.pm/phoenix_pubsub/Phoenix.Tracker.html) - Part of [Phoenix.PubSub](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html) [github](https://github.com/phoenixframework/phoenix_pubsub/tree/master/lib/phoenix/tracker)
> Provides distributed Presence tracking to processes.
>
> Tracker servers use a heartbeat protocol and CRDT to replicate presence information across a cluster in an eventually consistent, conflict-free manner. Under this design, there is no single source of truth or global process. Instead, each node runs one or more Phoenix.Tracker servers and node-local changes are replicated across the cluster and handled locally as a diff of changes.
* [How do I keep ETS in sync when I have multiple nodes at scale?](https://elixirforum.com/t/how-do-i-keep-ets-in-sync-when-i-have-multiple-nodes-at-scale/) - good discussion
> ETS is single-machine.
>
> Mnesia is multi-machine.
>
> Mnesia wraps ETS and DETS to add a distributed transaction layer, it running as in-memory mode is exactly a distributed ETS.
* [Specific reply](https://elixirforum.com/t/how-do-i-keep-ets-in-sync-when-i-have-multiple-nodes-at-scale/3828/4)
> ...
> Mnesia solves this problem, to some degree, though you have to do extra work to make it resilient to network partitions. Another approach is to have a process which synchronizes data between nodes, using CRDTs to handle conflict resolution, e.g. Phoenix.Tracker. There are some libraries which build on this capability, such as [dispatch](https://github.com/voicelayer/dispatch). You may find that the latter works better for your use case.
> ...
* [Mnesia Specific Reply](https://elixirforum.com/t/how-do-i-keep-ets-in-sync-when-i-have-multiple-nodes-at-scale/3828/7) to [this](https://elixirforum.com/t/how-do-i-keep-ets-in-sync-when-i-have-multiple-nodes-at-scale/3828/6)
> Mnesia is perfect for your use case then - writes are expensive because you have to execute a transaction across the cluster, but in your case that doesn't matter, and reads are done against ETS locally, and are extremely fast, so your performance reqs should be easy to meet.
* [gen_leader](https://github.com/knusbaum/gen_leader_revival) - Erlang project that tries to unify and modernize the GenLeader pattern. Still lagging in support.


Could create working sample project that uses a supervised GenServer that has a
register, unregister interface. It creates the entries in PG2, starts it, etc.
Then it can monitor the PID when it is added so it can be detected when one goes
down.

It could be an Application that supervises a GenServer that registers,
unregisters and monitors the PIDs as added. The Application also starts Mnesia
running in "in memory" only mode. There are other interface calls for finding
the leader service. It uses the local syned ETS table so it is fast. Has a
"send" function for sending a request to the leader service. Use Mnesia (via the
GenServer) to store the data in a local ETS table for the metadata for the
service.

Could provide a function or MFA to call when new leader should be appointed
because the current leader left or went down.

Anything to find on dealing with network splits with PG2? with Mnesia?


Mnesia is heavy on the "write" side. Requires a sync of all nodes in the
cluster. When the service membership changes (adding or removing) it is an
infrequent and very significant event. So this is an acceptable restriction.


Mnesia supports cross-node syncing of ram-tables (since it really is transient
data only). However, writing it into a library to make it easier to use would
make it harder to use an existing Mnesia DB or for your application to use
Mnesia for some other purpose.

Mnesia could be a good place to put the Bank Service's in-memory queue. So when
the running leader node goes down, the queue is up-to-date on another node
immediately and it can take over. The queue then might only need to be the
request_id that should be processed? If so, it couldn't group by card. Could
have some extra information.

------

Solution?

PG2 Group with broadcasting to all members of the group. Separate GenServer that
manages communication with the group. The other GenServer monitors your service,
to track it's pid and availability. They update their local ETS tables.  It
manages a local ETS table and on register or unregister, it broadcasts to the
others. Whenever the "metadata" for a node changes, it could be broadcast. Being
in an ETS table, it can be read by all, so a calling process could find which
node to send data to.


Request to do work could go through the managers? Could broadcast the job to
each service in the group. Then only the "leader" acts on it. Each service would
need to have the metadata of each other service to know if it was the leader.
