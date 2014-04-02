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

  beforeEach ->
    epub = new EPub book
    remoteEpub = new EPub 'http://www.epubbooks.com/downloads/587'

  describe "#constructor", ->
    it "has a resource", ->
      epub.resource.should.equal book

    it "detects a remote resource", ->
      epub.isRemote.should.not.be.true
      remoteEpub.isRemote.should.be.true

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
        .should.eventually.have.deep.property('flow').that.is.an('array')

  describe "#parseZip", ->
    it "eventually rejects non-epub files (mimetype)", ->
      nonEpub = new EPub "#{__dirname}/files/normal.zip"
      nonEpub.init().should.be.rejectedWith 'Not a valid epub (mimetype).'

    it "eventually throws an error if no epub container is found", ->
      noContainer = new EPub "#{__dirname}/files/mimetype.zip"
      noContainer.init().should.be
        .rejectedWith 'No epub container file found.'

  describe "#getRendition", ->
    it "eventually returns object for a particular rendition", ->
      epub.init().post('getRendition')
        .should.eventually.be.an('object')
        .and.should.eventually.contain.keys 'metadata', 'manifest', 'spine'

  describe "#getFlow", ->
    it "eventually returns an array of entries", ->
      epub.init().post('getFlow')
        .should.eventually.be.an 'array'

  describe "#getEntryAsText", ->
    it "eventually reads contents of a zip entry", ->
      epub.init().post('getEntryAsText', ['mimetype'])
        .should.eventually.equal 'application/epub+zip'

    it "eventuall throws an error if not initialized first", ->
      uninitializedBook = new EPub 'uninitialized'
      uninitializedBook.getEntryAsText('file').should
        .eventually.be.rejectedWith 'uninitialized must be initialized first.'

  describe "#getZipEntryByFilename", ->
    entry = '18333fig0101-tn.png'

    it "eventually returns a zipEntry object if it exists", ->
      epub.init().post('getZipEntryByFilename', [entry])
        .should.eventually.be.an 'object'

    it "is case insensitive", ->
      epub.init().post('getZipEntryByFilename', [entry.toUpperCase()])
        .should.eventually.be.an 'object'

    it "eventually throws an error if the entry does not exist", ->
      epub.init().post('getZipEntryByFilename', ['FAKEFILE'])
        .should.eventually.be.rejectedWith 'FAKEFILE not an entry.'

  describe "#getEntryAsBuffer", ->
    it "eventually returns a buffer if entry exists", ->
      entry = '18333fig0101-tn.png'
      epub.init().post('getEntryAsBuffer', [entry])
        .should.eventually.be.an 'object'
