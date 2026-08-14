# Pilot build stamping

One CI build produces one universal `OmniScribe.zip`, blank `OmniScribeTesterName`.
Before sending it to a specific pilot tester, stamp *that copy* with their name —
no rebuild, no Xcode, just Terminal. Repeat once per tester.

Settings → Diagnostics then shows "Testing build for `<name>`", and Copy Report
includes a `Tester: <name>` line — so a build or a report that turns up somewhere
it shouldn't is traceable to whose copy it was.

## Step 0 — get explicit consent, before sending anything

Send the terms below and **wait for an affirmative reply** before building or
sending their `.zip`. The point is a reply that exists, not just terms that
were included alongside the file — "I agree" said back to you is what makes
this a beta agreement rather than a footnote no one necessarily read.

> **OmniScribe — privatus beta testas (30 dienų)**
>
> Ačiū, kad sutikai išbandyti! Prieš siunčiant `.zip`, prašau vieno dalyko —
> atsakyk trumpai:
>
> *"Perskaičiau ir sutinku su OmniScribe closed beta sąlygomis."*
>
> **Sąlygos:**
> - Tai privati beta versija, programa ir jos kodas priklauso man.
> - Šis pilotas galioja **30 dienų** nuo gavimo dienos.
> - Prašau **nepersiųsti, nesidalinti, nepublikuoti, neparduoti** šios
>   programos ar jos kodo jokiam kitam asmeniui, ir nenaudoti jos kaip
>   pagrindo kuriant panašų ar konkuruojantį produktą.
> - Diktuotas tekstas ir garsas niekur nesiunčiami be tavo pačio API raktų
>   (juos įsivedi Settings skiltyje); diagnostikos statistika, jei ją
>   įjungsi, lieka tik tavo kompiuteryje.
>
> Gavęs sutikimą, atsiųsiu `.zip` su tavo vardu pažymėta kopija. Naudok
> laisvai kasdieniam diktavimui ir rašyk man tiesiogiai, kas veikia, kas ne
> — tam ir yra testas.

Only once that reply is in hand, move to stamping.

## Steps (repeat per tester, after their consent reply)

```bash
# 1. Start from a clean copy of the downloaded release each time.
cd ~/Downloads
rm -rf OmniScribe.app
unzip OmniScribe.zip

# 2. Stamp the name (edit the value between the quotes).
/usr/libexec/PlistBuddy -c "Set :OmniScribeTesterName Rūta" \
  OmniScribe.app/Contents/Info.plist

# 3. Re-sign — editing Info.plist invalidates the CI signature.
codesign --force --deep --sign - OmniScribe.app

# 4. Verify the stamp took (prints the name back).
/usr/libexec/PlistBuddy -c "Print :OmniScribeTesterName" \
  OmniScribe.app/Contents/Info.plist

# 5. Zip this tester's copy under their own filename, so you don't
#    accidentally hand two people the same file.
ditto -c -k --keepParent OmniScribe.app "OmniScribe-Ruta.zip"
```

Send `OmniScribe-Ruta.zip` to Rūta directly (email / AirDrop / a private Drive
link addressed to her) — never the public Releases page. Repeat from step 1 for
the next tester so each `.zip` starts from the same clean build.

## Notes

- The repo is now **private**; testers never need GitHub access to install.
- Ad-hoc signing (step 3) needs no Apple Developer account — same as CI.
- Quarantine removal on their end is unchanged: `xattr -dr com.apple.quarantine`.
- A name is enough — no need for anything more identifying than a first name or
  initials both of you recognize.
- **BYO API keys protect your OpenAI/Anthropic bill, nothing else.** Anyone
  holding a copy of the `.app` can enter their own keys and run it fully — it
  is not a usage gate. The consent step, the stamped name, and the proprietary
  LICENSE are what this pilot actually relies on; keep that straight if this
  doc is extended later.
