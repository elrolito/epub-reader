URL = require 'url'

_ = require 'lodash'
AdmZip = require 'adm-zip'
HTTP = require 'q-io/http'
Q = require 'q'
xml2js = require 'xml2js'

parserOpts =
  async: true
  normalize: true
  normalizeTags: true
  explicitArray: false
  explicitRoot: false
  strict: false
  xmlns: false

parser = new xml2js.Parser parserOpts
parseXML = Q.denodeify parser.parseString

class EPub
  constructor: (@resource) ->
    @isRemote = (URL.parse @resource).host?

    return @

  init: ->
    deferred = Q.defer()

    if @zip? and @rendition? and @flow?
      deferred.resolve @

    else
      if @isRemote
        Q.try( -> deferred.notify 'Requesting remote resource...')
        .then( => HTTP.read(@resource))
        .then(@parseZip)
        .catch(deferred.reject)
        .done( => deferred.resolve @)

      else
        @parseZip(@resource)
          .catch(deferred.reject)
          .done( => deferred.resolve @)

    return deferred.promise

  parseZip: (resource = @resource, encoding = 'utf8') ->
    deferred = Q.defer()

    Q.try(
      =>
        deferred.notify message: "Parsing #{resource}"

        @zip = new AdmZip resource

        Q.allSettled([
          @getEntryAsText('mimetype', encoding)
          @getEntryAsText('META-INF/container.xml', encoding)
        ]).spread(
          (mimetype, container) ->
            unless mimetype.value is 'application/epub+zip'
              deferred.reject 'Not a valid epub (mimetype).'

            unless container.value?.length
              deferred.reject 'No epub container file found.'

            deferred.notify message: "Getting rootfile(s) for #{resource}"
            return parseXML(container.value)

        ).then(
          (xml) =>
            @rootfiles = []

            if _.isArray xml.rootfiles
              _.forEach xml.rootfiles, (rootfile) =>
                @rootfiles.push rootfile['$']['full-path']

            else
              @rootfiles.push xml.rootfiles.rootfile['$']['FULL-PATH']

            return @getFlow()
        )

    ).catch(
      (error) ->
        deferred.reject error

    ).done(
      =>
        deferred.resolve @
    )

    return deferred.promise

  getRendition: (renditionIndex = 0) ->
    deferred = Q.defer()

    if @rendition?
      deferred.resolve @rendition

    else
      @getEntryAsText(@rootfiles[renditionIndex])
        .then(parseXML)
        .done(
          (xml) =>
            @rendition = xml

            deferred.resolve @rendition

          , (error) ->
            deferred.reject error
        )

    return deferred.promise

  getFlow: (renditionIndex = 0) ->
    deferred = Q.defer()

    if @flow?
      deferred.resolve @flow

    else
      @flow = []

      Q.when @getRendition(renditionIndex), (rendition) =>
        @manifest = _.pluck rendition.manifest.item, '$'
        @spine = _.pluck rendition.spine.itemref, '$'

        _.forEach @spine, (item) =>
          page = _.find @manifest, ID: item['IDREF']

          entry =
            id: item['IDREF']
            href: page['HREF']
            mimetype: page['MEDIA-TYPE']

          @flow.push entry

          deferred.resolve @flow

    return deferred.promise

  getEntryAsText: (entry, encoding = 'utf8') ->
    deferred = Q.defer()

    unless @zip?
      deferred.reject "#{@resource} must be initialized first."

    else
      @getZipEntryByFilename(entry)
        .then(
          (zipEntry) =>
            @zip.readAsTextAsync zipEntry, (content) ->
              deferred.resolve content

            , encoding

          , (error) ->
            deferred.reject error
        )

    return deferred.promise

  getEntryAsBuffer: (entry) ->
    deferred = Q.defer()

    unless @zip?
      deferred.reject "#{@resource} must be initialized first."

    else
      @getZipEntryByFilename(entry)
        .then(
          (zipEntry) =>
            @zip.readFileAsync zipEntry, (contents) ->
              deferred.resolve contents

          , (error) ->
            deferred.reject error
        )

    return deferred.promise

  getZipEntryByFilename: (file) ->
    deferred = Q.defer()

    unless @zip?
      deferred.reject "#{@resource} must be initialized first."

    else
      # Try getting entry by name first
      fileEntry = @zip.getEntry file

      unless fileEntry?
        @entries ?= @zip.getEntries()

        fileEntry = _.find @entries, (entry) ->
          entry.entryName.toLowerCase() is file.toLowerCase()

      if fileEntry?
        deferred.resolve fileEntry

      else
        deferred.reject "#{file} not an entry."

    return deferred.promise

exports = module.exports = EPub
