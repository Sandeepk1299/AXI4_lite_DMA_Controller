# AXI4-Lite DMA Controller with Descriptor Queue
### Memory-to-Memory DMA with a Hardware Job FIFO and FSM-Driven Transfer Engine in Verilog

A compact, register-programmable Direct Memory Access (DMA) controller written in Verilog. The CPU programs a transfer through an AXI4-Lite slave interface and walks away: the request is pushed into a 4-entry descriptor FIFO, and an FSM-driven engine copies the data word by word while the CPU is free to queue the next job. Completion is reported through a STATUS register and an interrupt line.

![Waveform](docs/waveform.png)

## Key Performance Metrics

- **Control Interface:** AXI4-Lite slave, 32-bit address and data (width parameterizable), independent write and read channels, OKAY responses
- **Job Queue:** 4-entry descriptor FIFO (depth parameterizable via `DEPTH_LOG2`), each entry holds `{source, destination, length}` (96 bits)
- **Transfer Engine:** 32-bit word copy, one word every 2 clock cycles
- **Job Latency:** `2N + 2` clock cycles for an N-word job (1 FETCH + 2 per word + 1 DONE), so an 8-word job completes in 18 cycles (180 ns at the 100 MHz simulation clock)
- **Memory Model:** 256 x 32-bit words, asynchronous read, synchronous write
- **Register Map:** 5 registers (SRC, DEST, LENGTH, CONTROL, STATUS)
- **Status Reporting:** done, busy, FIFO full, FIFO empty and a sticky overflow flag, plus a level interrupt output `irq_dma_done`

## Architecture

![Architecture](docs/architecture.png)

```
AXI4-Lite master (CPU)
        |
  axi_lite_slave --> register_file --push--> desc_fifo --> dma_fsm
                          ^                                   |
                          |                              (state, status)
                  dma_done / dma_busy                         |
                          +----------------------------- dma_controller --> memory_model
```

## Architectural Breakdown & Subsystem Design

### 1. AXI4-Lite Slave (`axi_lite_slave.v`)
Bridges the AXI4-Lite bus to a simple register bus (`wr_en / wr_addr / wr_data`, `rd_en / rd_addr / rd_data`).
- **Write path:** the address (AW) and data (W) channels are accepted independently and in either order; the slave latches both, then issues a single-cycle write strobe to the register file and returns a write response.
- **Read path:** the address is captured, the register file is read for one cycle and the data is returned with an OKAY response.
- **Back-pressure:** a new write or read is not accepted while the previous response is still waiting for `bready` / `rready`.
- Only the low 5 address bits are decoded. Byte strobes (`wstrb`) are not used, so every write is a full 32-bit write.

### 2. Register File (`register_file.v`)
SRC, DEST and LENGTH are **staging registers**. Writing CONTROL with bit 0 set generates a one-cycle `push` that copies them into the descriptor FIFO, so the CPU can immediately reprogram the registers for the next job.
- **STATUS (read-only):** `[0]` done, `[1]` busy, `[2]` FIFO full, `[3]` FIFO empty, `[4]` overflow. The register follows its inputs with one cycle of latency; done has priority over busy.
- **Overflow:** sticky flag, set when a job is submitted while the FIFO is full. Writing CONTROL bit 1 clears it; if both happen in the same cycle, set wins.

### 3. Descriptor FIFO (`desc_fifo.v`)
Holds queued jobs `{src, dest, len}` so the next transfer can be programmed while the current one is running.
- Circular buffer with pointers one bit wider than the address; the extra "lap" bit separates the full condition from the empty condition.
- First-word-fall-through output: the oldest descriptor is always visible on `out_src / out_dest / out_len`.
- A push while full and a pop while empty are ignored.

### 4. DMA FSM (`dma_fsm.v`)
Five states: `IDLE -> FETCH -> TRANSFER -> TRANSFER2 -> (TRANSFER | DONE) -> IDLE`.
- `IDLE` moves to `FETCH` when the FIFO is not empty (`job_available = !fifo_empty`).
- The descriptor is popped from the FIFO during `FETCH`.
- `TRANSFER2` loops back to `TRANSFER` until the controller raises its last-beat flag, then goes to `DONE`.

### 5. DMA Controller (`dma_controller.v`)
Datapath that executes one descriptor.
- `FETCH`: latches source, destination and length, sets `dma_busy`, clears `dma_done`.
- `TRANSFER`: drives the read address and the write address, enables the memory write and decrements the remaining length.
- `TRANSFER2`: captures the read data into the write-data register and increments both addresses.
- The last-beat flag is raised one beat early so the FSM, which sees it with one cycle of delay, leaves exactly after the final word. For a length of 0 or 1 there is no earlier beat, so the flag is raised in `FETCH` and exactly one word is copied.
- `DONE`: clears busy, sets `dma_done` (stays high until the next job is fetched).

### 6. Memory Model (`memory_model.v`)
256 x 32-bit memory with asynchronous read and synchronous write, standing in for system memory.

### 7. Top Level (`axi_dma_top.v`)
Connects the six modules, derives `fifo_pop` from the FSM `FETCH` state and exposes `irq_dma_done`.

## Register Map

| Offset | Name    | Access | Description |
|--------|---------|--------|-------------|
| 0x00   | SRC     | R/W    | Source word address (staging register) |
| 0x04   | DEST    | R/W    | Destination word address (staging register) |
| 0x08   | LENGTH  | R/W    | Number of words to copy |
| 0x0C   | CONTROL | R/W    | bit 0 = submit job to FIFO, bit 1 = clear overflow flag |
| 0x10   | STATUS  | R      | bit 0 done, bit 1 busy, bit 2 FIFO full, bit 3 FIFO empty, bit 4 overflow |

### Programming Sequence
1. Write SRC, DEST and LENGTH.
2. Write `1` to CONTROL to submit the job.
3. Optionally program and submit the next job while this one runs.
4. Poll STATUS (done = 1, busy = 0) or wait for `irq_dma_done`.

```c
dma[0] = src;  dma[1] = dest;  dma[2] = len;   // SRC, DEST, LENGTH
dma[3] = 1;                                     // CONTROL: submit
while ((dma[4] & 0xB) != 0x9);                  // STATUS: wait for done, not busy, FIFO empty
```

## Verification & Test Suite Architecture

Each module has its own self-checking testbench (`testbench/`), and every testbench prints `TEST PASSED` or `TEST FAILED`. They all drive the same AXI4-Lite master sequence into `axi_dma_top` and add a checker for the module under test.

### System Stimulus (`tb_dma_simple.v`)
- **Test 1 - Single Transfer:** programs an 8-word job (source 0 to destination 32), submits it, polls STATUS until done and compares destination against source word by word.
- **Test 2 - Queued Jobs:** submits job A (32 words, 64 to 128) and, while A is still running, programs and submits job B (16 words, 100 to 200). Checks that STATUS shows busy right after B is queued, waits for both jobs and compares both destinations.
- **Register Readback:** reads LENGTH back and checks that it holds job B's length.
- **Total:** 3 jobs and 56 words moved, completing in about 1.67 us of simulated time.

### Per-Module Checks

| Testbench | Module Under Test | What It Checks |
|-----------|-------------------|----------------|
| `tb_axi_lite_slave.v`  | AXI4-Lite slave | Every write reaches the register bus exactly once with the right address and data (12 writes); all write and read responses are OKAY |
| `tb_register_file.v`   | Register file   | Registers hold the written values, STATUS follows done / busy / full / empty, read data is correct, final registers match job B |
| `tb_desc_fifo.v`       | Descriptor FIFO | Descriptors leave in the order they entered (scoreboard), no push while full, 3 pushes and 3 pops, FIFO empty at the end |
| `tb_dma_fsm.v`         | DMA FSM         | Only legal state transitions, 3 DONE states visited, back in IDLE at the end |
| `tb_memory_model.v`    | Memory model    | Every write lands at the right address, asynchronous read returns the stored word, addresses stay inside the memory |
| `tb_dma_controller.v`  | DMA controller  | busy and done never high together, memory write only while busy, 56 words moved, 3 done events |
| `tb_dma_simple.v`      | Whole design    | System-level copy checks described above |

## Synthesis

Synthesized in Vivado. Resource utilization:

![Utilization](docs/utilization.png)


