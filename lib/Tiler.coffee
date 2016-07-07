QuadTree 	      = require('area-qt')
defer           = require('node-promise').defer
all             = require('node-promise').allOrNone
lru             = require('lru')
Siblings        = require('./TilerSiblings')

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

  constructor:(@storageEngine, @cacheEngine, @modelEngine, @myAddress, @sendFunction)->
    @zones = new lru(lruopts)
    @zoneItemQuadTrees = {}
    @zoneEntityQuadTrees = {}
    @zones.on 'evict', @onZoneEvicted
    @siblings = new Siblings(@myAddress, @cacheEngine, @modelEngine, @sendFunction)


  onZoneEvicted:(zoneObj) =>
    @siblings.deRegisterAsSiblingForZone(zoneObj)

  # This is called by a listener (for exmaple a spincycle target) that is the recipient of a call made using
  # the provided sendFunction, but form another replica
  onSiblingUpdate:(command)=>
    console.log 'Tiler.onSiblingUpdate called'
    arg1 = JSON.pars(command.arg1)
    arg2 = JSON.pars(command.arg2)
    switch command.cmd
      when Siblings.CMD_SET_TILE      then @setTileAt(arg1, arg2, true)
      when Siblings.CMD_ADD_ITEM      then @addItem(arg1, arg2, true)
      when Siblings.CMD_REMOVE_ITEM   then @removeItem(arg1, arg2, true)
      when Siblings.CMD_UPDATE_ITEM   then @updateItem(arg1, arg2, true)
      when Siblings.CMD_ADD_ENTITY    then @addEntity(arg1, arg2, true)
      when Siblings.CMD_REMOVE_ENTITY then @removeEntity(arg1, arg2, true)
      when Siblings.CMD_UPDATE_ENTITY then @updateEntity(arg1, arg2, true)


  addItem:(level, item, doNotPropagate)=>
    @resolveZoneFor(level, item.x, item.y).then (zoneObj)=>
      zoneObj.items.push item
      itemQT = @zoneItemQuadTrees[zoneObj.tileid]
      itemQT.insert item
      if not doNotPropagate then @siblings.sendCommand Siblings.CMD_ADD_ITEM,level,item

  removeItem:(level, item, doNotPropagate)=>
    @resolveZoneFor(level, item.x, item.y).then (zone)=>

  updateItem:(level, item, doNotPropagate)=>
    @resolveZoneFor(level, item.x, item.y).then (zone)=>

  addEntity:(level, entity, doNotPropagate)=>
    @resolveZoneFor(level, entity.x, entity.y).then (zone)=>
      zoneObj.entities.push entity
      entityQT = @zoneItemQuadTrees[zoneObj.tileid]
      entityQT.insert entity
      if not doNotPropagate then @siblings.sendCommand Siblings.CMD_ADD_ENTITY,level,entity

  removeEntity:(level, entity, doNotPropagate)=>
    @resolveZoneFor(level, entity.x, entity.y).then (zone)=>

  updateEntity:(level, entity, doNotPropagate)=>
    @resolveZoneFor(level, entity.x, entity.y).then (zone)=>


  getItemAt: (level, x, y) =>
    q = defer()
    @resolveZoneFor(level,x,y).then(
      (zoneObj)=>
        if zoneObj
          itemQT = @zoneItemQuadTrees[zoneObj.tileid]
          item = itemQT.retrieve({x: x, y: y})
          #console.log 'getItemAt '+x+' '+y+' got item '+item
          #console.dir item
          q.resolve(item[0])
    ,()->
      console.log 'getItemAt got reject from resolveZoneFor for level '+level+' x '+x+' y '+y
      q.reject('could not resolve zone tileid for '+(arguments.join('_')))
    )
    q

  getTileAt:(level,x,y)=>
    q = defer()
    @resolveZoneFor(level,x,y).then(
      (zone)->
        if zone then q.resolve(zone.tiles[x+'_'+y]) else q.resolve(BAD_TILE)
      ,()->
        console.log 'getTileAt got reject from resolveZoneFor for level '+level+' x '+x+' y '+y
        q.reject('could not resolve zone tileid for '+(arguments.join('_')))
    )
    q

  # NOTE: this method does not serialize the zone, so either serialize explicitly after this call or use setAndPersistTiles instead
  setTileAt:(level, tile, doNotPropagate)=>
    q = defer()
    if not tile or (tile and not tile.type) or not tile.x or not tile.y
      q.reject("bad tile format")
    else
      x = tile.x
      y = tile.y
      @resolveZoneFor(level,x,y).then (zone)=>
        zone.tiles[x+'_'+y] = tile
        if not doNotPropagate then @siblings.sendCommand Siblings.CMD_SET_TILE,level,tile
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
      entityQT = new QuadTree(x:x, y:y, height: TILE_SIDE, width: TILE_SIDE)
      @zoneEntityQuadTrees[zoneObj.tileid] = entityQT
      #console.log 'registerOne adds item and entity QTs for tileid '+zoneObj.tileid
      @zones.set tileid,zoneObj
      @siblings.registerAsSiblingForZone(zoneObj)
      q.resolve(zoneObj)

    tileid = @getZoneIdFor(level,x,y)
    lruZone = @zones.get tileid
    if lruZone
      q.resolve(lruZone)
    else
      # check to see if sibling instance have created the zone already
      #console.log 'could not resolve zoneObj for '+tileid
      #console.dir @zones
      @cacheEngine.get(tileid).then (exists) =>
        if exists
          @storageEngine.find('Zone', 'tileid', tileid).then (zone) ->
            if zone
              registerZone(q, zoneObj)
            else
              console.log '** Tiler Could not find supposedly existing zone '+tileid+' !!!!!'
              q.reject(BAD_TILE)
        else
          @createNewZone(tileid).then (zoneObj) =>
            registerZone(q, zoneObj)

    q

  createNewZone: (tileid) =>
    q = defer()
    newzone =
      type: 'Zone'
      id: tileid
      tileid: tileid
      items: []
      entities: []
      tiles: {}

    @modelEngine.createZone(newzone).then (zoneObj)=>
      zoneObj.serialize()
      @zones.set tileid,zoneObj
      # store that zone exists in distributed cache so sibling do not create duplicates
      @cacheEngine.set(tileid, 1).then ()->
        q.resolve(zoneObj)
    q


  getZoneIdFor:(level,x,y) ->
    xr = x % TILE_SIDE
    yr = y % TILE_SIDE
    zx =  (x - xr)
    zy =  (y - yr)
    level+'_'+zx+'_'+zy


module.exports = Tiler