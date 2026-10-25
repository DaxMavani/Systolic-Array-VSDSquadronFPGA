`timescale 1ns/1ps

module tb_systolic_array_top;

    localparam int N     = 4;
    localparam int ACT_W = 8;
    localparam int ACC_W = 32;

    // ------------------------------------------------------------
    // Clock/reset
    // ------------------------------------------------------------

    logic clk;
    logic rst_n;

    // ------------------------------------------------------------
    // Control
    // ------------------------------------------------------------

    logic start;
    logic busy;
    logic done;

    // ------------------------------------------------------------
    // Matrices
    // ------------------------------------------------------------

    logic [N*N*ACT_W-1:0] weight_matrix;
    logic [N*N*ACT_W-1:0] act_matrix;

    logic signed [ACC_W-1:0] result_matrix [0:N*N-1];

    integer i;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------

    systolic_array_top #(
        .N(N),
        .ACT_W(ACT_W),
        .ACC_W(ACC_W)
    ) dut (

        .clk(clk),
        .rst_n(rst_n),

        .start(start),
        .busy(busy),
        .done(done),

        .weight_matrix(weight_matrix),
        .act_matrix(act_matrix),

        .result_matrix(result_matrix)
    );

    // ------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------

    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // Helper: put one signed INT8 value into flattened matrix
    // ------------------------------------------------------------

    task automatic set_weight(
        input integer row,
        input integer col,
        input integer value
    );

        integer index;

        begin

            index = (row*N + col)*ACT_W;

            weight_matrix[index +: ACT_W] = value[ACT_W-1:0];

        end

    endtask

    task automatic set_activation(
        input integer row,
        input integer col,
        input integer value
    );

        integer index;

        begin

            index = (row*N + col)*ACT_W;

            act_matrix[index +: ACT_W] = value[ACT_W-1:0];

        end

    endtask

    // ------------------------------------------------------------
    // Test
    // ------------------------------------------------------------
    
    initial begin
        $dumpfile("waves_top.vcd");   // or "waves_top.fst" if you prefer FST
        $dumpvars(0, tb_systolic_array_top);  // dump entire hierarchy
        $display("");
        $display("========================================");
        $display(" 4x4 SYSTOLIC ARRAY TOP TESTBENCH");
        $display("========================================");

        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;

        weight_matrix = '0;
        act_matrix    = '0;

        // --------------------------------------------------------
        // Reset
        // --------------------------------------------------------

        repeat (2) @(posedge clk);

        rst_n = 1'b1;

        @(posedge clk);

        // --------------------------------------------------------
        // Load identity weight matrix
        //
        // W =
        //
        // 1 0 0 0
        // 0 1 0 0
        // 0 0 1 0
        // 0 0 0 1
        // --------------------------------------------------------

        set_weight(0,0,1);
        set_weight(0,1,0);
        set_weight(0,2,0);
        set_weight(0,3,0);

        set_weight(1,0,0);
        set_weight(1,1,1);
        set_weight(1,2,0);
        set_weight(1,3,0);

        set_weight(2,0,0);
        set_weight(2,1,0);
        set_weight(2,2,1);
        set_weight(2,3,0);

        set_weight(3,0,0);
        set_weight(3,1,0);
        set_weight(3,2,0);
        set_weight(3,3,1);

        // --------------------------------------------------------
        // Load activation matrix
        //
        // A =
        //
        // 1  2  3  4
        // 5  6  7  8
        // 9  10 11 12
        // 13 14 15 16
        // --------------------------------------------------------

        set_activation(0,0,1);
        set_activation(0,1,2);
        set_activation(0,2,3);
        set_activation(0,3,4);

        set_activation(1,0,5);
        set_activation(1,1,6);
        set_activation(1,2,7);
        set_activation(1,3,8);

        set_activation(2,0,9);
        set_activation(2,1,10);
        set_activation(2,2,11);
        set_activation(2,3,12);

        set_activation(3,0,13);
        set_activation(3,1,14);
        set_activation(3,2,15);
        set_activation(3,3,16);

        // --------------------------------------------------------
        // Start
        // --------------------------------------------------------

        $display("");
        $display("Starting matrix multiplication...");

        start = 1'b1;

        @(posedge clk);

        start = 1'b0;

        // --------------------------------------------------------
        // Wait for completion
        // --------------------------------------------------------

        wait(done == 1'b1);

        #1;

        $display("");
        $display("Computation complete.");
        $display("");

        // --------------------------------------------------------
        // Print results
        // --------------------------------------------------------

        $display("Result matrix:");

        for (i = 0; i < N; i = i + 1) begin

            $display(
                "%0d %0d %0d %0d",
                $signed(result_matrix[i*N+0]),
                $signed(result_matrix[i*N+1]),
                $signed(result_matrix[i*N+2]),
                $signed(result_matrix[i*N+3])
            );

        end

        // --------------------------------------------------------
        // Check expected result
        // --------------------------------------------------------

        if ($signed(result_matrix[0])  !== 1  ||
            $signed(result_matrix[1])  !== 2  ||
            $signed(result_matrix[2])  !== 3  ||
            $signed(result_matrix[3])  !== 4  ||

            $signed(result_matrix[4])  !== 5  ||
            $signed(result_matrix[5])  !== 6  ||
            $signed(result_matrix[6])  !== 7  ||
            $signed(result_matrix[7])  !== 8  ||

            $signed(result_matrix[8])  !== 9  ||
            $signed(result_matrix[9])  !== 10 ||
            $signed(result_matrix[10]) !== 11 ||
            $signed(result_matrix[11]) !== 12 ||

            $signed(result_matrix[12]) !== 13 ||
            $signed(result_matrix[13]) !== 14 ||
            $signed(result_matrix[14]) !== 15 ||
            $signed(result_matrix[15]) !== 16) begin

            $display("");
            $display("========================================");
            $display(" FAIL: RESULT MISMATCH");
            $display("========================================");

            $fatal;

        end

        // --------------------------------------------------------
        // PASS
        // --------------------------------------------------------

        $display("");
        $display("========================================");
        $display(" PASS: 4x4 MATRIX MULTIPLICATION");
        $display("========================================");
        $display("");

        $finish;

    end

endmodule
