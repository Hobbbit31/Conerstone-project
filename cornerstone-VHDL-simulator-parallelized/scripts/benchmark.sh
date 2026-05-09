#!/bin/bash
# Benchmark script for VHDL Event-Driven Simulator
#
# For each .vhd file in test_vhdl/, runs the simulator with OMP_NUM_THREADS
# varying from 1 to 8. Records avg/min/max simulation time for each run.
# Warmup pass runs first to exclude OpenMP thread pool init from timing.
#
# Usage:
#   cd <project root>
#   bash scripts/benchmark.sh
#
# Output: benchmark_results.txt

SIM=./simulator
VHDL_DIR=test_vhdl
OUTPUT_FILE=benchmark_results.txt
VCD_DIR=output
mkdir -p "$VCD_DIR"
MAX_THREADS=8
RUNS=3
# keep OpenMP threads spinning between runs so spawn cost is excluded from timing
export OMP_WAIT_POLICY=active
export OMP_NUM_THREADS=$(nproc)


# ── helpers ───────────────────────────────────────────────────────────────────

bc_calc() { echo "scale=6; $1" | bc -l; }

fmt() { printf "%.6f" "$1"; }


# ── sanity checks ─────────────────────────────────────────────────────────────

if [ ! -f "$SIM" ]; then
    echo "[ERROR] Simulator binary not found. Run 'make' first."
    exit 1
fi

echo "Thread range : 1 to $MAX_THREADS"
echo "Runs per config : $RUNS"
echo ""

# ── collect .vhd files ────────────────────────────────────────────────────────


VHDL_FILES=()
for f in "$VHDL_DIR"/*.vhd; do
    base=$(basename "$f")
    if [[ "$base" == "bad_"* ]]; then
        echo "Skipping $base (error test)"
        continue
    fi
    VHDL_FILES+=("$f")
done

if [ ${#VHDL_FILES[@]} -eq 0 ]; then
    echo "[ERROR] No .vhd files found in $VHDL_DIR/"
    exit 1
fi

echo "Circuits: ${#VHDL_FILES[@]}"
for f in "${VHDL_FILES[@]}"; do echo "  - $(basename $f)"; done
echo ""

# ── warmup ────────────────────────────────────────────────────────────────────

echo "Warming up OpenMP thread pool..."
OMP_NUM_THREADS=$MAX_THREADS $SIM "${VHDL_FILES[0]}" "$VCD_DIR/warmup.vcd" > /dev/null 2>&1
echo "Warmup done."
echo ""

# ── write header ──────────────────────────────────────────────────────────────

{
echo "====================================================================="
echo "  VHDL Simulator — Benchmark Results"
echo "  Date    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Host    : $(hostname)"
echo "  CPU     : $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
echo "  Cores   : $(nproc) logical (benchmarking 1–$MAX_THREADS threads)"
echo "  Avg over: $RUNS run(s) per config"
echo "====================================================================="
echo ""
} > "$OUTPUT_FILE"

# ── run_config <vhd_file> <threads|"seq"> → prints avg ms, also sets AVG MIN MAX

run_config() {
    local vhd="$1"
    local threads="$2"
    local total=0
    local min=""
    local max=""
    local ms

    for ((r=1; r<=RUNS; r++)); do
        local vcd_out="$VCD_DIR/output_$(basename ${vhd%.vhd})_${threads}.vcd"
        if [ "$threads" = "seq" ]; then
            ms=$(OMP_NUM_THREADS=1 $SIM "$vhd" "$vcd_out" -seq 2>/dev/null \
                 | grep -i "elapsed" | head -1 | grep -oE '[0-9.]+' | head -1 | awk '{print $1}')
        else
            ms=$(OMP_NUM_THREADS=$threads $SIM "$vhd" "$vcd_out" 2>/dev/null \
                 | grep -i "elapsed" | head -1 | grep -oE '[0-9.]+' | head -1 | awk '{print $1}')
        fi

        # skip empty/failed reads
        [ -z "$ms" ] && ms=0

        total=$(bc_calc "$total + $ms")

        if [ -z "$min" ]; then
            min=$ms
            max=$ms
        else
            if [ "$(echo "$ms < $min" | bc -l)" = "1" ]; then min=$ms; fi
            if [ "$(echo "$ms > $max" | bc -l)" = "1" ]; then max=$ms; fi
        fi
    done

    AVG=$(bc_calc "$total / $RUNS")
    MIN=$min
    MAX=$max
}

# ── main benchmark loop ───────────────────────────────────────────────────────

# collect all data into arrays
declare -A TIME_DATA   # TIME_DATA[circuit:threads] = avg_ms
declare -a CIRCUITS    # ordered list of circuit names

for vhd_file in "${VHDL_FILES[@]}"; do
    circuit=$(basename "$vhd_file" .vhd)
    CIRCUITS+=("$circuit")

    echo "Benchmarking: $circuit"
    {
        echo "---------------------------------------------------------------------"
        echo "Circuit : $circuit"
        echo "File    : $vhd_file"
        echo "---------------------------------------------------------------------"
        printf "%-14s  %-16s  %-16s  %s\n" "Mode" "Avg (ms)" "Min (ms)" "Max (ms)"
        printf "%-14s  %-16s  %-16s  %s\n" "----" "--------" "--------" "--------"
    } >> "$OUTPUT_FILE"

    # sequential baseline
    run_config "$vhd_file" "seq"
    SEQ_AVG=$AVG
    TIME_DATA["$circuit:seq"]=$AVG
    printf "  %-12s  avg=%sms  min=%sms  max=%sms\n" "seq" "$AVG" "$MIN" "$MAX"
    printf "  %-12s  %-16s  %-16s  %s\n" "seq (-seq)" "$AVG" "$MIN" "$MAX" >> "$OUTPUT_FILE"

    # parallel runs 1..MAX_THREADS
    for ((t=1; t<=MAX_THREADS; t++)); do
        run_config "$vhd_file" "$t"
        TIME_DATA["$circuit:$t"]=$AVG
        printf "  %-12s  avg=%sms  min=%sms  max=%sms\n" "${t} thread(s)" "$AVG" "$MIN" "$MAX"
        printf "  %-12s  %-16s  %-16s  %s\n" "${t}T" "$AVG" "$MIN" "$MAX" >> "$OUTPUT_FILE"
    done

    echo "" >> "$OUTPUT_FILE"
    echo ""
done

# ── Grid 1: Raw timing matrix ─────────────────────────────────────────────────
{
echo ""
echo "====================================================================="
echo "  Timing Matrix  — avg simulation time (ms)"
echo "  OMP_WAIT_POLICY=active  |  $RUNS run(s) averaged"
echo "====================================================================="
printf "%-38s  %-10s" "Circuit" "seq"
for ((t=1; t<=MAX_THREADS; t++)); do printf "  %-10s" "${t}T"; done
echo ""
printf "%-38s  %-10s" "$(printf '%.0s-' {1..38})" "----------"
for ((t=1; t<=MAX_THREADS; t++)); do printf "  %-10s" "----------"; done
echo ""

for circuit in "${CIRCUITS[@]}"; do
    printf "%-38s  %-10s" "$circuit" "$(printf '%.4f' ${TIME_DATA[$circuit:seq]})"
    for ((t=1; t<=MAX_THREADS; t++)); do
        printf "  %-10s" "$(printf '%.4f' ${TIME_DATA[$circuit:$t]})"
    done
    echo ""
done
echo ""

# ── Grid 2: Speedup matrix ────────────────────────────────────────────────────
echo "====================================================================="
echo "  Speedup Matrix  — seq_time / parallel_time  (>1.0 = faster than seq)"
echo "====================================================================="
printf "%-38s  %-10s" "Circuit" "seq(ms)"
for ((t=1; t<=MAX_THREADS; t++)); do printf "  %-10s" "${t}T"; done
echo ""
printf "%-38s  %-10s" "$(printf '%.0s-' {1..38})" "----------"
for ((t=1; t<=MAX_THREADS; t++)); do printf "  %-10s" "----------"; done
echo ""

for circuit in "${CIRCUITS[@]}"; do
    seq_t=${TIME_DATA[$circuit:seq]}
    printf "%-38s  %-10s" "$circuit" "$(printf '%.4f' $seq_t)"
    for ((t=1; t<=MAX_THREADS; t++)); do
        par_t=${TIME_DATA[$circuit:$t]}
        if [ "$(echo "$par_t == 0" | bc -l)" = "1" ]; then
            printf "  %-10s" "N/A"
        else
            sp=$(bc_calc "$seq_t / $par_t")
            printf "  %-10s" "$(printf '%.3f' $sp)"
        fi
    done
    echo ""
done
echo ""
echo "====================================================================="
} >> "$OUTPUT_FILE"

echo "Done. Results written to: $OUTPUT_FILE"
