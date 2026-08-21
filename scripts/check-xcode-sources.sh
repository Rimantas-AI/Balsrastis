#!/bin/bash
# Kiekvienas Balsrastis/*.swift failas turi būti įrašytas Xcode projekte.
#
# `swift build` failus randa automatiškai, o `xcodebuild` — tik tuos, kurie
# nurodyti project.pbxproj. Todėl naujas failas puikiai kompiliuojasi vietoje ir
# sugriauna CI. Taip nutiko tris kartus (HotkeyCombo, OpenAIService,
# TranscriptGuards) — visada tuo pačiu būdu, todėl geriau patikrinti automatiškai.
set -euo pipefail
missing=0
for f in Balsrastis/*.swift; do
  name=$(basename "$f")
  if ! grep -q "$name" Balsrastis.xcodeproj/project.pbxproj; then
    echo "❌ $name nėra Xcode projekte (project.pbxproj)"
    missing=1
  fi
done
if [ "$missing" -eq 0 ]; then echo "✓ visi šaltinio failai užregistruoti"; fi
exit $missing
