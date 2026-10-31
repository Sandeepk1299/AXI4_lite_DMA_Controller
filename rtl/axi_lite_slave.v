// axi_lite_slave.v  (UNCHANGED)
// AXI4-Lite slave bridge. Converts the AXI4-Lite write/read channel
// handshaking into the simple synchronous register interface expected
// by register_file (wr_en/wr_addr/wr_data, rd_en/rd_addr/rd_data).
//
// Address map (byte addresses on AXI bus, matching register_file's decode):
//   0x00 : src_addr
//   0x04 : dest_addr
//   0x08 : length
//   0x0C : control
//   0x10 : status  (read-only)

module axi_lite_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input                        clk,
    input                        reset,

    input      [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input                        s_axi_awvalid,
    output reg                   s_axi_awready,

    input      [DATA_WIDTH-1:0]  s_axi_wdata,
    input      [(DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input                        s_axi_wvalid,
    output reg                   s_axi_wready,

    output reg [1:0]             s_axi_bresp,
    output reg                   s_axi_bvalid,
    input                        s_axi_bready,

    input      [ADDR_WIDTH-1:0]  s_axi_araddr,
    input                        s_axi_arvalid,
    output reg                   s_axi_arready,

    output reg [DATA_WIDTH-1:0]  s_axi_rdata,
    output reg [1:0]             s_axi_rresp,
    output reg                   s_axi_rvalid,
    input                        s_axi_rready,

    output reg                   wr_en,
    output reg [4:0]             wr_addr,
    output reg [31:0]            wr_data,
    output reg                   rd_en,
    output reg [4:0]             rd_addr,
    input      [31:0]            rd_data
);

localparam RESP_OKAY = 2'b00;

reg [ADDR_WIDTH-1:0] awaddr_latch;
reg [DATA_WIDTH-1:0] wdata_latch;
reg                  aw_done;
reg                  w_done;

// ---------------- Write channel FSM ----------------
always @(posedge clk) begin
    if (reset) begin
        s_axi_awready <= 1'b0;
        s_axi_wready  <= 1'b0;
        s_axi_bvalid  <= 1'b0;
        s_axi_bresp   <= RESP_OKAY;
        aw_done       <= 1'b0;
        w_done        <= 1'b0;
        awaddr_latch  <= {ADDR_WIDTH{1'b0}};
        wdata_latch   <= {DATA_WIDTH{1'b0}};
        wr_en         <= 1'b0;
        wr_addr       <= 5'b0;
        wr_data       <= 32'b0;
    end else begin
        wr_en <= 1'b0; // default: pulse for one cycle only

        if (!aw_done && s_axi_awvalid && !s_axi_bvalid) begin
            s_axi_awready <= 1'b1;
            awaddr_latch  <= s_axi_awaddr;
            aw_done       <= 1'b1;
        end else begin
            s_axi_awready <= 1'b0;
        end

        if (!w_done && s_axi_wvalid && !s_axi_bvalid) begin
            s_axi_wready <= 1'b1;
            wdata_latch  <= s_axi_wdata;
            w_done       <= 1'b1;
        end else begin
            s_axi_wready <= 1'b0;
        end

        if (aw_done && w_done && !s_axi_bvalid) begin
            wr_en        <= 1'b1;
            wr_addr      <= awaddr_latch[4:0];
            wr_data      <= wdata_latch;
            s_axi_bvalid <= 1'b1;
            s_axi_bresp  <= RESP_OKAY;
            aw_done      <= 1'b0;
            w_done       <= 1'b0;
        end

        if (s_axi_bvalid && s_axi_bready) begin
            s_axi_bvalid <= 1'b0;
        end
    end
end

// ---------------- Read channel FSM ----------------
reg ar_done;

always @(posedge clk) begin
    if (reset) begin
        s_axi_arready <= 1'b0;
        s_axi_rvalid  <= 1'b0;
        s_axi_rresp   <= RESP_OKAY;
        s_axi_rdata   <= 32'b0;
        ar_done       <= 1'b0;
        rd_en         <= 1'b0;
        rd_addr       <= 5'b0;
    end else begin
        rd_en <= 1'b0;

        if (!ar_done && s_axi_arvalid && !s_axi_rvalid) begin
            s_axi_arready <= 1'b1;
            rd_addr       <= s_axi_araddr[4:0];
            rd_en         <= 1'b1;
            ar_done       <= 1'b1;
        end else begin
            s_axi_arready <= 1'b0;
        end

        if (ar_done && !s_axi_rvalid) begin
            s_axi_rdata  <= rd_data;
            s_axi_rresp  <= RESP_OKAY;
            s_axi_rvalid <= 1'b1;
            ar_done      <= 1'b0;
        end

        if (s_axi_rvalid && s_axi_rready) begin
            s_axi_rvalid <= 1'b0;
        end
    end
end

endmodule
