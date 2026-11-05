#!/usr/bin/env python3
"""Summarise the baseline netlist: cells, flops, area and where the flops are.

Inputs come from synth_baseline.sh. Area is recomputed from the Liberty file
and cross-checked against Yosys's own total, so a parsing slip cannot go
unnoticed. Writes summary.md (for people) and summary.json (for later steps).
"""
import argparse
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

PREFIX = "sky130_fd_sc_hd__"


def liberty_areas(lib_path):
    """Map cell name -> area (um^2), read straight from the .lib file."""
    areas, cell = {}, None
    for line in open(lib_path):
        m = re.match(r'\s*cell\s*\(\s*"?([\w]+)"?\s*\)', line)
        if m:
            cell = m.group(1)
            continue
        m = re.match(r"\s*area\s*:\s*([0-9.eE+-]+)", line)
        if m and cell and cell not in areas:
            areas[cell] = float(m.group(1))
    return areas


def yosys_stat(stat_path):
    """Return (cells_by_type, yosys_area) from `stat -json`."""
    data = json.load(open(stat_path))
    mod = next(iter(data["modules"].values()))
    return mod["num_cells_by_type"], mod.get("area")


def is_flop(cell):
    # SKY130 flip-flops all have "df" in the base name (dfxtp, edfxtp, dfrtp ...)
    return "df" in cell.replace(PREFIX, "")


def parse_netlist(path):
    """Yield (cell_type, {pin: net}) for every instance, and the output ports."""
    text = Path(path).read_text()
    outputs = set()
    for m in re.finditer(r"^\s*output\s+(\[(\d+):(\d+)\]\s*)?(\\?\S+?)\s*;", text, re.M):
        name = m.group(4).lstrip("\\")
        if m.group(1):
            hi, lo = int(m.group(2)), int(m.group(3))
            outputs |= {f"{name}[{i}]" for i in range(min(hi, lo), max(hi, lo) + 1)}
        else:
            outputs.add(name)
    insts = []
    for m in re.finditer(rf"^\s*({PREFIX}\w+)\s+\S+\s*\((.*?)\);", text, re.M | re.S):
        pins = {p: n.strip().lstrip("\\").replace(" ", "")
                for p, n in re.findall(r"\.(\w+)\(([^()]*)\)", m.group(2))}
        insts.append((m.group(1), pins))
    return insts, outputs


def register_name(net):
    """'cpuregs[5][3]' -> 'cpuregs[5]';  'count_cycle[63]' -> 'count_cycle'."""
    return re.sub(r"\[\d+\]$", "", net)


def main():
    ap = argparse.ArgumentParser()
    for a in ("--lib", "--netlist", "--stat", "--rtl", "--out"):
        ap.add_argument(a, required=True)
    args = ap.parse_args()

    areas = liberty_areas(args.lib)
    by_type, yosys_area = yosys_stat(args.stat)
    total_area = sum(areas[c] * n for c, n in by_type.items())
    if yosys_area is not None and abs(total_area - yosys_area) > 0.01:
        raise SystemExit(f"area mismatch: liberty sum {total_area:.3f} vs yosys {yosys_area:.3f}")

    flop_types = {c: n for c, n in by_type.items() if is_flop(c)}
    n_flops = sum(flop_types.values())
    flop_area = sum(areas[c] * n for c, n in flop_types.items())

    insts, outputs = parse_netlist(args.netlist)
    if len(insts) != sum(by_type.values()):
        raise SystemExit(f"netlist has {len(insts)} instances, stat says {sum(by_type.values())}")

    # Where are the flops? Group each flop by the register its Q pin drives.
    regs = Counter(register_name(p.get("Q", "?")) for c, p in insts if is_flop(c))
    groups = defaultdict(int)
    for reg, n in regs.items():
        if reg.startswith("cpuregs["):
            groups["register file (cpuregs)"] += n
        elif reg in ("count_cycle", "count_instr"):
            groups["cycle/instret counters"] += n
        else:
            groups["control, datapath, memory interface"] += n
    regfile_entries = sorted((r for r in regs if r.startswith("cpuregs[")),
                             key=lambda r: int(r[8:-1]))

    # Glue the clean-up commands added: tie cells and buffers in front of outputs
    ties = by_type.get(PREFIX + "conb_1", 0)
    port_bufs = sum(1 for c, p in insts
                    if c.startswith(PREFIX + "buf_") and p.get("X") in outputs)

    # Module parameters as written in the RTL (synthesis used the defaults)
    rtl = Path(args.rtl).read_text()
    header = rtl[rtl.index("module picorv32 #("):]
    header = header[:header.index(") (")]
    params = re.findall(r"parameter\s+\[[^\]]*\]\s+(\w+)\s*=\s*([^,\n]+)", header)

    summary = {
        "cells": sum(by_type.values()),
        "area_um2": round(total_area, 4),
        "flops": n_flops,
        "flop_area_um2": round(flop_area, 4),
        "flops_by_type": {c.replace(PREFIX, ""): n for c, n in sorted(flop_types.items())},
        "flop_groups": dict(groups),
        "regfile_entries": len(regfile_entries),
        "tie_cells": ties,
        "output_buffers": port_bufs,
        "parameters": {k: v.strip() for k, v in params},
    }
    out = Path(args.out)
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")

    pct = lambda x, tot: f"{100 * x / tot:.1f}%"
    md = [
        "# Baseline synthesis (no DFT)", "",
        "| Metric | Value |", "| --- | --- |",
        f"| Cells | {summary['cells']:,} |",
        f"| Area | {total_area:,.2f} um^2 |",
        f"| Flip-flops | {n_flops:,} |",
        f"| Flop area | {flop_area:,.2f} um^2 ({pct(flop_area, total_area)} of total) |",
        f"| Tie cells (constant outputs) | {ties} |",
        f"| Buffers in front of output ports | {port_bufs} |",
        "", "## Flops by cell type", "",
        "| Cell | Count | Area each (um^2) |", "| --- | --- | --- |",
        *[f"| {c.replace(PREFIX, '')} | {n:,} | {areas[c]:.4f} |" for c, n in sorted(flop_types.items())],
        "", "## Where the flops are", "",
        "| Block | Flops | Share |", "| --- | --- | --- |",
        *[f"| {g} | {n:,} | {pct(n, n_flops)} |" for g, n in sorted(groups.items(), key=lambda x: -x[1])],
        "",
        f"Register file: {len(regfile_entries)} entries ({regfile_entries[0]} .. {regfile_entries[-1]}).",
        "", "## Largest other registers", "",
        "| Register | Flops |", "| --- | --- |",
        *[f"| {r} | {n} |" for r, n in regs.most_common()
          if not r.startswith("cpuregs[") and r not in ("count_cycle", "count_instr")][:12],
        "", "## PicoRV32 parameters (defaults, unchanged)", "",
        "| Parameter | Value |", "| --- | --- |",
        *[f"| {k} | {v.strip()} |" for k, v in params],
        "",
    ]
    (out / "summary.md").write_text("\n".join(md))

    print(f"cells : {summary['cells']:,}")
    print(f"area  : {total_area:,.2f} um^2")
    print(f"flops : {n_flops:,}  " + ", ".join(f"{c}={n}" for c, n in summary['flops_by_type'].items()))
    for g, n in sorted(groups.items(), key=lambda x: -x[1]):
        print(f"        {n:5,}  {g}")
    print(f"glue  : {ties} tie cells, {port_bufs} output buffers")
    print(f"report: {out / 'summary.md'}")


if __name__ == "__main__":
    main()
