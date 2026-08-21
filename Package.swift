// swift-tools-version: 5.9
//
// Package.swift – Balsrastis
//
// Skirtas vienam tikslui: `swift build` – patikrinti, ar kodas kompiliuojasi
// terminale be Xcode (šiame projekte pilno Xcode nėra, tikrasis .app statomas
// GitHub Actions per `xcodebuild`).
//
// PASTABA: `swift build` NEsukuria .app paketo su Info.plist ir entitlements –
// tai daro tik Xcode/`xcodebuild`. Package.swift ir .xcodeproj gyvuoja šalia ir
// dalinasi tais pačiais šaltinio failais.
//
// Priklausomybių nėra: WhisperKit pašalintas (jis lūžta Intel Mac'uose),
// transkripcija vyksta per OpenAI debesį paprastu URLSession.

import PackageDescription

let package = Package(
    name: "Balsrastis",
    platforms: [
        // Turi sutapti su .xcodeproj deployment target, kitaip ši patikra
        // praleistų API, kurių senesnėje macOS nėra.
        .macOS(.v12)
    ],
    targets: [
        // Biblioteka, ne vykdomasis failas: SPM tas pačias rinkmenas gali priskirti
        // tik vienam taikiniui, o testams reikia nuo jų priklausyti. Tikroji .app
        // vis tiek statoma per `xcodebuild`, tad čia nieko neprarandama —
        // `swift build` ir toliau tikrina, ar viskas kompiliuojasi.
        //
        // `BalsrastisApp.swift` praleistas, nes `@main` bibliotekoje neturi prasmės.
        .target(
            name: "Balsrastis",
            path: "Balsrastis",
            // Info.plist ir .entitlements naudojami Xcode; SPM build jų nereikia.
            exclude: [
                "Info.plist",
                "Balsrastis.entitlements",
                "Assets.xcassets",
                "BalsrastisApp.swift"
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        // Apsaugų patikros. Sąmoningai ne XCTest: jis ateina su pilnu Xcode,
        // kurio šiame kompiuteryje nėra, o testų rinkinys, kurio negali paleisti
        // vietoje, parašomas kartą ir daugiau niekada netikrinamas.
        //
        // Įtraukia tik tuos failus, kuriems nereikia nei tinklo, nei mikrofono,
        // nei API raktų — todėl `swift run GuardChecks` veikia per sekundes ir
        // bet kur.
        .executableTarget(
            name: "GuardChecks",
            dependencies: ["Balsrastis"],
            path: "Tests/GuardChecks"
        )
    ]
)
