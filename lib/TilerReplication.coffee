defer           = require('node-promise').defer
LRU             = require('lru-cache')
debug = process.env["DEBUG"]

"""

The zone replica with the earliest timestamp (start-time) will act as master for the zone

The only thing the master does is persist the state each 60s (or so) of the zone, which also starts a new oplog epoch

If no new oplog epoch has been started in 120s (or so) then the next earliest timestamp replica will act as master.

The master is not elected, so if there are three replicas, and all but the lastest one goes off-line, that replica will wait for
3x60s before it persists the zone.

When one replica suspects another of being off-line, it will engage in reoeated polling and will remove the replica from the
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


  @CMD_NEW_OPLOG_EPOCH: 'newEpoch'
  @CMD_GET_OPLOG:         'getOplog'
  @TIME_BETWEEN_MASTER_SAVES    : 10 * 60 * 1000
  @TIME_BETWEEN_MASTER_PINGS    : 2000
  @NUMBER_OF_DEFERS_TO_OLDER_REPLICAS : 3

  options :
    max: 500
    maxAge: @TIME_BETWEEN_MASTER_SAVES * 3

  constructor:(@myAddress, @cacheEngine, @communicationManager) ->
    @oplogs = {}
    @timers = {}

    #@communicationManager.registerForUpdates(@, @onSiblingUpdate)

  registerTimer: (fun, arg, time, lookup) =>
    @timers[lookup] = setInterval(
      ()=>
        console.log '--- calling timer with interval '+time
        fun(arg)
      ,time
      )
    fun(arg)

  onSiblingUpdate: (command, replyfunc)=>
    #console.log 'TilerReplication.onSiblingUpdate: '+JSON.stringify(command)
    #console.dir command
    if command.cmd == TilerReplication.CMD_GET_OPLOG
      console.log '*** TODO *** oplog get in TilerReplication is NOT IMPLEMENTED'
      replyfunc({fake:'oplog'})

  deRegisterTimer: (lookup) =>
    l = @timers[lookup]
    if l then cancelInterval(l)

  # oplogs are keyed on the modifiedAt timestamp of the zone object the oplog refer to
  # the modifiedAt timestamp is of course set by the single master for the zone
  addCommandToOplog: (zoneObj, command)=>
    oplog = @getOplogFor(zoneObj)
    command.timeStamp = Date.now()
    oplog.push command
    @oplogs[zoneObj.modifiedAt] = oplog

  getOplogFor:(zoneObj) =>
    rv = @oplogs[zoneObj.modifiedAt] or []
    rv

  getSiblingsForZone: (zoneObj) =>
    q = defer()
    @cacheEngine.getAllValuesFor('zonereplica_'+zoneObj.tileid+':*').then (replicaAddresses)=>
      q.resolve(replicaAddresses)
    return q

  getAnyOtherSiblingsForZone: (zoneObj) =>
    q = defer()
    @cacheEngine.getAllValuesFor('zonereplica_'+zoneObj.tileid+':*').then (replicaAddresses)=>
      adr = '-1'
      for replica in replicaAddresses
        adr = replica.split(",")[0]
        if adr != @myAddress
          console.log 'found an address '+adr+' that was other than mine: '+@myAddress
          break
      q.resolve(adr)
    return q

  setOurselvesAsReplica: (zoneObj, kind = 'copy') =>
    console.log 'setting address '+@myAddress+' to be replica type '+kind+' for zone '+zoneObj.id
    @cacheEngine.set('zonereplica_'+zoneObj.tileid+':'+@myAddress, @myAddress+","+Date.now()+","+kind)

  checkMasterReplicaFor: (zoneObj) =>
    #console.log 'TilerSiblings.checkMasterReplicaFor called for '+zoneObj.id
    q = defer()
    @getSiblingsForZone(zoneObj).then (siblings) =>
      #console.log 'TilerSiblings.checkMasterReplicaFor got siblings'
      #console.dir siblings
      if siblings.length == 0
        @registerOurselvesAsMasterFor(zoneObj, siblings)
        q.resolve(true)
      else
        master = false
        siblings.forEach (sibling)=>
          arr = sibling.split ','
          if arr[2] and arr[2] == 'master' then master = true
        if not master
          @registerOurselvesAsMasterFor(zoneObj, siblings).then () =>
            q.resolve(true)
        else
          q.resolve(false)
    return q

  registerOurselvesAsMasterFor: (zoneObj, siblings) =>
    #console.log 'TilerSiblings.regsiterOurselvesAsMasterFor called for zone '+zoneObj.id
    if siblings.length  < 2 or @weAreOldestReplicaFor(zoneObj, siblings)
      #console.log 'replica '+@myAddress+' registering as master for replica '+zoneObj.id
      @deRegisterTimer(zoneObj.id)
      @setOurselvesAsReplica(zoneObj, 'master')
      @registerTimer(@saveZone, zoneObj, TilerReplication.TIME_BETWEEN_MASTER_SAVES, 'master_saves_for_'+zoneObj.id)
    else
      console.log 'we are not oldest replica. Deferring...'

  weAreOldestReplicaFor: (zoneObj, siblings) =>
    rv = false
    watch = zoneObj._masterWatch or 0
    oldestSibling = 0
    we = 0
    siblings.forEach (sibling) =>
      arr = sibling.split ','
      if arr[1] > oldestSibling then oldestSibling = arr[1]
      if arr[0] == @myAddress then we = arr[1]
    if we == oldestSibling or watch > TilerReplication.NUMBER_OF_DEFERS_TO_OLDER_REPLICAS then rv = true
    zoneObj._masterWatch = ++watch
    rv

  saveZone: (zoneObj)=>
    #console.log 'master replica '+@myAddress+' serializing replica state for zone '+zoneObj.id+' to storage'
    zoneObj.serialize().then (zo)=>
      #console.log 'serializing done'
      # send out new oplog timestamp to all siblings
      command = {cmd: TilerReplication.CMD_NEW_OPLOG_EPOCH, arg1: zoneObj.modifiedAt}
      @getSiblingsForZone(zoneObj).then (siblings) =>
        siblings.forEach (sibling)=>
          adr = sibling.split(',')[0]
          if adr isnt @myAddress
            console.log 'master '+@myAddress+' for zone '+zoneObj.id+' sends out newEpoch command to copy replica '+adr+' after zone save'
            @communicationManager.sendFunction(adr, command).then (reply)->

  getAndExecuteAllOutstandingCommands: (zoneObj, peerAddress) =>
    q = defer()
    @setOurselvesAsReplica(zoneObj)
    # get oplog
    @getAnyOtherSiblingsForZone(zoneObj).then (adr)=>
      command = {cmd: TilerReplication.CMD_GET_OPLOG, arg1: zoneObj.modifiedAt}
      if adr isnt '-1'
        console.log 'TilerReplication.getAndExecuteAllOutstandingCommands sending command from us ('+@myAddress+')  to sibling '+adr
        @communicationManager.sendFunction(adr, command).then (reply)->
          console.log 'got OPLOG reply from sibling: '+JSON.stringify(reply)
          console.log '*** TODO***  OPLOG restoration NOT IMPLEMENTED'
          # start executing all commands in the oplog oldest first

          # when oplog commands have timestamps < 1s from Date.now, open the replica for use
          console.log 'getAndExecuteAllOutstandingCommands done'
          q.resolve()
       else
        console.log 'getAndExecuteAllOutstandingCommands done 2'
        q.resolve()
    return q


module.exports = TilerReplication