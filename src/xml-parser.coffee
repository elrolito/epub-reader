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

exports = module.exports = parseXML
