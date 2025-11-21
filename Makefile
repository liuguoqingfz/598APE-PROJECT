# ==== Config (override at CLI: make TRIALS=7 N=2048 MB=128 NB=128 KB=256) ====
CC      ?= gcc
CSTD    ?= -std=c11
CFLAGS  ?= -O3 -march=native -Wall -Wextra $(CSTD) -fopenmp
LDFLAGS ?= -fopenmp -lpthread -lm
BLAS    ?= -lopenblas

THREADS ?= 4
N       ?= 2048
TRIALS  ?= 5
MB      ?= 96
NB      ?= 96
KB      ?= 256

STREAM_ARRAY_SIZE ?= 50000000
NTIMES            ?= 20

SRC     := src
TEST    := tests
BUILD   := build
RESULTS := results

# ==== Phony targets ====
.PHONY: all dirs test perf-large roofline calibrate-mem calibrate-comp collect clean help

all: baseline blocked

dirs:
	@mkdir -p $(BUILD) $(RESULTS)

# ==== Objects (no main) for linking into tests ====
$(BUILD)/gemm_baseline.o: $(SRC)/gemm_baseline.c $(SRC)/gemm.h | dirs
	$(CC) $(CFLAGS) -DGEMM_NO_MAIN -c $< -o $@

$(BUILD)/gemm_blocked.o: $(SRC)/gemm_blocked.c $(SRC)/gemm.h | dirs
	$(CC) $(CFLAGS) -DGEMM_NO_MAIN -DMB=$(MB) -DNB=$(NB) -DKB=$(KB) -c $< -o $@

# ==== Binaries for quick manual runs ====
baseline: $(SRC)/gemm_baseline.c | dirs
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS)

blocked: $(SRC)/gemm_blocked.c | dirs
	$(CC) $(CFLAGS) -DMB=$(MB) -DNB=$(NB) -DKB=$(KB) $< -o $@ $(LDFLAGS)

sgemm_peak: $(SRC)/sgemm_peak.c | dirs
	$(CC) $(CFLAGS) $< -o $@ $(BLAS) $(LDFLAGS)

# ==== Unit tests ====
test: $(TEST)/test_gemm_correctness.c $(BUILD)/gemm_baseline.o $(BUILD)/gemm_blocked.o | dirs
	$(CC) $(CFLAGS) $^ -o $(TEST)/test_gemm_correctness $(BLAS) $(LDFLAGS)
	OMP_NUM_THREADS=$(THREADS) OMP_PROC_BIND=close OMP_PLACES=cores \
		$(TEST)/test_gemm_correctness

# ==== Large performance test (produces results/large_runs.csv) ====
perf-large: $(TEST)/test_gemm_large.c $(BUILD)/gemm_baseline.o $(BUILD)/gemm_blocked.o | dirs
	$(CC) $(CFLAGS) $^ -o $(TEST)/test_gemm_large $(LDFLAGS)
	@echo "variant,n,threads,flops,time_s,gflops,date" > $(RESULTS)/large_runs.csv
	OMP_NUM_THREADS=$(THREADS) OMP_PROC_BIND=close OMP_PLACES=cores \
		$(TEST)/test_gemm_large) baseline $(N) $(TRIALS) | tee -a $(RESULTS)/large_runs.csv
	OMP_NUM_THREADS=$(THREADS) OMP_PROC_BIND=close OMP_PLACES=cores \
		$(TEST)/test_gemm_large) blocked  $(N) $(TRIALS) | tee -a $(RESULTS)/large_runs.csv
	@echo "Wrote $(RESULTS)/large_runs.csv"

# ==== Calibration helpers (optional, if you use the scripted flow) ====
# Build and run STREAM C-only; parse Triad (MB/s) -> GB/s and write calibration.json (B_mem only)
calibrate-mem: STREAM/stream.c | dirs
	$(CC) -O3 -march=native -fopenmp \
		-DSTREAM_ARRAY_SIZE=$(STREAM_ARRAY_SIZE) -DNTIMES=$(NTIMES) \
		STREAM/stream.c -o stream_c.exe
	OMP_NUM_THREADS=$(THREADS) ./stream_c.exe | tee $(RESULTS)/stream.out
	@B_MEM=$$(awk '/^Triad:/ {print $$2}' $(RESULTS)/stream.out | sort -nr | head -1 | awk '{printf "%.3f", $$1/1000.0}'); \
	echo "{ \"B_mem_GBs\": $$B_MEM, \"F_peak_GFLOPs\": null }" > $(RESULTS)/calibration.json; \
	echo "Wrote $(RESULTS)/calibration.json with B_mem_GBs=$$B_MEM"

# Run SGEMM peak, parse GFLOP/s number, and merge into calibration.json (requires jq)
calibrate-comp: sgemm_peak | dirs
	OMP_NUM_THREADS=$(THREADS) ./sgemm_peak | tee $(RESULTS)/sgemm_peak.out
	@F_PEAK=$$(grep -oE 'GFLOP/s=([0-9]+(\.[0-9]+)?)' $(RESULTS)/sgemm_peak.out | sed 's/.*=//'); \
	B_MEM=$$(jq -r '.B_mem_GBs' $(RESULTS)/calibration.json); \
	tmp=$$(mktemp); \
	jq -n --argjson b "$$B_MEM" --argjson f "$$F_PEAK" \
	   '{B_mem_GBs: $$b, F_peak_GFLOPs: $$f}' > $$tmp && mv $$tmp $(RESULTS)/calibration.json; \
	echo "Updated $(RESULTS)/calibration.json with F_peak_GFLOPs=$$F_PEAK"

# ==== Data collection helper (uses scripts/collect.sh from earlier steps) ====
collect: baseline blocked | dirs
	./scripts/collect.sh baseline $(N) $(TRIALS)
	./scripts/collect.sh blocked  $(N) $(TRIALS)

# ==== Plot (requires results/calibration.json and results/results.csv) ====
roofline: dash/roofline_plot.py | dirs
	python3 dash/roofline_plot.py

# ==== Cleanup ====
clean:
	rm -rf $(BUILD) baseline blocked sgemm_peak stream_c.exe \
	       $(TEST)/test_gemm_correctness) $(TEST)/test_gemm_large) \
	       $(RESULTS)/large_runs.csv

help:
	@echo "Targets:"
	@echo "  all               - build baseline and blocked"
	@echo "  test              - build & run unit tests"
	@echo "  perf-large        - build & run large perf test -> results/large_runs.csv"
	@echo "  calibrate-mem     - build+run STREAM (C) and write B_mem to calibration.json"
	@echo "  calibrate-comp    - run sgemm_peak and update F_peak in calibration.json"
	@echo "  collect           - run scripts/collect.sh for baseline/blocked (uses N,TRIALS)"
	@echo "  roofline          - plot roofline (needs calibration.json and results.csv)"
	@echo "Vars (overridable): THREADS N TRIALS MB NB KB STREAM_ARRAY_SIZE NTIMES"
