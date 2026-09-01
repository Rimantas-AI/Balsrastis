# Claude prieš OpenAI — palyginimas ant to paties garso

✅ **ĮVYKDYTA 2026-09-01. Verdiktas: lieka `claude-opus-4-8`.**
Pilnas rezultatas ir skaičiai — `AGENTS.md` §12, įrašas „Claude vs OpenAI cleanup,
on the same 11 recordings". Čia paliekamas tik planas ir tai, kas pasitvirtino.

**Kas pasitvirtino:** gpt-4o perredagavimas yra dėsnis, ne vienkartinis atvejis.
Jis pakeitė tekstą 6 kartus iš 11 (Claude — 3), ir keturi pakeitimai buvo
perredagavimai: perstatytas sakinys su dingusiais žodžiais, liepiamoji nuosaka
paversta bendratimi, `repo` išplėsta į `repozitorijoje`, o iš atpažinimo šiukšlės
`gidąbe` padarytas sklandžiai skambantis `gidą` — klaida ne ištaisyta, o paslėpta.
Plius vieną tikrą klaidą (`kasdienes`) jis paliko, o Claude ją ištaisė.

⚠️ **Rasta metodologinė riba:** atpažinimas nėra deterministinis. Tas pats WAV,
tas pats modelis ir promptas davė kitokį `Raw STT` 6 kartus iš 11. Kitą kartą
pirma sugretinti abi `Raw STT` skiltis ir atmesti eilutes, kur jau skiriasi
įvestis. Verdikto tai negriauna: visi keturi perredagavimai matomi gpt-4o
paties `Raw:`→`Final:` poroje.

Frazės — iš **tikro darbo**, ne sugalvotos: būtent jos atskleidė
gpt-4o perredagavimą, kurio 22 frazių scenarijus nepagavo.

## Paruošimas

| Kur | Ką |
|---|---|
| Diagnostics → **Save recordings** | ✅ |
| Diagnostics → **Capture test text** | ✅ |
| General → **AI Provider** | **Claude (Anthropic)** |
| General → **STT Model** | `gpt-4o-mini-transcribe` |
| | **Clear Diagnostics** |

## Frazės

1. Peržiūrėk repo GitHub'e, yra pakeitimai padaryti, ir pasakyk, kaip tu tai matai
2. Peržiūrėk repo GitHub'e ir pasakyk, ar viskas gerai padaryta
3. Manau, reikia kas porą savaičių atnaujinti kasdienės AI verslo apžvalgos promptą, atsižvelgiant į naujienas
4. Bet prieš tai pateik pasiūlymus, kad juos galėčiau patvirtinti
5. Ir dar reikėtų apriboti kasdienės apžvalgos atsakymo ilgį, kad nebūtų ilgai skaityti
6. Tai dabar pateik ir parašyk tą patį promptą, parodyk, kaip jis atrodys
7. **Prašau įvertink šitą promptą ir pažiūrėk, ar kažką galima pagerinti**
8. Pažiūrėk šitą, ką dabar įdėsiu, gal kažką galima panaudoti promptui
9. Sujunk šito prompto paprastumą ir ankstesnio prompto evoliuciją, iš dviejų padaryk vieną gerą
10. Gerai, manau, galim įrašyti į kasdienių darbų sąrašą

## Po to

Copy Report (Claude) → AI Provider → **GPT (OpenAI)** → Clear Diagnostics →
**Replay 10** → Copy Report (OpenAI).

Antrasis raundas eina per **tą patį garsą**, tad skiriasi tik teikėjas.

## Ko ieškoti

| Frazė | Ką gpt-4o padarė anksčiau |
|---|---|
| **7** | „promptą" → **„prašymą"** — terminas virto kitu žodžiu |
| **1** | „**yra** pakeitimai" → „**ar** pakeitimai" — teiginys virto klausimu |
| **10** | pridėjo „sąrašą", kurio atpažinimas negirdėjo |
| 3, 6, 8, 9 | visos su „promptas" — ar tai dėsnis, ar vienkartinis atvejis |

Sprendimo taisyklė ta pati kaip C1 raunde: **greitis nelaimi prieš prasmės klaidą.**
