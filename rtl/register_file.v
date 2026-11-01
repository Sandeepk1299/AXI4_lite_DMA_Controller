// register_file.v
// SRC/DEST/LENGTH are now STAGING registers. Writing CONTROL[0]=1 generates
// a one-cycle 'push' that copies them into the descriptor FIFO.
// STATUS: [0]=done [1]=busy [2]=fifo_full [3]=fifo_empty [4]=overflow(sticky)
// CONTROL[1]=1 clears overflow.
module register_file(
    input clk,
    input reset,
    input wire wr_en,
    input wire [4:0] wr_addr,
    input wire [31:0] wr_data,
    input wire rd_en,
    input wire [4:0] rd_addr,
    output reg [31:0] rd_data,
    input wire dma_done,
    input wire dma_busy,
    input wire fifo_full,
    input wire fifo_empty,
    output wire push,
    output reg [31:0] src_addr,
    output reg [31:0] dest_addr,
    output reg [31:0] length,
    output reg [31:0] control,
    output reg [31:0] status
);

reg overflow;

// one-cycle submit pulse: CPU wrote CONTROL with bit0 = 1
assign push = wr_en && (wr_addr == 5'h0c) && wr_data[0];

// original encoding kept: done = 01, busy = 10, idle = 00
wire [1:0] st_low = dma_done ? 2'b01 : (dma_busy ? 2'b10 : 2'b00);

// ---------------- read side ----------------
always @(*) begin
    rd_data = 32'b0;
    if (rd_en) begin
        if      (rd_addr == 5'h00) rd_data = src_addr;
        else if (rd_addr == 5'h04) rd_data = dest_addr;
        else if (rd_addr == 5'h08) rd_data = length;
        else if (rd_addr == 5'h0c) rd_data = control;
        else if (rd_addr == 5'h10) rd_data = status;
    end
end

// ---------------- write side ----------------
always @(posedge clk) begin
    if (reset) begin
        src_addr  <= 32'b0;
        dest_addr <= 32'b0;
        length    <= 32'b0;
        control   <= 32'b0;
        status    <= 32'b0;
        overflow  <= 1'b0;
    end else begin
        if (wr_en) begin
            if      (wr_addr == 5'h00) src_addr  <= wr_data;
            else if (wr_addr == 5'h04) dest_addr <= wr_data;
            else if (wr_addr == 5'h08) length    <= wr_data;
            else if (wr_addr == 5'h0c) control   <= wr_data;
        end

        // sticky overflow: set wins over clear
        if (push && fifo_full)
            overflow <= 1'b1;
        else if (wr_en && wr_addr == 5'h0c && wr_data[1])
            overflow <= 1'b0;

        status <= {27'b0, overflow, fifo_empty, fifo_full, st_low};
    end
end

endmodule