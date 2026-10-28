# Rifiniture di affidabilità e sicurezza

Da implementare in un secondo momento:

- [ ] Uniformare i codici di uscita: `0` per successo, diverso da zero per errore. Correggere in particolare il flusso di stop Ollama, gestendo come successo anche il motore già fermo.
- [ ] Propagare gli errori di arresto da `stop_process()` e verificare che il processo sia effettivamente terminato prima di dichiarare successo, anche per llama.
- [ ] Controllare gli errori HTTP nelle chiamate API e propagare il fallimento del preload Ollama, evitando di dichiarare pronto un modello non caricato.
- [ ] Costruire i JSON con `jq` anziché interpolare stringhe, per gestire correttamente virgolette, backslash e caratteri speciali.
- [ ] Aggiungere test mirati per arresto fallito, motore già fermo, errori HTTP, preload fallito e valori con caratteri speciali nei JSON. Verificare coerenza tra risultato, codice di uscita e risposta JSON.
