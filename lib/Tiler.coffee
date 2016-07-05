QuadTree 	      = require('area-qt')
defer           = require('node-promise').defer
lru             = require('lru')

lruopts =
  max: 1000
  maxAgeInMilliseconds: 1000 * 60 * 60 * 24 * 4

TILE_SIDE = 20

class Tiler

  constructor:(@storageEngine, @cacheEngine, @modelEngine)->
    @zones = new lru(lruopts)

  getTileAt:(x,y)=>
    q = defer()
    @resolveZoneFor(x,y).then (zone)=>
      if zone then q.resolve(zone.tiles[x+'_'+y]) else q.resolve()
    q

  setTileAt:(x,y, tile)=>
    q = defer()
    @resolveZoneFor(x,y).then (zone)=>
      zone.tiles[x+'_'+y] = tile
      zone.serialize()
      q.resolve(tile)
    q

  resolveZoneFor:(x,y)=>
    q = defer()
    tileid = @getZoneIdFor(x,y)
    lruZone = @zones.get tileid
    if lruZone
      q.resolve(lruZone)
    else
      @cacheEngine.get(tileid).then (exists) =>
        if exists
          @storageEngine.find('Zone', 'tileid', tileid).then (zone) ->
            if zone
              @zones.set tileid,zone
              q.resolve(zone)
            else
              console.log '** Tiler Could not find supposedly existing zone '+tileid+' !!!!!'
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
            @cacheEngine.set(tileid, 1).then ()->
              q.resolve(zoneObj)
    q

  getZoneIdFor:(x,y) ->
    xr = x % TILE_SIDE
    yr = y % TILE_SIDE
    zx =  (x - xr)
    zy =  (y - yr)
    zx+'_'+zy


module.exports = Tiler