## Spike — validate the architectural assumptions in IMPLEMENTATION_PLAN.md
## before committing to the full library design.
##
## Each section tests one assumption. Run this to verify all are green
## before writing the production wrapper.

import std/[strformat, options]
import softlink

# ============================================================================
# Section 1 — softlink loads libz3 with header verification
# ============================================================================

type
  # Z3's C typedef is `typedef struct _Z3_X * Z3_X;` — the typedef name
  # IS the pointer type. We mirror via `importc` of the typedef name
  # with `bycopy` so Nim emits `Z3_X` (not `Z3_X*`) in C output, and a
  # `pure` empty object so Nim doesn't try to manage its layout.
  RawZ3Config* {.importc: "Z3_config", header: "z3.h", bycopy.} = object
  RawZ3Context* {.importc: "Z3_context", header: "z3.h", bycopy.} = object
  RawZ3Sort* {.importc: "Z3_sort", header: "z3.h", bycopy.} = object
  RawZ3Ast* {.importc: "Z3_ast", header: "z3.h", bycopy.} = object
  RawZ3App* {.importc: "Z3_app", header: "z3.h", bycopy.} = object
  RawZ3Symbol* {.importc: "Z3_symbol", header: "z3.h", bycopy.} = object
  RawZ3Solver* {.importc: "Z3_solver", header: "z3.h", bycopy.} = object
  RawZ3Model* {.importc: "Z3_model", header: "z3.h", bycopy.} = object
  RawZ3FuncDecl* {.importc: "Z3_func_decl", header: "z3.h", bycopy.} = object

# Nil + equality helpers — RawZ3X are opaque value types from Nim's POV;
# we cast them to/from pointer for nil checks.
proc isNil*(x: RawZ3Config | RawZ3Context | RawZ3Sort | RawZ3Ast | RawZ3App |
            RawZ3Symbol | RawZ3Solver | RawZ3Model | RawZ3FuncDecl): bool {.inline.} =
  cast[pointer](x) == nil

type
  # Z3 enums — declared with importc so they map to Z3's own enum types
  # at the C level. softlink's _Static_assert sees the proper Z3 enum
  # name rather than int and accepts it.
  Z3LBool* {.importc: "Z3_lbool", header: "z3.h", size: sizeof(cint).} = enum
    Z3_L_FALSE = -1, Z3_L_UNDEF = 0, Z3_L_TRUE = 1

  Z3ErrorCode* {.importc: "Z3_error_code", header: "z3.h", size: sizeof(cint).} = enum
    Z3_OK = 0, Z3_SORT_ERROR = 1, Z3_IOB = 2, Z3_INVALID_ARG = 3,
    Z3_PARSER_ERROR = 4, Z3_NO_PARSER = 5, Z3_INVALID_PATTERN = 6,
    Z3_MEMOUT_FAIL = 7, Z3_FILE_ACCESS_ERROR = 8, Z3_INTERNAL_FATAL = 9,
    Z3_INVALID_USAGE = 10, Z3_DEC_REF_ERROR = 11, Z3_EXCEPTION = 12

  # Z3_string in C is `const char *`. softlink's GCC pathway doesn't
  # strip const (cpp pathway does); for the spike we use cpp backend
  # to get const handling. The cpp emission has a separate softlink
  # issue with `extern "C" static` we'd need to patch — known issue,
  # not validated in this spike.
  Z3String* {.importc: "Z3_string", header: "z3.h".} = cstring

dynlib "libz3.so(.4|)":
  # Version + lifecycle
  proc Z3_get_full_version(): Z3String {.cdecl, header: "z3.h".}
  proc Z3_mk_config(): RawZ3Config {.cdecl, header: "z3.h".}
  proc Z3_del_config(c: RawZ3Config) {.cdecl, header: "z3.h".}
  proc Z3_mk_context_rc(c: RawZ3Config): RawZ3Context {.cdecl, header: "z3.h".}
  proc Z3_del_context(c: RawZ3Context) {.cdecl, header: "z3.h".}

  # Refcounting
  proc Z3_inc_ref(c: RawZ3Context, a: RawZ3Ast) {.cdecl, header: "z3.h".}
  proc Z3_dec_ref(c: RawZ3Context, a: RawZ3Ast) {.cdecl, header: "z3.h".}
  proc Z3_solver_inc_ref(c: RawZ3Context, s: RawZ3Solver) {.cdecl, header: "z3.h".}
  proc Z3_solver_dec_ref(c: RawZ3Context, s: RawZ3Solver) {.cdecl, header: "z3.h".}
  proc Z3_model_inc_ref(c: RawZ3Context, m: RawZ3Model) {.cdecl, header: "z3.h".}
  proc Z3_model_dec_ref(c: RawZ3Context, m: RawZ3Model) {.cdecl, header: "z3.h".}

  # Sorts
  proc Z3_mk_int_sort(c: RawZ3Context): RawZ3Sort {.cdecl, header: "z3.h".}
  proc Z3_mk_bool_sort(c: RawZ3Context): RawZ3Sort {.cdecl, header: "z3.h".}

  # Symbols + variables
  proc Z3_mk_string_symbol(c: RawZ3Context, s: cstring): RawZ3Symbol {.cdecl, header: "z3.h".}
  proc Z3_mk_const(c: RawZ3Context, s: RawZ3Symbol, ty: RawZ3Sort): RawZ3Ast {.cdecl, header: "z3.h".}

  # Numerals
  proc Z3_mk_int(c: RawZ3Context, v: cint, ty: RawZ3Sort): RawZ3Ast {.cdecl, header: "z3.h".}

  # Boolean ops
  proc Z3_mk_eq(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_and(c: RawZ3Context, num_args: cuint, args: ptr UncheckedArray[RawZ3Ast]): RawZ3Ast {.cdecl, header: "z3.h".}

  # Arithmetic
  proc Z3_mk_add(c: RawZ3Context, num_args: cuint, args: ptr UncheckedArray[RawZ3Ast]): RawZ3Ast {.cdecl, header: "z3.h".}
  proc Z3_mk_gt(c: RawZ3Context, l, r: RawZ3Ast): RawZ3Ast {.cdecl, header: "z3.h".}

  # Solver
  proc Z3_mk_solver(c: RawZ3Context): RawZ3Solver {.cdecl, header: "z3.h".}
  proc Z3_solver_assert(c: RawZ3Context, s: RawZ3Solver, a: RawZ3Ast) {.cdecl, header: "z3.h".}
  proc Z3_solver_check(c: RawZ3Context, s: RawZ3Solver): Z3LBool {.cdecl, header: "z3.h".}
  proc Z3_solver_get_model(c: RawZ3Context, s: RawZ3Solver): RawZ3Model {.cdecl, header: "z3.h".}

  # Model
  proc Z3_model_eval(c: RawZ3Context, m: RawZ3Model, t: RawZ3Ast,
                     model_completion: bool, v: ptr RawZ3Ast): bool {.cdecl, header: "z3.h".}
  proc Z3_get_numeral_int(c: RawZ3Context, v: RawZ3Ast, i: ptr cint): bool {.cdecl, header: "z3.h".}

  # Error handling
  proc Z3_get_error_code(c: RawZ3Context): Z3ErrorCode {.cdecl, header: "z3.h".}

  # Pretty-print
  proc Z3_ast_to_string(c: RawZ3Context, a: RawZ3Ast): Z3String {.cdecl, header: "z3.h".}

  # Stats (for leak detection)
  proc Z3_finalize_memory() {.cdecl, header: "z3.h".}

# ============================================================================
# Section 2 — minimal idiomatic Nim layer (Z3Context + Z3Ast[Sort])
# ============================================================================

type
  SortTag* = enum
    stInt, stBool

  Z3ContextOwn = object
    raw: RawZ3Context
    cfg: RawZ3Config
  Z3Context* = ref Z3ContextOwn

  Z3Ast*[S: static SortTag] = object
    raw: RawZ3Ast
    ctx: Z3Context

  Z3SolverOwn = object
    raw: RawZ3Solver
    ctx: Z3Context
  Z3Solver* = ref Z3SolverOwn

  Z3ModelOwn = object
    raw: RawZ3Model
    ctx: Z3Context
  Z3Model* = ref Z3ModelOwn

  Z3Status* = enum
    zsUnsat = -1
    zsUnknown = 0
    zsSat = 1

# --- Context lifecycle ---

proc `=destroy`(c: Z3ContextOwn) {.raises: [].} =
  try:
    if not c.raw.isNil: Z3_del_context(c.raw)
    if not c.cfg.isNil: Z3_del_config(c.cfg)
  except CatchableError: discard

proc newContext*(): Z3Context =
  let r = loadZ3()
  if r.kind != lrOk:
    raise newException(IOError, "failed to load libz3: " & $r.kind)
  let cfg = Z3_mk_config()
  let ctx = Z3_mk_context_rc(cfg)
  Z3Context(raw: ctx, cfg: cfg)

# --- AST lifecycle ---

proc `=destroy`[S: static SortTag](a: Z3Ast[S]) {.raises: [].} =
  try:
    if not a.raw.isNil and a.ctx != nil and not a.ctx.raw.isNil:
      Z3_dec_ref(a.ctx.raw, a.raw)
  except CatchableError: discard

proc `=copy`[S: static SortTag](dst: var Z3Ast[S], src: Z3Ast[S]) {.raises: [].} =
  if dst.raw != src.raw:
    try:
      if not dst.raw.isNil and dst.ctx != nil and not dst.ctx.raw.isNil:
        Z3_dec_ref(dst.ctx.raw, dst.raw)
      dst.raw = src.raw
      dst.ctx = src.ctx
      if not dst.raw.isNil and dst.ctx != nil and not dst.ctx.raw.isNil:
        Z3_inc_ref(dst.ctx.raw, dst.raw)
    except CatchableError: discard

# --- Solver lifecycle ---

proc `=destroy`(s: Z3SolverOwn) {.raises: [].} =
  try:
    if not s.raw.isNil and s.ctx != nil and not s.ctx.raw.isNil:
      Z3_solver_dec_ref(s.ctx.raw, s.raw)
  except CatchableError: discard

proc `=destroy`(m: Z3ModelOwn) {.raises: [].} =
  try:
    if not m.raw.isNil and m.ctx != nil and not m.ctx.raw.isNil:
      Z3_model_dec_ref(m.ctx.raw, m.raw)
  except CatchableError: discard

# --- AST construction helpers (manage refcount on creation) ---

proc wrap[S: static SortTag](ctx: Z3Context, raw: RawZ3Ast): Z3Ast[S] =
  result = Z3Ast[S](raw: raw, ctx: ctx)
  if not raw.isNil:
    Z3_inc_ref(ctx.raw, raw)

# Integer constructors
proc mkInt*(ctx: Z3Context, v: int): Z3Ast[stInt] =
  let sort = Z3_mk_int_sort(ctx.raw)
  let raw = Z3_mk_int(ctx.raw, cint(v), sort)
  wrap[stInt](ctx, raw)

proc mkIntVar*(ctx: Z3Context, name: string): Z3Ast[stInt] =
  let sort = Z3_mk_int_sort(ctx.raw)
  let sym = Z3_mk_string_symbol(ctx.raw, name.cstring)
  let raw = Z3_mk_const(ctx.raw, sym, sort)
  wrap[stInt](ctx, raw)

# Boolean variable
proc mkBoolVar*(ctx: Z3Context, name: string): Z3Ast[stBool] =
  let sort = Z3_mk_bool_sort(ctx.raw)
  let sym = Z3_mk_string_symbol(ctx.raw, name.cstring)
  let raw = Z3_mk_const(ctx.raw, sym, sort)
  wrap[stBool](ctx, raw)

# Arithmetic — only on Int (phantom-typed)
proc `+`*(a, b: Z3Ast[stInt]): Z3Ast[stInt] =
  var args = [a.raw, b.raw]
  let raw = Z3_mk_add(a.ctx.raw, 2, cast[ptr UncheckedArray[RawZ3Ast]](addr args[0]))
  wrap[stInt](a.ctx, raw)

# Comparison — Int x Int -> Bool
proc `>`*(a, b: Z3Ast[stInt]): Z3Ast[stBool] =
  let raw = Z3_mk_gt(a.ctx.raw, a.raw, b.raw)
  wrap[stBool](a.ctx, raw)

# Equality — same sort -> Bool
proc `==`*[S: static SortTag](a, b: Z3Ast[S]): Z3Ast[stBool] =
  let raw = Z3_mk_eq(a.ctx.raw, a.raw, b.raw)
  wrap[stBool](a.ctx, raw)

# Boolean ops
proc `and`*(a, b: Z3Ast[stBool]): Z3Ast[stBool] =
  var args = [a.raw, b.raw]
  let raw = Z3_mk_and(a.ctx.raw, 2, cast[ptr UncheckedArray[RawZ3Ast]](addr args[0]))
  wrap[stBool](a.ctx, raw)

# Pretty-print
proc `$`*[S: static SortTag](a: Z3Ast[S]): string =
  $Z3_ast_to_string(a.ctx.raw, a.raw)

# Solver
proc mkSolver*(ctx: Z3Context): Z3Solver =
  let raw = Z3_mk_solver(ctx.raw)
  Z3_solver_inc_ref(ctx.raw, raw)
  Z3Solver(raw: raw, ctx: ctx)

proc assert*(s: Z3Solver, e: Z3Ast[stBool]) =
  Z3_solver_assert(s.ctx.raw, s.raw, e.raw)

proc check*(s: Z3Solver): Z3Status =
  let r = Z3_solver_check(s.ctx.raw, s.raw)
  Z3Status(ord(r))

proc model*(s: Z3Solver): Z3Model =
  let raw = Z3_solver_get_model(s.ctx.raw, s.raw)
  Z3_model_inc_ref(s.ctx.raw, raw)
  Z3Model(raw: raw, ctx: s.ctx)

proc evalInt*(m: Z3Model, v: Z3Ast[stInt]): Option[int] =
  var resAst: RawZ3Ast
  if not Z3_model_eval(m.ctx.raw, m.raw, v.raw, true, addr resAst):
    return none(int)
  Z3_inc_ref(m.ctx.raw, resAst)
  defer: Z3_dec_ref(m.ctx.raw, resAst)
  var n: cint
  if Z3_get_numeral_int(m.ctx.raw, resAst, addr n):
    some(int(n))
  else:
    none(int)

# ============================================================================
# Section 3 — verification harness
# ============================================================================

var failures = 0
var passes = 0

template check(name: string, cond: bool, detail: string = "") =
  if cond:
    echo "  PASS  ", name
    inc passes
  else:
    echo "  FAIL  ", name, (if detail.len > 0: "  --  " & detail else: "")
    inc failures

proc section(name: string) =
  echo ""
  echo "=== ", name, " ==="

# ----------------------------------------------------------------------------
section "1: softlink loads libz3 + header verification compiles"
let loadRes = loadZ3()
check "loadZ3 returns lrOk", loadRes.kind == lrOk,
  "got " & $loadRes.kind
check "z3Loaded() reports true", z3Loaded()

# ----------------------------------------------------------------------------
section "2: raw FFI smoke (version, config, context lifecycle)"
let version = $Z3_get_full_version()
check "Z3_get_full_version returns non-empty", version.len > 0,
  "got: " & version
echo "        Z3 version: ", version

block:
  let cfg = Z3_mk_config()
  check "Z3_mk_config returns non-nil", not cfg.isNil
  let ctx = Z3_mk_context_rc(cfg)
  check "Z3_mk_context_rc returns non-nil", not ctx.isNil
  Z3_del_context(ctx)
  Z3_del_config(cfg)
  check "manual context+config lifecycle survives delete", true

# ----------------------------------------------------------------------------
section "3: Z3Context with =destroy hook (idiomatic Nim lifecycle)"
block:
  let ctx = newContext()
  check "newContext returns non-nil context", ctx != nil and not ctx.raw.isNil
  # =destroy fires when ctx goes out of scope; no observable failure modes
  # short of crashing means it worked.

# ----------------------------------------------------------------------------
section "4: Z3Ast[S] phantom-sort construction + refcount discipline"
block:
  let ctx = newContext()
  let x = ctx.mkIntVar("x")
  let y = ctx.mkIntVar("y")
  check "mkIntVar(x) returns non-nil Z3Ast[stInt]", not x.raw.isNil
  check "mkIntVar(y) returns non-nil Z3Ast[stInt]", not y.raw.isNil

  # Test =copy: explicit copy preserves the raw pointer (refcount bumped)
  var z = x
  check "var z = x produces equal raw pointer", z.raw == x.raw

# ----------------------------------------------------------------------------
section "5: phantom-sort safety (compile-time)"
# These checks live in `when compiles(...)` — they assert that
# operations across sorts FAIL TO COMPILE.
block:
  let ctx = newContext()
  let x = ctx.mkIntVar("x")
  let b = ctx.mkBoolVar("b")

  check "Int + Int compiles", compiles(x + x)
  check "Int + Bool does NOT compile", not compiles(x + b)
  check "Bool > Bool does NOT compile", not compiles(b > b)
  check "Int == Int compiles", compiles(x == x)
  check "Bool == Bool compiles", compiles(b == b)
  check "Int == Bool does NOT compile", not compiles(x == b)
  check "Bool and Bool compiles", compiles(b and b)
  check "Int and Int does NOT compile", not compiles(x and x)

# ----------------------------------------------------------------------------
section "6: end-to-end solve (x + y == 10) and (x > 3)"
block:
  let ctx = newContext()
  let x = ctx.mkIntVar("x")
  let y = ctx.mkIntVar("y")
  let ten = ctx.mkInt(10)
  let three = ctx.mkInt(3)

  let constraint = (x + y == ten) and (x > three)
  echo "        constraint:"
  echo "          ", $constraint

  let s = ctx.mkSolver()
  s.assert(constraint)
  let status = s.check()
  check "solver returns sat", status == zsSat,
    "got " & $status

  if status == zsSat:
    let m = s.model()
    let xv = m.evalInt(x)
    let yv = m.evalInt(y)
    check "model[x] is some(value)", xv.isSome
    check "model[y] is some(value)", yv.isSome
    if xv.isSome and yv.isSome:
      echo "        model: x = ", xv.get, ", y = ", yv.get
      check "x + y == 10 in the model", xv.get + yv.get == 10
      check "x > 3 in the model", xv.get > 3

# ----------------------------------------------------------------------------
section "7: defensive — many AST creations don't leak (smoke)"
block:
  # Hard-to-measure programmatically without valgrind, but we can at least
  # verify the program doesn't crash creating + destroying many Z3 objects.
  for i in 0 ..< 1000:
    let ctx = newContext()
    let x = ctx.mkIntVar("x")
    let y = ctx.mkIntVar("y")
    let s = ctx.mkSolver()
    s.assert(x + y == ctx.mkInt(i))
    discard s.check()
  check "1000 context+solver lifecycles complete without crash", true

# ============================================================================
# Final report
# ============================================================================

echo ""
echo "============================================================"
echo &"  Result: {passes} pass, {failures} fail"
echo "============================================================"
if failures > 0:
  quit(1)
