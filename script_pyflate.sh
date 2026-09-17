#!/bin/bash
set -e

# Define the target file path
TARGET="pyperformance/pyperformance/data-files/benchmarks/bm_pyflate/run_benchmark.py"

echo "--- 1. Environment Setup ---"
if [ ! -d "$HOME/FlameGraph" ]; then
    echo "Cloning FlameGraph..."
    git clone https://github.com/brendangregg/FlameGraph.git ~/FlameGraph
fi

echo "--- 2. Baseline Profiling ---"
# Create a safe backup of the original file
cp $TARGET ${TARGET}.backup

perf record -F 999 -e cpu-clock -g -o perf.data.pyflate_base -- python3-dbg $TARGET
perf report -i perf.data.pyflate_base --stdio > perf_report_pyflate_baseline.txt

perf script -i perf.data.pyflate_base > pyflate_base.perf
~/FlameGraph/stackcollapse-perf.pl pyflate_base.perf > pyflate_base.folded
~/FlameGraph/flamegraph.pl pyflate_base.folded > pyflate_base.svg

echo "--- 3. Applying Optimization ---"
# Inject your submitted optimized file
cp pyflate_optimized.py $TARGET

echo "--- 4. Optimized Profiling ---"
perf record -F 999 -e cpu-clock -g -o perf.data.pyflate_opt -- python3-dbg $TARGET
perf report -i perf.data.pyflate_opt --stdio > perf_report_pyflate_opt.txt

perf script -i perf.data.pyflate_opt > pyflate_opt.perf
~/FlameGraph/stackcollapse-perf.pl pyflate_opt.perf > pyflate_opt.folded
~/FlameGraph/flamegraph.pl pyflate_opt.folded > pyflate_opt.svg

echo "--- 5. Restoring Original File ---"
# Put the original file back so the environment is clean
mv ${TARGET}.backup $TARGET

echo "--- Pyflate Pipeline Complete ---"