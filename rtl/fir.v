module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
    output  wire                     awready,
    output  wire                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  wire                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,    
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  wire                     ss_tready, 
    input   wire                     sm_tready, 
    output  wire                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  wire                     sm_tlast, 
    
    // bram for tap RAM
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,
    output  wire [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);

    // write your code here!
    // WE based on data width
    wire [3:0]                       we_sel;

    assign we_sel[0]   = (pDATA_WIDTH >= 1);
    assign we_sel[1]   = (pDATA_WIDTH >= 9);
    assign we_sel[0]   = (pDATA_WIDTH >= 17);
    assign we_sel[1]   = (pDATA_WIDTH >= 25);


    // AP Configuration Register
    wire                             ap_WE;
    wire                             ap_EN;
    wire [2:0]                       ap_Di;
    wire                             ap_Do;
    reg  [2:0]                       ap_reg;

    assign ap_Do = {pDATA_WIDTH{ap_EN}} & {pDATA_WIDTH-3{1'b0}, ap_reg};

    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (~axis_rst_n) begin
            ap_reg <= 3'b100;
        end else begin
            if (ap_reg[1]) begin
                if (ap_EN) begin
                    if (ap_WE) begin
                        ap_reg <= {ap_Di[2], 1'b0, ap_Di[0]};
                    end else begin
                        ap_reg <= {ap_reg[2], 1'b0, ap_reg[0]};
                end else begin
                    ap_reg <= ap_reg;
            end else begin
                if (ap_WE & ap_EN) begin
                    ap_reg <= ap_Di;
                end else begin
                    ap_reg <= ap_reg;
                end
            end
        end
    end


    // Length Configuration Register
    wire [3:0]                       len_WE;
    wire                             len_EN;
    wire [(pDATA_WIDTH-1):0]         len_Di;
    wire                             len_Do;
    reg  [(pDATA_WIDTH-1):0]         len_reg;

    assign len_Do = {pDATA_WIDTH{len_EN}} & len_reg;

    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (~axis_rst_n) begin
            len_reg <= 3'b000;
        end else begin
            if (len_EN) begin
	        if (len_WE[0]) begin
                    len_reg[7:0]   <= len_Di[7:0];
                end
                if (len_WE[1]) begin
                    len_reg[15:8]  <= len_Di[15:8];
                end
                if (len_WE[2]) begin
                    len_reg[23:16] <= len_Di[23:16];
                end
                if (len_WE[3]) begin
                    len_reg[31:24] <= len_Di[31:24];
                end
            end
        end
    end


    // AXI-Lite and AXI-Stream FSM
    parameter AXILITE_FSM_IDLE     = 2'b00;
    parameter AXILITE_FSM_ARREADY  = 2'b01;
    parameter AXILITE_FSM_AWREADY  = 2'b10;
    parameter AXISTREAM_FSM_IDLE   = 3'b000;
    parameter AXISTREAM_FSM_INIT   = 3'b001;
    parameter AXISTREAM_FSM_UPDATE = 3'b010;
    parameter AXISTREAM_FSM_MULT   = 3'b011;
    parameter AXISTREAM_FSM_SUM    = 3'b100;
    parameter AXISTREAM_FSM_OUT    = 3'b101;

    reg  [1:0]                       axilite_fsm;
    reg  [(pADDR_WIDTH-1):0]         axilite_A;
    wire                             axilite_ap;
    wire                             axilite_data;
    wire                             axilite_tap;
    wire [(pDATA_WIDTH-1):0]         axilite_Do;

    reg  [2:0]                       axistream_fsm;
    reg  [(pADDR_WIDTH-1):0]         axistream_A;
    reg  [(pDATA_WIDTH-1):0]         axistream_tap_Do;
    reg  [(pDATA_WIDTH-1):0]         axistream_data_Di;
    reg  [(pDATA_WIDTH-1):0]         axistream_data_Do;
    reg  [(pDATA_WIDTH-1):0]         axistream_mult;
    reg  [(pDATA_WIDTH-1):0]         axistream_sum;
    reg                              axistream_last;
    wire                             axistream_ap;
    wire                             axistream_tap;
    wire [(pADDR_WIDTH-1):0]         axistream_tap_A;
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (~axis_rst_n) begin
            axilite_fsm <= AXILITE_FSM_IDLE;
            axilite_A   <= pADDR_WIDTH'b0;
        end else begin
            case (axilite_fsm)
                AXILITE_FSM_IDLE: begin
                    if (arvalid) begin
                        axilite_fsm <= AXILITE_FSM_ARREADY;
                        axilite_A   <= araddr;
                    if (awvalid) begin
                        axilite_fsm <= AXILITE_FSM_AWREADY;
                        axilite_A   <= awaddr;
                    end else begin
                        axilite_fsm <= AXILITE_FSM_IDLE;
                        axilite_A   <= pADDR_WIDTH'b0;
                    end
                end
                AXILITE_FSM_ARREADY: begin
                    if (rready) begin
                        axilite_fsm <= AXILITE_FSM_IDLE;
                        axilite_Di  <= pDATA_WIDTH'b0;
                        axilite_A   <= pADDR_WIDTH'b0;
                    end else begin
                        axilite_fsm <= AXILITE_FSM_ARREADY;
                        axilite_A   <= A_reg;
                    end
                end
                AXILITE_FSM_AWREADY: begin
                    if (wvalid) begin
                        axilite_fsm <= AXILITE_FSM_IDLE;
                        axilite_A   <= pADDR_WIDTH'b0;
                    end else begin
                        axilite_fsm <= AXILITE_FSM_AWREADY;
                        axilite_A   <= A_reg;
                    end
                end
                default: begin
                    axilite_fsm <= AXILITE_FSM_IDLE;
                    axilite_A   <= pADDR_WIDTH'b0;
                end
            endcase
        end
    end

    // AXI-Stream
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (~axis_rst_n) begin
            axistream_fsm     <= AXISTREAM_FSM_IDLE;
            axistream_A       <= pADDR_WIDTH'h0;
            axistream_tap_Do  <= pDATA_WIDTH'h0;
            axistream_data_Di <= pDATA_WIDTH'h0;
            axistream_data_Do <= pDATA_WIDTH'h0;
            axistream_mult    <= pDATA_WIDTH'h0;
            axistream_sum     <= pDATA_WIDTH'h0;
            axistream_last    <= 1'b0;
        end else begin
            case (axistream_fsm)
                AXISTREAM_FSM_IDLE: begin
                    if (ap_reg[0] & ss_tvalid) begin
                        axistream_fsm     <= AXISTREAM_FSM_INIT;
                        axistream_A       <= pADDR_WIDTH'h0;
                        axistream_tap_Do  <= pDATA_WIDTH'h0;
                        axistream_data_Di <= pDATA_WIDTH'h0;
                        axistream_data_Do <= pDATA_WIDTH'h0;
                        axistream_mult    <= pDATA_WIDTH'h0;
                        axistream_sum     <= pDATA_WIDTH'h0;
                        axistream_last    <= ss_tlast;
                    end else begin
                        axistream_fsm     <= AXISTREAM_FSM_IDLE;
                        axistream_A       <= pADDR_WIDTH'h0;
                        axistream_tap_Do  <= pDATA_WIDTH'h0;
                        axistream_data_Di <= pDATA_WIDTH'h0;
                        axistream_data_Do <= pDATA_WIDTH'h0;
                        axistream_mult    <= pDATA_WIDTH'h0;
                        axistream_sum     <= pDATA_WIDTH'h0;
                        axistream_last    <= 1'b0;
                    end
                end
                AXISTREAM_FSM_INIT: begin
                    if (axistream_A != (Tape_Num - 2)) begin
                        axistream_fsm     <= AXISTREAM_FSM_INIT;
                        axistream_A       <= axistream_A + pADDR_WIDTH'b1;
                        axistream_tap_Do  <= pDATA_WIDTH'h0;
                        axistream_data_Di <= pDATA_WIDTH'h0;
                        axistream_data_Do <= pDATA_WIDTH'h0;
                        axistream_mult    <= pDATA_WIDTH'h0;
                        axistream_sum     <= pDATA_WIDTH'h0;
                        axistream_last    <= axistream_last;
                    end else begin
                        axistream_fsm     <= AXISTREAM_FSM_UPDATE;
                        axistream_A       <= pADDR_WIDTH'h0;
                        axistream_tap_Do  <= pDATA_WIDTH'h0;
                        axistream_data_Di <= pDATA_WIDTH'h0;
                        axistream_data_Do <= pDATA_WIDTH'h0;
                        axistream_mult    <= pDATA_WIDTH'h0;
                        axistream_sum     <= pDATA_WIDTH'h0;
                        axistream_last    <= axistream_last;
                    end
                end
                AXISTREAM_FSM_UPDATE: begin
                    if (axistream_A == 0) begin
                        axistream_fsm     <= AXISTREAM_FSM_MULT;
                        axistream_A       <= pADDR_WIDTH'h0;
                        axistream_tap_Do  <= tap_Do;
                        axistream_data_Di <= pDATA_WIDTH'h0;
                        axistream_data_Do <= ss_tdata;
                        axistream_mult    <= pDATA_WIDTH'h0;
                        axistream_sum     <= pDATA_WIDTH'h0;
                        axistream_last    <= axistream_last;
                    end else begin
                        axistream_fsm     <= AXISTREAM_FSM_MULT;
                        axistream_A       <= axistream_A;
                        axistream_tap_Do  <= tap_Do;
                        axistream_data_Di <= axistream_data_Do;
                        axistream_data_Do <= data_Do;
                        axistream_mult    <= pDATA_WIDTH'h0;
                        axistream_sum     <= axistream_sum;
                        axistream_last    <= axistream_last;
                    end
                end
                AXISTREAM_FSM_MULT: begin
                    axistream_fsm     <= AXISTREAM_FSM_SUM;
                    axistream_A       <= axistream_A + pADDR_WIDTH'b1;
                    axistream_tap_Do  <= axistream_tap_Do;
                    axistream_data_Di <= pDATA_WIDTH'h0;
                    axistream_data_Do <= axistream_data_Do;
                    axistream_mult    <= axistream_tap_Do * axistream_data_Do;
                    axistream_sum     <= axistream_sum;
                    axistream_last    <= axistream_last;
                end
                AXISTREAM_FSM_SUM: begin
                    if (axistream_A == Tape_Num) begin
                        axistream_fsm     <= AXISTREAM_FSM_OUT;
                        axistream_A       <= pADDR_WIDTH'h0;
                        axistream_tap_Do  <= pDATA_WIDTH'h0;
                        axistream_data_Di <= pDATA_WIDTH'h0;
                        axistream_data_Do <= pDATA_WIDTH'h0;
                        axistream_mult    <= pDATA_WIDTH'h0;
                        axistream_sum     <= axistream_sum + axistream_mult;
                        axistream_last    <= axistream_last;
                    end else begin
                        axistream_fsm     <= AXISTREAM_FSM_UPDATE;
                        axistream_A       <= axistream_A;
                        axistream_tap_Do  <= axistream_tap_Do;
                        axistream_data_Di <= pDATA_WIDTH'h0;
                        axistream_data_Do <= axistream_data_Do;
                        axistream_mult    <= pDATA_WIDTH'h0;
                        axistream_sum     <= axistream_sum + axistream_mult;
                        axistream_last    <= axistream_last;
                end
                AXISTREAM_FSM_OUT: begin
                    if (axistream_last) begin
                        if (sm_tready) begin
                            axistream_fsm     <= AXISTREAM_FSM_IDLE;
                            axistream_A       <= pADDR_WIDTH'h0;
                            axistream_tap_Do  <= pDATA_WIDTH'h0;
                            axistream_data_Di <= pDATA_WIDTH'h0;
                            axistream_data_Do <= pDATA_WIDTH'h0;
                            axistream_mult    <= pDATA_WIDTH'h0;
                            axistream_sum     <= pDATA_WIDTH'h0;
                            axistream_last    <= 1'b0;
                        end else begin begin
                            axistream_fsm     <= AXISTREAM_FSM_OUT;
                            axistream_A       <= pADDR_WIDTH'h0;
                            axistream_tap_Do  <= pDATA_WIDTH'h0;
                            axistream_data_Di <= pDATA_WIDTH'h0;
                            axistream_data_Do <= pDATA_WIDTH'h0;
                            axistream_mult    <= pDATA_WIDTH'h0;
                            axistream_sum     <= axistream_sum;
                            axistream_last    <= axistream_last;
                    end else begin
                        if (ss_tvalid & sm_tready) begin
                            axistream_fsm     <= AXISTREAM_FSM_UPDATE;
                            axistream_A       <= pADDR_WIDTH'h0;
                            axistream_tap_Do  <= pDATA_WIDTH'h0;
                            axistream_data_Di <= pDATA_WIDTH'h0;
                            axistream_data_Do <= pDATA_WIDTH'h0;
                            axistream_mult    <= pDATA_WIDTH'h0;
                            axistream_sum     <= pDATA_WIDTH'h0;
                            axistream_last    <= ss_tlast;
                        end else begin begin
                            axistream_fsm     <= AXISTREAM_FSM_OUT;
                            axistream_A       <= pADDR_WIDTH'h0;
                            axistream_tap_Do  <= pDATA_WIDTH'h0;
                            axistream_data_Di <= pDATA_WIDTH'h0;
                            axistream_data_Do <= pDATA_WIDTH'h0;
                            axistream_mult    <= pDATA_WIDTH'h0;
                            axistream_sum     <= axistream_sum;
                            axistream_last    <= axistream_last;
                        end
                    end
                end
                default: begin
                    axistream_fsm     <= AXISTREAM_FSM_IDLE;
                    axistream_A       <= pADDR_WIDTH'h0;
                    axistream_tap_Do  <= pDATA_WIDTH'h0;
                    axistream_data_Di <= pDATA_WIDTH'h0;
                    axistream_data_Do <= pDATA_WIDTH'h0;
                    axistream_mult    <= pDATA_WIDTH'h0;
                    axistream_sum     <= pDATA_WIDTH'h0;
                    axistream_last    <= 1'b0;
               end
            endcase
        end
    end

    assign axilite_ap      = (axilite_fsm != AXILITE_FSM_IDLE) & (axilite_A == pADDR_WIDTH'h0);
    assign axilite_len     = (axilite_fsm != AXILITE_FSM_IDLE) & (axilite_A >= pADDR_WIDTH'h10) & (axilite_A <= pADDR_WIDTH'h14);
    assign axilite_tap     = (axilite_fsm != AXILITE_FSM_IDLE) & (axilite_A >= pADDR_WIDTH'h20) & (axilite_A <= pADDR_WIDTH'hFF);
    assign axilite_Do      = {pDATA_WIDTH{axilite_ap  & ~axistream_ap }} & ap_Do               |
                             {pDATA_WIDTH{axilite_ap  &  axistream_ap }} & 3'b000              |
                             {pDATA_WIDTH{axilite_len                 }} & len_Do              |
                             {pDATA_WIDTH{axilite_tag & ~axistream_tap}} & tap_Do              |
                             {pDATA_WIDTH{axilite_tag &  axistream_tap}} & {pDATA_WIDTH{1'b1}};

    assign axistream_ap    = (axistream_fsm == AXISTREAM_FSM_IDLE) & ap_reg[0] & ss_tvalid | (axistream_fsm == AXISTREAM_FSM_OUT) & axistream_last & sm_tready;
    assign axistream_tap   = (axistream_fsm == AXISTREAM_FSM_IDLE) & ap_reg[0] & ss_tvalid | (axistream_fsm != AXISTREAM_FSM_IDLE);
    assign axistream_tap_A = (axistream_fsm == AXISTREAM_FSM_IDLE | axistream_fsm == AXISTREAM_FSM_INIT) ? pADDR_WIDTH'h0 : (axistream_A << 2);

    assign awready         = (axilite_fsm == AXILITE_FSM_IDLE   ) & awvalid;
    assign wready          = (axilite_fsm == AXILITE_FSM_AWREADY);
    assign arready         = (axilite_fsm == AXILITE_FSM_IDLE   ) & arvalid;
    assign rvalid          = (axilite_fsm == AXILITE_FSM_ARREADY) & rready;
    assign rdata           = {pDATA_WIDTH{(axilite_fsm == AXILITE_FSM_ARREADY)}} & axilite_Do;

    assign ap_WE           = axilite_ap & (wready & wvalid) | axistream_ap;
    assign ap_EN           = axilite_ap & (rvalid | wready & wvalid) | axistream_ap;
    assign ap_Di           = {3{axilite_ap & ~axistream_ap}} & {(ap_reg[2] & ~wdata[0]), 1'b0, (ap_reg[2] & wdata[0])} | 
                             {3{              axistream_ap}} & {2{sm_tlast}, 1'b0};

    assign len_WE          = axilite_len & (wready & wvalid);
    assign len_EN          = axilite_len & (rvalid | wready & wvalid);
    assign len_Di          = wdata;

    assign tap_WE          = axilite_tap & (wready & wvalid) & ~axistream_tap;
    assign tap_EN          = axilite_tap & (rvalid | wready & wvalid) | axistream_tap;
    assign tap_Di          = wdata;
    assign tap_A           = {3{axilite_tap & ~axistream_tap}} & (axilite_A - pADDR_WIDTH'20) |
                             {3{               axistream_tap}} & axistream_tap_A;

    assign data_WE         = (axistream_fsm == AXISTREAM_FSM_UPDATE) & (axistream_A != pADDR_WIDTH'h0);
    assign data_EN         = (axistream_fsm == AXISTREAM_FSM_SUM   ) & (axistream_A == Tape_Num      ) | (axistream_fsm == AXISTREAM_FSM_UPDATE) & (axistream_A != pADDR_WIDTH'h0);
    assign data_Di         = axistream_data_Di;
    assign data_A          = {pADDR_WIDTH{(axistream_A != pADDR_WIDTH'h0)}} & ((axistream_A - pADDR_WIDTH'b1) << 2);

    assign ss_tready       = (axistream_fsm == AXISTREAM_FSM_UPDATE) & (axistream_A == pADDR_WIDTH'h0);
    assign sm_tvalid       = (axistream_fsm == AXISTREAM_FSM_OUT);
    assign sm_tdata        = axistream_sum;
    assign sm_tlast        = (axistream_fsm == AXISTREAM_FSM_OUT) & axistream_last;

endmodule