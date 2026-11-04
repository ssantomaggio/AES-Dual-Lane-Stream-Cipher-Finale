# Vincoli comuni per wrapper_single_cycle e wrapper_pipeline.
# Unita temporale: ns. Caricare soltanto questo SDC per il clock clk.
# Punto di partenza: 10 ns = 100 MHz; non e una Fmax gia verificata.
set cipher_clock_period_ns 10.000
create_clock -name clk -period $cipher_clock_period_ns [get_ports {clk}]

# Ambiente esterno IPOTIZZATO per il confronto, non specificato dalla consegna.
# Gli ingressi arrivano tra 0 e 2 ns dopo il fronte del clock di riferimento.
# In uscita si riservano 2 ns al percorso esterno e si assume hold esterno 0 ns.
# Mantenere le stesse ipotesi per entrambe le architetture.
# Per una scheda reale, sostituire questi valori con quelli dell'interfaccia.
set cipher_inputs [get_ports {key[*] start_valid in_valid in_data[*] in_byte_valid[*] in_last out_ready}]
set cipher_outputs [get_ports {start_ready in_ready out_valid out_data[*] out_byte_valid[*] out_last busy protocol_error}]
set_input_delay  -clock [get_clocks {clk}] -max 2.000 $cipher_inputs
set_input_delay  -clock [get_clocks {clk}] -min 0.000 $cipher_inputs
set_output_delay -clock [get_clocks {clk}] -max 2.000 $cipher_outputs
set_output_delay -clock [get_clocks {clk}] -min 0.000 $cipher_outputs

# Incertezza del clock calcolata da TimeQuest per il dispositivo selezionato.
derive_clock_uncertainty

# Il reset asincrono e escluso dalla misura della frequenza del datapath.
# Questa eccezione esclude anche recovery/removal del reset: NON ne prova
# la sicurezza del rilascio. Nel banco di misura si assume che il reset
# venga rilasciato con clock fermo e stabilizzato prima di avviare il clock.
# Per hardware reale occorre definire una strategia di rilascio appropriata.
set_false_path -from [get_ports {reset_n}]
