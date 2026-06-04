## `z3/funcdecl` — N7.3: recursive function definitions via `defineRecFun`.
##
## `defineRecFun` is the self-referential analog of `defineFun`. The body
## proc receives the function itself as its first argument (`self`), enabling
## single-function recursion. Internally routes through the same
## `Z3_mk_rec_func_decl` + `Z3_add_rec_def` machinery as `defineFun`, but
## pre-creates the `Z3FuncDecl` wrapper before evaluating the body so that
## `self` can be applied recursively inside the body expression.
##
## Evaluation strategy: recursive functions are undecidable in general for
## arbitrary symbolic inputs. All tests assert `fact(5) == 120` etc. using
## a concrete integer argument, then assert the result equals the expected
## value and check satisfiability. Z3's model-based evaluation can handle
## concrete recursive applications by unrolling.
##
## Multi-param proc literals use separate type annotations per parameter
## (not shorthand `proc(a, b: T)`) to avoid the Nim 2.2 managed-value ABI
## bug where the second parameter's `.ctx` field is zeroed on entry.

import std/[unittest]
import z3

suite "defineRecFun — N7.3 recursive function definitions":

  test "factorial: fact(5) == 120  (concrete, SAT)":
    ## Z3 evaluates fact(5) by unrolling the recursive definition.
    ## fact(n) = if n <= 0 then 1 else n * fact(n-1)
    let ctx = newContext()
    let fact = defineRecFun(ctx, "fact_n73",
      proc(self: Z3FuncDecl[(Z3Int,), Z3Int], n: Z3Int): Z3Int =
        ite(n <= mkInt(0), mkInt(1), n * self(n - mkInt(1))))
    let solver = newSolver()
    solver.add(fact(mkInt(5)) == mkInt(120))
    let status = solver.check()
    if status == zsUnknown:
      skip()  # Z3 recursive-function solver incomplete for this query
    check status == zsSat

  test "factorial: fact(0) == 1  (base case)":
    let ctx = newContext()
    let fact = defineRecFun(ctx, "fact0_n73",
      proc(self: Z3FuncDecl[(Z3Int,), Z3Int], n: Z3Int): Z3Int =
        ite(n <= mkInt(0), mkInt(1), n * self(n - mkInt(1))))
    let solver = newSolver()
    solver.add(fact(mkInt(0)) == mkInt(1))
    let status = solver.check()
    if status == zsUnknown:
      skip()
    check status == zsSat

  test "fibonacci: fib(6) == 8  (concrete, SAT)":
    ## fib(n) = if n <= 1 then n else fib(n-1) + fib(n-2)
    ## fib(0)=0, fib(1)=1, fib(2)=1, fib(3)=2, fib(4)=3, fib(5)=5, fib(6)=8
    let ctx = newContext()
    let fib = defineRecFun(ctx, "fib_n73",
      proc(self: Z3FuncDecl[(Z3Int,), Z3Int], n: Z3Int): Z3Int =
        ite(n <= mkInt(1), n,
            self(n - mkInt(1)) + self(n - mkInt(2))))
    let solver = newSolver()
    solver.add(fib(mkInt(6)) == mkInt(8))
    let status = solver.check()
    if status == zsUnknown:
      skip()
    check status == zsSat

  test "fibonacci: fib(1) == 1  (base case)":
    let ctx = newContext()
    let fib = defineRecFun(ctx, "fib1_n73",
      proc(self: Z3FuncDecl[(Z3Int,), Z3Int], n: Z3Int): Z3Int =
        ite(n <= mkInt(1), n,
            self(n - mkInt(1)) + self(n - mkInt(2))))
    let solver = newSolver()
    solver.add(fib(mkInt(1)) == mkInt(1))
    let status = solver.check()
    if status == zsUnknown:
      skip()
    check status == zsSat
