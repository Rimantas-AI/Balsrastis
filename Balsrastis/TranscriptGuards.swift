import Foundation

/// Checks that decide whether a transcript is worth acting on, and whether an
/// AI reply may be pasted.
///
/// Kept apart from the UI deliberately: every one of these was added after
/// something specific reached a user's document, and they are the only part of
/// the pipeline that can be verified without a microphone, a network or an API
/// key. Living in their own Foundation-only file is what lets the test target
/// compile them on a machine with no Xcode installed.
extension String {

    /// `true` when a transcription contains no actual words.
    ///
    /// Whisper hallucinates filler on silent or near-silent audio — most often
    /// music notes ("🎵🎵🎵"), ellipses, or a lone punctuation mark. Treating
    /// those as text means paying for an LLM call and pasting nonsense, so the
    /// pipeline stops here instead. A single letter or digit anywhere is enough
    /// to consider the result real speech.
    ///
    /// See also `exceedsPlausibleSpeechRate(over:)`, which catches the opposite
    /// failure: far *too much* text for the audio's length.
    var looksLikeNoSpeech: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return !trimmed.unicodeScalars.contains {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }
    }

    /// `true` when this transcript holds more words than could physically have
    /// been spoken in `seconds` — the signature of a recogniser that returned
    /// something other than a transcription.
    ///
    /// Automates a cross-check previously done by hand (see the methodology notes
    /// in §12). Measured across a 30-clip Lithuanian round, real dictation ran
    /// 0.35–2.05 words/second at its fastest, so 4.0 leaves roughly double the
    /// headroom over the fastest real speech seen. Deliberately loose: falsely
    /// blocking a real dictation is worse than passing a rare bad one.
    ///
    /// This catches what the text checks cannot — a model echoing the vocabulary
    /// prompt back as its "transcript" (observed from `gpt-4o-mini-transcribe` on
    /// keyboard noise). That output is fluent and full of letters, so
    /// `looksLikeNoSpeech` passes it, but ~70 words attributed to a 10-second
    /// recording is not speech at any rate. It does **not** catch a short
    /// hallucinated sentence, which is plausibly paced — that stays open.
    func exceedsPlausibleSpeechRate(over seconds: TimeInterval) -> Bool {
        guard seconds > 0.5 else { return false }
        let words = split(whereSeparator: \.isWhitespace).count
        guard words > 8 else { return false }   // too few to judge a rate by
        return Double(words) / seconds > 4.0
    }

    /// `true` when this transcript reproduces a long unbroken stretch of
    /// `prompt` — a recogniser reciting the vocabulary hint back instead of
    /// transcribing.
    ///
    /// Measured behaviour, not a precaution: `gpt-4o-mini-transcribe` answered
    /// keyboard noise with the entire vocabulary prompt, verbatim, on three
    /// separate recordings.
    ///
    /// **Why a contiguous run and not word overlap.** Overlap is the obvious
    /// test and it is wrong here: real technical dictation reuses these very
    /// words. "HUD rodo būseną Listening, paskui Polishing" — a correct,
    /// deliberate dictation from the test set — shares nearly all of its words
    /// with the prompt and an overlap rule would destroy it. What separates
    /// recitation from speech is *sequence*.
    ///
    /// **Why 12.** Checked against every transcript from the test rounds: the
    /// full-prompt echo reproduced a **57-word** unbroken run, while real
    /// dictation reached at most **7** — and that worst case is a genuine one,
    /// not a fluke. The user dictated "Klaidos pranešimas gali būti „No
    /// microphone signal"", which appears verbatim in the prompt because the
    /// prompt was written from the app's own vocabulary. Anyone testing this app
    /// will say such sentences. 12 leaves five words of headroom above that and
    /// still catches echoes far shorter than the observed one.
    ///
    /// Two honest limits. A user *can* legitimately dictate a whole prompt
    /// sentence, so this trades a rare false block for the far more damaging
    /// paste — but the tension is real, not eliminated. And this catches
    /// recitation, not invention: a model answering noise with one short
    /// plausible sentence of its own defeats both this and the speech-rate
    /// check, and nothing here would notice.
    func echoesPrompt(_ prompt: String, minimumRun: Int = 12) -> Bool {
        func normalise(_ text: String) -> [Substring] {
            text.lowercased()
                .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation || $0.isSymbol })
        }
        let spoken = normalise(self)
        let hint = normalise(prompt)
        guard spoken.count >= minimumRun, hint.count >= minimumRun else { return false }

        // Longest common run of words, rolling one row at a time.
        var previous = [Int](repeating: 0, count: hint.count + 1)
        var longest = 0
        for s in spoken.indices {
            var current = [Int](repeating: 0, count: hint.count + 1)
            for h in hint.indices where spoken[s] == hint[h] {
                current[h + 1] = previous[h] + 1
                longest = max(longest, current[h + 1])
            }
            if longest >= minimumRun { return true }
            previous = current
        }
        return false
    }
}

/// The vocabulary hint sent to the recogniser.
///
/// Here rather than in `AppPreferences` for one reason: `echoesPrompt` was
/// tuned against *this exact text* — the full-prompt echo ran 57 words, real
/// dictation reached 7 — so the test that protects that threshold has to use
/// the real thing, not a stand-in.
enum LithuanianDictation {
    static let defaultVocabulary = """
    Tai lietuviška techninė diktacija apie macOS programą „Balsraštis". Programos \
    HUD, tariama raidėmis H-U-D, rodo būsenas „Listening", „Transcribing" ir \
    „Polishing". Nustatymuose yra skiltys „API Keys" ir „Diagnostics", o ten \
    mygtukai „Copy Report" ir „Clear Diagnostics". Galimi terminai: Mac \
    slaptažodis, API raktas, Keychain, Always Allow, TextEdit, Accessibility, \
    GitHub, Claude, Whisper. Klaidos pranešimas gali būti „No microphone signal".
    """
}
