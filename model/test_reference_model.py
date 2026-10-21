import random
from reference_model import crypt_message, crypt_transfer, AES_SBOX, AES_INV_SBOX


def test_vettore_assegnamento(): #verifica l’intero messaggio, compresa la divisione in coppie e la ricomposizione dei byte.
    #Vettore fornito nel PDF delle specifiche: K=0x3C, plaintext 00 11 22 33 44

    plaintext = bytes.fromhex("0011223344")
    ciphertext = crypt_message(0x3C, plaintext)
    assert ciphertext == bytes.fromhex("eb9a90164d"), "Errore nel vettore del testo!"

def test_trasferimenti_assegnamento(): #verifica ogni singolo trasferimento e il contatore restituito.
    cb = 0x3C

    out_word, cb = crypt_transfer(cb, 0x1100, 0b11, False)
    assert out_word == 0x9AEB
    assert cb == 0x3E  # 3C + 2 byte

    out_word, cb = crypt_transfer(cb, 0x3322, 0b11, False)
    assert out_word == 0x1690
    assert cb == 0x40  # 3E + 2 byte

    out_word, cb = crypt_transfer(cb, 0x0044, 0b01, True)
    assert out_word == 0x004D
    assert cb == 0x41  # 40 + 1 byte
    
def test_proprieta_xor():
    #Cifrare e poi decifrare deve ridare il testo in chiaro originale

    rng = random.Random(42)
    for length in range(1, 50):
        data = bytearray()

        for i in range(length):
            byte = rng.randrange(256)
            data.append(byte)

        key = rng.randrange(256)

        crypted = crypt_message(key, data)
        decrypted = crypt_message(key, crypted)

        assert decrypted == data, "La decifratura non recupera il messaggio"

def test_wrap_around_contatore():
    # Due byte: da FF il contatore passa a 01.
    # Lane 0: 34 XOR SBOX[FF] = 34 XOR 16 = 22
    # Lane 1: 12 XOR INV_SBOX[00] = 12 XOR 52 = 40
    out_word, next_cb = crypt_transfer(0xFF, 0x1234, 0b11, True)

    assert out_word == 0x4022, "Cifrato errato durante il wrap-around!"
    assert next_cb == 0x01, "Contatore errato con due byte!"

    # Un byte: da FF il contatore passa a 00.
    # Lane 0: 34 XOR SBOX[FF] = 22; lane 1 non valida.
    out_word, next_cb = crypt_transfer(0xFF, 0x0034, 0b01, True)

    assert out_word == 0x0022, "Cifrato errato con un byte!"
    assert next_cb == 0x00, "Contatore errato con un byte!"


def test_maschere_illegali():
    #Verifica che le maschere errate sollevino eccezione
    try:
        crypt_transfer(0, 0x1234, 0b10, True)#true si mette solo nel caso in cui è l'ultimo trasferimento di byte che si fa, quindi quando hai 0b01 o anche 0b11 se hai byte pari 
        assert False, "Non ha rifiutato maschera 0b10"
    except ValueError:
        pass

    try:
        crypt_transfer(0, 0x1234, 0b01, False)  # 0b01 ma non e' last
        assert False, "Non ha rifiutato 0b01 non-last"
    except ValueError:
        pass
    try:
        crypt_transfer(0, 0x1234, 0b00, True)
        assert False, "Non ha rifiutato maschera 0b00"
    except ValueError:
        pass


if __name__ == "__main__":
    test_vettore_assegnamento()
    test_proprieta_xor()
    test_wrap_around_contatore()
    test_maschere_illegali()
    print("Tutti i test sul modello Python sono passati con successo!")