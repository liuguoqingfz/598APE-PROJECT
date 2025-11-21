import pandas as pd, matplotlib.pyplot as plt, json
df = pd.read_csv("results/results.csv")
calib = json.load(open("results/calibration.json"))
B = float(calib["B_mem_GBs"]); F = float(calib["F_peak_GFLOPs"])

fig, ax = plt.subplots()
ax.set_xscale('log'); ax.set_yscale('log')
ax.set_xlabel("Operational Intensity (FLOPs/byte)")
ax.set_ylabel("GFLOP/s")

oi_min, oi_max = 1e-3, 1e3
ax.plot([oi_min, oi_max], [B*oi_min, B*oi_max], '--', label=f"Memory roof ({B:.1f} GB/s)")
ax.hlines(F, oi_min, oi_max, linestyles='--', label=f"Compute roof ({F:.0f} GF/s)")

for v, sub in df.groupby("variant"):
    ax.scatter(sub["oi"], sub["gflops"], label=v, s=30)

ax.set_xlim(oi_min, oi_max)
ax.grid(True, which='both', alpha=0.3)
ax.legend()
plt.tight_layout()
plt.savefig("results/roofline.png", dpi=180)
print("Wrote results/roofline.png")
