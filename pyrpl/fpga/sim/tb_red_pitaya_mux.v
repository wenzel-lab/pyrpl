`timescale 10ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/12/2024 11:42:06 AM
// Design Name: 
// Module Name: tb_red_pitaya_mux
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


module tb_red_pitaya_mux #( parameter DWT = 14 );
    reg adc_clk, adc_rstn;
//    reg [6-1:0] active_channels;
    
    always begin
        adc_clk = 1; #1;
        adc_clk = 0; #1;
    end
    
//    always begin
//        active_channels = 6'b101001; #10000;
//        active_channels = 6'b001111; #10000;
//    end
        
    
    always begin
        adc_rstn = 0; #10;
        adc_rstn = 1; #1000000000;
    end
        
    wire sort_trig;
    assign DIO1_P = sort_trig;
    
    wire [3-1: 0] mux_addr;
    assign DIO2_P = mux_addr[0];
    assign DIO3_P = mux_addr[1];
    assign DIO4_P = mux_addr[2];
    
    wire [6-1: 0] muxing_channels;
    wire signal_stable;
    
    // wire [6-1:0] active_channels;
    // assign active_channels = 6'b101001;

    red_pitaya_mux i_mux(
      .adc_clk_i            ( adc_clk         ),
      .adc_rstn_i           ( adc_rstn        ),
      .active_channels_i    ( muxing_channels ),
      .mux_addr_o           ( mux_addr        ),
      .signal_stable_o      ( signal_stable   )
      );
    
    wire [8-1: 0] led_o;    
    
    wire sys_wen;
    wire sys_ren;
    wire sys_err;
    wire sys_ack;
    wire [32-1:0] sys_rdata;
    wire [32-1:0] sys_addr;
    wire [32-1:0] sys_wdata;
    wire [ 4-1:0] sys_sel;
    
    assign sys_wen = 0;
    assign sys_ren = 0;
    assign sys_addr = 0;
    assign sys_wdata = 0;
    assign sys_sel = 0;
    
    reg [DWT-1:0] to_scope_a;
    reg droplet_sim_enable;
    
    always begin
        droplet_sim_enable = 1; #10000;
        droplet_sim_enable = 0; #1000;
    end
    
    always @(mux_addr, droplet_sim_enable) begin
        if (droplet_sim_enable) begin
            case (mux_addr)
                0: to_scope_a <= -14'sd100;
                1: to_scope_a <= -14'sd50;
                2: to_scope_a <=  14'sd0;
                3: to_scope_a <=  14'sd50;
                4: to_scope_a <=  14'sd10;
            endcase
        end else begin
            to_scope_a <= -14'sd500;
        end
    end
    
    //assign sys_err = 0;
    //assign sys_ack = 0;
    
    red_pitaya_fads i_fads(
      .adc_clk_i          ( adc_clk           ),
      .adc_rstn_i         ( adc_rstn          ),
      .adc_a_i            ( to_scope_a        ),
      .mux_addr_i         ( mux_addr          ),
      .signal_stable_i    ( signal_stable     ),
      .muxing_channels_o  ( muxing_channels   ),
      .sort_trig          ( sort_trig         ),
      .debug              ( led_o             ),
      
      // System bus
      .sys_addr           ( sys_addr                   ),  // address
      .sys_wdata          ( sys_wdata                  ),  // write data
      .sys_sel            ( sys_sel                    ),  // write byte select
      .sys_wen            ( sys_wen                 ),  // write enable
      .sys_ren            ( sys_ren                 ),  // read enable
      .sys_rdata          ( sys_rdata  ),  // read data
      .sys_err            ( sys_err                 ),  // error indicator
      .sys_ack            ( sys_ack                 )   // acknowledge signal
      );
        
endmodule
