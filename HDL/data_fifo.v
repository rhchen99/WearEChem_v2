module data_fifo #(
    //define SPI register size
    parameter ADDR_WIDTH        = 8,
    parameter DATA_WIDTH        = 16,
    //define SPI accessible address
    parameter ADDR_FIFO_STATUS   = 8'h40,
    
    parameter ADDR_FIFO0_DATA    = 8'h41,
    parameter ADDR_FIFO0_COUNT   = 8'h42,
    parameter ADDR_FIFO1_DATA    = 8'h43,
    parameter ADDR_FIFO1_COUNT   = 8'h44,
        
    parameter FIFO_DATA_WIDTH = 16,
    parameter FIFO_DEPTH = 256
)(
    input   wire                        clk,
    input   wire                        rst_n,
    
    input   wire    [ADDR_WIDTH-1:0]    reg_addr,
    input   wire                        reg_rd_en,
    output  reg     [DATA_WIDTH-1:0]    reg_rd_data,
    
    //INTERNAL DATA interface
    input   wire                        fifo_wr_en,
    input   wire    [DATA_WIDTH*2-1:0]  fifo_wr_data,
    
    //general irq flags
    output  wire                        fifo_error,
    output  wire                        fifo_wr_almost_full,
    output  wire                        fifo_rd_almost_empty    
);

wire    fifo_empty0, fifo_empty1;
wire    fifo_full0, fifo_full1;

wire    fifo_almost_empty0, fifo_almost_empty1;
wire    fifo_almost_full0, fifo_almost_full1;

wire    fifo_rd_en0,fifo_rd_en1;

wire    [FIFO_DATA_WIDTH-1:0]           fifo_rd_data0,fifo_rd_data1;
wire    [$clog2(FIFO_DEPTH):0]          fifo_count0,fifo_count1;

assign  fifo_rd_en0 = reg_rd_en & (reg_addr==ADDR_FIFO0_DATA);
assign  fifo_rd_en1 = reg_rd_en & (reg_addr==ADDR_FIFO1_DATA);
assign fifo_rd_empty = (fifo_rd_en0 & fifo_empty0)|(fifo_rd_en1 & fifo_empty1);

assign fifo_wr_full = fifo_wr_en & (fifo_full0|fifo_full1);

assign fifo_rd_almost_empty = (fifo_rd_en0 & fifo_almost_empty0)|(fifo_rd_en1 & fifo_almost_empty1);
assign fifo_wr_almost_full = fifo_wr_en & (fifo_almost_full0 | fifo_almost_full1);
assign fifo_error = fifo_rd_empty | fifo_wr_full;

fifo_sync #(
    .FIFO_DATA_WIDTH(FIFO_DATA_WIDTH),
    .FIFO_DEPTH(FIFO_DEPTH)
) u_fifo0 (
    .clk(clk),
    .rst_n(rst_n),
    .fifo_wr_en(fifo_wr_en),
    .fifo_wr_data(fifo_wr_data[FIFO_DATA_WIDTH-1:0]),
    .fifo_rd_en(fifo_rd_en0),
    .fifo_rd_data(fifo_rd_data0),
    
    .fifo_full(fifo_full0),
    .fifo_almost_full(fifo_almost_full0),
    .fifo_empty(fifo_empty0),
    .fifo_almost_empty(fifo_almost_empty0),
    .fifo_count(fifo_count0)
);

fifo_sync #(
    .FIFO_DATA_WIDTH(FIFO_DATA_WIDTH),
    .FIFO_DEPTH(FIFO_DEPTH)
) u_fifo1 (
    .clk(clk),
    .rst_n(rst_n),
    .fifo_wr_en(fifo_wr_en),
    .fifo_wr_data(fifo_wr_data[FIFO_DATA_WIDTH*2-1:FIFO_DATA_WIDTH]),
    .fifo_rd_en(fifo_rd_en1),
    .fifo_rd_data(fifo_rd_data1),
    
    .fifo_full(fifo_full1),
    .fifo_almost_full(fifo_almost_full1),
    .fifo_empty(fifo_empty1),
    .fifo_almost_empty(fifo_almost_empty1),
    .fifo_count(fifo_count1)
);

always @(*) begin
    case (reg_addr)
        ADDR_FIFO_STATUS:
            reg_rd_data = {{(DATA_WIDTH-8){1'b0}}, fifo_full1, fifo_almost_full1, fifo_empty1, fifo_almost_empty1, fifo_full0, fifo_almost_full0, fifo_empty0, fifo_almost_empty0};
        
        ADDR_FIFO0_DATA:
            reg_rd_data = fifo_rd_data0;
        
        ADDR_FIFO0_COUNT:
            reg_rd_data = fifo_count0;
        
        ADDR_FIFO1_DATA:
            reg_rd_data = fifo_rd_data1;
        
        ADDR_FIFO1_COUNT:
            reg_rd_data = fifo_count1;
        
        
        default:
            reg_rd_data = {DATA_WIDTH{1'b0}};
    endcase
end


endmodule
