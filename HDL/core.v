module core #(
    parameter ADDR_WIDTH        = 8,
    parameter DATA_WIDTH        = 16,
    
    parameter ADDR_GENERAL      = 4'h0,
    parameter ADDR_CMD          = 4'h1,
    parameter ADDR_SEQ          = 4'h2,
    parameter ADDR_ADC          = 4'h3,
    parameter ADDR_FIFO         = 4'h4,
    
    parameter CMD_ADDR_WIDTH    = 8,
    parameter CMD_DATA_WIDTH    = 16,
    parameter OPCODE_WIDTH      = 4,
    parameter DAC_WIDTH         = 10,
    parameter ADC_DATA_WIDTH    = 30
)(
    input   wire                        por_n,                                  //power on reset
    //clock
    input   wire                        clk,                                    //attach to main clock
    //interrupt
    output  wire                        irq, 
    
    //SPI interface
    input   wire                        spi_sclk,
    input   wire                        spi_cs_n,
    input   wire                        spi_mosi,
    output  wire                        spi_miso,
     
    //wake up controller interface
    input   wire                        startup_complete,                       //startup complete from wu controller
    input   wire                        seq_rst_rel_req,                        //main reset request
    output  wire                        seq_sleep_req,                          //sleep request from sequencer
    
    //DAC interface
    output  wire    [DAC_WIDTH-1:0]     dac_code,
    //ADC interface
    output  wire    adc_sleep,
    output  wire    adc_dac_startup,
    output  wire    adc_rst,
    //ADC filter interface
    output  wire      [1:0]                 adc_osr_sel,
    output  wire      [2:0]                 acc_filter_window,
    //CDC data output
    input   wire                            cdc_data_valid_out,
    input   wire      [ADC_DATA_WIDTH-1:0]  cdc_data_out
);

wire seq_rst_n;

wire [DATA_WIDTH-1:0] seq_wait_div;

wire seq_start,seq_abort,seq_pause;

wire seq_sleep_en;

wire seq_done,seq_error,seq_busy;

wire [DATA_WIDTH-1:0] reg_rd_data_gen,reg_rd_data_seq, reg_rd_data_cmd, reg_rd_data_adc, reg_rd_data_fifo;

wire [CMD_DATA_WIDTH-1:0] seq_cmd;
wire [CMD_ADDR_WIDTH-1:0] seq_addr;
wire cmd_valid;

wire adc_done_clear;
wire adc_start,adc_done;

    //fifo interrupt triggers
wire                        fifo_wr_almost_full;
wire                        fifo_rd_almost_empty;
wire                        fifo_error;

wire    [ADDR_WIDTH-1:0]    reg_addr;
wire                        reg_wr_en;
wire    [DATA_WIDTH-1:0]    reg_wr_data;
wire                        reg_rd_en;
reg     [DATA_WIDTH-1:0]    reg_rd_data;

main_fsm_reset_controller u_main_reset (
        .main_clk              (clk),
        .por_n                 (por_n),
        .main_rst_rel_req      (seq_rst_rel_req),
        .main_rst_n            (seq_rst_n)
);


spi_slave u_spi (
    .clk(clk),
    .rst_n(seq_rst_n),
        
    .spi_sclk(spi_sclk),
    .spi_cs_n(spi_cs_n),
    .spi_miso(spi_miso),
    .spi_mosi(spi_mosi),
    
    .reg_addr(reg_addr),
    .reg_wr_en(reg_wr_en),
    .reg_wr_data(reg_wr_data),
    .reg_rd_en(reg_rd_en),
    .reg_rd_data(reg_rd_data)
);


reg_general #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    
    .ADDR_CHIP_ID(8'h00),
    .ADDR_STATUS(8'h01),
    .ADDR_CTRL(8'h02),
    .ADDR_CONFIG(8'h03),
    .ADDR_IRQ_STATUS(8'h04),
    .ADDR_IRQ_CLEAR(8'h05),
    .ADDR_DIV(8'h06)
    
) u_reg_general(
    .clk(clk),
    .rst_n(por_n),
    
    .irq(irq),
    
    .reg_addr(reg_addr),
    .reg_wr_en(reg_wr_en),
    .reg_wr_data(reg_wr_data),
    .reg_rd_en(reg_rd_en),
    .reg_rd_data(reg_rd_data_gen),
    
    .seq_busy(seq_busy),
    .seq_done(seq_done),
    .seq_error(seq_error),
    
    .seq_start(seq_start),
    .seq_abort(seq_abort),
    .seq_pause(seq_pause),
    .seq_wait_div(seq_wait_div),
    
    .startup_complete(startup_complete),
    
    .fifo_wr_almost_full(fifo_wr_almost_full),
    .fifo_rd_almost_empty(fifo_rd_almost_empty),
    .fifo_error(fifo_error),
    
    .seq_sleep_en(seq_sleep_en)
);

reg_command #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_CMD_ADDR(8'h10),
    .ADDR_CMD_DATA(8'h11),
    .ADDR_CMD_CTRL(8'h12),
    .ADDR_CMD_STATUS(8'h13),
    .CMD_ADDR_WIDTH(CMD_ADDR_WIDTH),
    .CMD_DATA_WIDTH(CMD_DATA_WIDTH)
) u_reg_command(
    .clk(clk),
    .rst_n(por_n),
    
    .reg_addr(reg_addr),
    .reg_wr_en(reg_wr_en),
    .reg_wr_data(reg_wr_data),
    .reg_rd_en(reg_rd_en),
    .reg_rd_data(reg_rd_data_cmd),
    
    .cmd_valid(cmd_valid),
    .seq_busy(seq_busy),
    .seq_addr(seq_addr),
    .seq_cmd(seq_cmd)
);

sequencer #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    
    .ADDR_SEQ_ADDR(8'h20),
    .ADDR_SEQ_CMD(8'h21),
    .ADDR_SEQ_ERROR(8'h22),
    .ADDR_SEQ_LS(8'h23),
    .ADDR_SEQ_LP0(8'h24),
    .ADDR_SEQ_LP1(8'h25),
    .ADDR_SEQ_WAIT(8'h26),
    
    .CMD_ADDR_WIDTH(CMD_ADDR_WIDTH),
    .CMD_DATA_WIDTH(CMD_DATA_WIDTH),
    .OPCODE_WIDTH(OPCODE_WIDTH),
    .DAC_WIDTH(DAC_WIDTH)
) u_sequencer(
    .clk(clk),
    .rst_n(seq_rst_n),
    
    .seq_wait_div(seq_wait_div),
    
    .reg_addr(reg_addr),
    .reg_rd_en(reg_rd_en),
    .reg_rd_data(reg_rd_data_seq),
    
    .dac_code(dac_code),
    .adc_start(adc_start),
    .adc_done(adc_done),
    .adc_done_clear(adc_done_clear),
    
    .seq_addr(seq_addr),
    .seq_cmd(seq_cmd),
    .cmd_valid(cmd_valid),
    
    .seq_busy(seq_busy),
    .seq_done(seq_done),
    .seq_error(seq_error),
    
    .seq_start(seq_start),
    .seq_abort(seq_abort),
    .seq_pause(seq_pause),
    
    .seq_sleep_en(seq_sleep_en),
    .seq_sleep_req(seq_sleep_req)
);

adc_control #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    
    .ADDR_ADC_STATUS(8'h30),
    .ADDR_ADC_TWAKE_LSB(8'h31),
    .ADDR_ADC_TWAKE_MSB(8'h32),
    .ADDR_ADC_TSAM_LSB(8'h33),
    .ADDR_ADC_TSAM_MSB(8'h34),
    .ADDR_ADC_SINC_OSR(8'h35),
    .ADDR_ADC_ACC_WINDOW(8'h36)
    
) u_adc_control (
    .clk(clk),
    .rst_n(por_n),
    
    .reg_addr(reg_addr),
    .reg_wr_en(reg_wr_en),
    .reg_wr_data(reg_wr_data),
    .reg_rd_en(reg_rd_en),
    .reg_rd_data(reg_rd_data_adc),
    
    .adc_start(adc_start),
    .adc_done(adc_done),
    .adc_done_clear(adc_done_clear),
    
    .adc_sleep(adc_sleep),
    .adc_dac_startup(adc_dac_startup),
    .adc_rst(adc_rst),
    .adc_osr_sel(adc_osr_sel),
    .acc_filter_window(acc_filter_window)
);

data_fifo #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    
    .ADDR_FIFO_STATUS(8'h40),
    .ADDR_FIFO0_DATA(8'h41),
    .ADDR_FIFO0_COUNT(8'h42),
    .ADDR_FIFO1_DATA(8'h43),
    .ADDR_FIFO1_COUNT(8'h44),
    
    .FIFO_DATA_WIDTH(DATA_WIDTH),
    .FIFO_DEPTH(256)
) u_fifo (
    
    .clk(clk),
    .rst_n(por_n),
    
    .reg_addr(reg_addr),
    .reg_rd_en(reg_rd_en),
    .reg_rd_data(reg_rd_data_fifo),
    
    .fifo_wr_en(cdc_data_valid_out),
    .fifo_wr_data({2'b00,cdc_data_out}),
    
    .fifo_error(fifo_error),
    .fifo_wr_almost_full(fifo_wr_almost_full),
    .fifo_rd_almost_empty(fifo_rd_almost_empty)
);

always @(*) begin
    case (reg_addr[ADDR_WIDTH-1:ADDR_WIDTH-4])
        ADDR_GENERAL:
            reg_rd_data = reg_rd_data_gen;

        ADDR_CMD:
            reg_rd_data = reg_rd_data_cmd;
            
        ADDR_SEQ:
            reg_rd_data = reg_rd_data_seq;
        
        ADDR_ADC:
            reg_rd_data = reg_rd_data_adc;
        
        ADDR_FIFO:
            reg_rd_data = reg_rd_data_fifo;
             
        default:
            reg_rd_data = {DATA_WIDTH{1'b0}};
    endcase
end
    
endmodule
