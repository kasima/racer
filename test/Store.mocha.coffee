should = require 'should'
util = require './util'
Store = require '../src/Store'
redis = require 'redis'
transaction = require '../src/transaction'

describe 'Store', ->

  store = null
  redisClient = redis.createClient()

  after ->
    redisClient.end()

  # TODO: Add tests for all store modes
  beforeEach (done) ->
    store = new Store
      mode: 'stm'
    store.flush done

  afterEach (done) ->
    store.flush ->
      store.disconnect()
      done()

  it 'flush should delete everything in the adapter and redisClient', (done) ->
    callbackCount = 0
    store._adapter.set 'color', 'green', 1, ->
      redisClient.set 'color', 'green', ->
        store._adapter.get null, (err, value) ->
          value.should.specEql color: 'green'
          redisClient.keys '*', (err, value) ->
            # Note that flush calls redisInfo.onStart immediately after
            # flushing, so the key 'starts' should exist
            # Also note that the store will create a new model for use in store
            # operations, so 'clientClock' will be set
            value.should.eql ['color', 'clientClock', 'starts']
            store.flush (err) ->
              should.equal null, err
              (++callbackCount).should.eql 1
              store._adapter.get null, (err, value) ->
                value.should.eql {}
                redisClient.keys '*', (err, value) ->
                  # Once again, 'clientClock' and 'starts' should exist after the flush
                  value.should.eql ['clientClock', 'starts']
                  done()

  it 'flush should return an error if the adapter fails to flush', (done) ->
    callbackCount = 0
    store._adapter.flush = (callback) -> callback new Error
    store.flush (err) ->
      err.should.be.instanceof Error
      (++callbackCount).should.eql 1
      done()

  it 'flush should return an error if the journal fails to flush', (done) ->
    callbackCount = 0
    store.journal.flush = (callback) -> callback new Error
    store.flush (err) ->
      err.should.be.instanceof Error
      (++callbackCount).should.eql 1
      done()

  it 'flush should return an error if the adapter and journal fail to flush', (done) ->
    callbackCount = 0
    store._adapter.flush = (callback) -> callback new Error
    store.journal.flushdb = (callback) -> callback new Error
    store.flush (err) ->
      err.should.be.instanceof Error
      (++callbackCount).should.eql 1
      done()

  it 'subscribe should only copy the appropriate properties', (done) ->
    tests =
      '': {a: {b: 1, c: 2, d: [1, 2]}, e: {c: 7}}
      'a': {a: {b: 1, c: 2, d: [1, 2]}}
      'a.b': {a: {b: 1}}
      'a.d': {a: {d: [1, 2]}}
      '*.c': {a: {c: 2}, e: {c: 7}}

    patterns = Object.keys tests
    count = patterns.length
    finish = -> done() unless --count
    store.set 'a', {b: 1, c: 2, d: [1, 2]}, null, ->
      store.set 'e', {c: 7}, null, ->
        patterns.forEach (pattern) ->
          expected = tests[pattern]
          model = store.createModel()
          model.subscribe pattern, ->
            model.get().should.specEql expected
            finish()

  it 'store.commit should apply transactions in order', (done) ->
    idIn = []
    idOut = []
    for i in [0..9]
      idIn.push id = "1.#{i}"
      txn = transaction.create(base: 0, id: id, method: 'set', args: ['stuff', 0])
      store.commit txn, (err, txn) ->
        idOut.push transaction.id txn
        finish() if idOut.length is 10
    finish = ->
      idIn.should.eql idOut
      done()
  
  # TODO tests:
  # 'should, upon socket.io disconnect, remove the socket from the sockets._byClientID index'
