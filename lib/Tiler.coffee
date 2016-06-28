QuadTree 	      = require('area-qt')
defer           = require('node-promise').defer
lru             = require('lru')

lruopts =
  max: 1000
  maxAgeInMilliseconds: 1000 * 60 * 60 * 24 * 4

TILE_SIDE = 20

class Tiler

  constructor:(@storageEngine)->
    @zones = new lru(lruopts)

  getTileAt:(x,y)=>
    q = defer()
    @resolveZoneFor(x,y) (zone)=>
      if zone then q.resolve(zone.getTileAt(x,y)) else q.resolve()
    q

  setTileAt:(x,y)=>

  resolveZoneFor:(x,y)=>
    q = defer()
    tileid = @getZoneIdFor(x,y)
    @storageEngine.find('Zone', 'tileid', tileid).then (zone) -> q.resolve(zone)
    q

  getZoneIdFor:(x,y) ->
    xs = Math.sign(x)
    ys = Math.sign(y)
    #console.log 'xs = '+xs+' ys = '+ys
    xr = x % TILE_SIDE
    yr = y % TILE_SIDE
    zx =  (x - xr)
    zy =  (y - yr)
    #console.log 'zx = '+zx+' zy = '+zy
    zx+'_'+zy


module.exports = Tiler