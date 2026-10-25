// Simple 8N1 UART Transmitter
// Works with any clock (we will use 12 MHz)
// Baud rate is set by the parameter

module uart_tx #(
    parameter CLK_FREQ = 12_000_000,
    parameter BAUD     = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       valid,      // pulse high for 1 cycle to send
    output reg        ready,      // high when ready for new byte
    output reg        tx
);

    localparam DIV = CLK_FREQ / BAUD;

    reg [15:0] baud_cnt;
    reg [3:0]  bit_cnt;
    reg [9:0]  shift;             // start + 8 data + stop
    reg        busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx       <= 1'b1;
            ready    <= 1'b1;
            busy     <= 1'b0;
            baud_cnt <= 0;
            bit_cnt  <= 0;
            shift    <= 10'h3FF;
        end else begin
            if (!busy) begin
                ready <= 1'b1;
                if (valid) begin
                    shift    <= {1'b1, data, 1'b0}; // stop, data, start
                    busy     <= 1'b1;
                    ready    <= 1'b0;
                    baud_cnt <= 0;
                    bit_cnt  <= 0;
                end
            end else begin
                ready <= 1'b0;
                if (baud_cnt == DIV-1) begin
                    baud_cnt <= 0;
                    tx       <= shift[0];
                    shift    <= {1'b1, shift[9:1]};
                    if (bit_cnt == 9) begin
                        busy <= 1'b0;
                    end else begin
                        bit_cnt <= bit_cnt + 1;
                    end
                end else begin
                    baud_cnt <= baud_cnt + 1;
                end
            end
        end
    end
endmodule