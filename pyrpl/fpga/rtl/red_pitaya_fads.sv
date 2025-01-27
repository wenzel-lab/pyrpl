`timescale 10ns / 1ns
/*

General Description:

Fluorescence activated droplet sorting (FADS) module for the RedPitaya.
This module reads a fluorescence signal from the fast inputs and
triggers a pin to an external pulse signal generator and high voltage 
amplifier to control electrodes-on-chips and sort fluorescent droplets.

*/

module red_pitaya_fads #(
    parameter RSZ = 14,     // RAM size: 2^RSZ,
    parameter DWT = 14,     // data width thresholds
    parameter MEM = 32,     // data width RAM
    parameter CHNL = 6,     // maximum number of detectors/channels
    parameter ALIG = 4'h4   // RAM alignment
)(
    // ADC
    input                   adc_clk_i           ,   // ADC clock
    input                   adc_rstn_i          ,   // ADC reset - active low
    input signed [14-1: 0]  adc_a_i             ,   // ADC data Channel A - the multiplexer input
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

// Registers for timers
reg [MEM -1:0] general_timer_us = 32'd0; // General timer in microseconds
reg [8   -1:0] general_timer_counter = 8'd0; // Counter for general timer

// Output registers
reg         [MEM -1:0] droplet_id               = 32'd0;      // unique ID of the last fully evaluated droplet signal, stays stable until overwritten with the next event when its evaluation has finished
reg signed  [MEM -1:0] cur_droplet_intensity    [CHNL-1:0];   // intensity peak value
reg         [MEM -1:0] cur_droplet_width        [CHNL-1:0];   // peak width - full width at half maximum (fwhm)
reg signed  [MEM -1:0] cur_droplet_area         [CHNL-1:0];   // area under the curve (auc)

reg         [MEM -1:0] cur_time_us              = 32'd0;      // output of time - changes rapidly

// Eval
wire droplet_positive; // Indicates if the droplet is positive
wire droplet_negative; // Indicates if the droplet is negative
reg [16 -1:0] droplet_classification; // Classification of the droplet

// Maintenance
reg droplet_acquisition_enable = 1'b1; // Enable droplet acquisition
reg sort_enable = 1'b1; // Enable sorting
reg [MEM -1:0] sort_end_us = 32'd0; // End time for sorting in microseconds
reg [MEM -1:0] sort_delay_end_us = 32'd0; // End time for sorting delay in microseconds
reg [MEM -1:0] sort_duration = 32'd50; // Duration of sorting in microseconds
reg [MEM -1:0] sort_delay = 32'd100; // Delay before sorting in microseconds
reg fads_reset = 1'b0; // Reset signal for FADS

reg [4-1:0] state = 4'h0; // State of the state machine

// TODO it is still desirable to add a function that remembers if within a given time
// negative droplets preceded a positive one, to prevent contaminated sorting.

// Multi Channel registers and wires
wire [CHNL-1:0] droplet_sensing_channel; // Channel for droplet sensing
reg     [3-1:0] droplet_sensing_address; // Address for droplet sensing

reg [CHNL-1:0] enabled_channels; // Enabled channels
assign droplet_sensing_channel = 6'b000001 << droplet_sensing_address; // Assign droplet sensing channel

// Intensity (result of droplet classification) for all channels
wire [CHNL-1:0]      min_intensity;
wire [CHNL-1:0]      low_intensity;
wire [CHNL-1:0] positive_intensity;
wire [CHNL-1:0]     high_intensity;

// Width (result of droplet classification)
wire [CHNL-1:0]      min_width;
wire [CHNL-1:0]      low_width;
wire [CHNL-1:0] positive_width;
wire [CHNL-1:0]     high_width;

// Area (result of droplet classification)
wire [CHNL-1:0]      min_area;
wire [CHNL-1:0]      low_area;
wire [CHNL-1:0] positive_area;
wire [CHNL-1:0]     high_area;

// Intensity thresholds for all channels
reg signed  [DWT-1:0]   min_intensity_threshold [CHNL-1:0]; // noise cutoff threshold - from here on we evaluate and record
reg signed  [DWT-1:0]   low_intensity_threshold [CHNL-1:0]; // min sorting threshold - below this value droplets are not sorted
reg signed  [DWT-1:0]  high_intensity_threshold [CHNL-1:0]; // max sorting threshold - above this value droplets are not sorted

// Width thresholds
reg         [MEM-1:0]       min_width_threshold [CHNL-1:0]; // noise cutoff threshold
reg         [MEM-1:0]       low_width_threshold [CHNL-1:0]; // min sorting threshold
reg         [MEM-1:0]      high_width_threshold [CHNL-1:0]; // max sorting threshold

// Area thresholds
reg         [MEM-1:0]        min_area_threshold [CHNL-1:0]; // noise cutoff threshold
reg         [MEM-1:0]        low_area_threshold [CHNL-1:0]; // min sorting threshold
reg         [MEM-1:0]       high_area_threshold [CHNL-1:0]; // max sorting threshold

reg         [MEM-1:0] signal_width              [CHNL-1:0]; // Signal width for each channel
reg signed  [MEM-1:0] signal_area               [CHNL-1:0]; // Signal area for each channel
reg signed  [DWT-1:0] signal_max                [CHNL-1:0]; // Signal max intensity for each channel

// Registers to store fast-changing ADC values for each channel
reg signed [DWT-1:0] adc_values [CHNL-1:0];

// Averaged Detector Voltage Array from ADC
reg [DWT-1:0] temp_adc_data [CHNL-1:0]; // Temporary data array for each channel
reg [DWT-1:0] cur_adc_data [CHNL-1:0]; // Output data array for each channel
reg [MEM-1:0] update_cycle = 0; // Update cycle to track completion of all active channels
// Registers to accumulate ADC values and count samples
reg signed [MEM-1:0] adc_accum [CHNL-1:0]; // Accumulators for ADC values
reg [16-1:0] sample_count = 0; // Sample count
reg [3-1:0] prev_mux_addr = 0; // Previous multiplexer address


// Assigning
genvar i;
generate
    for (i = 0; i < CHNL; i = i + 1) begin
        // since min_intensity uses the current adc value, it is not something to be used in droplet evaluation (state >= 3)
        // Assign intensity thresholds
        assign      min_intensity[i] = (adc_values[i] >= min_intensity_threshold[i]) && signal_stable_i && (mux_addr_i == i);
        assign      low_intensity[i] = (signal_max[i] >=   min_intensity_threshold[i]) && (signal_max[i] < low_intensity_threshold[i]);
        assign positive_intensity[i] = (signal_max[i] >=   low_intensity_threshold[i]) && (signal_max[i] < high_intensity_threshold[i]);
        assign     high_intensity[i] =  signal_max[i] >=  high_intensity_threshold[i];

        // Assign area thresholds
        assign      min_area[i] =  signal_area[i] >=  min_area_threshold[i];
        assign      low_area[i] = (signal_area[i] >=  min_area_threshold[i]) && (signal_area[i] <  low_area_threshold[i]);
        assign positive_area[i] = (signal_area[i] >=  low_area_threshold[i]) && (signal_area[i] < high_area_threshold[i]) && min_area[i];
        assign     high_area[i] = (signal_area[i] >= high_area_threshold[i]) && min_area[i];

        // Assign width thresholds
        assign      min_width[i] =  signal_width[i] >=  min_width_threshold[i];
        assign      low_width[i] = (signal_width[i] >=  min_width_threshold[i]) && (signal_width[i] <  low_width_threshold[i]);
        assign positive_width[i] = (signal_width[i] >=  low_width_threshold[i]) && (signal_width[i] < high_width_threshold[i]) && min_width[i];
        assign     high_width[i] = (signal_width[i] >= high_width_threshold[i]) && min_width[i];
    end
endgenerate

// Final droplet sorting decision logic
assign droplet_positive = &positive_intensity && &positive_width;
assign droplet_negative = (|low_intensity || |high_intensity || |positive_intensity) && (|low_width || |high_width || |positive_width) && (~(&positive_intensity && &positive_width));

// General timer logic
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

// Capture and accumulate ADC values for the active channel
always @(posedge adc_clk_i) begin
    if (signal_stable_i) begin
        adc_values[mux_addr_i] <= adc_a_i;
        adc_accum[mux_addr_i] <= adc_accum[mux_addr_i] + adc_a_i;
        sample_count <= sample_count + 1;
    end
end
// Write averaged detector voltage signal data (ADC) to array when the multiplexer address changes
always @(posedge adc_clk_i) begin
    if (fads_reset || !adc_rstn_i) begin
        sample_count <= 0;
        adc_accum <= '{default: 0};
        prev_mux_addr <= 0;
        update_cycle <= 0;
        cur_adc_data <= '{default: 0}; // Reset output ADC data
        temp_adc_data <= '{default: 0}; // Reset temporary ADC data
    end else if (mux_addr_i != prev_mux_addr) begin
        if (sample_count > 0) begin
            // Write the averaged value to the temporary ADC array for the current channel
            temp_adc_data[prev_mux_addr] <= adc_accum[prev_mux_addr] / sample_count;
        end
        sample_count <= 0;
        adc_accum <= '{default: 0};
        prev_mux_addr <= mux_addr_i;

        // Check if all active channels have been updated
        if (mux_addr_i == (CHNL-1)) begin
            update_cycle <= update_cycle + 1; // Increment the update cycle
            cur_adc_data <= temp_adc_data; // Update the output ADC data
        end
    end
end

// State machine for droplet sorting
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

                droplet_id              <= 32'd0;
                cur_droplet_intensity   <= '{default: 32'd0}; // Reset all channels
                cur_droplet_width       <= '{default: 32'd0}; // Reset all channels
                cur_droplet_area        <= '{default: 32'd0}; // Reset all channels
                droplet_classification  <=  8'd0;

                // initialize with the most negative number possible in 14 bit
                // ADC input is signed, that is why 2-complement must be used
                signal_max <= '{default: -14'sd8192};

            end else begin

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
                        signal_width <= '{default: 32'd0}; // Reset all channels
                        signal_area  <= '{default: 32'd0}; // Reset all channels
                        signal_max   <= '{default: -14'sd8192}; // Reset all channels
                        
                        signal_width[droplet_sensing_address] <= 32'd1;
                        signal_area[droplet_sensing_address] <= signal_area[droplet_sensing_address] + adc_values[droplet_sensing_address];
                        signal_max[droplet_sensing_address] <= adc_values[droplet_sensing_address];

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
                if (adc_values[mux_addr_i] > signal_max[mux_addr_i]) begin
                    signal_max[mux_addr_i] <= adc_values[mux_addr_i];
                end

                // Width
                if (min_intensity[mux_addr_i]) begin
                    // TODO handle interpolation
                    signal_width[mux_addr_i] <= signal_width[mux_addr_i] + 32'd1;
                end

                // TODO Area
                signal_area[mux_addr_i] <= signal_area[mux_addr_i] + adc_values[mux_addr_i];

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
            
            // State transition
            if (fads_reset || !adc_rstn_i)
                state <= 4'h0;
            else begin
                debug <= 6'b001000;
                muxing_channels_o <= droplet_sensing_channel;
                
                // Update output
                if (droplet_positive || droplet_negative) begin
                    droplet_id <= droplet_id + 32'd1;
                    for (i = 0; i < CHNL; i = i + 1) begin
                        cur_droplet_width[i] <= signal_width[i]; // cur_droplet_width gets value from signal_width
                        cur_droplet_intensity[i] <= signal_max[i]; // cur_droplet_intensity gets value from signal_max
                        cur_droplet_area[i] <= signal_area[i]; // cur_droplet_area gets value from signal_area
                    end
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
    
                    droplet_classification[ 9] <= 1'b0;
                    droplet_classification[10] <= 1'b0;
                    droplet_classification[11] <= 1'b0;
                    droplet_classification[12] <= 1'b0;
                    droplet_classification[13] <= 1'b0;
    
                    droplet_classification[14] <= sort_trig;
                    droplet_classification[15] <= droplet_positive;
                end
                if (sort_enable && droplet_positive) begin
                    sort_delay_end_us <= general_timer_us + sort_delay;
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
        end
        default: debug <= 8'b11111111;
    endcase
end

// System bus
// Setting up necessary wires
wire sys_en;
assign sys_en = sys_wen | sys_ren;

// Reading from system bus
always @(posedge adc_clk_i)
    // Necessary handling of reset signal
    if (adc_rstn_i == 1'b0) begin
        // Resetting to default values
        min_intensity_threshold  <= '{CHNL{-14'sd175}}; // Should roughly correspond to -0.5V
        low_intensity_threshold  <= '{CHNL{-14'sd150}}; // On the specific RedPitaya I'm testing on
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
        // Writing to system bus
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
            20'h01000: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},  min_intensity_threshold[0]}  ; end // these inputs are written back to the system bus as standard procedure in FPGA development
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


            20'h00020: begin sys_ack <= sys_en;  sys_rdata <= {{32-   1{1'b0}},               fads_reset}     ; end // used for trouble shooting and in the interface to reset sorter and values including droplet id

            20'h00024: begin sys_ack <= sys_en;  sys_rdata <= {{32-   1{1'b0}},               sort_delay}     ; end
            20'h00028: begin sys_ack <= sys_en;  sys_rdata <= {{32-   1{1'b0}},            sort_duration}     ; end

//            20'h00100: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},   low_intensity_droplets}     ; end
//            20'h00104: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},  high_intensity_droplets}     ; end
//            20'h00108: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},           short_droplets}     ; end
//            20'h0010c: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},            long_droplets}     ; end
//            20'h00110: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},        positive_droplets}     ; end

            20'h00200: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},               droplet_id}    ; end // unique droplet identifier of the last fully analysed droplet
            
            20'h00204: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},    cur_droplet_intensity[0]} ; end // output of the droplet sorter for each channel
            20'h00208: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},    cur_droplet_intensity[1]} ; end
            20'h0020C: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},    cur_droplet_intensity[2]} ; end
            20'h00210: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},    cur_droplet_intensity[3]} ; end
            20'h00214: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},    cur_droplet_intensity[4]} ; end
            20'h00218: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},    cur_droplet_intensity[5]} ; end

            20'h0021C: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},        cur_droplet_width[0]} ; end
            20'h00220: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},        cur_droplet_width[1]} ; end
            20'h00224: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},        cur_droplet_width[2]} ; end
            20'h00228: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},        cur_droplet_width[3]} ; end
            20'h0022C: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},        cur_droplet_width[4]} ; end
            20'h00230: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},        cur_droplet_width[5]} ; end

            20'h00234: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},          cur_droplet_area[0]} ; end
            20'h00238: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},          cur_droplet_area[1]} ; end
            20'h0023C: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},          cur_droplet_area[2]} ; end
            20'h00240: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},          cur_droplet_area[3]} ; end
            20'h00244: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},          cur_droplet_area[4]} ; end
            20'h00248: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},          cur_droplet_area[5]} ; end

            20'h0024C: begin sys_ack <= sys_en;  sys_rdata <= {{32-  16{1'b0}},   droplet_classification}     ; end // results of the state machine droplet classification
            20'h00250: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},              cur_time_us}     ; end // real time value fast changing

            20'h00300: begin sys_ack <= sys_en;  sys_rdata <= {{32-CHNL{1'b0}},         enabled_channels}     ; end // bolean, starting with channel one as the digit (0/1) on the right
            20'h00304: begin sys_ack <= sys_en;  sys_rdata <= {{32-   3{1'b0}},  droplet_sensing_address}     ; end // number 0-5 this indicates the master channel which should be seleced to have a homogenious, droplet-wide fluorescence signal, not beads or cells. It's used to define where droplets start and finish across channels 

            20'h00308: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},                  adc_a_i}     ; end // real time value fast changing
            20'h0030C: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},            adc_values[0]}     ; end // ADC value for each channel seperately (only one active at a time during multiplexing)
            20'h00310: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},            adc_values[1]}     ; end
            20'h00314: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},            adc_values[2]}     ; end
            20'h00318: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},            adc_values[3]}     ; end
            20'h0031C: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},            adc_values[4]}     ; end
            20'h00320: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},            adc_values[5]}     ; end

            20'h10000: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},          cur_adc_data[0]}     ; end // Averaged raw voltage data for channel 0 during one multiplexing recording cycle (changing at approx 200kHz)
            20'h10004: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},          cur_adc_data[1]}     ; end // Averaged raw voltage data for channel 1
            20'h10008: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},          cur_adc_data[2]}     ; end // Averaged raw voltage data for channel 2
            20'h1000C: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},          cur_adc_data[3]}     ; end // ...
            20'h10010: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},          cur_adc_data[4]}     ; end
            20'h10014: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},          cur_adc_data[5]}     ; end
            20'h10018: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},             update_cycle}     ; end // Update cycle

//            20'h10000: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},                    32'd0}     ; end
//            20'h10004: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},                    32'd1}     ; end
//            20'h10008: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},                    32'd2}     ; end
//            20'h1000c: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},                    32'd3}     ; end

            default:   begin sys_ack <= sys_en;  sys_rdata <= 32'h0                                 ; end
        endcase
    end
endmodule
