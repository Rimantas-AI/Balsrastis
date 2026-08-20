# Saugumas

## Ką programa daro su tavo duomenimis

**Raktai.** Abu API raktai laikomi **macOS Keychain** — ne faile, ne
`UserDefaults`, ne programos viduje.
→ [`Balsrastis/KeychainManager.swift`](Balsrastis/KeychainManager.swift)

**Kas siunčiama.** Iš tavo turinio išeina du dalykai:

| Kas | Kur |
|---|---|
| Įrašytas garsas | `api.openai.com` |
| Transkribuotas tekstas | `api.anthropic.com` |

Kartu keliauja tavo paties raktas autentifikacijai ir techninė užklausos
informacija (modelio pavadinimas, kalba) — kaip bet kurioje API užklausoje.

**Tai vieninteliai du adresai visame kode.** Pasitikrink:

```bash
grep -rn "https://" Balsrastis/*.swift
```

**Savo serverio neturiu.** Nei statistikai, nei atnaujinimams, nei niekam.
Duomenys niekada nekeliauja per mane.

**Jokios telemetrijos.** Diagnostikos statistika (pagal nutylėjimą **išjungta**)
rašoma į CSV failą tavo kompiuteryje. Joje nėra nei teksto, nei garso — vien
skaičiai. → [`Balsrastis/UsageLog.swift`](Balsrastis/UsageLog.swift)

**Kokių leidimų reikia ir kodėl:**

| Leidimas | Kam |
|---|---|
| Microphone | įrašyti balsą |
| Accessibility | perimti klavišų derinį ir įklijuoti tekstą |

---

## Kaip patikrinti, ką atsisiuntei

Programa **nenotarizuota Apple**, todėl macOS nepatikrina nei kūrėjo, nei failo.
Užtat gali pasitikrinti pats.

### 1. Kontrolinė suma

Terminale, atsisiuntimų aplanke:

```bash
shasum -a 256 Balsrastis.zip
```

Palygink su suma, nurodyta tos versijos
[Releases](https://github.com/Rimantas-AI/Balsrastis/releases) puslapyje. Jei
nesutampa — **nediek** ir parašyk man.

### 2. Susikompiliuok pats

Licencija tai leidžia būtent tam, kad nereikėtų tikėti paskelbtu failu:

```bash
git clone https://github.com/Rimantas-AI/Balsrastis.git
cd Balsrastis
xcodebuild -project Balsrastis.xcodeproj -scheme Balsrastis -configuration Release build
```

Reikia Xcode. Rezultatas — ta pati programa iš kodo, kurį matai.

### 3. Pasižiūrėk, kur eina tinklas

Jei nori įsitikinti veikimo metu, naudok [Little Snitch](https://obdev.at/products/littlesnitch/)
ar panašų įrankį — turėtum matyti tik `api.openai.com` ir `api.anthropic.com`.

---

## Ką reikia žinoti prieš diegiant

- **Programa nenotarizuota.** Diegiant reikės rankomis pašalinti karantiną
  (`xattr -dr com.apple.quarantine`). Tai reiškia, kad Apple šio failo
  netikrino — sprendimą priimi pats.
- **Naudoji savo API raktus**, taigi ir apmoki savo naudojimą. Programa už tai
  neima nieko.
- **Tai beta versija.** Kai kas neveiks.

---

## Radai saugumo problemą?

Prašau **neskelbk viešai**, kol nepataisyta — ypač jei tai raktų nutekėjimas
ar kodo vykdymas.

Pranešk per GitHub, privačiai:
[**Security → Report a vulnerability**](https://github.com/Rimantas-AI/Balsrastis/security/advisories/new)

Ši forma **įjungta ir veikia** — pranešimą matysiu tik aš, viešai jis
nepasirodys. Atsakysiu per kelias dienas.

Jei problema nėra saugumo spraga, o tiesiog klaida — atidaryk įprastą
[Issue](https://github.com/Rimantas-AI/Balsrastis/issues).
