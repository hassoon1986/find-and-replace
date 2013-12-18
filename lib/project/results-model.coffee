Q = require 'q'
{_} = require 'atom'
{Emitter} = require 'emissary'

class Result
  @create: (result) ->
    if result.matches?.length then new Result(result) else null

  constructor: (result) ->
    _.extend(this, result)

module.exports =
class ResultsModel
  Emitter.includeInto(this)

  constructor: (state={}) ->
    @useRegex = state.useRegex ? false
    @caseSensitive = state.caseSensitive ? false

    atom.project.eachEditor (editSession) =>
      editSession.on 'contents-modified', => @onContentsModified(editSession)

    @clear()

  serialize: ->
    {@useRegex, @caseSensitive}

  clear: ->
    @pathCount = 0
    @matchCount = 0
    @regex = null
    @results = {}
    @paths = []
    @active = false
    @pattern = ''
    @replacementPattern = null
    @emit('cleared')

  search: (pattern, replacementPattern, paths, {onlyRunIfChanged, pathsReplaced, replacements}={}) ->
    return Q() if onlyRunIfChanged and pattern? and paths? and pattern == @pattern and _.isEqual(paths, @searchedPaths)

    @clear()
    @active = true
    @regex = @getRegex(pattern)
    @pattern = pattern
    @searchedPaths = paths

    @updateReplacementPattern(replacementPattern)

    onPathsSearched = (numberOfPathsSearched) =>
      @emit('paths-searched', numberOfPathsSearched)

    promise = atom.project.scan @regex, {paths, onPathsSearched}, (result) =>
      @setResult(result.filePath, Result.create(result))

    @emit('search', promise)
    promise.then => @emit('finished-searching', {@pattern, @pathCount, @matchCount, replacementPattern, pathsReplaced, replacements})

  replace: (pattern, replacementPattern, paths) ->
    regex = @getRegex(pattern)

    @updateReplacementPattern(replacementPattern)

    pathsReplaced = 0
    replacements = 0

    promise = atom.project.replace regex, replacementPattern, paths, (result) =>
      if result and result.replacements
        pathsReplaced++
        replacements += result.replacements
      @emit('path-replaced', result)

    @emit('replace', promise)
    promise.then =>
      replacementResult = {pattern, replacementPattern, pathsReplaced, replacements}
      @emit('finished-replacing', replacementResult)
      @search(pattern, replacementPattern, paths, replacementResult)

  updateReplacementPattern: (replacementPattern) ->
    @replacementPattern = replacementPattern or null
    @emit('replacement-pattern-changed', @regex, replacementPattern)

  toggleUseRegex: ->
    @useRegex = not @useRegex

  toggleCaseSensitive: ->
    @caseSensitive = not @caseSensitive

  getResultsSummary: ->
    pattern: @getPattern()
    pathCount: @getPathCount()
    matchCount: @getMatchCount()

  getPathCount: ->
    @pathCount

  getMatchCount: ->
    @matchCount

  getPattern: ->
    @pattern or ''

  getPaths: (filePath) ->
    @paths

  getResult: (filePath) ->
    @results[filePath]

  setResult: (filePath, result) ->
    if result
      @addResult(filePath, result)
    else
      @removeResult(filePath)

  addResult: (filePath, result) ->
    if @results[filePath]
      @matchCount -= @results[filePath].matches.length
    else
      @pathCount++
      @paths.push(filePath)

    @matchCount += result.matches.length

    @results[filePath] = result
    @emit('result-added', filePath, result)

  removeResult: (filePath) ->
    if @results[filePath]
      @pathCount--
      @matchCount -= @results[filePath].matches.length

      @paths = _.without(@paths, filePath)
      delete @results[filePath]
      @emit('result-removed', filePath)

  getRegex: (pattern) ->
    flags = 'g'
    flags += 'i' unless @caseSensitive

    if @useRegex
      new RegExp(pattern, flags)
    else
      new RegExp(_.escapeRegExp(pattern), flags)

  onContentsModified: (editSession) =>
    return unless @active

    matches = []
    editSession.scan @regex, (match) ->
      matches.push(match)

    result = Result.create({matches})
    @setResult(editSession.getPath(), result)
    # @emit('finished-searching', @getResultsSummary())
