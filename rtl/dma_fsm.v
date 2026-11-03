// dma_fsm.v
// start_pulse / control edge detector removed. IDLE -> FETCH when a
// descriptor is waiting in the FIFO (job_available = !fifo_empty).
module dma_fsm(
    input clk,
    input reset,
    input job_available,
    output reg [2:0] state,
    input status
);
reg [2:0] nextstate;
parameter idle=3'b000, fetch=3'b001, transfer=3'b010, done=3'b011, transfer2=3'b100;

always@(posedge clk)begin
    if(reset)
        state <= idle;
    else
        state <= nextstate;
end

always@(*)begin
    case(state)
        idle:      nextstate = job_available ? fetch : idle;
        fetch:     nextstate = transfer;
        transfer:  nextstate = transfer2;
        transfer2: nextstate = status ? done : transfer;
        done:      nextstate = idle;
        default:   nextstate = idle;
    endcase
end
endmodule