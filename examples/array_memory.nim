## Memory-model example — `Z3Array[K, V]` as a flat heap.
##
## The array theory's headline use case is reasoning about memory.
## A `Z3Array[Z3BitVec[64], Z3BitVec[8]]` models a 64-bit-addressed
## byte heap; `store` and `select` correspond to writes and reads.
##
## We prove three facts about the array theory in a single solve:
##
##   1. `select(store(a, i, v), i) == v` (read-over-write same index).
##   2. `store` doesn't affect other indices (read-over-write at j ≠ i).
##   3. `mkConstArray(0)`'s default value is observable everywhere via
##      `arrayDefault` (introduced in v1.0 audit round 2, HIGH #3).
##
## Plus a small nested-array demo: a `Z3Array[K1, Z3Array[K2, V]]` for
## a two-level memory map (e.g. process → byte address → byte).
##
## Run with:
##
## ```
## nim c -r examples/array_memory.nim
## ```

import std/strformat
import z3

proc main() =
  let ctx = newContext()
  # 64-bit-addressed byte heap.
  let heap = mkArrayVar[Z3BitVec[64], Z3BitVec[8]]("heap")
  let addr1 = mkBitVecVar[64]("addr1")
  let addr2 = mkBitVecVar[64]("addr2")
  let byte1 = mkBitVecVar[8]("byte1")

  let s = newSolver()

  # --- Fact 1: write-then-read at the same address returns the value.
  let heap1 = heap.store(addr1, byte1)
  s.withFrame:
    s.add not (heap1.select(addr1) == byte1)
    doAssert s.check() == zsUnsat
    echo "Fact 1 verified: select(store(h, a, v), a) == v"

  # --- Fact 2: write at addr1 doesn't disturb addr2 when they differ.
  s.withFrame:
    s.add addr1 != addr2
    s.add not (heap1.select(addr2) == heap.select(addr2))
    doAssert s.check() == zsUnsat
    echo "Fact 2 verified: store at addr1 preserves heap[addr2] when addr1 ≠ addr2"

  # --- Fact 3: arrayDefault on a const-array returns the constant.
  let zeroHeap = mkConstArray[Z3BitVec[64], Z3BitVec[8]](mkBitVec[8](0'u8))
  doAssert smtValid(arrayDefault(zeroHeap) == mkBitVec[8](0'u8))
  echo "Fact 3 verified: arrayDefault(mkConstArray(0)) == 0"

  # --- Nested arrays: process_id → (address → byte) two-level map.
  let mem = mkArrayVar[Z3BitVec[16], Z3Array[Z3BitVec[64], Z3BitVec[8]]]("mem")
  let pid = mkBitVecVar[16]("pid")
  let proc1Heap = mem.select(pid).store(addr1, byte1)
  # Write at addr1 in process `pid`, then verify the read.
  s.withFrame:
    s.add not (proc1Heap.select(addr1) == byte1)
    doAssert s.check() == zsUnsat
    echo "Nested verified: per-process byte address write round-trips"

  echo &"\nAll memory-model facts proved using {heap.getSortKind} arrays."

when isMainModule:
  main()
