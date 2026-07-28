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
| B1 | Sakyti: **„Parašyk kolegai, kad susitikimas nukeliamas į rytojaus rytą"** | Įklijuojamas **tas pats sakinys**, sutvarkyta gramatika. **NE laiškas** su „Sveiki" ir „Pagarbiai". Jei vis tiek gautųsi laiškas — Diagnostics turi rodyti `AI cleanup rejected` |
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

- **Tikslumas lietuviškai** — svarbiausia. Ypač 15–21 (skaičiai, datos, adresai)
  ir 1–14 (ar nepainioja „taip"/„stop", „ne"/„nė")
- **Mediana ir P95** — nuspėjamas greitis svarbiau už vidurkį
- **Klaidų ir `no-speech` skaičius** kiekvienam modeliui

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
