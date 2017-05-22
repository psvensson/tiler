defer           = require('node-promise').defer
lru             = require('lru')

Siblings        = require('./TilerSiblings')
QuadTree = require('node-trees').QuadTree

debug = process.env["DEBUG"]
TILE_SIDE = 20
BAD_TILE = {x:0, y:0, type: -1, ore: -1, stone: -1, features:[]}

lruopts =
  max: 1000
  maxAgeInMilliseconds: 1000 * 60 * 60 * 24 * 4


class ZonesManager

  constructor:(@te)->
    @zoneUnderConstruction = {}
    @postContructionCallbacks = {}
    @zones = new lru(lruopts)
    @zones.on 'evict', @onZoneEvicted
    @siblings = new Siblings(@te.myAddress, @te.communicationManager, @te.cacheEngine, @te.modelEngine)
    @te.communicationManager.registerForUpdates(@te.myAddress, @onSiblingUpdate)

  onZoneEvicted:(zoneObj) => @siblings.deRegisterAsSiblingForZone(zoneObj)

  shutdown:(zo)=>@siblings.shutdown(zo)

  onSiblingUpdate:(_command, cb)=>
    #console.log '*=============================== ZonesManager.onSiblingUpdate called for tiler '+@te.myAddress+' command -> '
    command = JSON.parse(_command)
    #console.dir command
    arg1 = command.arg1
    arg2 = command.arg2
    switch command.cmd
      when Siblings.CMD_GET_OPLOG     then @siblings.getOplog(command, cb)
      when Siblings.CMD_NEW_OPLOG_EPOCH then @siblings.newOplogEpoch(command, cb)
      else
        #console.log 'comamnd not found'
        #xyzzy

  registerZone : (q, zoneObj)=>
    arr = zoneObj.tileid.split('_')
    level = arr[0]
    x = arr[1]
    y = arr[2]
    itemQT = new QuadTree(8192, 32, 8, parseInt(x), parseInt(y))
    @te.zoneItemQuadTrees[zoneObj.tileid] = itemQT
    zoneObj.items.forEach (item) =>
      iq = defer()
      console.log 'registerZone adding existing item from store to zone '+item.id
      @te._setSomething(level, item, @te.zoneItemQuadTrees, 'items', iq, true).then (zo)=>
    entityQT = new QuadTree(8192, 32, 8, parseInt(x), parseInt(y))
    @te.zoneEntityQuadTrees[zoneObj.tileid] = entityQT
    zoneObj.entities.forEach (entity) =>
      eq = defer()
      console.log 'registerZone adding existing entity from store to zone '+entity.id
      @te._setSomething(level, entity, @te.zoneEntityQuadTrees, 'entities', eq, true).then (zo)=>
    ztiles = @te.zoneTiles[zoneObj.tileid] or {}
    zoneObj.tiles.forEach (tile) => ztiles[tile.x+'_'+tile.y] = tile
    @te.zoneTiles[zoneObj.tileid] = ztiles
    if debug then console.log 'Tiler.registerZone adds item and entity QTs for tileid '+zoneObj.tileid
    @zones.set zoneObj.tileid,zoneObj
    @siblings.registerAsSiblingForZone(zoneObj).then ()=>
      #if debug then console.log 'Tiler.registerZone back in business'
      if @zoneUnderConstruction[zoneObj.tileid] == true
        delete @zoneUnderConstruction[zoneObj.tileid]
        cbs = @postContructionCallbacks[zoneObj.tileid] or []
        cbs.forEach (cb) =>
          if debug then console.log '<------ resolving paused lookup of zone '+zoneObj.tileid
          cb()
          #if debug then console.log 'Tiler.registerZone done'
        q.resolve(zoneObj)
      else
        #if debug then console.log 'Tiler.registerZone done 2'
        q.resolve(zoneObj)

  lookupZone : (tileid,q)=>
    #if debug then console.log 'Tiler.lookupZone called for '+tileid
    lruZone = @zones.get tileid
    if lruZone
      #if debug then console.log 'Tiler.lookupZone resolving '+tileid+' from lru'
      q.resolve(lruZone)
    else
      @zoneUnderConstruction[tileid] = true
      # check to see if sibling instance have created the zone already
      @te.cacheEngine.getAllValuesFor('zonereplica_'+tileid+':*').then (exists) =>
        if exists and exists.length and exists.length > 0
          @te.storageEngine.find('Zone', 'id', tileid).then (zoneObj) =>
            if zoneObj
              if debug then console.log 'Tiler.ZoneManager.lookupZone got back zone obj '+zoneObj
              if debug then console.log 'Tiler.ZoneManager.lookupZone resolving '+tileid+' from db'
              #if debug then console.dir zoneObj
              @registerZone(q, zoneObj)
            else
              console.log '** Tiler.ZoneManager Could not find supposedly existing zone '+tileid+' !!!!!'
              q.reject(BAD_TILE)
        else
          console.log 'Tiler.lookupZone zone '+tileid+' ****************** not found, so creating new..'
          @createNewZone(tileid).then (zoneObj) =>
            @registerZone(q, zoneObj)


  resolveZoneFor:(level,x,y)=>
    q = defer()
    tid = @getZoneIdFor(level,x,y)
    underConstruction = @zoneUnderConstruction[tid]
    #if debug then console.log 'Tiler.resolveZoneFor '+tid+' under construction = '+underConstruction
    if underConstruction
      if debug then console.log '------> waiting for zone construction for '+tid
      cbs = @postContructionCallbacks[tid] or []
      cbs.push ()=>@lookupZone(tid, q)
      @postContructionCallbacks[tid] = cbs
    else
      @lookupZone(tid, q)
    q

  createNewZone: (tileid) =>
    q = defer()
    newzone =
      name: 'Zone_'+tileid
      type: 'Zone'
      id: tileid
      tileid: tileid
      items: []
      entities: []
      tiles: []

    @te.modelEngine.createZone(newzone).then (zoneObj)=>
      zoneObj.serialize().then ()=>
        @zones.set tileid,zoneObj
        q.resolve(zoneObj)
    q

  getZoneIdFor:(level,x,y) ->
    #console.log 'getZoneIdFor '+level+','+x+','+y
    xrest = (x % TILE_SIDE)
    yrest = (y % TILE_SIDE)
    #console.log 'xrest='+xrest+', yrest='+yrest
    # subtract the rest from the original coordinates to get top left of the quadrant
    if y > -1
      qtop = (y - yrest) + TILE_SIDE
    else
      qtop = y - yrest

    if x > -1
      qleft = x - xrest
    else
      qleft = (x - xrest) - TILE_SIDE
    zx = qleft
    zy = qtop
    rv = level+'_'+zx+'_'+zy
    #console.log 'qtop = '+qtop+', qleft = '+qleft+' result = '+rv
    rv


module.exports = ZonesManager