# Research and Background

* [Registry is Local Only](https://elixirforum.com/t/why-is-registry-local-only/6781/10) - response by Jose Valim
> A very quick rundown of your options:
>
> * registry is local only
> * gproc has a global mode but the consensus is that it is unreliable. so consider it local only.
> * you can use :pg2 (part of OTP) if you need a distributed process group (duplicate keys)
> * you can use :global (part of OTP) if you need a distributed process registry (unique keys)
> * you can also use [syn](https://github.com/ostinelli/syn - you seem to already be aware of its cons (extra: both syn and gproc both need all of the nodes before they are started)
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


## Mnesia

Mnesia is heavy on the "write" side. Requires a sync of all nodes in the
cluster. When the service membership changes (adding or removing) it is an
infrequent and very significant event. So this is an acceptable restriction.

Mnesia supports cross-node syncing of ram-tables (since it really is transient
data only). However, writing it into a library to make it easier to use would
make it harder to use an existing Mnesia DB or for your application to use
Mnesia for some other purpose.


## Leader Election Strategies

* https://docs.microsoft.com/en-us/azure/architecture/patterns/leader-election
