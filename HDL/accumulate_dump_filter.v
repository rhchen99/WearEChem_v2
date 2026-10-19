// Accumulate-and-dump averager for signed sinc3_filter output samples.
// acc_filter_window selects the averaging window as 2^acc_filter_window samples.
// When acc_filter_window is 0, valid input samples pass directly to data_out.
module accumulate_dump_filter #(
    parameter integer DATA_WIDTH = 30,
    parameter integer ACC_MAX_WINDOW = 7
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire signed [DATA_WIDTH-1:0] data_in,
    input  wire                         data_valid_in,
    input  wire [2:0]                   acc_filter_window,
    output reg  signed [DATA_WIDTH-1:0] data_out,
    output reg                          data_valid_out
);

    localparam integer ACC_WIDTH = DATA_WIDTH + ACC_MAX_WINDOW;

    reg signed [ACC_WIDTH-1:0] acc;
    reg [ACC_MAX_WINDOW-1:0] acc_count;
    // One-clk delayed copy of data_valid_in used to detect a high-to-low edge.
    reg data_valid_in_d;

    wire signed [ACC_WIDTH-1:0] data_ext;
    wire signed [ACC_WIDTH-1:0] acc_next;
    wire [ACC_MAX_WINDOW-1:0] acc_count_final;
    wire data_valid_falling;
    wire acc_count_rdy;

    // Convert the signed 30-bit input to signed 37-bit for internal 37-bit register
    assign data_ext = {{ACC_MAX_WINDOW{data_in[DATA_WIDTH-1]}}, data_in};
    assign acc_next = acc + data_ext;

    // Calculate the counter finish value according to the given filter window
    assign acc_count_final = ({{(ACC_MAX_WINDOW-1){1'b0}}, 1'b1} << acc_filter_window) - 1'b1;
    // Falling edge is true for one clk when previous valid was high and current valid is low.
    assign data_valid_falling = data_valid_in_d && !data_valid_in;
    assign acc_count_rdy = acc_count == acc_count_final;

    // Async active-high reset. A falling edge of data_valid_in triggers this filter,
    // and data_valid_out pulses for one clk when data_out updates.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            acc             <= {ACC_WIDTH{1'b0}};
            acc_count       <= {ACC_MAX_WINDOW{1'b0}};
            data_valid_in_d <= 1'b0;
            data_out        <= {DATA_WIDTH{1'b0}};
            data_valid_out <= 1'b0;
        end else begin
            // Nonblocking assignment lets data_valid_falling use the previous valid value
            // during this clk, then stores the current valid for the next clk.
            data_valid_in_d <= data_valid_in;
            data_valid_out  <= 1'b0;

            if (data_valid_falling) begin
                if (acc_count_rdy) begin
                    data_out       <= acc_next >>> acc_filter_window;
                    data_valid_out <= 1'b1;
                    acc            <= {ACC_WIDTH{1'b0}};
                    acc_count      <= {ACC_MAX_WINDOW{1'b0}};
                end else begin
                    acc       <= acc_next;
                    acc_count <= acc_count + 1'b1;
                end
            end
        end
    end

endmodule
