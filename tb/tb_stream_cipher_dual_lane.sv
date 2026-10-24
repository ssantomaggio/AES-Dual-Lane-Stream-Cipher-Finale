`timescale 1ns/1ps

module tb_stream_cipher_dual_lane;

    localparam MAX_TRANSFERS = 4096; //Riserva spazio per un massimo di 4096 trasferimenti, non messaggi.

    logic clk = 0; //uso gli stessi identici nomi di stream_cipher_dual_lane_single_cycle.sv per poter fare .* e collegare tutto automaticamente
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
    logic out_ready = 0;
    logic [15:0] out_data;
    logic [1:0] out_byte_valid;
    logic out_last;

    logic busy;
    logic protocol_error;
//gli array servono per memorizzare le colonne del file tv/test_vectors.tv
    integer first_vector [0:MAX_TRANSFERS-1]; //Indica il primo trasferimento di un messaggio
    logic [7:0] key_vector [0:MAX_TRANSFERS-1]; //Indica la chiave 
    logic [15:0] input_vector [0:MAX_TRANSFERS-1]; //Indica i dati di input per ogni trasferimento
    logic [1:0] mask_vector [0:MAX_TRANSFERS-1]; //Indica la maschera per ogni trasferimento
    integer last_vector [0:MAX_TRANSFERS-1]; //Indica l'ultimo trasferimento di un messaggio
    logic [15:0] expected_vector [0:MAX_TRANSFERS-1]; //Indica i dati attesi per ogni trasferimento

    integer file_handle, result, i; //file_handle è un numero intero che rappresenta il file aperto, result è il numero di valori letti da sscanf (deve essere 6), i è un contatore per i cicli for
    integer count = 0; //Conta i TRASFERIMENTI caricati dal file
    integer received = 0; //Conta le uscite consegnate e sceglie il risultato atteso da confrontare. expected_vector[received] è il risultato atteso per il trasferimento corrente, e va confrontato con out_data. Quindi mi sta dicendo questo out data di adesso confrontalo con il vector numero received. Dopo averlo confrontato, incremento received di 1 per passare al prossimo trasferimento.Per la prima uscita: out_data !== expected_vector[0]
    integer errors = 0; //conta gli errori di confronto tra out_data e expected_vector[received] e anche eventuali errori di protocollo. Se errors > 0 alla fine del test, il test fallisce.
    integer seed = 42; // Il seed serve a ripetere gli stessi blocchi casuali dell’uscita. Nel testbench generi out_ready pseudocasualmente: a volte il ricevente è pronto, altre deve aspettare
    string line; //linea letta dal file tv/test_vectors.tv

    logic stalled = 0;  //Ricorda se al fronte precedente l'uscita era valida ma non accettata. Se vale 1, verifica che il risultato sia rimasto valido e invariato,
    logic [15:0] saved_data; //li uso nel caso in cui l'uscita è bloccata
    logic [1:0] saved_mask; 
    logic saved_last; 

    // Per verificare la pipeline, cambia solo il nome del modulo.
    stream_cipher_dual_lane_single_cycle dut (.*);

    always #5 clk = ~clk; //clock a 100 MHz. Ogni 5 ns cambio il clock da 0 a 1 o da 1 a 0. Quindi un periodo completo è 10 ns, quindi la frequenza è 1/10ns = 100 MHz

    // Genera blocchi casuali dell'uscita.
    always @(negedge clk) begin //il cifrario legge out ready al fronte di salita del clock, quindi generiamo out_ready al fronte di discesa del clock. In questo modo, out_ready è stabile per mezzo ciclo prima che il cifrario legge il suo valore.
        if (!reset_n) //durante il reset, out_ready=0, quindi il ricevente non accetta risultati (perché il cifrario non è pronto a produrli)
            out_ready = 0;
        else
            out_ready = (($random(seed) & 3) != 0); // $random(seed), con seed inizialmente uguale a 42, genera un numero pseudocasuale a 32 bit. L’AND con 3, cioè 000...0011 in binario, azzera tutti i bit tranne gli ultimi due, che possono essere 00, 01, 10 oppure 11. 
            //Il confronto != 0 è falso solo per 00, quindi out_ready vale 0 indicativamente nel 25% dei casi e 1 nel restante 75%. In questo modo simuliamo un ricevente che a volte blocca l’uscita.
    end

    // Evita un'attesa infinita se qualcosa non funziona.
    initial begin //è un blocco che aspetta 1 ms (100000 ns) e se la simulazione è ancora in corso allora da errore
    //Serve perché un errore potrebbe lasciare il testbench ad aspettare per sempre un risultato o un segnale ready.
        #1000000;
        $fatal(1, "Timeout"); 
    end

    task automatic start_message(input logic [7:0] message_key); //// È come una funzione def che esegue le sue operazioni e aspetta i fronti del clock quando serve, 
        //mentre il resto del circuito continua a funzionare. Solo il blocco che la chiama aspetta che finisca.
        //automatic significa che ogni chiamata ha una propria copia di message_key e delle variabili locali. Eventuali chiamate contemporanee non condividono queste variabili.
        begin
            @(negedge clk); //aspetta un fronte di discesa
            while (start_ready !== 1'b1) 
                @(negedge clk);

            key = message_key; //quando chiamo questa task dentro all argomento passo key_vector[i], ovvero la seconda voce del vettore, che è la chiave di quel messaggio. cosi che poi faccio key=message_key
            start_valid = 1; //chi usa il circuito richiede di inviare un nuovo messaggio


            @(posedge clk);
            while (start_ready !== 1'b1)  
                @(posedge clk);
//una volta che start ready è diventato uno nel negedge metto la chiave su key. Nel posedge poi farà counter = key, 
//quindi al prossimo negedge abbassi start_valid, perché la richiesta è stata accettata
            @(negedge clk);
            start_valid = 0;
        end
    endtask

    initial begin //istruzioni eseguite in sequenza, una sola volta e a inizio simulazione,
        // Avvia Modelsim dalla cartella modelsim.
        file_handle = $fopen("tv/test_vectors.tv", "r"); //lo apre in lettura, r. L'apertura produrrà un valore per file_handle.
        if (file_handle == 0)
            $fatal(1, "Cannot open tv/test_vectors.tv");

        // Salta l'intestazione.
        result = $fgets(line, file_handle); //$fgets che è fatta per leggere una riga, fino al carattere di fine riga.
        //line serve per salvare la riga, file_handle da dove leggere

        while ($fgets(line, file_handle)) begin 
            if (count == MAX_TRANSFERS)
                $fatal(1, "Too many vectors");

            result = $sscanf( //prende i sei numeri contenuti nel testo line e li salva nei sei array.
                line, "%d %h %h %h %d %h", //dicono come leggere ciascun numero: %d in decimale, %h in esadecimale.
                first_vector[count], key_vector[count],
                input_vector[count], mask_vector[count],
                last_vector[count], expected_vector[count]
            );

            if (result != 6)
                $fatal(1, "Invalid vector at row %0d", count + 2);

            count = count + 1;
        end

        $fclose(file_handle); //Chiude il file, perché hai finito di leggerlo: i vettori sono ormai salvati negli array.
        if (count == 0)
            $fatal(1, "No vectors loaded");

        // Rimuove il reset lontano dal fronte di salita.
        repeat (3) @(negedge clk);
        reset_n = 1;
        @(negedge clk); //si potrebbe togliere
        // Aspetta tre fronti di discesa mantenendo il reset attivo, poi lo disattiva alla terza discesa. 
        //Aspetta un'altra discesa, lasciando passare una salita con reset disattivato prima di proseguire con le prove.

        //invio dei trasferimenti
        for (i = 0; i < count; i = i + 1) begin //scorre tutti i vettori caricati
            if (first_vector[i]) //se first vector = 1, e cioe è il primo trasferimento di un nuovo messaggio, allora devo prima fare handshake
                start_message(key_vector[i]); //allora voglio che start ready e start valid siano 1. Passo la chiave di quel messaggio come parametro

            in_data = input_vector[i];
            in_byte_valid = mask_vector[i];
            in_last = last_vector[i] != 0; //se last vector !=0 (è 1), allora in last sarà 1 perchè la condizione è vera. 
            in_valid = 1; //sto inviando dei byte (o un byte) validi

            // Mantiene il trasferimento fino all'accettazione.
            @(posedge clk);
            while (in_ready !== 1'b1)
                @(posedge clk);
//aspetta una salita con in_ready = 1. Durante l’attesa non esegue nuove assegnazioni, quindi quei segnali conservano i valori precedenti.
//A quella salita, siccome anche in_valid = 1, il circuito accetta il trasferimento. Solo dopo il mittente può cambiare i dati.
            @(negedge clk);
            in_valid = 0;//ho terminato l invio dei datidi quel trasferimento.
        end
//Il ciclo precedente termina quando hai inviato e fatto accettare l’ultimo ingresso, 
//non quando il ricevente ha preso l’ultimo risultato. Quindi posso avere 100 trasferimenti accettati e 99 uscite ricevute. 
//Devo aspettare anche l'ultima uscita, cioe quando ho received almeno uguale a count
        wait (received >= count); 
        repeat (3) @(negedge clk); //aspetto 3 fronti di discesa per lasciare tempo al monitor di rilevare eventuali uscite extra o errori tardivi

        if (errors != 0 || received != count ||
            busy !== 1'b0 || out_valid !== 1'b0) //out_valid = 1 significherebbe che c'è ancora un'uscita valida
            $fatal(1, "FAIL: errors=%0d, received=%0d", errors, received);

        $display("PASS: %0d transfers with randomized backpressure", count); //con blocchi casuali dell'uscita: cioè abbiamo fatto la verifica della ricezione dei messaggi in un contesto in cui il ricevente randomicamente poteva prendere subito o meno il risultato
        $finish;
    end

    always @(posedge clk) begin
        if (!reset_n) begin //se sto in reset metto a 0
            received <= 0;
            stalled <= 0;
        end
        else begin
            if (protocol_error !== 1'b0) begin
                $error("Unexpected protocol_error");
                errors = errors + 1;
            end
// Quando uso <= faccio un assegnamento NON bloccante: ovvero l'aggiornamento della variabile non avviene immediatamente, ma viene pianificato per la fine del passo di simulazione corrente.
// il valore a destra viene calcolato durante la valutazione del blocco,
// ma la variabile viene aggiornata nella fase successiva degli aggiornamenti
// non bloccanti, sempre nello stesso istante simulato, senza aspettare un altro clock.
// Quindi l'if(stalled) legge ancora il valore precedente di stalled,
// anche se l'assegnamento stalled <= ... dovesse essere scritto prima dell'if.
// Con =, invece, la variabile viene aggiornata subito e le istruzioni
// successive dello stesso blocco possono leggere il nuovo valore.
//always esegue tutte le operazioni in sequenza, ma gli assegnamenti non bloccanti vengono fatti applicati nella fase NBA dello stesso istante simulato.

            // Un risultato bloccato deve rimanere valido e invariato.
            if (stalled) begin //sto controllando l'uscita attuale (es. out_data) rispetto alla copia precedente (saved_data)
                if (out_valid !== 1'b1 ||
                    out_data !== saved_data ||
                    out_byte_valid !== saved_mask ||
                    out_last !== saved_last) begin
                    $error("Output changed while stalled");
                    errors = errors + 1;
                end
            end

            stalled <= out_valid && !out_ready; 

            if (out_valid && !out_ready) begin // if(stalled) verifica l'uscita attuale rispetto alla copia precedente.
// Qui invece controllo se è bloccata adesso e salvo la nuova copia.
                saved_data <= out_data; //quindi se ora sto in questa situazione salvo i valori
                saved_mask <= out_byte_valid;//poi nel posedge successivo stalled sarà 1 e quindi verifica se questi dati che mi sto salvando ora
                saved_last <= out_last;//saranno validi e invariati
            end

            // Confronta ogni uscita accettata con il relativo vettore.
            if (out_valid && out_ready) begin //confronta output con quello atteso
                if (received >= count) begin
                    $error("Unexpected extra output");
                    errors = errors + 1;
                end
                else if (
                    out_data !== expected_vector[received] ||
                    out_byte_valid !== mask_vector[received] ||
                    out_last !== (last_vector[received] != 0)
                ) begin
                    $error(
                        "Transfer %0d: data=%04h expected=%04h, mask=%b, last=%b",
                        received, out_data, expected_vector[received],
                        out_byte_valid, out_last
                    );
                    errors = errors + 1;
                end

                received <= received + 1;
            end
        end
    end

endmodule