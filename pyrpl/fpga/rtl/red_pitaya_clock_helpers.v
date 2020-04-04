/*

General Description:

Clock divider for testing stuff

adapted from https://www.fpga4student.com/2017/08/verilog-code-for-clock-divider-on-fpga.html
*/

module red_pitaya_clk_div #(
    parameter DIV = 28'd100
)(
    input clk_i,
    output clk_o
);

reg[27:0] counter=28'd0;
// The frequency of the output clk_out
//  = The frequency of the input clk_in divided by DIVISOR
// For example: Fclk_in = 50Mhz, if you want to get 1Hz signal to blink LEDs
// You will modify the DIVISOR parameter value to 28'd50.000.000
// Then the frequency of the output clk_out = 50Mhz/50.000.000 = 1Hz
always @(posedge clk_i)
    begin
        counter <= counter + 28'd1;
        if (counter >=  (DIV-1))
            counter <= 28'd0;
    end

assign clk_o = (counter < DIV/2)?1'b0:1'b1;

endmodule

