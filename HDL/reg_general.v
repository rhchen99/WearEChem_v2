module reg_general #(
    //define SPI register size
    parameter ADDR_WIDTH        = 8,
    parameter DATA_WIDTH        = 16,
    //define SPI accessible address
    parameter ADDR_CHIP_ID      = 8'h00,
    parameter ADDR_STATUS       = 8'h01,
    parameter ADDR_CTRL         = 8'h02,
    parameter ADDR_CONFIG       = 8'h03,
    parameter ADDR_IRQ_STATUS   = 8'h04,
    parameter ADDR_IRQ_CLEAR    = 8'h05,
    parameter ADDR_DIV          = 8'h06
)(
    input   wire                        clk,                    //main clock
    input   wire                        rst_n,                  //power on reset
    
    //SPI interface
    input   wire    [ADDR_WIDTH-1:0]    reg_addr,
    input   wire                        reg_wr_en,
    input   wire    [DATA_WIDTH-1:0]    reg_wr_data,
    input   wire                        reg_rd_en,
    output  reg     [DATA_WIDTH-1:0]    reg_rd_data,
    
    //wake up controller interface
    input   wire                        startup_complete,
    //sequencer interface
    input   wire                        seq_busy,
    input   wire                        seq_done,
    input   wire                        seq_error,
    //sequencer control signals
    output  wire                        seq_start,
    output  wire                        seq_abort,
    output  wire                        seq_pause,
    //configurations
    output  wire                        seq_sleep_en,
    output  reg     [DATA_WIDTH-1:0]    seq_wait_div,
    
    //fifo interface
    input   wire                        fifo_wr_almost_full,
    input   wire                        fifo_rd_almost_empty,
    input   wire                        fifo_error,
    //interrupt
    output  wire                        irq
);

    localparam IRQ_WAKEUP            = 0;
    localparam IRQ_SEQ_ERROR         = 1;
    localparam IRQ_FIFO_ALMOST_FULL  = 2;
    localparam IRQ_FIFO_ALMOST_EMPTY = 3;    
    localparam IRQ_FIFO_ERROR        = 4;

reg [DATA_WIDTH-1:0] control_out;
reg [DATA_WIDTH-1:0] configs;
reg [DATA_WIDTH-1:0] irq_status;

//configuration registers
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        configs <= {DATA_WIDTH{1'b0}};
        seq_wait_div <= {DATA_WIDTH{1'b0}};
    end else begin
        if(reg_wr_en && (reg_addr == ADDR_CONFIG))begin
            configs <= reg_wr_data;
        end else if (reg_wr_en && (reg_addr == ADDR_DIV))begin
            seq_wait_div <= reg_wr_data;
        end
    end
end

//interrupt registers
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        irq_status <= {DATA_WIDTH{1'b0}};
    end else begin
        
        if(reg_wr_en && (reg_addr == ADDR_IRQ_CLEAR))begin
            irq_status <= irq_status & ~reg_wr_data;
        end

        if(seq_error)begin
            irq_status[IRQ_SEQ_ERROR] <= 1'b1;
        end
        if(startup_complete)begin
            irq_status[IRQ_WAKEUP] <= 1'b1;
        end
        if(fifo_wr_almost_full)begin
            irq_status[IRQ_FIFO_ALMOST_FULL] <= 1'b1;
        end
        if(fifo_rd_almost_empty)begin
            irq_status[IRQ_FIFO_ALMOST_EMPTY] <= 1'b1;
        end
        if(fifo_error)begin
            irq_status[IRQ_FIFO_ERROR] <= 1'b1;
        end         
    end
end


// write one pulse control registers    
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        control_out <= {DATA_WIDTH{1'b0}};
    end else begin
        control_out <= {DATA_WIDTH{1'b0}};
        if(reg_wr_en && (reg_addr == ADDR_CTRL))begin
            control_out <= reg_wr_data;
        end
    end
end

assign seq_start = control_out[0];
assign seq_abort = control_out[1];
assign seq_pause = control_out[2];

assign seq_sleep_en = configs[0];

assign irq = |(irq_status);

always @(*) begin
    case (reg_addr)
        ADDR_CHIP_ID:
            reg_rd_data = 16'hABCD;
        
        ADDR_CONFIG:
            reg_rd_data = configs;
        
        ADDR_STATUS:
            reg_rd_data = {{(DATA_WIDTH-3){1'b0}}, seq_error, seq_done, seq_busy};

        ADDR_IRQ_STATUS:
            reg_rd_data = irq_status;
            
        ADDR_DIV:
            reg_rd_data = seq_wait_div;
        
        default:
            reg_rd_data = {DATA_WIDTH{1'b0}};
    endcase
end

endmodule
