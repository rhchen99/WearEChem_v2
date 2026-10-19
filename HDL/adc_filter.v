module adc_filter #(
    parameter           ADC_INTERNAL_WIDTH  = 30,
    parameter           ADC_DATA_WIDTH      = 30
)(
    input  wire         adc_rst,                  // attach to adc controller reset
    
    //ADC output
    input wire          adc_clk_d,              // delayed clock from ADC
    input wire          adc_data_1b,            // ADC data output (1-bit)
    
    input wire      [1:0]        adc_osr_sel,
    input wire      [2:0]        acc_filter_window,
    
    //FIFO interface
    output wire     [ADC_DATA_WIDTH-1:0]    acc_data_out,
    output wire                             acc_data_valid_out
    );

wire signed [ADC_DATA_WIDTH-1:0] sinc3_data_out;
wire sinc3_data_valid_out;

reg [1:0] rst_sync_clk1;

always @(posedge adc_clk_d or posedge adc_rst) begin
    if (adc_rst)
        rst_sync_clk1 <= 2'b11;
    else
        rst_sync_clk1 <= {rst_sync_clk1[0], 1'b0};
end

wire reset_clk1 = rst_sync_clk1[1];

sinc3_filter #(
        .INTERNAL_WIDTH(ADC_INTERNAL_WIDTH),
        .OUTPUT_WIDTH(ADC_DATA_WIDTH)
    ) sinc3_dut (
        .clk(adc_clk_d),
        .rst(reset_clk1),
        .a_sdm(adc_data_1b),
        .osr_sel(adc_osr_sel),
        .data_out(sinc3_data_out),
        .data_valid_out(sinc3_data_valid_out)
    );
    
//average filter cascaded after the sinc3 filter
accumulate_dump_filter #(
    .DATA_WIDTH(ADC_DATA_WIDTH)
) acc_dut (
    .clk(adc_clk_d),
    .rst(reset_clk1),
    .data_in(sinc3_data_out),
    .data_valid_in(sinc3_data_valid_out),
    .acc_filter_window(acc_filter_window),
    .data_out(acc_data_out),
    .data_valid_out(acc_data_valid_out)
);
    

endmodule
