module fpga_top (
    input  wire uart_rx,
    output wire uart_tx,
    output wire led_red,
    output wire led_green,
    output wire led_blue
);

    localparam N     = 4;
    localparam ACT_W = 8;
    localparam ACC_W = 32;

    // --------------------------------------------------
    // Internal 12 MHz oscillator
    // --------------------------------------------------
    wire clk;
    SB_HFOSC #(
        .CLKHF_DIV("0b10")
    ) hfosc (
        .CLKHFPU(1'b1),
        .CLKHFEN(1'b1),
        .CLKHF(clk)
    );

    // Power-on reset
    reg [15:0] rst_cnt = 0;
    wire rst_n = &rst_cnt;
    always @(posedge clk)
        if (!rst_n) rst_cnt <= rst_cnt + 1;

    // --------------------------------------------------
    // Host protocol (115200 8N1)
    //
    //   PC -> FPGA : 32 bytes
    //                  bytes  0..15 = A, row-major, signed INT8
    //                  bytes 16..31 = W, row-major, signed INT8
    //   FPGA -> PC : 65 bytes
    //                  bytes  0..63 = C = A x W, row-major,
    //                                 16 x signed INT32, little-endian
    //                  byte  64     = busy cycle count (start -> done)
    // --------------------------------------------------

    // --------------------------------------------------
    // UART receiver
    // --------------------------------------------------
    wire [7:0] rx_data;
    wire       rx_valid;

    uart_rx #(
        .CLK_FREQ(12_000_000),
        .BAUD(115200)
    ) urx (
        .clk(clk),
        .rst_n(rst_n),
        .rx(uart_rx),
        .data(rx_data),
        .valid(rx_valid)
    );

    // --------------------------------------------------
    // Input matrices (loaded over UART)
    // --------------------------------------------------
    // Incoming bytes are shifted into one 256-bit register (new byte enters
    // at the top). After 32 bytes the first byte (A[0][0]) sits at bit 0:
    //   in_sr[127:0]   = A,   in_sr[255:128] = W
    reg  [2*N*N*ACT_W-1:0] in_sr;
    wire [N*N*ACT_W-1:0]   a_reg = in_sr[N*N*ACT_W-1:0];
    wire [N*N*ACT_W-1:0]   w_reg = in_sr[2*N*N*ACT_W-1:N*N*ACT_W];

    // --------------------------------------------------
    // Systolic array
    // --------------------------------------------------
    reg  start;
    wire busy, done;
    wire signed [N*N*ACC_W-1:0] result_matrix;

    systolic_array_top #(
        .N(N), .ACT_W(ACT_W), .ACC_W(ACC_W)
    ) sa (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .busy(busy),
        .done(done),
        .weight_matrix(w_reg),
        .act_matrix(a_reg),
        .result_matrix(result_matrix)
    );

    // --------------------------------------------------
    // Cycle counter (busy cycles, start -> done)
    // --------------------------------------------------
    reg [7:0] cyc_cnt;
    reg [7:0] cyc_lat;

    always @(posedge clk) begin
        if (!rst_n) begin
            cyc_cnt <= 8'd0;
            cyc_lat <= 8'd0;
        end else begin
            if (start)
                cyc_cnt <= 8'd0;
            else if (busy)
                cyc_cnt <= cyc_cnt + 1'b1;

            if (done)
                cyc_lat <= cyc_cnt;
        end
    end

    // --------------------------------------------------
    // UART transmitter
    // --------------------------------------------------
    reg  [7:0] tx_data;
    reg        tx_valid;
    wire       tx_ready;

    uart_tx #(
        .CLK_FREQ(12_000_000),
        .BAUD(115200)
    ) utx (
        .clk(clk),
        .rst_n(rst_n),
        .data(tx_data),
        .valid(tx_valid),
        .ready(tx_ready),
        .tx(uart_tx)
    );

    wire can_send = tx_ready && !tx_valid;

    // --------------------------------------------------
    // Sequencer:  RX(32 bytes) -> START -> WAIT(done) -> TX(65 bytes)
    // --------------------------------------------------
    localparam S_RX    = 2'd0;
    localparam S_START = 2'd1;
    localparam S_WAIT  = 2'd2;
    localparam S_TX    = 2'd3;

    reg [1:0]  st;
    reg [5:0]  rx_cnt;
    reg [6:0]  tx_idx;
    reg [20:0] tmo;
    reg        ran;

    always @(posedge clk) begin
        if (!rst_n) begin
            st       <= S_RX;
            start    <= 1'b0;
            tx_valid <= 1'b0;
            tx_data  <= 8'd0;
            in_sr    <= {(2*N*N*ACT_W){1'b0}};
            rx_cnt   <= 6'd0;
            tx_idx   <= 7'd0;
            tmo      <= 21'd0;
            ran      <= 1'b0;
        end else begin
            start    <= 1'b0;
            tx_valid <= 1'b0;

            case (st)
                S_RX: begin
                    if (rx_valid) begin
                        tmo <= 21'd0;
                        in_sr <= {rx_data, in_sr[2*N*N*ACT_W-1:8]};

                        if (rx_cnt == 6'd31) begin
                            rx_cnt <= 6'd0;
                            st     <= S_START;
                        end else
                            rx_cnt <= rx_cnt + 1'b1;
                    end
                    else if (rx_cnt != 6'd0) begin
                        // Incomplete frame: drop it after ~100 ms of silence
                        if (tmo == 21'd1_200_000) begin
                            rx_cnt <= 6'd0;
                            tmo    <= 21'd0;
                        end else
                            tmo <= tmo + 1'b1;
                    end
                end

                S_START: begin
                    start <= 1'b1;
                    st    <= S_WAIT;
                end

                S_WAIT: begin
                    if (done) begin
                        ran    <= 1'b1;
                        tx_idx <= 7'd0;
                        st     <= S_TX;
                    end
                end

                S_TX: begin
                    if (can_send) begin
                        tx_valid <= 1'b1;
                        if (tx_idx == 7'd64) begin
                            tx_data <= cyc_lat;
                            tx_idx  <= 7'd0;
                            st      <= S_RX;
                        end else begin
                            tx_data <= result_matrix[tx_idx[5:0]*8 +: 8];
                            tx_idx  <= tx_idx + 1'b1;
                        end
                    end
                end
            endcase
        end
    end

    // --------------------------------------------------
    // LEDs (check polarity on your board; invert if needed)
    //   green = at least one multiply completed
    //   red   = receiving a frame
    //   blue  = array busy / transmitting
    // --------------------------------------------------
    assign led_green = ran;
    assign led_red   = (rx_cnt != 6'd0);
    assign led_blue  = busy | tx_valid;

endmodule