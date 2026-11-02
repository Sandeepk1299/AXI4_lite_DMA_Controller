// desc_fifo.v
// Descriptor FIFO: holds queued DMA jobs {src, dest, len}.
// CPU pushes a job via register_file; dma_fsm/controller pops it in FETCH.
module desc_fifo #(
    parameter DEPTH_LOG2 = 2          // 2 -> 4 entries
)(
    input         clk,
    input         reset,

    input         push,
    input  [31:0] in_src,
    input  [31:0] in_dest,
    input  [31:0] in_len,

    input         pop,
    output [31:0] out_src,
    output [31:0] out_dest,
    output [31:0] out_len,

    output        full,
    output        empty
);

localparam DEPTH = 1 << DEPTH_LOG2;

reg [95:0]          mem [0:DEPTH-1];
reg [DEPTH_LOG2:0]  wptr, rptr;       // extra MSB = lap bit, separates full from empty

assign empty = (wptr == rptr);
assign full  = (wptr[DEPTH_LOG2-1:0] == rptr[DEPTH_LOG2-1:0]) &&
               (wptr[DEPTH_LOG2]     != rptr[DEPTH_LOG2]);

wire do_push = push && !full;
wire do_pop  = pop  && !empty;

always @(posedge clk) begin
    if (reset) begin
        wptr <= 0;
        rptr <= 0;
    end else begin
        if (do_push) begin
            mem[wptr[DEPTH_LOG2-1:0]] <= {in_src, in_dest, in_len};
            wptr <= wptr + 1'b1;
        end
        if (do_pop)
            rptr <= rptr + 1'b1;
    end
end

assign {out_src, out_dest, out_len} = mem[rptr[DEPTH_LOG2-1:0]];

endmodule