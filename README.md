# Patch KOReader "ora no" per la sincronizzazione dei progressi

Questa repo contiene:

- `2-kosync-ora-no.lua`: la patch vera e propria.
- `README.md`: questo file. Spiega cosa fa la patch, come installarla e, in fondo, contiene istruzioni per Claude o un altro assistente AI.
- `LICENSE`: licenza AGPL-3.0, la stessa di KOReader.

---

## 1. Il problema che risolve

In KOReader, con la **sincronizzazione automatica dei progressi** (plugin *Sincronizzazione progressi* / KOSync) attiva, ogni volta che apri un libro o riaccendi l'e-reader KOReader accende il Wi-Fi per scaricare la posizione di lettura dal server.

Se non c'è una rete disponibile, per esempio quando sei in giro, compare il popup **"Connessione in corso…"** e il lettore resta bloccato per 15–40 secondi. Non lo si può chiudere, quindi non puoi leggere finché il tentativo non fallisce.

## 2. Cosa fa la patch

1. **Pausa breve.** Se riapri il lettore entro **5 minuti** da quando l'hai bloccato, non scarica niente e riprendi subito a leggere.
2. **"Ora no".** Quando KOReader vorrebbe accendere il Wi-Fi per scaricare la posizione (apertura di un libro, oppure riapertura dopo più di 5 minuti), *prima* di accenderlo mostra per **3 secondi** l'avviso:
   > Sincronizzo la posizione…
   > Tocca per saltare (ora no).
   - **Non tocchi niente:** sincronizza normalmente.
   - **Tocchi l'avviso:** torni subito a leggere, senza Wi-Fi e senza download.
3. **Chiusura invariata.** Quando blocchi il lettore, KOReader prova comunque a connettersi e a inviare la posizione, come fa senza patch. Se non trova la rete spegne il Wi-Fi e mette la posizione in coda, poi la invia da solo alla prossima connessione riuscita.

I comandi manuali del menu (*Invia progressi*, *Ricevi progressi*) non vengono toccati e funzionano come sempre.

L'avviso compare solo se il Wi-Fi è spento. Se il lettore è già online, la sincronizzazione avviene subito, senza avviso.

## 3. Requisiti

- **KOReader** recente. La patch è stata testata su **v2026.07.2**, sia su Kobo sia su Kindle Paperwhite. Su versioni molto diverse va prima verificata (vedi la sezione 7).
- Plugin **Sincronizzazione progressi** già configurato, con server e login funzionanti.
- In KOReader:
  - **Strumenti → Rete → Azione quando il Wi-Fi è spento → Accendi**
  - **Strumenti → Sincronizzazione progressi → Mantieni automaticamente sincronizzati i documenti** attivo. Questa voce si può attivare solo se l'impostazione precedente è su *Accendi*.

## 4. Installazione

1. Collega l'e-reader al computer via USB.
2. Trova la cartella di KOReader:
   - **Kobo:** `.adds/koreader/`. La cartella `.adds` è nascosta: sul Mac premi `Cmd+Maiusc+.` nel Finder per vedere i file nascosti.
   - **Kindle:** `koreader/` nella cartella principale del Kindle.
   - **Altri dispositivi:** la cartella dove si trovano `reader.lua` e la cartella `plugins/` di KOReader.
3. Dentro quella cartella crea, se non esiste già, una cartella chiamata **`patches`**.
4. Copia dentro `patches` il file **`2-kosync-ora-no.lua`**, lasciando il nome così com'è. Il `2-` iniziale è necessario: dice a KOReader quando caricare la patch.
5. Espelli l'e-reader dal computer.
6. In KOReader: **menu ☰ → Esci → Riavvia KOReader**.
7. Controlla le impostazioni della sezione 3.

Se all'avvio compare **"Error applying patch"**, la patch non è compatibile con la tua versione: cancella il file e vedi la sezione 7.

## 5. Come provarla

Usa un libro aperto. Puoi fare tutto a casa: l'avviso compare prima che il Wi-Fi si accenda.

1. **Apertura libro:** apri un libro e deve comparire l'avviso dei 3 secondi. Toccalo: torni subito a leggere.
2. **Pausa breve:** blocca il lettore e riaprilo dopo 1–2 minuti. Nessun avviso, leggi subito.
3. **Pausa lunga:** bloccalo e riaprilo dopo più di 5 minuti. Compare l'avviso. Non toccarlo: dopo 3 secondi si connette e sincronizza.
4. **Chiusura:** leggi qualche pagina e blocca il lettore. A casa si connette, invia la posizione e va in standby. Su un altro dispositivo sincronizzato trovi la posizione aggiornata.

Nel log di KOReader (`crash.log`, nella stessa cartella di KOReader) la patch scrive righe che iniziano con **`KOSync ora-no:`**, utili per capire cosa è successo.

## 6. Personalizzare o togliere

- **Cambiare i tempi:** apri il file `.lua` con un editor di testo semplice. In alto ci sono due righe:
  ```lua
  local PAUSA_BREVE = 5 * 60 -- secondi
  local ATTESA = 3           -- secondi
  ```
  Modifica i numeri, salva e riavvia KOReader.
- **Togliere del tutto:** cancella `2-kosync-ora-no.lua` dalla cartella `patches` e riavvia KOReader.

Se il Mac crea un file `._2-kosync-ora-no.lua` accanto alla patch, puoi ignorarlo: KOReader non lo considera.

---

## 7. Istruzioni per Claude (o altro assistente AI)

> Questa sezione è scritta per l'assistente a cui l'utente ha caricato questi file.

**Contesto.** `2-kosync-ora-no.lua` è una *user patch* di KOReader. KOReader esegue all'avvio, con `dofile`, i file in `koreader/patches/` il cui nome inizia con `2-`. Questa patch usa `userpatch.registerPatchPluginFunc("kosync", fn)` per modificare la classe del plugin KOSync ogni volta che viene istanziato, cioè a ogni libro aperto. Non modifica nessun file di KOReader.

**Cosa sostituisce (wrapper che chiamano sempre l'originale):**

- `KOSync.getProgress(self, ensure_networking, interactive, ...)`: quando `ensure_networking == true`, `interactive == false`, il dispositivo non è online (`NetworkMgr:isOnline()`) e l'account è configurato, mostra un `InfoMessage` con `timeout = 3`. Sull'istanza vengono sovrascritti `onTapClose` e `onAnyKeyPressed` per segnare il tocco come "saltato". Nel `dismiss_callback`, se l'utente non ha toccato, pianifica con `UIManager:scheduleIn(0.5, ...)` il `getProgress` originale; se ha toccato, non fa nulla. **Importante:** non chiamare `getProgress` direttamente dentro `dismiss_callback`. Il callback gira dentro `InfoMessage:onCloseWidget`, mentre l'avviso viene smontato, e la connessione chiama `UIManager:forceRePaint()`: KOReader prova a ridisegnare l'avviso già liberato e va in crash (`textboxwidget.lua: attempt to index field '_bb' (a nil value)`). Era un bug della prima versione. È questo il punto che evita il blocco: su Kobo e Kindle `NetworkMgr:turnOnWifiAndWaitForConnection` → `turnOnWifi` → `reconnectOrShowNetworkMenu` è **bloccante** (scansione e attesa fino a circa 15 s in un ciclo con `usleep`), quindi il popup "Connecting to Wi-Fi…" non può essere chiuso mentre è attivo. La scelta va fatta prima di accendere il Wi-Fi.
- `KOSync._onSuspend`: salva `os.time()` in una variabile locale del file, condivisa tra le istanze del plugin, poi chiama l'originale. L'invio alla chiusura resta invariato.
- `KOSync._onResume`: se sono passati meno di `PAUSA_BREVE` secondi dall'ultimo suspend, ritorna senza fare nulla; altrimenti chiama l'originale, il cui download passa dal `getProgress` modificato.
- `_onSuspend` e `_onResume` vengono assegnati a `self.onSuspend` e `self.onResume` da `KOSync:registerEvents()` in `onReaderReady`, quindi dopo la patch: per questo basta modificarli sulla classe.

**Prima di installarla su un dispositivo, verifica sulla versione installata dell'utente:**

1. Versione: file `git-rev` nella cartella KOReader. Con v2026.07.x la patch è testata.
2. In `frontend/userpatch.lua` deve esistere `userpatch.registerPatchPluginFunc`.
3. In `plugins/kosync.koplugin/main.lua` devono esistere `KOSync._onSuspend`, `KOSync._onResume`, `KOSync:getProgress(ensure_networking, interactive)` e `KOSync:registerEvents()` che li assegna. Inoltre `onReaderReady` deve chiamare `self:getProgress(true, false)`.
4. In `frontend/ui/widget/infomessage.lua`: `InfoMessage` deve supportare `timeout` e `dismiss_callback` (chiamato in `onCloseWidget`) e avere gli handler `onTapClose` / `onAnyKeyPressed`.
5. Nelle impostazioni (`settings.reader.lua`) `wifi_enable_action` deve valere `"turn_on"`; in `settings/kosync.lua` deve esserci `auto_sync = true`. Il plugin disattiva da solo `auto_sync` se `wifi_enable_action` non è `turn_on`.

Se i nomi sono cambiati, adatta i wrapper mantenendo la stessa logica.

**Per il debug:** cerca in `crash.log` le righe `KOSync ora-no:` (`patch applicata`, `download saltato dall'utente`, `nessun tocco, sincronizzo`, `riaperto dopo N s, niente download`) e i messaggi di NetworkMgr (`turnOnWifiAndWaitForConnection: Connection failed!`, `Wi-Fi successfully restored`).

**Comportamento voluto dall'autore**, da mantenere se modifichi la patch:

- L'apertura della lettura non deve mai restare bloccata dal Wi-Fi.
- La chiusura deve continuare a inviare la posizione. Se non c'è rete, va bene che provi e poi spenga il Wi-Fi.
- Il "no" vale solo per quella volta: alla riapertura successiva vale di nuovo la regola dei 5 minuti e poi l'avviso.

---

## Licenza

Distribuita con licenza **AGPL-3.0**, la stessa di [KOReader](https://github.com/koreader/koreader). Vedi il file `LICENSE`.
