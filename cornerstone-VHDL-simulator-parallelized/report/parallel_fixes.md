# Parallel Simulator — Fix Experiments (2026-04-19)

All fixes below were implemented iteratively on top of the 2026-04-19 checkpoint
(`Hobbbit31` branch, commit `9eb2282`). Each fix was benchmarked against
`scripts/benchmark.sh` (RUNS=3, 14 circuits, seq + 1–8 threads,
AMD Ryzen 7 7735HS, 16 logical cores, `OMP_WAIT_POLICY=active`).

A fix was **kept** only if it improved either the parallel speedup ratio or
absolute wall-clock time on the larger circuits.

---

## Fix status

| # | Fix | Status | Files touched |
|---|---|---|---|
| 1 | Hoist `#pragma omp parallel` outside event loop | ✅ KEEP | `src/Simulator.cpp` |
| 2 | Remove `omp_lock_t` on signal writes | ✅ KEEP | `include/Signal.hpp`, `src/Signal.cpp` |
| 3 | Dirty-signals list (thread-local) for commit | ❌ REVERT | — |
| 4 | `batch_id` dedup replaces `std::set<Process*>` + persistent scratch | ✅ KEEP | `include/Process.hpp`, `src/Simulator.cpp` |
| 5 | `PARALLEL_THRESHOLD=128` — small layers run under `omp single` | ✅ KEEP | `src/Simulator.cpp` |

---

## Fix #1 — Hoist parallel region

`#pragma omp parallel` was firing every batch inside `while (!event_queue.empty())`
(Simulator.cpp:111). Each batch re-created a thread team; per-gate work is ~3 ns,
team startup is tens of µs — overhead dominated.

**Change:** one `#pragma omp parallel` outside the `while`. Batch prep (pop events,
bucket by layer, clear scratch) runs under `#pragma omp single`. Layer execution
stays under `#pragma omp for`. Leftover processes and commit phase wrapped in
another `omp single`.

**Result:** clear win on large circuits.

| Circuit | baseline | Fix#1 |
|---|---|---|
| large_wide_and_tree | 0.97× | **1.77×** |
| large_huge_parallel_gates | 0.99× | **1.29×** |
| pyramid_and_tree | 1.07× | **1.23×** |

## Fix #2 — Remove per-signal lock

Each `Signal` held an `omp_lock_t` used in `scheduleUpdate()`. But the DAG
(`DependencyGraph::buildLayers` at `include/DependencyGraph.hpp:29`) maps every
signal to exactly one writer process. With single-writer-per-signal, the lock
is unnecessary and just adds lock-acquire/release cost on the hot path.

**Change:** removed `omp_lock_t`, `omp_init_lock`, `omp_destroy_lock`, and the
set/unset wrappers in `scheduleUpdate`. Dropped `<omp.h>` from `Signal.hpp`.

**Result:** improvement on 6 of 7 larger circuits (compared at RUNS=3).

| Circuit | Fix#1 | Fix#2 |
|---|---|---|
| large_wide_and_tree | 0.96× | **1.38×** |
| large_parallel_full_adders | 0.71× | **0.99×** |
| large_huge_parallel_gates | 0.97× | **1.16×** |

## Fix #3 — Dirty-signals list (REVERTED)

Intended to avoid scanning all 80k signals at commit. Added `vector<Signal*>
dirty_signals` populated by `scheduleUpdate()` on first write per batch,
iterated at commit instead of `all_signals`.

**Failure mode:** single shared `dirty_signals.push_back()` raced across
threads → `double free or corruption` crash. Fixed with per-thread lists
(`dirty_signals_tls[tid]`), merged at commit under `omp single`.

**Result (working version):** regressed most circuits.

| Circuit | Fix#2 | Fix#3 |
|---|---|---|
| large_wide_and_tree | 1.38× | 0.74× ✗ |
| large_huge_parallel_gates | 1.16× | 0.80× ✗ |

**Why it failed:** commit phase is already inside `omp single` (serial), so
the O(all_signals) scan cost is low. Meanwhile the TLS push added an
`omp_get_thread_num()` call + vector push on the *hot* scheduleUpdate path.
For these test circuits most signals change per batch anyway (pyramid tree
propagates broadly), so the "skip unchanged" savings were small.

Reverted. A dirty-list approach could work if (a) scheduleUpdate is batched
per-thread with no TLS lookup, and (b) circuits have sparse fanout — neither
holds here.

## Fix #4 — batch_id dedup + persistent scratch

Two changes bundled:
1. Replaced `std::set<Process*> already_added` (rebuilt every batch,
   RB-tree alloc/free) with `int Process::last_batch` sentinel + monotonic
   `batch_id` counter. Dedup is now O(1).
2. Moved `my_layer_buckets`, `leftover_processes` into persistent scratch
   on the stack of `run()` (was heap-allocated per batch).

**Result:** big absolute-time win for both seq and parallel.

| Circuit | seq before | seq after | parallel before | parallel after |
|---|---|---|---|---|
| pyramid_and_tree | 56.6 ms | **40.4 ms** (-28%) | 51.6 ms | 38.6 ms (-25%) |
| large_wide_and_tree | 0.40 ms | **0.18 ms** (-55%) | 0.29 ms | 0.20 ms (-31%) |

The speedup *ratio* did not improve (seq sped up proportionally), but wall-clock
dropped dramatically — the `std::set` was a universal tax, not just a parallel
one.

## Fix #5 — PARALLEL_THRESHOLD

Layers with <128 processes run under `omp single` instead of `omp for`.
Skips the dispatch barrier for tiny layers.

```cpp
static const size_t PARALLEL_THRESHOLD = 128;
...
if (L.size() < PARALLEL_THRESHOLD) {
    #pragma omp single
    { for (auto* p : L) p->execute(*this); }
} else {
    #pragma omp for schedule(static)
    for (size_t i = 0; i < L.size(); i++) L[i]->execute(*this);
}
```

**Result:** small additional gain on larger circuits.

| Circuit | Fix#4 | Fix#5 |
|---|---|---|
| large_huge_parallel_gates | 1.02× | **1.09×** |
| large_wide_mixed_gates | 0.85× | **0.92×** |
| pyramid_and_tree | 1.08× | **1.09×** |

---

## Combined final result (baseline vs all kept fixes)

**Absolute seq runtime (ms):**

| Circuit | baseline | final | Δ |
|---|---|---|---|
| pyramid_and_tree | 48.7 | 44.0 | -10% |
| large_wide_and_tree | 0.30 | 0.18 | -40% |
| large_alu_8bit | 0.14 | 0.09 | -36% |
| comparator_4bit | 0.054 | 0.036 | -33% |

**Best parallel speedup ratio (max across 1T–8T):**

| Circuit | baseline | final |
|---|---|---|
| large_huge_parallel_gates | 0.991 | **1.092** |
| pyramid_and_tree | 1.068 | **1.089** |
| large_parallel_full_adders | 0.888 | 0.892 |
| large_wide_and_tree | 0.975 | 0.942 (seq got much faster) |

---

## Remaining bottlenecks

Parallel speedup is still capped around 1.1×. Root cause on these test
circuits: per-gate work (~3 ns) is smaller than barrier-per-layer overhead.
Further gains would need one or more of:

- **OpenMP tasks instead of layer barriers** — let threads proceed into later
  layers as soon as their dependencies clear, rather than global barrier per
  layer.
- **Wider, shallower DAGs** — current test set (pyramid, AND-tree) has long
  critical paths with few gates per layer in the deep half.
- **Amortize work per gate** — batch multiple gates into a single callable
  to spread barrier cost.

## Correctness issues still open (not exercised by tests)

- **ClockProcess race** — `processes/ClockProcess.hpp:29` calls
  `sim.scheduleEvent()` from inside `execute()`. Clock lands in Layer 0
  (self-edge skipped at `DependencyGraph.hpp:50`) and runs under `omp for`.
  Safe today with one clock; would race with ≥2 clocks.
- **Fallback layer race** — feedback cycles (SR latches) land in one
  `omp for` layer and race on shared state.
- **Dead `leftover_processes` branch** — in theory stim/clock go there, but
  both have output signals → both end up in `which_layer`.

These don't trigger on any circuit in `test_vhdl/` because:
- only one clock per circuit
- no SR latches in the benchmark set
