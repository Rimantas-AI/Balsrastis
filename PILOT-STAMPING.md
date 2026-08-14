# Pilot build stamping

One CI build produces one universal `OmniScribe.zip`, blank `OmniScribeTesterName`.
Before sending it to a specific pilot tester, stamp *that copy* with their name —
no rebuild, no Xcode, just Terminal. Repeat once per tester.

Settings → Diagnostics then shows "Testing build for `<name>`", and Copy Report
includes a `Tester: <name>` line — so a build or a report that turns up somewhere
it shouldn't is traceable to whose copy it was.

## Steps (repeat per tester)

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
