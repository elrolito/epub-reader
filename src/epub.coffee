URL = require 'url'

_ = require 'lodash'
AdmZip = require 'adm-zip'
HTTP = require 'q-io/http'
Q = require 'q'

parseXML = require './xml-parser'

class EPub
  @factory: (resource) ->
    epub = new EPub resource

    return epub.init()

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
                @rootfiles.push rootfile['$']['FULL-PATH']

            else
              @rootfiles.push xml.rootfiles.rootfile['$']['FULL-PATH']

            return @getRendition()
        )

    ).catch(
      (error) ->
        deferred.reject error

    ).done(
      =>
        deferred.resolve @
    )

    return deferred.promise

  getRendition: (index = 0) ->
    deferred = Q.defer()

    if @rendition?[index]?
      deferred.resolve @rendition[index]

    else if @rootfiles[index]?
      @getEntryAsText(@rootfiles[index])
        .then(parseXML)
        .done(
          (xml) =>
            @rendition = xml

            @manifest = _.pluck xml.manifest?.item, '$'
            @spine = _.pluck xml.spine?.itemref, '$'

            tocID = xml.spine?['$']['TOC']
            @tocFile = (_.find @manifest, ID: tocID)['HREF']

            deferred.resolve @rendition

          , (error) ->
            deferred.reject error
        )

    else
      deferred.reject "#{@resource} only has #{@rootfiles.length} rendition(s)."

    return deferred.promise

  getFlow: ->
    deferred = Q.defer()

    if @flow?
      deferred.resolve @flow

    else
      @flow = []

      _.forEach @spine, (item) =>
        page = _.find @manifest, ID: item['IDREF']

        entry =
          id: item['IDREF']
          href: page['HREF']
          mimetype: page['MEDIA-TYPE']

        @flow.push entry

        deferred.resolve @flow

    return deferred.promise

  getTOC: ->
    deferred = Q.defer()

    if @toc?
      deferred.resolve @toc

    else
      tocMapper = (navpoints) ->
        _.map navpoints, (item) ->
          result =
            id: item['$']['ID']
            order: item['$']['PLAYORDER']
            label: item.navlabel.text
            href: item.content['$']['SRC']

          if item.navpoint?.length
            result.children = tocMapper(item.navpoint)

          return result

      @getEntryAsText(@tocFile)
        .then(parseXML)
        .then(
          (xml) =>
            @toc = tocMapper(xml.navmap.navpoint)
            deferred.resolve @toc

          , (error) ->
            deferred.reject error
        )


    return deferred.promise

  getEntryAsText: (href, encoding = 'utf8') ->
    deferred = Q.defer()

    @getZipEntryByFilename(href)
      .then(
        (entry) =>
          @zip.readAsTextAsync entry, (content) ->
            deferred.resolve content

          , encoding

        , (error) ->
          deferred.reject error
      )

    return deferred.promise

  getEntryAsBuffer: (href) ->
    deferred = Q.defer()

    @getZipEntryByFilename(href)
      .then(
        (entry) =>
          @zip.readFileAsync entry, (contents) ->
            deferred.resolve contents

        , (error) ->
          deferred.reject error
      )

    return deferred.promise

  getEntry: (href) ->
    deferred = Q.defer()

    @getEntryAsBuffer(href)
      .then(
        (data) =>
          result =
            data: data
            mimetype: (_.find @manifest, HREF: href)['MEDIA-TYPE']

          deferred.resolve result

        , (error) ->
          deferred.reject error
      )

    return deferred.promise

  getZipEntryByFilename: (href) ->
    deferred = Q.defer()

    unless @zip?
      deferred.reject "#{@resource} must be initialized first."

    else
      # Try getting entry by name first
      fileEntry = @zip.getEntry href

      unless fileEntry?
        @entries ?= @zip.getEntries()

        fileEntry = _.find @entries, (href) ->
          entry.entryName.toLowerCase() is href.toLowerCase()

      if fileEntry?
        deferred.resolve fileEntry

      else
        deferred.reject "#{href} not an entry."

    return deferred.promise

exports = module.exports = EPub
