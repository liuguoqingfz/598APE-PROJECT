#!/usr/bin/env python3
"""
Write calibration.json from environment variables B_MEM and F_PEAK.

Usage:
  B_MEM=<gbps> F_PEAK=<gflops> python3 scripts/write_calibration.py

Notes:
  - Expects the project layout .../results/calibration.json
  - Fails with a clear message if variables are missing or not numeric.
"""

import json
import os
import sys
from pathlib import Path

def main() -> int:
    b = os.environ.get("B_MEM")
    f = os.environ.get("F_PEAK")

    if not b or not f:
        print("Error: missing B_MEM or F_PEAK; re-run the benchmarks or fix extraction.",
              file=sys.stderr)
        print("Example:", file=sys.stderr)
        print("  B_MEM=18.7 F_PEAK=104.9 python3 scripts/write_calibration.py", file=sys.stderr)
        return 1

    try:
        b_val = float(b)
        f_val = float(f)
    except ValueError:
        print(f"Error: non-numeric values. B_MEM={b!r}, F_PEAK={f!r}", file=sys.stderr)
        return 1

    results_dir = Path("results")
    results_dir.mkdir(parents=True, exist_ok=True)
    out_path = results_dir / "calibration.json"

    data = {"B_mem_GBs": b_val, "F_peak_GFLOPs": f_val}

    # Write atomically: write to temp file, then replace
    tmp_path = out_path.with_suffix(".json.tmp")
    with tmp_path.open("w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    tmp_path.replace(out_path)

    print(f"Wrote {out_path} with B_mem_GBs={b_val} and F_peak_GFLOPs={f_val}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
