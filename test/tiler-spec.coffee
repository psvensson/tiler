expect    = require("chai").expect
Tiler     = require('../lib/Tiler')
defer     = require('node-promise').defer

debug = process.env['DEBUG']

describe "Tiler test", ()->
  #this.timeout(500000);
  storage = {}
  cache = {}
  tileCluster = {}
  tiler = undefined

  storageEngine =
    find: (type, prop, val)->
      #console.log 'storageEngine.find called.'
      #console.dir arguments
      #console.log 'contents are'
      #console.dir storage
      q = defer()
      result = undefined
      for i,o of storage
        for k,v of o
          if k == prop and v == val then result = o
      q.resolve(result)
      q
    get: (id)->
      console.log 'storageEngine.get id='+id
      q = defer()
      q.resolve(storage[id])
      q
    set: (id, obj)->
      console.log 'storageEngine.set id='+id
      q = defer()
      storage[id] = obj
      q.resolve()
      q

  cacheEngine =
    get: (type, id)->
      q = defer()
      q.resolve(cache[id])
      q
    set: (id, obj)->
      #console.log 'cachEngine set: '+id+' -> '+obj
      if not obj then xyzzy
      q = defer()
      cache[id] = obj
      q.resolve()
      q
    getAllValuesFor: (_wildcard)->
      wildcard = _wildcard.replace('*','')
      console.log 'cacheEngine.getAllValuesFor called for "'+wildcard+'"'
      console.dir cache
      q = defer()
      rv = []
      for k,v of cache
        if k.indexOf(':') then kk = k.substring(0, k.indexOf(':')+1) else kk = k
        match = kk.indexOf(wildcard)
        #console.log 'match for '+kk+' and '+wildcard+' was '+match+' v = '+v+' k = '+k
        if ((match > -1) or (k == wildcard)) then rv.push v
      q.resolve(rv)
      q
    delete:(id)->
      #console.log '********************************* DELETE CACHE CALLED *****************************'
      #console.dir arguments
      delete cache[id]
    expireat:(id,millis)->
      if not millis then xyzzy
      #console.log '******************************** EXPIREAT called for '+millis+' millis'
      setTimeout(
        ()->
          #console.log '******************************** EXPIREAT called for '+millis+' millis'
          cacheEngine.delete(id)
        ,millis
      )

  modelEngine =
    createAnything: (obj)->
      obj.createdAt = Date.now()
      obj.modifiedAt = obj.createdAt
      obj.serialize = ()-> storageEngine.set(obj.id, obj)
      q = defer()
      q.resolve(obj)
      q
    createZone: (obj)-> modelEngine.createAnything(obj)
    createItem: (obj)-> modelEngine.createAnything(obj)
    createEntity: (obj)-> modelEngine.createAnything(obj)


  communicationManager =
    sendFunction : (adr, command)->
      q = defer()
      funs = tileCluster[adr]
      #console.log '--------------------------> sendFunction sends using fun '+fun+' lookup for adr '+adr
      #console.dir command
      funs.forEach (fun)=>
        if not fun
          console.log '----- no function found for adr '+adr
          console.dir tileCluster
        fun(JSON.stringify(command),(reply)->
          #console.log '<-------------------------- sendFunction reply got '+reply
          #console.dir reply
          q.resolve(reply)
          )
      return q

    registerForUpdates : (adr, fun)->
      #console.log '+++++++++++++++++++++++++++ registerForUpdates called with fun '+fun+' and address '+adr
      funs = tileCluster[adr] or []
      funs.push fun
      tileCluster[adr] = funs

  before (done)->
    tiler = new Tiler(storageEngine, cacheEngine, modelEngine, "17", communicationManager)
    done()

#-----------------------------------------------------------------------------------------------------------------------

  it "should be able to calculate zoneid for positive x,y", (done)->
    zid = tiler.getZoneIdFor(1,23,25)
    expect(zid).to.equal('1_20_40')
    done()

  it "should be able to calculate zoneid for 0,0", (done)->
    zid = tiler.getZoneIdFor(1,0,0)
    expect(zid).to.equal('1_0_20')
    done()

  it "should be able to calculate zoneid for 1,1", (done)->
    zid = tiler.getZoneIdFor(1,1,1)
    expect(zid).to.equal('1_0_20')
    done()

  it "should be able to calculate zoneid for negative x,y", (done)->
    zid = tiler.getZoneIdFor(1,-44,-4)
    expect(zid).to.equal('1_-60_0')
    done()

  it "should be able to calculate zoneid for mixed x,y", (done)->
    zid = tiler.getZoneIdFor(1,1,-8)
    expect(zid).to.equal('1_0_0')
    done()

  it "should be able to resolve and create a new zone", (done)->
    tiler.zmgr.resolveZoneFor(1,114,-294).then (zoneObj)->
      expect(zoneObj.id).to.equal('1_100_-280')
      done()

  it "should be able to resolve an old, existing zone", (done)->
    tiler.zmgr.resolveZoneFor(1,114,-294).then (zoneObj)->
      expect(zoneObj.id).to.equal('1_100_-280')
      done()

  it "should be able set a tile", (done)->
    tiler.setTileAt(1, {id:'foo', type: 'bar',x:79, y:94}).then ()->
      tiler.zmgr.resolveZoneFor(1,79,94).then (zoneObj)->
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

  it "should be able to add an item", (done)->
    item = {name: 'item 1', x:30, y: 40, height:1, width: 1}
    tiler.addItem(1, item).then ()->
      tiler.zmgr.resolveZoneFor(1,30,40).then (zoneObj)->
        itemQT = tiler.zoneItemQuadTrees[zoneObj.tileid]
        addedItem = itemQT.get({x:30, y: 40, width:1, height:1})
        expect(addedItem).to.exist
        done()

  it "should be able to get an item", (done)->
    tiler.getItemAt(1, 30, 40).then (item)->
      console.log 'get item is'
      console.dir item
      expect(item).to.exist
      done()

  it "should be able to remove an item", (done)->
    item = {name: 'item 1', x:30, y: 40, height:1, width: 1}
    tiler.removeItem(1, item).then (result)->
      tiler.getItemAt(1, 30, 40).then (olditem)->
        expect(olditem).to.not.exist
        done()

  it "should be able to set up two sibling Tile engines and have updates on one propagate to the other", (done)->
    tiler1 = new Tiler(storageEngine, cacheEngine, modelEngine, "a", communicationManager)
    tiler2 = new Tiler(storageEngine, cacheEngine, modelEngine, "b", communicationManager)
    # prime zones, so each resolve the same
    tiler1.getTileAt(1, 0, 0).then ()->
      tiler2.getTileAt(1, 0, 0).then ()->
        console.log '>>> spec setting tile at 1,1'
        tiler1.setTileAt(1, {id:'xxyyzz', type:'Tile', x:1, y:1}).then ()->
          console.log '>>> tiler1 set tile 1,1,1'
          setTimeout(
            ()->
              tiler2.getTileAt(1, 1, 1).then (tile)->
                console.log '>>> tiler2 get tile 1,1,1 is '+tile
                expect(tile).to.exist
                done()
              , (reject)->console.log 'got reject from get tile: '+reject
            ,1000
          )

  it "should be able set a tile and have coresponding zone added to dirtyZones", (done)->
    tiler.setTileAt(1, {id:'foo', type: 'bar',x:79, y:94}).then ()->
      zone =  tiler.dirtyZones['1_60_80']
      console.log 'dirtyZones are'
      console.dir tiler.dirtyZones
      expect(zone).to.exist
      done()

  it "should be able set a tile and persist one or more dirtyZones", (done)->
    tiler.setTileAt(1, {id:'foo', type: 'bar',x:79, y:94}).then ()->
      tiler.persistDirtyZones().then (howmany)->
        expect(howmany).to.be.gt(0)
        done()

  it "should be able to have a Tiler replica/sibling elect itself to master", (done)->
    tiler = new Tiler(storageEngine, cacheEngine, modelEngine, "c", communicationManager)
    tiler.getTileAt(1, 500, 500).then ()->
      #console.dir cache
      cacheEngine.getAllValuesFor('zonereplica_1_500_500*').then (foo)->
        #console.log 'getallvalues for zone returned..'
        #console.dir foo
        bar = foo[0]
        #console.log bar
        expect(bar).to.contain('c,')
        expect(bar).to.contain('master')
        done()

  it "should be able to set up two Zones, shutdown the master and have the remaining rw copy become master", (done)->
    tiler1 = new Tiler(storageEngine, cacheEngine, modelEngine, "ma", communicationManager)
    tiler2 = new Tiler(storageEngine, cacheEngine, modelEngine, "co", communicationManager)
    # prime zones, so each resolve the same
    madr = 'zonereplica_2_0_0:ma'
    cadr = 'zonereplica_2_0_0:co'
    console.log '>>> resolving zone tiler1'
    tiler1.zmgr.resolveZoneFor(2,0,0).then (mzone)->
      console.log '>>> resolving zone tiler2'
      tiler2.zmgr.resolveZoneFor(2,0,0).then (czone)->
        setTimeout(
          ()->
            console.log '>>> getting all values for '+madr
            cacheEngine.getAllValuesFor(madr).then (moo)->
              console.log 'master replica info before shutdown is '+moo
              tiler1.zmgr.shutdown(mzone)
              setTimeout(
                ()->
                  console.log 'getting all values for cadr'
                  cacheEngine.getAllValuesFor(cadr).then (foo)->
                    console.log foo
                    bar = foo[0]
                    expect(bar).to.contain('master')
                    done()
                  , (reject)->console.log 'got reject from get tile: '+reject
              ,800
              )
        ,300
        )