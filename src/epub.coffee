'use strict'

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
    @isInitialized = false

    return @

  init: ->
    deferred = Q.defer()

    if @zip? and @rendition?
      deferred.resolve @

    else
      Q.try(
        =>
          deferred.notify message: "Initializing #{@resource}..."

          if @isRemote
            deferred.notify "Requesting #{@resource} remotely..."
            deferred.resolve HTTP.read(@resource).then(@parseZip)

          else
            deferred.resolve @parseZip(@resource)

      )
      .catch(deferred.reject)

    return deferred.promise

  parseZip: (resource = @resource, encoding = 'utf8') ->
    deferred = Q.defer()

    Q.try(
      =>
        deferred.notify message: "Parsing #{resource}..."

        @zip = new AdmZip resource

        Q.allSettled([
          @getEntryAsText('mimetype', encoding)
          @getEntryAsText('META-INF/container.xml', encoding)
        ])
        .spread(
          (mimetype, container) ->
            unless mimetype.value is 'application/epub+zip'
              err = new TypeError "#{resource} not a valid epub (mimetype)."
              deferred.reject err

            unless container.value?.length
              err = new Error "No epub container file found for #{resource}."
              deferred.reject err

            deferred.notify message: "Getting rootfile(s) for #{resource}..."
            return parseXML(container.value)
        )
        .then(
          (xml) =>
            @rootfiles = []

            _.forEach xml.rootfiles, (rootfile) =>
              @rootfiles.push rootfile['$']['FULL-PATH']

            return @render()
        )
        .then(
          =>
            @isInitialized = true
            return @
        )
    )
    .catch(deferred.reject)
    .done(deferred.resolve)

    return deferred.promise

  render: (index = 0) ->
    deferred = Q.defer()

    if @rendition and @rootfiles?[index]?
      deferred.resolve @rendition

    else if @rootfiles[index]?
      Q.try(
        =>
          message = "Rendering #{@resource} using #{@rootfiles[index]}..."
          deferred.notify message: message
          @getEntryAsText(@rootfiles[index])
            .then(parseXML)
            .catch(deferred.reject)
            .done(
              (xml) =>
                @rendition = xml

                @manifest = _.pluck xml.manifest?.item, '$'
                @spine = _.pluck xml.spine?.itemref, '$'

                tocID = xml.spine?['$']['TOC']
                @tocFile = (_.find @manifest, ID: tocID)['HREF']

                deferred.resolve @rendition
            )
      )

    else
      count = @rootfiles.length
      err = new RangeError "#{@resource} only has #{count} root file(s)."
      deferred.reject err

    return deferred.promise

  getFlow: ->
    unless @spine? and @manifest?
      throw new ReferenceError "#{@resource} must be initialized first."

    if @flow?
      return @flow

    else
      @flow = []

      _.forEach @spine, (item) =>
        page = _.find @manifest, ID: item['IDREF']

        entry =
          id: item['IDREF']
          href: page['HREF']
          mimetype: page['MEDIA-TYPE']

        @flow.push entry

      return @flow

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
        .catch(deferred.reject)
        .done(
          (xml) =>
            unless xml?.navmap?.navpoint
              ### @TODO: test invalid tocFile for getTOC() ###
              err = new TypeError "#{@tocFile} is not a valid toc file."
              deferred.reject err

            else
              @toc = tocMapper(xml.navmap.navpoint)
              deferred.resolve @toc
        )

    return deferred.promise

  getEntryAsText: (href, encoding = 'utf8') ->
    deferred = Q.defer()

    @findZipEntry(href)
      .then(
        (entry) =>
          @zip.readAsTextAsync entry, (content) ->
            unless content?.length
              ### @TODO: test no content error for getEntryAsText() ###
              deferred.reject new Error "#{href} has no content."

            else
              deferred.resolve content

          , encoding
      )
      .catch(deferred.reject)

    return deferred.promise

  getEntryAsBuffer: (href) ->
    deferred = Q.defer()

    @findZipEntry(href)
      .then(
        (entry) =>
          @zip.readFileAsync entry, (content) ->
            unless content?.length
              ### @TODO: test no content error for getEntryAsBuffer() ###
              deferred.reject new Error "#{href} has no content."

            else
              deferred.resolve content
      )
      .catch(deferred.reject)

    return deferred.promise

  getEntry: (href) ->
    deferred = Q.defer()

    @getEntryAsBuffer(href)
      .then(
        (data) =>
          unless data?
            ### @TODO: test no data error for getEntry() ###
            deferred.reject new Error "#{href} has no data."

          else
            result =
              data: data
              mimetype: (_.find @manifest, HREF: href)['MEDIA-TYPE']

            deferred.resolve result
      )
      .catch(deferred.reject)

    return deferred.promise

  findZipEntry: (name) ->
    deferred = Q.defer()

    unless @zip?
      deferred.reject new Error "#{@resource} must be initialized first."

    else
      # check manifest first by id
      item = _.find @manifest, ID: name

      # default to checking by passed name
      entryName = item?['HREF'] || name

      # search the zip for the entry
      fileEntry = @zip.getEntry entryName

      unless fileEntry?
        @entries ?= @zip.getEntries()

        # case insensitive search
        fileEntry = _.find @entries, (entry) ->
          entry.entryName.toLowerCase() is name.toLowerCase()

      unless fileEntry?
        deferred.reject new Error "#{name} not an entry in #{@resource}."

      else
        deferred.resolve fileEntry

    return deferred.promise

exports = module.exports = EPub
