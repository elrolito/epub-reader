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
      rootfiles = epub.init().get('rootfiles')
      rootfiles.should.eventually.be.a 'array'
      rootfiles.should.eventually.have.length.above 0

  describe "#getZipEntryTextContents", ->
    it "eventually reads contents of a zip entry", ->
      zip = new AdmZip "#{__dirname}/files/mimetype.zip"
      epub.getZipEntryTextContents(zip, 'mimetype').should
        .eventually.equal 'application/epub+zip'

    it "eventuall throws an error if a zip object is not passed", ->
      epub.getZipEntryTextContents(null, '').should
        .eventually.be.rejectedWith 'No AdmZip object given.'

    it "eventually throws an error if zip entry does not exist", ->
      zip = new AdmZip
      epub.getZipEntryTextContents(zip, 'mimetype').should
        .eventually.be.rejectedWith 'mimetype not found.'

  describe "#parseZip", ->
    it "eventually rejects non-epub files (mimetype)", ->
      nonEpub = new EPub "#{__dirname}/files/normal.zip"
      nonEpub.init().should.be.rejectedWith 'Not a valid epub (mimetype).'

    it "eventually throws an error if no epub container is found", ->
      noContainer = new EPub "#{__dirname}/files/mimetype.zip"
      noContainer.init().should.be
        .rejectedWith 'No epub container file found.'
