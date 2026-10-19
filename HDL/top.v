module top #(
    parameter ADDR_WIDTH        = 8,
    parameter DATA_WIDTH        = 16,
    
    parameter CMD_ADDR_WIDTH    = 8,
    parameter CMD_DATA_WIDTH    = 16,
    parameter OPCODE_WIDTH      = 4,
    parameter DAC_WIDTH         = 10,
    parameter ADC_DATA_WIDTH    = 30
)(
    input   wire                        por_n,
    //clock
    //input   wire                        main_clk,                                //on-chip gated clock
    //interrupt
    output  wire                        irq,
    //wake up latch
    input   wire                        wu_latch_d,
    output  wire                        wu_latch_rst,
    //On-chip oscillator interface
    input   wire                        osc_rdy,
    input   wire                        osc_clk,
    output  wire                        osc_en,
    //main clock gating
    //output  wire                        main_clk_en,
    // SPI interface: Mode 0, MSB first
    input  wire        spi_sclk,//
    input  wire        spi_cs_n,
    input  wire        spi_mosi,
    output wire        spi_miso,
    //ADC interface
    output  wire    adc_sleep,
    output  wire    adc_dac_startup,
    output  wire    adc_rst,
    input   wire    adc_data_1b,
    input   wire    adc_clk_d,
    //DAC interface
    output  wire    [DAC_WIDTH-1:0]     dac_code
    );
    
wire seq_sleep_req, seq_rst_rel_req;

wire [1:0]  adc_osr_sel;
wire [2:0]  acc_filter_window;

wire [ADC_DATA_WIDTH-1:0] cdc_data_out;
wire cdc_data_valid_out;

wire [ADC_DATA_WIDTH-1:0] acc_data_out;
wire acc_data_valid_out;

//reset management
reg [1:0] por_n_sync_main;
reg [1:0] por_n_sync_osc;

wire main_clk, main_clk_en;

always @(posedge main_clk or negedge por_n) begin
    if (!por_n)
        por_n_sync_main <= 2'b00;
    else
        por_n_sync_main <= {por_n_sync_main[0], 1'b1};
end

wire rst_n_main = por_n_sync_main[1];

always @(posedge osc_clk or negedge por_n) begin
    if (!por_n)
        por_n_sync_osc <= 2'b00;
    else
        por_n_sync_osc <= {por_n_sync_osc[0], 1'b1};
end

wire rst_n_osc = por_n_sync_osc[1];


CKLNQD4BWP7T u_icg (
        .CP (osc_clk),
        .E  (main_clk_en),
        .TE (1'b0),
        .Q  (main_clk)
    );

//run with main_clk
core #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    
    .ADDR_GENERAL(4'h0),
    .ADDR_CMD(4'h1),
    .ADDR_SEQ(4'h2),
    .ADDR_ADC(4'h3),
    .ADDR_FIFO(4'h4),
    
    .CMD_ADDR_WIDTH(CMD_ADDR_WIDTH),
    .CMD_DATA_WIDTH(CMD_DATA_WIDTH),
    .OPCODE_WIDTH(OPCODE_WIDTH),
    .DAC_WIDTH(DAC_WIDTH),
    .ADC_DATA_WIDTH(ADC_DATA_WIDTH)
) u_core(
    .por_n(rst_n_main),
    .clk(main_clk),
    .irq(irq),
    
    .spi_sclk(spi_sclk),
    .spi_cs_n(spi_cs_n),
    .spi_mosi(spi_mosi),
    .spi_miso(spi_miso),
    
    .startup_complete(startup_complete),
    .seq_rst_rel_req(seq_rst_rel_req),
    .seq_sleep_req(seq_sleep_req),
    
    .dac_code(dac_code),
    
    .adc_sleep(adc_sleep),
    .adc_dac_startup(adc_dac_startup),
    .adc_rst(adc_rst),
    
    .adc_osr_sel(adc_osr_sel),
    .acc_filter_window(acc_filter_window),
    
    .cdc_data_valid_out(cdc_data_valid_out),
    .cdc_data_out(cdc_data_out)
);

//clock with osc_clk
startup_sequencer #(
        .STARTUP_CYCLES   (16),
        .STARTUP_CNT_W    (5),
        .GATE_WAIT_CYCLES (2),
        .GATE_WAIT_CNT_W  (2)
    ) u_aon_sequencer (
        .por_n                 (rst_n_osc),
        .sleep_req             (seq_sleep_req),
        .wu_latched            (wu_latch_d),
        .osc_en                (osc_en),
        .osc_clk               (osc_clk),
        .osc_rdy               (osc_rdy),
        .wu_latch_rst          (wu_latch_rst),
        .main_clk_en           (main_clk_en),
        .seq_rst_rel_req       (seq_rst_rel_req),
        .startup_complete      (startup_complete)
    );

//clock with adc_clk_d
adc_filter #(
    .ADC_INTERNAL_WIDTH(30),
    .ADC_DATA_WIDTH(30)
) u_adc_filter(
    .adc_rst(adc_rst),
    .adc_clk_d(adc_clk_d),
    .adc_data_1b(adc_data_1b),
    .adc_osr_sel(adc_osr_sel),
    .acc_filter_window(acc_filter_window),
    .acc_data_out(acc_data_out),
    .acc_data_valid_out(acc_data_valid_out)
);

//clock domain crossing: adc clock to main clock
cdc_data_handshake #(
    .WIDTH(30)
) u_cdc (
    .adc_clk_d(adc_clk_d),
    .adc_rst(adc_rst),
    .rst_n(rst_n_main),
    .data_in(acc_data_out),
    .data_valid_in(acc_data_valid_out),
    .main_clk(main_clk),
    .data_out(cdc_data_out),
    .data_valid_out(cdc_data_valid_out)
);


endmodule
