module startup_sequencer #(
    parameter integer STARTUP_CYCLES   = 16,
    parameter integer STARTUP_CNT_W    = 5,

    parameter integer GATE_WAIT_CYCLES = 2,
    parameter integer GATE_WAIT_CNT_W  = 2
) (
    input  wire osc_clk,
    input  wire por_n,

    /*
     * Sleep request from the main sequencer.
     *
     * The main sequencer guarantees that all other circuits
     * are already in a safe shutdown state.
     */
    input  wire sleep_req,

    /*
     * Asynchronously captured external wake request.
     */
    input  wire wu_latched,

    /*
     * Oscillator status indication.
     */
    input  wire osc_rdy,

    output reg  wu_latch_rst,             //reset wakeup latch

    output reg  main_clk_en,                //main clock gate enable/disable
    output reg  seq_rst_rel_req,     //release the main sequencer FSM

    output wire osc_en,                     //oscillator enable    
    output reg  startup_complete            //goes into general register
);

    /*
     * State encoding.
     */
    localparam [3:0]
        ST_WAIT_OSC_READY = 4'd0,
        ST_STARTUP_DELAY  = 4'd1,
        ST_ENABLE_CLOCK   = 4'd2,
        ST_RELEASE_RESET  = 4'd3,
        ST_RUN            = 4'd4,
        ST_ASSERT_RESET   = 4'd5,
        ST_GATE_CLOCK     = 4'd6,
        ST_GATE_WAIT      = 4'd7,
        ST_SLEEP          = 4'd8;

    reg [3:0] state;
    reg [3:0] next_state;

    /*
     * Synchronization of osc_ready.
     */
    reg osc_ready_meta;
    reg osc_ready_sync;

    /*
     * Synchronization of sleep_request.
     *
     * main_clk is derived from osc_clk, but synchronizing the
     * request makes the interface more robust.
     */
    reg sleep_req_meta;
    reg sleep_req_sync;

    reg [STARTUP_CNT_W-1:0] startup_counter;
    reg [GATE_WAIT_CNT_W-1:0] gate_wait_counter;

    wire startup_count_done;
    wire gate_wait_done;
    
    reg startup_complete_lvl,startup_complete_pre;

    assign osc_en = wu_latched;
    
    assign sleeping =
        (state == ST_SLEEP);

    assign startup_count_done =
        (startup_counter == STARTUP_CYCLES - 1);

    assign gate_wait_done =
        (gate_wait_counter == GATE_WAIT_CYCLES - 1);
    
    always @(posedge osc_clk or negedge por_n) begin
        if (!por_n) begin
            startup_complete <= 1'b0;
            startup_complete_pre <= 1'b0;
        end else begin
            startup_complete_pre <= startup_complete_lvl;
            startup_complete <= startup_complete_lvl & ~startup_complete_pre;
        end
    end
    
    /*
     * Synchronize oscillator-ready indication.
     *
     * osc_ready_meta and osc_ready_sync are cleared while the
     * sequencer is in sleep.
     */
    always @(posedge osc_clk or negedge por_n) begin
        if (!por_n) begin
            osc_ready_meta <= 1'b0;
            osc_ready_sync <= 1'b0;
        end else if (state == ST_SLEEP) begin
            osc_ready_meta <= 1'b0;
            osc_ready_sync <= 1'b0;
        end else begin
            osc_ready_meta <= osc_rdy;
            osc_ready_sync <= osc_ready_meta;
        end
    end

    /*
     * Synchronize the main-domain sleep request.
     *
     * The main sequencer should hold sleep_request high until
     * main reset is asserted or sleep is entered.
     */
    always @(posedge osc_clk or negedge por_n) begin
        if (!por_n) begin
            sleep_req_meta <= 1'b0;
            sleep_req_sync <= 1'b0;
        end else begin
            sleep_req_meta <= sleep_req;
            sleep_req_sync <= sleep_req_meta;
        end
    end

    /*
     * State register.
     *
     * On power-up, the system starts the oscillator startup
     * sequence and eventually enters ST_RUN.
     */
    always @(posedge osc_clk or negedge por_n) begin
        if (!por_n)
            state <= ST_WAIT_OSC_READY;
        else
            state <= next_state;
    end

    /*
     * Startup stabilization counter.
     */
    always @(posedge osc_clk or negedge por_n) begin
        if (!por_n) begin
            startup_counter <= {STARTUP_CNT_W{1'b0}};
        end else if (state != ST_STARTUP_DELAY) begin
            startup_counter <= {STARTUP_CNT_W{1'b0}};
        end else if (!startup_count_done) begin
            startup_counter <= startup_counter + 1'b1;
        end
    end

    /*
     * Delay between gating main_clk and disabling osc_clk.
     */
    always @(posedge osc_clk or negedge por_n) begin
        if (!por_n) begin
            gate_wait_counter <= {GATE_WAIT_CNT_W{1'b0}};
        end else if (state != ST_GATE_WAIT) begin
            gate_wait_counter <= {GATE_WAIT_CNT_W{1'b0}};
        end else if (!gate_wait_done) begin
            gate_wait_counter <= gate_wait_counter + 1'b1;
        end
    end

    /*
     * Next-state logic.
     */
    always @(*) begin
        next_state = state;

        case (state)
            /*
            * wait for oscillator ready signal
            */
            ST_WAIT_OSC_READY: begin
                if (osc_ready_sync)
                    next_state = ST_STARTUP_DELAY;
            end
            /*
            * wait for oscillator to stabilize
            */
            ST_STARTUP_DELAY: begin
                if (startup_count_done)
                    next_state = ST_ENABLE_CLOCK;
            end
            /*
            * enable system clock
            */
            ST_ENABLE_CLOCK: begin
                next_state = ST_RELEASE_RESET;
            end
            /*
            * release main FSM reset
            */
            ST_RELEASE_RESET: begin
                next_state = ST_RUN;
            end
            /*
            * wait for sleep request
            */
            ST_RUN: begin
                if (sleep_req_sync)
                    next_state = ST_ASSERT_RESET;
            end
            /*
            * reset main FSM
            */
            ST_ASSERT_RESET: begin
                next_state = ST_GATE_CLOCK;
            end
            /*
            * stop system clock
            */
            ST_GATE_CLOCK: begin
                next_state = ST_GATE_WAIT;
            end
            /*
            * wait for system clock to fade away
            */
            ST_GATE_WAIT: begin
                if (gate_wait_done)
                    next_state = ST_SLEEP;
            end
            /*
            * stop oscillator in this state
            */
            ST_SLEEP: begin
                if (wu_latched)
                    next_state = ST_WAIT_OSC_READY;
            end
            
            default: begin
                next_state = ST_WAIT_OSC_READY;
            end
        endcase
    end
    
    

    /*
     * Moore-style output logic.
     */
    always @(*) begin
        wu_latch_rst            = 1'b0;
        main_clk_en             = 1'b0;
        seq_rst_rel_req        = 1'b0;
        startup_complete_lvl    = 1'b0;

        case (state)

            ST_WAIT_OSC_READY: begin
                /*
                 * The wake request has already restarted the
                 * oscillator. Clear the sticky wake event after
                 * it has served its purpose.
                 *
                 * osc_enable remains high because state is no
                 * longer ST_SLEEP.
                 */
                //wu_latch_rst = 1'b1;
            end

            ST_STARTUP_DELAY: begin
                main_clk_en            = 1'b0;
                seq_rst_rel_req       = 1'b0;
            end

            ST_ENABLE_CLOCK: begin
                main_clk_en            = 1'b1;
                seq_rst_rel_req       = 1'b0;
            end

            ST_RELEASE_RESET: begin
                main_clk_en            = 1'b1;
                seq_rst_rel_req       = 1'b1;
            end

            ST_RUN: begin
                main_clk_en            = 1'b1;
                seq_rst_rel_req       = 1'b1;
                startup_complete_lvl   = 1'b1;
            end

            ST_ASSERT_RESET: begin
                /*
                 * Keep main_clk running while reset assertion
                 * propagates into the main domain.
                 */
                main_clk_en            = 1'b1;
                seq_rst_rel_req       = 1'b0;
            end

            ST_GATE_CLOCK: begin
                main_clk_en            = 1'b0;
                seq_rst_rel_req       = 1'b0;
            end

            ST_GATE_WAIT: begin
                /*
                 * main_clk is already stopped.
                 * Raw osc_clk remains enabled because the state
                 * is not yet ST_SLEEP.
                 */
                main_clk_en            = 1'b0;
                seq_rst_rel_req       = 1'b0;
            end

            ST_SLEEP: begin
                main_clk_en            = 1'b0;
                seq_rst_rel_req       = 1'b0;
                wu_latch_rst           = 1'b1;
            end

            default: begin
                main_clk_en            = 1'b0;
                seq_rst_rel_req       = 1'b0;
            end
        endcase
    end

endmodule