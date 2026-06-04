## `z3/chars` — `>` / `>=` codepoint ordering.
##
## `a > b`  ≡  `b < a`   (arg swap)
## `a >= b` ≡  `b <= a`  (arg swap)
##
## All formulae are ground (no free variables), so validity and
## satisfiability coincide: a ground SMT formula is valid iff it's
## satisfiable iff it's true. `smtValid` is the natural predicate.

import std/[unittest]
import z3

suite "Z3Char — > and >=":
  test "> is SAT when left codepoint is strictly greater":
    ## 'B' (66) > 'A' (65) — ground tautology.
    let ctx = newContext()
    check smtValid(mkChar('B') > mkChar('A'))

  test ">= is SAT for equal codepoints":
    ## 'A' >= 'A' — reflexivity, ground tautology.
    let ctx = newContext()
    check smtValid(mkChar('A') >= mkChar('A'))

  test "> is UNSAT for equal codepoints":
    ## 'A' > 'A' — irreflexivity: strict ordering is false on equal args.
    let ctx = newContext()
    check smtValid(not (mkChar('A') > mkChar('A')))
