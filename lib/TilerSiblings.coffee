defer           = require('node-promise').defer

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
    @getSiblingsForZone(zoneObj).then (siblings) =>
      command = {cmd: cmd, arg1: JSON.stringify((arg1), arg2: JSON.stringify(arg2))}
      siblings.forEach (sibling) -> @sendFunction(sibling, command)

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