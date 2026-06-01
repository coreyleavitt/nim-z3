## Task-scheduling with Z3Optimize — hard constraints + soft
## preferences + a maximised objective.
##
## Problem: schedule four tasks into discrete time slots `t_i ∈ {0..9}`.
##
##   Hard:
##     * Each pair (t_i, t_j) must differ — no two tasks share a slot.
##     * Task 0 must finish before task 3 (`t_0 < t_3`).
##     * Total span `max(t_i) - min(t_i)` ≤ 6 — finish within a window.
##
##   Soft (preferences):
##     * `t_0 == 1` weight 3 — we'd like task 0 in slot 1.
##     * `t_2 == 4` weight 2 — task 2 in slot 4 is mildly preferred.
##     * `t_3 == 8` weight 1 — task 3 in slot 8 is a faint preference.
##
##   Maximise: `sum(value_i × scheduled_i)` where each task has a value,
##   and `scheduled_i` is a 0/1 indicator. Demonstrates a value-
##   maximisation objective alongside MaxSAT-style soft constraints.
##
## What this example demonstrates:
##   * `Z3Optimize` (`newOptimize`) — distinct from `Z3Solver` for
##     soft constraints and `maximize` / `minimize` objectives.
##   * `o.add(c)` — hard constraints (must hold).
##   * `o.addSoft(c, weight, group)` — soft preferences (cost on
##     violation).
##   * `o.maximize(expr)` — objective; returns a `Z3OptHandle[T]`.
##   * `o.withFrame:` — RAII frame management (v0.5.0 audit B2).
##   * `o.getParamDescrs()` — discoverable tunable params (v0.5.0
##     audit B3).
##   * `o.check()` + `o.model()` — solve and extract.
##   * `Z3OptHandle.upper` — read off the achieved objective bound.
##
## Run with:
##
## ```
## nim c -r examples/optimize_scheduling.nim
## ```

import std/[strformat, sequtils]
import z3

proc main() =
  let ctx = newContext()
  const NumTasks = 4
  const MaxSlot = 9
  # Per-task value (the maximisation reward for scheduling task i).
  const Values = [10, 7, 5, 8]

  # Time-slot variables.
  var tasks: array[NumTasks, Z3Int]
  for i in 0 ..< NumTasks:
    tasks[i] = mkIntVar("t_" & $i)

  let o = newOptimize()

  # ---- Hard constraints ---------------------------------------------------
  for i in 0 ..< NumTasks:
    o.add tasks[i] >= mkInt(0)
    o.add tasks[i] <= mkInt(MaxSlot)
  # All slots distinct — collapses to one call thanks to the v0.5.0
  # B5 mkDistinct[T: Z3Term] generic.
  o.add mkDistinct(tasks[0], tasks[1], tasks[2], tasks[3])
  # Precedence: task 0 strictly before task 3.
  o.add tasks[0] < tasks[3]

  # Total span ≤ 6.
  # max - min via pairwise: forall i,j: t_j - t_i <= 6.
  for i in 0 ..< NumTasks:
    for j in 0 ..< NumTasks:
      o.add tasks[j] - tasks[i] <= mkInt(6)

  # ---- Soft preferences ---------------------------------------------------
  discard o.addSoft(tasks[0] == mkInt(1), 3, "prefs")
  discard o.addSoft(tasks[2] == mkInt(4), 2, "prefs")
  discard o.addSoft(tasks[3] == mkInt(8), 1, "prefs")

  # ---- Objective: sum of task values, all four scheduled  ------------------
  # Since every task must land in [0, MaxSlot] (a hard constraint above),
  # `scheduled_i` is always true here. We still register the maximisation
  # to demonstrate the objective surface — Z3 will report the sum bound.
  var totalValue = mkInt(0)
  for i in 0 ..< NumTasks:
    totalValue = totalValue + mkInt(Values[i])
  let valueObj = o.maximize(totalValue)

  # ---- withFrame demonstration --------------------------------------------
  # We probe a what-if scenario inside a frame: "what if task 1 must
  # be in slot 5?" The frame ensures the probe doesn't leak.
  echo "What-if probe (frame): force task 1 into slot 5"
  o.withFrame:
    o.add tasks[1] == mkInt(5)
    let status = o.check()
    echo &"  status under probe: {status}"
    if status == zsSat:
      let m = o.model()
      for i in 0 ..< NumTasks:
        echo &"    t_{i} = {m.evalInt(tasks[i])}"
  # Frame popped — the probe constraint is gone.

  # ---- Parameter introspection -------------------------------------------
  # getParamDescrs() exposes the schema of tunable knobs for this
  # optimiser. Useful when wiring an optimiser into a config file.
  echo "\nAvailable optimiser params (count): ", o.getParamDescrs().len

  # ---- Final solve --------------------------------------------------------
  echo "\nFinal solve (no probe):"
  let status = o.check()
  echo &"  status: {status}"
  doAssert status == zsSat

  let m = o.model()
  for i in 0 ..< NumTasks:
    echo &"  t_{i} (value {Values[i]}) = {m.evalInt(tasks[i])}"

  let bound = m.evalInt(valueObj.upper)
  echo &"  total value bound: {bound}"
  doAssert bound == Values.foldl(a + b, 0)

when isMainModule:
  main()
