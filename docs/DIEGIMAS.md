# Diegimas

← [Atgal į pradžią](../README.md)

Vienkartinis darbas, apie 15–20 minučių. Daugiausia laiko užima API raktai.

---

## 1. Parsisiuntimas

1. Atidaryk [**Releases**](https://github.com/Rimantas-AI/omniScribe/releases/latest) —
   prisijungti prie GitHub **nereikia**.
2. Skiltyje **Assets** spausk **`OmniScribe.zip`**.
3. Išarchyvuok — gausi **`OmniScribe.app`**.
4. Nutempk `OmniScribe.app` į **Applications** (Programos).

**Patikrink, ką atsisiuntei** (nebūtina, bet verta — programa nenotarizuota):

```bash
shasum -a 256 OmniScribe.zip
```

Suma turi sutapti su nurodyta tos versijos
[Releases](https://github.com/Rimantas-AI/omniScribe/releases/latest) puslapyje.
Daugiau būdų pasitikrinti — [`SECURITY.md`](../SECURITY.md).

<details>
<summary>Alternatyva: naujausia kompiliacija iš Actions (reikia GitHub paskyros)</summary>

Jei nori versijos, kuri dar neišleista kaip Release:

1. Prisijunk prie GitHub → repozitorijos **Actions** skiltis.
2. Spausk paskutinį žalią (✅) **„Build OmniScribe”** paleidimą.
3. Apačioje, **Artifacts**, spausk **OmniScribe-app**.

</details>

---

## 2. Leisk atidaryti (Gatekeeper)

Programa pasirašyta tik laikinu (*ad-hoc*) parašu, be Apple sertifikato, todėl
macOS pirmą kartą ją blokuoja. **Terminale** paleisk:

```bash
xattr -dr com.apple.quarantine /Applications/OmniScribe.app
```

Tada dukart spustelėk `OmniScribe.app`. Jei vis tiek klausia — **dešinys pelės
klavišas → Open → Open**, arba: **System Settings → Privacy & Security** →
apačioje **„Open Anyway”**.

> Meniu juostos viršuje (dešinėje, prie laikrodžio) atsiras **mikrofono ikona**.
> **Lango nebus — tai normalu.** Spausk ikoną → matysi meniu (Settings, Quit).

---

## 3. Suteik leidimus

Nustatymuose (macOS 15: **System Settings**, macOS 12: **System Preferences**) →
**Privacy & Security**:

| Leidimas | Kam reikia |
|---|---|
| **Microphone** | įrašyti balsą |
| **Accessibility** | klavišų deriniui **ir** teksto įterpimui |
| **Input Monitoring** *(dažnai reikia macOS 12'e)* | klaviatūros klavišui perimti |

Įjunk **OmniScribe** kiekviename sąraše, tada **uždaryk ir paleisk programą iš
naujo** (Accessibility įsigalioja tik po perkrovimo).

---

## 4. Įvesk API raktus

Meniu ikona → **Settings… → API Keys**:

- **GPT (OpenAI)** laukelyje → įklijuok OpenAI raktą (`sk-...` arba `sk-proj-...`)
- **Claude** laukelyje → įklijuok Anthropic raktą (`sk-ant-...`)

Spausk **Save**. Iššoks **Keychain** langas → įrašyk savo **Mac slaptažodį** →
**Always Allow**. Prie abiejų turi atsirasti žalias **„Stored”** ✓.

> ⚠️ **Nesupainiok laukelių:** `sk-...` = OpenAI, `sk-ant-...` = Claude.
> Sukeitus — abu bus atmesti (klaida 401).
> ⚠️ **Raktai saugomi tik šiame kompiuteryje.** Kitame Mac'e juos reikia įvesti
> iš naujo.
> ⚠️ **OpenAI paskyroje turi būti kredito** (Billing), kitaip matysi klaidą `429`.

Raktus gauni:
- OpenAI: <https://platform.openai.com/api-keys>
- Claude: <https://console.anthropic.com> → API Keys

---

## 5. Naujos versijos diegimas

1. Parsisiųsk naują `OmniScribe.zip` iš
   [Releases](https://github.com/Rimantas-AI/omniScribe/releases/latest).
2. Pakeisk seną `.app` Applications aplanke.
3. `xattr -dr com.apple.quarantine /Applications/OmniScribe.app`
4. **Accessibility suteik iš naujo** (parašas pasikeitė): pašalink seną įrašą
   „−”, pridėk naują „+”, tada perkrauk programą.
5. **API raktai Keychain'e išlieka** — jų iš naujo vesti nereikia.

---

Kažkas neveikia? → [Problemų sprendimas](PROBLEMOS.md)
