`timescale 1ns/1ps

module tb_stream_cipher_protocol;

    logic clk = 0;
    logic reset_n = 0;

    logic [7:0] key = 0;
    logic start_valid = 0;
    logic start_ready;

    logic in_valid = 0;
    logic in_ready;
    logic [15:0] in_data = 0;
    logic [1:0] in_byte_valid = 0;
    logic in_last = 0;

    logic out_valid;
    logic out_ready = 1;
    logic [15:0] out_data;
    logic [1:0] out_byte_valid;
    logic out_last;

    logic busy;
    logic protocol_error;

    integer errors = 0;

    stream_cipher_dual_lane_single_cycle dut (.*);

    always #5 clk = ~clk;

    initial begin
        #100000;
        $fatal(1, "Timeout");
    end

    //Questa task attiva il reset e verifica che il circuito si azzeri 
    //senza aspettare una salita del clock, perché il reset è asincrono.
    task automatic apply_reset;
        begin
            @(negedge clk); //aspetta una discesa e metti tutte le richieste a 0
            start_valid = 0;//non possono essere messi a 0 dal reset perche sono richieste dall'esterno
            in_valid = 0;
            in_last = 0;
            in_byte_valid = 0;

            #2; //tolgo tutti i segnali dall'esterno mettendoli a 0 e poi aspetto 2ns.
            reset_n = 0; //poi resetto
            #1; //aspetto un altro 1ns per vedere l'effetto

            if (busy !== 1'b0 ||  //controllo che il reset abbia funzionato azzerando questi 3 segnali 
                out_valid !== 1'b0 ||
                protocol_error !== 1'b0) begin
                $error("Reset did not clear the circuit");
                errors = errors + 1;
            end

            repeat (2) @(negedge clk); //mantengo il reset attivo per altre 2 discese del clock, 
            
            reset_n = 1; //poi lo disattivo
        end
    endtask

    // Avvia un messaggio con chiave 3C.
    task automatic start_message; //in questo caso la task start message viene definita senza passare la chiave come parametro siccome viene definita esplicitamente nel corpo
        begin
            @(negedge clk);
            while (start_ready !== 1'b1)
                @(negedge clk);

            key = 8'h3C;
            start_valid = 1;

            @(posedge clk);
            while (start_ready !== 1'b1)
                @(posedge clk);

            @(negedge clk);
            start_valid = 0;

            if (busy !== 1'b1) begin
                $error("Message did not start");
                errors = errors + 1;
            end
        end
    endtask

    // Chiamata dopo aver presentato una violazione.
    // Controlla l'errore e poi rimuove la richiesta illegale.
   task automatic expect_error(input string test_name); // Il testbench presenta una violazione e chiama questa task passando un testo che descrive la prova.
    // Il test passa se il circuito mette protocol_error a 1 dopo la violazione.
    // La task poi toglie la richiesta illegale e verifica che protocol_error torni a 0 alla salita successiva.
        begin
            @(posedge clk);
            #1; //aspetto 1 cosi i registri hanno avuto tempo per aggiornarsi

            if (protocol_error !== 1'b1) begin //non è stato rilevato l'errore
                $error("Missing protocol_error: %s", test_name);
                errors = errors + 1;
            end

            @(negedge clk); //nel ffronte di discesa elimino la richieata rimettendo a 0 in e start valid
            in_valid = 0;
            start_valid = 0;

            @(posedge clk); //dopo la salita successiva l'errore deve essere sparito
            #1;

            if (protocol_error !== 1'b0) begin
                $error("protocol_error did not clear: %s", test_name);
                errors = errors + 1;
            end
        end
    endtask

    // Presenta un trasferimento e aspetta l'accettazione.
    task automatic send_transfer(
        input logic [15:0] data,
        input logic [1:0] mask,
        input logic last
    );
        begin
            @(negedge clk);
            in_data = data;
            in_byte_valid = mask;
            in_last = last;
            in_valid = 1;

            @(posedge clk);
            while (in_ready !== 1'b1)
                @(posedge clk);

            @(negedge clk);
            in_valid = 0;
        end
    endtask


//IN QUESTO BLOCCO OGNI VOLTA CHE CHIAMO UNA TASK DEVE PRIMA FINIRE PRIMA DI PROSEGUIRE
    initial begin
        // 1. Dati senza aver avviato un messaggio.
        apply_reset();//in questa prova sto facendo reset (busy=0) e poi alzo in valid senza aver chiamato start_message

        @(negedge clk);
        in_valid = 1;
        in_byte_valid = 2'b11;
        expect_error("input outside active message"); //controlla che viene segnalato questo errore

        // 2. Nuovo avvio mentre un messaggio è attivo.
        apply_reset();
        start_message();

        @(negedge clk);
        start_valid = 1; //alzo start valid mentre ho gia fatto start_message, quindi busy è gia 1.
        expect_error("new start while busy");

        // 3. Maschera illegale 00.
        apply_reset();
        start_message();

        @(negedge clk);
        in_valid = 1;
        in_byte_valid = 2'b00;
        in_last = 1;
        expect_error("illegal mask 00");

        // 4. Maschera illegale 10.
        apply_reset();
        start_message();

        @(negedge clk);
        in_valid = 1;
        in_byte_valid = 2'b10;
        in_last = 1;
        expect_error("illegal mask 10");

        // 5. Un byte singolo che non è l'ultimo.
        apply_reset();
        start_message();

        @(negedge clk);
        in_valid = 1;
        in_byte_valid = 2'b01;
        in_last = 0;
        expect_error("one-byte transfer without last");

        // 6. Ultimo risultato bloccato:
        // il messaggio deve rimanere occupato.
        apply_reset();
        start_message();

        @(negedge clk); //quando sto lontano da posedge metto out ready a 0 quindi il ricevente non è pronto
        out_ready = 0;

        send_transfer(16'h1100, 2'b11, 1'b1);

        if (busy !== 1'b1 || start_ready !== 1'b0) begin //se start ready è pronto o non sto in busy è un errore
            $error("Message ended before final output was accepted");
            errors = errors + 1;
        end

        // Aspetta l'uscita: utile anche per la futura pipeline.
        wait (out_valid === 1'b1);

//e poi dopo aver impedito al receiver di prendere il risultato provo due violazioni:

        // Non può partire un altro messaggio.
        @(negedge clk);
        start_valid = 1;
        expect_error("new start while final output is blocked");

        // Non possono entrare altri dati dopo l'ultimo ingresso.
        @(negedge clk);
        in_valid = 1;
        in_data = 16'h3322;
        in_byte_valid = 2'b11;
        in_last = 0;
        expect_error("input after final input");

        // 7. Verifico che il reset funzioni anche quando c'è un risultato bloccato in uscita. Il reset deve poterlo scartare
        apply_reset();

        // 8. Dopo il reset deve funzionare un nuovo messaggio,
        // senza ripresentare il risultato precedente.
        start_message();
        send_transfer(16'h0000, 2'b01, 1'b1);

//start_message() avvia il messaggio con chiave 3C.
//send_transfer() presenta la parola 0000.
//La maschera 01 indica che soltanto il byte basso 00 è valido.
//last = 1 indica che quel singolo byte costituisce tutto il messaggio.
        
        wait (out_valid === 1'b1); //aspettiamo che il cicuito tenga pronto l'output
        
        @(negedge clk); //aspettiamo poi una discesa per controllarlo
        //il risultato rimane nel registro, perché out_ready = 0.
        //L'AVEVAMO MESSO A 0 A RIGA 194
// Con chiave 3C: 00 XOR SBOX[3C] = EB.
        if (out_data !== 16'h00EB ||
            out_byte_valid !== 2'b01 ||
            out_last !== 1'b1) begin
            $error("Incorrect output after reset");
            errors = errors + 1;
        end

        if (protocol_error !== 1'b0) begin //vedo se ci sono errori che non dovrebbero esserci
            $error("Unexpected protocol_error after reset");
            errors = errors + 1;
        end

        // Consuma l'ultima uscita.
        out_ready = 1; //siamo ancora in discesa (riga 236), e metto out_ready=1 e così lo metto pronto per il prossimo fronte di salita
        @(posedge clk);
        #1;
    
        //dopo questa salita out_valid = 1 out_ready = 1 out_last = 1
    //L'ULTIMA USCITA VIENE ACCETTATA E IL MESSAGGIO TERMINA,
    //POI CONTROLLO CHE IL CIRCUITO SIA TORNATO LIBERO

        if (busy !== 1'b0 || out_valid !== 1'b0) begin
            $error("Message did not finish correctly");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: protocol and reset tests");
        else
            $fatal(1, "FAIL: %0d errors", errors);

        $finish; //se tutto va bene stampa PASS e termina correttamente
    end

endmodule