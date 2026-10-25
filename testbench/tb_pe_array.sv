`timescale 1ns/1ps

module tb_pe_array;

    localparam int N     = 4;
    localparam int ACT_W = 8;
    localparam int ACC_W = 32;

    logic clk;
    logic rst_n;

    // ------------------------------------------------------------
    // Inputs
    // ------------------------------------------------------------

    logic signed [ACT_W-1:0] weight_in [0:N-1];
    logic                    weight_load_en;

    logic signed [ACT_W-1:0] act_in [0:N-1];
    logic                    act_valid_in [0:N-1];

    // ------------------------------------------------------------
    // Outputs
    // ------------------------------------------------------------

    logic signed [ACC_W-1:0] psum_out [0:N-1];
    logic                    psum_valid_out [0:N-1];

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------

    pe_array #(
        .N(N),
        .ACT_W(ACT_W),
        .ACC_W(ACC_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .weight_in(weight_in),
        .weight_load_en(weight_load_en),

        .act_in(act_in),
        .act_valid_in(act_valid_in),

        .psum_out(psum_out),
        .psum_valid_out(psum_valid_out)
    );

    // ------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------

    always #5 clk = ~clk;

    integer i;

    // ------------------------------------------------------------
    // Test
    // ------------------------------------------------------------

    initial begin

        $display("----------------------------------------");
        $display(" 4x4 PE Array Testbench");
        $display("----------------------------------------");

        clk = 1'b0;
        rst_n = 1'b0;

        weight_load_en = 1'b0;

        for (i = 0; i < N; i = i + 1) begin

            weight_in[i]    = '0;
            act_in[i]       = '0;
            act_valid_in[i] = 1'b0;

        end

        // --------------------------------------------------------
        // Reset
        // --------------------------------------------------------

        repeat (2) @(posedge clk);

        rst_n = 1'b1;

        @(posedge clk);

        // --------------------------------------------------------
        // Load identity matrix
        //
        // Column 0:
        // W00=1
        // W10=0
        // W20=0
        // W30=0
        //
        // Column 1:
        // W01=0
        // W11=1
        // ...
        //
        // Because the loader is not used here, we manually provide
        // the correct sequence at the top of each column.
        // --------------------------------------------------------

        $display("");
        $display("Loading identity weights...");

        // Preload cycle 0 -> bottom row
        // W[3][c] = 0
        for (i = 0; i < N; i = i + 1)
            weight_in[i] = 8'sd0;

        weight_load_en = 1'b1;

        @(posedge clk);

        // Preload cycle 1 -> W[2][c] = 0
        for (i = 0; i < N; i = i + 1)
            weight_in[i] = 8'sd0;

        @(posedge clk);

        // Preload cycle 2 -> W[1][c]
        //
        // W[1] = [0 1 0 0]

        weight_in[0] = 8'sd0;
        weight_in[1] = 8'sd1;
        weight_in[2] = 8'sd0;
        weight_in[3] = 8'sd0;

        @(posedge clk);

        // Preload cycle 3 -> W[0][c]
        //
        // W[0] = [1 0 0 0]

        weight_in[0] = 8'sd1;
        weight_in[1] = 8'sd0;
        weight_in[2] = 8'sd0;
        weight_in[3] = 8'sd0;

        @(posedge clk);

        weight_load_en = 1'b0;

        $display("Weight preload complete.");

        // --------------------------------------------------------
        // Send activation rows
        //
        // A =
        //
        //  1 2 3 4
        //  5 6 7 8
        //  9 10 11 12
        //  13 14 15 16
        //
        // For identity W, expected C = A.
        //
        // Row skew:
        //
        // row 0 starts immediately
        // row 1 delayed by 1 cycle
        // row 2 delayed by 2 cycles
        // row 3 delayed by 3 cycles
        // --------------------------------------------------------

        $display("");
        $display("Starting activation stream...");

        // Cycle 0
        act_in[0] = 8'sd1;
        act_in[1] = 8'sd0;
        act_in[2] = 8'sd0;
        act_in[3] = 8'sd0;

        act_valid_in[0] = 1'b1;
        act_valid_in[1] = 1'b0;
        act_valid_in[2] = 1'b0;
        act_valid_in[3] = 1'b0;

        @(posedge clk);

        // Cycle 1
        act_in[0] = 8'sd2;
        act_in[1] = 8'sd5;

        act_valid_in[0] = 1'b1;
        act_valid_in[1] = 1'b1;

        @(posedge clk);

        // Cycle 2
        act_in[0] = 8'sd3;
        act_in[1] = 8'sd6;
        act_in[2] = 8'sd9;

        act_valid_in[0] = 1'b1;
        act_valid_in[1] = 1'b1;
        act_valid_in[2] = 1'b1;

        @(posedge clk);

        // Cycle 3
        act_in[0] = 8'sd4;
        act_in[1] = 8'sd7;
        act_in[2] = 8'sd10;
        act_in[3] = 8'sd13;

        act_valid_in[0] = 1'b1;
        act_valid_in[1] = 1'b1;
        act_valid_in[2] = 1'b1;
        act_valid_in[3] = 1'b1;

        @(posedge clk);

        // Cycle 4
        act_in[0] = 8'sd0;
        act_in[1] = 8'sd8;
        act_in[2] = 8'sd11;
        act_in[3] = 8'sd14;

        act_valid_in[0] = 1'b0;
        act_valid_in[1] = 1'b1;
        act_valid_in[2] = 1'b1;
        act_valid_in[3] = 1'b1;

        @(posedge clk);

        // Cycle 5
        act_in[1] = 8'sd0;
        act_in[2] = 8'sd12;
        act_in[3] = 8'sd15;

        act_valid_in[1] = 1'b0;
        act_valid_in[2] = 1'b1;
        act_valid_in[3] = 1'b1;

        @(posedge clk);

        // Cycle 6
        act_in[2] = 8'sd0;
        act_in[3] = 8'sd16;

        act_valid_in[2] = 1'b0;
        act_valid_in[3] = 1'b1;

        @(posedge clk);

        // Cycle 7
        act_valid_in[3] = 1'b0;

        @(posedge clk);

        // Allow pipeline to drain
        repeat (5) @(posedge clk);

        $display("");
        $display("----------------------------------------");
        $display(" PE ARRAY TEST COMPLETE");
        $display("----------------------------------------");

        $finish;

    end

endmodule
