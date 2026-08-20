# Dažnai užduodami klausimai

← [Atgal į pradžią](../README.md)

---

### Kas yra Balsraštis?

„macOS“ diktavimo programa lietuvių kalbai. Paspaudi klavišų derinį, kalbi, ir
sutvarkytas tekstas atsiranda ten, kur žymeklis — el. laiške, užrašuose,
dokumente ar pokalbyje. Ne failų transkripcija, o diktavimas realiu laiku į
aktyvią programą.

### Ar tikrai reikia API raktų?

**Taip, ir be jų programa neveikia išvis.** Reikia **dviejų**:

| Raktas | Kam | Kur gauti |
|---|---|---|
| **OpenAI** | Balsą paversti tekstu | [platform.openai.com](https://platform.openai.com/api-keys) |
| **Anthropic** | Tekstą sutvarkyti | [console.anthropic.com](https://console.anthropic.com) |

Abiejose paskyrose turi būti kredito. Susikurti abu raktus užtrunka apie 15
minučių. Raktai saugomi „macOS Keychain“ tavo kompiuteryje.

Tai ne pasirinkimas ir ne „kai kurioms funkcijoms“ — tai būtina sąlyga.

### Kiek kainuoja?

**Programa nemokama.** Bet naudoji **savo** raktus, tad apmoki savo naudojimą
tiesiogiai OpenAI ir Anthropic — apytiksliai **keli eurai per mėnesį**, jei
diktuoji kasdien. Aš už programą neimu nieko ir tavo mokėjimų nematau.

### Ar programa pasirašyta Apple sertifikatu?

**Ne, ir dar nenotarizuota.** Tai reiškia, kad diegiant „macOS“ ją blokuos, ir
karantiną reikės pašalinti rankomis viena komanda terminale. Apple nepatikrino
nei manęs kaip kūrėjo, nei failo.

Būtent todėl kodas viešas — [`SECURITY.md`](../SECURITY.md) aprašyta, kaip
pasitikrinti kontrolinę sumą arba susikompiliuoti pačiam. Notarizacija planuose,
bet datos nežadu.

### Kokie modeliai naudojami?

- **Balsas → tekstas:** `gpt-4o-mini-transcribe` (OpenAI). Pasirinktas po 45
  garso įrašų palyginimo — buvo tiksliausias lietuviškai ir greičiausias.
  `whisper-1` ir `gpt-4o-transcribe` pasirenkami nustatymuose.
- **Teksto tvarkymas:** `claude-opus-4-8` (Anthropic).

Versija yra viena, ir ji naudoja būtent šiuos teikėjus.

### Kokių leidimų reikia ir kodėl?

| Leidimas | Kam |
|---|---|
| **Mikrofonas** | Įrašyti balsą |
| **Accessibility** | Perimti klavišų derinį ir įklijuoti tekstą |

Be Accessibility programa negali nei išgirsti klavišo, nei įrašyti teksto į
kitą programą.

### Ar mano balsas ar tekstas kur nors kaupiami?

Iš tavo turinio išeina du dalykai: **garsas** į `api.openai.com` ir
**transkribuotas tekstas** į `api.anthropic.com`. Daugiau niekur.

**Savo serverio neturiu** — nei statistikai, nei atnaujinimams. Duomenys niekada
nekeliauja per mane. Diagnostikos statistika (pagal nutylėjimą **išjungta**)
rašoma į failą tavo kompiuteryje ir joje nėra nei teksto, nei garso.

Pasitikrinti: [`SECURITY.md`](../SECURITY.md).

### Su kokiais Mac veikia?

Nuo **macOS 12 (Monterey)**, ir vienodai su **Intel** bei Apple Silicon.
Praktiškai: MacBook Air ir Pro nuo 2015 m., Mac mini nuo 2014 m., iMac nuo
2015 m. Naujausio kompiuterio nereikia.

### Ar galiu naudoti savo terminus?

Taip. **Settings → General → Vocabulary** įrašyk vardus, vietovardžius ar
profesinius terminus, kuriuos vartoji. Tai padeda atpažinti žodžius, kuriuos
kitaip nuolat iškraipytų.

### Ar veikia be interneto?

Ne. Abu žingsniai — atpažinimas ir teksto tvarkymas — vyksta debesyje.

### Kiek galiu kalbėti iš karto?

Kol darai trumpesnes nei ~1,2 sek. pauzes, įrašoma toliau. Vienas diktavimas
patikimai veikia iki kelių minučių. Daugiau —
[naudojimo instrukcijoje](NAUDOJIMAS.md).

### Kur kreiptis, jei neveikia?

Pirma — [problemų sprendimas](PROBLEMOS.md). Jei nepadeda,
[Issue](https://github.com/Rimantas-AI/Balsrastis/issues) su „Settings →
Diagnostics → Copy Report“ turiniu.
