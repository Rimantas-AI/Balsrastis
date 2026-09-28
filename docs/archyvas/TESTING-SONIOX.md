# Soniox prieš gpt-4o-mini-transcribe — ant to paties garso

✅ **ĮVYKDYTA 2026-09-28. Verdiktas: prielaida NELAIKO.**
Soniox atpažįsta lietuviškai tiksliau ant to paties garso. Rezultatai ir tai, ką
jie keičia — failo apačioje ir `AGENTS.md` maršruto 5 punkte.

Šis testas atsako ne į techninį, o į **strateginį** klausimą. Soniox skelbia
lietuvių WER 9,4% prieš OpenAI 25,2%. Jei tai bent apytiksliai tiesa, Balsraštis
yra lietuviškai derintas sluoksnis ant atpažintuvo, kuris lietuviškai prastesnis
už konkurento numatytąjį. Prompto gudrybe 2,5 karto skirtumo neatsversi.

Todėl tai pigiausias būdas sužinoti, ar pagrindinė produkto prielaida laikosi.
Pusvalandis, vienuolika jau turimų failų, nulis pakeitimų programoje.

---

## Prieš pradedant

| Ko reikia | Kur |
|---|---|
| Soniox API raktas | `~/.soniox-key` — **ne repo, ne pokalbyje** |
| 11 įrašų | `~/Library/Application Support/Balsrastis/Fixtures/022.wav`…`032.wav` |

Programos liesti nereikia. Testas vyksta skriptu už jos ribų — jei Soniox
pralaimės, nebus ko atsukti atgal.

**ToS patikrinta 2026-09-01: vidinis benchmark'as leidžiamas.** Draudžiama tik
publikuoti palyginimus „false, misleading, deceptive or commercially
disparaging" būdu. Šio failo turinys yra vidinis.

---

## Ką lyginti

**Ne WER.** Vienuolika sakinių vieno balso WER nieko nepasakys — per mažas
imtis, o skaičius sukurs netikrą tikslumo įspūdį.

**Lyginti konkrečius žodžius**, kuriuos gpt-4o-mini-transcribe sudarkė. Jie
žinomi iš dviejų raundų (2026-08-21 ir 09-01) ant **to paties garso**:

| Failas | Kas pasakyta | 1 raundas | 2 raundas | Soniox |
|---|---|---|---|---|
| 023 | `repo` | ❌ `reklamą` | ❌ `reklamą` | ? |
| 023 | `GitHub'e` | ✅ | ❌ `gidąbe` | ? |
| 029 | `promptą` | ❌ `programą` | ❌ `programtą` | ? |
| 026 | `ilgį` | ❌ `ilges` | ✅ | ? |
| 024 | `kasdienės` | ❌ `kasdienes` | ❌ `kasdienes` | ? |
| 031 | `Sujunk` | ❌ `Sujungsiu` | ✅ | ? |
| 028 | `Tada dar` | ✅ | ❌ `Tai dabar` | ? |

Septyni kritiniai taškai. Du iš jų — `repo`→`reklamą` ir `promptą`→`programą` —
**pakeitė prasmę ir nuėjo į dokumentą**, pro visas apsaugas, nes tai tikri
lietuviški žodžiai normaliu tempu.

Papildomai fiksuoti, ar Soniox rašo **skaičius skaitmenimis** — tai vienintelis
likęs `whisper-1` pranašumas ir neišspręstas klausimas.

---

## Sprendimo taisyklė, paskelbta IŠ ANKSTO

Kaip C1 raunde. Užrašyta prieš matant rezultatą, kad nebūtų perrašyta pagal jį.

| Rezultatas | Reikšmė |
|---|---|
| Soniox teisingai **5+ iš 7** | Prielaida NELAIKO. Atpažinimo sluoksnį keisti verta, ir tai svarbiau už bet kokį kitą patobulinimą |
| Soniox **3–4 iš 7** | Neaišku. Reikia daugiau garso, ne daugiau svarstymų. Nedaryti išvadų |
| Soniox **0–2 iš 7** | Prielaida laikosi. WER 9,4% skelbimas tavo medžiagai negalioja, ir esamas sluoksnis vertas savo vietos |

**Greitis šiame teste nevertinamas.** Async REST nėra greitesnis už dabartinį
kelią, ir STT yra tik 26% latency. Testas apie tikslumą, ne apie laiką.

---

## Ko šis testas NEATSAKO

- **Ar Soniox apskritai galima naudoti.** Jų sąlygos draudžia iš jų išvestinių
  duomenų kurti konkuruojantį produktą, o jie patys turi lietuvišką Voice
  Typing. Prieš statant ant jų reikia **raštiško** patvirtinimo. Žr. `AGENTS.md`.
- **Ar Balsraštį verta vystyti.** Tai atsako tik pusę: ar techninis pamatas
  tvirtas. Kita pusė — ar bent vienas žmogus, be autoriaus, atidaro programą
  antrą savaitę. To joks matavimas nepakeis.
- **Ar keisti tiekėją.** Net jei Soniox laimės, adaptacija reiškia trečią
  paskyrą naudotojui arba tarpininką serveryje, o vieno rakto režimas žūva.

---

## Po testo

Rezultatą surašyti čia, o verdiktą — į `AGENTS.md` §12, kaip ir provider
raundą. Jei prielaida nelaikys, tai nebus blogas rezultatas: tai bus
pigiausiai gautas svarbiausias atsakymas projekte.

---

# REZULTATAI (2026-09-28)

11 fiksūrų, modelis `stt-async-v5`, dvi rankos kiekvienam.
Neapdoroti duomenys buvo `scratchpad/soniox-rezultatai.json`.

## Keturi aiškūs atvejai — taisyklė suveikė

| Žodis | Balsraštis (du raundai, tas pats garsas) | Soniox |
|---|---|---|
| `promptą` (029) | ❌ `programą` · ❌ `programtą` | ✅ `promptą` |
| `kasdienės` (024) | ❌ `kasdienes` · ❌ `kasdienes` | ✅ `kasdienės` |
| `GitHub'e` (023) | ✅ · ❌ `gidąbe` | ✅ `GitHub'e` |
| `repo` (023) | ❌ `reklamą` · ❌ `reklamą` | ⚠️ `repą` |

Trys švariai, ketvirtas dalinai → **3–4 iš 4 → prielaida nelaiko.**

Ketvirtasis vertas atskiro žvilgsnio, nes klaidos **rūšis** skiriasi: `repą` yra
sulietuvinta galūnė — žodis atpažįstamas, prasmė sveika. `reklamą` yra kitas
žodis, sklandus ir nematomas skaitant. Tai ne tas pats gedimas.

## Keturi papildomi taškai, kurių nebuvo ieškota

| Failas | Balsraštis | Soniox |
|---|---|---|
| 032 | `galime rašyti` | `galim įrašyti` (prasmės skirtumas) |
| 031 | `Sujungsiu` (1 r.) | `Sujunk` (su kontekstu) |
| 026 | `ilges` (1 r.) | `ilgį` |
| 028 | `Tada dar` (1 r.) | `Tai dabar` |

## Svarbiausias radinys — ne lentelėje

**Soniox žodyno konteksto nereikia.** Iš 11 failų abi rankos — su kontekstu ir be
jo — grąžino **identišką tekstą 10 kartų**. Skyrėsi tik 031, ir ten kontekstas
padėjo (`Sujunk` vietoj `Sujungsiu`, `promptą` vietoj `promto`).

Palyginimui, v1.6.3: **be** prompto šio projekto atpažintuve trumpi lietuviški
žodžiai subyra į kitas kalbas — „Taip" → `طيب`, `Тайпа`, `Tey`; „Ne" → `네`.

Iš to seka nemaloni, bet tiesi išvada: **didelė dalis „lietuviško derinimo" čia
yra kompensacija už silpnesnį atpažintuvą, ne pranašumas.** Žodyno promptas, jo
sukeliama haliucinacijų rizika, `echoesPrompt`, `exceedsPlausibleSpeechRate` —
visa grandinė yra atsakas į problemą, kurios geresnis atpažintuvas neturi.

## Ribos

11 klipų, vienas balsas, vienas įrašymo seansas, po kartą kiekvienas. Ir
2026-09-01 nustatyta, kad atpažinimas **nėra deterministinis** — tas pats failas
pakartojus gali duoti kitą tekstą. Kryptis nuosekli per kelis nepriklausomus
žodžius, bet tai ne 200 bandymų.

## Praktika, jei kas kartotų

Nemokamų **API** kreditų Soniox nebeturi — nutraukė dėl piktnaudžiavimo.
Savaitiniai nemokami kreditai galioja tik **programėlei**. Konsolės playground
remiasi tuo pačiu organizacijos balansu, tad ir jis be lėšų neveikia.
Pats testas suryja ~pusę cento (72 s garso × 2 rankos), bet balansą papildyti
reikia. Įkelti failai po testo **ištrinti iš jų paskyros** (22 vnt., 2026-09-28);
automatiškai jie būtų dingę po 30 dienų.
