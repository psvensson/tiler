expect = require("chai").expect
Tiler = require('../lib/Tiler')

debug = process.env['DEBUG']

describe "Tiler test", ()->
  before (done)->
    done()

  it "should work", (done)->
    expect(true).to.equal(true)
    done()
