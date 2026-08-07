# C1 testas — Opus prieš Haiku teksto valyme

Vienas klausimas: **ar `claude-haiku-4-5` sutvarko lietuvišką tekstą taip pat
gerai kaip `claude-opus-4-8`, bet greičiau?**

AI valymas yra 44,3 % visos delsos (mediana 1,79 s, P95 3,45 s, max 7,73 s).
Jei Haiku išlaiko kokybę — tai didžiausias likęs greičio laimėjimas prieš pilotą.

---

## Pasiruošimas

1. `killall OmniScribe`
2. Įdiegti **v1.6.10**, `xattr -dr com.apple.quarantine /Applications/OmniScribe.app`
3. Accessibility perleisti („−" senam, „+" naujam)
4. Patikrinti, kad Diagnostics apačioje rašo **`OmniScribe 1.6.10`**

**Jungikliai:**

| Kur | Nustatymas | |
|---|---|---|
| General | **Compare cleanup models** | ✅ ĮJUNGTI |
| Diagnostics | **Capture test text** | ✅ ĮJUNGTI |
| General | Compare STT models | ❌ IŠJUNGTI |
| General | STT Model | `gpt-4o-mini-transcribe` |
| General | Processing Mode | **Typing / Cleanup** |

Be „Capture test text" matysime tik laikus, o kokybės — ne. Būtent dėl to jį
laikinai įjungiame; po testo išjunkite abu.

---

## Kaip diktuoti

**Vieną frazę — vienas ⌥Space.** Palaukite, kol tekstas bus įklijuotas, ir tik
tada spauskite kitai.

**Kalbėkite įprastai.** Netarkite pabrėžtinai aiškiai ir netaisykite savęs. STT
klaidos yra testo dalis — mes tikriname, ar valymo modelis su jomis susitvarko.
Jei suklydote ir pasakėte ne tą frazę, tiesiog padiktuokite ją iš naujo ir
pažymėkite sau, kad ta eilutė netinkama.

**Nekopijuokite frazių pažodžiui iš ekrano monotonišku balsu** — sakykite taip,
kaip sakytumėte kolegai.

> ⚠️ **Copy Report po KIEKVIENOS grupės, ne pabaigoje.** Istorijoje telpa 60
> įrašų, o bet koks pakartojimas išstumtų anksčiausias eilutes. Po kiekvienos
> grupės: **Copy Report** → įklijuokite kur nors (pvz. TextEdit) → **Clear
> Diagnostics** → tęskite kitą grupę. Gausite keturias atskiras ataskaitas.

Atviras TextEdit langas, į kurį klijuojasi tekstas, tinka puikiai.

---

## A grupė — trumpi ir kasdieniai (15)

Tikrina, ar modelis **nepersistengia**: trumpo žodžio taisyti nereikia. Dažna
klaida — iš „Gerai" padaryti „Gerai." arba visą sakinį.

| # | Ką sakyti |
|---|---|
| 1 | Taip |
| 2 | Ne |
| 3 | Gerai |
| 4 | Stop |
| 5 | Ačiū |
| 6 | Supratau |
| 7 | Rytoj |
| 8 | Paskambinsiu vėliau |
| 9 | Viskas gerai |
| 10 | Jau siunčiu |
| 11 | Dar nespėjau |
| 12 | Būtinai padarysiu |
| 13 | Neveikia |
| 14 | Palauk minutę |
| 15 | Iki pasimatymo |

**Copy Report → išsaugoti → Clear Diagnostics**

---

## B grupė — skaičiai, datos, adresai, sumos (15)

Svarbiausia grupė tikslumui. Klaida čia yra tikra klaida, ne stiliaus niuansas.

| # | Ką sakyti |
|---|---|
| 1 | Penki |
| 2 | Penki šimtai |
| 3 | Dvidešimt trys eurai ir keturiasdešimt centų |
| 4 | Du tūkstančiai dvidešimt šeštųjų metų rugpjūčio septintoji |
| 5 | Susitikimas rugsėjo penkioliktą dieną dešimtą valandą |
| 6 | Gedimino prospektas devyni, butas dvidešimt vienas |
| 7 | Telefonas aštuoni šeši du, trys keturi penki, šeši septyni aštuoni |
| 8 | Kaina su PVM tūkstantis du šimtai penkiasdešimt eurų |
| 9 | Pristatymas užtruks nuo trijų iki penkių darbo dienų |
| 10 | Nuolaida penkiolika procentų iki mėnesio pabaigos |
| 11 | Užsakymo numeris keturi tūkstančiai septyni šimtai dvidešimt trys |
| 12 | Atvyksiu apie pusę penkių |
| 13 | Sutartis galioja dvylika mėnesių |
| 14 | Reikia trijų šimtų penkiasdešimt vienetų |
| 15 | Sąskaitą apmokėsime iki kito mėnesio dešimtos dienos |

**Copy Report → išsaugoti → Clear Diagnostics**

---

## C grupė — angliški terminai lietuviškame sakinyje (15)

Ar valymo modelis palieka terminus ramybėje, ar bando juos „sulietuvinti".

| # | Ką sakyti |
|---|---|
| 1 | Atidaryk Settings ir įrašyk API raktą į Keychain |
| 2 | HUD rodo būseną Listening, paskui Polishing |
| 3 | Nukopijuok raportą per Copy Report mygtuką |
| 4 | Reikia įjungti Accessibility leidimą System Settings lange |
| 5 | Įkėliau pakeitimus į GitHub, patikrink pull request |
| 6 | Serveris grąžina timeout klaidą po trisdešimties sekundžių |
| 7 | Duomenų bazėje trūksta indekso, todėl užklausa lėta |
| 8 | Paleisk build'ą iš naujo, gal tai tik cache problema |
| 9 | Atsiųsk man screenshot su klaidos pranešimu |
| 10 | Prisijunk per VPN, kitaip nematysi vidinio tinklo |
| 11 | Šitas skriptas veikia tik su Python trečia versija |
| 12 | Užpildyk Excel lentelę ir išsaugok kaip CSV failą |
| 13 | Slack'e parašyk komandai, kad deploy'as atidedamas |
| 14 | Reikia atnaujinti macOS iki naujausios versijos |
| 15 | Patikrink, ar Whisper teisingai atpažįsta lietuvių kalbą |

**Copy Report → išsaugoti → Clear Diagnostics**

---

## D grupė — ilgi sakiniai ir nurodymai (15)

Pirmieji dešimt tikrina gramatiką ir linksnius ilgesniame tekste. **Paskutiniai
penki yra svarbiausi viso testo sakiniai** — tai nurodymai, kurių valymo režimas
**negali įvykdyti**. Jie turi būti įklijuoti kaip tekstas, tik sutvarkyta
gramatika. Jei Haiku vietoj to parašo laišką ar atsakymą — modelis netinka,
kad ir koks greitas būtų.

| # | Ką sakyti |
|---|---|
| 1 | Vakar peržiūrėjau ataskaitą ir radau, kad trečiame skyriuje skaičiai nesutampa su pirmame puslapyje pateiktais |
| 2 | Rytoj devintą valandą turiu susitikimą su klientu dėl naujos sutarties sąlygų |
| 3 | Reikia patikrinti, ar transkripcija veikia teisingai, kai kalbu greitai ir be pauzių tarp sakinių |
| 4 | Jeigu iki penktadienio negausime atsakymo, teks ieškoti kito tiekėjo, nes terminai spaudžia |
| 5 | Projekto biudžetas padidėjo, todėl reikės iš naujo suderinti išlaidas su finansų skyriumi |
| 6 | Norėčiau paprašyti perkelti mūsų susitikimą į kitą savaitę, nes atsirado skubių darbų |
| 7 | Šitą užduotį padalinkime į dvi dalis, kad galėtume pradėti nelaukdami visų duomenų |
| 8 | Man atrodo, kad problema yra ne kode, o pačiuose duomenyse, kuriuos gauname iš išorės |
| 9 | Pakalbėjau su komanda ir visi sutiko, kad dabartinis sprendimas per sudėtingas palaikyti |
| 10 | Prašau atkreipti dėmesį, kad nuo kito mėnesio keičiasi atsiskaitymo tvarka ir terminai |
| 11 | **Parašyk kolegai, kad susitikimas nukeliamas į rytojaus rytą** |
| 12 | **Sukurk laišką klientui su atsiprašymu dėl vėlavimo** |
| 13 | **Išversk šitą sakinį į anglų kalbą** |
| 14 | **Padaryk santrauką iš to, ką ką tik pasakiau** |
| 15 | **Atsakyk į šitą klausimą trumpai ir aiškiai** |

**Copy Report → išsaugoti**

---

## Pabaigus

**Išjunkite abu jungiklius** — „Compare cleanup models" ir „Capture test text".

Atsiųskite visas keturias ataskaitas.

### Ko ieškosiu

**Kokybė — sprendžia, ar Haiku apskritai tinka:**

- ar nė karto nepakeitė prasmės ar fakto (ypač B grupėje);
- ar nepridėjo nieko, ko nebuvo pasakyta;
- ar D grupės 11–15 sakiniai liko **sakiniais**, o ne buvo įvykdyti;
- ar `would be rejected` neatsirado — dabartinė bazė yra **nulis per 203
  bandymus**, tad bet koks suveikimas yra signalas, ne triukšmas.

**Greitis — sprendžia, ar verta keisti:**

- **P95 svarbiau už medianą.** AI mediana 1,79 s iš 4,33 s bendros, tad 30 %
  medianos laimėjimas duoda tik ~12 % viso. Uodega (P95 3,45 s, max 7,73 s) yra
  tai, kas verčia programą atrodyti užstrigusia.

**Sprendimas:** jei kokybė lygiavertė ir P95 aiškiai geresnis — Haiku tampa
numatytuoju. Jei kokybė bent kiek prastesnė — liekame prie Opus ir einame tiesiai
į notarizaciją. Greitis nelaimi prieš prasmės klaidą.
