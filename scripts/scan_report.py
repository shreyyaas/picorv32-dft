#!/usr/bin/env python3
"""Step 3 report: what scan insertion cost, and the chains it built.

For every results/scan/chains_<N>/ run it:
  * re-adds the cell areas from the Liberty file -> area and overhead vs baseline
  * traces each chain through the netlist (scan-in port -> SCD -> Q -> SCD ...)
    and writes it in shift order to chains.json (steps 4-6 need that order)
  * cross-checks the traced chain lengths against OpenROAD's own plan in the log
  * flags flops that were not scan-replaced or not stitched into any chain
"""
import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

from baseline_report import PREFIX, is_flop, liberty_areas, parse_netlist


def is_scan(cell):
    base = cell.replace(PREFIX, "")
    return base.startswith("sdf") or base.startswith("sedf")


def input_ports(text):
    ports = set()
    for m in re.finditer(r"^\s*input\s+(\[(\d+):(\d+)\]\s*)?(\\?\S+?)\s*;", text, re.M):
        name = m.group(4).lstrip("\\")
        if m.group(1):
            hi, lo = int(m.group(2)), int(m.group(3))
            ports |= {f"{name}[{i}]" for i in range(min(hi, lo), max(hi, lo) + 1)}
        else:
            ports.add(name)
    return ports


def trace_chains(insts, inputs):
    """Follow SCD pins from each scan-in port to the end of its chain."""
    scan = {name: pins for cell, name, pins in insts if is_scan(cell)}
    driver = {pins["Q"]: name for name, pins in scan.items() if pins.get("Q")}
    succ, heads, loose = {}, [], []
    for name, pins in scan.items():
        scd = pins.get("SCD", "")
        if scd in driver:
            succ[driver[scd]] = name
        elif scd in inputs:
            heads.append((scd, name))
        else:
            loose.append(name)          # scan flop whose SCD is not stitched
    chains = []
    for scan_in, head in sorted(heads, key=lambda h: [int(x) if x.isdigit() else x
                                                      for x in re.split(r"(\d+)", h[0])]):
        order, seen = [head], {head}
        while order[-1] in succ:
            nxt = succ[order[-1]]
            if nxt in seen:
                raise SystemExit(f"scan loop found at {nxt}")
            order.append(nxt)
            seen.add(nxt)
        chains.append({
            "scan_in": scan_in,
            "scan_out": scan[order[-1]]["Q"],
            "scan_enable": sorted({scan[f].get("SCE", "") for f in order}),
            "length": len(order),
            "flops": order,
        })
    return chains, loose


def planned_lengths(log_path):
    """Chain lengths OpenROAD printed in report_dft_plan."""
    if not log_path.exists():
        return []
    text = log_path.read_text(errors="replace")
    return sorted(int(n) for n in re.findall(r"Scan chain '\S+' has (\d+) cells", text))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lib", required=True)
    ap.add_argument("--baseline", required=True, help="results/baseline")
    ap.add_argument("--scan", required=True, help="results/scan")
    args = ap.parse_args()

    areas = liberty_areas(args.lib)
    base = json.loads((Path(args.baseline) / "summary.json").read_text())
    base_area, base_flops = base["area_um2"], base["flops"]

    rows, problems = [], []
    runs = sorted(Path(args.scan).glob("chains_*/picorv32_scan.v"),
                  key=lambda p: int(p.parent.name.split("_")[1]))
    if not runs:
        raise SystemExit("no scan netlists found")
    for netlist in runs:
        d = netlist.parent
        n_req = int(d.name.split("_")[1])
        text = netlist.read_text()
        insts, _ = parse_netlist(netlist)
        inputs = input_ports(text)

        area = sum(areas[c] for c, _, _ in insts)
        flops = Counter(c.replace(PREFIX, "") for c, _, _ in insts if is_flop(c))
        not_replaced = {c: n for c, n in flops.items() if not is_scan(PREFIX + c)}
        chains, loose = trace_chains(insts, inputs)
        lengths = sorted(ch["length"] for ch in chains)
        stitched = sum(lengths)
        n_scan = sum(n for c, n in flops.items() if is_scan(PREFIX + c))

        if not_replaced:
            problems.append(f"{d.name}: flops NOT scan-replaced: {not_replaced}")
        if loose or stitched != n_scan:
            problems.append(f"{d.name}: {n_scan - stitched} scan flops not in any chain")
        planned = planned_lengths(d / "openroad.log")
        if planned and planned != lengths:
            problems.append(f"{d.name}: traced lengths {lengths} != OpenROAD plan {planned}")
        if len(chains) != n_req:
            problems.append(f"{d.name}: asked for {n_req} chains, OpenROAD built {len(chains)}")
        if sum(flops.values()) != base_flops:
            problems.append(f"{d.name}: {sum(flops.values())} flops vs {base_flops} in baseline")

        (d / "chains.json").write_text(json.dumps(
            {"chains_requested": n_req, "chains": chains}, indent=1) + "\n")
        rows.append({
            "chains_requested": n_req,
            "chains_built": len(chains),
            "longest": max(lengths) if lengths else 0,
            "shortest": min(lengths) if lengths else 0,
            "flops_stitched": stitched,
            "area_um2": round(area, 4),
            "overhead_um2": round(area - base_area, 4),
            "overhead_pct": round(100 * (area - base_area) / base_area, 3),
            "flops_by_type": dict(sorted(flops.items())),
            "plan_matches_netlist": (planned == lengths) if planned else None,
        })

    out = Path(args.scan)
    (out / "summary.json").write_text(json.dumps(
        {"baseline_area_um2": base_area, "baseline_flops": base_flops,
         "runs": rows, "problems": problems}, indent=2) + "\n")

    md = ["# Scan insertion (OpenROAD dft)", "",
          f"Baseline: {base_area:,.2f} um^2, {base_flops:,} flops.", "",
          "| Chains | Longest chain (shift cycles/pattern) | Shortest | Area (um^2) | Overhead (um^2) | Overhead |",
          "| --- | --- | --- | --- | --- | --- |"]
    for r in rows:
        md.append(f"| {r['chains_built']} | {r['longest']:,} | {r['shortest']:,} | {r['area_um2']:,.2f} "
                  f"| {r['overhead_um2']:,.2f} | {r['overhead_pct']:.2f}% |")
    md += ["", "## Scan cells used", "",
           "| Chains | " + " | ".join(rows[0]["flops_by_type"]) + " |",
           "| --- " * (len(rows[0]["flops_by_type"]) + 1) + "|"]
    for r in rows:
        md.append(f"| {r['chains_built']} | " + " | ".join(f"{n:,}" for n in r["flops_by_type"].values()) + " |")
    md += ["", "## Checks", ""]
    md += [f"- PROBLEM: {p}" for p in problems] or [
        "- Every flop was scan-replaced and stitched into exactly one chain.",
        "- Chain lengths traced from the netlist match OpenROAD's plan."]
    md += ["", "Overhead excludes the scan-enable buffer tree a full flow would add",
           "(the scan-enable net drives every scan flop directly here).", ""]
    (out / "summary.md").write_text("\n".join(md))

    print(f"baseline {base_area:,.2f} um^2")
    for r in rows:
        print(f"chains={r['chains_built']:<3} longest={r['longest']:<5} area={r['area_um2']:,.2f} "
              f"overhead={r['overhead_um2']:,.2f} ({r['overhead_pct']:.2f}%)")
    for p in problems:
        print("PROBLEM:", p)
    print(f"report: {out / 'summary.md'}")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
