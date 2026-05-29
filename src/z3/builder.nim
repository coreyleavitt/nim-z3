## AST builders — literals and variables.
##
## This is the user-facing entry point for constructing the simplest
## possible ASTs: integer / real / boolean literals, and named
## variables ("constants" in SMT-LIB speak). Operators (arithmetic,
## boolean, comparison) live in their own modules.
##
## Every builder has two forms: implicit-current-context and explicit
## via UFCS. The implicit form raises a clear `Z3Error` if no current
## context is set; the explicit form takes a `ctx: Z3Context` and works
## regardless. Pick whichever fits your call site:
##
## ```nim
## # Implicit form (most user code):
## let ctx = newContext()
## let x = mkIntVar("x")
## let n = mkInt(42)
##
## # Explicit form (library code that mustn't disturb caller's context):
## proc buildConstraint(ctx: Z3Context, n: int): Z3Ast[stInt] =
##   let x = ctx.mkIntVar("x")
##   x + ctx.mkInt(n)
## ```
##
## Type aliases (`Z3Int`, `Z3Real`, `Z3Bool`) live here so they're
## visible alongside the builders that produce them.

import ./ffi, ./context, ./sort, ./ast
export ast      # Z3Ast[S], $, astEqual; ast re-exports sort

# ============================================================================
# User-friendly type aliases
# ============================================================================

type
  Z3Int*  = Z3Ast[stInt]
  Z3Real* = Z3Ast[stReal]
  Z3Bool* = Z3Ast[stBool]

# ============================================================================
# Boolean literals
# ============================================================================

proc mkTrue*(ctx: Z3Context): Z3Bool =
  ## The boolean literal `true`.
  wrap[stBool](ctx, ctx.checkErr Z3_mk_true(ctx.raw))
proc mkTrue*(): Z3Bool = mkTrue(requireCurrentContext())

proc mkFalse*(ctx: Z3Context): Z3Bool =
  ## The boolean literal `false`.
  wrap[stBool](ctx, ctx.checkErr Z3_mk_false(ctx.raw))
proc mkFalse*(): Z3Bool = mkFalse(requireCurrentContext())

proc mkBool*(ctx: Z3Context, b: bool): Z3Bool =
  ## Promote a Nim bool to a Z3 boolean literal. Convenience over
  ## `if b: mkTrue() else: mkFalse()` so generic code can write
  ## `mkBool(value)` regardless of which branch.
  if b: mkTrue(ctx) else: mkFalse(ctx)
proc mkBool*(b: bool): Z3Bool = mkBool(requireCurrentContext(), b)

# ============================================================================
# Integer literals
# ============================================================================

proc mkInt*(ctx: Z3Context, n: int): Z3Int =
  ## Integer literal in Z3's `Int` sort. For values outside `cint`
  ## range (32-bit on most platforms), use `mkBigInt(numeral_string)`.
  let s = ctx.checkErr Z3_mk_int_sort(ctx.raw)
  wrap[stInt](ctx, ctx.checkErr Z3_mk_int(ctx.raw, cint(n), s))
proc mkInt*(n: int): Z3Int = mkInt(requireCurrentContext(), n)

proc mkBigInt*(ctx: Z3Context, numeral: string): Z3Int =
  ## Arbitrary-precision integer literal from its decimal string form.
  ## Use for values outside `cint` range:
  ##
  ## ```nim
  ## let big = mkBigInt("123456789012345678901234567890")
  ## ```
  let s = ctx.checkErr Z3_mk_int_sort(ctx.raw)
  wrap[stInt](ctx, ctx.checkErr Z3_mk_numeral(ctx.raw, numeral.cstring, s))
proc mkBigInt*(numeral: string): Z3Int =
  mkBigInt(requireCurrentContext(), numeral)

# ============================================================================
# Real literals
# ============================================================================

proc mkReal*(ctx: Z3Context, num, den: int): Z3Real =
  ## Rational literal `num / den` in Z3's `Real` sort.
  ##
  ## ```nim
  ## let half = mkReal(1, 2)   # "(/ 1.0 2.0)"
  ## ```
  ##
  ## `den == 0` is a sort error caught by Z3 and surfaced as `Z3Error`.
  wrap[stReal](ctx, ctx.checkErr Z3_mk_real(ctx.raw, cint(num), cint(den)))
proc mkReal*(num, den: int): Z3Real =
  mkReal(requireCurrentContext(), num, den)

proc mkReal*(ctx: Z3Context, n: int): Z3Real =
  ## Integer-as-real literal. Equivalent to `mkReal(n, 1)`.
  mkReal(ctx, n, 1)
proc mkReal*(n: int): Z3Real = mkReal(requireCurrentContext(), n)

proc mkBigReal*(ctx: Z3Context, numeral: string): Z3Real =
  ## Arbitrary-precision rational literal from its string form
  ## (`"1/2"`, `"3.14"`, `"1234567890.1234567890"`).
  let s = ctx.checkErr Z3_mk_real_sort(ctx.raw)
  wrap[stReal](ctx, ctx.checkErr Z3_mk_numeral(ctx.raw, numeral.cstring, s))
proc mkBigReal*(numeral: string): Z3Real =
  mkBigReal(requireCurrentContext(), numeral)

# ============================================================================
# Variables ("constants" in SMT-LIB speak)
# ============================================================================
#
# Z3 calls free variables "constants" because they have no body —
# they're fixed in the context but unconstrained until the solver
# assigns a model. We use `Var` in the Nim API names because Nim
# users will think of `x: Int` as a variable.

proc mkIntVar*(ctx: Z3Context, name: string): Z3Int =
  ## Free integer variable named `name` (visible in the model as
  ## `(define-fun name () Int ...)`).
  let s = ctx.checkErr Z3_mk_int_sort(ctx.raw)
  let sym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)
  wrap[stInt](ctx, ctx.checkErr Z3_mk_const(ctx.raw, sym, s))
proc mkIntVar*(name: string): Z3Int =
  mkIntVar(requireCurrentContext(), name)

proc mkRealVar*(ctx: Z3Context, name: string): Z3Real =
  let s = ctx.checkErr Z3_mk_real_sort(ctx.raw)
  let sym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)
  wrap[stReal](ctx, ctx.checkErr Z3_mk_const(ctx.raw, sym, s))
proc mkRealVar*(name: string): Z3Real =
  mkRealVar(requireCurrentContext(), name)

proc mkBoolVar*(ctx: Z3Context, name: string): Z3Bool =
  let s = ctx.checkErr Z3_mk_bool_sort(ctx.raw)
  let sym = ctx.checkErr Z3_mk_string_symbol(ctx.raw, name.cstring)
  wrap[stBool](ctx, ctx.checkErr Z3_mk_const(ctx.raw, sym, s))
proc mkBoolVar*(name: string): Z3Bool =
  mkBoolVar(requireCurrentContext(), name)
