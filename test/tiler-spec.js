// Generated by CoffeeScript 1.9.3
(function() {
  var Tiler, debug, defer, expect;

  expect = require("chai").expect;

  Tiler = require('../lib/Tiler');

  defer = require('node-promise').defer;

  debug = process.env['DEBUG'];

  describe("Tiler test", function() {
    var cache, cacheEngine, communicationManager, modelEngine, storage, storageEngine, tileCluster, tiler;
    storage = {};
    cache = {};
    tileCluster = {};
    tiler = void 0;
    storageEngine = {
      find: function(type, prop, val) {
        var i, k, o, q, result, v;
        q = defer();
        result = void 0;
        for (i in storage) {
          o = storage[i];
          for (k in o) {
            v = o[k];
            if (k === prop && v === val) {
              result = o;
            }
          }
        }
        q.resolve(result);
        return q;
      },
      get: function(id) {
        var q;
        q = defer();
        q.resolve(storage[id]);
        return q;
      },
      set: function(id, obj) {
        var q;
        q = defer();
        storage[id] = obj;
        q.resolve();
        return q;
      }
    };
    cacheEngine = {
      get: function(id) {
        var q;
        q = defer();
        q.resolve(cache[id]);
        return q;
      },
      set: function(id, obj) {
        var q;
        q = defer();
        cache[id] = obj;
        q.resolve();
        return q;
      },
      getAllValuesFor: function(_wildcard) {
        var k, match, q, rv, v, wildcard;
        wildcard = _wildcard.replace('*', '');
        q = defer();
        rv = [];
        for (k in cache) {
          v = cache[k];
          match = k.indexOf(wildcard);
          if (match > -1) {
            rv.push(v);
          }
        }
        q.resolve(rv);
        return q;
      }
    };
    modelEngine = {
      createAnything: function(obj) {
        var q;
        obj.createdAt = Date.now();
        obj.modifiedAt = obj.createdAt;
        obj.serialize = function() {
          return storageEngine.set(obj.id, obj);
        };
        q = defer();
        q.resolve(obj);
        return q;
      },
      createZone: function(obj) {
        return modelEngine.createAnything(obj);
      },
      createItem: function(obj) {
        return modelEngine.createAnything(obj);
      },
      createEntity: function(obj) {
        return modelEngine.createAnything(obj);
      }
    };
    communicationManager = {
      sendFunction: function(adr, command) {
        var fun, q;
        q = defer();
        fun = tileCluster[adr];
        if (!fun) {
          console.log('----- no function found for adr ' + adr);
          console.dir(tileCluster);
        }
        fun(JSON.stringify(command), function(reply) {
          return q.resolve(reply);
        });
        return q;
      },
      registerForUpdates: function(adr, fun) {
        return tileCluster[adr] = fun;
      }
    };
    before(function(done) {
      tiler = new Tiler(storageEngine, cacheEngine, modelEngine, "17", communicationManager);
      return done();
    });
    it("should be able to calculate zoneid for positive x,y", function(done) {
      var zid;
      zid = tiler.getZoneIdFor(1, 23, 25);
      expect(zid).to.equal('1_20_20');
      return done();
    });
    it("should be able to calculate zoneid for 0,0", function(done) {
      var zid;
      zid = tiler.getZoneIdFor(1, 0, 0);
      expect(zid).to.equal('1_0_0');
      return done();
    });
    it("should be able to calculate zoneid for 1,1", function(done) {
      var zid;
      zid = tiler.getZoneIdFor(1, 1, 1);
      expect(zid).to.equal('1_0_0');
      return done();
    });
    it("should be able to calculate zoneid for negative x,y", function(done) {
      var zid;
      zid = tiler.getZoneIdFor(1, -44, -4);
      expect(zid).to.equal('1_-40_0');
      return done();
    });
    it("should be able to calculate zoneid for mixed x,y", function(done) {
      var zid;
      zid = tiler.getZoneIdFor(1, 114, -294);
      expect(zid).to.equal('1_100_-280');
      return done();
    });
    it("should be able to resolve and create a new zone", function(done) {
      return tiler.resolveZoneFor(1, 114, -294).then(function(zoneObj) {
        expect(zoneObj.id).to.equal('1_100_-280');
        return done();
      });
    });
    it("should be able to resolve an old, existing zone", function(done) {
      return tiler.resolveZoneFor(1, 114, -294).then(function(zoneObj) {
        expect(zoneObj.id).to.equal('1_100_-280');
        return done();
      });
    });
    it("should be able set a tile", function(done) {
      return tiler.setTileAt(1, {
        id: 'foo',
        type: 'bar',
        x: 79,
        y: 94
      }).then(function() {
        return tiler.resolveZoneFor(1, 79, 94).then(function(zoneObj) {
          expect(tiler.zoneTiles[zoneObj.tileid]['79_94']).to.exist;
          return done();
        });
      });
    });
    it("should be able get a tile", function(done) {
      return tiler.getTileAt(1, 79, 94).then(function(tile) {
        expect(tile.id).to.equal('foo');
        return done();
      });
    });
    it("should be able set multiple tiles at once", function(done) {
      var tiles;
      tiles = [
        {
          x: 10,
          y: 10,
          type: 1,
          ore: 1,
          stone: 1,
          features: []
        }, {
          x: 11,
          y: 10,
          type: 1,
          ore: 1,
          stone: 1,
          features: []
        }, {
          x: 12,
          y: 10,
          type: 1,
          ore: 1,
          stone: 1,
          features: []
        }
      ];
      return tiler.setAndPersistTiles(1, tiles).then(function(tiles) {
        expect(tiles.length).to.equal(3);
        return done();
      });
    });
    it("should be able to add an item", function(done) {
      var item;
      item = {
        name: 'item 1',
        x: 30,
        y: 40,
        height: 1,
        width: 1
      };
      return tiler.addItem(1, item).then(function() {
        return tiler.resolveZoneFor(1, 30, 40).then(function(zoneObj) {
          var addedItem, itemQT;
          itemQT = tiler.zoneItemQuadTrees[zoneObj.tileid];
          addedItem = itemQT.retrieve({
            x: 30,
            y: 40
          });
          expect(addedItem).to.exist;
          return done();
        });
      });
    });
    it("should be able to get an item", function(done) {
      return tiler.getItemAt(1, 30, 40).then(function(item) {
        expect(item).to.exist;
        return done();
      });
    });
    it("should be able to remove an item", function(done) {
      var item;
      item = {
        name: 'item 1',
        x: 30,
        y: 40,
        height: 1,
        width: 1
      };
      return tiler.removeItem(1, item).then(function(result) {
        return tiler.getItemAt(1, 30, 40).then(function(olditem) {
          expect(olditem).to.not.exist;
          return done();
        });
      });
    });
    it("should be able to set up two sibling Tile engines and have updates on one propagate to the other", function(done) {
      var tiler1, tiler2;
      tiler1 = new Tiler(storageEngine, cacheEngine, modelEngine, "a", communicationManager);
      tiler2 = new Tiler(storageEngine, cacheEngine, modelEngine, "b", communicationManager);
      return tiler1.getTileAt(1, 0, 0).then(function() {
        return tiler2.getTileAt(1, 0, 0).then(function() {
          return tiler1.setTileAt(1, {
            id: 'xxyyzz',
            type: 'Tile',
            x: 1,
            y: 1
          }).then(function() {
            return setTimeout(function() {
              return tiler2.getTileAt(1, 1, 1).then(function(tile) {
                expect(tile).to.exist;
                return done();
              }, function(reject) {
                return console.log('got reject from get tile: ' + reject);
              });
            }, 50);
          });
        });
      });
    });
    it("should be able set a tile and have coresponding zone added to dirtyZones", function(done) {
      return tiler.setTileAt(1, {
        id: 'foo',
        type: 'bar',
        x: 79,
        y: 94
      }).then(function() {
        var zone;
        zone = tiler.dirtyZones['1_60_80'];
        expect(zone).to.exist;
        return done();
      });
    });
    it("should be able set a tile and persist one or more dirtyZones", function(done) {
      return tiler.setTileAt(1, {
        id: 'foo',
        type: 'bar',
        x: 79,
        y: 94
      }).then(function() {
        return tiler.persistDirtyZones().then(function(howmany) {
          expect(howmany).to.be.gt(0);
          return done();
        });
      });
    });
    return it("should be able to have a Tiler replica/sibling elect itself to master", function(done) {
      tiler = new Tiler(storageEngine, cacheEngine, modelEngine, "c", communicationManager);
      return tiler.getTileAt(1, 500, 500).then(function() {
        return cacheEngine.getAllValuesFor('zonereplica_1_500_500*').then(function(foo) {
          var bar;
          bar = foo[0];
          expect(bar.indexOf('c,') > -1 && bar.indexOf('master') > -1).to.equal(true);
          return done();
        });
      });
    });
  });

}).call(this);

//# sourceMappingURL=tiler-spec.js.map
