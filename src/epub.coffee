URL = require 'url'

_ = require 'lodash'
AdmZip = require 'adm-zip'
HTTP = require 'q-io/http'
Q = require 'q'
xml2js = require 'xml2js'

parserOpts =
  normalize: true
  explicitArray: false
  explicitRoot: false

parser = new xml2js.Parser parserOpts
parseXML = Q.denodeify parser.parseString

class EPub
  constructor: (@resource) ->
    @isRemote = (URL.parse @resource).host?

    return @

  init: ->
    deferred = Q.defer()

    deferred.resolve @zip if @zip?

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
          @getZipEntryTextContents(@zip, 'mimetype', encoding)
          @getZipEntryTextContents(@zip, 'META-INF/container.xml', encoding)
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
              @rootfiles.push xml.rootfiles.rootfile['$']['full-path']

            deferred.resolve @
        )

    ).catch(
      (error) ->
        deferred.reject error
    )

    return deferred.promise

  getZipEntryTextContents: (zip, entry, encoding = 'utf8') ->
    deferred = Q.defer()

    unless zip?
      deferred.reject 'No AdmZip object given.'

    else
      try
        zip.readAsTextAsync entry, (content) ->
          if content.length
            deferred.resolve content
          else
            deferred.reject "#{entry} not found."

        , encoding

      catch error
        deferred.reject error

    return deferred.promise

exports = module.exports = EPub
