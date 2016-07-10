expect    = require("chai").expect
Tiler     = require('../lib/Tiler')
defer     = require('node-promise').defer

debug = process.env['DEBUG']

describe "Tiler test", ()->

  storage = {}
  cache = {}
  tileCluster = {}
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
    getAllValuesFor: (_wildcard)->
      wildcard = _wildcard.replace('*','')
      #console.log 'cacheEngine.getAllValuesFor called'
      #console.dir cache
      q = defer()
      rv = []
      for k,v of cache
        match = k.indexOf(wildcard)
        #console.log 'match for '+k+' and '+wildcard+' was '+match
        if match > -1 then rv.push v
      q.resolve(rv)
      q

  modelEngine =
    createAnything: (obj)->
      obj.serialize = ()-> storageEngine.set(obj.id, obj)
      q = defer()
      q.resolve(obj)
      q
    createZone: (obj)-> modelEngine.createAnything(obj)
    createItem: (obj)-> modelEngine.createAnything(obj)
    createEntity: (obj)-> modelEngine.createAnything(obj)
    

  sendFunction = (adr, command)->
    sibling = tileCluster[adr]
    #console.log 'sendFunction sends'
    #console.dir command
    sibling.onSiblingUpdate(JSON.stringify(command))

  registerForUpdatesFunction = (tiler)->
    tileCluster[tiler.myAddress] = tiler

  before (done)->
    tiler = new Tiler(storageEngine, cacheEngine, modelEngine, "17", sendFunction, registerForUpdatesFunction)
    done()

#-----------------------------------------------------------------------------------------------------------------------

  it "should be able to calculate zoneid for positive x,y", (done)->
    zid = tiler.getZoneIdFor(1,23,25)
    expect(zid).to.equal('1_20_20')
    done()

  it "should be able to calculate zoneid for 0,0", (done)->
    zid = tiler.getZoneIdFor(1,0,0)
    expect(zid).to.equal('1_0_0')
    done()

  it "should be able to calculate zoneid for 1,1", (done)->
    zid = tiler.getZoneIdFor(1,1,1)
    expect(zid).to.equal('1_0_0')
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
    tiler.setTileAt(1, {id:'foo', type: 'bar',x:79, y:94}).then ()->
      tiler.resolveZoneFor(1,79,94).then (zoneObj)->
        expect(tiler.zoneTiles[zoneObj.tileid]['79_94']).to.exist
        done()

  it "should be able get a tile", (done)->
    tiler.getTileAt(1,79,94).then (tile)->
      expect(tile.id).to.equal('foo')
      done()

  it "should be able set multiple tiles at once", (done)->
    tiles =
    [
      {x:10, y:10, type: 1, ore: 1, stone: 1, features:[]}
      {x:11, y:10, type: 1, ore: 1, stone: 1, features:[]}
      {x:12, y:10, type: 1, ore: 1, stone: 1, features:[]}
    ]
    tiler.setAndPersistTiles(1, tiles).then (tiles)->
      expect(tiles.length).to.equal(3)
      done()

  it "should be able to fail when setting faulty tile", (done)->
    tiler.setTileAt(1, {id:'foo', type: 0,x:1179, y:1194}).then(
      ()->console.log 'setTile OK'
      (reject)->
        expect(reject).to.exist
        done()
    )

  it "should be able to add an item", (done)->
    item = {name: 'item 1', x:30, y: 40, height:1, width: 1}
    tiler.addItem(1, item).then ()->
      tiler.resolveZoneFor(1,30,40).then (zoneObj)->
        itemQT = tiler.zoneItemQuadTrees[zoneObj.tileid]
        addedItem = itemQT.retrieve({x:30, y: 40})
        expect(addedItem).to.exist
        done()

  it "should be able to get an item", (done)->
    tiler.getItemAt(1, 30, 40).then (item)->
      expect(item).to.exist
      done()

  it "should be able to remove an item", (done)->
    item = {name: 'item 1', x:30, y: 40, height:1, width: 1}
    tiler.removeItem(1, item).then (result)->
      tiler.getItemAt(1, 30, 40).then (olditem)->
        expect(olditem).to.not.exist
        done()


  it "should be able to set up two sibling Tile engines and have updates on one propagate to the other", (done)->
    tiler1 = new Tiler(storageEngine, cacheEngine, modelEngine, "a", sendFunction, registerForUpdatesFunction)
    tiler2 = new Tiler(storageEngine, cacheEngine, modelEngine, "b", sendFunction, registerForUpdatesFunction)
    # prime zones, so each resolve the same
    tiler1.getTileAt(1, 0, 0).then ()->
      tiler2.getTileAt(1, 0, 0).then ()->
        tiler1.setTileAt(1, {id:'xxyyzz', type:'Tile', x:1, y:1}).then ()->
          setTimeout(
            ()->
              tiler2.getTileAt(1, 1, 1).then (tile)->
                expect(tile).to.exist
                done()
            ,5
          )

  it "should be able set a tile and have coresponding zone added to dirtyZones", (done)->
    tiler.setTileAt(1, {id:'foo', type: 'bar',x:79, y:94}).then ()->
      zone =  tiler.dirtyZones['1_60_80']
      expect(zone).to.exist
      done()

  it "should be able set a tile and persist one or more dirtyZones", (done)->
    tiler.setTileAt(1, {id:'foo', type: 'bar',x:79, y:94}).then ()->
      tiler.persistDirtyZones().then (howmany)->
        expect(howmany).to.be.gt(0)
        done()