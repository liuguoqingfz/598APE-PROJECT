#!/usr/bin/env bash
set -euo pipefail
variant="$1"
n="$2"
trials="${3:-5}"
bin="./$variant"
[ -x "$bin" ] || {
	echo "Missing binary: $bin"
	exit 1
}

calc_flops() {
	python3 - <<PY
n=$1
print(int(2*n*n*n))
PY
}
# Conservative bytes for blocked GEMM (fp32, beta=0): read A+B once, write C once → 12*n^2 bytes
bytes_est() {
	python3 - <<PY
n=$1
print(int(12*n*n))
PY
}
for t in $(seq 1 $trials); do
	ts=$(date -Iseconds)
	/usr/bin/time -f "%e" -o .t "$bin" "$n" >/dev/null
	time_s=$(cat .t)
	flops=$(calc_flops $n)
	gflops=$(
		python3 - <<PY
flops=$flops; t=float("$time_s")
print(flops/t/1e9)
PY
	)
	bytes=$(bytes_est $n)
	oi=$(
		python3 - <<PY
flops=$flops; b=$bytes
print(flops/b)
PY
	)
	bw=$(
		python3 - <<PY
b=$bytes; t=float("$time_s")
print(b/t/1e9)
PY
	)
	echo "$variant,$n,${OMP_NUM_THREADS:-4},$flops,$time_s,$gflops,$bytes,$oi,$bw,$ts" |
		tee -a results/results.csv
done
