#!/usr/bin/env bash
set -euo pipefail
BIN="$1"; shift || true
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
exec valgrind \
  --tool=memcheck \
  --leak-check=full --show-leak-kinds=all \
  --track-origins=yes \
  --error-exitcode=1 \
  --suppressions=./valgrind.supp \
  "$BIN" "$@"
