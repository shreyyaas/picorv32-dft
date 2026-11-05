# Baseline synthesis (no DFT)

| Metric | Value |
| --- | --- |
| Cells | 6,308 |
| Area | 78,831.86 um^2 |
| Flip-flops | 1,597 |
| Flop area | 44,782.95 um^2 (56.8% of total) |
| Tie cells (constant outputs) | 138 |
| Buffers in front of output ports | 138 |

## Flops by cell type

| Cell | Count | Area each (um^2) |
| --- | --- | --- |
| dfxtp_1 | 317 | 20.0192 |
| edfxtp_1 | 1,280 | 30.0288 |

## Where the flops are

| Block | Flops | Share |
| --- | --- | --- |
| register file (cpuregs) | 1,024 | 64.1% |
| control, datapath, memory interface | 445 | 27.9% |
| cycle/instret counters | 128 | 8.0% |

Register file: 32 entries (cpuregs[0] .. cpuregs[31]).

## Largest other registers

| Register | Flops |
| --- | --- |
| reg_out | 32 |
| alu_out_q | 32 |
| decoded_imm | 32 |
| mem_rdata_q | 32 |
| dbg_mem_wdata | 32 |
| reg_op2 | 32 |
| reg_op1 | 32 |
| reg_next_pc | 31 |
| reg_pc | 31 |
| dbg_mem_addr | 30 |
| decoded_imm_j | 20 |
| cpu_state | 7 |

## PicoRV32 parameters (defaults, unchanged)

| Parameter | Value |
| --- | --- |
| ENABLE_COUNTERS | 1 |
| ENABLE_COUNTERS64 | 1 |
| ENABLE_REGS_16_31 | 1 |
| ENABLE_REGS_DUALPORT | 1 |
| LATCHED_MEM_RDATA | 0 |
| TWO_STAGE_SHIFT | 1 |
| BARREL_SHIFTER | 0 |
| TWO_CYCLE_COMPARE | 0 |
| TWO_CYCLE_ALU | 0 |
| COMPRESSED_ISA | 0 |
| CATCH_MISALIGN | 1 |
| CATCH_ILLINSN | 1 |
| ENABLE_PCPI | 0 |
| ENABLE_MUL | 0 |
| ENABLE_FAST_MUL | 0 |
| ENABLE_DIV | 0 |
| ENABLE_IRQ | 0 |
| ENABLE_IRQ_QREGS | 1 |
| ENABLE_IRQ_TIMER | 1 |
| ENABLE_TRACE | 0 |
| REGS_INIT_ZERO | 0 |
| MASKED_IRQ | 32'h 0000_0000 |
| LATCHED_IRQ | 32'h ffff_ffff |
| PROGADDR_RESET | 32'h 0000_0000 |
| PROGADDR_IRQ | 32'h 0000_0010 |
| STACKADDR | 32'h ffff_ffff |
