#!/bin/bash
set -e

# Define the target file path
TARGET="pyperformance/pyperformance/data-files/benchmarks/bm_raytrace/run_benchmark.py"

echo "--- 1. Environment Setup ---"
if [ ! -d "$HOME/FlameGraph" ]; then
    echo "Cloning FlameGraph..."
    git clone https://github.com/brendangregg/FlameGraph.git ~/FlameGraph
fi

echo "--- 2. Baseline Profiling ---"
# Create a safe backup of the original file
cp $TARGET ${TARGET}.backup

perf record -F 999 -e cpu-clock -g -o perf.data.raytrace_base -- python3-dbg $TARGET
perf report -i perf.data.raytrace_base --stdio > perf_report_raytrace_baseline.txt

perf script -i perf.data.raytrace_base > raytrace_base.perf
~/FlameGraph/stackcollapse-perf.pl raytrace_base.perf > raytrace_base.folded
~/FlameGraph/flamegraph.pl raytrace_base.folded > raytrace_base.svg

echo "--- 3. Applying Optimization ---"
# Inject your submitted optimized file
cp raytrace_optimized.py $TARGET

echo "--- 4. Optimized Profiling ---"
perf record -F 999 -e cpu-clock -g -o perf.data.raytrace_opt -- python3-dbg $TARGET
perf report -i perf.data.raytrace_opt --stdio > perf_report_raytrace_opt.txt

perf script -i perf.data.raytrace_opt > raytrace_opt.perf
~/FlameGraph/stackcollapse-perf.pl raytrace_opt.perf > raytrace_opt.folded
~/FlameGraph/flamegraph.pl raytrace_opt.folded > raytrace_opt.svg

echo "--- 5. Restoring Original File ---"
# Put the original file back so the environment is clean
mv ${TARGET}.backup $TARGET

echo "--- Raytrace Pipeline Complete ---"