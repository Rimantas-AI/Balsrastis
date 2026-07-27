import SwiftUI

/// The visual phase the floating HUD reflects.
///
/// `error` exists because the pipeline used to fail silently into a console log
/// nobody sees when the app is launched normally — from the user's side that is
/// indistinguishable from "the app is broken".
enum HUDPhase: Equatable {
    case listening
    case transcribing
    case polishing
    case error(String)

    var label: String {
        switch self {
        case .listening:      return "Listening\u{2026}"
        case .transcribing:   return "Transcribing\u{2026}"
        case .polishing:      return "Polishing\u{2026}"
        case .error(let msg): return msg
        }
    }

    var symbol: String {
        switch self {
        case .listening:    return "mic.fill"
        case .transcribing: return "waveform"
        case .polishing:    return "sparkles"
        case .error:        return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .listening:    return .red
        case .transcribing: return .accentColor
        case .polishing:    return .purple
        case .error:        return .orange
        }
    }

    /// The level meter is only meaningful while capturing audio.
    var showsMeter: Bool {
        if case .listening = self { return true }
        return false
    }

    /// Width the hosting panel should use — error text needs noticeably more room.
    var preferredWidth: CGFloat {
        switch self {
        case .listening:    return 215
        case .transcribing: return 205
        case .polishing:    return 190
        case .error:        return 380
        }
    }
}

/// Observable state driving the HUD. Owned by `WindowManager`; mutated on the
/// main thread as the dictation phase changes.
final class RecordingHUDState: ObservableObject {
    @Published var phase: HUDPhase = .listening
    /// Normalised 0…1 microphone level, updated ~12×/second while listening.
    @Published var level: Float = 0
}

/// A small, non-interactive recording indicator. Purely visual — the hosting
/// `HUDPanel` handles the "never steal focus" behaviour.
struct RecordingHUDView: View {
    @ObservedObject var state: RecordingHUDState
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.phase.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(state.phase.tint)
                .scaleEffect(pulse && state.phase.showsMeter ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)

            Text(state.phase.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if state.phase.showsMeter {
                LevelMeter(level: state.level, tint: state.phase.tint)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .onAppear { pulse = true }
    }
}

/// Live input-level bars.
///
/// This is not decoration: it is the fastest way for someone to see that their
/// microphone is (or is not) reaching the app — the failure that previously
/// surfaced only as nonsense text several seconds later.
private struct LevelMeter: View {
    let level: Float
    let tint: Color

    /// Fixed per-bar weights give the classic uneven meter look from one value.
    private let weights: [Float] = [0.55, 1.0, 0.78, 0.42]
    private let maxHeight: CGFloat = 16

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(weights.indices, id: \.self) { index in
                Capsule()
                    .fill(tint.opacity(0.9))
                    .frame(width: 3, height: height(for: weights[index]))
            }
        }
        .frame(height: maxHeight)
        .animation(.easeOut(duration: 0.09), value: level)
    }

    private func height(for weight: Float) -> CGFloat {
        let scaled = CGFloat(min(1, max(0, level) * weight)) * maxHeight
        return max(3, scaled)   // never fully collapse, so the meter stays visible
    }
}
