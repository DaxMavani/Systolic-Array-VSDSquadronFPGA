module weight_loader #(
    parameter N     = 4,
    parameter ACT_W = 8
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         enable,

    // Flattened 4x4 weight matrix.
    // Byte 0  = W[0][0] ... Byte 15 = W[3][3]
    input  wire [N*N*ACT_W-1:0]         weight_matrix,

    // Packed weight outputs: column c = weight_out[c*ACT_W +: ACT_W]
    output reg  signed [N*ACT_W-1:0]    weight_out,
    output reg                          load_en,
    output wire                         done
);

    localparam COUNT_W = $clog2(N);

    reg [COUNT_W-1:0] count;

    integer c;
    integer index;

    // Combinational done: asserted on the last preload cycle while
    // enable is still high (count == N-1).
    assign done = enable && (count == N-1);

    always @(*) begin
        load_en    = 1'b0;
        weight_out = {(N*ACT_W){1'b0}};

        for (c = 0; c < N; c = c + 1) begin
            // W[N-1-count][c]
            index = ((N-1-count) * N + c) * ACT_W;
            weight_out[c*ACT_W +: ACT_W] = weight_matrix[index +: ACT_W];
        end

        if (enable)
            load_en = 1'b1;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            count <= {COUNT_W{1'b0}};
        end
        else begin
            if (enable) begin
                if (count == N-1)
                    count <= {COUNT_W{1'b0}};
                else
                    count <= count + 1'b1;
            end
            else begin
                count <= {COUNT_W{1'b0}};
            end
        end
    end

endmodule
