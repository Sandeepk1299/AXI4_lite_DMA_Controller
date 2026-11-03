# AXI4-Lite DMA Controller with Descriptor Queue

A small memory-to-memory DMA written in Verilog. A CPU programs a transfer
(source, destination, length) through an AXI4-Lite slave interface, the
descriptor is pushed into a 4-entry FIFO, and the DMA engine pops it and copies
the data word by word.

```
AXI4-Lite master
      |
axi_lite_slave --> register_file --push--> desc_fifo --> dma_fsm
                        ^  (status)                          |
                        |                                    v
                    dma_done/busy <------------------- dma_controller --> memory_model
```

## Modules

| Order | File | Purpose | Testbench |
|-------|------|---------|-----------|
| 1 | `rtl/dma_fsm.v`        | IDLE / FETCH / TRANSFER / TRANSFER2 / DONE state machine | `tb/tb_dma_fsm.v` |
| 2 | `rtl/dma_controller.v` | Address/length counters, memory read/write control | `tb/tb_dma_controller.v` |
| 3 | `rtl/memory_model.v`   | 256 x 32 memory, async read, sync write | `tb/tb_memory_model.v` |
| 4 | `rtl/desc_fifo.v`      | 4-entry descriptor FIFO `{src, dest, len}` | `tb/tb_desc_fifo.v` |
| 5 | `rtl/register_file.v`  | SRC / DEST / LENGTH staging regs, CONTROL, STATUS | `tb/tb_register_file.v` |
| 6 | `rtl/axi_lite_slave.v` | AXI4-Lite write/read channels -> simple register bus | `tb/tb_axi_lite_slave.v` |
| 7 | `rtl/axi_dma_top.v`    | Top level that connects everything | `tb/tb_dma_simple.v` |

Each module has its own testbench. The inputs of every module testbench are the
values that module sees inside `axi_dma_top` while `tb_dma_simple` runs, so the
waveforms match the full-system simulation. `tb_dma_controller`, `tb_memory_model`
and `tb_axi_lite_slave` also use modules from earlier steps as helpers
(`dma_fsm`, `dma_controller`, `register_file`).

## Register map

| Offset | Name | Description |
|--------|------|-------------|
| 0x00 | SRC     | Source word address (staging register) |
| 0x04 | DEST    | Destination word address (staging register) |
| 0x08 | LENGTH  | Number of words to copy |
| 0x0C | CONTROL | bit0 = submit descriptor to FIFO, bit1 = clear overflow flag |
| 0x10 | STATUS  | read-only, see below |

STATUS: `[0]` done, `[1]` busy, `[2]` FIFO full, `[3]` FIFO empty, `[4]` overflow (sticky, set when a descriptor is submitted while the FIFO is full).

## How to program a transfer

1. Write SRC, DEST, LENGTH.
2. Write `1` to CONTROL -> descriptor goes into the FIFO.
3. Poll STATUS (or use `irq_dma_done`) until done.
4. Another descriptor can be queued while one is still running.

## Simulation

**Vivado:** add `rtl/*.v` as design sources and the testbench you want as a simulation source,
right-click it -> *Set as Top*, then *Run Simulation -> Run Behavioral Simulation* and press *Run All*
(the default 1000 ns is shorter than the tests).

**Icarus Verilog:**

```
./run_all.sh                 # every testbench + summary
./run_all.sh desc_fifo       # one module
```

Every testbench prints `TEST PASSED` or `TEST FAILED`.

## Known limitations

- `LENGTH` must be at least 2 (the end-of-transfer flag is raised when the remaining count reaches 1, so a length of 0 or 1 never terminates).
- Word addressing, 256-word memory model, single-clock design, OKAY responses only on AXI.

## Repository layout

```
rtl/   design files
tb/    one self-checking testbench per module
```

