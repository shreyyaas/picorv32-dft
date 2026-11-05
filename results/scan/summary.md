# Scan insertion (OpenROAD dft)

Baseline: 78,831.86 um^2, 1,597 flops.

| Chains | Longest chain (shift cycles/pattern) | Shortest | Area (um^2) | Overhead (um^2) | Overhead |
| --- | --- | --- | --- | --- | --- |
| 1 | 1,597 | 1,597 | 88,822.69 | 9,990.83 | 12.67% |
| 2 | 799 | 798 | 88,822.69 | 9,990.83 | 12.67% |
| 4 | 400 | 397 | 88,822.69 | 9,990.83 | 12.67% |
| 8 | 200 | 197 | 88,822.69 | 9,990.83 | 12.67% |
| 16 | 100 | 97 | 88,822.69 | 9,990.83 | 12.67% |

## Scan cells used

| Chains | sdfxtp_1 | sedfxtp_1 |
| --- | --- | --- |
| 1 | 317 | 1,280 |
| 2 | 317 | 1,280 |
| 4 | 317 | 1,280 |
| 8 | 317 | 1,280 |
| 16 | 317 | 1,280 |

## Checks

- Every flop was scan-replaced and stitched into exactly one chain.
- Chain lengths traced from the netlist match OpenROAD's plan.

Overhead excludes the scan-enable buffer tree a full flow would add
(the scan-enable net drives every scan flop directly here).
