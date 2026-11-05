`timescale 1ns/1ps
// tb_memory_model.v
// Same stimulus, signals and waveform as tb_dma_simple (AXI4-Lite master -> axi_dma_top).
// In addition, mon_memory_model (bottom of this file) checks the memory: every write lands at the right address, reads return the stored word, and (like tb_dma_simple) every job is copied word by word.


module tb_memory_model;

localparam REG_SRC    = 32'h00;
localparam REG_DEST   = 32'h04;
localparam REG_LEN    = 32'h08;
localparam REG_CTRL   = 32'h0C;
localparam REG_STATUS = 32'h10;

// Test 1 : single job
localparam SRC_BASE  = 32'd0;
localparam DEST_BASE = 32'd32;
localparam XFER_LEN  = 32'd8;

// Test 2 : two queued jobs (B is programmed while A is running)
localparam A_SRC = 32'd64,  A_DEST = 32'd128, A_LEN = 32'd32;
localparam B_SRC = 32'd100, B_DEST = 32'd200, B_LEN = 32'd16;

reg clk = 0;
reg reset;

reg  [31:0] awaddr, wdata, araddr;
reg         awvalid, wvalid, bready, arvalid, rready;
wire        awready, wready, bvalid, arready, rvalid;
wire [1:0]  bresp, rresp;
wire [31:0] rdata;
wire        irq_dma_done;

integer i, errors;
reg [31:0] status_rd, rd_val;
time t_push_a, t_done;

always #5 clk = ~clk;   // 100 MHz

axi_dma_top dut (
    .clk(clk), .reset(reset),
    .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata),   .s_axi_wstrb(4'hF),       .s_axi_wvalid(wvalid), .s_axi_wready(wready),
    .s_axi_bresp(bresp),   .s_axi_bvalid(bvalid),    .s_axi_bready(bready),
    .s_axi_araddr(araddr), .s_axi_arvalid(arvalid),  .s_axi_arready(arready),
    .s_axi_rdata(rdata),   .s_axi_rresp(rresp),      .s_axi_rvalid(rvalid), .s_axi_rready(rready),
    .irq_dma_done(irq_dma_done)
);

// per-module checker (see bottom of this file)
mon_memory_model u_mon (.clk(clk), .reset(reset));

task axi_write(input [31:0] addr, input [31:0] data);
    reg aw_done, w_done;
    begin
        aw_done = 0; w_done = 0;
        awaddr = addr; awvalid = 1;
        wdata  = data; wvalid  = 1;
        bready = 1;

        while (!(aw_done && w_done)) begin
            @(posedge clk);
            if (!aw_done && awready) begin
                awvalid = 0;
                aw_done = 1;
            end
            if (!w_done && wready) begin
                wvalid = 0;
                w_done = 1;
            end
        end

        while (!bvalid) @(posedge clk);
        @(posedge clk);
        bready = 0;
    end
endtask

task axi_read(input [31:0] addr, output [31:0] data);
    begin
        araddr = addr; arvalid = 1; rready = 1;
        while (!arready) @(posedge clk);
        @(posedge clk);
        arvalid = 0;
        while (!rvalid) @(posedge clk);
        data = rdata;
        @(posedge clk);
        rready = 0;
    end
endtask

initial begin
    $dumpfile("tb_memory_model.vcd");
    $dumpvars(0, tb_memory_model);
end

initial begin
    awvalid = 0; wvalid = 0; bready = 0; arvalid = 0; rready = 0;
    awaddr = 0; wdata = 0; araddr = 0;
    reset = 1;
    errors = 0;
    repeat (3) @(posedge clk);
    reset = 0;
    repeat (2) @(posedge clk);

    // =====================================================
    // TEST 1 : single transfer (same as original testbench)
    // =====================================================
    for (i = 0; i < XFER_LEN; i = i + 1) begin
        dut.u_memory_model.mem[SRC_BASE  + i] = 32'hA000_0000 + i;
        dut.u_memory_model.mem[DEST_BASE + i] = 32'h0;
    end

    axi_write(REG_SRC,  SRC_BASE);
    axi_write(REG_DEST, DEST_BASE);
    axi_write(REG_LEN,  XFER_LEN);
    axi_write(REG_CTRL, 32'h1);        // submit
    $display("[%0t] TEST1: job submitted src=%0d dest=%0d len=%0d", $time, SRC_BASE, DEST_BASE, XFER_LEN);

    status_rd = 0; i = 0;
    while ((status_rd & 32'hB) != 32'h9 && i < 500) begin
        axi_read(REG_STATUS, status_rd);
        i = i + 1;
    end
    if ((status_rd & 32'hB) != 32'h9) begin
        $display("[%0t] ERROR: TEST1 DMA never finished, status=%0h", $time, status_rd);
        errors = errors + 1;
    end else
        $display("[%0t] TEST1: DMA done, polled status %0d time(s), status=%0h", $time, i, status_rd);

    repeat (3) @(posedge clk);
    for (i = 0; i < XFER_LEN; i = i + 1)
        if (dut.u_memory_model.mem[DEST_BASE + i] !== dut.u_memory_model.mem[SRC_BASE + i]) begin
            $display("[%0t] TEST1 MISMATCH idx=%0d src=%h dest=%h", $time, i,
                     dut.u_memory_model.mem[SRC_BASE + i], dut.u_memory_model.mem[DEST_BASE + i]);
            errors = errors + 1;
        end

    // =====================================================
    // TEST 2 : queue job B while job A is still running
    // =====================================================
    for (i = 0; i < A_LEN; i = i + 1) begin
        dut.u_memory_model.mem[A_SRC  + i] = 32'hA100_0000 + i;
        dut.u_memory_model.mem[A_DEST + i] = 32'h0;
    end
    for (i = 0; i < B_LEN; i = i + 1) begin
        dut.u_memory_model.mem[B_SRC  + i] = 32'hB200_0000 + i;
        dut.u_memory_model.mem[B_DEST + i] = 32'h0;
    end

    // job A
    axi_write(REG_SRC,  A_SRC);
    axi_write(REG_DEST, A_DEST);
    axi_write(REG_LEN,  A_LEN);
    t_push_a = $time;
    axi_write(REG_CTRL, 32'h1);
    $display("[%0t] TEST2: job A submitted src=%0d dest=%0d len=%0d", $time, A_SRC, A_DEST, A_LEN);

    // job B, programmed while A is running
    axi_write(REG_SRC,  B_SRC);
    axi_write(REG_DEST, B_DEST);
    axi_write(REG_LEN,  B_LEN);
    axi_write(REG_CTRL, 32'h1);
    $display("[%0t] TEST2: job B submitted src=%0d dest=%0d len=%0d (A still running)", $time, B_SRC, B_DEST, B_LEN);

    axi_read(REG_STATUS, rd_val);
    $display("[%0t] TEST2: status right after queuing B = %h  (busy bit1 = %0d, expected 1)", $time, rd_val, rd_val[1]);
    if (rd_val[1] !== 1'b1) begin
        $display("ERROR: DMA was not busy while B was queued");
        errors = errors + 1;
    end

    status_rd = 0; i = 0;
    while ((status_rd & 32'hB) != 32'h9 && i < 500) begin
        axi_read(REG_STATUS, status_rd);
        i = i + 1;
    end
    t_done = $time;
    if ((status_rd & 32'hB) != 32'h9) begin
        $display("[%0t] ERROR: TEST2 DMA never finished, status=%0h", $time, status_rd);
        errors = errors + 1;
    end else
        $display("[%0t] TEST2: both jobs done, status=%0h (done=1 busy=0 empty=1)", $time, status_rd);

    repeat (3) @(posedge clk);
    for (i = 0; i < A_LEN; i = i + 1)
        if (dut.u_memory_model.mem[A_DEST + i] !== dut.u_memory_model.mem[A_SRC + i]) begin
            $display("[%0t] JOB A MISMATCH idx=%0d src=%h dest=%h", $time, i,
                     dut.u_memory_model.mem[A_SRC + i], dut.u_memory_model.mem[A_DEST + i]);
            errors = errors + 1;
        end
    for (i = 0; i < B_LEN; i = i + 1)
        if (dut.u_memory_model.mem[B_DEST + i] !== dut.u_memory_model.mem[B_SRC + i]) begin
            $display("[%0t] JOB B MISMATCH idx=%0d src=%h dest=%h", $time, i,
                     dut.u_memory_model.mem[B_SRC + i], dut.u_memory_model.mem[B_DEST + i]);
            errors = errors + 1;
        end

    // register readback (staging register holds job B's length)
    axi_read(REG_LEN, rd_val);
    if (rd_val !== B_LEN) begin
        $display("[%0t] ERROR: LENGTH readback = %0d, expected %0d", $time, rd_val, B_LEN);
        errors = errors + 1;
    end

    // ---- memory_model checks ----
    errors = errors + u_mon.err;
    $display("[INFO] Test 2 total time from submit A to both done: %0t ns", t_done - t_push_a);

    if (errors == 0)
        $display("TEST PASSED");
    else
        $display("TEST FAILED: %0d error(s)", errors);

    $finish;
end

initial begin
    #100000;
    $display("[%0t] ERROR: simulation timeout", $time);
    $finish;
end

endmodule

module mon_memory_model (input clk, input reset);
    integer err = 0;
    reg        pend = 0;
    reg [31:0] pa = 0, pd = 0;
    always @(posedge clk) begin
        if (!reset) begin
            // a write seen on the previous edge must now be stored
            if (pend && tb_memory_model.dut.u_memory_model.mem[pa] !== pd) begin
                $display("[%0t] MON ERROR: mem[%0d] = %h, expected %h", $time, pa, tb_memory_model.dut.u_memory_model.mem[pa], pd);
                err = err + 1;
            end
            pend = 0;
            if (tb_memory_model.dut.mem_wr_en === 1'b1) begin
                pend = 1; pa = tb_memory_model.dut.mem_wr_addr; pd = tb_memory_model.dut.mem_wr_data;
                if (tb_memory_model.dut.mem_wr_addr > 255) begin
                    $display("[%0t] MON ERROR: write address %0d outside the 256-word memory", $time, tb_memory_model.dut.mem_wr_addr);
                    err = err + 1;
                end
            end
            // asynchronous read
            if (tb_memory_model.dut.mem_rd_data !== tb_memory_model.dut.u_memory_model.mem[tb_memory_model.dut.mem_rd_addr]) begin
                $display("[%0t] MON ERROR: rd_data=%h but mem[%0d]=%h", $time, tb_memory_model.dut.mem_rd_data,
                         tb_memory_model.dut.mem_rd_addr, tb_memory_model.dut.u_memory_model.mem[tb_memory_model.dut.mem_rd_addr]);
                err = err + 1;
            end
        end
    end
endmodule