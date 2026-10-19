module sequencer #(
    //define SPI register size
    parameter   ADDR_WIDTH          = 8,
    parameter   DATA_WIDTH          = 16,
    //define SPI accessible address
    parameter   ADDR_SEQ_ADDR       = 8'h20,        //current command address (program counter)
    parameter   ADDR_SEQ_CMD        = 8'h21,        //current command
    parameter   ADDR_SEQ_ERROR      = 8'h22,        //sequencer error codes
    parameter   ADDR_SEQ_LS         = 8'h23,        //loop stack
    parameter   ADDR_SEQ_LP0        = 8'h24,        //loop 0 counts
    parameter   ADDR_SEQ_LP1        = 8'h25,        //loop 1 counts
    parameter   ADDR_SEQ_WAIT       = 8'h26,        //wait counter
    //define command register file size
    parameter   CMD_ADDR_WIDTH      = 8,
    parameter   CMD_DATA_WIDTH      = 16,
    //define opcode width
    parameter   OPCODE_WIDTH        = 4,
    //define DAC control interface
    parameter   DAC_WIDTH           = 10
)(
    // system reset and clock
    input   wire                            clk,
    input   wire                            rst_n,
    // timer divider settings
    input   wire    [DATA_WIDTH-1:0]        seq_wait_div,
    
    // SPI read interface
    input   wire    [ADDR_WIDTH-1:0]        reg_addr,
    input   wire                            reg_rd_en,
    output  reg     [DATA_WIDTH-1:0]        reg_rd_data,
   
    // one-pulse control (from 0x01 register)
    input   wire                            seq_start,
    input   wire                            seq_abort,
    input   wire                            seq_pause,
    
    // interface with command register files
    input   wire                            cmd_valid,
    output  reg     [CMD_ADDR_WIDTH-1:0]    seq_addr,
    input   wire    [CMD_DATA_WIDTH-1:0]    seq_cmd,
    
    // On chip ADC interface
    output  reg                             adc_start,
    input   wire                            adc_done,
    output  reg                             adc_done_clear,
    // On chip DAC interface
    output  reg     [DAC_WIDTH-1:0]         dac_code,
    
    //auto hibernation setting
    input   wire                            seq_sleep_en,    
    output  reg                             seq_sleep_req,
    
    //status
    output  reg                             seq_busy,
    output  reg                             seq_done,
    output  reg                             seq_error  
    );

//----------------------------------------
// Opcodes
//----------------------------------------
localparam [OPCODE_WIDTH-1:0] OP_NOP        = 4'h0;          // No Operation
localparam [OPCODE_WIDTH-1:0] OP_WAIT       = 4'h1;          // Wait
localparam [OPCODE_WIDTH-1:0] OP_LOOP_START = 4'h2;          // Indicates the start of a loop, needs a corresponding OP_LOOP_END
localparam [OPCODE_WIDTH-1:0] OP_LOOP_END   = 4'h3;          // Indicates the start of a loop, needs a corresponding OP_LOOP_START
localparam [OPCODE_WIDTH-1:0] OP_END        = 4'h4;          // Indicates the end of sequence
localparam [OPCODE_WIDTH-1:0] OP_DAC_SET    = 4'hA;          // Set DAC output base value
localparam [OPCODE_WIDTH-1:0] OP_DAC_MOD    = 4'hB;          // Modify DAC output
localparam [OPCODE_WIDTH-1:0] OP_ADC_START  = 4'hC;          // ADC Start


//----------------------------------------
// States
//----------------------------------------
localparam [2:0] ST_IDLE   = 3'd0;
localparam [2:0] ST_FETCH  = 3'd1;
localparam [2:0] ST_DECODE = 3'd2;
localparam [2:0] ST_WAIT   = 3'd3;
localparam [2:0] ST_DONE   = 3'd4;
localparam [2:0] ST_ERROR  = 3'd5;
localparam [2:0] ST_SLEEP  = 3'd6;
localparam [2:0] ST_ADC    = 3'd7;


//----------------------------------------
// Error Codes
//----------------------------------------
localparam [3:0] ERR_NONE           = 4'd0;
localparam [3:0] ERR_BAD_OPCODE     = 4'd1;
localparam [3:0] ERR_LOOP_OVERFLOW  = 4'd2;
localparam [3:0] ERR_LOOP_UNDERFLOW = 4'd3;
localparam [3:0] ERR_ZERO_LOOP      = 4'd4;

reg [3:0] seq_error_code;

reg [2:0] state;

//loop start address 
reg [CMD_ADDR_WIDTH-1:0]  loop_start_addr [0:1];

// loop counter. There are two loop counters
reg [CMD_DATA_WIDTH-OPCODE_WIDTH-1:0] loop_count    [0:1];

// loop stack pointer
reg [1:0]  loop_sp;

// wait counter
reg [CMD_DATA_WIDTH-OPCODE_WIDTH-1:0] wait_cnt;
reg [CMD_DATA_WIDTH-1:0] wait_div_cnt;

integer i;

always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;                     //return to idle

            //clear program counter
            seq_addr        <= {CMD_ADDR_WIDTH{1'b0}};      
            
            //clear the status
            seq_busy        <= 1'b0;
            seq_done        <= 1'b0;
            seq_error       <= 1'b0;
            
            //clear sleep request
            seq_sleep_req   <= 1'b0;
            
            //clear error codes
            seq_error_code  <= ERR_NONE;
            
            //clear wait counter
            wait_cnt        <= {(CMD_DATA_WIDTH-OPCODE_WIDTH){1'b0}};
            wait_div_cnt    <= {(CMD_DATA_WIDTH){1'b0}};
            
            //clear loop informations
            for (i = 0; i < 2; i = i + 1) begin
                loop_start_addr[i] <= {CMD_ADDR_WIDTH{1'b0}};
                loop_count[i]    <= {(CMD_DATA_WIDTH-OPCODE_WIDTH){1'b0}};
            end
            loop_sp         <= 2'd0;
            
            //clear DAC codes
            dac_code        <= {DAC_WIDTH{1'b0}};
            
            adc_start       <= 1'b0;
            adc_done_clear  <= 1'b0;
            
        end else begin


            // Abort has highest priority
            if (seq_abort) begin
                state           <= ST_IDLE;
                
                // clear program counter
                seq_addr        <= {CMD_ADDR_WIDTH{1'b0}};
                
                // clear status
                seq_busy        <= 1'b0;
                seq_done        <= 1'b0;
                seq_error       <= 1'b0;
                
                // clear sleep request
                seq_sleep_req   <= 1'b0;
                
                //clear error codes
                seq_error_code  <= ERR_NONE;
                
                //clear wait counter
                wait_cnt        <= {(CMD_DATA_WIDTH-OPCODE_WIDTH){1'b0}};
                wait_div_cnt    <= {(CMD_DATA_WIDTH){1'b0}};
                //clear loop informations
                for (i = 0; i < 2; i = i + 1) begin
                    loop_start_addr[i] <= {CMD_ADDR_WIDTH{1'b0}};
                    loop_count[i]    <= {(CMD_DATA_WIDTH-OPCODE_WIDTH){1'b0}};
                end
                loop_sp         <= 2'd0;
                
                // clear DAC codes
                dac_code        <= {DAC_WIDTH{1'b0}};
                
                adc_start       <= 1'b0;
                adc_done_clear  <= 1'b0;
            end

            // Pause freezes the executor state.
            // Outputs like reg_wr_en and irq_pulse are already deasserted above.
            else if (seq_pause && seq_busy) begin
                state <= state;
            end

            else begin
                
                adc_start   <= 1'b0;
                adc_done_clear  <= 1'b0;
                                
                case (state)

                    // ------------------------------------------------
                    // IDLE: wait for start
                    // ------------------------------------------------
                    ST_IDLE: begin
                        seq_busy        <= 1'b0;
                        seq_done        <= 1'b0;
                        seq_error       <= 1'b0;
                        seq_error_code  <= ERR_NONE;
                        loop_sp         <= 2'd0;

                        if (seq_start && cmd_valid) begin
                            seq_busy     <= 1'b1;
                            seq_addr     <= {CMD_ADDR_WIDTH{1'b0}};
                            state        <= ST_FETCH;
                        end
                    end

                    // ------------------------------------------------
                    // FETCH:
                    // Present command address to external command memory.
                    // Note there will be one clock cycle spent for this state
                    // ------------------------------------------------
                    ST_FETCH: begin
                        state    <= ST_DECODE;
                    end

                    // ------------------------------------------------
                    // DECODE / EXECUTE:
                    // Latch instruction and execute simple commands.
                    // ------------------------------------------------
                    ST_DECODE: begin
                        
                        case (seq_cmd[CMD_DATA_WIDTH-1:CMD_DATA_WIDTH-OPCODE_WIDTH])

                            OP_NOP: begin
                                seq_addr    <= seq_addr + 1'b1;
                                state <= ST_FETCH;
                            end

                            OP_WAIT: begin
                                // If WAIT operand is zero, treat as Non-Op.
                                if (seq_cmd[CMD_DATA_WIDTH-OPCODE_WIDTH-1:0] == {(CMD_DATA_WIDTH-OPCODE_WIDTH){1'b0}}) begin
                                    seq_addr    <= seq_addr + 1'b1;
                                    state <= ST_FETCH;
                                end else begin
                                    wait_cnt        <= seq_cmd[CMD_DATA_WIDTH-OPCODE_WIDTH-1:0];
                                    wait_div_cnt    <= seq_wait_div; 
                                    state    <= ST_WAIT;
                                end
                            end
                            
                            OP_LOOP_START: begin
                                // If loop operand is zero, return zero loop error
                                if (seq_cmd[CMD_DATA_WIDTH-OPCODE_WIDTH-1:0] == {(CMD_DATA_WIDTH-OPCODE_WIDTH){1'b0}}) begin
                                    seq_error      <= 1'b1;
                                    seq_error_code <= ERR_ZERO_LOOP;
                                    state      <= ST_ERROR;
                                // If loop stack is already full, return loop overflow error
                                end else if (loop_sp == 2) begin
                                    seq_error      <= 1'b1;
                                    seq_error_code <= ERR_LOOP_OVERFLOW;
                                    state      <= ST_ERROR;
                                
                                end else begin
                                    loop_start_addr[loop_sp] <= seq_addr + 1;           //pc will jump back here
                                    loop_count[loop_sp]    <= seq_cmd[CMD_DATA_WIDTH-OPCODE_WIDTH-1:0];  //register loop count
                                    loop_sp                <= loop_sp + 1'b1;   //increase 1 loop depth

                                    seq_addr    <= seq_addr + 1'b1;
                                    state <= ST_FETCH;
                                end
                            end

                            OP_LOOP_END: begin
                                // if there is no ongoing loop, return loop underflow error
                                if (loop_sp == 2'd0) begin
                                    seq_error      <= 1'b1;
                                    seq_error_code <= ERR_LOOP_UNDERFLOW;
                                    state      <= ST_ERROR;
                                end else begin
                                    // Top of loop stack is loop_sp - 1
                                    if (loop_count[loop_sp - 1'b1] > 1) begin
                                        loop_count[loop_sp - 1'b1] <= loop_count[loop_sp - 1'b1] - 1;
                                        seq_addr <= loop_start_addr[loop_sp - 1'b1];
                                    end else begin
                                        loop_sp <= loop_sp - 1'b1;
                                        seq_addr <= seq_addr + 1'b1;
                                    end

                                    state <= ST_FETCH;
                                end
                            end
                            
                            OP_END: begin
                                seq_busy  <= 1'b0;
                                seq_done  <= 1'b1;
                                state <= ST_DONE;
                            end
                            
                            OP_DAC_SET: begin
                                dac_code <= seq_cmd[DAC_WIDTH-1:0];
                                seq_addr <= seq_addr + 1'b1;
                                state <= ST_FETCH;
                            end
                            
                            OP_DAC_MOD: begin
                                if (seq_cmd[11]) begin
                                    // Decrease with saturation
                                    if (dac_code < seq_cmd[DAC_WIDTH-1:0])
                                        dac_code <= {DAC_WIDTH{1'b0}};
                                    else
                                        dac_code <= dac_code - seq_cmd[DAC_WIDTH-1:0];
                                    end else begin
                                    // Increase with saturation
                                    if ({1'b0, dac_code} + {1'b0, seq_cmd[DAC_WIDTH-1:0]} > 11'd1023)
                                        dac_code <= 10'd1023;
                                    else
                                        dac_code <= dac_code + seq_cmd[DAC_WIDTH-1:0];
                                end
                                seq_addr <= seq_addr + 1'b1;
                                state <= ST_FETCH;
                            end
                            
                            OP_ADC_START: begin
                                adc_start   <= 1'b1;
                                state       <= ST_ADC;
                            end
  

                            default: begin
                                seq_error      <= 1'b1;
                                seq_error_code <= ERR_BAD_OPCODE;
                                state      <= ST_ERROR;
                            end

                        endcase
                    end

                    // ------------------------------------------------
                    // WAIT:
                    // One wait count is consumed per clock.
                    // Pause freezes this state.
                    // ------------------------------------------------
                    ST_WAIT: begin
                        if (wait_div_cnt > 1'b1) begin
                            wait_div_cnt <= wait_div_cnt - 1'b1;
                            state        <= ST_WAIT;
                        end else begin
                            if (wait_cnt > 1'b1) begin
                                wait_div_cnt    <= seq_wait_div;
                                wait_cnt        <= wait_cnt - 1'b1;
                                state           <= ST_WAIT;
                            end else begin
                                wait_cnt        <= 0;
                                wait_div_cnt    <= 0;
                                seq_addr    <= seq_addr + 1'b1;
                                state       <= ST_FETCH;
                            end
                        end
                    end
                    
                    ST_ADC: begin
                        if (!adc_done) begin
                            state       <= ST_ADC;
                        end else begin
                            adc_done_clear  <= 1'b1;
                            seq_addr    <= seq_addr + 1'b1;
                            state       <= ST_FETCH;
                        end
                    end

                    // ------------------------------------------------
                    // DONE:
                    // Hold done high until start is released.
                    // This prevents immediate restart if start is held high.
                    // ------------------------------------------------
                    ST_DONE: begin
                        seq_busy <= 1'b0;

                        if (!seq_start) begin
                            seq_done  <= 1'b0;
                            if (seq_sleep_en) begin
                                state <= ST_SLEEP;
                            end else begin
                                state <= ST_IDLE;
                            end
                        end
                    end

                    // ------------------------------------------------
                    // ERROR:
                    // Hold error until abort or reset.
                    // ------------------------------------------------
                    ST_ERROR: begin
                        seq_busy <= 1'b0;
                        seq_done <= 1'b0;
                    end
                    
                    ST_SLEEP: begin
                        seq_sleep_req <= 1'b1;
                    end

                    default: begin
                        state      <= ST_ERROR;
                        seq_error      <= 1'b1;
                        seq_error_code <= ERR_BAD_OPCODE;
                    end

                endcase
            end
        end
    end

    always @(*) begin
    case (reg_addr)
        ADDR_SEQ_ADDR:
            reg_rd_data = {{(DATA_WIDTH-CMD_ADDR_WIDTH){1'b0}}, seq_addr};
        
        ADDR_SEQ_CMD:
            reg_rd_data = {{(DATA_WIDTH-CMD_DATA_WIDTH){1'b0}}, seq_cmd};
        
        ADDR_SEQ_ERROR:
            reg_rd_data = {{(DATA_WIDTH-4){1'b0}}, seq_error_code};
        
        ADDR_SEQ_LS:
            reg_rd_data = {{(DATA_WIDTH-2){1'b0}}, loop_sp};
        
        ADDR_SEQ_LP0:
            reg_rd_data = {{(DATA_WIDTH-4){1'b0}}, seq_error_code};
        
        ADDR_SEQ_LP1:
            reg_rd_data = {{(DATA_WIDTH-4){1'b0}}, seq_error_code};
        
        ADDR_SEQ_WAIT:
            reg_rd_data = {{(DATA_WIDTH-4){1'b0}}, seq_error_code};

        default:
            reg_rd_data = {DATA_WIDTH{1'b0}};
    endcase
end

    
endmodule
