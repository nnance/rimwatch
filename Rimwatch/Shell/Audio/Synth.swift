import AVFoundation
import Foundation
import GameCore
import UIKit

/// The game's sound: sound patches rendered once to PCM, played through a small pool of voices,
/// plus the generative music bed. Decisions (which voice, what to drop) are made on the main
/// thread and are cheap; everything that touches AVAudioEngine runs on one serial queue, so a
/// sound starting never waits on the audio system.
///
/// - Gameplay voices: `gameplayVoiceCount` players. Each patch has a cooldown and a cap on
///   copies; past that, a new sound replaces the oldest copy, or the oldest lowest-priority
///   voice, or is dropped if everything sounding matters more.
/// - Menu voices are separate, so a menu click never cuts a gameplay sound and pausing (which
///   silences gameplay) leaves them working.
/// - Levels: the sound and music options set mixer volumes live. All effects go through a peak
///   limiter with headroom below it; the music sits on its own quieter bus.
/// - The audio session is `.ambient`: it respects the silent switch and mixes with other apps.
///   Interruptions, route and configuration changes, backgrounding and foregrounding restart the
///   engine when it is wanted again.
final class Synth: SoundOutput {
    static let sampleRate = 44_100.0
    static let gameplayVoiceCount = 12
    static let menuVoiceCount = 2

    private struct Voice {
        var patch: String?
        var priority = 0
        var startedAt: TimeInterval = 0
        var endsAt: TimeInterval = 0
    }

    private let graph: AudioGraph
    private var patches: [String: SoundPatch] = [:]
    private var isReady = false
    private var voices = [Voice](repeating: Voice(), count: Synth.gameplayVoiceCount)
    private var menuVoices = [Voice](repeating: Voice(), count: Synth.menuVoiceCount)
    private var lastStart: [String: TimeInterval] = [:]

    private var soundLevel = 0.8
    private var musicLevel = 0.6
    /// Gameplay sounds are wanted (false while paused, on menus and with the phone closed).
    private var gameplayActive = false
    private var gameplayGain = 0.0
    private var musicWanted = false
    private var musicGain = 0.0
    private var mood: MusicMood = .title
    private var observers: [NSObjectProtocol] = []

    #if DEBUG
    private static let logs = ProcessInfo.processInfo.arguments.contains("-logFeedback")
    #endif

    init(sounds: [SoundPatch], music: MusicStyle?, options: GameOptions) {
        graph = AudioGraph(gameplayVoices: Self.gameplayVoiceCount, menuVoices: Self.menuVoiceCount,
                           sampleRate: Self.sampleRate, music: music)
        for patch in sounds { patches[patch.name] = patch }
        setLevels(sound: options.soundLevel, music: options.musicLevel)

        let all = sounds
        graph.queue.async { [graph, weak self] in
            let started = Date()
            graph.prepare(all)
            let count = all.count
            let seconds = Date().timeIntervalSince(started)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.isReady = true
                    debugLog("[Rimwatch audio] \(count) patches rendered in \(String(format: "%.2f", seconds)) s")
                }
            }
        }
        graph.queue.async { [graph] in graph.start(reason: "launch") }
        observeSystem()
        #if DEBUG
        AudioDump.runIfAsked(sounds: sounds, music: music)
        #endif
    }

    isolated deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: SoundOutput

    func setLevels(sound: Double, music: Double) {
        soundLevel = min(max(sound, 0), 1)
        musicLevel = min(max(music, 0), 1)
        applyVolumes()
        #if DEBUG
        if Self.logs { NSLog("[Rimwatch audio] levels: sound %.1f music %.1f", soundLevel, musicLevel) }
        #endif
    }

    func play(_ patch: SoundPatch, gain: Double, pan: Double) {
        start(patch, gain: gain, pan: pan, menu: false)
    }

    func playMenu(_ patch: SoundPatch) {
        start(patch, gain: 1, pan: 0, menu: true)
    }

    /// Whether gameplay sounds may play. Turning it off fades out whatever is sounding.
    func setGameplayActive(_ active: Bool) {
        guard active != gameplayActive else { return }
        gameplayActive = active
        #if DEBUG
        if Self.logs { NSLog("[Rimwatch audio] gameplay sound %@", active ? "on" : "off") }
        #endif
    }

    /// The music to play, or nil for silence. Changes fade.
    func setMusic(_ newMood: MusicMood?) {
        let wanted = newMood != nil
        let changed = (newMood.map { $0 != mood } ?? false) || wanted != musicWanted
        musicWanted = wanted
        if let newMood, newMood != mood {
            mood = newMood
            graph.queue.async { [graph] in graph.setMood(newMood) }
        }
        #if DEBUG
        if changed, Self.logs {
            NSLog("[Rimwatch audio] music %@", wanted ? mood.rawValue : "fading out (\(mood.rawValue))")
        }
        #else
        _ = changed
        #endif
    }

    /// Call every frame: moves the fades along.
    func update(elapsed: Double) {
        let dt = min(max(elapsed, 0), 0.1)
        // Gameplay sound: in quickly, out in about 0.15 s.
        let gameplayTarget = gameplayActive ? 1.0 : 0.0
        gameplayGain = approach(gameplayGain, gameplayTarget, rate: gameplayActive ? 12 : 7, dt: dt)
        if !gameplayActive, gameplayGain == 0, voices.contains(where: { $0.patch != nil }) {
            voices = [Voice](repeating: Voice(), count: voices.count)
            graph.queue.async { [graph] in graph.stopGameplayVoices() }
        }
        // Music: fades out over about a second, back in over two.
        musicGain = approach(musicGain, musicWanted ? 1 : 0, rate: musicWanted ? 0.5 : 1.1, dt: dt)
        applyVolumes()
    }

    private func approach(_ value: Double, _ target: Double, rate: Double, dt: Double) -> Double {
        if value < target { return min(value + rate * dt, target) }
        return max(value - rate * dt, target)
    }

    private var appliedVolumes: (Float, Float, Float) = (-1, -1, -1)

    private func applyVolumes() {
        // Squared, so the option steps feel even to the ear.
        let sound = Float(soundLevel * soundLevel)
        let volumes = (sound * Float(gameplayGain), sound, Float(musicLevel * musicLevel * musicGain))
        guard volumes != appliedVolumes else { return }
        appliedVolumes = volumes
        graph.queue.async { [graph] in graph.setVolumes(gameplay: volumes.0, menu: volumes.1, music: volumes.2) }
    }

    // MARK: Voices

    private func start(_ requested: SoundPatch, gain: Double, pan: Double, menu: Bool) {
        let patch = patches[requested.name] ?? requested
        let name = patch.name
        guard isReady else { return log("dropped", name, why: "not rendered yet") }
        guard soundLevel > 0 else { return }
        guard menu || gameplayActive else { return log("dropped", name, why: "gameplay sound off") }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastStart[name], now - last < patch.cooldown {
            return log("dropped", name, why: "rate limit")
        }

        var pool = menu ? menuVoices : voices
        var stolen: String?
        let index: Int
        let copies = pool.indices.filter { pool[$0].patch == name && pool[$0].endsAt > now }
        if copies.count >= patch.maxVoices, let oldest = copies.min(by: { pool[$0].startedAt < pool[$1].startedAt }) {
            index = oldest
            stolen = "own oldest copy"
        } else if let free = pool.indices.first(where: { pool[$0].endsAt <= now }) {
            index = free
        } else if let victim = pool.indices
            .filter({ pool[$0].priority <= patch.priority })
            .min(by: { (pool[$0].priority, pool[$0].startedAt) < (pool[$1].priority, pool[$1].startedAt) }) {
            index = victim
            stolen = pool[victim].patch
        } else {
            return log("dropped", name, why: "all voices busy with more important sounds")
        }

        pool[index] = Voice(patch: name, priority: patch.priority, startedAt: now, endsAt: now + patch.duration)
        if menu { menuVoices = pool } else { voices = pool }
        lastStart[name] = now
        let volume = Float(min(max(gain, 0), 1))
        let side = Float(min(max(pan, -1), 1))
        graph.queue.async { [graph] in graph.play(name, voice: index, menu: menu, volume: volume, pan: side) }
        #if DEBUG
        if Self.logs {
            let stealNote = stolen.map { " (stole \($0))" } ?? ""
            NSLog("[Rimwatch audio] started %@ voice %@%d gain %.2f pan %.2f%@", name, menu ? "m" : "g", index,
                  Double(volume), Double(side), stealNote)
        }
        #else
        _ = stolen
        #endif
    }

    private func log(_ what: String, _ name: String, why: String) {
        #if DEBUG
        if Self.logs { NSLog("[Rimwatch audio] %@ %@: %@", what, name, why) }
        #endif
    }

    // MARK: System events

    private func observeSystem() {
        let center = NotificationCenter.default
        let graph = self.graph
        func on(_ name: Notification.Name, _ object: Any? = nil, _ action: @escaping @Sendable (Notification) -> Void) {
            observers.append(center.addObserver(forName: name, object: object, queue: nil, using: action))
        }
        on(UIApplication.didEnterBackgroundNotification) { _ in
            graph.queue.async { graph.suspend() }
        }
        on(UIApplication.willEnterForegroundNotification) { _ in
            graph.queue.async { graph.resumeFromBackground() }
        }
        // Another app or a call took the audio away, and later says we may have it back.
        on(AVAudioSession.didBecomeInactiveNotification) { _ in
            graph.queue.async { graph.interrupted() }
        }
        on(AVAudioSession.resumptionRecommendationNotification) { _ in
            graph.queue.async { graph.start(reason: "resumption") }
        }
        on(AVAudioSession.mediaServicesWereResetNotification) { _ in
            graph.queue.async { graph.rebuildAfterReset() }
        }
        on(AVAudioSession.routeChangeNotification) { _ in
            graph.queue.async { graph.start(reason: "route change") }
        }
        // The engine's own configuration changes are watched by the graph, which re-registers
        // whenever it replaces its engine.
    }
}

/// The AVAudioEngine graph. Only ever touched on `queue`.
nonisolated final class AudioGraph: @unchecked Sendable {
    let queue = DispatchQueue(label: "rimwatch.audio", qos: .userInitiated)
    private(set) var engine = AVAudioEngine()
    private let format: AVAudioFormat
    private var gameplayVoices: [AVAudioPlayerNode] = []
    private var menuVoices: [AVAudioPlayerNode] = []
    private var gameplayMixer = AVAudioMixerNode()
    private var menuMixer = AVAudioMixerNode()
    private var effectsBus = AVAudioMixerNode()
    private var limiter: AVAudioUnitEffect
    private var musicPlayer = AVAudioPlayerNode()
    private var musicMixer = AVAudioMixerNode()
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var music: AmbientMusic?
    /// Bumped whenever the music queue is thrown away, so stale completions don't refill it.
    private var musicGeneration = 0
    private var musicQueued = 0
    private var isSuspended = false
    private var volumes: (gameplay: Float, menu: Float, music: Float) = (0, 0, 0)
    private let voiceCounts: (gameplay: Int, menu: Int)

    /// Music is rendered in chunks this long, a few queued ahead.
    private static let musicChunk: AVAudioFrameCount = 8192
    private static let musicChunksAhead = 3
    /// Effects run below the limiter with this much headroom.
    private static let effectsHeadroom: Float = 0.8

    init(gameplayVoices: Int, menuVoices: Int, sampleRate: Double, music style: MusicStyle?) {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        voiceCounts = (gameplayVoices, menuVoices)
        limiter = Self.makeLimiter()
        if let style {
            music = AmbientMusic(style: style, seed: UInt64(Date().timeIntervalSince1970), sampleRate: sampleRate)
        }
        build()
    }

    private static func makeLimiter() -> AVAudioUnitEffect {
        AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    }

    /// Watches the current engine for configuration changes (output device or format changed),
    /// which stop it. Replaced, with the old observer removed, whenever the engine is rebuilt.
    private var configurationObserver: NSObjectProtocol?

    private func observeConfiguration() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.start(reason: "configuration change") }
        }
    }

    private func build() {
        observeConfiguration()
        let engine = self.engine
        gameplayVoices = (0..<voiceCounts.gameplay).map { _ in AVAudioPlayerNode() }
        menuVoices = (0..<voiceCounts.menu).map { _ in AVAudioPlayerNode() }
        for node in [gameplayMixer, menuMixer, effectsBus, musicPlayer, musicMixer, limiter] as [AVAudioNode] {
            engine.attach(node)
        }
        for voice in gameplayVoices {
            engine.attach(voice)
            connect(voice, to: gameplayMixer, format: format)
        }
        for voice in menuVoices {
            engine.attach(voice)
            connect(voice, to: menuMixer, format: format)
        }
        connect(gameplayMixer, to: effectsBus, format: nil)
        connect(menuMixer, to: effectsBus, format: nil)
        connect(effectsBus, to: limiter, format: nil)
        connect(limiter, to: engine.mainMixerNode, format: nil)
        connect(musicPlayer, to: musicMixer, format: format)
        connect(musicMixer, to: engine.mainMixerNode, format: nil)
        effectsBus.outputVolume = Self.effectsHeadroom
        applyVolumes()
    }

    private func connect(_ source: AVAudioNode, to destination: AVAudioNode, format: AVAudioFormat?) {
        do {
            try engine.connectNode(source, to: destination, format: format)
        } catch {
            NSLog("[Rimwatch audio] could not connect %@ to %@: %@", "\(source)", "\(destination)", "\(error)")
        }
    }

    /// Renders every patch to a buffer. Slow-ish; runs once, on the queue.
    func prepare(_ patches: [SoundPatch]) {
        for patch in patches {
            let samples = SoundRenderer.render(patch, sampleRate: format.sampleRate)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
                continue
            }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { source in
                buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
            }
            buffers[patch.name] = buffer
        }
    }

    // MARK: Engine life

    /// Starts (or restarts) the engine if it isn't running and the app isn't in the background.
    func start(reason: String) {
        guard !isSuspended, !engine.isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            if session.category != .ambient {
                try session.setCategory(.ambient, mode: .default, options: [])
            }
            try session.setActive(true)
        } catch {
            NSLog("[Rimwatch audio] session could not be activated (%@): %@", reason, "\(error)")
        }
        do {
            engine.prepare()
            try engine.start()
            debugLog("[Rimwatch audio] engine started (\(reason)), output \(Int(engine.outputNode.outputFormat(forBus: 0).sampleRate)) Hz")
            restartMusic()
        } catch {
            NSLog("[Rimwatch audio] engine failed to start (%@): %@", reason, "\(error)")
        }
    }

    func suspend() {
        isSuspended = true
        musicGeneration += 1
        musicQueued = 0
        if engine.isRunning {
            for voice in gameplayVoices + menuVoices { voice.stop() }
            musicPlayer.stop()
            engine.pause()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        debugLog("[Rimwatch audio] suspended for background")
    }

    func resumeFromBackground() {
        isSuspended = false
        start(reason: "foreground")
    }

    func interrupted() {
        musicGeneration += 1
        musicQueued = 0
        debugLog("[Rimwatch audio] interrupted")
    }

    /// The media server restarted: every node is gone. Build a new engine and graph.
    func rebuildAfterReset() {
        debugLog("[Rimwatch audio] media services reset; rebuilding")
        musicGeneration += 1
        musicQueued = 0
        engine = AVAudioEngine()
        gameplayMixer = AVAudioMixerNode()
        menuMixer = AVAudioMixerNode()
        effectsBus = AVAudioMixerNode()
        limiter = Self.makeLimiter()
        musicPlayer = AVAudioPlayerNode()
        musicMixer = AVAudioMixerNode()
        build()
        start(reason: "media reset")
    }

    // MARK: Playing

    func setVolumes(gameplay: Float, menu: Float, music: Float) {
        volumes = (gameplay, menu, music)
        applyVolumes()
    }

    private func applyVolumes() {
        gameplayMixer.outputVolume = volumes.gameplay
        menuMixer.outputVolume = volumes.menu
        musicMixer.outputVolume = volumes.music
    }

    func play(_ name: String, voice index: Int, menu: Bool, volume: Float, pan: Float) {
        guard engine.isRunning, let buffer = buffers[name] else { return }
        let pool = menu ? menuVoices : gameplayVoices
        guard pool.indices.contains(index) else { return }
        let node = pool[index]
        node.stop()
        node.volume = volume
        node.pan = pan
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        do {
            try node.playAudio()
        } catch {
            NSLog("[Rimwatch audio] voice %d could not play %@: %@", index, name, "\(error)")
        }
    }

    func stopGameplayVoices() {
        guard engine.isRunning else { return }
        for voice in gameplayVoices { voice.stop() }
    }

    // MARK: Music

    func setMood(_ mood: MusicMood) {
        music?.setMood(mood)
    }

    private func restartMusic() {
        guard music != nil, engine.isRunning else { return }
        musicGeneration += 1
        musicQueued = 0
        musicPlayer.stop()
        fillMusic()
        do {
            try musicPlayer.playAudio()
        } catch {
            NSLog("[Rimwatch audio] music could not play: %@", "\(error)")
        }
    }

    private func fillMusic() {
        guard engine.isRunning, music != nil else { return }
        let generation = musicGeneration
        while musicQueued < Self.musicChunksAhead {
            let samples = music!.render(Int(Self.musicChunk))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.musicChunk) else { return }
            buffer.frameLength = Self.musicChunk
            samples.withUnsafeBufferPointer { source in
                buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
            }
            musicQueued += 1
            musicPlayer.scheduleBuffer(buffer, completionCallbackType: .dataConsumed) { [weak self] _ in
                guard let self else { return }
                self.queue.async {
                    guard generation == self.musicGeneration else { return }
                    self.musicQueued -= 1
                    self.fillMusic()
                }
            }
        }
    }
}
