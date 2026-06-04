## Pretty-printing — indented multi-line SMT-LIB rendering plus
## SMT2 script emission and parsing.
##
## ## Why a Nim-side re-indenter
##
## Z3's own `Z3_*_to_string` family emits a *flat* SMT-LIB string with
## no line breaks regardless of nesting depth — for a tightly-nested
## term you get one extremely long line. `Z3_set_ast_print_mode`
## (surfaced as `setAstPrintMode` in `z3/context`) chooses between
## flavors of output (SMT-LIB v2 full / low-level / SMTLIB2-compliant)
## but doesn't add structure. So this module implements the indentation
## pass in Nim, operating on top of Z3's flat output regardless of
## which print mode is active.
##
## ## Algorithm (Wadler-style "fit or stack")
##
## We do a single-pass sexp walk that:
##
## 1. Tokenises the flat input on whitespace and parens while preserving
##    `"..."` quoted runs and `|...|` quoted symbols (SMT-LIB quoted
##    identifiers).
## 2. For each opening `(`, decides whether the *entire* enclosed form
##    fits on one line within `width - currentColumn`. If yes, emit it
##    flat (just whitespace-normalised). If no, emit it stacked: head
##    token on the opening line, each subsequent child on its own
##    indented line.
## 3. Inner forms recurse with the same fit-or-stack decision.
##
## The result reads exactly the way a competent SMT-LIB user would
## indent the term by hand. Pure function over a string, so it works
## uniformly for `Z3Ast[S]`, `Z3BitVec[W]`, `Z3Sort[S]`, `Z3Solver`,
## and `Z3Model` — each has its own `pretty` overload that calls into
## the same reformatter on `$node`.

import std/[strutils]
import ./context, ./sort, ./ast, ./bitvec, ./solver, ./model

# ============================================================================
# Tokeniser
# ============================================================================

type
  TokKind = enum tkOpen, tkClose, tkAtom
  Tok = object
    kind: TokKind
    text: string   # for tkAtom; empty for tkOpen/tkClose

proc tokenize(src: string): seq[Tok] =
  ## Sexp tokeniser. Whitespace-delimited atoms, plus the `(` / `)`
  ## structural tokens. `"..."` and `|...|` quoted runs are kept atomic
  ## — their contents may include parens and whitespace that would
  ## otherwise look structural.
  result = @[]
  var i = 0
  while i < src.len:
    let c = src[i]
    case c
    of ' ', '\t', '\n', '\r':
      inc i
    of '(':
      result.add Tok(kind: tkOpen)
      inc i
    of ')':
      result.add Tok(kind: tkClose)
      inc i
    of '"':
      # SMT-LIB string literal — consume up to the matching unescaped
      # quote (`""` inside a literal escapes a single quote).
      var j = i + 1
      while j < src.len:
        if src[j] == '"':
          if j + 1 < src.len and src[j + 1] == '"':
            inc j, 2     # escaped quote
          else:
            break
        else:
          inc j
      let endIdx = min(j, src.len - 1)
      result.add Tok(kind: tkAtom, text: src[i .. endIdx])
      i = endIdx + 1
    of '|':
      # SMT-LIB quoted symbol — `|...|` contains anything except `|`
      # and backslash. Atomic.
      var j = i + 1
      while j < src.len and src[j] != '|':
        inc j
      let endIdx = min(j, src.len - 1)
      result.add Tok(kind: tkAtom, text: src[i .. endIdx])
      i = endIdx + 1
    else:
      var j = i
      while j < src.len and src[j] notin {' ', '\t', '\n', '\r', '(', ')'}:
        inc j
      result.add Tok(kind: tkAtom, text: src[i ..< j])
      i = j

# ============================================================================
# Renderer
# ============================================================================
#
# Two-pass per group: first compute the flat length of the group; if it
# fits within `width - currentColumn`, render flat; otherwise stack with
# `indent` spaces of additional indentation per nesting level.

proc flatLen(toks: seq[Tok], start: int): tuple[len: int, endIdx: int] =
  ## If `toks[start]` is `(`, return the flat-rendered length of the
  ## group (including outer parens) and the index of the matching `)`.
  ## If `toks[start]` is an atom, return its length and `start`.
  ## tkClose at top level shouldn't happen here; behaves as length 0.
  if toks[start].kind == tkAtom:
    return (toks[start].text.len, start)
  # tkOpen: walk to matching close, counting tokens + interleaved spaces.
  var depth = 1
  var len = 1   # opening '('
  var i = start + 1
  var prevWasToken = false
  while i < toks.len and depth > 0:
    case toks[i].kind
    of tkOpen:
      if prevWasToken: inc len     # space before
      inc len                       # '('
      inc depth
      prevWasToken = false          # `(` itself doesn't take a trailing space
    of tkClose:
      inc len                       # ')'
      dec depth
      prevWasToken = true
    of tkAtom:
      if prevWasToken: inc len     # space before
      len += toks[i].text.len
      prevWasToken = true
    if depth == 0: break
    inc i
  (len, i)

proc renderGroup(toks: seq[Tok], start: int, col, indent, width: int,
                 buf: var string): int =
  ## Render `toks[start]` (an atom or a group) into `buf` starting at
  ## column `col`. Returns the index past the rendered region.
  if toks[start].kind == tkAtom:
    buf.add toks[start].text
    return start + 1
  # tkOpen group.
  let (flat, endIdx) = flatLen(toks, start)
  if col + flat <= width:
    # Render flat: just walk and emit with single-space separators.
    var depth = 0
    var prevWasToken = false
    var i = start
    while i <= endIdx:
      case toks[i].kind
      of tkOpen:
        if prevWasToken: buf.add ' '
        buf.add '('
        inc depth
        prevWasToken = false
      of tkClose:
        buf.add ')'
        dec depth
        prevWasToken = true
      of tkAtom:
        if prevWasToken: buf.add ' '
        buf.add toks[i].text
        prevWasToken = true
      inc i
    return endIdx + 1
  # Stacked: head token (if any) on opening line, children indented.
  buf.add '('
  var i = start + 1
  let childCol = col + indent
  # Head token: if the first child is an atom (an operator name like
  # `and`, `or`, `assert`), keep it on the opening line.
  var firstOnSameLine = false
  if i <= endIdx and toks[i].kind == tkAtom:
    buf.add toks[i].text
    inc i
    firstOnSameLine = true
  var first = true
  while i < toks.len and toks[i].kind != tkClose:
    if first and firstOnSameLine:
      buf.add ' '
      first = false
      i = renderGroup(toks, i, col + 1 + toks[start + 1].text.len + 1,
                     indent, width, buf)
    else:
      buf.add '\n'
      buf.add ' '.repeat(childCol)
      first = false
      i = renderGroup(toks, i, childCol, indent, width, buf)
  buf.add ')'
  return i + 1  # past the matching close

proc reformat*(flat: string, indent = 2, width = 80): string =
  ## Reformat a flat SMT-LIB string into the indented "fit-or-stack"
  ## form. Exposed publicly so callers who already have a flat string
  ## (perhaps from a different Z3 call) can pretty it without going
  ## through the typed `pretty` overloads.
  let toks = tokenize(flat)
  result = newStringOfCap(flat.len * 2)
  var i = 0
  var first = true
  while i < toks.len:
    if not first:
      result.add '\n'
    first = false
    i = renderGroup(toks, i, 0, indent, width, result)

# ============================================================================
# Generic surface (v0.5 step 3A)
# ============================================================================
#
# Pre-v0.5 there were five per-family `pretty` overloads — `Z3Ast[S]`,
# `Z3BitVec[W]`, `Z3Sort[S]`, `Z3Solver`, `Z3Model` — each with the
# identical body `reformat($x, indent, width)`. The unification
# constraint is "anything with `$x` defined and a `.ctx` field" —
# captured by the `Z3Renderable` concept here. The concept is wider
# than `Z3Term` (which requires `.raw is RawZ3Ast`) because pretty-
# printing also covers sorts (`Z3Sort[S]` has `RawZ3Sort`) and ref
# handles (`Z3Solver` has `RawZ3Solver`, etc.) — they all have `$`
# defined and a `.ctx` accessor.

type Z3Renderable* = concept x
  ## Anything with `$x` returning string and a `.ctx: Z3Context`
  ## field. Used to constrain the generic `pretty[T]` — wider than
  ## `Z3Term` because pretty-printing covers sorts and ref handles
  ## in addition to typed AST families.
  ($x) is string
  x.ctx is Z3Context

proc pretty*[T: Z3Renderable](v: T, indent = 2, width = 80): string =
  ## Reformat `$v` as an indented multi-line SMT-LIB-ish layout.
  ## Generic over every typed family, every sort, and every ref
  ## handle (`Z3Solver` / `Z3Model` / `Z3Goal` / `Z3Tactic` /
  ## `Z3Fixedpoint` / `Z3Optimize` / `Z3Stats` / `Z3AstVector` /
  ## `Z3Probe` / `Z3ParserContext` / `Z3FuncDecl[A, R]`).
  ##
  ## ```nim
  ## echo pretty(s)             # Solver state, indent=2, width=80
  ## echo pretty(formula, 4)    # AST with indent=4
  ## echo pretty(model, width = 40)
  ## ```
  reformat($v, indent, width)

# SMT2 emission / parsing / streaming parser live in `z3/io`
# (v0.4 step 14 relocation). This module retains only the
# human-facing pretty-printers.
