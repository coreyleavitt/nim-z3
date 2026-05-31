# Cross-family parity contract

> **Audience: contributors.** When you add a new typed family to
> nim-z3 (a new `Z3Foo` value type or `Z3Foo` ref handle), this is the
> checklist that ensures the family fits the wrapper's `Z3Term`-load-
> bearing concept and matches the cross-cutting surfaces every other
> family supports.
>
> See also: [GOTCHAS.md](GOTCHAS.md) (user-facing pitfalls),
> [INTERNAL_API.md](INTERNAL_API.md) (the "promoted private→public for
> sibling modules" seam).

The `Z3Term` concept (defined in `src/z3/lifecycle.nim`) is:

```nim
type Z3Term* = concept x
  x.raw is RawZ3Ast
  x.ctx is Z3Context
```

Anything matching this gets a long list of cross-cutting surfaces
automatically: `wrap[T]`, `eval[T]`, `smtEquiv[T]`, `astEqual[T]`,
generic `$[T]` (v0.5 step 3D), and `pretty[T]` (v0.5 step 3A via the
`Z3Renderable` super-concept). For the architectural concept to stay
load-bearing, every typed value family **must** match `Z3Term` and
follow the conventions below.

---

## 1. Typed AST value families (`Z3Foo` value type)

For a new value family carrying a `RawZ3Ast`:

### 1.1 Type definition (in `src/z3/foo.nim`)

```nim
type
  Z3Foo* = object
    raw*: RawZ3Ast
    ctx*: Z3Context
```

Fields **must** be `raw*` and `ctx*` (exported) to satisfy the
`Z3Term` concept and let cross-cutting templates see them.

### 1.2 Lifecycle (`emitTermLifecycle`)

```nim
emitTermLifecycle(Z3Foo, Z3_dec_ref, Z3_inc_ref)
```

If the underlying handle needs a special refcount path (like
`Z3Pattern`'s `Z3_pattern_to_ast` round-trip), see the
`emitTermLifecycle` docstring for the custom-handle form.

### 1.3 `sortOf` overload

```nim
proc sortOf*(_: typedesc[Z3Foo], ctx: Z3Context): RawZ3Sort {.inline.} =
  ctx.checkErr Z3_mk_foo_sort(ctx.raw)
```

This participates in `z3/sortdispatch` resolution so `Z3Seq[Z3Foo]`,
`Z3Array[Z3Foo, Z3Bar]`, etc. work. Required for compositional types.

### 1.4 Construction

Two patterns, in this order:

```nim
proc mkFoo*(ctx: Z3Context, args...): Z3Foo = ...
proc mkFoo*(args...): Z3Foo = mkFoo(requireCurrentContext(), args...)

proc mkFooVar*(ctx: Z3Context, name: string): Z3Foo = ...
proc mkFooVar*(name: string): Z3Foo = mkFooVar(requireCurrentContext(), name)
```

Every family that admits free variables ships `mkFooVar`. (Char added
this in v0.5 step 3C — was missing.)

### 1.5 Operators

`==` and `!=` are family-specific (return `Z3Bool`); equality
semantics are at the family's discretion (most use SMT structural
equality via `Z3_mk_eq`; `Z3Fp` uses IEEE 754 equality via
`Z3_mk_fpa_eq`). Document the choice loudly in the module docstring.

### 1.6 No explicit `$` needed

The generic `$[T: Z3Term]` in `z3/ast.nim` covers every Z3Term value
family. Don't add a per-family `$` — it would shadow the generic.

### 1.7 No explicit `astEqual` needed

The generic `astEqual[T: Z3Term]` in `z3/ast.nim` covers every family.

### 1.8 No explicit `pretty` needed

The generic `pretty[T: Z3Renderable]` in `z3/pretty.nim` covers every
family that has `$` and `.ctx` (i.e. every typed value family AND
every ref handle).

### 1.9 Model extraction — `toXxx` (AST-level) + `evalXxx` (model-level)

Convention:

```nim
proc toXxx*(a: Z3Foo): Xxx = ...        # in foo.nim or model.nim
proc evalXxx*(m: Z3Model, a: Z3Foo,
              modelCompletion = true): Xxx {.inline.} =
  m.eval(a, modelCompletion).toXxx
```

**Rule:** if `toXxx(a: Z3Foo)` extracts a Nim value from a literal
AST, there is a matching `evalXxx(m, a)` shortcut. Closes the
"evaluate then extract" two-step into a one-liner.

Current evalXxx inventory (after v0.5 step 3):

| Family | Shortcut | Returns |
|---|---|---|
| `Z3Int` | `evalInt(m, a)` | `int` |
| `Z3Bool` | `evalBool(m, a)` | `bool` |
| `Z3Real` | `evalReal(m, a)` | `float` |
| `Z3Int` (big) | `evalBigIntStr(m, a)` | `string` |
| `Z3Real` (big) | `evalBigRealStr(m, a)` | `string` |
| `Z3BitVec[W]` | `evalUint(m, a)` | `uint64` |
| `Z3BitVec[W]` | `evalInt(m, a)` | `int64` (signed 2's-complement) |
| `Z3Float32` | `evalFloat32(m, a)` | `float32` |
| `Z3Float64` | `evalFloat64(m, a)` | `float` (float64) |
| `Z3String` | `evalStr(m, a)` | `string` |
| `Z3Char` | `evalChar(m, a)` | `int` (Unicode codepoint) |
| `Z3Seq[E]` | `evalSeqLen(m, a)` | `int` (length) |

`Z3Float16` / `Z3Float128` / `Z3DatatypeValue[T]` are intentionally
absent — no native Nim type for those widths, and datatype-value
extraction needs the case-discriminator surface from `z3/datatypes`.
Both deferred per v0.4 §8b.

---

## 2. Ref handles (non-`Z3Term` families)

Ref-handle families (`Z3Solver`, `Z3Model`, `Z3Goal`, `Z3Tactic`,
`Z3Fixedpoint`, `Z3Optimize`, `Z3Params`, `Z3Stats`, `Z3AstVector`,
`Z3Probe`, `Z3ParserContext`, `Z3FuncDecl[A, R]`) don't carry
`RawZ3Ast` and so don't match `Z3Term`. They need explicit
per-handle versions of:

- `$` (typically `$Z3_xxx_to_string(ctx.raw, h.raw)`)
- `pretty` (falls through to the generic `Z3Renderable` if `$` is
  defined and `.ctx` is exported; no per-handle override needed)
- Refcount lifecycle via `emitRefcountLifecycle(Z3FooOwn, Z3_foo_dec_ref)`

They typically don't need `astEqual` (handles aren't compared for
AST identity).

---

## 3. The "for every new family, here's what you implement" rule

When you add a new `Z3Foo` typed family:

- [ ] Type def with `raw*: RawZ3Ast` + `ctx*: Z3Context`
- [ ] `emitTermLifecycle(Z3Foo, ...)`
- [ ] `sortOf*(_: typedesc[Z3Foo], ctx)` for sortdispatch
- [ ] `mkFoo(ctx, ...)` + ctx-less overload
- [ ] `mkFooVar(ctx, name)` + ctx-less overload (if variables exist)
- [ ] Family-specific `==` / `!=` (with IEEE-equality docstring if
      semantics diverge)
- [ ] `toXxx(a: Z3Foo): Xxx` extractor (if a useful Nim-side value
      can be pulled from a literal)
- [ ] `evalXxx(m: Z3Model, a: Z3Foo): Xxx` shortcut (paired with
      `toXxx` per §1.9)
- [ ] Add a section to this file documenting the new family's eval
      pattern
- [ ] Add tests covering at least: construction, equality, `==`
      compile-time sort safety (if applicable), model round-trip
      through `evalXxx`

You do **NOT** need to add `$`, `astEqual`, or `pretty` per-family
— the generics cover them automatically once `Z3Term` matches.

---

## 4. Cross-references

- `src/z3/lifecycle.nim` — `Z3Term` concept + lifecycle template
  generators (`emitTermLifecycle`, `emitRefcountLifecycle`).
- `src/z3/ast.nim` — generic `$[T: Z3Term]`, `astEqual[T: Z3Term]`,
  `==` / `!=` (generic over `Z3Ast[S]`).
- `src/z3/pretty.nim` — generic `pretty[T: Z3Renderable]`.
- `src/z3/sortdispatch.nim` — `sortOf` resolution that picks up new
  families automatically once they ship the overload.
- `src/z3/semantics.nim` — generic `smtValid` / `smtEquiv[T]`.

For deeper rationale on the architectural unification this parity
contract enforces, see [V0.3_PLAN.md](V0.3_PLAN.md) §1 step 1
(`Z3Term` introduction) and the v0.5 step 3 entries in §8 of
[IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md).
