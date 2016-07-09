defer           = require('node-promise').defer
debug = process.env["DEBUG"]

class TilerSiblings

  @CMD_SET_TILE:      'setTile'
  @CMD_ADD_ITEM:      'addItem'
  @CMD_REMOVE_ITEM:   'removeItem'
  @CMD_UPDATE_ITEM:   'updateItem'
  @CMD_ADD_ENTITY:    'addEntity'
  @CMD_REMOVE_ENTITY: 'removeEntity'
  @CMD_UPDATE_ENTITY: 'updateEntity'

  constructor:(@myAddress, @cacheEngine, @modelEngine, @sendFunction)->

  sendCommand:(zoneObj, cmd, arg1, arg2)=>
    #console.log 'TilerSiblings.sendCommand called for '+cmd
    #console.dir arguments
    @getSiblingsForZone(zoneObj).then (siblings) =>
      #if debug then console.log 'TilerSiblings.sendCommand got these siblings:'+JSON.stringify(siblings)
      command = {cmd: cmd, arg1: arg1, arg2: arg2}
      if arg1.toClient then command.arg1 = arg1.toClient()
      if arg2.toClient then command.arg2 = arg2.toClient()
      siblings.forEach (sibling) => if sibling isnt @myAddress then @sendFunction(sibling, command)

  registerAsSiblingForZone: (zoneObj) =>
    @cacheEngine.set 'zonereplica_'+zoneObj.tileid+':'+@myAddress, @myAddress

  deRegisterAsSiblingForZone: (zoneObj) =>
    @cacheEngine.del 'zonereplica_'+zoneObj.tileid+':'+@myAddress

  getSiblingsForZone: (zoneObj) =>
    q = defer()
    @cacheEngine.getAllValuesFor('zonereplica_'+zoneObj.tileid+':*').then (replicaAddresses)=>
      q.resolve(replicaAddresses)
    q


module.exports = TilerSiblings