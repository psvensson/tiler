defer           = require('node-promise').defer
Repl            = require('./TilerReplication')

debug = process.env["DEBUG"]

class TilerSiblings

  @CMD_SET_TILE:      'setTile'
  @CMD_ADD_ITEM:      'addItem'
  @CMD_REMOVE_ITEM:   'removeItem'
  @CMD_UPDATE_ITEM:   'updateItem'
  @CMD_ADD_ENTITY:    'addEntity'
  @CMD_REMOVE_ENTITY: 'removeEntity'
  @CMD_UPDATE_ENTITY: 'updateEntity'
  @CMD_NEW_OPLOG_EPOCH: 'newEpoch'
  @CMD_GET_OPLOG:         'getOplog'


  @PAUSE_BETWEEN_REGISTER_AND_GET_OPLOG:  500

  constructor:(@myAddress, @communicationManager, @cacheEngine, @modelEngine)->
    @repl = new Repl(@myAddress, @cacheEngine, @communicationManager)

  getOplog:(command, cb)=>
    #console.log 'TilerSiblings.getOplog passing through to replication manager'
    @repl.onSiblingUpdate(command,cb)

  shutdown:(zo)=>@repl.shutdown(zo)

  newOplogEpoch: (command, cb)=>@repl.onSiblingUpdate(command,cb)

  sendCommand:(zoneObj, cmd, arg1, arg2)=>
    #console.log 'TilerSiblings.sendCommand called for '+cmd
    #console.dir arguments
    @repl.getSiblingsForZone(zoneObj).then (siblings) =>
      if debug then console.log 'TilerSiblings.sendCommand got these siblings:'+JSON.stringify(siblings)
      command = {cmd: cmd, arg1: arg1, arg2: arg2}
      # If arguments are actual spincycle objects, make sure to flatten them before packing them up and sending them away
      if arg1.toClient then command.arg1 = arg1.toClient()
      if arg2.toClient then command.arg2 = arg2.toClient()
      @repl.addCommandToOplog(zoneObj, command)
      siblings.forEach (sibling) =>
        if debug then console.log 'splitting sibling '+sibling
        adr = sibling.split(',')[0]
        if adr isnt @myAddress
          #console.log 'sending command to sibling '+adr
          if not adr or adr == 'undefined'
            console.log 'Tiler-Engine:TilerSibling::sendCommand - adr is '+adr
            xyzzy
          else
            @communicationManager.sendFunction(adr, command).then (reply)->console.log 'TilerSiblings.sendCommand got reply '+reply

  # AKA 'registerReplice'
  # We have already loaded the current Zone state fully from storage
  registerAsSiblingForZone: (zoneObj) =>
    q = defer()
    console.log 'TilerSiblings.registerAsSiblingForZone '+zoneObj.tileid+' myAddress = '+@myAddress
    console.dir zoneObj
    # Get up to speed with current zone changes by requesting oplog from random sibling
    # Registering with the redis-like cache-engine will make all subsequent operations from all other siblings/replicas replicate to us from now on
    @repl.checkMasterReplicaFor(zoneObj).then (becameMaster)=>
      console.log 'master checked. becameMaster = '+becameMaster
      if becameMaster
        console.log '================== registerAsSiblingForZone done'
        q.resolve()
      else
        @repl.setOurselvesAsReplica(zoneObj)
        setTimeout(
          ()=>
            # We ask a random replica to get their oplog that started with the save timestamp of the zone just loaded
            @repl.getAndExecuteAllOutstandingCommands(zoneObj).then ()=>
              console.log '==================  registerAsSiblingForZone done 2'
              q.resolve()
          ,@PAUSE_BETWEEN_REGISTER_AND_GET_OPLOG
        )
    return q

  deRegisterAsSiblingForZone: (zoneObj) => @repl.shutdown(zoneObj)


module.exports = TilerSiblings