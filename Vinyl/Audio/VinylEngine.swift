import AVFoundation
import Combine

class VinylEngine: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isBypassed = false
    @Published var monoMode = false
    @Published var preampOn = true
    @Published var powerampOn = true
    @Published var params = VinylParameters()
    @Published var currentTrack: SampleTrack?
    @Published var currentPreset: VinylPreset = .electronic
    @Published var displayTitle: String = "no track loaded"

    // Mode: library vs converter (mutually exclusive)
    enum ActiveMode { case library, converter }
    @Published var activeMode: ActiveMode = .library
    var lastSampleTrack: SampleTrack?

    // Needle Drop
    enum NeedleDropMode: Int, CaseIterable {
        case bypass = 0, drop1, drop2, drop3, drop4
        var next: NeedleDropMode {
            let all = NeedleDropMode.allCases
            let idx = (rawValue + 1) % all.count
            return all[idx]
        }
        var label: String {
            switch self {
            case .bypass: return "OFF"
            case .drop1: return "ND1"
            case .drop2: return "ND2"
            case .drop3: return "ND3"
            case .drop4: return "ND4"
            }
        }
    }
    @Published var needleDropMode: NeedleDropMode = .bypass
    private var needleDropBuffers: [AVAudioPCMBuffer] = []
    /// Number of frames the needle drop prepended (0 when bypass)
    private(set) var needleDropFrameCount: AVAudioFrameCount = 0
    private let needleDropFiles = ["needle_drop_1", "needle_drop_2", "needle_drop_3", "needle_drop_4"]

    // MARK: Crackle "just dropped" ramp
    //
    // When the stylus first lands, real records have a bunch of surface debris
    // that clears out over the first several seconds of playback. We emulate
    // that by linearly decaying a crackle-volume multiplier from `initialBoost`
    // down to 1.0 over `rampSeconds`, starting when playback begins near the
    // top of a buffer that has the needle drop prefix.
    //
    // `crackleBoost` is multiplied into the crackle volume inside
    // updateNoiseParams(), so it composes cleanly with whatever the user's
    // crackle slider is set to — if they move the slider mid-ramp, the target
    // level slides with them while the ramp keeps tapering toward 1.0×.
    private var crackleBoost: Float = 1.0
    private var crackleRampStartTime: Date?
    private var crackleRampTimer: Timer?
    private static let crackleRampSeconds: Double = 10.0
    private static let crackleRampInitialBoost: Float = 2.0

    // Converter state
    @Published var isConverting = false
    @Published var convertProgress: Double = 0
    @Published var convertedFileURL: URL?
    @Published var isPreviewing = false
    @Published var converterSourceLoaded = false
    @Published var convertFailed = false
    @Published var converterSourceName: String = ""
    @Published var convertedFiles: [URL] = []
    private var converterBuffer: AVAudioPCMBuffer?
    private var previewPlayer: AVAudioPlayer?

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func scanConvertedFiles() {
        let docs = VinylEngine.documentsDirectory
        let files = (try? FileManager.default.contentsOfDirectory(
            at: docs, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles
        )) ?? []
        convertedFiles = files
            .filter { $0.pathExtension.lowercased() == "wav" && $0.lastPathComponent.hasSuffix("_vinyl.wav") }
            .sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return d1 > d2
            }
    }

    private let engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var audioBuffer: AVAudioPCMBuffer?
    private var lpFilter: AVAudioUnitEQ!
    private var hpFilter: AVAudioUnitEQ!
    private var satNode: AVAudioUnitDistortion!
    private var riaaEQ: AVAudioUnitEQ!
    private var roomEQ: AVAudioUnitEQ!
    private var masterMixer: AVAudioMixerNode!
    // Incremented on every startPlayback(). Completion callbacks capture the generation
    // at scheduling time and bail if it no longer matches — prevents stale callbacks
    // from previous buffers cascading into handleEnd() and flickering through tracks.
    private var playbackGeneration = 0
    // On first play, mainMixerNode fades from 0→1 over 500ms to mask the iOS audio
    // hardware/EQ initialization pop. Output is locked at 0 from engine startup.
    private var hasWarmedUp = false
    private var tubeWarmthEQ: AVAudioUnitEQ!
    private var tubeAirEQ: AVAudioUnitEQ!
    private var microEQ: AVAudioUnitEQ!
    private var xformerEQ: AVAudioUnitEQ!
    private var speakerEQ: AVAudioUnitEQ!
    private var timePitch: AVAudioUnitTimePitch!
    private var hissPlayer = AVAudioPlayerNode()
    private var rumblePlayer = AVAudioPlayerNode()
    private var cracklePlayer = AVAudioPlayerNode()

    // Playback speed
    static let speedOptions: [Float] = [0.5, 0.9, 1.0, 1.2, 1.5, 1.7, 2.0, 2.5, 3.0, 4.0]
    @Published var playbackSpeed: Float = 1.0
    @Published var showSpeedMenu = false
    @Published var speedButtonFrame: CGRect = .zero

    private var pausedPosition: Double = 0
    private var progressTimer: Timer?
    private var driftTimer: Timer?
    private var wowTimer: Timer?
    private var driftOffset: Double = 0
    private var driftDir: Double = 1
    private var noiseUpdateWorkItem: DispatchWorkItem?

    init() {
        setupAudioSession()
        setupEngine()
        setupInterruptionHandling()
        loadNeedleDropFiles()
        applyPreset(.electronic)
        scanConvertedFiles()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { print("Audio session error: \(error)") }
    }

    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        DispatchQueue.main.async {
            if type == .began {
                if self.isPlaying { self.stopPlayback() }
            } else if type == .ended {
                try? AVAudioSession.sharedInstance().setActive(true)
                if !self.engine.isRunning { try? self.engine.start() }
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        if reason == .oldDeviceUnavailable {
            DispatchQueue.main.async { if self.isPlaying { self.stopPlayback() } }
        }
    }

    private func setupEngine() {
        lpFilter = makeEQ(type: .lowPass, freq: 18000)
        hpFilter = makeEQ(type: .highPass, freq: 28)
        riaaEQ = makeEQ(type: .parametric, freq: 900, bw: 1.0, gain: 0)
        roomEQ = makeEQ(type: .parametric, freq: 180, bw: 0.5, gain: 0)
        masterMixer = AVAudioMixerNode()
        satNode = AVAudioUnitDistortion()
        // Use the cubic soft-clipping preset to emulate Class A amplifier
        // behavior. Cubic distortion produces predominantly odd-order harmonics
        // and a smooth, compressive transfer curve — much closer to how real
        // Class A tube stages squash transients than the default harsh preset
        // AVAudioUnitDistortion otherwise uses.
        satNode.loadFactoryPreset(.multiDistortedCubed)
        satNode.wetDryMix = 0
        tubeWarmthEQ = makeEQ(type: .parametric, freq: 200, bw: 1.0, gain: 0)
        tubeAirEQ = makeEQ(type: .highShelf, freq: 10000, gain: 0)
        microEQ = makeEQ(type: .parametric, freq: 220, bw: 0.2, gain: 0)
        xformerEQ = makeEQ(type: .lowShelf, freq: 120, gain: 0)
        speakerEQ = makeEQ(type: .parametric, freq: 2800, bw: 1.2, gain: 0)
        timePitch = AVAudioUnitTimePitch()
        timePitch.rate = 1.0
        timePitch.pitch = 0
        let nodes: [AVAudioNode] = [playerNode, timePitch, hpFilter, riaaEQ, tubeWarmthEQ, tubeAirEQ, microEQ, xformerEQ, speakerEQ, satNode, lpFilter, roomEQ, masterMixer, hissPlayer, rumblePlayer, cracklePlayer]
        nodes.forEach { engine.attach($0) }
        let fmt = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(playerNode, to: timePitch, format: nil)
        engine.connect(timePitch, to: hpFilter, format: nil)
        engine.connect(hpFilter, to: riaaEQ, format: nil)
        engine.connect(riaaEQ, to: tubeWarmthEQ, format: nil)
        engine.connect(tubeWarmthEQ, to: tubeAirEQ, format: nil)
        engine.connect(tubeAirEQ, to: microEQ, format: nil)
        engine.connect(microEQ, to: xformerEQ, format: nil)
        engine.connect(xformerEQ, to: speakerEQ, format: nil)
        engine.connect(speakerEQ, to: satNode, format: nil)
        engine.connect(satNode, to: lpFilter, format: nil)
        engine.connect(lpFilter, to: roomEQ, format: nil)
        engine.connect(roomEQ, to: masterMixer, format: nil)
        engine.connect(hissPlayer, to: masterMixer, format: fmt)
        engine.connect(rumblePlayer, to: masterMixer, format: fmt)
        engine.connect(cracklePlayer, to: masterMixer, format: fmt)
        engine.connect(masterMixer, to: engine.mainMixerNode, format: nil)
        do { try engine.start() } catch { print("Engine start error: \(error)") }
        // Lock output to 0 at startup — ramped back up on first play to mask pop.
        engine.mainMixerNode.outputVolume = 0
        generateNoise()
    }

    // Podcast files are often mono — duplicate the channel to stereo so the
    // buffer format always matches the stereo engine connection.
    private func toStereo(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard buffer.format.channelCount == 1 else { return buffer }
        let stereoFmt = AVAudioFormat(standardFormatWithSampleRate: buffer.format.sampleRate, channels: 2)!
        guard let out = AVAudioPCMBuffer(pcmFormat: stereoFmt, frameCapacity: buffer.frameLength) else { return buffer }
        out.frameLength = buffer.frameLength
        if let src = buffer.floatChannelData?[0],
           let dstL = out.floatChannelData?[0],
           let dstR = out.floatChannelData?[1] {
            memcpy(dstL, src, Int(buffer.frameLength) * MemoryLayout<Float>.size)
            memcpy(dstR, src, Int(buffer.frameLength) * MemoryLayout<Float>.size)
        }
        return out
    }

    private func makeEQ(type: AVAudioUnitEQFilterType, freq: Float, bw: Float = 1.0, gain: Float = 0) -> AVAudioUnitEQ {
        let eq = AVAudioUnitEQ(numberOfBands: 1)
        eq.bands[0].filterType = type
        eq.bands[0].frequency = freq
        eq.bands[0].bandwidth = bw
        eq.bands[0].gain = gain
        eq.bands[0].bypass = false
        return eq
    }

    private func generateNoise() {
        let sr = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        if let b = makePink(fmt, 3.0, 1.0) { hissPlayer.scheduleBuffer(b, at: nil, options: .loops) }
        if let b = makeRumble(fmt, 2.0, 1.0) { rumblePlayer.scheduleBuffer(b, at: nil, options: .loops) }
        if let b = makeCrackle(fmt, 2.0, 1.0) { cracklePlayer.scheduleBuffer(b, at: nil, options: .loops) }
    }

    private func makePink(_ fmt: AVAudioFormat, _ dur: Double, _ gain: Float) -> AVAudioPCMBuffer? {
        let n = AVAudioFrameCount(fmt.sampleRate * dur)
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n) else { return nil }
        buf.frameLength = n
        var b0: Float = 0; var b1: Float = 0; var b2: Float = 0
        var b3: Float = 0; var b4: Float = 0; var b5: Float = 0
        for ch in 0..<Int(fmt.channelCount) {
            guard let d = buf.floatChannelData?[ch] else { continue }
            for i in 0..<Int(n) {
                let w = Float.random(in: -1...1)
                b0 = 0.99886 * b0 + w * 0.0555179
                b1 = 0.99332 * b1 + w * 0.0750759
                b2 = 0.96900 * b2 + w * 0.1538520
                b3 = 0.86650 * b3 + w * 0.3104856
                b4 = 0.55000 * b4 + w * 0.5329522
                b5 = -0.7616 * b5 - w * 0.0168980
                d[i] = (b0 + b1 + b2 + b3 + b4 + b5 + w * 0.5362) * 0.11 * gain
            }
        }
        return buf
    }

    private func makeRumble(_ fmt: AVAudioFormat, _ dur: Double, _ gain: Float) -> AVAudioPCMBuffer? {
        let n = AVAudioFrameCount(fmt.sampleRate * dur)
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n) else { return nil }
        buf.frameLength = n
        for ch in 0..<Int(fmt.channelCount) {
            guard let d = buf.floatChannelData?[ch] else { continue }
            for i in 0..<Int(n) {
                let t = Double(i) / fmt.sampleRate
                d[i] = Float((sin(2 * Double.pi * 26 * t) + sin(2 * Double.pi * 38 * t)) * 0.5) * gain
            }
        }
        return buf
    }

    private func makeCrackle(_ fmt: AVAudioFormat, _ dur: Double, _ gain: Float, popProb: Double = 0.0003) -> AVAudioPCMBuffer? {
        let n = AVAudioFrameCount(fmt.sampleRate * dur)
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n) else { return nil }
        buf.frameLength = n
        var phase = 0; var amp: Float = 1
        for ch in 0..<Int(fmt.channelCount) {
            guard let d = buf.floatChannelData?[ch] else { continue }
            for i in 0..<Int(n) {
                if Double.random(in: 0...1) < popProb { phase = Int.random(in: 8...28); amp = Float.random(in: 0.4...1.0) }
                if phase > 0 { d[i] = Float.random(in: -1...1) * amp * Float(phase) / 28.0 * gain; phase -= 1 }
                else { d[i] = 0 }
            }
        }
        return buf
    }

    func loadTrack(_ track: SampleTrack) {
        let wasPlaying = isPlaying
        // FIX: use stop() not pause(), and never detach/reattach the node
        if isPlaying { stopPlayback() } else { playerNode.stop() }
        // Clear podcast state when switching to a regular track
        podcastFileURL = nil
        podcastTotalDuration = 0
        podcastChunkStartTime = 0
        currentEpisodeId = nil
        podcastEpisodeList = []
        podcastEpisodeIndex = 0
        currentTrack = track
        lastSampleTrack = track
        activeMode = .library
        displayTitle = track.title
        pausedPosition = 0
        currentTime = 0
        // Fallback chain of extensions for bundled sample tracks. .flac added
        // for "Big Bad John" (and any future lossless samples). AVAudioFile on
        // iOS 11+ decodes FLAC natively, so this just works — no extra codec
        // or framework needed. Order is cheapest-first (most common format
        // tried first) so the typical mp3 track hits on the first lookup.
        let url = Bundle.main.url(forResource: track.filename, withExtension: "mp3")
            ?? Bundle.main.url(forResource: track.filename, withExtension: "m4a")
            ?? Bundle.main.url(forResource: track.filename, withExtension: "mp4")
            ?? Bundle.main.url(forResource: track.filename, withExtension: "flac")
        guard let fileURL = url else { print("Not found: \(track.filename)"); return }
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
            guard let af = audioFile else { return }
            duration = Double(af.length) / af.fileFormat.sampleRate
            let frameCount = AVAudioFrameCount(af.length)
            let rawBuffer = AVAudioPCMBuffer(pcmFormat: af.processingFormat, frameCapacity: frameCount)
            guard let ab = rawBuffer else { return }
            try af.read(into: ab)
            audioBuffer = toStereo(ab)
            needleDropFrameCount = 0
            rebuildBufferWithNeedleDrop()
            if let preset = VinylPreset.all.first(where: { $0.id == track.defaultPresetID }) { applyPreset(preset) }
            if wasPlaying {
                // Small delay ensures the engine has fully settled after stop() before rescheduling
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.startPlayback()
                }
            }
        } catch { print("Load error: \(error)") }
    }

    func loadFile(url: URL) {
        let wasPlaying = isPlaying
        // FIX: use stop() not pause(), and never detach/reattach the node
        if isPlaying { stopPlayback() } else { playerNode.stop() }
        // Clear podcast state
        podcastFileURL = nil
        podcastTotalDuration = 0
        podcastChunkStartTime = 0
        currentEpisodeId = nil
        podcastEpisodeList = []
        podcastEpisodeIndex = 0
        currentTrack = nil
        activeMode = .converter
        displayTitle = url.deletingPathExtension().lastPathComponent
        pausedPosition = 0
        currentTime = 0
        do {
            audioFile = try AVAudioFile(forReading: url)
            guard let af = audioFile else { return }
            duration = Double(af.length) / af.fileFormat.sampleRate
            let frameCount = AVAudioFrameCount(af.length)
            let rawBuffer = AVAudioPCMBuffer(pcmFormat: af.processingFormat, frameCapacity: frameCount)
            guard let ab = rawBuffer else { return }
            try af.read(into: ab)
            audioBuffer = toStereo(ab)
            needleDropFrameCount = 0
            rebuildBufferWithNeedleDrop()
            applyPreset(.audiophile)
            preampOn = false
            powerampOn = false
            updateAmpParams()
            if wasPlaying {
                // Small delay ensures the engine has fully settled after stop() before rescheduling
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.startPlayback()
                }
            }
        } catch { print("Load error: \(error)") }
    }

    func startPlayback() {
        // For podcast files: load the correct chunk from disk
        let isPodcast = podcastFileURL != nil
        if isPodcast, audioFile != nil {
            loadPodcastChunk(at: pausedPosition)
        }

        guard let buffer = audioBuffer else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { print("Engine start failed: \(error)"); return }
        }
        let sr = audioFile?.fileFormat.sampleRate ?? 44100

        // For podcasts, pausedPosition is absolute — compute chunk-relative offset
        let bufferPosition = isPodcast ? (pausedPosition - podcastChunkStartTime) : pausedPosition
        let startFrame = AVAudioFramePosition(max(0, bufferPosition) * sr)
        let frameCount = buffer.frameLength - AVAudioFrameCount(max(0, startFrame))
        guard frameCount > 0 else { return }
        guard let fmt = audioBuffer?.format,
              let sub = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frameCount) else { return }
        sub.frameLength = frameCount
        for ch in 0..<Int(fmt.channelCount) {
            guard let src = buffer.floatChannelData?[ch],
                  let dst = sub.floatChannelData?[ch] else { continue }
            memcpy(dst, src.advanced(by: Int(startFrame)), Int(frameCount) * MemoryLayout<Float>.size)
        }
        // Mix L+R to mono when mono mode is on
        if monoMode, fmt.channelCount == 2,
           let l = sub.floatChannelData?[0],
           let r = sub.floatChannelData?[1] {
            for i in 0..<Int(frameCount) {
                let m = (l[i] + r[i]) * 0.5
                l[i] = m; r[i] = m
            }
        }
        // Resample to match the engine connection format if needed (playerNode does no SRC)
        let connFmt = playerNode.outputFormat(forBus: 0)
        let bufToSchedule: AVAudioPCMBuffer
        if sub.format.sampleRate != connFmt.sampleRate,
           let converter = AVAudioConverter(from: sub.format, to: connFmt) {
            let ratio = connFmt.sampleRate / sub.format.sampleRate
            let destFrames = AVAudioFrameCount(Double(sub.frameLength) * ratio)
            if let dest = AVAudioPCMBuffer(pcmFormat: connFmt, frameCapacity: destFrames) {
                var inputConsumed = false
                let status = converter.convert(to: dest, error: nil) { _, outStatus in
                    if inputConsumed { outStatus.pointee = .noDataNow; return nil }
                    outStatus.pointee = .haveData
                    inputConsumed = true
                    return sub
                }
                bufToSchedule = (status != .error) ? dest : sub
            } else { bufToSchedule = sub }
        } else { bufToSchedule = sub }

        // Capture generation so stale callbacks from previous buffers are ignored.
        // Without this, old callbacks see isPlaying=true after the next track starts
        // and cascade through handleEnd() repeatedly, flickering through tracks.
        playbackGeneration += 1
        let gen = playbackGeneration
        playerNode.scheduleBuffer(bufToSchedule, at: nil, options: []) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.isPlaying, self.playbackGeneration == gen else { return }
                self.handleEnd()
            }
        }
        playerNode.play()
        if !hissPlayer.isPlaying { hissPlayer.play() }
        if !rumblePlayer.isPlaying { rumblePlayer.play() }
        if !cracklePlayer.isPlaying { cracklePlayer.play() }
        if !hasWarmedUp {
            hasWarmedUp = true
            let steps = 50
            let interval = 0.5 / Double(steps)
            var step = 0
            Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
                step += 1
                self?.engine.mainMixerNode.outputVolume = Float(step) / Float(steps)
                if step >= steps { timer.invalidate() }
            }
        }
        isPlaying = true
        // Trigger the "just-dropped" crackle ramp when we're starting playback
        // from the top of a buffer that has the needle drop prefix. Guard on
        // both conditions: `needleDropFrameCount > 0` means the buffer actually
        // contains a drop sample, and `pausedPosition < 0.5` ensures we're
        // beginning at (or very close to) the top — so seeking into the middle
        // of a track doesn't re-trigger the ramp.
        if needleDropMode != .bypass && needleDropFrameCount > 0 && pausedPosition < 0.5 {
            startCrackleRamp()
        }
        startProgressTimer()
        startDriftTimer()
        startWow()
        updateVinylParams()
        updateAmpParams()
    }

    func stopPlayback() {
        // For podcasts, currentTime is already absolute — save it directly
        pausedPosition = currentTime
        // FIX: stop() instead of pause() — cancels all pending scheduled buffers and
        // prevents stale completion callbacks from firing after a track change.
        playerNode.stop()
        hissPlayer.pause()
        rumblePlayer.pause()
        cracklePlayer.pause()
        isPlaying = false
        progressTimer?.invalidate(); progressTimer = nil
        driftTimer?.invalidate(); driftTimer = nil
        wowTimer?.invalidate(); wowTimer = nil
    }

    func togglePlayback() {
        if isPlaying { stopPlayback() } else { startPlayback() }
    }

    func seek(to time: Double) {
        let was = isPlaying
        // FIX: stop() not pause(), no node detach/reattach
        if isPlaying { stopPlayback() } else { playerNode.stop() }
        pausedPosition = max(0, min(time, duration - 0.1))
        currentTime = pausedPosition
        if was {
            // Same 50ms settle delay as loadTrack — ensures stop() has fully
            // flushed before we reschedule a new buffer from the seek position.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.startPlayback()
            }
        }
    }

    func restart() { seek(to: 0) }  // starts from needle drop if active

    private func handleEnd() {
        // Buffer finished naturally.
        isPlaying = false
        progressTimer?.invalidate(); progressTimer = nil
        driftTimer?.invalidate(); driftTimer = nil
        wowTimer?.invalidate(); wowTimer = nil

        // For podcast files: check if there's more audio to load
        if podcastFileURL != nil, let af = audioFile {
            let sr = af.fileFormat.sampleRate
            let absolutePos = Double(af.framePosition) / sr
            if absolutePos < podcastTotalDuration - 1.0 {
                // More audio remains — set absolute position and load next chunk
                pausedPosition = absolutePos
                currentTime = absolutePos
                startPlayback()
                return
            }
            // Podcast finished — stop at the end
            pausedPosition = 0
            currentTime = 0
            return
        }

        // Library track: advance to next track (wraps around), applying its default preset.
        // Converter/file tracks have no currentTrack set, so they loop as before.
        if let current = currentTrack,
           let idx = SampleTrack.library.firstIndex(where: { $0.id == current.id }) {
            let next = SampleTrack.library[(idx + 1) % SampleTrack.library.count]
            if let preset = VinylPreset.all.first(where: { $0.id == next.defaultPresetID }) {
                applyPreset(preset)
            }
            loadTrack(next)
            startPlayback()
        } else {
            // No library track loaded (converter mode) — loop from top
            pausedPosition = 0
            currentTime = 0
            startPlayback()
        }
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            guard let nodeTime = self.playerNode.lastRenderTime,
                  let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) else { return }
            let elapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
            self.currentTime = min(self.pausedPosition + elapsed, self.duration)
        }
    }

    private func startDriftTimer() {
        driftTimer?.invalidate()
        driftTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, !self.isBypassed else { return }
            let w = Double(self.params.wear) / 100
            let s = Double(self.params.speedDrift) / 100
            let amt = (0.00005 + w * 0.0003) * s
            self.driftOffset += self.driftDir * amt * Double.random(in: 0.5...1.5)
            if abs(self.driftOffset) > 0.008 { self.driftDir *= -1 }
        }
    }

    private func startWow() {
        wowTimer?.invalidate(); wowTimer = nil
        guard !isBypassed else {
            // Bypassed: keep user speed but no wow/flutter
            timePitch.rate = playbackSpeed
            timePitch.pitch = 0
            return
        }
        var phase: Double = 0
        // IMPORTANT: the modulation depths (wowD / flutD / warpD) are intentionally
        // computed INSIDE the timer closure on every tick, not captured once up
        // front. Previously they were captured as constants when startWow() was
        // called, which meant moving the wow depth / flutter / warp wow sliders
        // during playback had no audible effect — the timer was "frozen" on
        // whichever values the params happened to hold at playback-start time.
        // The symptom: after playing with the sliders, setting them back to 0
        // would NOT silence the effect; only toggling bypass (which reseeks and
        // re-runs startWow) cleared them.
        //
        // Reading the params live on each 50 ms tick is negligible CPU cost and
        // makes these sliders behave like every other slider — move them, hear
        // the change, set them to 0, they stop.
        wowTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            let w = Double(self.params.wear) / 100
            let m = Double(self.params.masterIntensity) / 100
            let wowD  = (0.004 + w * 0.035) * Double(self.params.wowDepth) / 100 * m
            let flutD = (0.002 + w * 0.02)  * Double(self.params.flutter)  / 100 * m
            let warpD = (0.006 + w * 0.05)  * Double(self.params.warpWow)  / 100 * m
            phase += 0.05
            let combined = 1.0 + wowD * sin(2 * Double.pi * 0.4 * phase) + flutD * sin(2 * Double.pi * 8 * phase) + warpD * sin(2 * Double.pi * 0.25 * phase) + self.driftOffset
            let clamped = max(0.97, min(1.03, combined))
            // Apply user speed × wow modulation via timePitch
            self.timePitch.rate = self.playbackSpeed * Float(clamped)
            // Vinyl-realistic pitch wobble: 1731 ≈ 1200/ln(2), maps rate deviation to cents
            self.timePitch.pitch = Float(1731.0 * (clamped - 1.0))
        }
    }

    /// Set playback speed (pitch-preserving). Applies immediately.
    func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        timePitch.rate = speed
        if isPlaying { startWow() }
    }

    /// Format speed for display, e.g. "1x", "1.5x", "0.9x"
    static func speedLabel(_ speed: Float) -> String {
        if speed == Float(Int(speed)) { return "\(Int(speed))x" }
        return "\(String(format: "%g", speed))x"
    }

    func applyPreset(_ preset: VinylPreset) {
        currentPreset = preset
        params = preset.params
        monoMode = (preset.id == "78rpm")
        // Needle drop preset carries engine-level state beyond VinylParameters:
        // it auto-engages the stylus-drop sound so the preset feels "complete"
        // without needing the user to also tap the needle drop button. We only
        // force this when the button is currently OFF — if the user has already
        // dialed in ND2/ND3/ND4, preserve their choice.
        if preset.id == "needledrop" && needleDropMode == .bypass {
            needleDropMode = .drop1
            rebuildBufferWithNeedleDrop()
        }
        updateVinylParams()
        updateAmpParams()
        scheduleNoiseUpdate()
        if isPlaying { seek(to: currentTime) }
    }

    func updateAllParams() {
        updateVinylParams()
        updateAmpParams()
        scheduleNoiseUpdate()
        // Rebuild needle drop with updated intensity (volume + rolloff)
        if needleDropMode != .bypass {
            let musicPos = needleDropAdjustedTime
            let wasPlaying = isPlaying
            rebuildBufferWithNeedleDrop()
            let newNdOffset = Double(needleDropFrameCount) / sampleRate
            pausedPosition = musicPos + newNdOffset
            currentTime = pausedPosition
            if wasPlaying { seek(to: pausedPosition) }
        }
    }

    private func scheduleNoiseUpdate() {
        noiseUpdateWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.updateNoiseParams()
            self?.updateCrackleBuffer()
        }
        noiseUpdateWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private var crackleWorkItem: DispatchWorkItem?

    func scheduleCrackleUpdate() {
        crackleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.updateCrackleBuffer() }
        crackleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func updateCrackleBuffer() {
        let sr = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        // Exponential mapping: 0 → ~1 pop/30s, 100 → dense crackle
        let t = Double(params.crackle) / 100.0
        let popProb = 0.000001 * pow(2000.0, t)
        guard let b = makeCrackle(fmt, 2.0, 1.0, popProb: popProb) else { return }
        let wasPlaying = cracklePlayer.isPlaying
        cracklePlayer.stop()
        cracklePlayer.scheduleBuffer(b, at: nil, options: .loops)
        if wasPlaying { cracklePlayer.play() }
    }

    func updateVinylParams() {
        guard !isBypassed else {
            lpFilter.bands[0].frequency = 20000
            // Note: satNode.wetDryMix is no longer zeroed here. satNode is
            // now owned by updateAmpParams() (it drives the "class A drive"
            // slider's effect), which evaluates `pw = powerampOn && !isBypassed`
            // and will correctly set wetDryMix to 0 while bypassed. toggleBypass()
            // always calls both updateVinylParams() and updateAmpParams() together,
            // so the bypass state stays consistent.
            roomEQ.bands[0].gain = 0
            riaaEQ.bands[0].gain = 0
            return
        }
        let w = params.wear / 100
        let m = params.masterIntensity / 100
        let cutoff = max(600.0, 18000.0 - Double(w) * 11000 - Double(params.hfRolloff) / 100 * Double(m) * 13000)
        lpFilter.bands[0].frequency = Float(cutoff)
        // satNode.wetDryMix intentionally not set here — see note in the
        // bypass guard above. Class A drive lives in updateAmpParams() now.
        riaaEQ.bands[0].gain = params.riaaVariance / 100 * m * 6 - 3
        roomEQ.bands[0].gain = params.roomResonance / 100 * m * 3
    }

    func updateAmpParams() {
        let pa = preampOn && !isBypassed
        let pw = powerampOn && !isBypassed
        let m = params.masterIntensity / 100
        // Each EQ node is now driven by its OWN independent parameter, not a
        // shared one. This is the audio-engine half of the slider-decoupling
        // change (the other half is in VinylParameters + ControlsViews). The
        // DSP math itself (scaling factors, sign conventions) is unchanged so
        // the sound at default preset values is identical to before; only the
        // ability to move each slider independently is new.
        tubeWarmthEQ.bands[0].gain = pa ? params.saturation / 100 * m * 1.2 : 0      // "tube warmth"
        tubeAirEQ.bands[0].gain    = pa ? -(params.airRolloff / 100 * m * 0.35) : 0   // "air rolloff"
        microEQ.bands[0].gain      = pa ? params.microphonics / 100 * m * 0.6 : 0     // "microphonics"
        xformerEQ.bands[0].gain    = pw ? params.outputTransformer / 100 * m * 0.6 : 0 // "output transformer"
        speakerEQ.bands[0].gain    = pw ? -(params.speakerCoupling / 100 * m * 0.5) : 0 // "speaker coupling"
        // "class A drive" — cubic soft-clip via AVAudioUnitDistortion.
        // wetDryMix is in percent (0-100). Cap at 15% even at slider=100 and
        // masterIntensity=100 so the effect stays in "subtle warmth" territory
        // rather than ever sounding like a guitar-amp distortion pedal.
        satNode.wetDryMix          = pw ? params.classADrive / 100 * m * 15 : 0
    }

    func updateNoiseParams() {
        let w = params.wear / 100
        let m = params.masterIntensity / 100
        let active = !isBypassed
        hissPlayer.volume = active ? Float((0.01 + Double(w) * 0.08) * Double(params.hiss) / 100 * Double(m)) * 2 : 0
        rumblePlayer.volume = active ? Float((0.02 + Double(w) * 0.22) * Double(params.rumble) / 100 * Double(m)) * 1.5 : 0
        // Multiplied by crackleBoost so the "just dropped" ramp can temporarily
        // elevate crackle above the preset's steady-state level — see
        // startCrackleRamp(). When no ramp is active, crackleBoost == 1.0 and
        // this term is a no-op, preserving the previous behavior exactly.
        cracklePlayer.volume = active ? Float((0.08 + Double(w) * 0.55) * Double(params.crackle) / 100 * Double(m)) * 1.0 * crackleBoost : 0
    }

    private var monoModeBeforeBypass = false

    func toggleBypass() {
        if isBypassed {
            // Restoring: bring mono back to what it was before bypass
            isBypassed = false
            monoMode = monoModeBeforeBypass
        } else {
            // Bypassing: save mono state then turn everything off
            monoModeBeforeBypass = monoMode
            monoMode = false
            isBypassed = true
        }
        updateVinylParams()
        updateAmpParams()
        scheduleNoiseUpdate()
        if isPlaying { seek(to: currentTime) }
    }

    func toggleMono() {
        monoMode.toggle()
        // Re-seek to current position so the mono mix applies immediately
        if isPlaying { seek(to: currentTime) }
    }

    // MARK: - Needle Drop

    private func loadNeedleDropFiles() {
        needleDropBuffers = []
        for name in needleDropFiles {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
                print("Needle drop not found: \(name)")
                continue
            }
            do {
                let file = try AVAudioFile(forReading: url)
                let frameCount = AVAudioFrameCount(file.length)
                guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else { continue }
                try file.read(into: buf)
                needleDropBuffers.append(toStereo(buf))
            } catch { print("Needle drop load error: \(error)") }
        }
    }

    func cycleNeedleDrop() {
        let wasPlaying = isPlaying
        let musicPos = needleDropAdjustedTime  // music-relative time before mode change
        if wasPlaying { stopPlayback() }
        needleDropMode = needleDropMode.next
        // Rebuild buffer with new needle drop and resume from same music position
        rebuildBufferWithNeedleDrop()
        // Seek to same music position (add new needle drop offset)
        let newNdOffset = Double(needleDropFrameCount) / sampleRate
        let absolutePos = musicPos + newNdOffset
        pausedPosition = absolutePos
        currentTime = absolutePos
        if wasPlaying {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.startPlayback()
            }
        }
    }

    /// Starts (or restarts) the "just dropped" crackle ramp.
    /// Invalidates any in-flight ramp first so repeat triggers don't stack.
    /// Timer ticks every 100 ms and self-terminates when the 10 s window
    /// has elapsed, settling `crackleBoost` exactly at 1.0.
    private func startCrackleRamp() {
        crackleRampTimer?.invalidate()
        crackleRampStartTime = Date()
        crackleBoost = Self.crackleRampInitialBoost
        updateNoiseParams()
        crackleRampTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self, let start = self.crackleRampStartTime else {
                timer.invalidate(); return
            }
            let elapsed = Date().timeIntervalSince(start)
            let progress = min(1.0, elapsed / Self.crackleRampSeconds)
            // Linear decay from initialBoost down to 1.0
            self.crackleBoost = Self.crackleRampInitialBoost
                              - Float(progress) * (Self.crackleRampInitialBoost - 1.0)
            self.updateNoiseParams()
            if progress >= 1.0 {
                self.crackleBoost = 1.0
                self.crackleRampStartTime = nil
                self.crackleRampTimer = nil
                timer.invalidate()
            }
        }
    }

    /// Current playback time adjusted for needle drop offset (music-relative)
    var needleDropAdjustedTime: Double {
        let ndSec = Double(needleDropFrameCount) / sampleRate
        return max(0, currentTime - ndSec)
    }

    /// Actual duration of the music (without needle drop)
    var musicDuration: Double {
        let ndSec = Double(needleDropFrameCount) / sampleRate
        return max(0, duration - ndSec)
    }

    private func rebuildBufferWithNeedleDrop() {
        // Strip any existing needle drop from the buffer first
        guard let buf = strippedMusicBuffer() else { return }
        if needleDropMode == .bypass {
            audioBuffer = buf
            needleDropFrameCount = 0
        } else {
            let idx = needleDropMode.rawValue - 1  // drop1=0, drop2=1, etc.
            guard idx >= 0 && idx < needleDropBuffers.count else {
                audioBuffer = buf
                needleDropFrameCount = 0
                return
            }
            let ndBuf = needleDropBuffers[idx]
            let m = params.masterIntensity / 100
            audioBuffer = prependNeedleDrop(ndBuf, to: buf, intensity: m)
        }
        let sr = audioBuffer?.format.sampleRate ?? 44100
        duration = Double(audioBuffer?.frameLength ?? 0) / sr
    }

    /// Returns the music-only buffer (strips needle drop prefix if present)
    private func strippedMusicBuffer() -> AVAudioPCMBuffer? {
        guard let buf = audioBuffer else { return nil }
        if needleDropFrameCount == 0 { return buf }
        let musicFrames = buf.frameLength - needleDropFrameCount
        guard musicFrames > 0 else { return buf }
        guard let fmt = audioBuffer?.format,
              let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: musicFrames) else { return buf }
        out.frameLength = musicFrames
        for ch in 0..<Int(fmt.channelCount) {
            guard let src = buf.floatChannelData?[ch],
                  let dst = out.floatChannelData?[ch] else { continue }
            memcpy(dst, src.advanced(by: Int(needleDropFrameCount)), Int(musicFrames) * MemoryLayout<Float>.size)
        }
        return out
    }

    /// Prepend needle drop buffer to music buffer with intensity-based volume and rolloff fade.
    ///
    /// IMPORTANT — sample rate handling: the needle drop WAVs ship at 44.1 kHz,
    /// but music tracks can be 44.1 kHz or 48 kHz (or higher). Previously we
    /// memcpy'd needle drop samples directly into a buffer that claimed the
    /// music's sample rate, which on 48 kHz tracks played the needle drop back
    /// ~8.8% too fast — the shifted-up high-frequency transients sounded like
    /// squeaking/whistling. The fix below resamples the needle drop buffer to
    /// the music's sample rate (via AVAudioConverter) before prepending, so
    /// the two halves of the combined buffer are always at the same rate.
    private func prependNeedleDrop(_ rawNd: AVAudioPCMBuffer, to music: AVAudioPCMBuffer, intensity: Float) -> AVAudioPCMBuffer {
        let sr = music.format.sampleRate
        // Resample needle drop to music's sample rate if they differ. If the
        // conversion fails for any reason, fall back to the original buffer —
        // same behavior as before this fix, just with the known artifact.
        let nd: AVAudioPCMBuffer = {
            if rawNd.format.sampleRate == sr { return rawNd }
            guard let targetFmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: rawNd.format.channelCount),
                  let converter = AVAudioConverter(from: rawNd.format, to: targetFmt) else { return rawNd }
            let ratio = sr / rawNd.format.sampleRate
            let outCapacity = AVAudioFrameCount(Double(rawNd.frameLength) * ratio) + 16 // small padding
            guard let dest = AVAudioPCMBuffer(pcmFormat: targetFmt, frameCapacity: outCapacity) else { return rawNd }
            var consumed = false
            let status = converter.convert(to: dest, error: nil) { _, outStatus in
                if consumed { outStatus.pointee = .noDataNow; return nil }
                outStatus.pointee = .haveData
                consumed = true
                return rawNd
            }
            return (status != .error) ? dest : rawNd
        }()
        let ndFrames = nd.frameLength
        let musicFrames = music.frameLength
        let totalFrames = ndFrames + musicFrames
        let fmt = music.format

        guard let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: totalFrames) else { return music }
        out.frameLength = totalFrames
        needleDropFrameCount = ndFrames

        // Fade-out duration scales with intensity: 0% = no fade, 100% = 1.5s fade
        let fadeDuration = Double(intensity) * 1.5
        let fadeSamples = Int(fadeDuration * sr)
        let fadeStart = max(0, Int(ndFrames) - fadeSamples)

        for ch in 0..<Int(fmt.channelCount) {
            guard let dst = out.floatChannelData?[ch] else { continue }

            // Copy needle drop with volume scaling and fade
            if ch < Int(nd.format.channelCount), let ndSrc = nd.floatChannelData?[ch] {
                for i in 0..<Int(ndFrames) {
                    var sample = ndSrc[i] * intensity
                    // Apply fade-out envelope in the tail
                    if i >= fadeStart && fadeSamples > 0 {
                        let fadePos = Float(i - fadeStart) / Float(fadeSamples)
                        // Exponential fade for smooth rolloff
                        let fadeGain = (1.0 - fadePos) * (1.0 - fadePos)
                        sample *= fadeGain
                    }
                    dst[i] = sample
                }
            } else {
                // Zero-fill if channel mismatch
                memset(dst, 0, Int(ndFrames) * MemoryLayout<Float>.size)
            }

            // Copy music after needle drop
            if let musicSrc = music.floatChannelData?[ch] {
                memcpy(dst.advanced(by: Int(ndFrames)), musicSrc, Int(musicFrames) * MemoryLayout<Float>.size)
            }
        }

        return out
    }

    // MARK: - Mode Switching

    func switchToLibrary() {
        if activeMode == .library { return }
        if isPreviewing { stopPreview() }
        if isPlaying { stopPlayback() }
        activeMode = .library
        let track = lastSampleTrack ?? SampleTrack.library.first(where: { $0.id == "france" }) ?? SampleTrack.library[0]
        loadTrack(track)
    }

    func switchToConverter() {
        if activeMode == .converter { return }
        if isPlaying { stopPlayback() }
        activeMode = .converter
        currentTrack = nil
        pausedPosition = 0
        currentTime = 0
        if let url = convertedFileURL {
            // Converted file exists — load it for preview
            displayTitle = url.deletingPathExtension().lastPathComponent
            loadConvertedIntoPlayer(url: url)
        } else if let buf = converterBuffer {
            // Source loaded but not yet converted — reload for auditioning
            displayTitle = converterSourceName
            audioBuffer = buf
            let sr = buf.format.sampleRate
            duration = Double(buf.frameLength) / sr
        } else {
            displayTitle = "no file loaded"
            duration = 0
        }
    }

    // MARK: - Podcast Streaming

    @Published var isPodcastLoading = false
    @Published var podcastLoadError: String?
    private var currentEpisodeId: String?
    private var urlDownloadTask: URLSessionDownloadTask?
    private var podcastFileURL: URL?
    /// Total duration of the full podcast episode (not the chunk)
    private var podcastTotalDuration: Double = 0
    /// Absolute start time (in seconds) of the currently loaded chunk within the full episode
    private var podcastChunkStartTime: Double = 0
    /// Episode list from the current feed (newest first) for skip forward/back
    private var podcastEpisodeList: [PodcastEpisode] = []
    /// Index of the currently playing episode within podcastEpisodeList
    private var podcastEpisodeIndex: Int = 0

    /// True when a podcast episode is loaded (not a sample track or converter file)
    var isPodcastMode: Bool { podcastFileURL != nil || isPodcastLoading }

    /// Can skip back to a previous (older) episode in the feed
    var canPodcastSkipBack: Bool {
        isPodcastMode && !podcastEpisodeList.isEmpty && podcastEpisodeIndex < podcastEpisodeList.count - 1
    }

    /// Can skip forward to a more recent episode in the feed
    var canPodcastSkipForward: Bool {
        isPodcastMode && !podcastEpisodeList.isEmpty && podcastEpisodeIndex > 0
    }

    /// Skip to the previous (older) episode
    func podcastSkipBack() {
        guard canPodcastSkipBack else { return }
        podcastEpisodeIndex += 1
        let episode = podcastEpisodeList[podcastEpisodeIndex]
        playPodcastEpisode(episode)
    }

    /// Skip to the next (more recent) episode
    func podcastSkipForward() {
        guard canPodcastSkipForward else { return }
        podcastEpisodeIndex -= 1
        let episode = podcastEpisodeList[podcastEpisodeIndex]
        playPodcastEpisode(episode)
    }

    /// Load a ~10-minute chunk of the podcast file starting at the given absolute time.
    /// Sets audioBuffer to the chunk (with needle drop if applicable), updates
    /// podcastChunkStartTime, and preserves podcastTotalDuration as `duration`.
    private func loadPodcastChunk(at absoluteTime: Double) {
        guard let af = audioFile else { return }
        let sr = af.fileFormat.sampleRate
        let totalFrames = af.length

        // Seek the file to the correct frame
        let startFrame = min(AVAudioFramePosition(absoluteTime * sr), totalFrames)
        af.framePosition = startFrame
        podcastChunkStartTime = Double(startFrame) / sr

        // Read up to 10 minutes of audio
        let remainingFrames = totalFrames - startFrame
        let maxChunkFrames = AVAudioFrameCount(min(Double(remainingFrames), sr * 600))
        guard maxChunkFrames > 0 else { return }

        guard let rawBuffer = AVAudioPCMBuffer(pcmFormat: af.processingFormat, frameCapacity: maxChunkFrames) else { return }
        do {
            try af.read(into: rawBuffer, frameCount: maxChunkFrames)
        } catch {
            print("Podcast chunk read error: \(error)")
            return
        }

        audioBuffer = toStereo(rawBuffer)
        needleDropFrameCount = 0

        // Only prepend needle drop at the very start of the episode
        if podcastChunkStartTime < 1.0 {
            rebuildBufferWithNeedleDrop()
        }

        // Always preserve full episode duration (rebuildBufferWithNeedleDrop overwrites it)
        duration = podcastTotalDuration
    }

    /// Set episode list context for skip forward/back. Call before playPodcastEpisode.
    func setPodcastEpisodeList(_ episodes: [PodcastEpisode], currentIndex: Int) {
        podcastEpisodeList = episodes
        podcastEpisodeIndex = currentIndex
    }

    func playPodcastEpisode(_ episode: PodcastEpisode, resumeFrom: TimeInterval = 0) {
        if isPlaying { stopPlayback() } else { playerNode.stop() }

        isPodcastLoading = true
        podcastLoadError = nil
        currentEpisodeId = episode.id
        currentTrack = nil
        activeMode = .library
        displayTitle = episode.title
        pausedPosition = 0
        currentTime = 0

        // Use downloadTask — streams to disk, never holds entire file in RAM
        urlDownloadTask?.cancel()
        urlDownloadTask = URLSession.shared.downloadTask(with: episode.audioURL) { [weak self] tempLocation, response, error in
            guard let self = self else { return }

            if let error = error as NSError?, error.code == NSURLErrorCancelled { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.isPodcastLoading = false
                    self.podcastLoadError = "Download failed: \(error.localizedDescription)"
                }
                return
            }

            guard let tempLocation = tempLocation else {
                DispatchQueue.main.async {
                    self.isPodcastLoading = false
                    self.podcastLoadError = "No audio data received"
                }
                return
            }

            // Move to a stable temp path (download temp files get deleted immediately)
            let ext = episode.audioURL.pathExtension.isEmpty ? "mp3" : episode.audioURL.pathExtension
            let destURL = FileManager.default.temporaryDirectory.appendingPathComponent("podcast_stream.\(ext)")
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.moveItem(at: tempLocation, to: destURL)
                self.podcastFileURL = destURL

                // Open the file on disk — AVAudioFile reads lazily, not all at once
                let file = try AVAudioFile(forReading: destURL)
                let sr = file.fileFormat.sampleRate
                let totalFrames = file.length
                let totalDuration = Double(totalFrames) / sr
                // Read in a capped chunk (max ~10 minutes at a time to limit RAM)
                let maxFrames = AVAudioFrameCount(min(Double(totalFrames), sr * 600))
                let rawBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: maxFrames)
                guard let ab = rawBuffer else {
                    DispatchQueue.main.async {
                        self.isPodcastLoading = false
                        self.podcastLoadError = "Buffer allocation failed"
                    }
                    return
                }
                try file.read(into: ab, frameCount: maxFrames)
                let stereo = self.toStereo(ab)

                DispatchQueue.main.async {
                    self.audioFile = file
                    self.audioBuffer = stereo
                    self.needleDropFrameCount = 0
                    self.podcastTotalDuration = totalDuration
                    self.podcastChunkStartTime = 0
                    self.rebuildBufferWithNeedleDrop()
                    // Always use full episode duration, not chunk duration
                    self.duration = totalDuration
                    self.isPodcastLoading = false

                    // Apply podcast preset
                    if let podcastPreset = VinylPreset.all.first(where: { $0.id == "podcast" }) {
                        self.applyPreset(podcastPreset)
                    }

                    // Resume from saved position if applicable
                    if resumeFrom > 0 {
                        let ndOffset = Double(self.needleDropFrameCount) / self.sampleRate
                        self.seek(to: resumeFrom + ndOffset)
                    } else {
                        self.startPlayback()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isPodcastLoading = false
                    self.podcastLoadError = "Failed to load audio: \(error.localizedDescription)"
                }
            }
        }
        urlDownloadTask?.resume()
    }

    func cancelPodcastDownload() {
        urlDownloadTask?.cancel()
        isPodcastLoading = false
    }

    // MARK: - Converter

    func loadForConversion(url: URL) {
        // Read once while security scope is active, then share buffer
        let wasPlaying = isPlaying
        if isPlaying { stopPlayback() } else { playerNode.stop() }
        // Clear podcast state
        podcastFileURL = nil
        podcastTotalDuration = 0
        podcastChunkStartTime = 0
        currentEpisodeId = nil
        podcastEpisodeList = []
        podcastEpisodeIndex = 0
        currentTrack = nil
        activeMode = .converter
        converterSourceName = url.deletingPathExtension().lastPathComponent
        displayTitle = converterSourceName
        convertFailed = false
        pausedPosition = 0
        currentTime = 0
        do {
            let file = try AVAudioFile(forReading: url)
            let sr = file.fileFormat.sampleRate
            let frameCount = AVAudioFrameCount(file.length)
            duration = Double(file.length) / sr
            let rawBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount)
            guard let ab = rawBuffer else { return }
            try file.read(into: ab)
            let stereo = toStereo(ab)
            // Set both main player buffer and converter buffer from single read
            audioFile = file
            audioBuffer = stereo
            needleDropFrameCount = 0
            rebuildBufferWithNeedleDrop()
            converterBuffer = strippedMusicBuffer()  // converter always uses clean music
            applyPreset(.audiophile)
            preampOn = true
            powerampOn = true
            updateAmpParams()
            if wasPlaying {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.startPlayback()
                }
            }
        } catch { print("Converter load error: \(error)") }
        convertedFileURL = nil
        converterSourceLoaded = true
        isPreviewing = false
        previewPlayer?.stop()
        previewPlayer = nil
    }

    var hasConvertedFile: Bool { convertedFileURL != nil }
    var sampleRate: Double { audioBuffer?.format.sampleRate ?? 44100 }

    func performOfflineRender() {
        guard let sourceBuffer = converterBuffer else { return }
        if isPlaying { stopPlayback() }
        isConverting = true
        convertProgress = 0
        convertedFileURL = nil

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                let result = try self.offlineRender(source: sourceBuffer)
                DispatchQueue.main.async {
                    self.convertedFileURL = result
                    self.isConverting = false
                    self.convertProgress = 1.0
                    self.convertFailed = false
                    self.displayTitle = result.deletingPathExtension().lastPathComponent
                    self.scanConvertedFiles()
                    // Load converted WAV into main player for preview with transport controls
                    self.loadConvertedIntoPlayer(url: result)
                }
            } catch {
                print("Offline render error: \(error)")
                DispatchQueue.main.async {
                    self.isConverting = false
                    self.convertProgress = 0
                    self.convertFailed = true
                }
            }
        }
    }

    private func offlineRender(source: AVAudioPCMBuffer) throws -> URL {
        let sampleRate = source.format.sampleRate
        let channels: AVAudioChannelCount = 2
        let renderFmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let totalFrames = source.frameLength

        // 1) Pre-resample source with wow/flutter rate curve baked in
        let prebaked = prebakeWowFlutter(source: source, format: renderFmt)

        // 2) Build offline engine with duplicate EQ chain
        let offEngine = AVAudioEngine()
        let offPlayer = AVAudioPlayerNode()
        let offLP = makeEQ(type: .lowPass, freq: 18000)
        let offHP = makeEQ(type: .highPass, freq: 28)
        let offRIAA = makeEQ(type: .parametric, freq: 900, bw: 1.0, gain: 0)
        let offRoom = makeEQ(type: .parametric, freq: 180, bw: 0.5, gain: 0)
        let offSat = AVAudioUnitDistortion(); offSat.wetDryMix = 0
        let offTubeWarmth = makeEQ(type: .parametric, freq: 200, bw: 1.0, gain: 0)
        let offTubeAir = makeEQ(type: .highShelf, freq: 10000, gain: 0)
        let offMicro = makeEQ(type: .parametric, freq: 220, bw: 0.2, gain: 0)
        let offXformer = makeEQ(type: .lowShelf, freq: 120, gain: 0)
        let offSpeaker = makeEQ(type: .parametric, freq: 2800, bw: 1.2, gain: 0)
        let offMixer = AVAudioMixerNode()
        let offHiss = AVAudioPlayerNode()
        let offRumble = AVAudioPlayerNode()
        let offCrackle = AVAudioPlayerNode()

        let nodes: [AVAudioNode] = [offPlayer, offHP, offRIAA, offTubeWarmth, offTubeAir, offMicro, offXformer, offSpeaker, offSat, offLP, offRoom, offMixer, offHiss, offRumble, offCrackle]
        nodes.forEach { offEngine.attach($0) }

        offEngine.connect(offPlayer, to: offHP, format: renderFmt)
        offEngine.connect(offHP, to: offRIAA, format: renderFmt)
        offEngine.connect(offRIAA, to: offTubeWarmth, format: renderFmt)
        offEngine.connect(offTubeWarmth, to: offTubeAir, format: renderFmt)
        offEngine.connect(offTubeAir, to: offMicro, format: renderFmt)
        offEngine.connect(offMicro, to: offXformer, format: renderFmt)
        offEngine.connect(offXformer, to: offSpeaker, format: renderFmt)
        offEngine.connect(offSpeaker, to: offSat, format: renderFmt)
        offEngine.connect(offSat, to: offLP, format: renderFmt)
        offEngine.connect(offLP, to: offRoom, format: renderFmt)
        offEngine.connect(offRoom, to: offMixer, format: renderFmt)
        offEngine.connect(offHiss, to: offMixer, format: renderFmt)
        offEngine.connect(offRumble, to: offMixer, format: renderFmt)
        offEngine.connect(offCrackle, to: offMixer, format: renderFmt)
        offEngine.connect(offMixer, to: offEngine.mainMixerNode, format: renderFmt)

        // Apply current EQ params to offline chain
        let w = params.wear / 100
        let m = params.masterIntensity / 100
        if !isBypassed {
            let cutoff = max(600.0, 18000.0 - Double(w) * 11000 - Double(params.hfRolloff) / 100 * Double(m) * 13000)
            offLP.bands[0].frequency = Float(cutoff)
            offRIAA.bands[0].gain = params.riaaVariance / 100 * m * 6 - 3
            offRoom.bands[0].gain = params.roomResonance / 100 * m * 3
            let pa = preampOn && !isBypassed
            let pw = powerampOn && !isBypassed
            offTubeWarmth.bands[0].gain = pa ? params.saturation / 100 * m * 1.2 : 0
            offTubeAir.bands[0].gain = pa ? -(params.hfRolloff / 100 * m * 0.35) : 0
            offMicro.bands[0].gain = pa ? params.roomResonance / 100 * m * 0.6 : 0
            offXformer.bands[0].gain = pw ? params.rumble / 100 * m * 0.6 : 0
            offSpeaker.bands[0].gain = pw ? -(params.roomResonance / 100 * m * 0.5) : 0
        }

        // Noise volumes
        let active = !isBypassed
        offHiss.volume = active ? Float((0.01 + Double(w) * 0.08) * Double(params.hiss) / 100 * Double(m)) * 2 : 0
        offRumble.volume = active ? Float((0.02 + Double(w) * 0.22) * Double(params.rumble) / 100 * Double(m)) * 1.5 : 0
        offCrackle.volume = active ? Float((0.08 + Double(w) * 0.55) * Double(params.crackle) / 100 * Double(m)) * 1.0 : 0

        // Enable offline rendering
        try offEngine.enableManualRenderingMode(.offline, format: renderFmt, maximumFrameCount: 4096)
        try offEngine.start()

        // Schedule source and noise
        offPlayer.scheduleBuffer(prebaked, at: nil, options: [])
        offPlayer.play()

        // Generate noise buffers for offline
        let dur = Double(totalFrames) / sampleRate + 1.0
        if let hb = makePink(renderFmt, min(dur, 5.0), 1.0) { offHiss.scheduleBuffer(hb, at: nil, options: .loops) }
        if let rb = makeRumble(renderFmt, min(dur, 3.0), 1.0) { offRumble.scheduleBuffer(rb, at: nil, options: .loops) }
        let t = Double(params.crackle) / 100.0
        let popProb = 0.000001 * pow(2000.0, t)
        if let cb = makeCrackle(renderFmt, min(dur, 3.0), 1.0, popProb: popProb) { offCrackle.scheduleBuffer(cb, at: nil, options: .loops) }
        offHiss.play(); offRumble.play(); offCrackle.play()

        // Render in chunks, writing directly to output file
        let outputFrames = prebaked.frameLength
        let tempDir = VinylEngine.documentsDirectory
        let baseName = converterSourceName.isEmpty ? "Vinyl_\(Int(Date().timeIntervalSince1970))" : "\(converterSourceName)_vinyl"
        let filename = "\(baseName).wav"
        let outputURL = tempDir.appendingPathComponent(filename)

        let outputFile = try AVAudioFile(forWriting: outputURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])

        guard let renderBuf = AVAudioPCMBuffer(pcmFormat: renderFmt, frameCapacity: 4096) else {
            throw NSError(domain: "Vinyl", code: -1, userInfo: [NSLocalizedDescriptionKey: "Buffer allocation failed"])
        }

        var framesRendered: AVAudioFrameCount = 0
        while framesRendered < outputFrames {
            let status = try offEngine.renderOffline(min(4096, outputFrames - framesRendered), to: renderBuf)
            switch status {
            case .success:
                try outputFile.write(from: renderBuf)
                framesRendered += renderBuf.frameLength
                let prog = Double(framesRendered) / Double(outputFrames)
                DispatchQueue.main.async { self.convertProgress = prog }
            case .error, .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                break
            @unknown default:
                break
            }
            if status != .success { break }
        }

        offEngine.stop()
        return outputURL
    }

    private func prebakeWowFlutter(source: AVAudioPCMBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer {
        guard !isBypassed else { return source }
        let sr = format.sampleRate
        let totalSamples = Int(source.frameLength)
        let duration = Double(totalSamples) / sr
        let w = Double(params.wear) / 100
        let m = Double(params.masterIntensity) / 100
        let wowD = (0.004 + w * 0.035) * Double(params.wowDepth) / 100 * m
        let flutD = (0.002 + w * 0.02) * Double(params.flutter) / 100 * m
        let warpD = (0.006 + w * 0.05) * Double(params.warpWow) / 100 * m

        // Build rate curve in 50ms chunks
        let chunkDuration = 0.05
        let totalChunks = Int(duration / chunkDuration) + 1
        var rateCurve = [Float](repeating: 1.0, count: totalChunks)
        var phase = 0.0
        for i in 0..<totalChunks {
            phase += chunkDuration
            let wow = wowD * sin(2 * .pi * 0.4 * phase)
            let flutter = flutD * sin(2 * .pi * 8 * phase)
            let warp = warpD * sin(2 * .pi * 0.25 * phase)
            rateCurve[i] = Float(max(0.97, min(1.03, 1.0 + wow + flutter + warp)))
        }

        // Variable-rate resample
        let chunkSamples = Int(chunkDuration * sr)
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalSamples + Int(sr))) else { return source }
        var outPos = 0
        var srcPos: Double = 0.0

        for ch in 0..<Int(format.channelCount) {
            guard let srcData = source.floatChannelData?[ch],
                  let dstData = output.floatChannelData?[ch] else { continue }
            outPos = 0
            srcPos = 0.0
            for chunkIdx in 0..<totalChunks {
                let rate = Double(rateCurve[chunkIdx])
                let samplesThisChunk = chunkSamples
                for _ in 0..<samplesThisChunk {
                    let intSrc = Int(srcPos)
                    let frac = Float(srcPos - Double(intSrc))
                    if intSrc + 1 < totalSamples {
                        dstData[outPos] = srcData[intSrc] * (1 - frac) + srcData[intSrc + 1] * frac
                    } else if intSrc < totalSamples {
                        dstData[outPos] = srcData[intSrc]
                    } else { break }
                    outPos += 1
                    srcPos += rate
                    if outPos >= totalSamples + Int(sr) { break }
                }
                if outPos >= totalSamples + Int(sr) { break }
            }
        }

        output.frameLength = AVAudioFrameCount(min(outPos, totalSamples + Int(sr)))

        // Mono mix if enabled
        if monoMode, format.channelCount == 2,
           let l = output.floatChannelData?[0],
           let r = output.floatChannelData?[1] {
            for i in 0..<Int(output.frameLength) {
                let mid = (l[i] + r[i]) * 0.5
                l[i] = mid; r[i] = mid
            }
        }

        return output
    }

    /// Load the converted WAV into the main player buffer (no effects applied)
    private func loadConvertedIntoPlayer(url: URL) {
        if isPlaying { stopPlayback() } else { playerNode.stop() }
        pausedPosition = 0
        currentTime = 0
        needleDropFrameCount = 0  // converted files don't get needle drop
        do {
            let file = try AVAudioFile(forReading: url)
            duration = Double(file.length) / file.fileFormat.sampleRate
            let frameCount = AVAudioFrameCount(file.length)
            let rawBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount)
            guard let ab = rawBuffer else { return }
            try file.read(into: ab)
            audioFile = file
            audioBuffer = toStereo(ab)
        } catch { print("Load converted error: \(error)") }
    }

    private var bypassBeforePreview = false

    func previewConverted() {
        guard audioBuffer != nil, convertedFileURL != nil else { return }
        // Enable bypass so the already-rendered WAV plays clean through the player
        bypassBeforePreview = isBypassed
        if !isBypassed {
            isBypassed = true
            updateVinylParams()
            updateAmpParams()
            scheduleNoiseUpdate()
        }
        isPreviewing = true
        pausedPosition = 0
        currentTime = 0
        startPlayback()
    }

    func stopPreview() {
        if isPlaying { stopPlayback() }
        isPreviewing = false
        // Restore bypass state
        isBypassed = bypassBeforePreview
        updateVinylParams()
        updateAmpParams()
        scheduleNoiseUpdate()
    }

    func clearConverter() {
        stopPreview()
        converterBuffer = nil
        convertedFileURL = nil
        convertProgress = 0
        converterSourceLoaded = false
        convertFailed = false
        converterSourceName = ""
    }
}
