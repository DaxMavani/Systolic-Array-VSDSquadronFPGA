`timescale 1ns/1ps

module tb_processing_element;

    localparam int ACT_W = 8;
    localparam int ACC_W = 32;

    // ------------------------------------------------------------
    // Clock and reset
    // ------------------------------------------------------------

    logic clk;
    logic rst_n;

    // ------------------------------------------------------------
    // PE inputs
    // ------------------------------------------------------------

    logic signed [ACT_W-1:0] weight_in;
    logic                    weight_load_en;

    logic signed [ACT_W-1:0] act_in;
    logic                    act_valid_in;

    logic signed [ACC_W-1:0] psum_in;
    logic                    psum_valid_in;

    // ------------------------------------------------------------
    // PE outputs
    // ------------------------------------------------------------

    logic signed [ACT_W-1:0] act_out;
    logic                    act_valid_out;

    logic signed [ACC_W-1:0] psum_out;
    logic                    psum_valid_out;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------

    processing_element #(
        .ACT_W(ACT_W),
        .ACC_W(ACC_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .weight_in(weight_in),
        .weight_load_en(weight_load_en),

        .act_in(act_in),
        .act_valid_in(act_valid_in),

        .psum_in(psum_in),
        .psum_valid_in(psum_valid_in),

        .act_out(act_out),
        .act_valid_out(act_valid_out),

        .psum_out(psum_out),
        .psum_valid_out(psum_valid_out)
    );

    // ------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------

    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // Helper task
    // ------------------------------------------------------------

    task automatic check_value(
        input integer expected_psum,
        input integer expected_act,
        input logic   expected_psum_valid,
        input logic   expected_act_valid
    );

        begin

            if ($signed(psum_out) !== expected_psum) begin

                $display("ERROR: PSUM mismatch");
                $display("  Expected = %0d", expected_psum);
                $display("  Actual   = %0d", $signed(psum_out));

                $fatal;

            end

            if ($signed(act_out) !== expected_act) begin

                $display("ERROR: ACT mismatch");
                $display("  Expected = %0d", expected_act);
                $display("  Actual   = %0d", $signed(act_out));

                $fatal;

            end

            if (psum_valid_out !== expected_psum_valid) begin

                $display("ERROR: PSUM valid mismatch");
                $display("  Expected = %0b", expected_psum_valid);
                $display("  Actual   = %0b", psum_valid_out);

                $fatal;

            end

            if (act_valid_out !== expected_act_valid) begin

                $display("ERROR: ACT valid mismatch");
                $display("  Expected = %0b", expected_act_valid);
                $display("  Actual   = %0b", act_valid_out);

                $fatal;

            end

            $display("PASS: act=%0d psum=%0d",
                     $signed(act_out),
                     $signed(psum_out));

        end

    endtask

    // ------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------

    initial begin

        $display("----------------------------------------");
        $display(" Processing Element Testbench");
        $display("----------------------------------------");

        // Initial values
        clk             = 1'b0;
        rst_n           = 1'b0;

        weight_in       = '0;
        weight_load_en  = 1'b0;

        act_in          = '0;
        act_valid_in    = 1'b0;

        psum_in         = '0;
        psum_valid_in   = 1'b0;

        // --------------------------------------------------------
        // RESET
        // --------------------------------------------------------

        repeat (2) @(posedge clk);

        rst_n = 1'b1;

        @(posedge clk);

        #1;

        check_value(
            0,
            0,
            0,
            0
        );

        // --------------------------------------------------------
        // TEST 1: Load weight = 5
        // --------------------------------------------------------

        $display("");
        $display("TEST 1: Loading weight = 5");

        weight_in      = 8'sd5;
        weight_load_en = 1'b1;

        @(posedge clk);

        #1;

        weight_load_en = 1'b0;

        $display("PASS: Weight loaded");

        // --------------------------------------------------------
        // TEST 2:
        //
        // Send activation = 3
        //
        // Because the PE uses the CURRENT act_reg for the MAC,
        // the activation is first registered.
        // --------------------------------------------------------

        $display("");
        $display("TEST 2: Sending activation = 3");

        act_in        = 8'sd3;
        act_valid_in  = 1'b1;

        psum_in       = 32'sd0;
        psum_valid_in = 1'b0;

        @(posedge clk);

        #1;

        // Activation should now be registered.
        // PSUM is still zero because the OLD activation was zero.

        check_value(
            0,
            3,
            0,
            1
        );

        // --------------------------------------------------------
        // TEST 3:
        //
        // No new activation.
        //
        // Current act_reg = 3
        // weight = 5
        //
        // PSUM = 3 × 5 = 15
        // --------------------------------------------------------

        $display("");
        $display("TEST 3: MAC 3 x 5");

        act_in        = 8'sd0;
        act_valid_in  = 1'b0;

        psum_in       = 32'sd0;
        psum_valid_in = 1'b0;

        @(posedge clk);

        #1;

        check_value(
            15,
            0,
            1,
            0
        );

        // --------------------------------------------------------
        // TEST 4:
        //
        // New activation = 2
        //
        // Current act_reg = 0, so current MAC is zero.
        //
        // This also tests activation replacement.
        // --------------------------------------------------------

        $display("");
        $display("TEST 4: Sending activation = 2");

        act_in        = 8'sd2;
        act_valid_in  = 1'b1;

        psum_in       = 32'sd0;
        psum_valid_in = 1'b0;

        @(posedge clk);

        #1;

        check_value(
            0,
            2,
            0,
            1
        );

        // --------------------------------------------------------
        // TEST 5:
        //
        // Current activation = 2
        // weight = 5
        // incoming psum = 15
        //
        // Result = 15 + (2 × 5)
        //        = 25
        // --------------------------------------------------------

        $display("");
        $display("TEST 5: Accumulation 15 + (2 x 5)");

        act_in        = 8'sd0;
        act_valid_in  = 1'b0;

        psum_in       = 32'sd15;
        psum_valid_in = 1'b1;

        @(posedge clk);

        #1;

        check_value(
            25,
            0,
            1,
            0
        );

        // --------------------------------------------------------
        // TEST 6: Negative values
        //
        // weight = -3
        // activation = -4
        //
        // product = +12
        // --------------------------------------------------------

        $display("");
        $display("TEST 6: Signed multiplication");

        weight_in      = -8'sd3;
        weight_load_en = 1'b1;

        @(posedge clk);

        #1;

        weight_load_en = 1'b0;

        act_in        = -8'sd4;
        act_valid_in  = 1'b1;

        psum_in       = 32'sd0;
        psum_valid_in = 1'b0;

        @(posedge clk);

        #1;

        // Activation is now registered.
        check_value(
            0,
            -4,
            0,
            1
        );

        act_in       = 8'sd0;
        act_valid_in = 1'b0;

        @(posedge clk);

        #1;

        check_value(
            12,
            0,
            1,
            0
        );

        // --------------------------------------------------------
        // DONE
        // --------------------------------------------------------

        $display("");
        $display("----------------------------------------");
        $display(" ALL PE TESTS PASSED");
        $display("----------------------------------------");

        $finish;

    end

endmodule
