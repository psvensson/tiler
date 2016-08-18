QuadTree 	      = require('area-qt')
defer           = require('node-promise').defer
all             = require('node-promise').allOrNone
lru             = require('lru')
Siblings        = require('./TilerSiblings')

debug = process.env["DEBUG"]

lruopts =
  max: 1000
  maxAgeInMilliseconds: 1000 * 60 * 60 * 24 * 4

TILE_SIDE = 20
BAD_TILE = {x:0, y:0, type: -1, ore: -1, stone: -1, features:[]}

"""
TODO:
1. Add support for manipulating items and entities
2. Detect and manage siblings through cacheEngine
3. Replicate tile, item and entity updates to siblings
"""

class Tiler

  constructor:(@storageEngine, @cacheEngine, @modelEngine, @myAddress, @sendFunction, @registerForUpdatesFunction)->
    @dirtyZones = {}
    @zoneUnderConstruction = {}
    @postContructionCallbacks = {}
    @zones = new lru(lruopts)
    @zoneItemQuadTrees = {}
    @zoneEntityQuadTrees = {}
    @zoneTiles = {}
    @zones.on 'evict', @onZoneEvicted
    @registerForUpdatesFunction(@)
    @siblings = new Siblings(@myAddress, @cacheEngine, @modelEngine, @sendFunction)


  onZoneEvicted:(zoneObj) =>
    @siblings.deRegisterAsSiblingForZone(zoneObj)

  persistDirtyZones: () =>
    q = defer()
    count = 0
    for a,b of @dirtyZones
      count++
    howmany = count
    console.log 'Tiler.persistDirtyZones persisting '+count+' zones'
    if count == 0 then q.resolve(0)
    for k,zone of @dirtyZones
      #console.log 'persistDirtyZone persisting '+zone.name
      zone.serialize().then ()=>
        if --count == 0
          @dirtyZones = {}
          q.resolve(howmany)
    q

  # This is called by a listener (for exmaple a spincycle target) that is the recipient of a call made using
  # the provided sendFunction, but from another replica
  onSiblingUpdate:(_command)=>
    command = JSON.parse(_command)
    console.log 'Tiler.onSiblingUpdate called for tiler '+@myAddress
    #console.dir command
    arg1 = command.arg1
    arg2 = command.arg2
    switch command.cmd
      when Siblings.CMD_SET_TILE      then @setTileAt(arg1, arg2, true)
      when Siblings.CMD_ADD_ITEM      then @addItem(arg1, arg2, true)
      when Siblings.CMD_REMOVE_ITEM   then @removeItem(arg1, arg2, true)
      when Siblings.CMD_UPDATE_ITEM   then @updateItem(arg1, arg2, true)
      when Siblings.CMD_ADD_ENTITY    then @addEntity(arg1, arg2, true)
      when Siblings.CMD_REMOVE_ENTITY then @removeEntity(arg1, arg2, true)
      when Siblings.CMD_UPDATE_ENTITY then @updateEntity(arg1, arg2, true)

#
# ---- NOTE: None of these get/update/add/remove methods serializes the Zone. This must be done explicitly afterwards by the caller!!
#
  createItem:(level, itemRecord)=>
    q = defer()
    if not level or not itemRecord or not itemRecord.x or not itemRecord.y
      q.reject('Tiler.createItem got bad item!!')
    else
      @modelEngine.createItem(itemRecord).then (itemObj)=>
        itemObj.serialize()
        @addItem(level, itemObj) # Will propagate
        q.resolve(itemObj)
    q

  addItem:(level, item, doNotPropagate)=>
    q = defer()
    @_setSomething(level, item, @zoneItemQuadTrees, 'items', q).then ()=>
      if not doNotPropagate then @siblings.sendCommand zoneObj,Siblings.CMD_ADD_ITEM,level,item
    q

  removeItem:(level, item, doNotPropagate)=>
    q = defer()
    @removeSomething(level, item, @zoneItemQuadTrees, 'items', q).then (zoneObj)=>
      if not doNotPropagate then @siblings.sendCommand zoneObj,Siblings.CMD_REMOVE_ITEM,level,item
    q

  # Since we're getting live objects, what update does is jus making sure to propagate local changes to siblings
  updateItem:(level, item, doNotPropagate)=>
    if not doNotPropagate then @siblings.sendCommand zoneObj,Siblings.CMD_UPDATE_ITEM,level,item
    @modelEngine.updateObject(item)

  createEntity:(level, entityRecord)=>
    q = defer()
    if not entity or not entityRecord or not entityRecord.x or not entityRecord.y
      q.reject('Tiler.createEntity got bad entity!!')
    else
      @modelEngine.createEntity(entityRecord).then (entityObj)=>
        entityObj.serialize()
        @addEntity(level, entityObj) # Will propagate
        q.resolve(entityObj)
    q

  addEntity:(level, entity, doNotPropagate)=>
    q = defer()
    @_setSomething(level, entity, @zoneEntityQuadTrees, 'entities', q).then (zoneObj)=>
      if not doNotPropagate then @siblings.sendCommand zoneObj,Siblings.CMD_ADD_ENTITY,level,entity
    q

  removeEntity:(level, entity, doNotPropagate)=>
    q = defer()
    @removeSomething(level, entity, @zoneEntityQuadTrees, 'entities',  q).then (zoneObj)=>
      if not doNotPropagate then @siblings.sendCommand zoneObj,Siblings.CMD_REMOVE_ENTITY,level,entity
    q

  updateEntity:(level, entity, doNotPropagate)=>
    if not doNotPropagate then @siblings.sendCommand zoneObj,Siblings.CMD_UPDATE_ENTITY,level,entity
    @modelEngine.updateObject(entity)

  getItemAt: (level, x, y) =>
    q = defer()
    if not level or (not x and x != 0) or (not y and y !=0)
      q.reject('Tiler.getTileAt got wrong parameters ')
    else
      @_getSomething(level, x, y, @zoneItemQuadTrees, q)
    q

  getEntityAt: (level, x, y) =>
    q = defer()
    if not level or (not x and x != 0) or (not y and y !=0)
      q.reject('Tiler.getTileAt got wrong parameters ')
    else
      @_getSomething(level, x, y, @zoneEntityQuadTrees, q)
    q

  getTileAt:(level,x,y)=>
    #console.log '............................getTileAt for '+level+' '+x+' '+y
    q = defer()
    if not level or (not x and x != 0) or (not y and y !=0)
      q.reject('Tiler.getTileAt wrong parameters ')
    else
      @resolveZoneFor(level,x,y).then(
        (zone)=>
          if zone and zone.tileid
            ztiles = @zoneTiles[zone.tileid]
            q.resolve(ztiles[x+'_'+y])
          else
            q.resolve(BAD_TILE)
        ,()->
          console.log 'getTileAt got reject from resolveZoneFor for level '+level+' x '+x+' y '+y
          q.reject('could not resolve zone tileid for '+(arguments.join('_')))
      )
    q

  # NOTE: this method does not serialize the zone, so either serialize explicitly after this call or use setAndPersistTiles instead
  setTileAt:(level, tile, doNotPropagate)=>
    if debug then console.log 'setTileAt for tiler '+@myAddress+' called'
    #console.dir arguments
    q = defer()
    if not tile or (tile and not tile.type and tile.type != 0) or (not tile.x and tile.x != 0) or (not tile.y and tile.y !=0)
      if debug then console.dir tile
      q.reject("bad tile format")
    else
      x = tile.x
      y = tile.y
      @resolveZoneFor(level,x,y).then (zone)=>
        ztiles = @zoneTiles[zone.tileid] or []
        ztiles[x+'_'+y] = tile
        @zoneTiles[zone.tileid] = ztiles
        found = false
        for i,oldtile in zone.tiles
          if oldtile.x == x and oldtile.y == y
            zone.tiles.splice i,1,tile
            found = true
            break
        if not found then zone.tiles.push tile
        @dirtyZones[zone.tileid] = zone
        if not doNotPropagate then @siblings.sendCommand zone, Siblings.CMD_SET_TILE,level,tile
        q.resolve(tile)
    q

  setAndPersistTiles:(level, tiles) =>
    q = defer()
    count = tiles.length
    zonesAffected = {}
    tileOps = []

    error = (err)->
      console.log 'setAndPersistTiles error: '+err
      q.reject(err)

    success = (tiles)->
      for k,v of zonesAffected
        v.serialize()
      q.resolve(tiles)

    tiles.forEach (tile)=>
      @resolveZoneFor(level, tile.x, tile.y).then (zone)=>
        zonesAffected[zone.id] = zone
        tileOps.push @setTileAt(level, tile)
        if --count == 0 then all(tileOps, error).then(success, error)
    q

  resolveZoneFor:(level,x,y)=>
    q = defer()

    registerZone = (q, zoneObj)=>
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
      #console.log 'registerOne adds item and entity QTs for tileid '+zoneObj.tileid
      @zones.set zoneObj.tileid,zoneObj
      @siblings.registerAsSiblingForZone(zoneObj)
      if @zoneUnderConstruction[zoneObj.tileid] = true
        delete @zoneUnderConstruction[zoneObj.tileid]
        cbs = @postContructionCallbacks[zoneObj.tileid] or []
        cbs.forEach (cb) =>
          #console.log '<------ resolving paused lookup of zone'
          cb()
      q.resolve(zoneObj)

    lookupZone = (tileid,q)=>
      lruZone = @zones.get tileid
      if lruZone
        #console.log 'resolving '+tileid+' from lru'
        q.resolve(lruZone)
      else
        @zoneUnderConstruction[tileid] = true
        # check to see if sibling instance have created the zone already
        @cacheEngine.get(tileid).then (exists) =>
          if exists
            @storageEngine.find('Zone', 'tileid', tileid).then (zoneObj) ->
              if zoneObj
                #console.log 'resolving '+tileid+' from db'
                registerZone(q, zoneObj)
              else
                console.log '** Tiler Could not find supposedly existing zone '+tileid+' !!!!!'
                q.reject(BAD_TILE)
          else
            #console.log 'zone '+tileid+' ****************** not found, so creating new..'
            @createNewZone(tileid).then (zoneObj) =>
              registerZone(q, zoneObj)

    tid = @getZoneIdFor(level,x,y)
    underConstruction = @zoneUnderConstruction[tid]
    #console.log 'resolve '+tid+' under construction = '+underConstruction
    if underConstruction
      #console.log '------> waiting for zone construction for '+tid
      cbs = @postContructionCallbacks[tid] or []
      cbs.push ()->lookupZone(tid, q)
      @postContructionCallbacks[tid] = cbs
    else
      lookupZone(tid, q)
    q

  #---------------------------------------------------------------------------------------------------------------------

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
      # store that zone exists in distributed cache so sibling do not create duplicates
      @cacheEngine.set(tileid, 1).then ()->
        q.resolve(zoneObj)
    q

  _getSomething:(level, x, y, qthash, q) =>
    @resolveZoneFor(level,x,y).then(
      (zoneObj)=>
        if zoneObj
          qt = qthash[zoneObj.tileid]
          something = qt.retrieve({x: x, y: y})
          q.resolve(something[0])
    ,()->
      console.log '_getSomething got reject from resolveZoneFor for level '+level+' x '+x+' y '+y
      q.reject('could not resolve zone tileid for '+(arguments.join('_')))
    )

  _setSomething:(level, something, qthash, propname, q, skipadd) =>
    qq = defer()
    @resolveZoneFor(level, something.x, something.y).then(
      (zoneObj)=>
        if zoneObj
          qt = qthash[zoneObj.tileid]
          qt.insert(something)
          if not skipadd
            # actually insert it into zone too!!!
            stuff = zoneObj[propname]
            for what,i in stuff
              if what.id == something.id
                found = true
                stuff[i] = something
            if not found then stuff.push something
            @dirtyZones[zoneObj.tileid] = zoneObj
          q.resolve(true)
          qq.resolve(zoneObj)
    ,()->
      console.log '_setSomething got reject from resolveZoneFor for level '+level+' x '+x+' y '+y
      q.reject('could not resolve zone tileid for level '+level+' and something '+something.type+' '+ something.id)
      qq.resolve(false)
    )
    qq

  removeSomething:(level, something, qthash, propname, q) =>
    qq = defer()
    @resolveZoneFor(level, something.x, something.y).then(
      (zoneObj)=>
        if zoneObj
          qt = qthash[zoneObj.tileid]
          qt.remove(something)
          @dirtyZones[zoneObj.tileid] = zoneObj
          stuff = zoneObj[propname]
          index = -1
          for what,i in stuff
            if what.id == something.id
              index = i
              break
          if index > -1 then stuff.splice index,1
          q.resolve(true)
          qq.resolve(zoneObj)
    ,()->
      console.log 'removeSomething got reject from resolveZoneFor for level '+level+' x '+x+' y '+y
      q.reject('could not resolve zone tileid for level '+level+' and something '+something.type+' '+ something.id)
    )
    qq

  getZoneIdFor:(level,x,y) ->
    xr = x % TILE_SIDE
    yr = y % TILE_SIDE
    zx =  (x - xr)
    zy =  (y - yr)
    level+'_'+zx+'_'+zy


module.exports = Tiler