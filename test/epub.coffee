'use strict'

path = require 'path'

AdmZip = require 'adm-zip'

require('mocha-as-promised')()

chai = require 'chai'
chaiAsPromised = require 'chai-as-promised'
sinon = require 'sinon'
sinonChai = require 'sinon-chai'

chai.should()
chai.use(chaiAsPromised)
chai.use(sinonChai)

EPub = require '../src/epub'

describe "Epub", ->
  epub = remoteEpub = null
  book = path.resolve __dirname, './files/progit.epub'

  describe ".factory", ->
    it "eventually returns a new and initialized EPub object", ->
      EPub.factory(book)
        .should.eventually.be.an.instanceof EPub

  beforeEach ->
    epub = new EPub book
    remoteEpub = new EPub 'http://www.epubbooks.com/downloads/587'

  describe "#constructor", ->
    it "has a resource", ->
      epub.resource.should.equal book

    it "detects a remote resource", ->
      epub.isRemote.should.not.be.true
      remoteEpub.isRemote.should.be.true

    it "is not initialized", ->
      epub.isInitialized.should.not.be.true

  describe "#init", ->
    it.skip "makes an http request if resource is remote url", ->
      @timeout 5000 # give enough time to make request
      progressSpy = sinon.spy()

      return remoteEpub.init().progress(progressSpy)
        .then(
          ->
            progressSpy.should.have
              .been.calledWith 'Requesting remote resource...'
            progressSpy.should.have.been.calledOnce
        )

    it "eventually finds container file, parses, and locates root file(s)", ->
      initializedBook = epub.init()

      initializedBook
        .should.eventually.have.deep.property('zip').that.is.an('object')
      initializedBook
        .should.eventually.have.deep.property('rendition').that.is.an('object')
      initializedBook
        .should.eventually.have.deep.property('manifest').that.is.an('array')
      initializedBook
        .should.eventually.have.deep.property('spine').that.is.an('array')

  describe "#parseZip", ->
    it "eventually rejects non-epub files (mimetype)", ->
      resource = "#{__dirname}/files/normal.zip"
      nonEpub = new EPub resource
      nonEpub.init()
        .should.be
        .rejectedWith TypeError, "#{resource} not a valid epub (mimetype)."

    it "eventually throws an error if no epub container is found", ->
      resource = "#{__dirname}/files/mimetype.zip"
      noContainer = new EPub resource
      noContainer.init().should.be
        .rejectedWith "No epub container file found for #{resource}."

  describe "#render", ->
    it "eventually returns object for a particular rendition", ->
      epub.init().post('render')
        .should.eventually.be.an('object')
        .and.should.eventually.contain.keys 'metadata', 'manifest', 'spine'

    it "eventually throws an error if index is set to high.", ->
      epub.init().post('render', [10])
        .should.eventually.be
        .rejectedWith RangeError, "#{book} only has 1 root file(s)."

  describe "#getFlow", ->
    it "returns an array of entries", ->
      epub.init().post('getFlow')
        .should.eventually.be.an 'array'

    it "throws an error if not initialized", ->
      resource = 'uninitialized'
      uninitializedBook = new EPub resource
      try
        uninitializedBook.getFlow()
          .should.throw ReferenceError, "#{resource} must be initialized first."
      catch error

  describe "#getTOC", ->
    it "eventually returns an object", ->
      epub.init().post('getTOC')
        .should.eventually.be.an 'array'

  describe "#getEntryAsText", ->
    it "eventually reads contents of a zip entry", ->
      epub.init().post('getEntryAsText', ['mimetype'])
        .should.eventually.equal 'application/epub+zip'

  describe "#findZipEntry", ->
    entry = '18333fig0101-tn.png'

    it "eventually returns a zipEntry object if it exists", ->
      epub.init().post('findZipEntry', [entry])
        .should.eventually.be.an 'object'

    it "is case insensitive", ->
      epub.init().post('findZipEntry', [entry.toUpperCase()])
        .should.eventually.be.an 'object'

    it "eventually throws an error if the entry does not exist", ->
      entry = 'FAKEFILE'
      epub.init().post('findZipEntry', [entry])
        .should.eventually.be.rejectedWith "#{entry} not an entry in #{book}."

    it "eventually throws an error if not initialized first", ->
      uninitializedBook = new EPub 'uninitialized'
      uninitializedBook.findZipEntry('file').should
        .eventually.be.rejectedWith 'uninitialized must be initialized first.'

  describe "#getEntryAsBuffer", ->
    it "eventually returns a buffer if entry exists", ->
      entry = '18333fig0101-tn.png'
      epub.init().post('getEntryAsBuffer', [entry])
        .should.eventually.be.an 'object'

  describe "#getEntry", ->
    it "eventually returns and object with a buffer and mimetype", ->
      entry = '18333fig0101-tn.png'
      result = epub.init().post('getEntry', [entry])
      result
        .should.eventually.be.an('object')
      result
        .should.eventually.have.property('data')
      result
        .should.eventually.have.property('mimetype', 'image/png')
