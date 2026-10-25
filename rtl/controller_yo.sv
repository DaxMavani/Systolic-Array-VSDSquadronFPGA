module controller #(
    parameter N = 4
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         start,

    input  wire                         preload_done,
    input  wire                         collector_done,

    output reg                          weight_load_en,
    output reg                          activation_enable,
    output reg                          collector_enable,

    output reg  [$clog2(32)-1:0]        cycle_count,

    output reg                          busy,
    output reg                          done
);

    localparam S_IDLE    = 3'd0;
    localparam S_PRELOAD = 3'd1;
    localparam S_RUN     = 3'd2;
    localparam S_FLUSH   = 3'd3;
    localparam S_DONE    = 3'd4;

    reg [2:0] state, next_state;

    // total_cycles = M + 2*(N-1) + 1  (M=N=4 → 11)
    localparam TOTAL_RUN_CYCLES = N + 2*(N-1) + 1;
    localparam COUNT_W = $clog2(TOTAL_RUN_CYCLES + 1);

    reg [COUNT_W-1:0] run_count;

    always @(posedge clk) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            run_count <= {COUNT_W{1'b0}};
        end
        else begin
            state <= next_state;

            if (state == S_RUN) begin
                if (run_count < TOTAL_RUN_CYCLES-1)
                    run_count <= run_count + 1'b1;
                else
                    run_count <= {COUNT_W{1'b0}};
            end
            else begin
                run_count <= {COUNT_W{1'b0}};
            end
        end
    end

    always @(*) begin
        next_state = state;

        case (state)
            S_IDLE: begin
                if (start)
                    next_state = S_PRELOAD;
            end
            S_PRELOAD: begin
                if (preload_done)
                    next_state = S_RUN;
            end
            S_RUN: begin
                if (run_count == TOTAL_RUN_CYCLES-1)
                    next_state = S_FLUSH;
            end
            S_FLUSH: begin
                if (collector_done)
                    next_state = S_DONE;
            end
            S_DONE: begin
                next_state = S_IDLE;
            end
            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

    always @(*) begin
        weight_load_en    = 1'b0;
        activation_enable = 1'b0;
        collector_enable  = 1'b0;
        busy              = 1'b0;
        done              = 1'b0;
        cycle_count       = run_count;

        case (state)
            S_IDLE: begin
                busy = 1'b0;
            end
            S_PRELOAD: begin
                busy           = 1'b1;
                weight_load_en = 1'b1;
            end
            S_RUN: begin
                busy              = 1'b1;
                activation_enable = 1'b1;
                collector_enable  = 1'b1;
            end
            S_FLUSH: begin
                busy             = 1'b1;
                collector_enable = 1'b1;
            end
            S_DONE: begin
                done = 1'b1;
            end
            default: begin
                busy = 1'b0;
            end
        endcase
    end

endmodule