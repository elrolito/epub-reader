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

  parseZip: (resource = @resource) ->
    deferred = Q.defer()

    Q.try(
      =>
        deferred.notify message: "Parsing #{resource}"

        @zip = new AdmZip resource

        Q.allSettled([
          @getTextContents(@zip, 'mimetype')
          @getTextContents(@zip, 'META-INF/container.xml')
        ]).spread(
          (mimetype, container) ->
            unless mimetype.value is 'application/epub+zip'
              deferred.reject 'Not a valid epub (mimetype).'

            unless container.value?.length
              deferred.reject 'No epub container file found.'

            return parseXML(container.value)

        ).then(
          (xml) =>
            @rootfile = null
            @rootfiles = []

            if _.isArray xml.rootfiles
              _.forEach xml.rootfiles, (rootfile) =>
                @rootfiles.push rootfile['$']['full-path']

            else
              @rootfile = xml.rootfiles.rootfile['$']['full-path']

            deferred.resolve @
        )

    ).catch(
      (error) ->
        deferred.reject error
    )

    return deferred.promise

  getTextContents: (zip, entry) ->
    deferred = Q.defer()

    zip.readAsTextAsync entry, (content) ->
      if content.length
        deferred.resolve content
      else
        deferred.reject "#{entry} not found."

    return deferred.promise

exports = module.exports = EPub