/*

General Description:

Clock divider for testing stuff

adapted from https://www.fpga4student.com/2017/08/verilog-code-for-clock-divider-on-fpga.html
*/

module red_pitaya_clk_div #(
    parameter DIV = 32'd125000000
)(
    input clk_i,
    output reg clk_o = 0
);

reg [32-1:0] counter = 0;
// The frequency of the output clk_out
//  = The frequency of the input clk_in divided by DIVISOR
// For example: Fclk_in = 50Mhz, if you want to get 1Hz signal to blink LEDs
// You will modify the DIVISOR parameter value to 28'd50.000.000
// Then the frequency of the output clk_out = 50Mhz/50.000.000 = 1Hz
always @(posedge clk_i)
    begin
        counter <= counter + 32'd1;
        if (counter >=  (DIV-1)) begin
            clk_o <= ~clk_o;
            counter <= 32'd0;
        end
    end
endmodule

