`timescale 1ns/1ps

// Wrapper di misura per sintesi, implementazione e STA in Quartus.
// I registri delimitano i percorsi del cifrario con lo stesso clock.
// Non e un adattatore funzionale ready/valid: i testbench del protocollo
// devono continuare a istanziare direttamente il cifrario.
// La STA richiede comunque vincoli SDC appropriati.

module wrapper_single_cycle (
    input  logic        clk,
    input  logic        reset_n,
    input  logic [7:0]  key,
    input  logic        start_valid,
    output logic        start_ready,
    input  logic        in_valid,
    output logic        in_ready,
    input  logic [15:0] in_data,
    input  logic [1:0]  in_byte_valid,
    input  logic        in_last,
    output logic        out_valid,
    input  logic        out_ready,
    output logic [15:0] out_data,
    output logic [1:0]  out_byte_valid,
    output logic        out_last,
    output logic        busy,
    output logic        protocol_error
);

    logic [7:0]  key_reg;
    logic        start_valid_reg;
    logic        start_ready_dut;
    logic        in_valid_reg;
    logic        in_ready_dut;
    logic [15:0] in_data_reg;
    logic [1:0]  in_byte_valid_reg;
    logic        in_last_reg;
    logic        out_valid_dut;
    logic        out_ready_reg;
    logic [15:0] out_data_dut;
    logic [1:0]  out_byte_valid_dut;
    logic        out_last_dut;
    logic        busy_dut;
    logic        protocol_error_dut;

    // Registri di ingresso e di uscita con reset asincrono attivo basso.
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            key_reg                <= '0;
            start_valid_reg        <= '0;
            start_ready            <= '0;
            in_valid_reg           <= '0;
            in_ready               <= '0;
            in_data_reg            <= '0;
            in_byte_valid_reg      <= '0;
            in_last_reg            <= '0;
            out_valid              <= '0;
            out_ready_reg          <= '0;
            out_data               <= '0;
            out_byte_valid         <= '0;
            out_last               <= '0;
            busy                   <= '0;
            protocol_error         <= '0;
        end else begin
            key_reg                <= key;
            start_valid_reg        <= start_valid;
            start_ready            <= start_ready_dut;
            in_valid_reg           <= in_valid;
            in_ready               <= in_ready_dut;
            in_data_reg            <= in_data;
            in_byte_valid_reg      <= in_byte_valid;
            in_last_reg            <= in_last;
            out_valid              <= out_valid_dut;
            out_ready_reg          <= out_ready;
            out_data               <= out_data_dut;
            out_byte_valid         <= out_byte_valid_dut;
            out_last               <= out_last_dut;
            busy                   <= busy_dut;
            protocol_error         <= protocol_error_dut;
        end
    end

    stream_cipher_dual_lane_single_cycle dut (
        .clk             (clk),
        .reset_n         (reset_n),
        .key             (key_reg),
        .start_valid     (start_valid_reg),
        .start_ready     (start_ready_dut),
        .in_valid        (in_valid_reg),
        .in_ready        (in_ready_dut),
        .in_data         (in_data_reg),
        .in_byte_valid   (in_byte_valid_reg),
        .in_last         (in_last_reg),
        .out_valid       (out_valid_dut),
        .out_ready       (out_ready_reg),
        .out_data        (out_data_dut),
        .out_byte_valid  (out_byte_valid_dut),
        .out_last        (out_last_dut),
        .busy            (busy_dut),
        .protocol_error  (protocol_error_dut)
    );

endmodule
