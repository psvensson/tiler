defer           = require('node-promise').defer
debug = process.env["DEBUG"]

"""

The zone replica with the earliest timestamp (start-time) will act as master for the zone

The only thing the master does is persist the state each 60s (or so) of the zone, which also starts a new oplog epoch

If no new oplog epoch has been started in 120s (or so) then the next earliest timestamp replica will act as master.

The master is not elected, so if there are three replicas, and all but the lastest one goes off-line, that replica will wait for
3x60s before it persists the zone.

When one replica suspects another of being off-line, it will engage in reoeated polling and will reomve the replica from the
list of siblings for the zone after 5 retries (with 2000ms spacing), this will result in a fairly stateless replica management.

Before a replica master for a zone persist, it sends out a new epoch command to all replicas, which will be the array, keyed by epoch timestamp (in a hashtable)
where every replica stores operations made on the zone. All action results in operations and will be sent from the originating replica to all others. All will store
the operations in the same way under the same key.

When a new replica for a zone goes on-line, it will send a join command to any of the replicas, and then start to load the zone from persistent storage.
The replica receiving the command will send over the oplog for the current epoch of the zone to the newly joining replica.

The new replica will be able to see all the addresses of all other zone replicas through the global cache system (redis or pubsub equiv) and all other replicas
will directly start sending any new operations for the current epoch to the new replica.

When the replica have loaded the persistent state of the zone and applied all operations sent for the current epoch ,and after that applied all incoming operations that
was sent as part of normal operations from all other replica members, then it will be considering itself synchronized and will open for operations itself.

"""

class TilerReplication

  constructor:() ->


module.exports = TilerReplication