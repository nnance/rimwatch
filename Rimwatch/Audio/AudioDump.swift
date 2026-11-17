#if DEBUG
import Foundation
import GameCore

/// DEBUG only. Launch with `-dumpAudio <folder>` to render every sound patch and 20 seconds of
/// each music mood to 16-bit mono WAV files in `Documents/<folder>`, for analysis off the device:
///
///     xcrun simctl get_app_container <udid> com.nicknance.Rimwatch data
///
/// Runs once in the background at launch and logs where the files went.
nonisolated enum AudioDump {
    static let sampleRate = 44_100.0
    static let musicSeconds = 20.0

    static func runIfAsked(theme: any Theme) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-dumpAudio") else { return }
        let folder = arguments.indices.contains(flag + 1) && !arguments[flag + 1].hasPrefix("-")
            ? arguments[flag + 1] : "AudioDump"
        let sounds = theme.allSounds
        let style = theme.music
        DispatchQueue.global(qos: .utility).async {
            write(sounds: sounds, music: style, folder: folder)
        }
    }

    private static func write(sounds: [SoundPatch], music: MusicStyle?, folder: String) {
        let manager = FileManager.default
        guard let documents = manager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let directory = documents.appendingPathComponent(folder, isDirectory: true)
        try? manager.removeItem(at: directory)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var written = 0
        for patch in sounds {
            let samples = SoundRenderer.render(patch, sampleRate: sampleRate)
            if save(samples, to: directory.appendingPathComponent("\(patch.name).wav")) { written += 1 }
        }
        if let music {
            for mood in MusicMood.allCases {
                var bed = AmbientMusic(style: music, seed: 1, sampleRate: sampleRate, mood: mood)
                let samples = bed.render(Int(musicSeconds * sampleRate))
                if save(samples, to: directory.appendingPathComponent("music.\(mood.rawValue).wav")) { written += 1 }
            }
        }
        NSLog("[Rimwatch audio] dumped %d WAV files to %@", written, directory.path)
    }

    private static func save(_ samples: [Float], to url: URL) -> Bool {
        (try? wav(samples).write(to: url)) != nil
    }

    /// A 16-bit PCM mono WAV file.
    static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36) + bytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate) * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(bytes)
        for sample in samples {
            append(Int16(max(-1, min(1, sample)) * 32767))
        }
        return data
    }
}
#endif
