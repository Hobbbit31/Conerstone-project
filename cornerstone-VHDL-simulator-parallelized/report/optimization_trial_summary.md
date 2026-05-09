# Optimization Trial Summary

Date: 2026-04-20

This file records the optimization experiments I ran on the simulator, what was measured, and which changes actually helped before the code was reverted back to the original implementation.

Current repo state:
- Source changes from the optimization pass were reverted.
- This file is only a record of the experiments and results.

## Files that were modified during the experiments

- `src/Simulator.cpp`
- `include/Process.hpp`
- `include/Signal.hpp`

Final reverted source state:
- `src/Simulator.cpp` restored to the original batch loop implementation
- `include/Process.hpp` restored to the original base class
- `include/Signal.hpp` restored to the original lock-based signal update path

## Workloads used for checking speedup

Main representative workloads:
- `generated/pyramid_and_tree.net` / `.stim`
- `test_vhdl/large_flat_and.net` / `.stim`
- `generated/large_huge_parallel_gates.net` / `.stim`
- `generated/large_pipeline_4stage.net` / `.stim`
- `generated/large_parallel_full_adders.net` / `.stim`

Measurement setup:
- `OMP_WAIT_POLICY=active`
- most timing checks used `/dev/null` for VCD output to reduce file-I/O noise
- multiple runs were averaged during the keep/revert decision

## Changes that worked

### 1. Hoist OpenMP team outside the event batch loop

What changed:
- kept one `#pragma omp parallel` region alive across the simulation loop instead of creating a new team for every `(time, delta)` batch

Why it helped:
- the original code paid OpenMP team setup cost every batch
- that overhead was significant on larger circuits with many delta batches

Observed effect:
- improved larger workloads enough to keep during the experiment pass
- tiny circuits still remained slower in parallel

### 2. Replace per-batch `std::set` dedup with `batch_id` markers and reuse scratch buffers

What changed:
- added a per-process `last_batch_id`
- replaced `std::set<Process*> already_added` with O(1) batch marking
- reused `batch`, layer buckets, and leftover vectors instead of rebuilding them every batch

Why it helped:
- removed repeated tree allocation and lookup overhead from the hottest path in `Simulator::run()`

Observed effect:
- clear absolute win on both sequential and parallel runtime
- example measured during the trials:
  - `pyramid_and_tree`: about `68.7 ms seq / 52.2 ms 8T` before this step in one clean comparison
  - after this step: about `52.9 ms seq / 40.8 ms 8T`

### 3. Small-layer threshold

What changed:
- layers smaller than a threshold were run under `omp single` instead of `omp for`

Threshold used:
- `PARALLEL_THRESHOLD = 128`

Why it helped:
- avoided OpenMP dispatch and barrier cost for very small layers

Observed effect:
- this was one of the cleanest wins on the main large workload
- example measured during the trials:
  - `pyramid_and_tree`: about `56.0 ms seq / 36.9 ms 8T`
  - `large_flat_and`: about `14.3 ms seq / 12.0 ms 8T`

### 4. Parallel commit scan with thread-local changed-signal lists

What changed:
- parallelized the `all_signals[i]->commit()` scan
- used per-thread changed-signal lists
- merged and rescheduled on one thread afterward

Why it helped:
- moved the full signal scan out of a purely serial phase

Observed effect:
- helped the main large/deep workload
- example measured during the trials:
  - `pyramid_and_tree`: about `50.8 ms seq / 35.3 ms 8T`
- this was not a universal win for tiny circuits, but it did improve the main target workload enough to count as effective in the experiment pass

## Changes that did not reliably help

### 1. Remove `Signal` write locking

What changed:
- removed the `omp_lock_t` from `Signal`
- made `scheduleUpdate()` lock-free

Result:
- not a reliable win
- improved some sequential numbers
- did not improve the main target case consistently enough to keep
- was reverted during the experiment pass

### 2. Per-process cached layer index

What changed:
- stored layer index directly inside `Process`
- avoided `which_layer.find(process)` during bucketing

Result:
- no meaningful improvement in the representative measurements
- reverted

## Final best measured optimized state before revert

This was the best combined state I reached before reverting the source:
- hoisted OpenMP team
- batch-id dedup
- persistent scratch buffers
- small-layer threshold
- parallel commit scan

Final benchmark snapshot from that optimized state:
- `pyramid_and_tree`: `seq 53.502 ms`, `1T 40.779 ms`, `4T 36.286 ms`, `8T 35.148 ms`
- `large_flat_and`: `seq 14.121 ms`, `1T 11.380 ms`, `4T 11.613 ms`, `8T 12.690 ms`
- `large_huge_parallel_gates`: `seq 0.308 ms`, `1T 0.246 ms`, `4T 0.424 ms`, `8T 0.424 ms`
- `large_pipeline_4stage`: `seq 0.109 ms`, `1T 0.321 ms`, `4T 0.476 ms`, `8T 0.586 ms`
- `large_parallel_full_adders`: `seq 0.144 ms`, `1T 0.142 ms`, `4T 0.303 ms`, `8T 0.311 ms`

Interpretation:
- large workloads with enough useful work per batch improved
- tiny or narrow/deep circuits remained dominated by OpenMP overhead and still preferred `-seq`

## Correctness status during the optimized pass

The optimized version was checked with:
- `bash scripts/test.sh`

Result:
- `36 / 36 passed`

## Recommendation if these optimizations are re-applied later

Priority order:
1. hoisted OpenMP team
2. batch-id dedup plus persistent scratch buffers
3. small-layer threshold
4. parallel commit scan

Avoid re-applying without stronger evidence:
- lock-free `Signal::scheduleUpdate()`
- per-process cached layer index
