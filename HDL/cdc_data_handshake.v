module cdc_data_handshake #(
    parameter WIDTH = 30
) (
    // Source domain
    input  wire             adc_clk_d,
    input  wire             adc_rst,
    input  wire [WIDTH-1:0] data_in,
    input  wire             data_valid_in,

    // Destination domain
    input  wire             main_clk,
    input  wire             rst_n,
    output reg  [WIDTH-1:0] data_out,
    output reg              data_valid_out
);

    reg [WIDTH-1:0] data_hold;
    reg             req_toggle;

    reg ack_sync1;
    reg ack_sync2;

    reg req_sync1;
    reg req_sync2;
    reg req_seen;

    reg ack_toggle;
    
    reg [1:0] rst_sync_clk1;

    always @(posedge adc_clk_d or posedge adc_rst) begin
        if (adc_rst)
            rst_sync_clk1 <= 2'b11;
        else
            rst_sync_clk1 <= {rst_sync_clk1[0], 1'b0};
    end

    wire reset_clk1 = rst_sync_clk1[1];

    /*
     * Source domain
     *
     * Source is ready when the returned acknowledgement has
     * caught up with the current request state.
     */
    assign src_ready = (ack_sync2 == req_toggle);

    always @(posedge adc_clk_d or posedge reset_clk1) begin
        if (reset_clk1) begin
            ack_sync1 <= 1'b0;
            ack_sync2 <= 1'b0;
        end else begin
            ack_sync1 <= ack_toggle;
            ack_sync2 <= ack_sync1;
        end
    end

    always @(posedge adc_clk_d or posedge reset_clk1) begin
        if (reset_clk1) begin
            data_hold  <= {WIDTH{1'b0}};
            req_toggle <= 1'b0;
        end else if (data_valid_in && src_ready) begin
            data_hold  <= data_in;
            req_toggle <= ~req_toggle;
        end
    end

    /*
     * Synchronize request into destination domain.
     */
    always @(posedge main_clk or negedge rst_n) begin
        if (!rst_n) begin
            req_sync1 <= 1'b0;
            req_sync2 <= 1'b0;
        end else begin
            req_sync1 <= req_toggle;
            req_sync2 <= req_sync1;
        end
    end

    /*
     * Destination domain
     *
     * data_hold has remained stable while the request crossed
     * the synchronizer, so it can now be captured as a bundle.
     */
    always @(posedge main_clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out      <= {WIDTH{1'b0}};
            data_valid_out <= 1'b0;
            req_seen       <= 1'b0;
            ack_toggle     <= 1'b0;
        end else begin
            data_valid_out <= 1'b0;

            if (req_sync2 != req_seen) begin
                data_out       <= data_hold;
                data_valid_out <= 1'b1;
                req_seen       <= req_sync2;
                ack_toggle     <= req_sync2;
            end
        end
    end

endmodule
