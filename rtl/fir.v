(* use_dsp = "no" *)
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
    assign we_sel[2]   = (pDATA_WIDTH >= 17);
    assign we_sel[3]   = (pDATA_WIDTH >= 25);


    // AP Configuration Register
    wire                             ap_WE;
    wire                             ap_EN;
    wire [2:0]                       ap_Di;
    wire [(pDATA_WIDTH-1):0]         ap_Do;
    reg  [2:0]                       ap_reg;

    assign ap_Do = {pDATA_WIDTH{ap_EN}} & {{pDATA_WIDTH-3{1'b0}}, ap_reg};

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
                    end
                end else begin
                    ap_reg <= ap_reg;
                end
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
    wire [(pDATA_WIDTH-1):0]         len_Do;
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


    // Tap Number Configuration Register
    wire [3:0]                       num_WE;
    wire                             num_EN;
    wire [(pDATA_WIDTH-1):0]         num_Di;
    wire [(pDATA_WIDTH-1):0]         num_Do;
    reg  [(pDATA_WIDTH-1):0]         num_reg;

    assign num_Do = {pDATA_WIDTH{num_EN}} & num_reg;

    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (~axis_rst_n) begin
            num_reg <= 3'b000;
        end else begin
            if (num_EN) begin
	            if (num_WE[0]) begin
                    num_reg[7:0]   <= num_Di[7:0];
                end
                if (num_WE[1]) begin
                    num_reg[15:8]  <= num_Di[15:8];
                end
                if (num_WE[2]) begin
                    num_reg[23:16] <= num_Di[23:16];
                end
                if (num_WE[3]) begin
                    num_reg[31:24] <= num_Di[31:24];
                end
            end
        end
    end


    // AXI-Lite and AXI-Stream FSM
    parameter AXILITE_FSM_RESET    = 3'b000;
    parameter AXILITE_FSM_IDLE     = 3'b001;
    parameter AXILITE_FSM_AWREADY  = 3'b010;
    parameter AXILITE_FSM_WREADY   = 3'b011;
    parameter AXILITE_FSM_ARREADY  = 3'b100;
    parameter AXILITE_FSM_RREADY   = 3'b101;
    parameter AXISTREAM_FSM_RESET  = 3'b000;
    parameter AXISTREAM_FSM_IDLE   = 3'b001;
    parameter AXISTREAM_FSM_INIT   = 3'b010;
    parameter AXISTREAM_FSM_UPDATE = 3'b011;
    parameter AXISTREAM_FSM_MULT   = 3'b100;
    parameter AXISTREAM_FSM_SUM    = 3'b101;
    parameter AXISTREAM_FSM_OUT    = 3'b110;

    reg  [2:0]                       axilite_fsm;
    reg  [(pADDR_WIDTH-1):0]         axilite_A_pre;
    reg  [(pDATA_WIDTH-1):0]         axilite_Di_pre;
    reg                              axilite_rr;
    wire                             axilite_active;
    wire                             axilite_ap;
    wire                             axilite_len;
    wire                             axilite_num;
    wire                             axilite_tap;
    wire [(pDATA_WIDTH-1):0]         axilite_Do;
    wire [(pADDR_WIDTH-1):0]         axilite_A;
    wire [(pDATA_WIDTH-1):0]         axilite_Di;

    reg  [2:0]                       axistream_fsm;
    reg  [(pADDR_WIDTH-1):0]         axistream_A;
    reg  [(pDATA_WIDTH-1):0]         axistream_data_Di;
    reg  [(pDATA_WIDTH-1):0]         axistream_data_Do;
    reg  [(pDATA_WIDTH-1):0]         axistream_mult;
    reg  [(pDATA_WIDTH-1):0]         axistream_sum;
    reg                              axistream_sent;
    reg                              axistream_last;
    wire                             axistream_active;
    wire                             axistream_ap;
    wire                             axistream_tap;
    wire [(pADDR_WIDTH-1):0]         axistream_tap_A;


    // AXI-Lite
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (~axis_rst_n) begin
            axilite_fsm    <= AXILITE_FSM_RESET;
            axilite_A_pre  <= {pADDR_WIDTH{1'b0}};
            axilite_Di_pre <= {pDATA_WIDTH{1'b0}};
            axilite_rr     <= 1'b0;
        end else begin
            case (axilite_fsm)
                AXILITE_FSM_RESET: begin
                    axilite_fsm    <= AXILITE_FSM_IDLE;
                    axilite_A_pre  <= {pADDR_WIDTH{1'b0}};
                    axilite_Di_pre <= {pDATA_WIDTH{1'b0}};
                    axilite_rr     <= 1'b0;
                end
                AXILITE_FSM_IDLE: begin
                    if (awvalid & ~(arvalid & axilite_rr)) begin
                        axilite_fsm    <= AXILITE_FSM_AWREADY;
                        axilite_A_pre  <= awaddr;
                        axilite_Di_pre <= {pDATA_WIDTH{1'b0}};
                        axilite_rr     <= 1'b1;
                    end else if (wvalid & ~(arvalid & axilite_rr)) begin
                        axilite_fsm    <= AXILITE_FSM_WREADY;
                        axilite_A_pre  <= {pADDR_WIDTH{1'b0}};
                        axilite_Di_pre <= wdata;
                        axilite_rr     <= 1'b1;
                    end else if (arvalid) begin
                        axilite_fsm    <= AXILITE_FSM_ARREADY;
                        axilite_A_pre  <= araddr;
                        axilite_Di_pre <= {pDATA_WIDTH{1'b0}};
                        axilite_rr     <= 1'b0;
                    end else begin
                        axilite_fsm    <= AXILITE_FSM_IDLE;
                        axilite_A_pre  <= {pADDR_WIDTH{1'b0}};
                        axilite_Di_pre <= {pDATA_WIDTH{1'b0}};
                        axilite_rr     <= axilite_rr;
                    end
                end
                AXILITE_FSM_AWREADY: begin
                    if (wvalid) begin
                        axilite_fsm    <= AXILITE_FSM_IDLE;
                        axilite_A_pre  <= {pADDR_WIDTH{1'b0}};
                        axilite_Di_pre <= {pDATA_WIDTH{1'b0}};
                        axilite_rr     <= axilite_rr;
                    end else begin
                        axilite_fsm    <= AXILITE_FSM_AWREADY;
                        axilite_A_pre  <= axilite_A;
                        axilite_Di_pre <= {pDATA_WIDTH{1'b0}};
                        axilite_rr     <= axilite_rr;
                    end
                end
                AXILITE_FSM_WREADY: begin
                    if (awvalid) begin
                        axilite_fsm    <= AXILITE_FSM_IDLE;
                        axilite_A_pre  <= {pADDR_WIDTH{1'b0}};
                        axilite_Di_pre <= {pDATA_WIDTH{1'b0}};
                        axilite_rr     <= axilite_rr;
                    end else begin
                        axilite_fsm    <= AXILITE_FSM_WREADY;
                        axilite_A_pre  <= {pADDR_WIDTH{1'b0}};
                        axilite_Di_pre <= axilite_Di;
                        axilite_rr     <= axilite_rr;
                    end
                end                    
                AXILITE_FSM_ARREADY: begin
                    if (rready) begin
                        axilite_fsm    <= AXILITE_FSM_RREADY;
                        axilite_A_pre  <= axilite_A;
                        axilite_Di_pre <= {pDATA_WIDTH{1'b0}};
                        axilite_rr     <= axilite_rr;
                    end else begin
                        axilite_fsm    <= AXILITE_FSM_ARREADY;
                        axilite_A_pre  <= axilite_A;
                        axilite_Di_pre <= {pDATA_WIDTH{1'b0}};
                        axilite_rr     <= axilite_rr;
                    end
                end
                AXILITE_FSM_RREADY: begin
                    axilite_fsm    <= AXILITE_FSM_IDLE;
                    axilite_A_pre  <= {pADDR_WIDTH{1'b0}};
                    axilite_Di_pre <= {pDATA_WIDTH{1'b0}};
                    axilite_rr     <= axilite_rr;
                end
                default: begin
                    axilite_fsm    <= AXILITE_FSM_IDLE;
                    axilite_A_pre  <= {pADDR_WIDTH{1'b0}};
                    axilite_Di_pre <= {pDATA_WIDTH{1'b0}};
                    axilite_rr     <= 1'b0;
                end
            endcase
        end
    end

    // AXI-Stream
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (~axis_rst_n) begin
            axistream_fsm     <= AXISTREAM_FSM_RESET;
            axistream_A       <= {pADDR_WIDTH{1'b0}};
            axistream_data_Di <= {pDATA_WIDTH{1'b0}};
            axistream_data_Do <= {pDATA_WIDTH{1'b0}};
            axistream_mult    <= {pDATA_WIDTH{1'b0}};
            axistream_sum     <= {pDATA_WIDTH{1'b0}};
            axistream_sent    <= 1'b0;
            axistream_last    <= 1'b0;
        end else begin
            case (axistream_fsm)
                AXISTREAM_FSM_RESET: begin
                    axistream_fsm     <= AXISTREAM_FSM_IDLE;
                    axistream_A       <= {pADDR_WIDTH{1'b0}};
                    axistream_data_Di <= {pDATA_WIDTH{1'b0}};
                    axistream_data_Do <= {pDATA_WIDTH{1'b0}};
                    axistream_mult    <= {pDATA_WIDTH{1'b0}};
                    axistream_sum     <= {pDATA_WIDTH{1'b0}};
                    axistream_sent    <= 1'b0;    
                    axistream_last    <= 1'b0;
                end
                AXISTREAM_FSM_IDLE: begin
                    if (~axilite_ap & ap_reg[0] & ss_tvalid) begin
                        axistream_fsm     <= AXISTREAM_FSM_INIT;
                        axistream_A       <= Tape_Num - 1;
                        axistream_data_Di <= {pDATA_WIDTH{1'b0}};
                        axistream_data_Do <= {pDATA_WIDTH{1'b0}};
                        axistream_mult    <= {pDATA_WIDTH{1'b0}};
                        axistream_sum     <= {pDATA_WIDTH{1'b0}};
                        axistream_sent    <= 1'b0;
                        axistream_last    <= ss_tlast;
                    end else begin
                        axistream_fsm     <= AXISTREAM_FSM_IDLE;
                        axistream_A       <= {pADDR_WIDTH{1'b0}};
                        axistream_data_Di <= {pDATA_WIDTH{1'b0}};
                        axistream_data_Do <= {pDATA_WIDTH{1'b0}};
                        axistream_mult    <= {pDATA_WIDTH{1'b0}};
                        axistream_sum     <= {pDATA_WIDTH{1'b0}};
                        axistream_sent    <= 1'b0;
                        axistream_last    <= 1'b0;
                    end
                end
                AXISTREAM_FSM_INIT: begin
                    if (axistream_A != {pADDR_WIDTH{1'b0}}) begin
                        axistream_fsm     <= AXISTREAM_FSM_INIT;
                        axistream_A       <= axistream_A - {{pADDR_WIDTH-1{1'b0}}, 1'b1};
                        axistream_data_Di <= {pDATA_WIDTH{1'b0}};
                        axistream_data_Do <= {pDATA_WIDTH{1'b0}};
                        axistream_mult    <= {pDATA_WIDTH{1'b0}};
                        axistream_sum     <= {pDATA_WIDTH{1'b0}};
                        axistream_sent    <= 1'b0;
                        axistream_last    <= axistream_last;
                    end else begin
                        axistream_fsm     <= AXISTREAM_FSM_UPDATE;
                        axistream_A       <= {pADDR_WIDTH{1'b0}};
                        axistream_data_Di <= {pDATA_WIDTH{1'b0}};
                        axistream_data_Do <= {pDATA_WIDTH{1'b0}};
                        axistream_mult    <= {pDATA_WIDTH{1'b0}};
                        axistream_sum     <= {pDATA_WIDTH{1'b0}};
                        axistream_sent    <= 1'b0;
                        axistream_last    <= axistream_last;
                    end
                end
                AXISTREAM_FSM_UPDATE: begin
                    if (axistream_A == {pADDR_WIDTH{1'b0}}) begin
                        axistream_fsm     <= AXISTREAM_FSM_MULT;
                        axistream_A       <= {pADDR_WIDTH{1'b0}};
                        axistream_data_Di <= {pDATA_WIDTH{1'b0}};
                        axistream_data_Do <= ss_tdata;
                        axistream_mult    <= tap_Do;
                        axistream_sum     <= {pDATA_WIDTH{1'b0}};
                        axistream_sent    <= 1'b0;
                        axistream_last    <= axistream_last;
                    end else begin
                        axistream_fsm     <= AXISTREAM_FSM_MULT;
                        axistream_A       <= axistream_A;
                        axistream_data_Di <= axistream_data_Do;
                        axistream_data_Do <= data_Do;
                        axistream_mult    <= tap_Do;
                        axistream_sum     <= axistream_sum;
                        axistream_sent    <= 1'b0;
                        axistream_last    <= axistream_last;
                    end
                end
                AXISTREAM_FSM_MULT: begin
                    axistream_fsm     <= AXISTREAM_FSM_SUM;
                    axistream_A       <= axistream_A + {{pADDR_WIDTH-1{1'b0}}, 1'b1};
                    axistream_data_Di <= {pDATA_WIDTH{1'b0}};
                    axistream_data_Do <= axistream_data_Do;
                    axistream_mult    <= axistream_mult * axistream_data_Do;
                    axistream_sum     <= axistream_sum;
                    axistream_sent    <= 1'b0;
                    axistream_last    <= axistream_last;
                end
                AXISTREAM_FSM_SUM: begin
                    if (axistream_A == Tape_Num) begin
                        axistream_fsm     <= AXISTREAM_FSM_OUT;
                        axistream_A       <= {pADDR_WIDTH{1'b0}};
                        axistream_data_Di <= {pDATA_WIDTH{1'b0}};
                        axistream_data_Do <= {pDATA_WIDTH{1'b0}};
                        axistream_mult    <= {pDATA_WIDTH{1'b0}};
                        axistream_sum     <= axistream_sum + axistream_mult;
                        axistream_sent    <= 1'b0;
                        axistream_last    <= axistream_last;
                    end else begin
                        axistream_fsm     <= AXISTREAM_FSM_UPDATE;
                        axistream_A       <= axistream_A;
                        axistream_data_Di <= {pDATA_WIDTH{1'b0}};
                        axistream_data_Do <= axistream_data_Do;
                        axistream_mult    <= {pDATA_WIDTH{1'b0}};
                        axistream_sum     <= axistream_sum + axistream_mult;
                        axistream_sent    <= 1'b0;
                        axistream_last    <= axistream_last;
                    end
                end
                AXISTREAM_FSM_OUT: begin
                    if (axistream_last) begin
                        if (sm_tready) begin
                            axistream_fsm     <= AXISTREAM_FSM_IDLE;
                            axistream_A       <= {pADDR_WIDTH{1'b0}};
                            axistream_data_Di <= {pDATA_WIDTH{1'b0}};
                            axistream_data_Do <= {pDATA_WIDTH{1'b0}};
                            axistream_mult    <= {pDATA_WIDTH{1'b0}};
                            axistream_sum     <= {pDATA_WIDTH{1'b0}};
                            axistream_sent    <= sm_tready;
                            axistream_last    <= 1'b0;
                        end else begin
                            axistream_fsm     <= AXISTREAM_FSM_OUT;
                            axistream_A       <= {pADDR_WIDTH{1'b0}};
                            axistream_data_Di <= {pDATA_WIDTH{1'b0}};
                            axistream_data_Do <= {pDATA_WIDTH{1'b0}};
                            axistream_mult    <= {pDATA_WIDTH{1'b0}};
                            axistream_sum     <= axistream_sum;
                            axistream_sent    <= axistream_sent;
                            axistream_last    <= axistream_last;
                        end
                    end else begin
                        if (ss_tvalid & (sm_tready | axistream_sent)) begin
                            axistream_fsm     <= AXISTREAM_FSM_UPDATE;
                            axistream_A       <= {pADDR_WIDTH{1'b0}};
                            axistream_data_Di <= {pDATA_WIDTH{1'b0}};
                            axistream_data_Do <= {pDATA_WIDTH{1'b0}};
                            axistream_mult    <= {pDATA_WIDTH{1'b0}};
                            axistream_sum     <= {pDATA_WIDTH{1'b0}};
                            axistream_sent    <= sm_tready;
                            axistream_last    <= ss_tlast;
                        end else begin
                            axistream_fsm     <= AXISTREAM_FSM_OUT;
                            axistream_A       <= {pADDR_WIDTH{1'b0}};
                            axistream_data_Di <= {pDATA_WIDTH{1'b0}};
                            axistream_data_Do <= {pDATA_WIDTH{1'b0}};
                            axistream_mult    <= {pDATA_WIDTH{1'b0}};
                            axistream_sum     <= axistream_sum;
                            axistream_sent    <= axistream_sent | sm_tready;
                            axistream_last    <= axistream_last;
                        end
                    end
                end
                default: begin
                    axistream_fsm     <= AXISTREAM_FSM_IDLE;
                    axistream_A       <= {pADDR_WIDTH{1'b0}};
                    axistream_data_Di <= {pDATA_WIDTH{1'b0}};
                    axistream_data_Do <= {pDATA_WIDTH{1'b0}};
                    axistream_mult    <= {pDATA_WIDTH{1'b0}};
                    axistream_sum     <= {pDATA_WIDTH{1'b0}};
                    axistream_sent    <= 1'b0;
                    axistream_last    <= 1'b0;
               end
            endcase
        end
    end

    assign axilite_active   = (axilite_fsm != AXILITE_FSM_RESET) & (axilite_fsm != AXILITE_FSM_IDLE);
    assign axilite_ap       = axilite_active & (axilite_A == {pADDR_WIDTH{1'b0}});
    assign axilite_len      = axilite_active & (axilite_A >= {{pADDR_WIDTH-5{1'b0}},5'h10}) & (axilite_A <= {{pADDR_WIDTH-5{1'b0}},5'h13});
    assign axilite_num      = axilite_active & (axilite_A >= {{pADDR_WIDTH-5{1'b0}},5'h14}) & (axilite_A <= {{pADDR_WIDTH-5{1'b0}},5'h18});
    assign axilite_tap      = axilite_active & (axilite_A >= {{pADDR_WIDTH-8{1'b0}},8'h40}) & (axilite_A <= {{pADDR_WIDTH-8{1'b0}},8'hFF});
    assign axilite_Do       = {pDATA_WIDTH{axilite_ap  & ~axistream_ap                }} & ap_Do               |
                              {pDATA_WIDTH{axilite_ap  &  axistream_ap                }} & 3'b000              |
                              {pDATA_WIDTH{axilite_len                                }} & len_Do              |
                              {pDATA_WIDTH{axilite_num                                }} & num_Do              |                          
                              {pDATA_WIDTH{axilite_tap & (~ap_reg[0] & ~axistream_tap)}} & tap_Do              |
                              {pDATA_WIDTH{axilite_tap & ( ap_reg[0] |  axistream_tap)}} & {pDATA_WIDTH{1'b1}};
    assign axilite_A        = (axilite_fsm == AXILITE_FSM_WREADY) ? awaddr         : axilite_A_pre;
    assign axilite_Di       = (axilite_fsm == AXILITE_FSM_WREADY) ? axilite_Di_pre : wdata;

    assign axistream_active = (axistream_fsm != AXISTREAM_FSM_RESET) & (axistream_fsm != AXISTREAM_FSM_IDLE);
    assign axistream_ap     = (axistream_fsm == AXISTREAM_FSM_IDLE ) & ~axilite_ap & ap_reg[0] & ss_tvalid | (axistream_fsm == AXISTREAM_FSM_OUT) & axistream_last & sm_tready;
    assign axistream_tap    = (axistream_fsm == AXISTREAM_FSM_IDLE ) & ~axilite_ap & ap_reg[0] & ss_tvalid | axistream_active;
    assign axistream_tap_A  = (axistream_fsm == AXISTREAM_FSM_IDLE | axistream_fsm == AXISTREAM_FSM_INIT) ? {pADDR_WIDTH{1'b0}} : (axistream_A << 2);

    assign awready          = (axilite_fsm == AXILITE_FSM_IDLE   ) &  awvalid &          ~(arvalid & axilite_rr) | (axilite_fsm == AXILITE_FSM_WREADY );
    assign wready           = (axilite_fsm == AXILITE_FSM_IDLE   ) & ~awvalid & wvalid & ~(arvalid & axilite_rr) | (axilite_fsm == AXILITE_FSM_AWREADY);
    assign arready          = (axilite_fsm == AXILITE_FSM_IDLE   ) &  arvalid & ~((awvalid | wvalid) & ~axilite_rr);
    assign rvalid           = (axilite_fsm == AXILITE_FSM_RREADY );
    assign rdata            = {pDATA_WIDTH{rvalid}} & axilite_Do;

    assign ap_WE            = axilite_ap & ((axilite_fsm == AXILITE_FSM_AWREADY) & wvalid | (axilite_fsm == AXILITE_FSM_WREADY) & awvalid         ) | axistream_ap;
    assign ap_EN            = axilite_ap & ((axilite_fsm == AXILITE_FSM_AWREADY) & wvalid | (axilite_fsm == AXILITE_FSM_WREADY) & awvalid | rvalid) | axistream_ap;
    assign ap_Di            = {3{axilite_ap & ~axistream_ap}} & {(ap_reg[2] & ~axilite_Di[0]), 1'b0, (ap_reg[2] & axilite_Di[0])} | 
                              {3{              axistream_ap}} & {{2{sm_tlast}}, 1'b0};

    assign len_WE           = {4{axilite_len & ((axilite_fsm == AXILITE_FSM_AWREADY) & wvalid | (axilite_fsm == AXILITE_FSM_WREADY) & awvalid)}} & we_sel;
    assign len_EN           = axilite_len    & ((axilite_fsm == AXILITE_FSM_AWREADY) & wvalid | (axilite_fsm == AXILITE_FSM_WREADY) & awvalid | rvalid);
    assign len_Di           = axilite_Di;

    assign num_WE           = {4{axilite_num & ((axilite_fsm == AXILITE_FSM_AWREADY) & wvalid | (axilite_fsm == AXILITE_FSM_WREADY) & awvalid)}} & we_sel;
    assign num_EN           = axilite_num    & ((axilite_fsm == AXILITE_FSM_AWREADY) & wvalid | (axilite_fsm == AXILITE_FSM_WREADY) & awvalid | rvalid);
    assign num_Di           = axilite_Di;

    assign tap_WE           = {4{axilite_tap & ((axilite_fsm == AXILITE_FSM_AWREADY) & wvalid | (axilite_fsm == AXILITE_FSM_WREADY) & awvalid) & (~ap_reg[0] & ~axistream_tap)}} & we_sel;
    assign tap_EN           = axilite_tap    & ((axilite_fsm == AXILITE_FSM_AWREADY) & wvalid | (axilite_fsm == AXILITE_FSM_WREADY) & awvalid | rvalid) | axistream_tap;
    assign tap_Di           = axilite_Di;
    assign tap_A            = {pADDR_WIDTH{axilite_tap & (~ap_reg[0] & ~axistream_tap)}} & (axilite_A - {{pADDR_WIDTH-8{1'b0}},8'h40}) |
                              {pADDR_WIDTH{axistream_tap                              }} & axistream_tap_A;

    assign data_WE          = {4{(axistream_fsm == AXISTREAM_FSM_INIT) | (axistream_fsm == AXISTREAM_FSM_MULT) & (axistream_A != {pADDR_WIDTH{1'b0}})}} & we_sel;
    assign data_EN          = (axistream_fsm == AXISTREAM_FSM_INIT  )                                        | 
                              (axistream_fsm == AXISTREAM_FSM_UPDATE) & (axistream_A != {pADDR_WIDTH{1'b0}}) | 
                              (axistream_fsm == AXISTREAM_FSM_MULT  ) & (axistream_A != {pADDR_WIDTH{1'b0}}) ;
    assign data_Di          = axistream_data_Di;
    assign data_A           = {pADDR_WIDTH{(axistream_fsm == AXISTREAM_FSM_INIT)}} & (axistream_A << 2) |
                              {pADDR_WIDTH{(axistream_active & (axistream_fsm != AXISTREAM_FSM_INIT))}} & ((axistream_A - {{pADDR_WIDTH-1{1'b0}}, 1'b1}) << 2);

    assign ss_tready        = (axistream_fsm == AXISTREAM_FSM_UPDATE) & (axistream_A == {pADDR_WIDTH{1'b0}});
    assign sm_tvalid        = (axistream_fsm == AXISTREAM_FSM_OUT) & ~axistream_sent;
    assign sm_tdata         = axistream_sum;
    assign sm_tlast         = (axistream_fsm == AXISTREAM_FSM_OUT) & axistream_last;

endmodule