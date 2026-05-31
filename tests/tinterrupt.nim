## `interrupt` — cross-thread cancellation of a long-running check.
## v1.0 audit round 2, item #1 (CRITICAL).

import std/[unittest, os, atomics, times]
import z3

suite "Z3Context — interrupt":
  test "long-running check cancels promptly when interrupted":
    # Build a hard SAT instance: pigeonhole at moderate size, which
    # Z3's default solver takes a few seconds to crack with a long
    # timeout disabled. We start the check on the main thread, fire
    # interrupt from a worker thread after a short delay, and assert
    # the check returns zsUnknown within a tight wall-clock window.
    let ctx = newContext()
    # 12 pigeons in 11 holes — unsat, but Z3 spends real time proving it.
    const N = 12
    var pigeons: array[N, array[N-1, Z3Bool]]
    for i in 0 ..< N:
      for j in 0 ..< N-1:
        pigeons[i][j] = mkBoolVar("p_" & $i & "_" & $j)
    let s = newSolver()
    # Every pigeon goes in at least one hole.
    for i in 0 ..< N:
      s.add mkOr(pigeons[i])
    # No two pigeons share a hole.
    for j in 0 ..< N-1:
      for i in 0 ..< N:
        for k in (i+1) ..< N:
          s.add not (pigeons[i][j] and pigeons[k][j])

    # Spawn a worker that calls ctx.interrupt() after a brief delay.
    var fired: Atomic[bool]
    fired.store(false)
    proc workerProc(args: tuple[ctx: Z3Context, fired: ptr Atomic[bool]]) {.thread.} =
      sleep(150)
      args.ctx.interrupt()
      args.fired[].store(true)

    var worker: Thread[tuple[ctx: Z3Context, fired: ptr Atomic[bool]]]
    createThread(worker, workerProc, (ctx, addr fired))

    let t0 = epochTime()
    let res = s.check()
    let elapsed = epochTime() - t0
    joinThread(worker)

    check fired.load()
    # Z3 honored the interrupt: returned within a small window of when
    # the interrupt fired (150ms + slack).
    check elapsed < 3.0
    # The interrupt path yields zsUnknown (not unsat, even though the
    # formula is unsat — we cancelled before Z3 finished proving it).
    check res == zsUnknown
