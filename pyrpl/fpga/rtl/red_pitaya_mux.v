/*

General Description:

Logic to control an analog multiplexer chip to select inputs for FADS.

*/

module red_pitaya_mux #(
    parameter CHNL = 6  // maximum number of detectors/channels
)(
    input adc_clk_i,
    input adc_rstn_i,
    input [CHNL-1:0] active_channels_i,
    output reg [3-1:0] mux_addr_o
);

reg [16   -1:0] mux_clock_counter = 16'd0;
reg [3-1:0] next_address;
reg [CHNL-1:0] active_rot;
reg next_address_found;
integer i;

always @(posedge adc_clk_i) begin
    if (!adc_rstn_i) begin
        mux_clock_counter <= 16'd0;
        mux_addr_o <= 3'd0;
        next_address <= 3'd0;
        next_address_found <= 0;
    end else begin
        mux_clock_counter <= mux_clock_counter + 16'd1;
        if (mux_clock_counter >= 16'd125) begin
            next_address_found = 0;
            next_address = mux_addr_o;
            active_rot = (active_channels_i >> mux_addr_o | active_channels_i << (CHNL - mux_addr_o));
            for (i = 0; i < CHNL; i = i+1) begin
                if (!next_address_found) begin
                    next_address = next_address + 1;
                    if (next_address >= CHNL) begin
                        next_address = 0;
                    end
                    
                    active_rot = (active_rot >> 1 | active_rot << (CHNL - 1));
                    if (active_rot[0]) begin
                        next_address_found = 1;
                    end
                end
            end

            mux_addr_o = next_address;
            mux_clock_counter <= 16'd0;            
        end
    end
end

endmodule

