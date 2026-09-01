# Soniox prieš gpt-4o-mini-transcribe — ant to paties garso

**Neįvykdytas. Paruošta 2026-09-01, daryti 2026-09-02.**

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
