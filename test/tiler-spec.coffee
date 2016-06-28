expect    = require("chai").expect
Tiler     = require('../lib/Tiler')
defer     = require('node-promise').defer

debug = process.env['DEBUG']

describe "Tiler test", ()->

  storage = {}
  tiler = undefined

  storageEngine =
    find: (type, prop, val)->
      q = defer()
      result = undefined
      for i,o in storage
        for k,v in o
          if k == prop and v == val then result = o
      q.resolve(result)
      q

  before (done)->
    tiler = new Tiler(storageEngine)
    done()

  it "should be able to calculate zoneid for positive x,y", (done)->
    zid = tiler.getZoneIdFor(23,25)
    expect(zid).to.equal('20_20')
    done()

  it "should be able to calculate zoneid for negative x,y", (done)->
    zid = tiler.getZoneIdFor(-44,-4)
    expect(zid).to.equal('-40_0')
    done()

  it "should be able to calculate zoneid for mixed x,y", (done)->
    zid = tiler.getZoneIdFor(114,-294)
    expect(zid).to.equal('100_-280')
    done()
