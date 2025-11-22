#!/usr/bin/env bash
set -euo pipefail

# --- Args -------------------------------------------------------------
variant="${1:?usage: $0 <variant> <n> [trials=5] [threads(optional)]}"
n="${2:?usage: $0 <variant> <n> [trials=5] [threads(optional)]}"
trials="${3:-5}"
threads="${4:-${OMP_NUM_THREADS:-$(command -v nproc >/dev/null 2>&1 && nproc || echo 4)}}"

# --- Locate binary (support ./<variant> or ./build/bin/<variant>) -----
bin=""
for cand in "./${variant}" "./build/bin/${variant}"; do
  if [[ -x "$cand" ]]; then bin="$cand"; break; fi
done
if [[ -z "$bin" ]]; then
  echo "Missing binary: ./${variant} (or ./build/bin/${variant})" >&2
  exit 1
fi

# --- CSV setup --------------------------------------------------------
outdir="results"
csv="${outdir}/results.csv"
mkdir -p "$outdir"

header="variant,n,threads,flops,time_s,gflops,bytes,oi,bw_GBps,date"
if [[ ! -s "$csv" ]]; then
  echo "$header" >"$csv"
else
  first_line="$(head -n1 "$csv")"
  if [[ "$first_line" != "$header" ]]; then
    tmp="$(mktemp)"
    { echo "$header"; cat "$csv"; } >"$tmp"
    mv "$tmp" "$csv"
  fi
fi

# --- Small helpers ----------------------------------------------------
calc_flops() {
  python3 - "$1" <<'PY'
import sys
n=int(sys.argv[1])
print(2*n*n*n)
PY
}

bytes_est() {
  python3 - "$1" <<'PY'
import sys
n=int(sys.argv[1])
print(12*n*n)
PY
}

# --- Main loop --------------------------------------------------------
for t in $(seq 1 "$trials"); do
  ts="$(date -Iseconds)"

  # time the kernel (silence stdout; capture elapsed seconds)
  LC_ALL=C OMP_NUM_THREADS="$threads" OMP_PROC_BIND=close OMP_PLACES=cores \
    /usr/bin/time -f "%e" -o .t "$bin" "$n" >/dev/null
  time_s="$(cat .t)"

  flops="$(calc_flops "$n")"
  gflops="$(python3 - <<PY
flops=$flops
t=float("$time_s")
print(f"{flops/t/1e9:.6f}")
PY
)"
  bytes="$(bytes_est "$n")"
  oi="$(python3 - <<PY
flops=$flops
b=$bytes
print(f"{flops/b:.6f}")
PY
)"
  bw="$(python3 - <<PY
b=$bytes
t=float("$time_s")
print(f"{b/t/1e9:.6f}")
PY
)"

  echo "$variant,$n,$threads,$flops,$time_s,$gflops,$bytes,$oi,$bw,$ts" | tee -a "$csv"
done

rm -f .t
