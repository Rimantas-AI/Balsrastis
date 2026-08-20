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
        .executableTarget(
            name: "Balsrastis",
            path: "Balsrastis",
            // Info.plist ir .entitlements naudojami Xcode; SPM build jų nereikia.
            exclude: [
                "Info.plist",
                "Balsrastis.entitlements",
                "Assets.xcassets"
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
