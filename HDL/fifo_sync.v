module fifo_sync #(
    parameter FIFO_DATA_WIDTH = 16,
    parameter FIFO_DEPTH = 256,
    // derive address width from depth
    parameter FIFO_ADDR_WIDTH = $clog2(FIFO_DEPTH)
)(
    input  wire                         clk,
    input  wire                         rst_n,     // active-low synchronous reset

    // write interface
    input  wire                         fifo_wr_en,     // write enable
    input  wire [FIFO_DATA_WIDTH-1:0]   fifo_wr_data,   // data in

    // read interface
    input  wire                         fifo_rd_en,     // read enable
    output reg  [FIFO_DATA_WIDTH-1:0]   fifo_rd_data,   // data out

    // status
    output wire                         fifo_full,
    output wire                         fifo_almost_full,
    output wire                         fifo_empty,
    output wire                         fifo_almost_empty,
    output reg  [FIFO_ADDR_WIDTH:0]     fifo_count      // how many words currently stored
);

    // ----------------------------------------------------------------
    // Memory array
    // ----------------------------------------------------------------
    reg [FIFO_ADDR_WIDTH-1:0] mem [0:FIFO_DEPTH-1];

    // Read / write pointers
    reg [FIFO_ADDR_WIDTH-1:0] wr_ptr;
    reg [FIFO_ADDR_WIDTH-1:0] rd_ptr;

    // ----------------------------------------------------------------
    // Full / Empty logic
    // ----------------------------------------------------------------
    assign fifo_empty = (fifo_count == 0);
    assign fifo_almost_empty = (fifo_count == 1);
    assign fifo_full  = (fifo_count == FIFO_DEPTH);
    assign fifo_almost_full = (fifo_count == FIFO_DEPTH-1);
    // ----------------------------------------------------------------
    // Write logic
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {FIFO_ADDR_WIDTH{1'b0}};
        end else begin
            if (fifo_wr_en && !fifo_full) begin
                mem[wr_ptr] <= fifo_wr_data;
                // increment write pointer with wrap
                if (wr_ptr == FIFO_DEPTH-1)
                    wr_ptr <= {FIFO_ADDR_WIDTH{1'b0}};
                else
                    wr_ptr <= wr_ptr + 1'b1;
            end
        end
    end

    // ----------------------------------------------------------------
    // Read logic
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr  <= {FIFO_ADDR_WIDTH{1'b0}};
            fifo_rd_data <= {FIFO_DATA_WIDTH{1'b0}};
        end else begin
            if (fifo_rd_en && !fifo_empty) begin
                fifo_rd_data <= mem[rd_ptr];
                // increment read pointer with wrap
                if (rd_ptr == FIFO_DEPTH-1)
                    rd_ptr <= {FIFO_ADDR_WIDTH{1'b0}};
                else
                    rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

    // ----------------------------------------------------------------
    // Count logic
    // ----------------------------------------------------------------
    // count goes up on valid write (no read), down on valid read (no write),
    // unchanged on both or neither
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_count <= {(FIFO_ADDR_WIDTH+1){1'b0}};
        end else begin
            case ({(fifo_wr_en && !fifo_full), (fifo_rd_en && !fifo_empty)})
                2'b10: fifo_count <= fifo_count + 1'b1; // write only
                2'b01: fifo_count <= fifo_count - 1'b1; // read only
                default: fifo_count <= fifo_count;      // same size
            endcase
        end
    end

endmodule
