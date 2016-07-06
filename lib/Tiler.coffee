QuadTree 	      = require('area-qt')
defer           = require('node-promise').defer
lru             = require('lru')

lruopts =
  max: 1000
  maxAgeInMilliseconds: 1000 * 60 * 60 * 24 * 4

TILE_SIDE = 20
BAD_TILE = {type: -1, ore: -1, stone: -1, features:[]}

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

  setTileAt:(level,x,y, tile)=>
    q = defer()
    if not tile or (tile and not tile.type)
      q.reject(BAD_TILE)
    else
      @resolveZoneFor(level,x,y).then (zone)=>
        zone.tiles[x+'_'+y] = tile
        zone.serialize()
        q.resolve(tile)
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