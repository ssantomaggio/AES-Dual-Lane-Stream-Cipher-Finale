`timescale 1ns/1ps

module stream_cipher_dual_lane (
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

    logic [7:0] counter;
    logic [7:0] counter_plus_one;
    logic       input_closed;

    // Risultati combinatori delle lookup.
    logic [7:0] sbox_out;
    logic [7:0] inv_sbox_out;

    // Registro intermedio: dati e keystream dello stesso trasferimento.
    logic        stage_valid;//indica che lo stadio intermedio contiene un trasferiment valido
    logic [15:0] stage_data; //è quello che poi insieme allo XOR diventerà l'out_data. Cioe il byte del messaggio da combianre con XOR
    logic [7:0]  stage_z0;//keystream della lane 0
    logic [7:0]  stage_z1;//keystream della lane 1
    logic [1:0]  stage_byte_valid; //maschera
    logic        stage_last; //indicatore ultimo trasferimento

    logic output_ready;
    logic stage_ready;
    logic input_transfer;
    logic legal_mask;

    assign counter_plus_one = counter + 8'd1;

    aes_sbox u_sbox (
        .data_in  (counter),
        .data_out (sbox_out)
    );

    aes_inv_sbox u_inv_sbox (
        .data_in  (counter_plus_one),
        .data_out (inv_sbox_out)
    );

    assign legal_mask = (in_byte_valid == 2'b11) ||
                        ((in_byte_valid == 2'b01) && in_last);

    // Il registro di uscita è vuoto oppure può essere consumato.
    assign output_ready = !out_valid || out_ready;

    // il registro intermedio può ricevere un nuovo trasferimento se è vuoto 
    //oppure il suo contenuto può andare avanti al registro di uscita
    assign stage_ready = !stage_valid || output_ready;

    //possso avviare un nuovo messaggio solo se non sono in reset o se non sono in busy
    assign start_ready = reset_n && !busy;

    //posso accettare dati quando:
    assign in_ready = reset_n && //non sei in reset;
                    busy && //il messaggio è attivo;
                    !input_closed && //non hai già accettato l’ultimo ingresso;
                    stage_ready && //il registro intermedio può ricevere;
                    legal_mask; //la maschera è legale


//SE QUESTA CONDIZIONE VALE 1 ALLA SALITA, ACCETTI IL TRASFERIMENTO
    assign input_transfer = in_valid && in_ready;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            counter          <= 8'h00;
            input_closed     <= 1'b0;

            stage_valid      <= 1'b0; //nessun trasferimento nello stadio intermedio
            stage_data       <= 16'h0000;
            stage_z0         <= 8'h00;
            stage_z1         <= 8'h00;
            stage_byte_valid <= 2'b00;
            stage_last       <= 1'b0;

            out_valid        <= 1'b0; //nessun risultato valido in uscita
            out_data         <= 16'h0000;
            out_byte_valid   <= 2'b00;
            out_last         <= 1'b0;

            busy             <= 1'b0;
            protocol_error   <= 1'b0;
        end
        //Il reset scarta quindi tutti i trasferimenti presenti nella pipeline.
        else begin
        //A ogni salita l’errore viene normalmente azzerato. I controlli successivi possono impostarlo a 1.
            protocol_error <= 1'b0;

            // Avvio del messaggio e caricamento della chiave.
            if (start_valid && start_ready) begin
                counter      <= key;
                input_closed <= 1'b0;
                busy         <= 1'b1;
            end

            if (start_valid && !start_ready) //non è possibile
                protocol_error <= 1'b1;

            if (in_valid) begin //non è possibile
                if (!busy || input_closed)
                    protocol_error <= 1'b1;

                if (!legal_mask) 
                    protocol_error <= 1'b1;
            end

            // Fine del messaggio solo dopo la consegna dell'ultima uscita.
            if (out_valid && out_ready && out_last) begin
                busy         <= 1'b0;
                input_closed <= 1'b0;
            end

            // Secondo stadio: XOR e registro di uscita.
            // Se l'uscita è bloccata, conserva tutti i suoi valori.
            if (output_ready) begin //controlla se l'uscita può essere scritta. Entra se il registro di uscita è vuoto oppure il risultato precedente viene accettato dal ricevente.
                out_valid <= stage_valid; //Al fronte di clock:
                //stage_valid = 1 → c’è un trasferimento intermedio da elaborare, quindi la nuova uscita sarà valida;
                //stage_valid = 0 → non c’è un trasferimento da elaborare, quindi l’uscita diventa non valida.

                if (stage_valid) begin //se c'è un trasferimento valido
                // USO I VALORI GIA PRESENTI NEL REGISTRO INTERMEDIO PRIMA DEL FRONTE
                    out_data[7:0] <= stage_data[7:0] ^ stage_z0; //byte basso

                    if (stage_byte_valid == 2'b11)
                        out_data[15:8] <= stage_data[15:8] ^ stage_z1; //byte alto
                    else
                        out_data[15:8] <= 8'h00;

                    out_byte_valid <= stage_byte_valid;//Il risultato deve portare con sé la maschera e 
                    out_last       <= stage_last; //il last del trasferimento corrispondente.
                    
                end
            end

            //Per esempio, prima del fronte:
                //stage_valid      = 1
                //stage_data       = 1100
                //stage_z0         = EB
                //stage_z1         = 8B
                //stage_byte_valid = 11
                //stage_last       = 0

                //Se output_ready = 1, al fronte vengono salvati insieme:

                //out_data       = 9AEB   ← 00 XOR EB, 11 XOR 8B
                //out_byte_valid = 11
                //out_last       = 0
                //out_valid      = 1

            // Primo stadio: salva insieme dati, risultati delle lookup,
            // maschera e last del trasferimento accettato.
            if (stage_ready) begin
                //Se lo stadio può essere scritto:
                    //input_transfer = 1 → entra un nuovo trasferimento, quindi stage_valid diventa 1;
                    //input_transfer = 0 → non entra nulla. L’eventuale trasferimento precedente avanza verso l’uscita, quindi lo stadio diventa vuoto: stage_valid = 0.
                //Se lo stadio è occupato e non può avanzare, stage_ready = 0: salti il blocco e conservi tutto.
                stage_valid <= input_transfer;

                if (input_transfer) begin //sto accettando un nuovo ingresso
                    stage_data       <= in_data;
                    stage_z0         <= sbox_out;
                    stage_z1         <= inv_sbox_out;
                    stage_byte_valid <= in_byte_valid;
                    stage_last       <= in_last;

                    if (in_byte_valid == 2'b11)
                        counter <= counter + 8'd2;
                    else
                        counter <= counter + 8'd1;

                    if (in_last)
                        input_closed <= 1'b1;
                end
            end
        end
    end

endmodule