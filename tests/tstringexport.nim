## v0.5.0 audit fixup #8 — verify z3/strings's `export sequence`
## actually surfaces the generic Z3Seq operations on Z3String.
import std/[unittest]
import z3/strings
import z3/context  # for newContext

suite "z3/strings re-exports z3/sequence":
  test "Z3Seq ops (len, concat, &) are reachable through z3/strings":
    let ctx = newContext()
    let s = mkString("abc")
    let t = mkString("xyz")
    # `&` is a Z3Seq operator (sequence.nim). If string.nim's
    # `export sequence` is broken, this wouldn't compile.
    let st = s & t
    check ($st).len > 0
    # `len` is also a Z3Seq op.
    let n = s.len
    check ($n).len > 0
