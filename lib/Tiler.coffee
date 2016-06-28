QuadTree 	      = require('area-qt')
defer           = require('node-promise').defer
lru             = require('lru')

lruopts =
  max: 1000
  maxAgeInMilliseconds: 1000 * 60 * 60 * 24 * 4

tileside = 20

class Tiler

  constructor:(@storageEngine)->
    @zones = new lru(lruopts)

  getTileAt:(x,y)=>
    q = defer()
    @resolveZoneFor(x,y) (zone)=>
      q.resolve(zone.getTileAt(x,y))
    q

  setTileAt:(x,y)=>

  resolveZoneFor:(x,y)=>
    q = defer()
    zone = @zones.get
    q

module.exports = Tiler