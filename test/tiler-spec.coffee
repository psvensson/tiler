expect    = require("chai").expect
Tiler     = require('../lib/Tiler')
defer     = require('node-promise').defer

debug = process.env['DEBUG']

describe "Tiler test", ()->

  storage = {}
  cache = {}
  tiler = undefined

  storageEngine =
    find: (type, prop, val)->
      q = defer()
      result = undefined
      for i,o of storage
        for k,v of o
          if k == prop and v == val then result = o
      q.resolve(result)
      q
    get: (id)->
      q = defer()
      q.resolve(storage[id])
      q
    set: (id, obj)->
      q = defer()
      storage[id] = obj
      q.resolve()
      q

  cacheEngine =
    get: (id)->
      q = defer()
      q.resolve(cache[id])
      q
    set: (id, obj)->
      q = defer()
      cache[id] = obj
      q.resolve()
      q

  modelEngine =
    createZone: (obj)->
      obj.serialize = ()-> storageEngine.set(obj.id, obj)
      q = defer()
      q.resolve(obj)
      q

  before (done)->
    tiler = new Tiler(storageEngine, cacheEngine, modelEngine)
    done()

#-----------------------------------------------------------------------------------------------------------------------

  it "should be able to calculate zoneid for positive x,y", (done)->
    zid = tiler.getZoneIdFor(1,23,25)
    expect(zid).to.equal('1_20_20')
    done()

  it "should be able to calculate zoneid for negative x,y", (done)->
    zid = tiler.getZoneIdFor(1,-44,-4)
    expect(zid).to.equal('1_-40_0')
    done()

  it "should be able to calculate zoneid for mixed x,y", (done)->
    zid = tiler.getZoneIdFor(1,114,-294)
    expect(zid).to.equal('1_100_-280')
    done()

  it "should be able to resolve and create a new zone", (done)->
    tiler.resolveZoneFor(1,114,-294).then (zoneObj)->
      expect(zoneObj.id).to.equal('1_100_-280')
      done()

  it "should be able to resolve an old, existing zone", (done)->
    tiler.resolveZoneFor(1,114,-294).then (zoneObj)->
      expect(zoneObj.id).to.equal('1_100_-280')
      done()

  it "should be able set a tile", (done)->
    tiler.setTileAt(1,79,94, {id:'foo'}).then ()->
      tiler.resolveZoneFor(1,79,94).then (zoneObj)->
        expect(zoneObj.tiles['79_94']).to.exist
        done()

  it "should be able get a tile", (done)->
    tiler.getTileAt(1,79,94, {id:'foo'}).then (tile)->
      expect(tile.id).to.equal('foo')
      done()
