module pe_array #(
    parameter N      = 4,
    parameter ACT_W  = 8,
    parameter ACC_W  = 32
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // ------------------------------------------------------------
    // Weight preload (packed: column c = weight_in[c*ACT_W +: ACT_W])
    // One weight enters the top of each column.
    // ------------------------------------------------------------
    input  wire signed [N*ACT_W-1:0]    weight_in,
    input  wire                         weight_load_en,

    // ------------------------------------------------------------
    // Activation input to each row (packed)
    // ------------------------------------------------------------
    input  wire signed [N*ACT_W-1:0]    act_in,
    input  wire        [N-1:0]          act_valid_in,

    // ------------------------------------------------------------
    // Bottom-row outputs (packed)
    // ------------------------------------------------------------
    output wire signed [N*ACC_W-1:0]    psum_out,
    output wire        [N-1:0]          psum_valid_out
);

    // Activation wires between columns
    // act_wire[r][c]  -- use flat index: r*(N+1)+c  for width N+1 columns
    wire signed [ACT_W-1:0] act_wire       [0:N-1][0:N];
    wire                    act_valid_wire [0:N-1][0:N];

    // Partial-sum wires between rows
    wire signed [ACC_W-1:0] psum_wire       [0:N][0:N-1];
    wire                    psum_valid_wire [0:N][0:N-1];

    // Weight wires between rows (weight shifts DOWN each column)
    wire signed [ACT_W-1:0] weight_wire [0:N][0:N-1];

    genvar r, c;

    // ------------------------------------------------------------
    // Connect external activation input to column 0
    // ------------------------------------------------------------
    generate
        for (r = 0; r < N; r = r + 1) begin : GEN_ACT_INPUT
            assign act_wire[r][0]       = act_in[r*ACT_W +: ACT_W];
            assign act_valid_wire[r][0] = act_valid_in[r];
        end
    endgenerate

    // ------------------------------------------------------------
    // Top row partial-sum input = zero
    // ------------------------------------------------------------
    generate
        for (c = 0; c < N; c = c + 1) begin : GEN_PSUM_INPUT
            assign psum_wire[0][c]       = {ACC_W{1'b0}};
            assign psum_valid_wire[0][c] = 1'b0;
        end
    endgenerate

    // ------------------------------------------------------------
    // Top of each column receives the external weight-preload input
    // ------------------------------------------------------------
    generate
        for (c = 0; c < N; c = c + 1) begin : GEN_WEIGHT_INPUT
            assign weight_wire[0][c] = weight_in[c*ACT_W +: ACT_W];
        end
    endgenerate

    // ------------------------------------------------------------
    // Instantiate 4x4 PE array
    // ------------------------------------------------------------
    generate
        for (r = 0; r < N; r = r + 1) begin : GEN_ROWS
            for (c = 0; c < N; c = c + 1) begin : GEN_COLS

                processing_element #(
                    .ACT_W(ACT_W),
                    .ACC_W(ACC_W)
                ) pe_inst (
                    .clk(clk),
                    .rst_n(rst_n),

                    // Weight moves vertically, one row per cycle
                    .weight_in(weight_wire[r][c]),
                    .weight_load_en(weight_load_en),
                    .weight_out(weight_wire[r+1][c]),

                    // Activation moves horizontally
                    .act_in(act_wire[r][c]),
                    .act_valid_in(act_valid_wire[r][c]),

                    // Partial sum moves vertically
                    .psum_in(psum_wire[r][c]),
                    .psum_valid_in(psum_valid_wire[r][c]),

                    // Activation -> right
                    .act_out(act_wire[r][c+1]),
                    .act_valid_out(act_valid_wire[r][c+1]),

                    // Partial sum -> down
                    .psum_out(psum_wire[r+1][c]),
                    .psum_valid_out(psum_valid_wire[r+1][c])
                );

            end
        end
    endgenerate

    // ------------------------------------------------------------
    // Bottom row is the output of the systolic array
    // ------------------------------------------------------------
    generate
        for (c = 0; c < N; c = c + 1) begin : GEN_OUTPUT
            assign psum_out[c*ACC_W +: ACC_W] = psum_wire[N][c];
            assign psum_valid_out[c]          = psum_valid_wire[N][c];
        end
    endgenerate

endmodule