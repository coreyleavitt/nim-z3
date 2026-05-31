## SMT-LIB2 round-trip example — write, parse, solve.
##
## A common workflow when interoperating with other SMT tools (cvc5,
## Yices, MathSAT, …) is to serialise a problem as SMT-LIB2 and pass
## it around as text. nim-z3 supports the full cycle:
##
##   * `toSmt2Benchmark(formula, …)` → string render
##   * `parseSmt2String(ctx, text)` → seq[Z3Bool] re-parsed in `ctx`
##   * `parseSmt2File(ctx, path)` → same, from a file
##   * `Z3ParserContext` → streaming parser that remembers decls
##     across calls (useful for incremental scripts)
##
## We demonstrate write → roundtrip → solve, plus loading from a
## file written to /tmp.
##
## Run with:
##
## ```
## nim c -r examples/smt2_roundtrip.nim
## ```

import std/[strformat, os]
import z3

proc main() =
  let ctx = newContext()

  # Build a constraint in nim-z3 directly.
  let x = mkIntVar("x")
  let y = mkIntVar("y")
  let formula = (x + y == mkInt(10)) and (x > mkInt(3)) and (y > mkInt(0))

  # --- Step 1: Render as SMT-LIB2 benchmark text ---------------------------
  let smt2 = toSmt2Benchmark(formula,
    name = "round-trip-demo",
    logic = "QF_LIA",
    status = "sat")
  echo "=== Rendered SMT2 ==="
  echo smt2

  # --- Step 2: Parse the text back into a fresh context --------------------
  let ctxB = newContext()
  let asserts = parseSmt2String(ctxB, smt2)
  doAssert asserts.len >= 1
  echo &"\nParsed {asserts.len} assertion(s) back into context B."

  # --- Step 3: Solve the re-parsed version ---------------------------------
  let s = newSolver(ctxB)
  for a in asserts:
    s.add a
  doAssert s.check() == zsSat
  let m = s.model()
  echo "Round-trip solve found a model in context B."
  # We can't `m.evalInt(x)` directly — x was constructed in ctx (not ctxB).
  # Instead extract via SMT2 model rendering.
  echo "Model:\n", $m

  # --- Step 4: Write to a file and parse it back ---------------------------
  let path = getTempDir() / "nim_z3_demo.smt2"
  writeFile(path, smt2)
  echo &"\nWrote SMT2 to {path}"

  let ctxC = newContext()
  let fromFile = parseSmt2File(ctxC, path)
  doAssert fromFile.len == asserts.len
  echo &"parseSmt2File brought back the same {fromFile.len} assertions."

  let sC = newSolver(ctxC)
  for a in fromFile:
    sC.add a
  doAssert sC.check() == zsSat
  echo "File-loaded model is also sat. Round-trip complete."

  removeFile(path)

when isMainModule:
  main()
