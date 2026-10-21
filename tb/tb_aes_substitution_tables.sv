`timescale 1ns/1ps

module tb_aes_substitution_tables;
    logic [7:0] input_value;
    logic [7:0] sbox_value;
    logic [7:0] inverse_input_value;
    logic [7:0] inverse_sbox_value;
    integer index;
    integer errors;

    aes_sbox dut_sbox (
        .data_in  (input_value),
        .data_out (sbox_value)
    );

    aes_inv_sbox dut_sbox_inverse (
        .data_in  (inverse_input_value),
        .data_out (inverse_sbox_value)
    );

    initial begin
        errors = 0;

        input_value = 8'h00; #1;
        if (sbox_value !== 8'h63) errors = errors + 1;
        input_value = 8'h53; #1;
        if (sbox_value !== 8'hed) errors = errors + 1;
        input_value = 8'hff; #1;
        if (sbox_value !== 8'h16) errors = errors + 1;

        inverse_input_value = 8'h00; #1;
        if (inverse_sbox_value !== 8'h52) errors = errors + 1;
        inverse_input_value = 8'h52; #1;
        if (inverse_sbox_value !== 8'h48) errors = errors + 1;
        inverse_input_value = 8'hff; #1;
        if (inverse_sbox_value !== 8'h7d) errors = errors + 1;

        for (index = 0; index < 256; index = index + 1) begin
            input_value = index[7:0];
            #1;
            inverse_input_value = sbox_value;
            #1;
            if (inverse_sbox_value !== index[7:0]) begin
                $error("Input=%02h SBOX=%02h INV=%02h",index[7:0], sbox_value, inverse_sbox_value);
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("PASS: known values and inverse property verified.");
        else
            $fatal(1, "FAIL: substitution table errors = %0d", errors);

        $finish;
    end
endmodule

