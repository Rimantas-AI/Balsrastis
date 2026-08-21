import AVFoundation
import Foundation

/// Saved recordings that can be pushed back through the pipeline instead of a
/// microphone.
///
/// Why this exists: every model decision in this project was made by dictating
/// the same twenty-odd phrases again, by voice, and reading the results. That
/// costs twenty minutes a round and — worse — **it is not the same input twice.**
/// Pace, mic distance and pronunciation shift between takes, so a comparison
/// between two models is partly a comparison between two performances. The STT
/// round worked around this by sending one recording to several models at once;
/// nothing did the same for the cleanup step, and nothing at all survived to the
/// next day.
///
/// A fixture is just a 16 kHz mono WAV of what was actually captured. Recording
/// them costs one ordinary dictation session with the switch on; after that the
/// same audio can be replayed against any model, any prompt, any guard change,
/// as often as needed.
///
/// Deliberately **not** part of the test suite: replaying calls the real APIs and
/// costs money, so it stays a thing the user starts on purpose.
enum AudioFixtures {

    static let sampleRate: Double = 16_000

    /// `~/Library/Application Support/Balsrastis/Fixtures`.
    ///
    /// Alongside the usage log rather than inside the bundle, which is replaced
    /// wholesale on every install.
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("Balsrastis", isDirectory: true)
            .appendingPathComponent("Fixtures", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Saved recordings in a stable order, so a replay run lines up with the
    /// previous one row by row.
    static func all() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "wav" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: – Writing

    /// Writes captured samples as a numbered WAV and returns where it landed.
    ///
    /// The number is a zero-padded count, not a timestamp: a replay report is
    /// read next to the previous one, and `003` lines up where `2026-08-21T…`
    /// does not.
    @discardableResult
    static func save(samples: [Float]) throws -> URL {
        let index = all().count + 1
        let url = folder.appendingPathComponent(String(format: "%03d.wav", index))
        try write(samples: samples, to: url)
        return url
    }

    private static func write(samples: [Float], to url: URL) throws {
        // 16-bit integer PCM on disk — the format every tool reads — while the
        // in-memory buffer stays Float32 and AVAudioFile converts on write.
        let settings: [String: Any] = [
            AVFormatIDKey:               kAudioFormatLinearPCM,
            AVSampleRateKey:             sampleRate,
            AVNumberOfChannelsKey:       1,
            AVLinearPCMBitDepthKey:      16,
            AVLinearPCMIsFloatKey:       false,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey:   false,
        ]
        let file = try AVAudioFile(forWriting: url,
                                   settings: settings,
                                   commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw FixtureError.bufferAllocation
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData {
            samples.withUnsafeBufferPointer { src in
                channel[0].update(from: src.baseAddress!, count: samples.count)
            }
        }
        try file.write(from: buffer)
    }

    // MARK: – Reading

    /// Reads a fixture back as the same 16 kHz mono Float32 buffer the
    /// microphone would have produced, so the pipeline cannot tell the
    /// difference.
    static func load(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: sampleRate,
                                   channels: 1,
                                   interleaved: false)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)) else {
            throw FixtureError.bufferAllocation
        }
        try file.read(into: buffer)

        // Convert only when the file is not already in the pipeline's format —
        // fixtures written by `save` never need it, but a WAV dropped in by hand
        // might be 44.1 kHz stereo.
        if file.processingFormat == format {
            return samples(from: buffer)
        }
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format),
              let out = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: AVAudioFrameCount(file.length)) else {
            throw FixtureError.bufferAllocation
        }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        return samples(from: out)
    }

    private static func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
    }

    enum FixtureError: LocalizedError {
        case bufferAllocation
        var errorDescription: String? { "Could not allocate an audio buffer for the fixture." }
    }
}
