QuadTree 	      = require('area-qt')
defer           = require('node-promise').defer
all             = require('node-promise').allOrNone
lru             = require('lru')

lruopts =
  max: 1000
  maxAgeInMilliseconds: 1000 * 60 * 60 * 24 * 4

TILE_SIDE = 20
BAD_TILE = {x:0, y:0, type: -1, ore: -1, stone: -1, features:[]}

class Tiler

  constructor:(@storageEngine, @cacheEngine, @modelEngine)->
    @zones = new lru(lruopts)

  getTileAt:(level,x,y)=>
    q = defer()
    @resolveZoneFor(level,x,y).then(
      (zone)->
        if zone then q.resolve(zone.tiles[x+'_'+y]) else q.resolve(BAD_TILE)
      ,()->
        console.log 'getTileAt got reject from resolveZoneFor for level '+level+' x '+x+' y '+y
        q.reject(BAD_TILE)
    )
    q

  setTileAt:(level, tile)=>
    q = defer()
    if not tile or (tile and not tile.type) or not tile.x or not tile.y
      q.reject("bad tile format")
    else
      x = tile.x
      y = tile.y
      @resolveZoneFor(level,x,y).then (zone)=>
        zone.tiles[x+'_'+y] = tile
        #zone.serialize()
        #console.log 'setTileAt for '+tile
        q.resolve(tile)
    q

  setAndPersistTiles:(level, tiles) =>
    q = defer()

    zonesAffected = {}
    tileOps = []

    error = (err)->
      console.log 'setAndPersistTiles error: '+err
      q.reject(err)

    success = (tiles)->
      #console.log 'setAndPersistTiles success'
      for k,v of zonesAffected
        #console.log 'setAndPersistTiles serializing zone '+v.id
        v.serialize()
      q.resolve(tiles)

    count = tiles.length
    tiles.forEach (tile)=>
      @resolveZoneFor(level, tile.x, tile.y).then (zone)=>
        zonesAffected[zone.id] = zone
        #console.log 'adding tileop for tile '+tile
        tileOps.push @setTileAt(level, tile)
        if --count == 0 then all(tileOps, error).then(success, error)
    q

  resolveZoneFor:(level,x,y)=>
    q = defer()
    tileid = @getZoneIdFor(level,x,y)
    lruZone = @zones.get tileid
    if lruZone
      q.resolve(lruZone)
    else
      # check to see if sibling instance have created the zone already
      @cacheEngine.get(tileid).then (exists) =>
        if exists
          @storageEngine.find('Zone', 'tileid', tileid).then (zone) ->
            if zone
              @zones.set tileid,zone
              q.resolve(zone)
            else
              console.log '** Tiler Could not find supposedly existing zone '+tileid+' !!!!!'
              q.reject(BAD_TILE)
        else
          newzone =
            type: 'Zone'
            id: tileid
            tileid: tileid
            items: {}
            entities: {}
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