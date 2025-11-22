# Roofline-Guided FP32 GEMM (Ubuntu 24.04 · 4 vCPUs)

This artifact builds a **reproducible Roofline workflow** for FP32 GEMM:

1) **Calibrate** sustained **memory bandwidth** (STREAM Triad) and **compute throughput** (OpenBLAS SGEMM).
2) **Run** two GEMM kernels (naive baseline and cache-blocked).
3) **Collect** FLOPs, bytes, OI, GFLOP/s to CSV.
4) **Plot** a Roofline figure using your measured ceilings.
5) **Validate** with unit tests and Valgrind memcheck.

---

## What you get

- **Kernels:** `gemm_baseline` (i–j–k), `gemm_blocked` (tiled MB×NB×KB)
- **Calibration tools:** STREAM Triad (C, OpenMP) and an SGEMM peak timer
- **Data & plots:** CSV logs and a Roofline chart (OI vs GFLOP/s, log–log)
- **Tests & hygiene:** unit tests, Valgrind memcheck, stable OMP settings

---

## System Requirements

- Ubuntu **24.04** (tested on a 4-vCPU, 8 GB RAM VM)
- GCC / OpenMP / OpenBLAS
- Python 3 with Matplotlib + Pandas
- `jq` (parse JSON), `awk` (parsing logs)
- Valgrind 

Install prerequisites:

```bash
sudo apt update
sudo apt install -y build-essential libopenblas-dev valgrind jq \
                    python3 python3-matplotlib python3-pandas
```

Set up Environment settings
```bash
export OMP_NUM_THREADS=4
export OMP_PROC_BIND=close
export OMP_PLACES=cores
```

Clean build folder
```bash
make clean
```

Clean result folder
```bash
make distclean
```

Memory roof B (GB/s) with STREAM Triad, STREAM_ARRAY_SIZE=50,000,000 by default, NTIMES=20 iterations
```bash
make calibrate-mem
```

Compute roof F (GFLOP/s) with an SGEMM peak timer
```bash
make sgemm_peak
make calibrate-comp
```

Check the combined file
```bash
cat results/calibration.json
```

Build kernels
```bash
make baseline
make blocked MB=96 NB=96 KB=256   # you can tune block size
```

Run and collect the results (***This will take a while***)
```bash
./scripts/collect.sh baseline 1024 7
./scripts/collect.sh blocked  1024 7 # n, Trial
./scripts/collect.sh baseline 2048 7
./scripts/collect.sh blocked  2048 7
```

Plot the roofline graph (There's unit issue in the paper, should've divide by 1000 in the paper)
```bash
make roofline # -> results/roofline.png
```

Unit tests
```bash
make test
```

Large tests
```bash
make perf-large N=2048 TRIALS=5 THREADS=4 # -> results/large_runs.csv
```

Valgrind tests
```bash
make memcheck-test       # unit tests under valgrind
make memcheck-baseline   # n=128, baseline kernel
make memcheck-blocked    # n=128, blocked kernel
make memcheck-sgemm      # sgemm_peak sanity
```