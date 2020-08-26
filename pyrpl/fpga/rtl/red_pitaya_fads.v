/*

General Description:

Fluorescence activated droplet sorting (FADS) module for the RedPitaya.
This module reads a fluorescence signal from the fast inputs and
triggers a waveform on the arbitrary signal generator (ASG) to be amplified
by an external high voltage amplifier to sort fluorescent droplets.

*/

module red_pitaya_fads #(
    parameter RSZ = 14, // RAM size: 2^RSZ,
    parameter DWT = 14, // data width thresholds
    parameter MEM = 32,  // data width RAM
    parameter ALIG = 4'h4, // RAM alignment
//    parameter BUFL = (1<<RSZ)   // fads logger buffer length
//    parameter BUFL = 8'h10   // fads logger buffer length
//    parameter BUFL = 4   // fads logger buffer length
//    parameter signed low_threshold  = 14'b00000000001111,
//    parameter signed high_threshold = 14'b00000011111111
)(
    // ADC
    input                   adc_clk_i       ,   // ADC clock
    input                   adc_rstn_i      ,   // ADC reset - active low
    input signed [14-1: 0]  adc_a_i         ,   // ADC data CHA
//    input       [ 14-1: 0]  adc_b_i         ,   // ADC data CHB

    output reg              sort_trig       ,   // Sorting trigger
    output reg [8-1:0]      debug           ,

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

// Registers for thresholds
// need to be signed for proper comparison with negative voltages
reg signed [DWT -1:0]   min_intensity_threshold;
reg signed [DWT -1:0]   low_intensity_threshold;
reg signed [DWT -1:0]  high_intensity_threshold;

reg [MEM -1:0]  min_width_threshold;
reg [MEM -1:0]  low_width_threshold;
reg [MEM -1:0] high_width_threshold;

// Registers for timers
reg [MEM -1:0] droplet_width_counter = 32'd0;

// Registers for droplet counters;
reg [MEM -1:0]  low_intensity_droplets = 32'd0;
reg [MEM -1:0] high_intensity_droplets = 32'd0;

reg [MEM -1:0] short_droplets = 32'd0;
reg [MEM -1:0]  long_droplets = 32'd0;

reg [MEM -1:0] positive_droplets = 32'd0;
reg [MEM -1:0] negative_droplets = 32'd0;


// State machine
// Intensity
wire      min_intensity;
wire      low_intensity;
wire positive_intensity;
wire     high_intensity;

//reg      min_intensity_reg =  1'b0;
//reg positive_intensity_reg =  1'b0;
//reg     high_intensity_reg =  1'b0;

reg signed [DWT -1:0] droplet_intensity_max = {1'b1, {DWT-2{1'b0}}};

// Width
wire      min_width;
wire      low_width;
wire positive_width;
wire     high_width;

//reg      min_width_reg = 1'b0;
//reg      low_width_reg = 1'b0;
//reg positive_width_reg = 1'b0;
//reg     high_width_reg = 1'b0;

// Maintenance
reg droplet_acquisition_enable = 1'b1;
reg sort_enable = 1'b1;
reg [MEM -1:0] sort_counter = 32'd0;
reg [MEM -1:0] sort_delay_counter = 32'd0;
reg [MEM -1:0] sort_duration = 32'd125000;
reg [MEM -1:0] sort_delay = 32'd31250;
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


// Assigning
assign      min_intensity = adc_a_i >= min_intensity_threshold;

assign      low_intensity = (droplet_intensity_max >=   min_intensity_threshold) && (droplet_intensity_max < low_intensity_threshold);
assign positive_intensity = (droplet_intensity_max >=   low_intensity_threshold) && (droplet_intensity_max < high_intensity_threshold) && min_intensity;
assign     high_intensity =  droplet_intensity_max >=  high_intensity_threshold;

assign      min_width =  droplet_width_counter >=  min_width_threshold;
assign      low_width = (droplet_width_counter >=  min_width_threshold) && (droplet_width_counter <  low_width_threshold);
assign positive_width = (droplet_width_counter >=  low_width_threshold) && (droplet_width_counter < high_width_threshold) && min_width;
assign     high_width =  droplet_width_counter >= high_width_threshold && min_width;


//integer i;
//always @(posedge adc_clk_i) begin
//    logger_wp_cur <= logger_wp;
//end

always @(posedge adc_clk_i) begin
    // Debug
    case (state)
        4'h0 : debug <= 8'b00000001;
        4'h1 : debug <= 8'b00000010;
        4'h2 : debug <= 8'b00000100;
        4'h3 : debug <= 8'b00001000;
        4'h4 : debug <= 8'b00010000;
        4'h5 : debug <= 8'b00100000;
        default: debug <= 8'b11111111;
    endcase

    // Base state | 0
    if (state == 4'h0) begin
        if (fads_reset) begin
            state <= 4'h0;

            negative_droplets       <= 32'd0;
            positive_droplets       <= 32'd0;

            low_intensity_droplets  <= 32'd0;
            high_intensity_droplets <= 32'd0;

            short_droplets          <= 32'd0;
            long_droplets           <= 32'd0;

        end else begin
//            for (i=0; i<BUFL; i=i+1) begin
//                logger_data_buf[i] <= 0;
//            end

//            logger_wp <= {BUFL{1'b0}};

            if (droplet_acquisition_enable) begin
                state <= 4'h1;
            end
        end
    end

    // Wait for Droplet | 1
    if (state == 4'h1) begin
        if (fads_reset)
                state <= 4'h0;
        else begin
            if (min_intensity) begin
                droplet_width_counter <= 32'd1;
                droplet_intensity_max <= adc_a_i;

                state <= 4'h2;
            end
        end
    end

    // Acquiring Droplet | 2
    if (state == 4'h2) begin
        // Intensity
        if (adc_a_i > droplet_intensity_max) begin
            droplet_intensity_max <= adc_a_i;
        end

        // Width
        droplet_width_counter <= droplet_width_counter + 32'd1;

        // State
        if (fads_reset)
                state <= 4'h0;
        else begin
            if (!min_intensity) begin
                state <= 4'h3;
            end
        end
    end

    // Evaluating Droplet | 3
    if (state == 4'h3) begin
        if (positive_intensity && positive_width)
            positive_droplets <= positive_droplets + 32'd1;
        else
            negative_droplets <= negative_droplets + 32'd1;

        if (low_intensity)
            low_intensity_droplets <= low_intensity_droplets + 32'd1;

        if (high_intensity_droplets)
            high_intensity_droplets <= high_intensity_droplets + 32'd1;

        if (low_width)
            short_droplets <= short_droplets + 32'd1;

        if (high_width)
            long_droplets <= long_droplets + 32'd1;

        // Logging
        // getting log data
//        logger_data_buf[logger_wp] <= positive_droplets + negative_droplets;
        // incrementing write pointer
//        logger_wp <= (logger_wp + ALIG) % BUFL;
//        logger_wp <= logger_wp + 4'b0001;
//        logger_wp <= logger_wp + 1;

        // State

        if (fads_reset)
                state <= 4'h0;
        else begin
            if (sort_enable && positive_intensity && positive_width) begin
                sort_counter <= 32'd0;
                sort_delay_counter <= 32'd0;
                state <= 4'h4;
            end else begin
                state <= 4'h0;
            end
        end

    end

    // Sorting Delay | 4
    if (state == 4'h4) begin
        if (fads_reset)
                state <= 4'h0;

        if (sort_delay_counter < sort_delay) begin
            sort_delay_counter <= sort_delay_counter + 32'd1;

        end else begin
            state <= 4'h5;
        end

    end

    // Sorting | 5
    if (state == 4'h5) begin
        if (sort_counter < sort_duration) begin
            sort_counter <= sort_counter + 32'd1;
            sort_trig <= 1'b1;

            if (fads_reset)
                state <= 4'h0;
        end else begin
            sort_trig <= 1'b0;
            state <= 4'h0;
        end

    end

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


// System bus
// setting up necessary wires
wire sys_en;
assign sys_en = sys_wen | sys_ren;

// Reading from system bus
always @(posedge adc_clk_i)
    // Necessary handling of reset signal
    if (adc_rstn_i == 1'b0) begin
        // resetting to default values
         min_intensity_threshold  <= 14'b00000000001111;
         low_intensity_threshold  <= 14'b00000000010000;
        high_intensity_threshold  <= 14'b00000011111111;

             min_width_threshold  <= 32'h00000001;
             low_width_threshold  <= 32'haabbccdd;
            high_width_threshold  <= 32'hccddeeff;

    end else if (sys_wen) begin
        if (sys_addr[19:0]==20'h00000)    min_intensity_threshold    <= sys_wdata[DWT-1:0];
        if (sys_addr[19:0]==20'h00004)    low_intensity_threshold    <= sys_wdata[DWT-1:0];
        if (sys_addr[19:0]==20'h00008)   high_intensity_threshold    <= sys_wdata[DWT-1:0];

        if (sys_addr[19:0]==20'h00010)        min_width_threshold    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h00014)        low_width_threshold    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h00018)       high_width_threshold    <= sys_wdata[MEM-1:0];

        if (sys_addr[19:0]==20'h00020)                 fads_reset    <= sys_wdata[MEM-1:0];

        if (sys_addr[19:0]==20'h00024)                 sort_delay    <= sys_wdata[MEM-1:0];
        if (sys_addr[19:0]==20'h00028)              sort_duration    <= sys_wdata[MEM-1:0];

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
            20'h00000: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},  min_intensity_threshold}     ; end
            20'h00004: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}},  low_intensity_threshold}     ; end
            20'h00008: begin sys_ack <= sys_en;  sys_rdata <= {{32- DWT{1'b0}}, high_intensity_threshold}     ; end

            20'h00010: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},      min_width_threshold}     ; end
            20'h00014: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},      low_width_threshold}     ; end
            20'h00018: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},     high_width_threshold}     ; end

            20'h00020: begin sys_ack <= sys_en;  sys_rdata <= {{32-   1{1'b0}},               fads_reset}     ; end

            20'h00024: begin sys_ack <= sys_en;  sys_rdata <= {{32-   1{1'b0}},               sort_delay}     ; end
            20'h00028: begin sys_ack <= sys_en;  sys_rdata <= {{32-   1{1'b0}},            sort_duration}     ; end


            20'h00100: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},   low_intensity_droplets}     ; end
            20'h00104: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},  high_intensity_droplets}     ; end

            20'h00108: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},           short_droplets}     ; end
            20'h0010c: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},            long_droplets}     ; end

            20'h00110: begin sys_ack <= sys_en;  sys_rdata <= {{32- MEM{1'b0}},        positive_droplets}     ; end

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
