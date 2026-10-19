module main_fsm_reset_controller (
    input  wire main_clk,               //main clock
    input  wire por_n,                  //power on reset

    input  wire main_rst_rel_req,        //reset release request sent by startup sequencer

    output wire main_rst_n              //main sequencer reset
);

    reg [1:0] reset_sync;

    wire async_reset_n;

    assign async_reset_n =
        por_n &&
        main_rst_rel_req;

    /*
     * Reset assertion is asynchronous.
     * Reset release is synchronized to main_clk.
     */
    always @(posedge main_clk or negedge async_reset_n) begin
        if (!async_reset_n)
            reset_sync <= 2'b00;
        else
            reset_sync <= {reset_sync[0], 1'b1};
    end

    assign main_rst_n = reset_sync[1];

endmodule