// Third-order CIC/sinc3 decimator for a 1-bit delta-sigma ADC stream.
// The input bitstream is mapped to signed samples: 1 -> +1, 0 -> -1.
// data_out is the raw sinc3/CIC output. Its DC gain is OSR^3.
module sinc3_filter #(
    parameter integer INTERNAL_WIDTH = 30,
    parameter integer OUTPUT_WIDTH = 30
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     a_sdm,
    input  wire [1:0]               osr_sel,
    output reg  signed [OUTPUT_WIDTH-1:0] data_out,
    output reg                      data_valid_out
);

    reg signed [INTERNAL_WIDTH-1:0] integ1;
    reg signed [INTERNAL_WIDTH-1:0] integ2;
    reg signed [INTERNAL_WIDTH-1:0] integ3;

    reg signed [INTERNAL_WIDTH-1:0] comb1_d;
    reg signed [INTERNAL_WIDTH-1:0] comb2_d;
    reg signed [INTERNAL_WIDTH-1:0] comb3_d;

    // Counts input samples from 0 to OSR-1 before producing one output.
    reg [9:0] decim_count;
    reg [9:0] osr_value;

    wire signed [INTERNAL_WIDTH-1:0] sample;
    wire signed [INTERNAL_WIDTH-1:0] integ1_next;
    wire signed [INTERNAL_WIDTH-1:0] integ2_next;
    wire signed [INTERNAL_WIDTH-1:0] integ3_next;
    wire signed [INTERNAL_WIDTH-1:0] comb1_next;
    wire signed [INTERNAL_WIDTH-1:0] comb2_next;
    wire signed [INTERNAL_WIDTH-1:0] comb3_next;

    // Convert the single-bit ADC code into a centered signed stream.
    assign sample = a_sdm ? {{(INTERNAL_WIDTH-1){1'b0}}, 1'b1} : {INTERNAL_WIDTH{1'b1}};

    // Three cascaded integrators running at the ADC sampling clock.
    assign integ1_next = integ1 + sample;
    assign integ2_next = integ2 + integ1_next;
    assign integ3_next = integ3 + integ2_next;

    // Three cascaded comb stages evaluated only when a decimated sample is taken.
    assign comb1_next = integ3_next - comb1_d;
    assign comb2_next = comb1_next  - comb2_d;
    assign comb3_next = comb2_next  - comb3_d;

    // Select decimation ratio. The raw filter gain is OSR^3.
    always @* begin
        osr_value = 10'd256;

        case (osr_sel)
            2'b00: begin
                osr_value = 10'd256;
            end
            2'b01: begin
                osr_value = 10'd64;
            end
            2'b10: begin
                osr_value = 10'd128;
            end
            2'b11: begin
                osr_value = 10'd512;
            end
        endcase
    end

    // Async active-high reset. data_valid_out pulses for one clk when data_out updates.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            integ1      <= {INTERNAL_WIDTH{1'b0}};
            integ2      <= {INTERNAL_WIDTH{1'b0}};
            integ3      <= {INTERNAL_WIDTH{1'b0}};
            comb1_d     <= {INTERNAL_WIDTH{1'b0}};
            comb2_d     <= {INTERNAL_WIDTH{1'b0}};
            comb3_d     <= {INTERNAL_WIDTH{1'b0}};
            decim_count <= 10'd0;
            data_out    <= {OUTPUT_WIDTH{1'b0}};
            data_valid_out  <= 1'b0;
        end else begin
            integ1     <= integ1_next;
            integ2     <= integ2_next;
            integ3     <= integ3_next;
            data_valid_out <= 1'b0;

            // Latch comb history and output once per OSR input samples.
            if (decim_count >= (osr_value - 10'd1)) begin
                decim_count <= 10'd0;
                comb1_d     <= integ3_next;
                comb2_d     <= comb1_next;
                comb3_d     <= comb2_next;
                data_out    <= comb3_next;
                data_valid_out  <= 1'b1;
            end else begin
                decim_count <= decim_count + 10'd1;
            end
        end
    end

endmodule
