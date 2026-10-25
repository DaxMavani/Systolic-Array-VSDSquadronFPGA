module output_collector #(
    parameter N     = 4,
    parameter ACC_W = 32
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         enable,

    // Packed psums: column c = psum_in[c*ACC_W +: ACC_W]
    input  wire signed [N*ACC_W-1:0]    psum_in,
    input  wire        [N-1:0]          psum_valid_in,

    // Packed result matrix (row-major): element (r,c) at [(r*N+c)*ACC_W +: ACC_W]
    output reg  signed [N*N*ACC_W-1:0]  result_matrix,
    output reg                          done
);

    localparam CW = $clog2(N+1);

    // One small row counter per column. Write addresses are constants per
    // (row, column) pair, so no wide shifters/decoders are generated.
    wire [N-1:0] full;

    genvar c, r;
    generate
        for (c = 0; c < N; c = c + 1) begin : GEN_COL
            reg [CW-1:0] cnt;

            assign full[c] = (cnt >= N);

            always @(posedge clk) begin
                if (!rst_n)
                    cnt <= {CW{1'b0}};
                else if (!enable)
                    cnt <= {CW{1'b0}};          // clear between runs
                else if (psum_valid_in[c] && (cnt < N))
                    cnt <= cnt + 1'b1;
            end

            for (r = 0; r < N; r = r + 1) begin : GEN_ROW
                always @(posedge clk) begin
                    if (!rst_n)
                        result_matrix[(r*N+c)*ACC_W +: ACC_W] <= {ACC_W{1'b0}};
                    else if (enable && psum_valid_in[c] && (cnt == r))
                        result_matrix[(r*N+c)*ACC_W +: ACC_W] <= psum_in[c*ACC_W +: ACC_W];
                end
            end
        end
    endgenerate

    // All N x N results captured when every column holds N results
    always @(posedge clk) begin
        if (!rst_n)
            done <= 1'b0;
        else begin
            done <= 1'b0;
            if (enable && (&full))
                done <= 1'b1;
        end
    end

endmodule