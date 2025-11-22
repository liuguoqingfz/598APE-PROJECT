CC       := gcc
CSTD     := -std=c11
CFLAGS   ?= -O3 -march=native -fopenmp -Wall -Wextra $(CSTD)
LDFLAGS  ?= -fopenmp
LIBS     ?= -lopenblas
INCLUDES := -Isrc
CFLAGS += -D_POSIX_C_SOURCE=200112L

SRC_DIR     := src
TEST_DIR    := tests
SCRIPT_DIR  := scripts
DASH_DIR    := dash
BUILD_DIR   := build
BIN_DIR     := $(BUILD_DIR)/bin
RESULTS_DIR := results

THREADS ?= 4
N       ?= 1024
TRIALS  ?= 5
MB      ?= 96
NB      ?= 96
KB      ?= 256

BASELINE_SRC := $(SRC_DIR)/gemm_baseline.c
BLOCKED_SRC  := $(SRC_DIR)/gemm_blocked.c
PEAK_SRC     := $(SRC_DIR)/sgemm_peak.c
GEMM_HDR     := $(SRC_DIR)/gemm.h

BASELINE_BIN := $(BIN_DIR)/gemm_baseline
BLOCKED_BIN  := $(BIN_DIR)/gemm_blocked
PEAK_BIN     := $(BIN_DIR)/sgemm_peak

STREAM_DIR   := STREAM
STREAM_EXE   := $(STREAM_DIR)/stream_c.exe
STREAM_EXTRA := -O3 -march=native -fopenmp -DSTREAM_ARRAY_SIZE=50000000 -DNTIMES=20

CALJSON      := $(RESULTS_DIR)/calibration.json
STREAM_OUT   := $(RESULTS_DIR)/stream.out
PEAK_OUT     := $(RESULTS_DIR)/sgemm_peak.out
RESULTS_CSV  := $(RESULTS_DIR)/results.csv
LARGE_CSV    := $(RESULTS_DIR)/large_runs.csv
ROOFLINE_PNG := $(RESULTS_DIR)/roofline.png

.PHONY: all dirs clean distclean \
        test baseline blocked sgemm_peak \
        calibrate-mem calibrate-comp \
        collect perf-large roofline \
        memcheck-test memcheck-baseline memcheck-blocked memcheck-sgemm \
        print-vars stream-build

all: dirs baseline blocked sgemm_peak

dirs:
	@mkdir -p $(BIN_DIR) $(RESULTS_DIR)

$(BASELINE_BIN): $(BASELINE_SRC) $(GEMM_HDR) | dirs
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ $(BASELINE_SRC) $(LDFLAGS) $(LIBS)

$(BLOCKED_BIN): $(BLOCKED_SRC) $(GEMM_HDR) | dirs
	$(CC) $(CFLAGS) $(INCLUDES) -DMB=$(MB) -DNB=$(NB) -DKB=$(KB) -o $@ $(BLOCKED_SRC) $(LDFLAGS) $(LIBS)

$(PEAK_BIN): $(PEAK_SRC) | dirs
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ $(PEAK_SRC) $(LDFLAGS) $(LIBS)

baseline: $(BASELINE_BIN)
blocked:  $(BLOCKED_BIN)
sgemm_peak: $(PEAK_BIN)

stream-build: | dirs
	@echo "[stream] Building upstream STREAM C target with your flags…"
	@$(MAKE) -C $(STREAM_DIR) CC=$(CC) EXTRA_FLAGS="$(STREAM_EXTRA)"

calibrate-mem: stream-build
	@echo "[calibrate-mem] Running STREAM Triad with pinned threads…"
	@OMP_NUM_THREADS=$$(nproc) OMP_PROC_BIND=close OMP_PLACES=cores \
		$(STREAM_EXE) | tee $(STREAM_OUT)
	@echo "[calibrate-mem] Parsing Triad MB/s and updating $(CALJSON)"
	@mkdir -p $(RESULTS_DIR) && [ -f $(CALJSON) ] || echo '{}' > $(CALJSON)
	@MBPS=$$(awk '/^Triad:/ {print $$2; exit}' $(STREAM_OUT)); \
	GBPS=$$(awk -v m=$$MBPS 'BEGIN{printf "%.3f", m/1024.0}'); \
	jq --argjson b $$GBPS '.B_mem_GBs = $$b' $(CALJSON) > $(CALJSON).tmp && mv $(CALJSON).tmp $(CALJSON)
	@echo "[calibrate-mem] B_mem_GBs=$$(jq -r '.B_mem_GBs' $(CALJSON))"

calibrate-comp: $(PEAK_BIN)
	@echo "[calibrate-comp] Running SGEMM peak…"
	@OMP_NUM_THREADS=$(THREADS) OMP_PROC_BIND=close OMP_PLACES=cores \
		$(PEAK_BIN) | tee $(PEAK_OUT)
	@echo "[calibrate-comp] Parsing GFLOP/s and updating $(CALJSON)"
	@mkdir -p $(RESULTS_DIR) && [ -f $(CALJSON) ] || echo '{}' > $(CALJSON)
	@GF=$$(awk 'match($$0,/GFLOP\/s=([0-9.]+)/,a){print a[1]}' $(PEAK_OUT) | tail -n1); \
	jq --argjson f $$GF '.F_peak_GFLOPs = $$f' $(CALJSON) > $(CALJSON).tmp && mv $(CALJSON).tmp $(CALJSON)
	@echo "[calibrate-comp] F_peak_GFLOPs=$$(jq -r '.F_peak_GFLOPs' $(CALJSON))"

test: $(BASELINE_BIN) $(BLOCKED_BIN)
	@echo "[test] Building and running unit tests..."
	$(CC) $(CFLAGS) -DGEMM_NO_MAIN $(INCLUDES) -o $(BIN_DIR)/test_gemm_correctness \
		$(TEST_DIR)/test_gemm_correctness.c src/gemm_baseline.c src/gemm_blocked.c \
		$(LDFLAGS) $(LIBS)
	OMP_NUM_THREADS=$(THREADS) OMP_PROC_BIND=close OMP_PLACES=cores \
		$(BIN_DIR)/test_gemm_correctness

perf-large: $(BASELINE_BIN) $(BLOCKED_BIN)
	@echo "[perf-large] N=$(N) TRIALS=$(TRIALS) THREADS=$(THREADS)"
	@mkdir -p $(RESULTS_DIR)
	@bash $(SCRIPT_DIR)/collect.sh baseline $(N) $(TRIALS) $(THREADS) >> $(LARGE_CSV)
	@bash $(SCRIPT_DIR)/collect.sh blocked  $(N) $(TRIALS) $(THREADS) >> $(LARGE_CSV)
	@echo "[perf-large] Wrote $(LARGE_CSV)"

collect: $(BASELINE_BIN) $(BLOCKED_BIN)
	@echo "[collect] Appending sweeps to $(RESULTS_CSV)"
	@bash $(SCRIPT_DIR)/collect.sh baseline $(N) $(TRIALS) $(THREADS) >> $(RESULTS_CSV)
	@bash $(SCRIPT_DIR)/collect.sh blocked  $(N) $(TRIALS) $(THREADS) >> $(RESULTS_CSV)
	@echo "[collect] Wrote $(RESULTS_CSV)"

roofline: $(RESULTS_CSV) $(CALJSON)
	@echo "[roofline] Generating $(ROOFLINE_PNG)"
	@python3 $(DASH_DIR)/roofline_plot.py --csv $(RESULTS_CSV) --cal $(CALJSON) --out $(ROOFLINE_PNG)
	@echo "[roofline] Done: $(ROOFLINE_PNG)"

VALGRIND := valgrind --leak-check=full --track-origins=yes --error-exitcode=1

memcheck-test: $(BASELINE_BIN) $(BLOCKED_BIN)
	$(CC) -O2 -g -DGEMM_NO_MAIN $(INCLUDES) -o $(BIN_DIR)/test_gemm_correctness_dbg \
		$(TEST_DIR)/test_gemm_correctness.c $(BASELINE_SRC) $(BLOCKED_SRC) $(LDFLAGS) $(LIBS)
	OMP_NUM_THREADS=1 $(VALGRIND) $(BIN_DIR)/test_gemm_correctness_dbg

memcheck-baseline: $(BASELINE_BIN)
	OMP_NUM_THREADS=1 $(VALGRIND) $(BASELINE_BIN) 128

memcheck-blocked: $(BLOCKED_BIN)
	OMP_NUM_THREADS=1 $(VALGRIND) $(BLOCKED_BIN) 128

memcheck-sgemm: $(PEAK_BIN)
	OPENBLAS_NUM_THREADS=1 GOTO_NUM_THREADS=1 BLIS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
	OMP_NUM_THREADS=1 $(VALGRIND) $(PEAK_BIN) 256

clean:
	@rm -rf $(BUILD_DIR)

distclean: clean
	@rm -f $(STREAM_OUT) $(PEAK_OUT) $(ROOFLINE_PNG)
	@rm -f $(RESULTS_CSV) $(LARGE_CSV)
	@rm -f $(CALJSON)

print-vars:
	@echo "CFLAGS=$(CFLAGS)"
	@echo "LDFLAGS=$(LDFLAGS)"
	@echo "LIBS=$(LIBS)"
	@echo "THREADS=$(THREADS) N=$(N) TRIALS=$(TRIALS) MB=$(MB) NB=$(NB) KB=$(KB)"
