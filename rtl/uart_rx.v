// Simple 8N1 UART receiver
// Samples each bit in the middle of the bit period.
// 'valid' pulses high for one clock when 'data' holds a new byte.

module uart_rx #(
    parameter CLK_FREQ = 12_000_000,
    parameter BAUD     = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid
);

    localparam DIV  = CLK_FREQ / BAUD;
    localparam HALF = DIV / 2;

    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    // Two-flop synchronizer for the asynchronous rx pin
    reg rx_s1, rx_s2;
    always @(posedge clk) begin
        rx_s1 <= rx;
        rx_s2 <= rx_s1;
    end

    reg [1:0]  state;
    reg [15:0] cnt;
    reg [2:0]  bit_i;
    reg [7:0]  shift;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= S_IDLE;
            cnt   <= 16'd0;
            bit_i <= 3'd0;
            shift <= 8'd0;
            data  <= 8'd0;
            valid <= 1'b0;
        end else begin
            valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (!rx_s2) begin          // falling edge = start bit
                        cnt   <= 16'd0;
                        state <= S_START;
                    end
                end

                S_START: begin                 // wait to middle of start bit
                    if (cnt == HALF-1) begin
                        cnt <= 16'd0;
                        if (!rx_s2) begin
                            bit_i <= 3'd0;
                            state <= S_DATA;
                        end else
                            state <= S_IDLE;   // glitch, ignore
                    end else
                        cnt <= cnt + 1'b1;
                end

                S_DATA: begin                  // sample at middle of each bit
                    if (cnt == DIV-1) begin
                        cnt   <= 16'd0;
                        shift <= {rx_s2, shift[7:1]};   // LSB first
                        if (bit_i == 3'd7)
                            state <= S_STOP;
                        else
                            bit_i <= bit_i + 1'b1;
                    end else
                        cnt <= cnt + 1'b1;
                end

                S_STOP: begin                  // middle of stop bit
                    if (cnt == DIV-1) begin
                        cnt   <= 16'd0;
                        state <= S_IDLE;
                        if (rx_s2) begin       // valid stop bit
                            data  <= shift;
                            valid <= 1'b1;
                        end
                    end else
                        cnt <= cnt + 1'b1;
                end
            endcase
        end
    end

endmodule