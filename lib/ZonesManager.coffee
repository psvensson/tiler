defer           = require('node-promise').defer
lru             = require('lru')

Siblings        = require('./TilerSiblings')
QuadTree 	      = require('area-qt')

debug = process.env["DEBUG"]
TILE_SIDE = 20
lruopts =
  max: 1000
  maxAgeInMilliseconds: 1000 * 60 * 60 * 24 * 4


class ZonesManager

  constructor:(@storageEngine, @cacheEngine, @modelEngine, @myAddress, @communicationManager, @zoneItemQuadTrees, @zoneEntityQuadTrees,@zoneTiles)->
    @zoneUnderConstruction = {}
    @postContructionCallbacks = {}
    @zones = new lru(lruopts)
    @zones.on 'evict', @onZoneEvicted
    @siblings = new Siblings(@myAddress, @communicationManager, @cacheEngine, @modelEngine)
    @communicationManager.registerForUpdates(@myAddress, @onSiblingUpdate)

  onZoneEvicted:(zoneObj) => @siblings.deRegisterAsSiblingForZone(zoneObj)

  shutdown:(zo)=>@siblings.shutdown(zo)

  onSiblingUpdate:(_command, cb)=>
    #console.log '*=============================== ZonesManager.onSiblingUpdate called for tiler '+@myAddress+' command -> '
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
    x = arr[1]
    y = arr[2]
    itemQT = new QuadTree(x:x, y:y, height: TILE_SIDE, width: TILE_SIDE)
    @zoneItemQuadTrees[zoneObj.tileid] = itemQT
    zoneObj.items.forEach (item) => @_setSomething(level, item, itemQT, 'items', q, true).then (zo)=>
    entityQT = new QuadTree(x:x, y:y, height: TILE_SIDE, width: TILE_SIDE)
    @zoneEntityQuadTrees[zoneObj.tileid] = entityQT
    zoneObj.entities.forEach (entity) => @_setSomething(level, entity, entityQT, 'entities', q, true).then (zo)=>
    ztiles = @zoneTiles[zoneObj.tileid] or {}
    zoneObj.tiles.forEach (tile) => ztiles[tile.x+'_'+tile.y] = tile
    @zoneTiles[zoneObj.tileid] = ztiles
    if debug then console.log 'Tiler.registerZone adds item and entity QTs for tileid '+zoneObj.tileid
    @zones.set zoneObj.tileid,zoneObj
    @siblings.registerAsSiblingForZone(zoneObj).then ()=>
#if debug then console.log 'Tiler.registerZone back in business'
      if @zoneUnderConstruction[zoneObj.tileid] == true
        delete @zoneUnderConstruction[zoneObj.tileid]
        cbs = @postContructionCallbacks[zoneObj.tileid] or []
        cbs.forEach (cb) =>
          if debug then console.log '<------ resolving paused lookup of zone'
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
      @cacheEngine.get('Zone',tileid).then (exists) =>
        if exists
          @storageEngine.find('Zone', 'tileid', tileid).then (zoneObj) =>
            if debug then console.log 'Tiler.lookupZone got back zone obj'
            if zoneObj
              if debug then console.log 'Tiler.lookupZone resolving '+tileid+' from db'
              @registerZone(q, zoneObj)
            else
              if debug then console.log '** Tiler Could not find supposedly existing zone '+tileid+' !!!!!'
              q.reject(BAD_TILE)
        else
          if debug then console.log 'Tiler.lookupZone zone '+tileid+' ****************** not found, so creating new..'
          @createNewZone(tileid).then (zoneObj) =>
            @registerZone(q, zoneObj)


  resolveZoneFor:(level,x,y)=>
    q = defer()
    tid = @getZoneIdFor(level,x,y)
    underConstruction = @zoneUnderConstruction[tid]
    if debug then console.log 'Tiler.resolveZoneFor '+tid+' under construction = '+underConstruction
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

    @modelEngine.createZone(newzone).then (zoneObj)=>
      zoneObj.serialize()
      @zones.set tileid,zoneObj
      q.resolve(zoneObj)
    q

  getZoneIdFor:(level,x,y) ->
    xr = x % TILE_SIDE
    yr = y % TILE_SIDE
    zx =  (x - xr)
    zy =  (y - yr)
    level+'_'+zx+'_'+zy



module.exports = ZonesManager