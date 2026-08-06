# OmniScribe — planas po savaitės validacijos

Dokumentas skirtas nepriklausomam vertinimui. Savarankiškas: visi skaičiai
pateikti, konteksto iš pokalbio nereikia.

---

## 1. Kur esame

Programa: macOS meniu juostos diktavimo įrankis. ⌥Space → įrašas → OpenAI STT →
Claude sutvarko tekstą → įklijuojama į aktyvią programą. Pagrindinė kalba —
lietuvių.

Ką ką tik baigėme (kelrodžio 1–3 žingsniai):

- **STT modelio pasirinkimas** — 45 klipai per du raundus, palyginimas to paties
  garso pagrindu per 6 šakas. Rezultatas: `gpt-4o-mini-transcribe` + ilgas
  prozinis žodyno prompt'as. Atmesta su įrodymais: be prompt'o (trumpi žodžiai
  virsta kitomis rašto sistemomis) ir trumpas prompt'as (atkartojimas išlieka,
  bet tampa per trumpas, kad apsauga jį pagautų).
- **Savaitės realaus naudojimo validacija** — 203 bandymai per du Mac'us.

### Validacijos rezultatai (pagrindinis Mac, 132 bandymai per 7 dienas)

| Kelrodžio reikalavimas | Tikslas | Rezultatas | |
|---|---|---|---|
| Įklijuotų haliucinacijų | 0 | 0 aptinkamų | ✅ |
| Klaidingai užblokuota kalba | ≤1–2 % | 0 % (2 blokavimai, abu pagrįsti) | ✅ |
| Mediana | ≤~5 s | 4,33 s | ✅ |
| P95 be 15–20 s šuolių | — | 7,15 s, max 11,67 s | ✅ |

Sėkmė 98,5 % (130/132). Apsaugos per visus 203 bandymus **nė karto nesuveikė
klaidingai**.

### Delsos struktūra (pagrindinis Mac)

| Etapas | Mediana | P95 | Max | Dalis |
|---|---|---|---|---|
| **AI valymas (Claude)** | 1,79 s | 3,45 s | 7,73 s | **44,3 %** |
| STT | 1,09 s | 2,33 s | 5,15 s | 29,0 % |
| VAD tylos laukimas | 1,20 s | 1,21 s | 1,21 s | 23,8 % |
| Įklijavimas | 0,13 s | 0,16 s | 0,27 s | 2,9 % |

Antrame Mac'e (senesnis, macOS 12): mediana 5,47 s, AI 43,6 %, STT 32,3 %.
Struktūra ta pati.

### Žinomos, išmatuotos problemos

1. **Ventiliatoriaus triukšmas išjungia automatinį sustojimą — 7,6 % (10/132).**
   Nuolatinis foninis triukšmas virš fiksuoto 0,012 RMS slenksčio reiškia, kad
   tylos niekada nebūna, todėl nei 1,2 s tylos, nei 6 s pradinis laikmatis
   nesuveikia. Įrašas tęsiasi, kol vartotojas paspaudžia ⌥Space.
   Matavimo pasekmė: tose eilutėse `total_s` **optimistiškai iškreiptas**
   (mediana 3,50 s prieš 4,41 s automatinių), nes į jį nepatenka laikas, per kurį
   vartotojas pastebi, kad programa nesustojo. Tikroji mediana be jų — 4,41 s.
2. **Neišaiškinti STT gedimai — 5,6 % antrame Mac'e (4/71).** Eilutės turi
   patvirtintą kalbą, bet `stt_s = 0` ir `model = —`, t. y. lūžo pati užklausa.
   Žurnale nėra gedimo kategorijos, todėl neaišku, ar tai tinklas, timeout, 429,
   ar 401. Pagrindiniame Mac'e tokių gedimų nebuvo nė vieno.
3. **Naudojimas netolygus:** 3/3/2/**105**/2/10/7 per dienas. Programa atidaroma
   7 skirtingomis dienomis (geras išlaikymo ženklas), bet apimtis susitelkusi
   vienoje sesijoje. Vis dar arčiau testo nei natūralaus kasdienio darbo.
4. **„Nulis haliucinacijų" reiškia „nulis aptinkamų".** Žurnale sąmoningai nėra
   teksto. Trumpos, tikroviškai skambančios haliucinacijos jis nepagautų.

---

## 2. Siūlomas planas

### A. Uždaryti dokumentaciją (be rizikos, ~10 min)

Įrašyti validacijos rezultatus į AGENTS.md, uždaryti kelrodžio 2–3 žingsnius.
Kodas nekeičiamas.

### B. `failure_category` žurnale (mažas, ~30 min)

Fiksuotų reikšmių laukas: `network_timeout`, `network`, `invalid_api_key`,
`rate_limited`, `bad_request`, `server_error`, `invalid_response`. Jokių klaidų
tekstų, jokio turinio. Be jo kiekvienas būsimas gedimas lieka neišaiškintas.

### C. AI valymo delsa — didžiausias likęs svertas (vidutinis)

AI yra 44,3 % delsos ir didžiausia uodega (max 7,73 s). Vieno žodžio
diktavimams („Taip", „Ne") Claude sugaišta 1,1–2,5 s nieko nepakeisdamas.

Trys galimi keliai:

- **C1. Pigesnis/greitesnis modelis valymui.** Dabar naudojamas
  `claude-opus-4-8`. Gramatikos taisymui tai greičiausiai per stipru. Haiku
  klasės modelis galėtų būti 2–3× greitesnis. **Būtina išmatuoti, ne spėti** —
  tas pats principas kaip su STT. Palyginimas čia pigus, nes įvestis yra
  **tekstas**, ne garsas: tą patį transkriptą galima siųsti dviem modeliams
  lygiagrečiai ir įrašyti abu rezultatus.
- **C2. Raw Dictation režimas** — vartotojo pasirenkamas, visiškai praleidžia
  Claude. Pašalintų 44 % delsos tiems atvejams, kai valymo nereikia.
- **C3. Automatinis trumpo teksto apėjimas** — pvz. ≤2 žodžiai → nesiųsti į AI.
  **Nerekomenduoju**: tai tylus elgesio pakeitimas, o šiame projekte tylūs
  pakeitimai jau kartą kainavo.

### D. Ventiliatoriaus problema (vidutinis, rizikingas)

Kryptis: tyla matuojama **santykinai** su besisukančiu triukšmo lygiu, o ne
absoliučiu 0,012 RMS.

**Pagrindinė rizika, dėl kurios iki šiol nedaryta:** jei triukšmo lygio įvertis
paimamas iš įrašo, kuriame nėra tylių akimirkų, jis pakyla iki pačios kalbos
lygio — tada viskas laikoma tyla ir sakinys nukertamas per vidurį. Būtina
sąlyga: triukšmo lygiu pasitikėti tik po to, kai realiai stebėtas tylus
laikotarpis.

7,6 % dažnis — ties riba. Ne kasdienė kančia, bet ir ne retenybė.

### E. Notarizacija + pirmo paleidimo vediklis (didelis, blokuojamas)

Kelrodžio 4 žingsnis. Vienintelis dalykas, atveriantis programą kitiems
žmonėms — dabar reikia `xattr` komandos terminale ir Accessibility perleidimo po
kiekvieno atnaujinimo. Reikia Apple Developer paskyros (99 $/metus) ir vartotojo
kredencialų; agentas jų pateikti negali.

---

## 3. Eiliškumo klausimas — čia norime nuomonės

Yra du gynybini požiūriai, ir aš nesu tikras, kuris teisingas.

**Variantas 1 — pirma notarizacija (E), paskui optimizavimas.**
Argumentas: 4,33 s mediana jau priimtina, programa veikia. Kelrodžio 6 žingsnis
sako „tegul realūs naudojimo įpročiai nusprendžia, ką verta statyti, o ne
spėlionės". Uždaras testas su 5–10 žmonių duotų informacijos, kurios dabar
neturime, ir gali paaiškėti, kad delsa jiems visai ne problema — o problema yra
kažkas, ko net nesvarstome.

**Variantas 2 — pirma C1 (greitesnis valymo modelis), paskui notarizacija.**
Argumentas: 44 % delsos yra didelis, išmatuotas ir žinomas dydis. Duoti žmonėms
programą, kuri be reikalo lėtesnė 1–2 s, kai tai pataisoma per vieną testų
raundą, būtų neapdairu. Be to pirmas įspūdis pilotui yra svarbus.

**Papildomi klausimai vertintojui:**

1. Ar `claude-opus-4-8` keitimas į Haiku klasės modelį lietuvių gramatikos
   taisymui yra pagrįsta rizika? Ar yra priežasčių manyti, kad būtent lietuvių
   morfologijai reikia stipraus modelio?
2. Ar 7,6 % ventiliatoriaus dažnis pateisina VAD keitimą, ar geriau laukti
   piloto duomenų iš kitų mikrofonų ir aplinkų?
3. Ar Raw režimas turėtų būti atskiras režimas (C2), ar apskritai nereikalingas,
   jei C1 pakankamai sumažina delsą?
4. Ar prieš pilotą reikia dar ko nors, ko nematome? Ypač: klaidų pranešimai
   vartotojui, kuris nėra kūrėjas.

---

## 4. Ko sąmoningai NEDARYSIME

- **Lokalus Whisper (whisper.cpp).** Buvo pasiūlytas atskirai. Priežastys prieš:
  STT yra tik 29 % delsos, tad net momentinis lokalus STT nepašalintų dominuojančio
  AI etapo; Intel iMac (2015 m., 4 branduoliai) su `base`/`small` modeliais
  realiai būtų **lėtesnis** už dabartinę 1,09 s medianą; `base`/`small` lietuvių
  kalbos tikslumas prastesnis nei `gpt-4o-mini-transcribe`; ir tai nėra privatumo
  sprendimas, kol transkriptas vis tiek siunčiamas Claude.
- **Automatinis perjungimas į atsarginį STT modelį po „no speech".** Antras
  modelis iš to paties triukšmo gali sukurti haliucinaciją. Perjungimas leistinas
  tik po **techninės** klaidos.
- **Naujos apsaugos be duomenų.** Turime kandidatą — išlaikymo santykį
  (`longest_span / above_threshold`), kuris triukšme buvo 0,17–0,22, o kalboje
  0,38–1,0. Bet tai remiasi keturiais triukšmo pavyzdžiais. Nestatome, kol
  neprasmuks reali haliucinacija.
- **Skaičių formos keitimas AI prompt'e.** `whisper-1` rašė „862-345-678", o
  `gpt-4o-mini` — „aštuoni šeši du...". Pagunda liepti Claude normalizuoti, bet
  tai sugadintų atvejus, kur žodžiai prasmingi („penki šimtai žingsnių").
