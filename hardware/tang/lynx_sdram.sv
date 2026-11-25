// Original single-word x32 SDR SDRAM controller for GW2AR-18C's packaged
// 2M x32 memory: four banks, 2048 rows, 256 columns. All transfers auto-precharge.
// At 64 MHz: tRCD/tRP/tWR >=31.25ns and tRFC >=78.125ns. Automatic refresh
// takes priority at each idle boundary, independently of client traffic.
module lynx_sdram #(parameter integer CLOCK_HZ=64000000, INIT_CYCLES=CLOCK_HZ/5000) (
    input wire clk, reset,
    input wire request,
    output wire request_ready,
    input wire write,
    input wire [22:0] address,
    input wire [31:0] write_data,
    input wire [3:0] write_mask,
    output reg response,
    output reg [31:0] read_data,
    output reg initialized,
    output reg [10:0] sdram_a,
    output reg [1:0] sdram_ba,
    output reg [3:0] sdram_dqm,
    output wire sdram_cke, sdram_cs_n,
    output reg sdram_ras_n, sdram_cas_n, sdram_we_n,
    input wire [31:0] dq_in,
    output reg [31:0] dq_out,
    output reg dq_oe
);
    localparam [2:0] NOP=7, PRE=2, REF=1, MODE=0, ACT=3, RD=5, WR=4;
    localparam WAIT_POWER=0, INIT_PRE=1, INIT_REF1=2, INIT_REF2=3, INIT_MODE=4,
               IDLE=5, ACCESS=6, RECOVER=7, REFRESH=8;
    reg [3:0] state=WAIT_POWER;
    reg [15:0] delay_count=0;
    reg [9:0] refresh_age=0;
    reg [3:0] cycle=0;
    reg saved_write;
    reg [7:0] column;
    reg [31:0] saved_data;
    reg [3:0] saved_mask;
    // Requests address aligned 32-bit words; DQM selects the written byte lanes.
    wire _unused_byte_offset=^address[1:0];
    assign sdram_cke=1;
    assign sdram_cs_n=0;
    assign request_ready=initialized && state==IDLE && refresh_age<500;
    always @(posedge clk) begin
        response<=0;
        {sdram_ras_n,sdram_cas_n,sdram_we_n}<=NOP;
        dq_oe<=0;
        if(reset) begin
            state<=WAIT_POWER; delay_count<=16'(INIT_CYCLES-1);
            initialized<=0; refresh_age<=0; sdram_dqm<=15;
            sdram_a<=0; sdram_ba<=0;
        end else begin
            if(initialized && refresh_age<1023) refresh_age<=refresh_age+1;
            if(delay_count!=0) delay_count<=delay_count-1;
            case(state)
                WAIT_POWER: if(delay_count==0) begin
                    {sdram_ras_n,sdram_cas_n,sdram_we_n}<=PRE;
                    sdram_a<=11'h400; delay_count<=1; state<=INIT_PRE;
                end
                INIT_PRE: if(delay_count==0) begin
                    {sdram_ras_n,sdram_cas_n,sdram_we_n}<=REF;
                    delay_count<=4; state<=INIT_REF1;
                end
                INIT_REF1: if(delay_count==0) begin
                    {sdram_ras_n,sdram_cas_n,sdram_we_n}<=REF;
                    delay_count<=4; state<=INIT_REF2;
                end
                INIT_REF2: if(delay_count==0) begin
                    {sdram_ras_n,sdram_cas_n,sdram_we_n}<=MODE;
                    sdram_a<=11'h020; sdram_ba<=0;
                    delay_count<=1; state<=INIT_MODE;
                end
                INIT_MODE: if(delay_count==0) begin
                    initialized<=1; refresh_age<=0; state<=IDLE;
                end
                IDLE: begin
                    sdram_dqm<=0;
                    if(refresh_age>=500) begin
                        {sdram_ras_n,sdram_cas_n,sdram_we_n}<=REF;
                        delay_count<=4; refresh_age<=0; state<=REFRESH;
                    end else if(request) begin
                        {sdram_ras_n,sdram_cas_n,sdram_we_n}<=ACT;
                        sdram_ba<=address[22:21]; sdram_a<=address[20:10];
                        column<=address[9:2]; saved_write<=write;
                        saved_data<=write_data; saved_mask<=write_mask;
                        cycle<=1; state<=ACCESS;
                    end
                end
                ACCESS: begin
                    cycle<=cycle+1;
                    if(cycle==2) begin
                        {sdram_ras_n,sdram_cas_n,sdram_we_n}<=saved_write ? WR:RD;
                        sdram_a<={1'b1,2'b00,column};
                        sdram_dqm<=saved_write ? ~saved_mask:4'b0;
                        dq_out<=saved_data; dq_oe<=saved_write;
                    end
                    if(!saved_write && cycle==5) begin read_data<=dq_in; response<=1; end
                    if(cycle==6) begin
                        if(saved_write) response<=1;
                        state<=RECOVER;
                    end
                end
                RECOVER: state<=IDLE;
                REFRESH: if(delay_count==0) state<=IDLE;
                default: state<=WAIT_POWER;
            endcase
        end
    end
endmodule
