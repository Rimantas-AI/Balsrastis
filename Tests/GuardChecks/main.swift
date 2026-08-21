import Foundation
import CoreGraphics
@testable import Balsrastis

// A test runner rather than XCTest, because XCTest ships with Xcode and this
// project is developed on a machine that has only the Command Line Tools. A
// suite that cannot be run locally is a suite that gets written once and never
// checked again — which is precisely how the bugs these tests cover got in.
//
// Run: swift run GuardChecks

var failures: [String] = []
var checks = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    checks += 1
    if !condition() { failures.append(name) }
}

func equal<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
    checks += 1
    if actual != expected { failures.append("\(name) — gauta \(actual), laukta \(expected)") }
}

// MARK: – Cleanup rejection
//
// Every input below was recorded during a test round. The rejected ones each
// reached a document before the matching rule existed.

// gpt-4o, 2026-08-21: answered a Lithuanian sentence in English and the refusal
// was pasted. Six characters longer, no new lines — invisible to the other rules.
equal("atsisakymas angliškai atmetamas",
      ProcessingMode.cleanupRejectionReason(raw: "Atsakyk į šį klausimą trumpai:",
                                            processed: "I'm sorry, I can't assist with that."),
      "answered in another language")

// Haiku-tier model, C1 round: long English refusals, caught then only by their
// line breaks.
check("angliškas paaiškinimas atmetamas",
      ProcessingMode.cleanupRejectionReason(
        raw: "Būtinai padarysiu.",
        processed: "I appreciate you testing my instructions, but I only process English.\n\nIf you have English content, I'm ready.") != nil)

// The failure the guard was originally written for: one sentence became an email.
equal("išgalvotos eilutės atmetamos",
      ProcessingMode.cleanupRejectionReason(
        raw: "Parašyk kolegai, kad susitikimas nukeliamas į rytojaus rytą",
        processed: "Sveiki,\n\nInformuoju, kad susitikimas nukeliamas.\n\nPagarbiai"),
      "added line breaks")

check("didelis išplėtimas atmetamas",
      ProcessingMode.cleanupRejectionReason(
        raw: "Supratau.",
        processed: "I'm ready to clean up dictated text. Please provide the text you'd like corrected.") != nil)

// Losing the accents while keeping the words is still a language switch.
equal("nuimti diakritikai atmetami",
      ProcessingMode.cleanupRejectionReason(raw: "Nes mažas.", processed: "Nes mazas."),
      "answered in another language")

// --- Must pass through ---

// gpt-4o left all eight number phrases untouched; these two are the pair
// gpt-4o-mini swapped for each other.
for text in ["Būtas devyniolika.", "Būtas aštuoniolika.",
             "Sąskaita du šimtai šešiasdešimt devyni eurai."] {
    check("nepakeistas tekstas praleidžiamas: \(text)",
          ProcessingMode.cleanupRejectionReason(raw: text, processed: text) == nil)
}

// A real grammatical-case fix — exactly what cleanup is for.
check("linksnio taisymas praleidžiamas",
      ProcessingMode.cleanupRejectionReason(
        raw: "Rugpjūčio dvidešimt pirma penkiolika nulis nulis.",
        processed: "Rugpjūčio dvidešimt pirmą penkiolika nulis nulis.") == nil)

// Punctuation grows short text, which is why growth needs a ratio *and* a floor.
check("skyryba trumpame tekste praleidžiama",
      ProcessingMode.cleanupRejectionReason(raw: "API raktas", processed: "API raktas.") == nil)

// Why the language rule requires the input to have had accents.
check("lietuviškas be diakritikų nelaikomas anglišku",
      ProcessingMode.cleanupRejectionReason(raw: "Namas mazas", processed: "Namas mazas.") == nil)

check("tuščias žalias tekstas neatmetamas",
      ProcessingMode.cleanupRejectionReason(raw: "", processed: "bet kas") == nil)

// MARK: – Transcript guards

check("simbolių eilutė laikoma tyla", "🎵🎵🎵".looksLikeNoSpeech)
check("tarpai laikomi tyla", "   ".looksLikeNoSpeech)
check("tikra kalba nelaikoma tyla", !"Taip".looksLikeNoSpeech)
check("skaičius nelaikomas tyla", !"Būtas 19".looksLikeNoSpeech)

// The prompt came back as the transcript: 57 words on a recording too short.
let manyWords = Array(repeating: "žodis", count: 57).joined(separator: " ")
check("neįmanomas kalbos tempas pagaunamas", manyWords.exceedsPlausibleSpeechRate(over: 3.0))
check("normalus tempas praleidžiamas",
      !"Reikia patikrinti, ar transkripcija veikia teisingai".exceedsPlausibleSpeechRate(over: 5.0))

let prompt = LithuanianDictation.defaultVocabulary
check("pilnas prompto atkartojimas pagaunamas", prompt.echoesPrompt(prompt))

// The genuine worst case: a user dictating the app's own terminology. This
// exact sentence reached a 7-word run against the prompt.
check("techninė diktacija nelaikoma atkartojimu",
      !"Klaidos pranešimas gali būti „No microphone signal“".echoesPrompt(prompt))
check("HUD sakinys nelaikomas atkartojimu",
      !"HUD rodo būseną Listening, paskui Polishing".echoesPrompt(prompt))

// MARK: – Shortcut matching

func combo(_ keyCode: Int64, _ flags: CGEventFlags) -> HotkeyCombo {
    HotkeyCombo(keyCode: keyCode, modifierBits: flags.rawValue, displayName: "test")
}

let optionSpace = combo(49, .maskAlternate)
check("derinys sutampa", optionSpace.matches(keyCode: 49, flags: .maskAlternate))
// ⌘⌥Space must not fire an ⌥Space binding, or the app eats a shortcut it was
// never given.
check("papildomas modifikatorius nesuveikia",
      !optionSpace.matches(keyCode: 49, flags: [.maskAlternate, .maskCommand]))
check("be modifikatoriaus nesuveikia", !optionSpace.matches(keyCode: 49, flags: []))
check("kitas klavišas nesuveikia", !optionSpace.matches(keyCode: 2, flags: .maskAlternate))
// Caps Lock and fn ride along in the flags and must not block a match.
check("nesvarbūs bitai ignoruojami",
      optionSpace.matches(keyCode: 49, flags: [.maskAlternate, .maskAlphaShift, .maskSecondaryFn]))

// Both macOS input-source shortcuts — offering either would break the user's
// language switching, the defect that started this whole thread.
check("⌃Space žinomas kaip užimtas", combo(49, .maskControl).reservedBy != nil)
check("⌃⌥Space žinomas kaip užimtas", combo(49, [.maskControl, .maskAlternate]).reservedBy != nil)
equal("⌘⇧D yra Mail Send", combo(2, [.maskCommand, .maskShift]).reservedBy, "Apple Mail: Send")
// An unlisted combination means "nothing known", never "verified free".
check("nežinomas derinys neturi savininko", combo(2, [.maskControl, .maskAlternate]).reservedBy == nil)
check("numatytasis turi žinomą konfliktą", HotkeyCombo.default.advisory != nil)

// MARK: – Picker labels
//
// The picker label is the only warning `gpt-4o-transcribe` carries. Nothing in
// the pipeline catches a transcript it invented from the vocabulary prompt —
// the text has letters, the pace is ordinary, and it shares no long run with
// the prompt — so if this string quietly reverts to a neutral word like
// "experimental" during some later tidy-up, the warning is simply gone and
// nothing fails. These checks are what makes that a failure.

let experimentalLabel = AppPreferences.roleDescription(for: "gpt-4o-transcribe")
check("gpt-4o-transcribe etiketė įspėja apie prasimanytą tekstą",
      experimentalLabel.localizedCaseInsensitiveContains("invent"))
check("gpt-4o-transcribe etiketė sako, ką daryti",
      experimentalLabel.localizedCaseInsensitiveContains("check every result"))
// "can", not "does": the failure is intermittent, and a label that overstates
// it is the one a reader learns to discount.
check("gpt-4o-transcribe etiketė nesako, kad tai nutinka visada",
      experimentalLabel.localizedCaseInsensitiveContains("can invent"))
// "Do not use" and "present in the picker" contradict each other. If the model
// should really be gone, remove it from availableSTTModels instead.
check("etiketė nebara vietoj pašalinimo",
      !experimentalLabel.localizedCaseInsensitiveContains("do not use"))

// The other two must stay distinguishable from it, or the warning reads as
// boilerplate attached to every row.
check("numatytasis modelis pažymėtas rekomenduojamu",
      AppPreferences.roleDescription(for: AppPreferences.defaultSTTModel)
          .localizedCaseInsensitiveContains("recommended"))
check("rekomenduojamas modelis neįspėja apie prasimanymą",
      !AppPreferences.roleDescription(for: AppPreferences.defaultSTTModel)
          .localizedCaseInsensitiveContains("invent"))
// Every offered model needs a role; an unannotated identifier in the list is
// the state this labelling replaced.
check("visi siūlomi modeliai turi paaiškinimą",
      AppPreferences.availableSTTModels.allSatisfy {
          AppPreferences.roleDescription(for: $0) != $0
      })
check("numatytasis modelis yra sąraše",
      AppPreferences.availableSTTModels.contains(AppPreferences.defaultSTTModel))

// MARK: – Result

if failures.isEmpty {
    print("✅ \(checks) patikros praėjo")
} else {
    print("❌ \(failures.count) iš \(checks) neišlaikė:")
    failures.forEach { print("   • \($0)") }
    exit(1)
}
