module reg_command #(
    //define SPI register size
    parameter ADDR_WIDTH        = 8,
    parameter DATA_WIDTH        = 16,
    //define SPI accessible address
    parameter ADDR_CMD_ADDR     = 8'h10,
    parameter ADDR_CMD_DATA     = 8'h11,
    parameter ADDR_CMD_CTRL     = 8'h12,
    parameter ADDR_CMD_STATUS   = 8'h13,
    //define command register file size
    parameter CMD_ADDR_WIDTH    = 8,
    parameter CMD_DATA_WIDTH    = 16
)(
    input   wire            clk,
    input   wire            rst_n,
    // SPI interface
    input   wire    [ADDR_WIDTH-1:0]    reg_addr,
    input   wire                        reg_wr_en,
    input   wire    [DATA_WIDTH-1:0]    reg_wr_data,
    input   wire                        reg_rd_en,
    output  reg     [DATA_WIDTH-1:0]    reg_rd_data,
    //command executer interface
    input   wire                            seq_busy,
    input   wire    [CMD_ADDR_WIDTH-1:0]    seq_addr,
    output  reg     [CMD_DATA_WIDTH-1:0]    seq_cmd,
    output  reg                             cmd_valid
);
    //command memory file
    reg [CMD_DATA_WIDTH-1:0]    cmd_mem [0:2**CMD_ADDR_WIDTH-1];
    reg [CMD_ADDR_WIDTH-1:0]    cmd_addr;
    
    //feature: auto-increment. The address pointer automatically moves forward when auto-inc == 1 
    reg auto_inc;
    //feature: error when trying to modify command memory during execution
    reg cmd_acc_err;
    
    integer i;
    
    //command memory output (to sequencer/executor)
    always @(posedge clk)begin
        seq_cmd <= cmd_mem[seq_addr];
    end

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            auto_inc <= 1'b0;
            cmd_acc_err <= 1'b0;
            cmd_addr <= {CMD_ADDR_WIDTH{1'b0}};
            cmd_valid <= 1'b0;
        end else begin
            if (reg_wr_en) begin
                case (reg_addr)
                    ADDR_CMD_ADDR: begin
                        cmd_addr <= reg_wr_data[CMD_ADDR_WIDTH-1:0];
                    end
    
                    ADDR_CMD_DATA: begin
                        if (!seq_busy) begin
                            cmd_mem[cmd_addr] <= reg_wr_data;
                            if (auto_inc)
                                cmd_addr <= cmd_addr + 8'd1;
                        end else begin
                        //error is raised when trying to write while executing commands
                            cmd_acc_err <= 1'b1;
                        end
                    end
    
                    ADDR_CMD_CTRL: begin
                        auto_inc <= reg_wr_data[0];
                        cmd_valid <= reg_wr_data[1];
                        //clear error flag
                        if (reg_wr_data[2])
                            cmd_acc_err <= 1'b0;
                        end
                    default: begin
                    end
                endcase
            end
        end
    end
    
always @(*) begin
    case (reg_addr)
        ADDR_CMD_ADDR:
            reg_rd_data = {{(DATA_WIDTH-CMD_ADDR_WIDTH){1'b0}}, cmd_addr};

        ADDR_CMD_DATA:
            reg_rd_data = cmd_mem[cmd_addr];

        ADDR_CMD_CTRL:
            reg_rd_data = {{(DATA_WIDTH-2){1'b0}}, cmd_acc_err, cmd_valid, auto_inc};

        ADDR_CMD_STATUS:
            reg_rd_data = {{(DATA_WIDTH-2){1'b0}}, cmd_acc_err, seq_busy};

        default:
            reg_rd_data = {DATA_WIDTH{1'b0}};
    endcase
end
    
endmodule
