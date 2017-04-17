
defer           = require('node-promise').defer
all             = require('node-promise').allOrNone
lru             = require('lru')
ZonesManager    = require './ZonesManager'
Siblings        = require('./TilerSiblings')

debug = process.env["DEBUG"]

lruopts =
  max: 1000
  maxAgeInMilliseconds: 1000 * 60 * 60 * 24 * 4


BAD_TILE = {x:0, y:0, type: -1, ore: -1, stone: -1, features:[]}

class Tiler

  constructor:(@storageEngine, @cacheEngine, @modelEngine, @myAddress, @communicationManager)->
    @dirtyZones = {}

    @zoneItemQuadTrees = {}
    @zoneEntityQuadTrees = {}
    @zoneTiles = {}
    @zmgr = new ZonesManager(@storageEngine, @cacheEngine, @modelEngine, @myAddress, @communicationManager, @zoneItemQuadTrees, @zoneEntityQuadTrees, @zoneTiles)
    @communicationManager.registerForUpdates(@myAddress, @onSiblingUpdate)

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
  onSiblingUpdate:(_command, cb)=>
    #console.log '*=============================== Tiler.onSiblingUpdate called for tiler '+@myAddress+' command -> '
    command = JSON.parse(_command)
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
      else
        #console.log 'command not found'
        #xyzzy

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
    @_setSomething(level, item, @zoneItemQuadTrees, 'items', q).then (zoneObj)=>
      if not doNotPropagate then @zmgr.siblings.sendCommand zoneObj,Siblings.CMD_ADD_ITEM,level,item
    q

  removeItem:(level, item, doNotPropagate)=>
    q = defer()
    @removeSomething(level, item, @zoneItemQuadTrees, 'items', q).then (zoneObj)=>
      if not doNotPropagate then @zmgr.siblings.sendCommand zoneObj,Siblings.CMD_REMOVE_ITEM,level,item
    q

  # Since we're getting live objects, what update does is jus making sure to propagate local changes to siblings
  updateItem:(level, item, doNotPropagate)=>
    if not doNotPropagate then @zmgr.siblings.sendCommand zoneObj,Siblings.CMD_UPDATE_ITEM,level,item
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
      if not doNotPropagate then @zmgr.siblings.sendCommand zoneObj,Siblings.CMD_ADD_ENTITY,level,entity
    q

  removeEntity:(level, entity, doNotPropagate)=>
    q = defer()
    @removeSomething(level, entity, @zoneEntityQuadTrees, 'entities',  q).then (zoneObj)=>
      if not doNotPropagate then @zmgr.siblings.sendCommand zoneObj,Siblings.CMD_REMOVE_ENTITY,level,entity
    q

  updateEntity:(level, entity, doNotPropagate)=>
    if not doNotPropagate then @zmgr.siblings.sendCommand zoneObj,Siblings.CMD_UPDATE_ENTITY,level,entity
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
      @zmgr.resolveZoneFor(level,x,y).then(
        (zone)=>
          #console.log 'getTile got zone '+zone.id+' for get tile at '+x+','+y
          if zone and zone.tileid
            ztiles = @zoneTiles[zone.tileid]
            tile = ztiles[x+'_'+y]
            #console.log 'resolving tile '+tile
            #if not tile then console.dir ztiles
            q.resolve(tile)
          else
            q.resolve(BAD_TILE)
        ,()->
          console.log 'getTileAt got reject from resolveZoneFor for level '+level+' x '+x+' y '+y
          q.reject('could not resolve zone tileid for '+(arguments.join('_')))
      )
    q

  # NOTE: this method does not serialize the zone, so either serialize explicitly after this call or use setAndPersistTiles instead
  setTileAt:(level, tile, doNotPropagate)=>
    #console.log 'setTileAt for tiler '+@myAddress+' called. doNotPropagate = '+doNotPropagate
    #console.dir arguments
    q = defer()
    if not tile or (tile and not tile.type and tile.type != 0) or (not tile.x and tile.x != 0) or (not tile.y and tile.y !=0)
      #if debug then console.dir tile
      q.reject("bad tile format")
    else
      x = tile.x
      y = tile.y
      #console.log 'trying to get zone for '+x+','+y
      @zmgr.resolveZoneFor(level,x,y).then (zone)=>
        #console.log '** found zone '+zone.id+' for set tile '+x+','+y
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
        #console.log 'found = '+found+', ztiles is..'
        #console.dir ztiles
        @dirtyZones[zone.tileid] = zone
        if not doNotPropagate then @zmgr.siblings.sendCommand zone, Siblings.CMD_SET_TILE,level,tile
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
      @zmgr.resolveZoneFor(level, tile.x, tile.y).then (zone)=>
        zonesAffected[zone.id] = zone
        tileOps.push @setTileAt(level, tile)
        if --count == 0 then all(tileOps, error).then(success, error)
    q




  #---------------------------------------------------------------------------------------------------------------------



  _getSomething:(level, x, y, qthash, q) =>
    @zmgr.resolveZoneFor(level,x,y).then(
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
    @zmgr.resolveZoneFor(level, something.x, something.y).then(
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
    @zmgr.resolveZoneFor(level, something.x, something.y).then(
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

  getZoneIdFor:(level,x,y)->@zmgr.getZoneIdFor(level,x,y)

module.exports = Tiler