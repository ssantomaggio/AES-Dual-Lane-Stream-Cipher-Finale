`timescale 1ns/1ps

module stream_cipher_dual_lane_single_cycle (
    input  logic        clk, 
    input  logic        reset_n, //riporta il circuito alla condizione iniziale quando vale 0 (reset attivo basso)

    input  logic [7:0]  key, //chiave a 8 bit
    input  logic        start_valid, //chi usa il circuito richiede di inviare un nuovo messaggio
    output logic        start_ready, //indica quando il circuito è pronto per accettare un nuovo messaggio e caricare la chiave
//L’avvio viene accettato al fronte di salita del clock quando entrambi sono 1.

    input  logic        in_valid, //il mittente sta presentando un byte o due byte validi
    output logic        in_ready,//il circuito è pronto ad accettare quel uno o due byte presentati dal mittente
    input  logic [15:0] in_data,//dati in ingresso
    input  logic [1:0]  in_byte_valid,//maschera, 11 oppure 01 ammesso solo nel caso in cui in_last = 1 (in last può essere uno anche con 11, si parla di un messaggio con byte pari)
    input  logic        in_last, //ultimo trasferimento
//La parola viene accettata solamente al fronte di salita del clock quando in_valid e in_ready sono entrambi 1.

    output logic        out_valid, //(prodotto dal cifrario) il circuito ha una parola valida in uscita
    input  logic        out_ready, //(prodotto dal ricevente) è 1 se il ricevente è pronto ad accettare la parola in uscita
    output logic [15:0] out_data, //dati in uscita
    output logic [1:0]  out_byte_valid,//maschera che si riferisce ai byte(o al byte) in uscita, 11 oppure 01 solo nel caso in cui out_last = 1
    output logic        out_last, //indica che la parola in uscita è l’ultima del messaggio, il ricevente deve accettarla per completare il messaggio

    output logic        busy,
    output logic        protocol_error
);

    logic [7:0] counter; //contatore a 8 bit preso dalla chiave e incrementato di 1 o 2 a seconda del numero di byte validi in ingresso. viene fatto quando i byte o il byte in ingresso sono stati accettati, cioè in_valid e in_ready sono entrambi 1 al fronte di salita del clock
    logic [7:0] counter_plus_one; //contatore incrementato di 1, usato per l’inverso della S-box
    logic       input_closed; // indica che l’ultimo trasferimento è stato accettato, quindi non si accettano coppie di byte o byte singoli in ingresso fino a quando non viene avviato un nuovo messaggio

    logic [7:0] sbox_out; //sarebbe l'equivalente di data_out della S-box
    logic [7:0] inv_sbox_out;//sarebbe l'equivalente di data_out della S-box inversa
    logic       output_ready;//indica che il registro di uscita può essere scritto, cioè è vuoto oppure viene consumato
    logic       input_transfer; //indica che l’ingresso è stato accettato, cioè in_valid e in_ready sono entrambi 1
    logic       legal_mask; //indica che la maschera in ingresso è legale, cioè 11 oppure 01 se in_last = 1

    // Il risultato resta su 8 bit: FF + 1 diventa 00.
    assign counter_plus_one = counter + 8'd1;

    aes_sbox u_sbox ( // istanza della S-box
        .data_in  (counter),
        .data_out (sbox_out)
    );

    aes_inv_sbox u_inv_sbox (
        .data_in  (counter_plus_one),
        .data_out (inv_sbox_out)
    );

    // Due byte validi, oppure un byte soltanto nell'ultimo trasferimento.
    assign legal_mask = (in_byte_valid == 2'b11) ||
                        ((in_byte_valid == 2'b01) && in_last);

    // Possiamo scrivere il registro se è vuoto oppure viene consumato.
    assign output_ready = !out_valid || out_ready; //il registro puo essere scritto se non c'è una parola valida (o non c'è scritto nulla) oppure se il ricevente è pronto a prendere la parola in uscita (out_ready = 1)

    assign start_ready = reset_n && !busy; //il circuito è pronto ad accettare un nuovo MESSAGGIO se non è occupato (busy = 0) e se non è in reset (reset_n = 1)

    assign in_ready = reset_n && //se non è in reset 
                    busy && //c'è un messaggio in corso, quindi il circuito è occupato
                    !input_closed && //input close sta sempre a 0 tranne quando avviene l'ultimo trasferimento di byte di un messaggio, dopodichè diventa di nuovo 0 quando viene avviato un nuovo messaggio (diventa 0 subito dopo l'accettazione dell'ultima uscita). 
                    output_ready && //se il registro di uscita può essere scritto
                    legal_mask;//se la maschera in ingresso è legale

    assign input_transfer = in_valid && in_ready; // Se vale 1 al fronte di salita, l'ingresso viene accettato.

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin //se non è 1, quindi 0 (reset attivo basso)
            counter        <= 8'h00;
            input_closed   <= 1'b0;

            out_valid      <= 1'b0;
            out_data       <= 16'h0000;
            out_byte_valid <= 2'b00;
            out_last       <= 1'b0;

            busy           <= 1'b0;
            protocol_error <= 1'b0;
        end
        else begin
            // Si riattiva se una violazione è presente in questo ciclo.
            protocol_error <= 1'b0;

            // Avvio di un nuovo messaggio.
            if (start_valid && start_ready) begin //gli start si mettono quando si parla di nuovi messaggi 
                counter      <= key; //Se la chiave è 3C, da quel momento il primo trasferimento userà SBOX[3C] e INV_SBOX[3D].
                input_closed <= 1'b0;
                busy         <= 1'b1; 
            end

            
//se al fronte di salita start valid e start ready sono 1, il cifrario carica counter=key e DAL CICLO SUCCESSIVO si possono mandare byte o coppie di byte validi.


            // Non è consentito avviare un messaggio mentre siamo occupati.
            if (start_valid && !start_ready) //richiedo di inviare un nuovo messaggio ma il circuito non è pronto per accettarlo, quindi protocol error
                protocol_error <= 1'b1;

            // ora fa i controlli nel caso in cui mittente ha dati validi da inviare, quindi in_valid = 1
            if (in_valid) begin //in valid dice che il mittente sta presentando un byte o due byte validi
                if (!busy || input_closed) //ma se presento byte validi e il circuito sta in not busy, significa che non ha ricevuto nessuna chiave del messaggio oppure che è terminato il messaggio precedente. Quindi come faccio a essere pronto a mandare byte di un messaggio senza aver ricevuto la chiave?(ovvero senza aver inviato la richiesta di invio di un nuovo messaggio?)? Oppure se input closed sta a 1, significa che l’ultimo trasferimento è stato accettato e in quel momento non si accettano coppie di byte o byte singoli, quindi non posso avere in_valid = 1, quindi protocol error
                    protocol_error <= 1'b1;

                if (!legal_mask)
                    protocol_error <= 1'b1;
            end

            // Il messaggio termina quando l'ultima uscita viene accettata.
            if (out_valid && out_ready && out_last) begin //finito tutto il messaggio, quindi il ricevente ha accettato l'ultima parola in uscita
                busy         <= 1'b0;
                input_closed <= 1'b0;
            end

            // Se l'uscita è bloccata, dato, maschera, last e valid mantengono i valori precedenti.
            if (output_ready) //se il registro di uscita può essere scritto
                out_valid <= input_transfer; //input transfer indica che l’ingresso è stato accettato. Quindi dal momento che viene accettato il dato in ingresso verranno fatti tutti i calcoli (in realtà vengono fatti sempre e continuamente, ma in questo caso da quanto input transfer è 1 al fronte di salita verranno aggiornati i dati) e nel fronte di salita si mette out valid = input transfer, cioe se input trasfer è 1 allora ci saranno stati calcoli che hanno prodotto un data out da inserire nel registro di uscita, e quindi out_valid=1. 

            // Un ingresso accettato ha sempre una maschera legale.
            if (input_transfer) begin
                out_data[7:0] <= in_data[7:0] ^ sbox_out;

                if (in_byte_valid == 2'b11) begin
                    out_data[15:8] <= in_data[15:8] ^ inv_sbox_out;
                    counter       <= counter + 8'd2;
                end
                else begin
                    out_data[15:8] <= 8'h00;
                    counter       <= counter + 8'd1;
                end

                out_byte_valid <= in_byte_valid;
                out_last       <= in_last;

                // Dopo l'ultimo ingresso aspettiamo solo l'ultima uscita.
                if (in_last)
                    input_closed <= 1'b1;
            end
        end
    end

endmodule


// Quindi praticamente io ho un byte o una coppia di byte da mandare
// di quel messaggio in corso.
// Posso presentare i dati e alzare in_valid anche se in_ready=0,
// ma serve in_ready=1 al fronte di salita per farli accettare.
// Metti che ho in_valid=1 perché sto presentando uno o due byte validi:
// avrò in_byte_valid=11 oppure 01, che è ammesso solo se in_last=1.
//
// Se in_ready è ancora 0, probabilmente il circuito sta aspettando
// che il ricevente possa prendere i dati in uscita.
// Nel frattempo mantengo stabili dati, maschera, in_last e in_valid.
// Quando in_ready diventa 1, ho sia in_valid sia in_ready a 1,
// quindi input_transfer=1. I dati saranno accettati al fronte di salita.
//
// Le S-box e gli XOR lavorano continuamente sui valori presenti:
// input_transfer decide se salvare il risultato al fronte di salita,
// non se iniziare il calcolo.
//
// Al fronte di salita, se input_transfer è ancora 1,
// nell'if di output_ready out_valid prende il valore di input_transfer,
// cioè 1. Nello stesso fronte, l'if di input_transfer aggiorna out_data
// con il risultato già preparato dalle S-box e dagli XOR,
// e aggiorna anche out_byte_valid, out_last e il contatore.
//
// Quindi adesso out_byte_valid ha la maschera del trasferimento accettato.
// Se il mittente poi presenta un solo byte finale e il risultato precedente
// non viene ancora preso, avrò in_byte_valid=01 mentre out_byte_valid=11,
// perché il circuito sta ancora aspettando che il ricevente
// prenda il risultato precedente in uscita.
