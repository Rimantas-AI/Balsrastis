<p align="center">
  <img src=".github/social-preview.png" alt="Balsraštis" width="640">
</p>

<h1 align="center">Balsraštis</h1>

<p align="center">
  <strong>Kalbėk. Parašyta.</strong><br>
  Diktuok lietuviškai — sutvarkytas tekstas atsiranda bet kurioje macOS programoje.
</p>

<p align="center">
  <a href="https://github.com/Rimantas-AI/Balsrastis/actions/workflows/build.yml"><img src="https://github.com/Rimantas-AI/Balsrastis/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Source%20Available-blue.svg" alt="License: Source Available"></a>
  <a href="https://github.com/Rimantas-AI/Balsrastis/releases/latest"><img src="https://img.shields.io/github/v/release/Rimantas-AI/Balsrastis" alt="Release"></a>
</p>

---

Paspaudi **⌥Space**, kalbi lietuviškai — ir **sutvarkytas tekstas atsiranda ten,
kur tavo žymeklis**. Mail, Pages, Safari, Slack, bet kur.

„Apple“ iki šiol nepalaiko diktavimo lietuvių kalba, todėl Balsraštis užpildo šią spragą.

Programa gyvena meniu juostoje: jokio lango, jokios piktogramos „Dock“ juostoje. Balsą į tekstą
verčia **GPT-4o mini Transcribe** (OpenAI), tekstą sutvarko **Claude**
(Anthropic).

## Kaip tai veikia

**1. Paspausk ⌥Space ir kalbėk.** Ekrano apačioje pasirodo diktavimo indikatorius.

<p align="center">
  <img src="docs/images/01-omniscribe-listening.png" alt="Balsraštis klausosi lietuviško diktavimo" width="900">
</p>

**2. Baigus kalbėti, sutvarkytas tekstas įterpiamas ten, kur buvo žymeklis.**

<p align="center">
  <img src="docs/images/02-omniscribe-result.png" alt="Balsraštis įterptas sutvarkytas lietuviškas tekstas" width="900">
</p>

<details>
<summary><strong>Meniu ir nustatymai</strong> (paspausk, kad pamatytum)</summary>

<p align="center">
  <img src="docs/images/03-omniscribe-settings.png" alt="Balsraštis bendrieji nustatymai" width="640">
  <br><br>
  <img src="docs/images/04-omniscribe-menu.png" alt="Balsraštis meniu juostos meniu" width="420">
</p>

</details>

## Ką reikia žinoti prieš diegiant

| | |
|---|---|
| **Kaina** | Programa nemokama. Naudoji **savo** OpenAI ir Anthropic raktus, tad apmoki savo naudojimą — apytiksliai keli eurai per mėnesį |
| **Reikia** | macOS 12 (Monterey) ar naujesnės. Veikia ir su **Intel**, ir su Apple Silicon |
| **Senesnis Mac tinka** | MacBook Air ir Pro nuo 2015 m., Mac mini nuo 2014 m., iMac nuo 2015 m. |
| **Parašas** | ⚠️ **Programa nėra notarizuota „Apple“.** Diegiant reikės rankomis pašalinti karantiną |
| **Stadija** | Beta. Kai kas neveiks |
| **Paruošimas** | ~15–20 min., daugiausia — API raktų susikūrimas |

## Parsisiuntimas

**[⬇️ Atsisiųsti naujausią versiją](https://github.com/Rimantas-AI/Balsrastis/releases/latest)** — be prisijungimo prie GitHub.

Toliau — **[diegimo instrukcija](docs/DIEGIMAS.md)**.

## Kur dingsta tavo duomenys ir raktai

Programa prašo dviejų API raktų, todėl klausimas „Ar ji jų kur nors nenusiųs?“
yra teisingas klausimas.

- **Raktai laikomi macOS Keychain** — ne faile, ne programos viduje
- **Iš tavo turinio siunčiami tik du dalykai:** garsas į `api.openai.com`,
  tekstas į `api.anthropic.com`. Tai vieninteliai du adresai visame kode
- **Savo serverio neturiu** — nei statistikai, nei atnaujinimams
- **Jokios telemetrijos.** Diagnostikos statistika (pagal nutylėjimą išjungta)
  lieka tavo kompiuteryje

Nesitikiu, kad patikėsi vien žodžiu — **[`SECURITY.md`](SECURITY.md)** rodo, kaip
pasitikrinti pačiam: kontrolinė suma, kompiliavimas iš kodo, tinklo stebėjimas.

## Dokumentacija

- 📥 **[Diegimas](docs/DIEGIMAS.md)** — parsisiuntimas, Gatekeeper, leidimai, API raktai
- 📖 **[Naudojimas](docs/NAUDOJIMAS.md)** — režimai, klavišų derinys, ribos
- 🔧 **[Problemų sprendimas](docs/PROBLEMOS.md)** — kai kas nors neveikia
- 🔒 **[Saugumas](SECURITY.md)** — ką programa daro su duomenimis ir kaip patikrinti

## Licencija

Kodą galima **skaityti, tikrinti ir savarankiškai sukompiliuoti** — kaip tik tam,
kad galėtum įsitikinti, jog paskelbtas vykdomasis failas atitinka paskelbtą kodą.

Bet tai **ne** atviro kodo licencija: platinti, parduoti ar leisti savo versijos
negalima be sutikimo. → [`LICENSE`](LICENSE)

## ☕ Patiko? Pavaišink kava

Jei sutaupė tau laiko ir nori padėkoti — gali įmesti kelias EUR kavai.
Kiekvienas puodelis motyvuoja tobulinti toliau 🙏

- ☕ **Ko-fi:** https://ko-fi.com/rimantasd
- 💳 **Revolut:** https://revolut.me/rimant6ap
