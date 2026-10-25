module systolic_array_top #(
    parameter N     = 4,
    parameter ACT_W = 8,
    parameter ACC_W = 32
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // ------------------------------------------------------------
    // Control
    // ------------------------------------------------------------
    input  wire                         start,
    output wire                         busy,
    output wire                         done,

    // ------------------------------------------------------------
    // Input matrices (flattened, byte 0 = [0][0] ... byte 15 = [3][3])
    // ------------------------------------------------------------
    input  wire [N*N*ACT_W-1:0]         weight_matrix,
    input  wire [N*N*ACT_W-1:0]         act_matrix,

    // ------------------------------------------------------------
    // Output matrix (packed row-major)
    // ------------------------------------------------------------
    output wire signed [N*N*ACC_W-1:0]  result_matrix
);

    // ------------------------------------------------------------
    // Controller signals
    // ------------------------------------------------------------
    wire                        weight_load_en;
    wire                        activation_enable;
    wire                        collector_enable;
    wire [$clog2(32)-1:0]       cycle_count;
    wire                        preload_done;
    wire                        collector_done;

    // ------------------------------------------------------------
    // Inter-module packed buses
    // ------------------------------------------------------------
    wire signed [N*ACT_W-1:0]   weight_in;
    wire signed [N*ACT_W-1:0]   act_in;
    wire        [N-1:0]         act_valid_in;
    wire signed [N*ACC_W-1:0]   psum_out;
    wire        [N-1:0]         psum_valid_out;

    // ============================================================
    // CONTROLLER
    // ============================================================
    controller #(
        .N(N)
    ) controller_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .preload_done(preload_done),
        .collector_done(collector_done),
        .weight_load_en(weight_load_en),
        .activation_enable(activation_enable),
        .collector_enable(collector_enable),
        .cycle_count(cycle_count),
        .busy(busy),
        .done(done)
    );

    // ============================================================
    // WEIGHT LOADER
    // ============================================================
    weight_loader #(
        .N(N),
        .ACT_W(ACT_W)
    ) weight_loader_inst (
        .clk(clk),
        .rst_n(rst_n),
        .enable(weight_load_en),
        .weight_matrix(weight_matrix),
        .weight_out(weight_in),
        .load_en(),
        .done(preload_done)
    );

    // ============================================================
    // ACTIVATION SKEW
    // ============================================================
    activation_skew #(
        .N(N),
        .ACT_W(ACT_W)
    ) activation_skew_inst (
        .enable(activation_enable),
        .act_matrix(act_matrix),
        .cycle_count(cycle_count),
        .act_out(act_in),
        .act_valid(act_valid_in)
    );

    // ============================================================
    // 4x4 PE ARRAY
    // ============================================================
    pe_array #(
        .N(N),
        .ACT_W(ACT_W),
        .ACC_W(ACC_W)
    ) pe_array_inst (
        .clk(clk),
        .rst_n(rst_n),
        .weight_in(weight_in),
        .weight_load_en(weight_load_en),
        .act_in(act_in),
        .act_valid_in(act_valid_in),
        .psum_out(psum_out),
        .psum_valid_out(psum_valid_out)
    );

    // ============================================================
    // OUTPUT COLLECTOR
    // ============================================================
    output_collector #(
        .N(N),
        .ACC_W(ACC_W)
    ) output_collector_inst (
        .clk(clk),
        .rst_n(rst_n),
        .enable(collector_enable),
        .psum_in(psum_out),
        .psum_valid_in(psum_valid_out),
        .result_matrix(result_matrix),
        .done(collector_done)
    );

endmodule