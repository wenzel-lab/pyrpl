`timescale 10ns / 1ns
/*

General Description:

Fluorescence activated droplet sorting (FADS) module for the RedPitaya.
This module reads a fluorescence signal from the fast inputs and
triggers a waveform on the arbitrary signal generator (ASG) to be amplified
by an external high voltage amplifier to sort fluorescent droplets.

*/

module red_pitaya_fads #(
    parameter RSZ = 14,     // RAM size: 2^RSZ,
    parameter DWT = 14,     // data width thresholds
    parameter MEM = 32,     // data width RAM
    parameter CHNL = 6,     // maximum number of detectors/channels
    parameter ALIG = 4'h4   // RAM alignment
//    parameter BUFL = (1<<RSZ)   // fads logger buffer length
//    parameter BUFL = 8'h10   // fads logger buffer length
//    parameter BUFL = 4   // fads logger buffer length
//    parameter signed low_threshold  = 14'b00000000001111,
//    parameter signed high_threshold = 14'b00000011111111
)(
    // ADC
    input                   adc_clk_i           ,   // ADC clock
    input                   adc_rstn_i          ,   // ADC reset - active low
    input signed [14-1: 0]  adc_a_i             ,   // ADC data CHA
//    input       [ 14-1: 0]  adc_b_i         ,   // ADC data CHB
    input        [ 3-1: 0]  mux_addr_i          ,   // Current multiplexer address
    input                   signal_stable_i       ,   // Active high when multiplexer is settled and provides a stable signal

    output reg              sort_trig           ,   // Sorting trigger
    output reg  [CHNL-1:0]  muxing_channels_o   ,   // Output of the currently active channels for the multiplexer
    output reg  [8-1:0]     debug               ,   // At the moment the current state of the state machine

    // System bus
    input      [ 32-1: 0] sys_addr      ,  // bus address
    input      [ 32-1: 0] sys_wdata     ,  // bus write data
    input      [  4-1: 0] sys_sel       ,  // bus write byte select
    input                 sys_wen       ,  // bus write enable
    input                 sys_ren       ,  // bus read enable
    output reg [ 32-1: 0] sys_rdata     ,  // bus read data
    output reg            sys_err       ,  // bus error indicator
    output reg            sys_ack          // bus acknowledge signal
);

// // Registers for thresholds
// // need to be signed for proper comparison with negative voltages
// reg signed [DWT -1:0]   min_intensity_threshold;
// reg signed [DWT -1:0]   low_intensity_threshold;
// reg signed [DWT -1:0]  high_intensity_threshold;

// reg [MEM -1:0]  min_width_threshold;
// reg [MEM -1:0]  low_width_threshold;
// reg [MEM -1:0] high_width_threshold;

// Registers for timers
// reg [MEM -1:0] droplet_width_counter = 32'd0;
reg [MEM -1:0] general_timer_us = 32'd0;
reg [8   -1:0] general_timer_counter = 8'd0;


//// Registers for droplet counters;
//reg [MEM -1:0]  low_intensity_droplets = 32'd0;
//reg [MEM -1:0] high_intensity_droplets = 32'd0;

//reg [MEM -1:0] short_droplets = 32'd0;
//reg [MEM -1:0]  long_droplets = 32'd0;

//reg [MEM -1:0] positive_droplets = 32'd0;
//reg [MEM -1:0] negative_droplets = 32'd0;

// Output registers
reg [MEM -1:0] droplet_id = 32'd0;

reg [MEM -1:0] cur_droplet_intensity = 32'd0;
reg [MEM -1:0] cur_droplet_width = 32'd0;
reg [MEM -1:0] cur_time_us = 32'd0;


// State machine


//reg      min_intensity_reg =  1'b0;
//reg positive_intensity_reg =  1'b0;
//reg     high_intensity_reg =  1'b0;

// reg signed [DWT -1:0] droplet_intensity_max = {1'b1, {DWT-2{1'b0}}};


//reg      min_width_reg = 1'b0;
//reg      low_width_reg = 1'b0;
//reg positive_width_reg = 1'b0;
//reg     high_width_reg = 1'b0;

// Eval
wire droplet_positive;
wire droplet_negative;
reg [16 -1:0] droplet_classification;

// Maintenance
reg droplet_acquisition_enable = 1'b1;
reg sort_enable = 1'b1;
reg [MEM -1:0] sort_end_us = 32'd0;
// reg [MEM -1:0] sort_counter = 32'd0;
reg [MEM -1:0] sort_delay_end_us = 32'd0;
// reg [MEM -1:0] sort_delay_counter = 32'd0;
reg [MEM -1:0] sort_duration = 32'd50;
reg [MEM -1:0] sort_delay = 32'd100;
reg fads_reset = 1'b0;

reg [4-1:0] state = 4'h0;


// Logger Buffer
//reg [20 -1:0] logger_wp_offset = 4'h1;
//reg [BUFL-1:0] logger_wp = 4'h0;
//reg [BUFL-1:0] logger_wp_cur = 4'h0;

//reg [16 -1:0] logger_rp     = 16'b0;
//reg [16 -1:0] buffer_length = 16'b1;

//reg [MEM-1:0] logger_data_buf [BUFL-1:0];
//reg [MEM-1:0] logger_data_buf [0:(1<<BUFL)-1];
//reg [MEM-1:0] logger_data;
//reg [BUFL-1:0] logger_raddr;

// Multi Channel registers and wires
// Registers that need to be added to system bus
wire [CHNL-1:0] droplet_sensing_channel;
reg     [3-1:0] droplet_sensing_address;

reg [CHNL-1:0] enabled_channels;
assign droplet_sensing_channel = 6'b000001 << droplet_sensing_address;


// Intensity
wire [CHNL-1:0]      min_intensity;
wire [CHNL-1:0]      low_intensity;
wire [CHNL-1:0] positive_intensity;
wire [CHNL-1:0]     high_intensity;

// Width
wire [CHNL-1:0]      min_width;
wire [CHNL-1:0]      low_width;
wire [CHNL-1:0] positive_width;
wire [CHNL-1:0]     high_width;

// Area
wire [CHNL-1:0]      min_area;
wire [CHNL-1:0]      low_area;
wire [CHNL-1:0] positive_area;
wire [CHNL-1:0]     high_area;

reg signed  [DWT-1:0]   min_intensity_threshold [CHNL-1:0];
reg signed  [DWT-1:0]   low_intensity_threshold [CHNL-1:0];
reg signed  [DWT-1:0]  high_intensity_threshold [CHNL-1:0];

reg         [MEM-1:0]       min_width_threshold [CHNL-1:0];
reg         [MEM-1:0]       low_width_threshold [CHNL-1:0];
reg         [MEM-1:0]      high_width_threshold [CHNL-1:0];

reg         [MEM-1:0]        min_area_threshold [CHNL-1:0];
reg         [MEM-1:0]        low_area_threshold [CHNL-1:0];
reg         [MEM-1:0]       high_area_threshold [CHNL-1:0];

reg         [MEM-1:0] signal_width              [CHNL-1:0];
reg signed  [MEM-1:0] signal_area               [CHNL-1:0];
reg signed  [DWT-1:0] signal_max                [CHNL-1:0];


// Assigning
genvar i;
generate
    for (i = 0; i < CHNL; i = i + 1) begin
        
        // since min_intensity uses the current adc value, it is not something to be used in droplet evaluation (state >= 3)
        assign      min_intensity[i] = (adc_a_i >= min_intensity_threshold[i]) && signal_stable_i && (mux_addr_i == i);

        assign      low_intensity[i] = (signal_max[i] >=   min_intensity_threshold[i]) && (signal_max[i] < low_intensity_threshold[i]);
        assign positive_intensity[i] = (signal_max[i] >=   low_intensity_threshold[i]) && (signal_max[i] < high_intensity_threshold[i]);
        assign     high_intensity[i] =  signal_max[i] >=  high_intensity_threshold[i];

        assign      min_area[i] =  signal_area[i] >=  min_area_threshold[i];
        assign      low_area[i] = (signal_area[i] >=  min_area_threshold[i]) && (signal_area[i] <  low_area_threshold[i]);
        assign positive_area[i] = (signal_area[i] >=  low_area_threshold[i]) && (signal_area[i] < high_area_threshold[i]) && min_area[i];
        assign     high_area[i] = (signal_area[i] >= high_area_threshold[i]) && min_area[i];

        assign      min_width[i] =  signal_width[i] >=  min_width_threshold[i];
        assign      low_width[i] = (signal_width[i] >=  min_width_threshold[i]) && (signal_width[i] <  low_width_threshold[i]);
        assign positive_width[i] = (signal_width[i] >=  low_width_threshold[i]) && (signal_width[i] < high_width_threshold[i]) && min_width[i];
        assign     high_width[i] = (signal_width[i] >= high_width_threshold[i]) && min_width[i];
    end
endgenerate


// Final droplet sorging decision logic
assign droplet_positive = &positive_intensity && &positive_width;
assign droplet_negative = (|low_intensity || |high_intensity || |positive_intensity) && (|low_width || |high_width || |positive_width) && (~(&positive_intensity && &positive_width));


//integer i;
//always @(posedge adc_clk_i) begin
//    logger_wp_cur <= logger_wp;
//end

always @(posedge adc_clk_i) begin
    if (fads_reset) begin
        general_timer_counter <= 8'd0;
        general_timer_us <= 32'd0;
    end else begin
        general_timer_counter <= general_timer_counter + 8'd1;
        if (general_timer_counter >= 8'd125) begin
            general_timer_us <= general_timer_us + 32'd1;
            general_timer_counter <= 8'd0;
        end
    end
end



// wire droplet_min;
// assign droplet_min = adc_a_i >= -14'd250;

// always @(posedge adc_clk_i) begin
//     debug[0] <= droplet_min;
//     debug[1] <= min_intensity[0];
//     debug[2] <= min_intensity[1];
//     debug[3] <= min_width[0];
//     debug[4] <= min_width[1];
//     debug[5] <= droplet_positive;
//     debug[6] <= droplet_negative;
//     debug[7] <= 1;
// end


always @(posedge adc_clk_i) begin
    debug[6] <= droplet_negative;
    debug[7] <= droplet_positive;
    
    // Debug
    case (state)
        // Base state | 0
        4'h0 : begin
            debug <= 6'b000001;
            if (fads_reset || !adc_rstn_i) begin
                state <= 4'h0;
                muxing_channels_o <= droplet_sensing_channel;
                sort_trig <= 1'b0;

//                negative_droplets       <= 32'd0;
//                positive_droplets       <= 32'd0;

//                low_intensity_droplets  <= 32'd0;
//                high_intensity_droplets <= 32'd0;

//                short_droplets          <= 32'd0;
//                long_droplets           <= 32'd0;

                droplet_id              <= 32'd0;
                cur_droplet_intensity   <= 32'd0;
                cur_droplet_width       <= 32'd0;
                // droplet_width_counter   <= 32'd0;

                droplet_classification  <=  8'd0;

                
                // initialize with the most negative number possible in 14 bit
                // ADC input is signed, that is why 2-complement must be used
                // signal_max <= '{CHNL{1'b1, {DWT-2{1'b0}}}};
                signal_max <= '{CHNL{-14'sd8192}};

            end else begin
                // for (i=0; i<BUFL; i=i+1) begin
                //     logger_data_buf[i] <= 0;
                // end

                // logger_wp <= {BUFL{1'b0}};

                if (droplet_acquisition_enable) begin
                    state <= 4'h1;
                end
            end
        end

        // Wait for Droplet | 1
        4'h1 : begin
            debug <= 6'b000010;
            if (fads_reset || !adc_rstn_i)
                state <= 4'h0;
            else begin
                muxing_channels_o <= droplet_sensing_channel;
                if (signal_stable_i) begin
                    if (min_intensity[droplet_sensing_address]) begin
                        signal_width <= '{CHNL{0}};
                        signal_area  <= '{CHNL{0}};
                        signal_max   <= '{CHNL{-14'sd8192}};
                        
                        
                        signal_width[droplet_sensing_address] <= 32'd1;
                        signal_area[droplet_sensing_address] <= signal_area[droplet_sensing_address] + adc_a_i;
                        signal_max[droplet_sensing_address] <= adc_a_i;

                        state <= 4'h2;
                    end
                end else
                    state <= 4'h1;
            end
        end

        // Acquiring Droplet | 2
        4'h2 : begin
            debug <= 6'b000100;
            muxing_channels_o = enabled_channels | droplet_sensing_channel;
            if (fads_reset || !adc_rstn_i)
                state <= 4'h0;
            else if (signal_stable_i) begin
                // Intensity
                if (adc_a_i > signal_max[mux_addr_i]) begin
                    signal_max[mux_addr_i] <= adc_a_i;
                end

                // Width
                if (min_intensity[mux_addr_i]) begin
                    // TODO handle interpolation
                    signal_width[mux_addr_i] <= signal_width[mux_addr_i] + 32'd1;
                end

                // TODO Area
                signal_area[mux_addr_i] <= signal_area[mux_addr_i] + adc_a_i;

                // State transition
                // Simple state transition if signal is below min intensity
                // in the droplet sensing channel - for now.
                // TODO there should be a register for the last adc values of each channel
                if (!min_intensity[droplet_sensing_address] && (mux_addr_i == droplet_sensing_address)) begin
                    state <= 4'h3;
                    droplet_classification <= 8'd0;
                end
            end
        end

        // Evaluating Droplet | 3
        4'h3 : begin
/* 
//             // TODO evaluate droplet counter necessity
//             // Update droplet counters
//             if (droplet_positive) begin
// //                positive_droplets <= positive_droplets + 32'd1;
//                 droplet_classification[7] <= 1;
// //            end else begin
// //                if (droplet_negative)
// ////                    negative_droplets <= negative_droplets + 32'd1;
//             end

//             if (low_intensity) begin
// //                low_intensity_droplets <= low_intensity_droplets + 32'd1;
//                 droplet_classification[0] <= 1;
//             end

//             if (positive_intensity)
//                 droplet_classification[1] <= 1;

//             if (high_intensity) begin
// //                high_intensity_droplets <= high_intensity_droplets + 32'd1;
//                 droplet_classification[2] <= 1;
//             end

//             if (low_width) begin
// //                short_droplets <= short_droplets + 32'd1;
//                 droplet_classification[3] <= 1;
//             end

//             if (positive_width)
//                 droplet_classification[4] <= 1;

//             if (high_width) begin
// //                long_droplets <= long_droplets + 32'd1;
//                 droplet_classification[5] <= 1;
//             end

            // Logging
            // getting log data
    //        logger_data_buf[logger_wp] <= positive_droplets + negative_droplets;
            // incrementing write pointer
    //        logger_wp <= (logger_wp + ALIG) % BUFL;
    //        logger_wp <= logger_wp + 4'b0001;
    //        logger_wp <= logger_wp + 1; 
*/

            
            // State transition
            if (fads_reset || !adc_rstn_i)
                state <= 4'h0;
            else begin
                debug <= 6'b001000;
                muxing_channels_o <= droplet_sensing_channel;
                
                // Update output
                if (droplet_positive || droplet_negative) begin
                    droplet_id <= droplet_id + 32'd1;
                    cur_droplet_width[0] <= signal_width[0];
                    cur_droplet_intensity[0] <= signal_max[0];
                    cur_time_us <= general_timer_us;
    
                    droplet_classification[ 0] <= | low_intensity;
                    droplet_classification[ 1] <= & positive_intensity;
                    droplet_classification[ 2] <= | high_intensity;
    
                    droplet_classification[ 3] <= | low_width;
                    droplet_classification[ 4] <= & positive_width;
                    droplet_classification[ 5] <= | high_width;
    
                    droplet_classification[ 6] <= | low_area;
                    droplet_classification[ 7] <= & positive_area;
                    droplet_classification[ 8] <= | high_area;
                    // droplet_classification[ 6] <= 1'b0;
                    // droplet_classification[ 7] <= 1'b0;
                    // droplet_classification[ 8] <= 1'b0;
    
                    droplet_classification[ 9] <= 1'b0;
                    droplet_classification[10] <= 1'b0;
                    droplet_classification[11] <= 1'b0;
                    droplet_classification[12] <= 1'b0;
                    droplet_classification[13] <= 1'b0;
    
                    droplet_classification[14] <= sort_trig;
                    droplet_classification[15] <= droplet_positive;
                end
                if (sort_enable && droplet_positive) begin
                    // sort_counter <= 32'd0;
                    sort_delay_end_us <= general_timer_us + sort_delay;
                    // sort_delay_counter <= 32'd0;
                    state <= 4'h4;
                end else begin
                    state <= 4'h1;
                end
            end
        end

        // Sorting Delay | 4
        4'h4 : begin
            if (fads_reset || !adc_rstn_i)
                state <= 4'h0;

            else if (general_timer_us >= sort_delay_end_us) begin
                debug <= 6'b010000;
                muxing_channels_o <= droplet_sensing_channel;

            // if (sort_delay_counter < sort_delay) begin
            //     sort_delay_counter <= sort_delay_counter + 32'd1;
            // end else begin

                sort_end_us <= general_timer_us + sort_duration;
                state <= 4'h5;
            end
        end

        // Sorting | 5
        4'h5 : begin
            if (fads_reset || !adc_rstn_i)
                state <= 4'h0;
            else begin 
                debug <= 6'b100000;
                muxing_channels_o <= droplet_sensing_channel;
                if (general_timer_us < sort_end_us) begin
                    sort_trig <= 1;
                end else begin
                    sort_trig <= 0;
                    state <= 4'h1;
                end
            end
                //     sort_trig <= 1'b0;
                //     state <= 4'h1;
            // if (sort_counter < sort_duration) begin
            //     sort_counter <= sort_counter + 32'd1;
            //     sort_trig <= 1'b1;

        //     if (fads_reset)
        //         state <= 4'h0;
        // end else begin
        //     sort_trig <= 1'b0;
        //     state <= 4'h1;
        // end
        end
        default: debug <= 8'b11111111;
    endcase
end
//
//always @(posedge adc_clk_i) begin
//    if (sys_addr[19:0] == {logger_wp_offset, logger_wp}) begin
//        sys_ack <= sys_en;
//        sys_rdata <= {{32- MEM{1'b0}}, logger_data};
//
//    end
//end

//always @(posedge adc_clk_i) begin
//   logger_raddr   <= sys_addr[BUFL+1:2] ; // address synchronous to clock
//   logger_data    <= logger_data_buf[logger_raddr] ;
//end

//always @(posedge adc_clk_i) begin
//    logger_raddr <= sys_addr[
//end

// wire [3-1:0] mux_addr;
// always @(posedge adc_clk_i) begin
//     mux_addr_o <= mux_addr;
// end

// red_pitaya_mux i_mux(
//   .adc_clk_i            ( adc_clk_i        ),
//   .adc_rstn_i           ( adc_rstn_i       ),
//   .active_channels_i    ( enabled_channels  ),
//   .mux_addr_o           ( mux_addr_o       )
//   );

// System bus
// setting up necessary wires
wire sys_en;
assign sys_en = sys_wen | sys_ren;

// Reading from system bus
always @(posedge adc_clk_i)
    // Necessary handling of reset signal
    if (adc_rstn_i == 1'b0) begin
        // resetting to default values

        //  min_intensity_threshold[k]  <= 14'b11111111111111;
        //  low_intensity_threshold[k]  <= 14'b11111111111110;
        // high_intensity_threshold[k]  <= 14'b10000011111111;

            min_intensity_threshold  <= '{CHNL{-14'sd175}}; // should roughly correspond to -0.5V
            low_intensity_threshold  <= '{CHNL{-14'sd150}}; // on the specific redpitaya I'm testing on
           high_intensity_threshold  <= '{CHNL{ 14'sd900}};

                min_width_threshold  <= '{CHNL{32'h00000001}};
                low_width_threshold  <= '{CHNL{32'h000000ff}};
               high_width_threshold  <= '{CHNL{32'hccddeeff}};

                 min_area_threshold  <= '{CHNL{32'h00000001}};
                 low_area_threshold  <= '{CHNL{32'h000000ff}};
                high_area_threshold  <= '{CHNL{32'hccddeeff}};
               
               enabled_channels <= 6'b000011;
               droplet_sensing_address <= 3'h0;

    end else if (sys_wen) begin
        if (sys_addr[19:0]==20'h00020)                 fads_reset       <= sys_wdata[MEM-1:0];

        if (sys_addr[19:0]==20'h00024)                 sort_delay       <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h00028)              sort_duration       <= sys_wdata[MEM-1:0];

        if (sys_addr[19:0]==20'h00300)              enabled_channels    <= sys_wdata[CHNL-1:0];
        if (sys_addr[19:0]==20'h00304)       droplet_sensing_address    <= sys_wdata[   3-1:0];

        if (sys_addr[19:0]==20'h01000)    min_intensity_threshold[0]    <= sys_wdata[DWT-1:0];
        if (sys_addr[19:0]==20'h01004)    min_intensity_threshold[1]    <= sys_wdata[DWT-1:0];
        if (sys_addr[19:0]==20'h01008)    min_intensity_threshold[2]    <= sys_wdata[DWT-1:0];
        if (sys_addr[19:0]==20'h0100c)    min_intensity_threshold[3]    <= sys_wdata[DWT-1:0];
        if (sys_addr[19:0]==20'h01010)    min_intensity_threshold[4]    <= sys_wdata[DWT-1:0];
        if (sys_addr[19:0]==20'h01014)    min_intensity_threshold[5]    <= sys_wdata[DWT-1:0];

        if (sys_addr[19:0]==20'h01020)    low_intensity_threshold[0]    <= sys_wdata[DWT-1:0];
        if (sys_addr[19:0]==20'h01024)    low_intensity_threshold[1]    <= sys_wdata[DWT-1:0];
        if (sys_addr[19:0]==20'h01028)    low_intensity_threshold[2]    <= sys_wdata[DWT-1:0];
        if (sys_addr[19:0]==20'h0102c)    low_intensity_threshold[3]    <= sys_wdata[DWT-1:0];
        if (sys_addr[19:0]==20'h01030)    low_intensity_threshold[4]    <= sys_wdata[DWT-1:0];
        if (sys_addr[19:0]==20'h01034)    low_intensity_threshold[5]    <= sys_wdata[DWT-1:0];

        if (sys_addr[19:0]==20'h01040)   high_intensity_threshold[0]    <= sys_wdata[DWT-1:0];
        if (sys_addr[19:0]==20'h01044)   high_intensity_threshold[1]    <= sys_wdata[DWT-1:0];
        if (sys_addr[19:0]==20'h01048)   high_intensity_threshold[2]    <= sys_wdata[DWT-1:0];
        if (sys_addr[19:0]==20'h0104c)   high_intensity_threshold[3]    <= sys_wdata[DWT-1:0];
        if (sys_addr[19:0]==20'h01050)   high_intensity_threshold[4]    <= sys_wdata[DWT-1:0];
        if (sys_addr[19:0]==20'h01054)   high_intensity_threshold[5]    <= sys_wdata[DWT-1:0];


        if (sys_addr[19:0]==20'h01060)        min_width_threshold[0]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h01064)        min_width_threshold[1]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h01068)        min_width_threshold[2]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h0106c)        min_width_threshold[3]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h01070)        min_width_threshold[4]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h01074)        min_width_threshold[5]    <= sys_wdata[MEM-1:0];

        if (sys_addr[19:0]==20'h01080)        low_width_threshold[0]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h01084)        low_width_threshold[1]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h01088)        low_width_threshold[2]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h0108c)        low_width_threshold[3]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h01090)        low_width_threshold[4]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h01094)        low_width_threshold[5]    <= sys_wdata[MEM-1:0];

        if (sys_addr[19:0]==20'h010a0)       high_width_threshold[0]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h010a4)       high_width_threshold[1]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h010a8)       high_width_threshold[2]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h010ac)       high_width_threshold[3]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h010b0)       high_width_threshold[4]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h010b4)       high_width_threshold[5]    <= sys_wdata[MEM-1:0];


        if (sys_addr[19:0]==20'h010c0)         min_area_threshold[0]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h010c4)         min_area_threshold[1]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h010c8)         min_area_threshold[2]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h010cc)         min_area_threshold[3]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h010d0)         min_area_threshold[4]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h010d4)         min_area_threshold[5]    <= sys_wdata[MEM-1:0];

        if (sys_addr[19:0]==20'h010e0)         low_area_threshold[0]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h010e4)         low_area_threshold[1]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h010e8)         low_area_threshold[2]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h010ec)         low_area_threshold[3]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h010f0)         low_area_threshold[4]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h010f4)         low_area_threshold[5]    <= sys_wdata[MEM-1:0];

        if (sys_addr[19:0]==20'h01100)        high_area_threshold[0]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h01104)        high_area_threshold[1]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h01108)        high_area_threshold[2]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h0110c)        high_area_threshold[3]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h01110)        high_area_threshold[4]    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h01114)        high_area_threshold[5]    <= sys_wdata[MEM-1:0];

    end

// Writing to system bus
always @(posedge adc_clk_i)
    // Necessary handling of reset signal
    if (adc_rstn_i == 1'b0) begin
        sys_err <= 1'b0;
        sys_ack <= 1'b0;
    end else begin
        sys_err <= 1'b0;
        casez (sys_addr[19:0])
        //   Address  |       handling bus signals        | creating 32 bit wide word containing the data
            20'h01000: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},  min_intensity_threshold[0]}  ; end
            20'h01004: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},  min_intensity_threshold[1]}  ; end
            20'h01008: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},  min_intensity_threshold[2]}  ; end
            20'h0100c: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},  min_intensity_threshold[3]}  ; end
            20'h01010: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},  min_intensity_threshold[4]}  ; end
            20'h01014: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},  min_intensity_threshold[5]}  ; end

            20'h01020: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},  low_intensity_threshold[0]}  ; end
            20'h01024: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},  low_intensity_threshold[1]}  ; end
            20'h01028: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},  low_intensity_threshold[2]}  ; end
            20'h0102c: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},  low_intensity_threshold[3]}  ; end
            20'h01030: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},  low_intensity_threshold[4]}  ; end
            20'h01034: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},  low_intensity_threshold[5]}  ; end

            20'h01040: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}}, high_intensity_threshold[0]}  ; end
            20'h01044: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}}, high_intensity_threshold[1]}  ; end
            20'h01048: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}}, high_intensity_threshold[2]}  ; end
            20'h0104c: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}}, high_intensity_threshold[3]}  ; end
            20'h01050: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}}, high_intensity_threshold[4]}  ; end
            20'h01054: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}}, high_intensity_threshold[5]}  ; end

            
            20'h01060: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},      min_width_threshold[0]}  ; end
            20'h01064: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},      min_width_threshold[1]}  ; end
            20'h01068: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},      min_width_threshold[2]}  ; end
            20'h0106c: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},      min_width_threshold[3]}  ; end
            20'h01070: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},      min_width_threshold[4]}  ; end
            20'h01074: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},      min_width_threshold[5]}  ; end

            20'h01080: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},      low_width_threshold[0]}  ; end
            20'h01084: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},      low_width_threshold[1]}  ; end
            20'h01088: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},      low_width_threshold[2]}  ; end
            20'h0108c: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},      low_width_threshold[3]}  ; end
            20'h01090: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},      low_width_threshold[4]}  ; end
            20'h01094: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},      low_width_threshold[5]}  ; end

            20'h010a0: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},     high_width_threshold[0]}  ; end
            20'h010a4: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},     high_width_threshold[1]}  ; end
            20'h010a8: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},     high_width_threshold[2]}  ; end
            20'h010ac: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},     high_width_threshold[3]}  ; end
            20'h010b0: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},     high_width_threshold[4]}  ; end
            20'h010b4: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},     high_width_threshold[5]}  ; end


            20'h010c0: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},       min_area_threshold[0]}  ; end
            20'h010c4: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},       min_area_threshold[1]}  ; end
            20'h010c8: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},       min_area_threshold[2]}  ; end
            20'h010cc: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},       min_area_threshold[3]}  ; end
            20'h010d0: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},       min_area_threshold[4]}  ; end
            20'h010d4: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},       min_area_threshold[5]}  ; end

            20'h010e0: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},       low_area_threshold[0]}  ; end
            20'h010e4: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},       low_area_threshold[1]}  ; end
            20'h010e8: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},       low_area_threshold[2]}  ; end
            20'h010ec: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},       low_area_threshold[3]}  ; end
            20'h010f0: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},       low_area_threshold[4]}  ; end
            20'h010f4: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},       low_area_threshold[5]}  ; end

            20'h01100: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},      high_area_threshold[0]}  ; end
            20'h01104: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},      high_area_threshold[1]}  ; end
            20'h01108: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},      high_area_threshold[2]}  ; end
            20'h0110c: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},      high_area_threshold[3]}  ; end
            20'h01110: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},      high_area_threshold[4]}  ; end
            20'h01114: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},      high_area_threshold[5]}  ; end


            20'h00020: begin sys_ack <= sys_en;  sys_rdata <= {{32-   1{1'b0}},               fads_reset}     ; end

            20'h00024: begin sys_ack <= sys_en;  sys_rdata <= {{32-   1{1'b0}},               sort_delay}     ; end
            20'h00028: begin sys_ack <= sys_en;  sys_rdata <= {{32-   1{1'b0}},            sort_duration}     ; end


//            20'h00100: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},   low_intensity_droplets}     ; end
//            20'h00104: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},  high_intensity_droplets}     ; end

//            20'h00108: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},           short_droplets}     ; end
//            20'h0010c: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},            long_droplets}     ; end

//            20'h00110: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},        positive_droplets}     ; end

            20'h00200: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},               droplet_id}     ; end
            20'h00204: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},    cur_droplet_intensity}     ; end
            20'h00208: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},        cur_droplet_width}     ; end
            20'h0020c: begin sys_ack <= sys_en;  sys_rdata <= {{32-  16{1'b0}},   droplet_classification}     ; end
            20'h00210: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},              cur_time_us}     ; end

            20'h00300: begin sys_ack <= sys_en;  sys_rdata <= {{32-CHNL{1'b0}},         enabled_channels}     ; end
            20'h00304: begin sys_ack <= sys_en;  sys_rdata <= {{32-   3{1'b0}},  droplet_sensing_address}     ; end
            20'h00308: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},                  adc_a_i}     ; end

//            20'h01000: begin sys_ack <= sys_en;  sys_rdata <= {{32-BUFL{1'b0}},            logger_wp_cur}     ; end

//            20'h100??: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},              logger_data}     ; end


//            20'h10000: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},                    32'd0}     ; end
//            20'h10004: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},                    32'd1}     ; end
//            20'h10008: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},                    32'd2}     ; end
//            20'h1000c: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},                    32'd3}     ; end

            default:   begin sys_ack <= sys_en;  sys_rdata <= 32'h0                                 ; end
        endcase
    end
endmodule
