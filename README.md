# Hardware/Software Co-Design Project: Raytrace & Pyflate

**Authors:** Musa Eisa, Saadi Saadi

This repository contains the software optimizations, profiling data, and custom RTL hardware acceleration design for the `bm_raytrace` and `pyflate` benchmarks.

## How to Run

The profiling, execution, and performance comparisons are fully automated. To generate the runtime logs, `perf` reports, and flame graphs, execute the provided shell scripts:

```bash
# Run the Raytrace benchmark suite
chmod +x script_raytrace.sh
./script_raytrace.sh

# Run the Pyflate benchmark suite
chmod +x script_pyflate.sh
./script_pyflate.sh
