# Problemų sprendimas

← [Atgal į pradžią](../README.md)

---

## Dažniausios problemos

| Problema | Sprendimas |
|---|---|
| **„Balsraštis is damaged“ / neatidaro** | Terminale: `xattr -dr com.apple.quarantine /Applications/Balsrastis.app`, tada paleisk |
| **„Safari can't open the file“** | Neatidarinėk iš Safari — eik per **Finder → Applications** |
| **Paleidus nieko nerodo** | Tai normalu — ieškok **mikrofono piktogramos ekrano viršuje dešinėje**, ne lango |
| **Klavišų derinys neveikia** | Įjunk **Accessibility** (macOS 12: dar ir **Input Monitoring**) → **paleisk iš naujo**. Jei derinys užimtas kitos programos — **Settings → General → Shortcut → Change…** ir įrašyk kitą |
| **Tekstas neatsiranda** | Pažiūrėk **Settings → Diagnostics** — ten matysi, kuriame etape sustojo. Dažniausiai — neįvesti ar blogi API raktai |
| **Transkripcija „🎵🎵🎵“** | Mikrofonas negauna balso: **Sound → Input** pasirink teisingą mikrofoną ir žiūrėk, kad „Input level“ juostelė judėtų kalbant; išjunk foninę muziką |
| **Neišsijungia pats po tylos** | Dažniausia priežastis — **nuolatinis foninis triukšmas** (ventiliatorius, oro kondicionierius): programa jį girdi kaip garsą ir laukia tylos, kuri neateina. Stabdyk derinį paspausdamas dar kartą |
| **Klaida „API key was rejected“ (401)** | Blogas arba sukeistas raktas. Settings → API Keys → **Remove** → įvesk teisingą (`sk-...` OpenAI, `sk-ant-...` Claude) |
| **Klaida „429“ / „insufficient_quota“** | OpenAI paskyroje nėra kredito — pridėk skiltyje „Billing“ |
| **„Network Error“** | Nėra interneto |
| **Kelios mikrofono piktogramos meniu juostoje** | Terminale: `killall Balsrastis`, tada paleisk vieną kartą iš Applications |
| **Keychain klausia slaptažodžio** | Įrašyk **Mac** slaptažodį (ne API raktą) → **Always Allow** |
| **Po naujos versijos derinys nustojo veikti** | Naujas parašas → „Accessibility“ leidimą reikės suteikti iš naujo: pašalink seną „−“, pridėk naują „+“, perkrauk |

---

## Pirmas žingsnis: Diagnostics

**Meniu piktograma → Settings… → Diagnostics.**

Ten matysi kiekvieno diktavimo eigą: kiek truko įrašymas, transkripcija, AI
valymas ir įterpimas, ir kuriame etape kas nors nutrūko. Dažniausiai to užtenka
suprasti, kur problema.

**Copy Report** mygtukas nukopijuoja visą ataskaitą tekstu — patogu, jei nori ją
kam nors atsiųsti.

> Pagal nutylėjimą ataskaitoje **nėra** to, ką padiktavai — tik skaičiai ir
> būsenos. Jei nori, kad matytųsi ir tekstas (kad būtų aišku, ką atpažino
> blogai), įjunk **Capture test text**, pakartok problemą, tada išjunk.

---

## Jei Diagnostics neužtenka

Uždaryk programą, tada **Terminale**:

```bash
/Applications/Balsrastis.app/Contents/MacOS/Balsraštis
```

Padiktuok ir žiūrėk į eilutes:

- `📝 Transcription (...): "..."` — ką atpažino
- `✨ Processed (...)` — ką sutvarkė Claude
- `⌨️ Inserted into the focused app.` — įterpta
- `❌ Pipeline failed: ...` — **tiksli klaida**

> ⚠️ **Svarbu:** paleidžiant per Terminalą, leidimus (Microphone, Accessibility)
> macOS priskiria **Terminalui**, ne Balsraštis. Todėl mikrofonas gali
> neperduoti garso (`🎵🎵🎵`) ir atsirasti problemų, kurių įprastai nėra. Tai **paskutinė**
> priemonė, ne pirma — kasdien programą paleisk įprastai iš Applications.

---

## Vis tiek neveikia?

Atidaryk [Issue](https://github.com/Rimantas-AI/Balsrastis/issues) ir pridėk
**Copy Report** turinį. Iš jo dažniausiai matyti, kas vyksta.

Radai saugumo problemą? → [`SECURITY.md`](../SECURITY.md)
