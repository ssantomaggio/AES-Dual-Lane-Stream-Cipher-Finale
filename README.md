# Dual-Lane AES Substitution Stream Cipher

Progetto per il corso **Hardware and Embedded Security (930II)**, Università di Pisa.

Implementazione in SystemVerilog di uno stream cipher che elabora fino a **due byte per trasferimento**, usando la S-box AES per la lane 0 e la S-box inversa AES per la lane 1.

La cifratura e la decifratura usano lo stesso calcolo XOR. Il progetto non implementa l’algoritmo AES completo.

## Architetture

- **Single-cycle:** lookup e XOR senza registro intermedio.
- **Pipeline:** registro intermedio tra lookup e XOR.

Entrambe supportano handshake valid/ready, backpressure, messaggi di lunghezza pari e dispari, reset asincrono attivo basso e segnalazione degli errori di protocollo.

## Struttura

| Cartella | Contenuto |
|----------|-----------|
| `db/` | Moduli SystemVerilog del circuito |
| `tb/` | Testbench SystemVerilog |
| `model/` | Modello Python, test e generatore di vettori |
| `modelsim/tv/` | Vettori di test |
| `modelsim/wave/` | Configurazioni delle forme d’onda |
| `quartus/constr/` | Vincoli temporali |
| `doc/` | Specifiche, regole e materiale per il report |

## Modello Python

Dalla cartella principale:

```bash
python model/test_reference_model.py
python model/generate_test_vectors.py
```

Il generatore salva i vettori in `modelsim/tv/test_vectors.tv`.

## Simulazione

I testbench verificano:

- valori noti e proprietà inversa delle lookup;
- risultati del cifrario rispetto al modello Python;
- stabilità dell’uscita durante la backpressure;
- errori di protocollo, reset e ripartenza.

Per il testbench dei vettori, impostare `modelsim/` come cartella di lavoro.

I moduli principali sono:

- `stream_cipher_dual_lane_single_cycle`
- `stream_cipher_dual_lane` — versione con pipeline, nel file `stream_cipher_dual_lane_pipeline.sv`

## Implementazione FPGA

Dispositivo richiesto: **Cyclone V — 5CGXFC9D6F27C7**.

Il confronto tra le due architetture considera risorse utilizzate, latenza e frequenza massima ottenuta mediante Static Timing Analysis in Quartus.

## Stato

Modello Python e simulazioni funzionali completati. Implementazione e analisi temporale in Quartus in corso di preparazione.
