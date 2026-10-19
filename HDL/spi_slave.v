module spi_slave (
    input  wire        clk,
    input  wire        rst_n,

    // SPI pins
    input  wire        spi_cs_n,
    input  wire        spi_sclk,
    input  wire        spi_mosi,
    output reg         spi_miso,

    // Register interface
    output reg  [7:0]  reg_addr,
    output reg  [15:0] reg_wr_data,
    output reg         reg_rd_en,
    output reg         reg_wr_en,
    input  wire [15:0] reg_rd_data
);

    localparam [7:0] CMD_WRITE = 8'h00;
    localparam [7:0] CMD_READ  = 8'h80;

    // ============================================================
    // SPI input synchronizers
    // ============================================================

    reg [2:0] sclk_sync;
    reg [2:0] cs_sync;
    reg [1:0] mosi_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_sync <= 3'b000;
            cs_sync   <= 3'b111;
            mosi_sync <= 2'b00;
        end else begin
            sclk_sync <= {sclk_sync[1:0], spi_sclk};
            cs_sync   <= {cs_sync[1:0], spi_cs_n};
            mosi_sync <= {mosi_sync[0], spi_mosi};
        end
    end

    wire sclk_rising  =  sclk_sync[1] & ~sclk_sync[2];
    wire sclk_falling = ~sclk_sync[1] &  sclk_sync[2];

    wire cs_active    = ~cs_sync[1];
    wire cs_falling   = ~cs_sync[1] & cs_sync[2];
    wire cs_rising    =  cs_sync[1] & ~cs_sync[2];

    wire mosi_sample  = mosi_sync[1];

    // ============================================================
    // SPI receive and transmit logic
    // ============================================================

    reg [31:0] rx_shift;
    reg [15:0] tx_shift;

    reg [7:0] command;
    reg [5:0] bit_count;

    reg       read_pending;
    reg       read_active;

    wire [31:0] rx_shift_next = {
        rx_shift[30:0],
        mosi_sample
    };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_shift     <= 32'd0;
            tx_shift     <= 16'd0;
            command      <= 8'd0;
            bit_count    <= 6'd0;

            read_pending <= 1'b0;
            read_active  <= 1'b0;

            spi_miso     <= 1'b0;

            reg_addr     <= 8'd0;
            reg_wr_data  <= 16'd0;
            reg_rd_en    <= 1'b0;
            reg_wr_en    <= 1'b0;
        end else begin
            // Register strobes default to one system-clock cycle
            reg_rd_en <= 1'b0;
            reg_wr_en <= 1'b0;

            // ----------------------------------------------------
            // Beginning of SPI transaction
            // ----------------------------------------------------

            if (cs_falling) begin
                rx_shift     <= 32'd0;
                tx_shift     <= 16'd0;
                command      <= 8'd0;
                bit_count    <= 6'd0;

                read_pending <= 1'b0;
                read_active  <= 1'b0;

                spi_miso     <= 1'b0;
            end

            // ----------------------------------------------------
            // Capture register read result
            // ----------------------------------------------------

            if (read_pending) begin
                tx_shift     <= reg_rd_data;
                read_pending <= 1'b0;
                read_active  <= 1'b1;
            end

            // ----------------------------------------------------
            // SPI transfer
            // ----------------------------------------------------

            if (cs_active) begin

                // Mode 0: sample MOSI on rising SCLK
                if (sclk_rising) begin
                    rx_shift <= rx_shift_next;

                    case (bit_count)

                        // Last bit of command byte
                        6'd7: begin
                            command <= rx_shift_next[7:0];
                        end

                        // Last bit of address byte
                        6'd15: begin
                            reg_addr <= rx_shift_next[7:0];

                            if (command == CMD_READ) begin
                                reg_rd_en    <= 1'b1;
                                read_pending <= 1'b1;
                            end
                        end

                        // Last bit of complete frame
                        6'd31: begin
                            if (command == CMD_WRITE) begin
                                reg_addr    <= rx_shift_next[23:16];
                                reg_wr_data <= rx_shift_next[15:0];
                                reg_wr_en   <= 1'b1;
                            end
                        end

                        default: begin
                        end
                    endcase

                    if (bit_count < 6'd31)
                        bit_count <= bit_count + 1'b1;
                end

                // Mode 0: update MISO on falling SCLK
                if (sclk_falling) begin
                    if ((bit_count >= 6'd16) &&
                        (bit_count <= 6'd31) &&
                        read_active) begin

                        spi_miso <= tx_shift[15];
                        tx_shift <= {
                            tx_shift[14:0],
                            1'b0
                        };
                    end else begin
                        spi_miso <= 1'b0;
                    end
                end
            end

            // ----------------------------------------------------
            // End or abort of SPI transaction
            // ----------------------------------------------------

            if (cs_rising) begin
                bit_count    <= 6'd0;
                read_pending <= 1'b0;
                read_active  <= 1'b0;
                spi_miso     <= 1'b0;
            end
        end
    end

endmodule