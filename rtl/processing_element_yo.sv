module processing_element #(
    parameter ACT_W = 8,
    parameter ACC_W = 32
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // Weight preload interface
    input  wire signed [ACT_W-1:0]      weight_in,
    input  wire                         weight_load_en,
    output wire signed [ACT_W-1:0]      weight_out,

    // Activation interface
    input  wire signed [ACT_W-1:0]      act_in,
    input  wire                         act_valid_in,

    // Partial-sum interface
    input  wire signed [ACC_W-1:0]      psum_in,
    input  wire                         psum_valid_in,

    // Activation output -> next PE to the right
    output wire signed [ACT_W-1:0]      act_out,
    output wire                         act_valid_out,

    // Partial-sum output -> PE below
    output wire signed [ACC_W-1:0]      psum_out,
    output wire                         psum_valid_out
);

    reg signed [ACT_W-1:0] weight_reg;
    reg signed [ACT_W-1:0] act_reg;
    reg                    act_valid_reg;

    reg signed [ACC_W-1:0] psum_reg;
    reg                    psum_valid_reg;

    // INT8 x INT8 = INT16
    wire signed [(2*ACT_W)-1:0] product;
    // Sign-extended product to accumulator width
    wire signed [ACC_W-1:0] product_ext;

    assign product     = act_reg * weight_reg;
    assign product_ext = {{(ACC_W-(2*ACT_W)){product[(2*ACT_W)-1]}}, product};

    always @(posedge clk) begin
        if (!rst_n) begin
            weight_reg     <= {ACT_W{1'b0}};
            act_reg        <= {ACT_W{1'b0}};
            act_valid_reg  <= 1'b0;
            psum_reg       <= {ACC_W{1'b0}};
            psum_valid_reg <= 1'b0;
        end
        else begin
            // Weight preload
            if (weight_load_en)
                weight_reg <= weight_in;

            // Activation pipeline
            act_reg       <= act_in;
            act_valid_reg <= act_valid_in;

            // MAC: multiply uses CURRENT act_reg; act_in captured for next cycle
            if (act_valid_reg) begin
                psum_reg       <= psum_in + product_ext;
                psum_valid_reg <= 1'b1;
            end
            else begin
                psum_reg       <= {ACC_W{1'b0}};
                psum_valid_reg <= 1'b0;
            end
        end
    end

    assign act_out        = act_reg;
    assign act_valid_out  = act_valid_reg;
    assign psum_out       = psum_reg;
    assign psum_valid_out = psum_valid_reg;
    assign weight_out     = weight_reg;

endmodule