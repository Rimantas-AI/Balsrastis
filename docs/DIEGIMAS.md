# Diegimas

← [Atgal į pradžią](../README.md)

Vienkartinis darbas, apie 15–20 minučių. Daugiausia laiko užima API raktai.

---

## 1. Parsisiuntimas

1. Atidaryk [**Releases**](https://github.com/Rimantas-AI/Balsrastis/releases/latest) —
   prisijungti prie GitHub **nereikia**.
2. Skiltyje **Assets** spausk **`Balsrastis.zip`**.
3. Išarchyvuok — gausi **`Balsrastis.app`**.
4. Nutempk `Balsrastis.app` į **Applications** (Programos).

**Patikrink, ką atsisiuntei** (nebūtina, bet verta — programa nenotarizuota):

```bash
shasum -a 256 Balsrastis.zip
```

Suma turi sutapti su nurodyta tos versijos
[Releases](https://github.com/Rimantas-AI/Balsrastis/releases/latest) puslapyje.
Daugiau būdų pasitikrinti — [`SECURITY.md`](../SECURITY.md).

<details>
<summary>Alternatyva: naujausia kompiliacija iš Actions (reikia GitHub paskyros)</summary>

Jei nori versijos, kuri dar neišleista kaip Release:

1. Prisijunk prie GitHub → repozitorijos **Actions** skiltis.
2. Spausk paskutinį žalią (✅) **„Build Balsraštis“** paleidimą.
3. Apačioje, **Artifacts**, spausk **Balsrastis-app**.

</details>

---

## 2. Leisk atidaryti (Gatekeeper)

Programa pasirašyta tik laikinu (*ad-hoc*) parašu, be Apple sertifikato, todėl
macOS pirmą kartą ją blokuoja. **Terminale** paleisk:

```bash
xattr -dr com.apple.quarantine /Applications/Balsrastis.app
```

Tada dukart spustelėk `Balsrastis.app`. Jei vis tiek klausia — **dešinys pelės
klavišas → Open → Open**, arba: **System Settings → Privacy & Security** →
apačioje **„Open Anyway“**.

> **Pirmą kartą paleidus** programa paklaus, kokį klavišų derinį nori naudoti
> diktavimui. Derinį ji perima iš visų programų, tad verta pasirinkti tokį,
> kurio pats nenaudoji. Vėliau pakeisi: Settings → General → Shortcut.
>
> Meniu juostos viršuje (dešinėje, prie laikrodžio) atsiras **mikrofono piktograma**.
> **Lango nebus — tai normalu.** Spausk piktogramą → matysi meniu (Settings, Quit).

---

## 3. Suteik leidimus

Nustatymuose (macOS 15: **System Settings**, macOS 12: **System Preferences**) →
**Privacy & Security**:

| Leidimas | Kam reikia |
|---|---|
| **Microphone** | įrašyti balsą |
| **Accessibility** | klavišų deriniui **ir** teksto įterpimui |
| **Input Monitoring** *(dažnai reikia macOS 12'e)* | klaviatūros klavišui perimti |

Įjunk **Balsraštis** kiekviename sąraše, tada **uždaryk ir paleisk programą iš
naujo** (Accessibility įsigalioja tik po perkrovimo).

---

## 4. Įvesk API raktus

Meniu piktograma → **Settings… → API Keys**:

- **GPT (OpenAI)** laukelyje → įklijuok OpenAI raktą (`sk-...` arba `sk-proj-...`)
- **Claude** laukelyje → įklijuok Anthropic raktą (`sk-ant-...`)

Spausk **Save**. Iššoks **Keychain** langas → įrašyk savo **Mac slaptažodį** →
**Always Allow**. Prie abiejų turi atsirasti žalias **„Stored“** ✓.

> ⚠️ **Nesupainiok laukelių:** `sk-...` = OpenAI, `sk-ant-...` = Claude.
> Sukeitus — abu bus atmesti (klaida 401).
> ⚠️ **Raktai saugomi tik šiame kompiuteryje.** Kitame Mac kompiuteryje juos reikia įvesti
> iš naujo.
> ⚠️ **OpenAI paskyroje turi būti kredito** (skiltyje „Billing“), kitaip matysi klaidą `429`.

Raktus gauni:
- OpenAI: <https://platform.openai.com/api-keys>
- Claude: <https://console.anthropic.com> → API Keys

---

## 5. Naujos versijos diegimas

1. Parsisiųsk naują `Balsrastis.zip` iš
   [Releases](https://github.com/Rimantas-AI/Balsrastis/releases/latest).
2. Pakeisk seną `.app` Applications aplanke.
3. `xattr -dr com.apple.quarantine /Applications/Balsrastis.app`
4. **„Accessibility“ leidimą suteik iš naujo** (parašas pasikeitė): pašalink seną įrašą
   „−“, pridėk naują „+“, tada perkrauk programą.
5. **API raktai „Keychain“ saugykloje išlieka** — jų iš naujo vesti nereikia.

---

Kažkas neveikia? → [Problemų sprendimas](PROBLEMOS.md)
