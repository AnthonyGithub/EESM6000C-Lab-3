`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/20/2023 10:38:55 AM
// Design Name: 
// Module Name: fir_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`define Data_Num 600
`define Coef_Num 11

module fir_tb
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32
)();
    wire                        awready;
    wire                        wready;
    reg                         awvalid;
    reg   [(pADDR_WIDTH-1): 0]  awaddr;
    reg                         wvalid;
    reg signed [(pDATA_WIDTH-1) : 0] wdata;
    wire                        arready;
    reg                         rready;
    reg                         arvalid;
    reg         [(pADDR_WIDTH-1): 0] araddr;
    wire                        rvalid;
    wire signed [(pDATA_WIDTH-1): 0] rdata;
    reg                         ss_tvalid;
    reg signed [(pDATA_WIDTH-1) : 0] ss_tdata;
    reg                         ss_tlast;
    wire                        ss_tready;
    reg                         sm_tready;
    wire                        sm_tvalid;
    wire signed [(pDATA_WIDTH-1) : 0] sm_tdata;
    wire                        sm_tlast;
    reg                         axis_clk;
    reg                         axis_rst_n;

// ram for tap
    wire [3:0]               tap_WE;
    wire                     tap_EN;
    wire [(pDATA_WIDTH-1):0] tap_Di;
    wire [(pADDR_WIDTH-1):0] tap_A;
    wire [(pDATA_WIDTH-1):0] tap_Do;

// ram for data RAM
    wire [3:0]               data_WE;
    wire                     data_EN;
    wire [(pDATA_WIDTH-1):0] data_Di;
    wire [(pADDR_WIDTH-1):0] data_A;
    wire [(pDATA_WIDTH-1):0] data_Do;



    fir #(.pADDR_WIDTH(pADDR_WIDTH), .pDATA_WIDTH(pDATA_WIDTH), .Tape_Num(`Coef_Num)) fir_DUT(
        .awready(awready),
        .wready(wready),
        .awvalid(awvalid),
        .awaddr(awaddr),
        .wvalid(wvalid),
        .wdata(wdata),
        .arready(arready),
        .rready(rready),
        .arvalid(arvalid),
        .araddr(araddr),
        .rvalid(rvalid),
        .rdata(rdata),
        .ss_tvalid(ss_tvalid),
        .ss_tdata(ss_tdata),
        .ss_tlast(ss_tlast),
        .ss_tready(ss_tready),
        .sm_tready(sm_tready),
        .sm_tvalid(sm_tvalid),
        .sm_tdata(sm_tdata),
        .sm_tlast(sm_tlast),

        // ram for tap
        .tap_WE(tap_WE),
        .tap_EN(tap_EN),
        .tap_Di(tap_Di),
        .tap_A(tap_A),
        .tap_Do(tap_Do),

        // ram for data
        .data_WE(data_WE),
        .data_EN(data_EN),
        .data_Di(data_Di),
        .data_A(data_A),
        .data_Do(data_Do),

        .axis_clk(axis_clk),
        .axis_rst_n(axis_rst_n)

        );
    
    // RAM for tap
    bram11 tap_RAM (
        .CLK(axis_clk),
        .WE(tap_WE),
        .EN(tap_EN),
        .Di(tap_Di),
        .A(tap_A),
        .Do(tap_Do)
    );

    // RAM for data: choose bram11 or bram12
    bram11 data_RAM(
        .CLK(axis_clk),
        .WE(data_WE),
        .EN(data_EN),
        .Di(data_Di),
        .A(data_A),
        .Do(data_Do)
    );
    reg signed [(pDATA_WIDTH-1):0] Din_list[0:(`Data_Num-1)];
    reg signed [(pDATA_WIDTH-1):0] Do_list[0:(`Data_Num-1)];
    reg signed [(pDATA_WIDTH-1):0] golden_list[0:(`Data_Num-1)];
    reg signed [(pDATA_WIDTH-1):0] coef[0:(`Coef_Num-1)]; // fill in coef 
    // `ifdef FSDB
    //     initial begin
    //         $fsdbDumpfile("fir.fsdb");
    //         $fsdbDumpvars("+mda");
    //     end
    // `elsif
        initial begin
            $dumpfile("fir.vcd");
            $dumpvars();
        end
    // `endif

    initial begin
        axis_clk = 0;
        forever begin
            #5 axis_clk = (~axis_clk);
        end
    end

    initial begin
        axis_rst_n = 0;
        @(posedge axis_clk); 
        @(posedge axis_clk);
        axis_rst_n = 1;
    end

    reg [31:0]  data_length;
    reg [31:0] coef_length;
    integer Din, golden, coef_in, input_data, golden_data, m, n, coef_data, load_done;
    initial begin
        data_length = 0;
        coef_length = 0;
        load_done = 0;
        Din = $fopen("../py/x.dat","r");
        golden = $fopen("../py/y.dat","r");
	    coef_data= $fopen("../py/coef.dat","r");

        for(m=0;m< `Data_Num ;m=m+1) begin
            input_data = $fscanf(Din,"%d", Din_list[m]);
            golden_data = $fscanf(golden,"%d", golden_list[m]);
            data_length = data_length + 1;
        end
        for(n=0;n< `Coef_Num ;n=n+1)  begin 
            coef_in=$fscanf(coef_data,"%d", coef[n]);
            coef_length = coef_length + 1;
        end
        
        load_done = 1;
    end
    
    reg error_coef;
    reg error; 
    reg fir_done;
    reg ap_or_tap;
    reg tap_rd_wr;
    reg latency_enable;
    reg throughput_enable;
    integer latency,throughput,i,f,k,l;
    integer delay_axis_in_sel,   delay_axis_out_sel;
    integer delay_axis_in_short, delay_axis_out_short, delay_write_addr, delay_read_addr;
    integer delay_axis_in_long,  delay_axis_out_long,  delay_write_data, delay_read_data;
    initial begin
        arvalid = 0;
        rready = 0;
        awvalid = 0; 
        wvalid = 0;
        error_coef = 0;
        error = 0;
        ss_tvalid = 0;
        ss_tlast = 0;
        latency = 0;
        throughput = 0;
        fir_done = 0;
        sm_tready = 0;
        ap_or_tap = 0;
        tap_rd_wr = 0;
        latency_enable = 0;
        throughput_enable = 0;
        while (!axis_rst_n | !load_done) @(posedge axis_clk) begin
            $display("Waiting for data to be loaded and reset done...");
        end
        $display("Loaded!");
        $display("----Start the coefficient input(AXI-lite)----");
        config_write(12'h10, data_length);
        config_write(12'h14, coef_length);
        for(k=0; k< `Coef_Num; k=k+1) begin
            config_write(12'h40+4*k, coef[k]);
        end
        // read-back and check
        $display(" Check Data Length ...");
        config_read_check(12'h10, data_length, 32'hffffffff);
        $display(" Check Number of Taps ...");
        config_read_check(12'h14, coef_length, 32'hffffffff);
        $display(" Check Coefficient ...");
        for(k=0; k < `Coef_Num; k=k+1) begin
            config_read_check(12'h40+4*k, coef[k], 32'hffffffff);
        end
        $display(" Check AP Configuration Register ...");
        config_read_check(12'h00, 32'h04, 32'h0000_0007); // check ap_start = 0, ap_done = 0, ap_idle = 1
        $display(" Programming done ...");
        $display("----End the coefficient input(AXI-lite)----");
        $display("------------Start simulation-----------");
        for(f = 0;f < 3; f = f + 1)  begin
            $display(" Start FIR, Round %d", (f + 1));
            @(posedge axis_clk) config_write(12'h00, 32'h0000_0001);    // ap_start = 1
            latency = 0;
            throughput = 0;
            fir_done = 0;
            sm_tready = 0;
            ap_or_tap = 0;
            tap_rd_wr = 0;
            fork
                begin
                    axis_in();
                end
                begin
                    axis_out();
                end
                begin
                    axilite_polling();
                end
                begin
                    axilite_illegal();
                end
                begin
                    latency_count();
                end
                begin
                    throughput_count();
                end
            join
            $display("The latency is %d cycles", latency);
            sm_tready = 0;
            for(l=0;l < data_length;l=l+1) begin
                sm(golden_list[l],Do_list[l],l);
            end
            if (error | error_coef) begin
                f = 3;
            end
        end
        if (error == 0 & error_coef == 0) begin
            $display("---------------------------------------------");
            $display("-----------Congratulations! Pass-------------");
        end
        else begin
            $display("--------Simulation Failed---------");
        end
        $finish;
    end

    task axis_in;
        begin
            $display("----Start the data input(AXI-Stream)----");
            for(i=0;i<(data_length-1);i=i+1) begin
                ss_tlast = 0;
                axi_stream_master(Din_list[i]);
                $display("AXI-Stream inputting data %d...", i);
            end
            ss_tlast = 1;
            axi_stream_master(Din_list[(`Data_Num - 1)]);
            $display("AXI-Stream inputting data %d...", (`Data_Num - 1));
            wait(fir_done == 1);
            $display("------End the data input(AXI-Stream)------");
        end
    endtask
    
    task axis_out;
        begin
            $display("----Start the data output(AXI-Stream)----");
            for(l=0;l < data_length;l=l+1) begin
                delay_axis_out_short = $urandom_range(0,5);
                delay_axis_out_long  = $urandom_range(0,2) * throughput;
                delay_axis_out_sel   = ($urandom % 2) ? delay_axis_out_short : delay_axis_out_long;
                @(posedge axis_clk) 
                #(delay_axis_out_sel * 10) sm_tready <= 1;
                @(posedge axis_clk);
                while(!sm_tready | !sm_tvalid) @(posedge axis_clk);
                sm_tready <= 0;
                Do_list[l] <= sm_tdata;
                $display("AXI-Stream outputting data %d...", l);
                $display("The throughput is %d cycles", throughput);
            end
            wait(fir_done == 1);
            $display("------End the data output(AXI-Stream)------");
        end
    endtask
    
    task axilite_polling;
        begin
            $display("----Start the ap_done sampling(AXI-Lite)----");
            while (fir_done == 0) @(posedge axis_clk) begin
                if (ap_or_tap == 0) begin
                    delay_read_addr = $urandom_range(0,5);
                    delay_read_data = $urandom_range(0,5);
                    fork 
                        begin
                            @(posedge axis_clk);
                            #(delay_read_addr * 10) arvalid <= 1; araddr <= 12'h00;
                            @(posedge axis_clk);
                            while (!arvalid | (arvalid & !arready)) @(posedge axis_clk);
                            arvalid<=0;
                            araddr<=0;
                        end
                        begin
                            @(posedge axis_clk);
                            #(delay_read_data * 10) rready <= 1;
                            while (!rready | (rready & !rvalid)) @(posedge axis_clk);
                            fir_done = rdata[1];
                            if (rdata[1]) begin
                                $display("ap_done sampled!");
                            end else begin
                                ap_or_tap = $urandom();
                            end
                            rready<=0;
                        end
                    join
                end
            end
            $display("------End the ap_done sampling(AXI-Lite)------");
        end
    endtask

    task axilite_illegal;
        begin
            $display("----Start the illegal tap sampling(AXI-Lite)----");
            while (fir_done == 0) @(posedge axis_clk) begin
                if (ap_or_tap & tap_rd_wr) begin
                    delay_read_addr = $urandom_range(0,5);
                    delay_read_data = $urandom_range(0,5);
                    if (!ss_tlast) begin
                        k = $urandom_range(0,`Coef_Num);
                        fork 
                            begin
                                @(posedge axis_clk);
                                #(delay_read_addr * 10) arvalid <= 1; araddr <= 12'h40+4*k;
                                @(posedge axis_clk);
                                while (!arvalid | (arvalid & !arready)) @(posedge axis_clk);
                                arvalid<=0;
                                araddr<=0;
                            end
                            begin
                                @(posedge axis_clk);
                                #(delay_read_data * 10) rready <= 1;
                                while (!rready | (rready & !rvalid)) @(posedge axis_clk);
                                if (rdata != 32'hffffffff) begin
                                    $display("Illegal TAP ERROR: exp = %d, rdata = %d", 32'hffffffff, rdata);
                                    error_coef <= 1;
                                end
                                rready<=0;
                            end
                        join
                    end
                    ap_or_tap = $urandom();
                end else begin
                    if (!ss_tlast) begin
                        k = $urandom_range(0,`Coef_Num);
                        config_write(12'h40+4*k, $urandom_range(0,32'hffffffff));
                        awvalid <= 0; wvalid <= 0;
                    end
                end 
                tap_rd_wr = $urandom();
            end
            $display("------End the illegal tap sampling(AXI-Lite)------");
        end
    endtask

    task latency_count;
        begin
            while(fir_done == 0) @(posedge axis_clk) begin
                if (fir_DUT.ap_reg[0] & !latency_enable) begin
                    latency_enable <= 1;
                    latency        <= 1;
                end else if (fir_DUT.ap_reg[1] & latency_enable) begin
                    latency_enable <= 0;
                    latency        <= latency;
                end else if (~fir_DUT.ap_reg[1] & latency_enable) begin
                    latency_enable <= latency_enable;
                    latency        <= latency + 1;
                end else begin
                    latency_enable <= 0;
                    latency        <= latency;
                end
            end
        end
    endtask

    task throughput_count;
        begin
            while(fir_done == 0) @(posedge axis_clk) begin
                if (ss_tvalid & ss_tready & !throughput_enable) begin
                    throughput_enable <= 1;
                    throughput        <= 1;
                end else if (sm_tvalid & throughput_enable) begin
                    throughput_enable <= 0;
                    throughput        <= throughput;
                end else if (!sm_tvalid & throughput_enable) begin
                    throughput_enable <= throughput_enable;
                    throughput        <= throughput + 1;
                end else begin
                    throughput_enable <= 0;
                    throughput        <= throughput;
                end
            end
        end
    endtask

    task config_write;
        input [11:0]    addr;
        input [31:0]    data;
        begin
            delay_write_addr = $urandom_range(0,5);
            delay_write_data = $urandom_range(0,5);
            fork
                begin
                    @(posedge axis_clk);
                    #(delay_write_addr * 10) awvalid <= 1; awaddr <= addr;
                    @(posedge axis_clk);
                    while (!awvalid | (awvalid & !awready)) @(posedge axis_clk);
                    awvalid<=0;
                    awaddr<=0;
                end
                begin
                    @(posedge axis_clk);
                    #(delay_write_data * 10) wvalid <= 1; wdata <= data;
                    @(posedge axis_clk);
                    while (!wvalid | (wvalid & !wready)) @(posedge axis_clk);
                    wvalid<=0;   
                    wdata<=0;
                end
            join 
        end
    endtask

    task config_read_check;
        input [11:0]        addr;
        input signed [31:0] exp_data;
        input [31:0]        mask;
        begin
            delay_read_addr = $urandom_range(0,5);
            delay_read_data = $urandom_range(0,5);
            fork 
                begin
                    @(posedge axis_clk);
                    #(delay_read_addr * 10) arvalid <= 1; araddr <= addr;
                    @(posedge axis_clk);
                    while (!arvalid | (arvalid & !arready)) @(posedge axis_clk);
                    arvalid<=0;
                    araddr<=0;
                end
                begin
                    @(posedge axis_clk);
                    #(delay_read_data * 10) rready <= 1;
                    while (!rready | (rready & !rvalid)) @(posedge axis_clk);
                    if( (rdata & mask) != (exp_data & mask)) begin
                        $display("ERROR: exp = %d, rdata = %d", exp_data, rdata);
                        error_coef <= 1;
                    end else begin
                        $display("OK: exp = %d, rdata = %d", exp_data, rdata);
                    end
                    rready<=0;                

                end
            join 
        end
    endtask

    task axi_stream_master;
        input  signed [31:0] in1;
        begin
            delay_axis_in_short = $urandom_range(0,5);
            delay_axis_in_long  = $urandom_range(0,2) * throughput;
            delay_axis_in_sel   = ($urandom % 2) ? delay_axis_in_short : delay_axis_in_long;
            @(posedge axis_clk);
            #(delay_axis_in_sel * 10) ss_tvalid <= 1; ss_tdata <= in1;
            @(posedge axis_clk);
            while (!ss_tvalid | (ss_tvalid & !ss_tready)) @(posedge axis_clk);
            ss_tvalid <= 0;
            ss_tdata <=0;
        end
    endtask

    task sm;
        input   signed [31:0] in2; // golden data
        input   signed [31:0] Do;  // Yn buffer
        input         [31:0] pcnt; // pattern count
        begin
            if (Do != in2) begin
                $display("[ERROR] [Pattern %d] Golden answer: %d, Your answer: %d", pcnt, in2, Do);
                error <= 1;
            end
            else begin
                $display("[PASS] [Pattern %d] Golden answer: %d, Your answer: %d", pcnt, in2, Do);
            end
        end
    endtask
endmodule

