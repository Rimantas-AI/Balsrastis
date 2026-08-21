# Naudojimas

← [Atgal į pradžią](../README.md)

---

## Kasdienis ciklas

1. Pastatyk žymeklį ten, kur nori teksto (TextEdit, Mail, naršyklė, žinutės…).
2. Paspausk **⌥ (Option) + Space** — apačioje atsiras įrašymo indikatorius.
3. Kalbėk **lietuviškai, aiškiai**.
4. Baigęs kalbėti tylėk — **po maždaug 1,2 sek. tylos įrašymas sustoja pats**
   (arba paspausk **⌥Space dar kartą**, jei nenori laukti).
5. Po kelių sekundžių sutvarkytas tekstas atsiras ties žymekliu.

Terminalo, diagnostikos žurnalų ar `xattr` kasdien **nereikia** — jie tik pirmam
diegimui ar problemų sprendimui.

---

## Klavišų derinys

Derinio programa paklausia **per pirmą paleidimą** — būtent tam, kad nieko
neatimtų nepaklaususi. Pasikeisti galima bet kada:
**Settings → General → Shortcut → Change…** ir paspausti tą derinį, kurio nori.

Verta pasikeisti, jei ⌥Space tau jau užimtas — pavyzdžiui, jei juo perjungi
klaviatūros kalbą.

Programa įspės, jei įrašytas derinys jau kam nors priklauso (⌃Space, ⌘Space,
⌘Tab, ekrano nuotraukų deriniai, Apple Mail „Send“ ir kiti).

---

## Režimai

Keiti: meniu → **Settings → General → Processing Mode**.

| Režimas | Ką daro |
|---|---|
| **Typing / Cleanup** | Sutvarko gramatiką, palieka tavo tekstą |
| **Email** | Perrašo į dalykišką laišką |
| **Code** | Paverčia į kodą |
| **Messenger** | Trumpa žinutė |
| **Translation** | Vertimas |

> **Typing / Cleanup** turi papildomą apsaugą: jei modelis vietoj taisymo imasi
> **vykdyti** padiktuotą nurodymą (pvz. iš „parašyk kolegai, kad susitikimas
> nukeliamas“ padaro laišką), rezultatas atmetamas ir įklijuojamas tavo
> originalus tekstas.

---

## Kada įrašymas sustoja pats

- **Nustojus kalbėti daugiau nei ~1,2 sek.** Trumpesnės pauzės sakinio viduryje
  jo nenutraukia, tad galvoti garsiai galima.
- Jei paspaudei derinį, bet **iš viso nieko nepasakei** — įrašymas išsijungia po
  ~6 sek., kad neliktų veikti be reikalo.
- Bet kada gali sustabdyti pats — **paspausk derinį dar kartą**.

> ⚠️ **Jei aplinkoje nuolatinis triukšmas** (ventiliatorius, oro kondicionierius),
> automatinis sustabdymas gali nesuveikti — programa girdi triukšmą kaip garsą ir
> laukia tylos, kuri neateina. Tada tiesiog paspausk derinį dar kartą.

---

## Kiek gali kalbėti iš viso

- **Kol kalbi be ilgesnių nei ~1,2 sek. pauzių, įrašoma toliau** — fiksuoto laiko
  limito nėra.
- Vienas diktavimas patikimai veikia **iki kelių minučių** (transkripcijos
  užklausos riba — 120 s; OpenAI failo riba — 25 MB ≈ ~13 min garso).
- Labai ilgo teksto **redaguotas** rezultatas gali būti apkarpytas (Claude ~8000
  tokenų riba, ~5000 žodžių).

💡 **Patarimas:** diktuok sakiniais ar pastraipomis, darydamas pauzę tarp jų —
natūraliausia ir patikimiausia. Ilgesniems tekstams — kelios trumpos dalys.

---

## Atpažinimo tikslumas

**Settings → General → Vocabulary** yra tekstas, kuris padeda atpažinti
specifinius žodžius — vardus, terminus, santrumpas. Jei nuolat diktuoji tam
tikrus žodžius ir jie atpažįstami blogai, įrašyk juos ten sakinio pavidalu.

**STT modelį** taip pat galima keisti (**Settings → General → STT Model**).
Numatytasis `gpt-4o-mini-transcribe` pasirinktas po 45 garso įrašų palyginimo — buvo
tiksliausias lietuviškai ir greičiausias. `whisper-1` lieka kaip atsarginis.

---

Kažkas neveikia? → [Problemų sprendimas](PROBLEMOS.md)

---

## Įrašų atkūrimas (modelių palyginimui)

Skirta ne kasdieniam naudojimui, o tada, kai nori palyginti du modelius arba
patikrinti, ar pakeitimas nieko nesugadino.

**Problema, kurią tai sprendžia:** pakartojus tas pačias frazes balsu, tai jau
**kitas įrašas** — kitas tempas, kitas atstumas iki mikrofono, kitas tarimas.
Vadinasi, lygini ne du modelius, o du savo pasakymus.

**Kaip naudoti:**

1. **Settings → Diagnostics → „Save recordings"** ✅
2. Padiktuok savo testines frazes **vieną kartą**, įprastai
3. Išjunk „Save recordings" — daugiau įrašinėti nereikia
4. Pakeisk, ką nori palyginti (modelį, teikėją, žodyną)
5. Spausk **„Replay N"** — visos frazės praeis tą pačią grandinę su tuo pačiu garsu

Ataskaitoje kiekvienoje eilutėje matysi **`Replay: 003.wav`**, tad du raundus
gali skaityti greta eilutė po eilutės.

> ⚠️ Atkūrimas naudoja **tikras API užklausas** ir kainuoja tiek pat, kiek tiek
> pat diktavimų. Tarp įrašų daroma 6 sek. pauzė, kad neatsitrenktum į užklausų
> limitą.

Įrašai guli `~/Library/Application Support/Balsrastis/Fixtures` — mygtukas
**„Show Recordings"** atidaro tą aplanką. Nereikalingus tiesiog ištrink.
