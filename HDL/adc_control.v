module adc_control #(
    parameter           ADDR_WIDTH = 8,
    parameter           DATA_WIDTH = 16,
    
    parameter           ADDR_ADC_STATUS     =   8'h30,
    parameter           ADDR_ADC_TWAKE_LSB  =   8'h31,      //32-bit value split in half
    parameter           ADDR_ADC_TWAKE_MSB  =   8'h32,      //32-bit value split in half
    parameter           ADDR_ADC_TSAM_LSB   =   8'h33,      //32-bit value split in half
    parameter           ADDR_ADC_TSAM_MSB   =   8'h34,      //32-bit value split in half
    parameter           ADDR_ADC_SINC_OSR   =   8'h35,      //OSR of the sinc3 filter
    parameter           ADDR_ADC_ACC_WINDOW =   8'h36       //averaging window of the filter
)(
    input  wire         clk,                // attach to main clock
    input  wire         rst_n,              // attach to por_n
    
    //SPI interface
    input   wire    [ADDR_WIDTH-1:0]    reg_addr,
    input   wire                        reg_wr_en,
    input   wire    [DATA_WIDTH-1:0]    reg_wr_data,
    input   wire                        reg_rd_en,
    output  reg     [DATA_WIDTH-1:0]    reg_rd_data,
    
    //sequencer interface
    input  wire         adc_start,          // sequencer issued start signal  
    input  wire         adc_done_clear,
    output reg          adc_done,           // ADC operation complete flag
    //ADC control bits
    output reg          adc_sleep,          // SLP signal
    output reg          adc_dac_startup,    // DAC External startup signal
    output reg          adc_rst,            // ADC reset signal
    
    output reg      [1:0]           adc_osr_sel,
    output reg      [2:0]           acc_filter_window
);

    // State encoding
    localparam S0 = 2'd0;
    localparam S1 = 2'd1;
    localparam S2 = 2'd2;
    localparam S3 = 2'd3;
    
    reg [1:0] state;
    
    reg [31:0] counter;
    reg [31:0] adc_twake;
    reg [31:0] adc_tsam;   

    
   //filter configurations
   always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            adc_osr_sel <= 2'b00;
            acc_filter_window <= 3'b000;
        end else begin
            if(reg_wr_en)begin
                case(reg_addr)
                    ADDR_ADC_TWAKE_LSB:
                        adc_twake[15:0]     <= reg_wr_data;
                    ADDR_ADC_TWAKE_MSB:
                        adc_twake[31:16]    <= reg_wr_data;
                    ADDR_ADC_TSAM_LSB:
                        adc_tsam[15:0]      <= reg_wr_data;
                    ADDR_ADC_TSAM_MSB:
                        adc_tsam[31:16]     <= reg_wr_data;
                    ADDR_ADC_SINC_OSR:
                        adc_osr_sel         <= reg_wr_data[1:0];
                    ADDR_ADC_ACC_WINDOW:
                        acc_filter_window   <= reg_wr_data[2:0];
                    default: ;
                endcase
            end
        end
    end    
    
    // FSM sequential logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S0;
            counter    <= 32'd0;
            adc_done   <= 1'b0;                   
        end else begin
            case (state)
                // Reset/Idle
                S0: begin
                    counter    <= 32'd0;
                    if (adc_start)
                        state <= S1;
                end

                // Wait N cycles
                S1: begin
                    if (counter >= adc_twake - 1) begin
                        counter <= 32'd0;
                        state   <= S2;
                    end else begin
                        counter <= counter + 1'b1;
                    end
                end

                // One-cycle state
                S2: begin
                    counter <= 32'd0;
                    state   <= S3;
                end

                // Wait M cycles
                S3: begin
                    if(counter >= adc_tsam-1)begin
                        counter <= 32'd0;
                        state <= S0;
                        adc_done <= 1'b1;
                    end else begin
                        counter <= counter +1'b1;
                    end
                end
                default: state <= S0;
            endcase
            if(adc_done_clear)begin
                adc_done   <= 1'b0;
            end
        end
    end

    // Decoder combinational logic
    always @(*) begin
        adc_sleep               = 1'b0;
        adc_dac_startup         = 1'b0;
        adc_rst                 = 1'b0;

        case (state)
            S0: begin
                adc_sleep           = 1'b1;
                adc_dac_startup     = 1'b0;
                adc_rst             = 1'b1;
            end

            S1: begin
                adc_sleep           = 1'b0;
                adc_dac_startup     = 1'b0;
                adc_rst             = 1'b1;
            end

            S2: begin
                adc_sleep           = 1'b0;
                adc_dac_startup     = 1'b1;
                adc_rst             = 1'b1;
            end

            S3: begin
                adc_sleep           = 1'b0;
                adc_dac_startup     = 1'b1;
                adc_rst             = 1'b0;
            end
        endcase
    end

always @(*) begin
    case (reg_addr)
        ADDR_ADC_STATUS:
            reg_rd_data = {{(DATA_WIDTH-4){1'b0}},adc_done,adc_sleep,adc_dac_startup,adc_rst};
        ADDR_ADC_TWAKE_LSB:
            reg_rd_data = adc_twake[15:0];
        ADDR_ADC_TWAKE_MSB:
            reg_rd_data = adc_twake[31:16];
        ADDR_ADC_TSAM_LSB:
            reg_rd_data = adc_tsam[15:0];
        ADDR_ADC_TSAM_MSB:
            reg_rd_data = adc_tsam[31:16];
        ADDR_ADC_SINC_OSR:
            reg_rd_data = {{(DATA_WIDTH-2){1'b0}},adc_osr_sel};
        ADDR_ADC_ACC_WINDOW:
            reg_rd_data = {{(DATA_WIDTH-3){1'b0}},acc_filter_window};
        default:
            reg_rd_data = {DATA_WIDTH{1'b0}};
    endcase
end

endmodule
