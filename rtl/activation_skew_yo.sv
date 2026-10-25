module activation_skew #(
    parameter N     = 4,
    parameter ACT_W = 8
)(
    input  wire                         enable,

    // Flattened 4x4 activation matrix
    input  wire [N*N*ACT_W-1:0]         act_matrix,

    // Current systolic-array cycle
    input  wire [$clog2(32)-1:0]        cycle_count,

    // Packed outputs: row r = act_out[r*ACT_W +: ACT_W]
    output reg  signed [N*ACT_W-1:0]    act_out,
    output reg         [N-1:0]          act_valid
);

    integer r;
    integer m;
    integer index;

    always @(*) begin
        act_out   = {(N*ACT_W){1'b0}};
        act_valid = {N{1'b0}};

        for (r = 0; r < N; r = r + 1) begin
            // Python model: m = t - r
            m = cycle_count - r;

            if (enable && (m >= 0) && (m < N)) begin
                index = (m * N + r) * ACT_W;
                act_out[r*ACT_W +: ACT_W] = act_matrix[index +: ACT_W];
                act_valid[r] = 1'b1;
            end
        end
    end

endmodule
