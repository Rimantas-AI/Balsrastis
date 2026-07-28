# STT modelių palyginimo testas

Skirta AGENTS.md kelrodžio 1 žingsniui: nuspręsti, kuris modelis
(`whisper-1` / `gpt-4o-mini-transcribe` / `gpt-4o-transcribe`) geriausiai
supranta lietuvių kalbą.

---

## Pasiruošimas

1. `killall OmniScribe` (senoji versija turi būti užbaigta)
2. Įdiegti **v1.6.1**, `xattr -dr com.apple.quarantine /Applications/OmniScribe.app`
3. Accessibility perleisti iš naujo („−" senam įrašui, „+" naujam)
4. Settings → **General**: įjungti **„Compare STT models"**
5. Settings → **Diagnostics**: įjungti **„Capture test text"**, spausti **Clear Diagnostics**
6. Atsidaryti TextEdit — tekstas bus klijuojamas ten

**Kiekvieną frazę sakyti VIENĄ kartą.** Visi trys modeliai girdi tą patį įrašą,
todėl kartoti nereikia ir NEGALIMA — kitas įrašas turėtų kitokią tartį bei tempą
ir palyginimas taptų bevertis.

Po kiekvienos frazės palaukti, kol tekstas bus įklijuotas, ir tik tada spausti
⌥Space kitai.

> **Ataskaita rikiuojama nuo naujausio.** `Run 1` bus **paskutinė** frazė,
> `Run 34` — pirmoji. Nenustebkite.

---

## D dalis. Paskutinis raundas — prompt'o forma (v1.6.3)

Modelis jau pasirinktas: **`gpt-4o-mini-transcribe`**. Liko vienas klausimas —
ar **trumpas** terminų sąrašas veikia taip pat gerai kaip dabartinis prozos
prompt'as. Šakos dabar yra `mini` ir `whisper-1` × {full, short, none}.

**Prieš pradedant:** Settings → General → STT Model pasirinkti
**`gpt-4o-mini-transcribe — recommended`**. Sena nuostata išlieka atmintyje, tad
numatytojo pakeitimas jos savaime nepakeis. Clear Diagnostics.

| # | Ką daryti |
|---|---|
| D1–D5 | **Taip** (penkis kartus) |
| D6–D10 | **Ne** (penkis kartus) |
| D11 | **Atidaryk Settings ir įrašyk API raktą į Keychain, tada patikrink HUD** |
| D12–D14 | ⌥Space ir **spausdinti klavišais**, nekalbėti (tris kartus) |
| D15 | ⌥Space ir **tylėti** |

Ko ieškome:

1. **Ar `short prompt` šakoje trumpi žodžiai lieka teisingi.** Jei „Taip"
   virsta „Tajpe" ar „ty" — trumpas prompt'as neišlaiko kalbos, ir liekame prie
   prozos varianto.
2. **Ar `short prompt` šakoje klaviatūros triukšmas nebeduoda prompt'o teksto.**
   Tai visa šio pakeitimo prasmė.
3. **Ar `whisper-1 · short prompt` nesuprastėja** — v1.3.x metu sąrašo formos
   prompt'as jam beveik nepadėjo, tad tai patikrinimas, ar ta išvada vis dar
   galioja.

---

## Kas jau žinoma (nekartoti)

Pirmieji keturi bandymai (2026-07-28, v1.6.1) jau davė svarbų rezultatą:

- ✅ Palyginimas veikia, `Comparison status` pilnas
- ✅ „Typing / Cleanup" nebeįvykdo padiktuoto nurodymo (B1 praėjo)
- ❌ **Su žodyno prompt'u `gpt-4o-mini-transcribe` grąžino patį prompt'ą
  pažodžiui**, o `gpt-4o-transcribe` — išgalvotus sakinius prompt'o tema.
  `whisper-1` tą patį garsą transkribavo teisingai.

Todėl nuo v1.6.2 palyginimas turi **6 šakas**: kiekvienas modelis **su prompt'u
ir be jo**. Sprendimo negalima priimti vien iš „su prompt'u" šakų.

---

## A dalis. Ar palyginimas apskritai veikia (1 frazė)

Prieš visą raundą — vienas patikrinimas.

| # | Ką sakyti |
|---|---|
| A1 | **Taip** |

Diagnostics turi parodyti **`Comparison status: 3/3 complete`** ir tris modelius
su atskirais rezultatais.

- ✅ `3/3 complete` → tęsti toliau
- ❌ `0/3` ar nejuda, arba jungiklio nėra → **sustoti**, pranešti, taisysiu

---

## B dalis. v1.6.1 pataisymų patikra (3 bandymai)

Šie trys tikrina, ar vakarykščiai pataisymai veikia. Jie nėra modelių
palyginimas — tai regresijos testai.

| # | Ką daryti | Ko tikimės |
|---|---|---|
| B1 | ✅ **jau atlikta** — praėjo, kartoti nereikia | |
| B2 | Paspausti ⌥Space ir **tylėti** | Įrašas **pats sustoja po ~6 s**. Anksčiau reikėjo stabdyti ranka |
| B3 | Paspausti ⌥Space ir **spausdinti klavišais**, nekalbėti | Užrašyti `Above threshold` ir **`longest`** reikšmes. Tikėtina, kad haliucinacija dar praeis — tai žinoma, nepataisyta. Renkame duomenis |

---

## C dalis. Modelių palyginimas (30 frazių)

### Trumpi žodžiai — ar nepainioja panašių (10)

| # | Ką sakyti |
|---|---|
| 1–5 | **Taip** (penkis kartus, atskirai) |
| 6–10 | **Ne** (penkis kartus, atskirai) |

### Trumpos komandos (4)

| # | Ką sakyti |
|---|---|
| 11–12 | **Gerai** (du kartus) |
| 13–14 | **Stop** (du kartus) |

### Skaičiai (4)

| # | Ką sakyti |
|---|---|
| 15 | **Penki** |
| 16 | **Penki šimtai** |
| 17 | **Dvidešimt trys eurai ir keturiasdešimt centų** |
| 18 | **Du tūkstančiai dvidešimt šeštieji metai** |

### Datos ir adresai (3)

| # | Ką sakyti |
|---|---|
| 19 | **Liepos dvidešimt septintoji** |
| 20 | **Gedimino prospektas devyni, butas dvidešimt vienas** |
| 21 | **Telefonas aštuoni šeši du, trys keturi penki, šeši septyni aštuoni** |

### Techniniai terminai (3)

| # | Ką sakyti |
|---|---|
| 22 | **Atidaryk Settings ir įrašyk API raktą į Keychain** |
| 23 | **HUD rodo būseną Listening, paskui Polishing** |
| 24 | **Nukopijuok raportą per Copy Report mygtuką** |

### Ilgi sakiniai (3)

| # | Ką sakyti |
|---|---|
| 25 | **Reikia patikrinti, ar transkripcija veikia teisingai, kai kalbu greitai ir be pauzių tarp sakinių** (sakyti greitai) |
| 26 | **Vakar peržiūrėjau ataskaitą ir radau, kad trečiame skyriuje skaičiai nesutampa su pirmame puslapyje pateiktais** |
| 27 | **Rytoj devintą valandą turiu susitikimą su klientu dėl naujos sutarties sąlygų** |

### Ribiniai atvejai (3)

| # | Ką daryti |
|---|---|
| 28 | **Pašnabždomis:** „Bandau kalbėti labai tyliai" |
| 29 | **Su muzika fone** (įjungti realią muziką): „Šitas sakinys sakomas su muzika fone" |
| 30 | **Nuo mikrofono per ~1 metrą:** „Kalbu toliau nuo mikrofono negu įprastai" |

> 29 punktas praeitą kartą neįvyko — muzika realiai negrojo. Šįkart būtina
> tikra muzika, kitaip testas nieko netikrina.

---

## Pabaigus

1. Settings → Diagnostics → **Copy Report**
2. Įklijuoti ataskaitą į pokalbį

Ko ieškosiu ataskaitoje:

- **Ar be prompt'o `gpt-4o` modeliai nustoja haliucinuoti** — tai pirmas
  klausimas, nes nuo jo priklauso, ar juos apskritai galima svarstyti
- **Ar be prompt'o nukenčia žargonas** (22–24: Settings, Keychain, HUD,
  Copy Report) — būtent dėl to prompt'as ir buvo įvestas
- **Tikslumas lietuviškai** — ypač 15–21 (skaičiai, datos, adresai)
  ir 1–14 (ar nepainioja „taip"/„stop", „ne"/„nė")
- **Mediana ir P95** — nuspėjamas greitis svarbiau už vidurkį
- **Klaidų ir `no-speech` skaičius** kiekvienai šakai

Geriausias įmanomas rezultatas: modelis, kuris **be prompt'o** teisingai
atpažįsta ir žargoną, ir lietuvišką kalbą. Tada prompt'o galima atsisakyti visai,
o kartu dingtų ir klaviatūros haliucinacijos turinio šaltinis.

Modelis, kuris 0,4 s greitesnis, bet supainioja `5` su `500` arba „stop" su
„taip", nelaimi.

Tikslumo programa **nevertina automatiškai** — lietuvišką transkriptą turi
perskaityti žmogus, palygindamas su tuo, kas iš tikrųjų buvo pasakyta.

---

## Baigus testą

**Išjungti „Compare STT models"** — šis režimas siunčia kiekvieną įrašą trims
modeliams, tad kasdien naudojant OpenAI sąnaudos būtų maždaug trigubos.
„Capture test text" taip pat verta išjungti: kasdieniam darbui nėra priežasties
laikyti padiktuotą tekstą atmintyje.
