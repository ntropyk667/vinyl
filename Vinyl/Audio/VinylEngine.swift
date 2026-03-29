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

    // Converter state
    @Published var isConverting = false
    @Published var convertProgress: Double = 0
    @Published var convertedFileURL: URL?
    @Published var isPreviewing = false
    @Published var converterSourceLoaded = false
    private var converterBuffer: AVAudioPCMBuffer?
    private var previewPlayer: AVAudioPlayer?

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
    private var tubeWarmthEQ: AVAudioUnitEQ!
    private var tubeAirEQ: AVAudioUnitEQ!
    private var microEQ: AVAudioUnitEQ!
    private var xformerEQ: AVAudioUnitEQ!
    private var speakerEQ: AVAudioUnitEQ!
    private var hissPlayer = AVAudioPlayerNode()
    private var rumblePlayer = AVAudioPlayerNode()
    private var cracklePlayer = AVAudioPlayerNode()
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
        applyPreset(.electronic)
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
        satNode.wetDryMix = 0
        tubeWarmthEQ = makeEQ(type: .parametric, freq: 200, bw: 1.0, gain: 0)
        tubeAirEQ = makeEQ(type: .highShelf, freq: 10000, gain: 0)
        microEQ = makeEQ(type: .parametric, freq: 220, bw: 0.2, gain: 0)
        xformerEQ = makeEQ(type: .lowShelf, freq: 120, gain: 0)
        speakerEQ = makeEQ(type: .parametric, freq: 2800, bw: 1.2, gain: 0)
        let nodes: [AVAudioNode] = [playerNode, hpFilter, riaaEQ, tubeWarmthEQ, tubeAirEQ, microEQ, xformerEQ, speakerEQ, satNode, lpFilter, roomEQ, masterMixer, hissPlayer, rumblePlayer, cracklePlayer]
        nodes.forEach { engine.attach($0) }
        let fmt = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(playerNode, to: hpFilter, format: nil)
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
        currentTrack = track
        displayTitle = track.title
        pausedPosition = 0
        currentTime = 0
        let url = Bundle.main.url(forResource: track.filename, withExtension: "mp3")
            ?? Bundle.main.url(forResource: track.filename, withExtension: "m4a")
            ?? Bundle.main.url(forResource: track.filename, withExtension: "mp4")
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
        currentTrack = nil
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
        guard let buffer = audioBuffer else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { print("Engine start failed: \(error)"); return }
        }
        let sr = audioFile?.fileFormat.sampleRate ?? 44100
        let startFrame = AVAudioFramePosition(pausedPosition * sr)
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
        // FIX: guard against stale completion callbacks fired after stopPlayback()
        playerNode.scheduleBuffer(sub, at: nil, options: []) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.isPlaying else { return }
                self.handleEnd()
            }
        }
        playerNode.play()
        if !hissPlayer.isPlaying { hissPlayer.play() }
        if !rumblePlayer.isPlaying { rumblePlayer.play() }
        if !cracklePlayer.isPlaying { cracklePlayer.play() }
        isPlaying = true
        startProgressTimer()
        startDriftTimer()
        startWow()
        updateVinylParams()
        updateAmpParams()
    }

    func stopPlayback() {
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

    func restart() { seek(to: 0) }

    private func handleEnd() {
        // Buffer finished naturally. Clean up timers, reset position, loop from top.
        // FIX: no resetPlayerNode() — reuse the same node graph; just stop and reschedule.
        isPlaying = false
        progressTimer?.invalidate(); progressTimer = nil
        driftTimer?.invalidate(); driftTimer = nil
        wowTimer?.invalidate(); wowTimer = nil
        pausedPosition = 0
        currentTime = 0
        startPlayback()
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
        guard !isBypassed else { return }
        var phase: Double = 0
        let w = Double(params.wear) / 100
        let m = Double(params.masterIntensity) / 100
        let wowD = (0.004 + w * 0.035) * Double(params.wowDepth) / 100 * m
        let flutD = (0.002 + w * 0.02) * Double(params.flutter) / 100 * m
        let warpD = (0.006 + w * 0.05) * Double(params.warpWow) / 100 * m
        wowTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            phase += 0.05
            let combined = 1.0 + wowD * sin(2 * Double.pi * 0.4 * phase) + flutD * sin(2 * Double.pi * 8 * phase) + warpD * sin(2 * Double.pi * 0.25 * phase) + self.driftOffset
            self.playerNode.rate = Float(max(0.97, min(1.03, combined)))
        }
    }

    func applyPreset(_ preset: VinylPreset) {
        currentPreset = preset
        params = preset.params
        monoMode = (preset.id == "78rpm")
        updateVinylParams()
        updateAmpParams()
        scheduleNoiseUpdate()
        if isPlaying { seek(to: currentTime) }
    }

    func updateAllParams() {
        updateVinylParams()
        updateAmpParams()
        scheduleNoiseUpdate()
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
            satNode.wetDryMix = 0
            roomEQ.bands[0].gain = 0
            riaaEQ.bands[0].gain = 0
            return
        }
        let w = params.wear / 100
        let m = params.masterIntensity / 100
        let cutoff = max(600.0, 18000.0 - Double(w) * 11000 - Double(params.hfRolloff) / 100 * Double(m) * 13000)
        lpFilter.bands[0].frequency = Float(cutoff)
        satNode.wetDryMix = 0  // saturation effect removed — tube warmth EQ handles all warmth
        riaaEQ.bands[0].gain = params.riaaVariance / 100 * m * 6 - 3
        roomEQ.bands[0].gain = params.roomResonance / 100 * m * 3
    }

    func updateAmpParams() {
        let pa = preampOn && !isBypassed
        let pw = powerampOn && !isBypassed
        let m = params.masterIntensity / 100
        tubeWarmthEQ.bands[0].gain = pa ? params.saturation / 100 * m * 1.2 : 0
        tubeAirEQ.bands[0].gain = pa ? -(params.hfRolloff / 100 * m * 0.35) : 0
        microEQ.bands[0].gain = pa ? params.roomResonance / 100 * m * 0.6 : 0
        xformerEQ.bands[0].gain = pw ? params.rumble / 100 * m * 0.6 : 0
        speakerEQ.bands[0].gain = pw ? -(params.roomResonance / 100 * m * 0.5) : 0
    }

    func updateNoiseParams() {
        let w = params.wear / 100
        let m = params.masterIntensity / 100
        let active = !isBypassed
        hissPlayer.volume = active ? Float((0.01 + Double(w) * 0.08) * Double(params.hiss) / 100 * Double(m)) * 2 : 0
        rumblePlayer.volume = active ? Float((0.02 + Double(w) * 0.22) * Double(params.rumble) / 100 * Double(m)) * 1.5 : 0
        cracklePlayer.volume = active ? Float((0.08 + Double(w) * 0.55) * Double(params.crackle) / 100 * Double(m)) * 1.0 : 0
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

    // MARK: - Converter

    func loadForConversion(url: URL) {
        // Read once while security scope is active, then share buffer
        let wasPlaying = isPlaying
        if isPlaying { stopPlayback() } else { playerNode.stop() }
        currentTrack = nil
        displayTitle = url.deletingPathExtension().lastPathComponent
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
            converterBuffer = stereo
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
                    self.displayTitle = result.deletingPathExtension().lastPathComponent
                }
            } catch {
                print("Offline render error: \(error)")
                DispatchQueue.main.async {
                    self.isConverting = false
                    self.convertProgress = 0
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
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "Vinyl_\(Int(Date().timeIntervalSince1970)).wav"
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

    func previewConverted() {
        guard let url = convertedFileURL else { return }
        // Stop main playback so preview plays clean (no double effects)
        if isPlaying { stopPlayback() }
        do {
            previewPlayer = try AVAudioPlayer(contentsOf: url)
            previewPlayer?.delegate = nil
            previewPlayer?.play()
            isPreviewing = true
        } catch { print("Preview error: \(error)") }
    }

    func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        isPreviewing = false
    }

    func clearConverter() {
        stopPreview()
        converterBuffer = nil
        convertedFileURL = nil
        convertProgress = 0
        converterSourceLoaded = false
    }
}
