import random
from pathlib import Path
from reference_model import crypt_transfer


def genera_vettori(output_file, num_random=80): #dove salvare il file di output e quanti messaggi casuali generare
    rng = random.Random(0x9302026) #seed fisso per riproducibilità dei test

    # messaggi di base (caso del testo + casi limite)
    messaggi = [
        (0x3C, bytes.fromhex("0011223344")),  # Vettore del PDF
        (0x00, bytes.fromhex("A5")),          # Messaggio da 1 solo byte
        (0xFE, bytes.fromhex("01020304")),    # Lunghezza pari con wrap contatore
        (0xFF, bytes.fromhex("102030")),      # Lunghezza dispari con wrap contatore
    ]

    # aggiunta di messaggi casuali
    for _ in range(num_random):
        length = rng.randint(1, 40) #scelta casuale della lunghezza del messaggio tra 1 e 40 byte,    
        key = rng.randrange(256) #scelta casuale della chiave tra 0 e 255
        data = bytes(rng.randrange(256) for _ in range(length)) #genera un messaggio casuale di lunghezza 'length' (infatti  range(length) genera un iteratore da 0 a length-1, e per ogni elemento genera un byte casuale tra 0 e 255) e li raccoglie in una sequenza di byte.
        messaggi.append((key, data)) #84 messaggi in totale: 4 di base + 80 casuali

    righe = ["# start key in_data byte_valid last expected_out"] #cioe la prima riga del file di output contiene i nomi dei campi separati da spazi

    for key, data in messaggi:
        cb = key #all'inizio di ogni messaggio il contatore viene inizializzato con la sua relativa chiave
        # suddivide i byte in parole a 16 bit
        for i in range(0, len(data), 2): #scorre il messaggio a passi di 2 byte (16 bit) per volta.
            chunk = data[i : i + 2] #parte da i e prende i successivi 2 byte (o meno se siamo alla fine del messaggio)
            is_start = 1 if i == 0 else 0 #Vale 1 soltanto per il primo trasferimento del messaggio. È una forma compatta
            is_last = 1 if (i + len(chunk)) >= len(data) else 0 #Vale 1 quando il blocco corrente raggiunge la fine del messaggio.
            #Per un messaggio di un solo trasferimento, entrambi valgono 1.

            if len(chunk) == 2:
                in_data = chunk[0] | (chunk[1] << 8)
                mask = 0b11
            else:
                in_data = chunk[0]
                mask = 0b01

            expected_out, cb = crypt_transfer(cb, in_data, mask, bool(is_last))

            # Formattazione per SystemVerilog ($fscanf): hex a dimensione fissa
            righe.append(
                f"{is_start} {key:02x} {in_data:04x} {mask:x} {is_last} {expected_out:04x}"
            )

    path = Path(output_file)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(righe) + "\n", encoding="ascii")
    print(f"Generati {len(righe)-1} vettori di test in: {output_file}")


if __name__ == "__main__":
    genera_vettori("modelsim/tv/test_vectors.tv")