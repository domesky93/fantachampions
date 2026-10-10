# ⭐ Fanta Champions

Fantacalcio della Champions League. Ogni giornata schieri **11 titolari + 7 panchinari** (1 portiere, 2 difensori, 2 centrocampisti, 2 attaccanti) scegliendo tra tutti i giocatori della competizione, entro un budget di crediti. Punteggio con **voto + bonus/malus**, sostituzioni automatiche dalla panchina, classifica generale e leghe private con codice invito.

Tecnologia: sito statico (HTML + JavaScript, nessuna build) su **Cloudflare Pages**, database e login su **Supabase**.

---

## 1. Crea il database su Supabase (10 minuti)

1. Vai su <https://supabase.com>, crea un account e un **nuovo progetto** (regione: *Central EU – Frankfurt*). Annota la password del database.
2. Apri **SQL Editor → New query** ed esegui, **uno alla volta e in quest'ordine**, i file della cartella `supabase/`:
   1. `01_schema.sql` — tabelle
   2. `02_functions.sql` — logica di gioco (salvataggio formazione, calcolo punti, leghe)
   3. `03_security.sql` — regole di sicurezza
   4. `04_seed.sql` — le 36 squadre e le 8 giornate della fase campionato 2026/27
   5. `05_players.sql` — i 1022 giocatori con i prezzi
   6. `06_photos.sql` — colonne per le foto dei giocatori
3. In **Project Settings → API** copia:
   - **Project URL** (es. `https://abcd1234.supabase.co`)
   - **anon public key**
4. Incolla i due valori in `js/config.js`.

> La chiave *anon* è fatta per stare nel sito: la sicurezza è garantita dalle regole del file `03_security.sql`. **Non** usare mai la chiave `service_role` nel sito.

### Impostazioni di login
In **Authentication → URL Configuration** metti come *Site URL* l'indirizzo del sito (lo avrai al punto 2, es. `https://fanta-champions.pages.dev`).
Per i primi test puoi disattivare la conferma email in **Authentication → Providers → Email → Confirm email**.

---

## 2. Metti il sito online su Cloudflare Pages (5 minuti)

**Metodo semplice (trascina la cartella):**
1. Vai su <https://dash.cloudflare.com> → **Workers & Pages → Create → Pages → Upload assets**.
2. Dai un nome al progetto (es. `fanta-champions`) e trascina **tutta la cartella** del progetto (quella con `index.html`).
3. Clicca **Deploy**. Avrai un indirizzo tipo `https://fanta-champions.pages.dev`.

Per aggiornare il sito: stesso progetto → **Create new deployment** → trascina di nuovo la cartella.

**Metodo con GitHub (consigliato più avanti):** metti la cartella in un repository GitHub, poi in Cloudflare Pages scegli *Connect to Git*. Build command: *vuoto*. Output directory: `/`. Ogni modifica pubblicata su GitHub aggiorna il sito da sola.

---

## 3. Diventa amministratore

1. Registrati sul sito con il tuo account.
2. In Supabase → **SQL Editor** esegui (cambia lo username):
   ```sql
   update public.profiles set is_admin = true where username = 'domenico';
   ```
3. Ricarica il sito: compare la voce **Admin**.

---

## 4. Carica i giocatori

Il listone completo della Champions 2026/27 è già pronto: **1022 giocatori delle 36 squadre con i prezzi**.
Hai due modi per caricarlo (sono equivalenti):

- **SQL Editor di Supabase** → esegui `supabase/05_players.sql` (il più veloce), oppure
- **Admin → Giocatori → Importa rose da CSV** → scegli `giocatori-champions-2026-27.csv`.

### Come sono fatti i prezzi
Ogni giocatore ha una fascia di valore, moltiplicata per il ruolo (gli attaccanti costano di più perché portano più bonus):

| Fascia | Chi | Attaccante | Centrocampista | Difensore | Portiere |
|---|---|---|---|---|---|
| S | fuoriclasse (Mbappé, Kane, Haaland, Yamal, Lautaro…) | 50 | 42 | 35 | 30 |
| A | top (Bellingham, Pedri, Barella, Dimarco, McTominay…) | 36 | 31 | 25 | 22 |
| B | big / portieri delle grandi | 26 | 22 | 18 | 16 |
| C | titolari forti | 17 | 14 | 12 | 10 |
| D | titolari | 11 | 9 | 8 | 7 |
| E | rotazione / titolari squadre piccole | 7 | 6 | 5 | 4 |
| F | riserve, giovani, portieri di riserva | 4 | 3 | 3 | 2 |

Con 300 crediti per 18 giocatori la media è circa 16,7 a testa. Il prezzo medio del listone è 10, quindi si può fare una buona squadra, ma non una squadra di soli campioni: chi prende 3 fuoriclasse in attacco (150 crediti) deve poi mettere difensori e portiere quasi a costo zero.

Per cambiare i prezzi: modifica le fasce in `tools/prezzi.py`, esegui `python3 tools/prezzi.py` e reimporta il CSV. Oppure correggi il singolo giocatore da Admin → Giocatori.

> Le rose vengono da Wikipedia (ottobre 2026). Dai un'occhiata alla tua squadra del cuore e correggi eventuali errori o trasferimenti dal pannello Admin. I giocatori che non sono nella lista UEFA si possono disattivare togliendo la spunta **Attivo**.

### Foto dei giocatori
Admin → **Giocatori** → **📷 Cerca foto mancanti**. Il sito cerca su Wikipedia la foto di ogni giocatore, usando solo immagini con **licenza libera** (Wikimedia Commons). Per ogni foto salva anche autore e licenza, che tutti possono vedere nella pagina **Crediti foto** (dal Profilo o in fondo alla Formazione): le licenze Creative Commons lo richiedono.

- Ci vogliono 1-3 minuti, lascia la pagina aperta.
- I giocatori senza foto libera continuano a vedersi con la maglia della squadra.
- Se una foto è sbagliata (omonimi), incolla un altro link nella colonna *Link foto* oppure svuotala e premi **Salva**.
- Non usare foto prese da siti ufficiali o agenzie: sono protette da copyright.

### Formato del CSV
Per aggiungere giocatori o aggiornare le rose (separatore `;`):

```
nome;ruolo;squadra;prezzo
Lautaro Martinez;A;Inter;38
Yann Sommer;P;Inter;14
```

- `ruolo`: **P**, **D**, **C**, **A**
- `squadra`: nome come nell'elenco (es. *Inter*, *Bayern Monaco*, *Real Madrid*) o sigla (*INT*, *BAY*, *RMA*)
- `prezzo`: crediti (con budget 300 per 18 giocatori, la media è ~16)

Puoi reimportare il file quando vuoi: i giocatori esistenti vengono aggiornati. Per togliere un giocatore (infortunato a lungo, ceduto) togli la spunta **Attivo**.

---

## 5. Ogni giornata

1. **Prima della scadenza** i giocatori schierano la formazione (il sito la blocca da solo all'ora indicata).
2. **Dopo le partite** → Admin → **Voti e calcolo**:
   - scegli giornata e squadra; con *Solo giocatori schierati* vedi solo quelli che servono
   - inserisci il voto (vuoto = *senza voto*) e gol, assist, cartellini, rigori, autogol, gol subiti
   - oppure importa un CSV: `nome;squadra;voto;gol;assist;amm;esp;rp;rs;ag;gs`
3. Premi **⚡ Calcola giornata**. La classifica si aggiorna subito. Se correggi un voto, ricalcola.

---

## Regole di punteggio (modificabili in Admin → Impostazioni)

| Evento | Punti |
|---|---|
| Gol | +3 |
| Assist | +1 |
| Rigore parato | +3 |
| Porta inviolata (portiere) | +1 |
| Ammonizione | −0,5 |
| Espulsione | −1 |
| Gol subito (portiere) | −1 |
| Autogol | −2 |
| Rigore sbagliato | −3 |

**Sostituzioni:** se un titolare è senza voto, entra il primo panchinaro **dello stesso ruolo** che ha preso voto (in ordine di panchina), fino a 3 cambi. Se nessuno può entrare, quel posto vale 0.

**Vincoli formazione:** moduli 3-4-3, 3-5-2, 4-3-3, 4-4-2, 4-5-1, 5-3-2, 5-4-1 · budget 300 crediti · massimo 3 giocatori della stessa squadra reale.

---

## Struttura dei file

```
index.html              pagina principale
css/style.css           grafica
js/config.js            ← URL e chiave Supabase
js/app.js               navigazione
js/api.js               collegamento al database
js/ui.js                utility (finestre, avvisi, CSV)
js/views/               le pagine: home, formazione, classifica, leghe, admin, profilo, login
supabase/*.sql          database, logica e sicurezza
giocatori-esempio.csv   modello per importare le rose
giocatori-champions-2026-27.csv   listone completo con prezzi
tools/prezzi.py         script che calcola i prezzi (fasce modificabili)
```
