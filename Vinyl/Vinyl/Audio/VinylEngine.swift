import AVFoundation
import Combine

class VinylEngine: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isBypassed = false
    @Published var preampOn = true
    @Published var powerampOn = true
    @Published var params = VinylParameters()
    @Published var currentTrack: SampleTrack?
    @Published var currentPreset: VinylPreset = .electronic

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
        if let b = makePink(fmt, 3.0, 0) { hissPlayer.scheduleBuffer(b, at: nil, options: .loops) }
        if let b = makeRumble(fmt, 2.0, 0) { rumblePlayer.scheduleBuffer(b, at: nil, options: .loops) }
        if let b = makeCrackle(fmt, 2.0, 0) { cracklePlayer.scheduleBuffer(b, at: nil, options: .loops) }
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

    private func makeCrackle(_ fmt: AVAudioFormat, _ dur: Double, _ gain: Float) -> AVAudioPCMBuffer? {
        let n = AVAudioFrameCount(fmt.sampleRate * dur)
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n) else { return nil }
        buf.frameLength = n
        var phase = 0; var amp: Float = 1
        for ch in 0..<Int(fmt.channelCount) {
            guard let d = buf.floatChannelData?[ch] else { continue }
            for i in 0..<Int(n) {
                if Double.random(in: 0...1) < 0.0003 { phase = Int.random(in: 8...28); amp = Float.random(in: 0.4...1.0) }
                if phase > 0 { d[i] = Float.random(in: -1...1) * amp * Float(phase) / 28.0 * gain; phase -= 1 }
                else { d[i] = 0 }
            }
        }
        return buf
    }

    private func resetPlayerNode() {
        engine.detach(playerNode)
        playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: hpFilter, format: nil)
    }

    func loadTrack(_ track: SampleTrack) {
        let wasPlaying = isPlaying
        if isPlaying { stopPlayback() }
        resetPlayerNode()
        currentTrack = track
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
            audioBuffer = AVAudioPCMBuffer(pcmFormat: af.processingFormat, frameCapacity: frameCount)
            guard let ab = audioBuffer else { return }
            try af.read(into: ab)
            if let preset = VinylPreset.all.first(where: { $0.id == track.defaultPresetID }) { applyPreset(preset) }
            if wasPlaying { startPlayback() }
        } catch { print("Load error: \(error)") }
    }

    func loadFile(url: URL) {
        let wasPlaying = isPlaying
        if isPlaying { stopPlayback() }
        resetPlayerNode()
        pausedPosition = 0
        currentTime = 0
        do {
            audioFile = try AVAudioFile(forReading: url)
            guard let af = audioFile else { return }
            duration = Double(af.length) / af.fileFormat.sampleRate
            let frameCount = AVAudioFrameCount(af.length)
            audioBuffer = AVAudioPCMBuffer(pcmFormat: af.processingFormat, frameCapacity: frameCount)
            guard let ab = audioBuffer else { return }
            try af.read(into: ab)
            applyPreset(.audiophile)
            preampOn = false
            powerampOn = false
            updateAmpParams()
            if wasPlaying { startPlayback() }
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
        playerNode.scheduleBuffer(sub, at: nil, options: []) { [weak self] in
            DispatchQueue.main.async { self?.handleEnd() }
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
        playerNode.pause()
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
        if isPlaying { stopPlayback() }
        resetPlayerNode()
        pausedPosition = max(0, min(time, duration - 0.1))
        currentTime = pausedPosition
        if was { startPlayback() }
    }

    func restart() { seek(to: 0) }

    private func handleEnd() {
        pausedPosition = 0
        currentTime = 0
        resetPlayerNode()
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
        updateVinylParams()
        updateAmpParams()
        scheduleNoiseUpdate()
    }

    func updateAllParams() {
        updateVinylParams()
        updateAmpParams()
        scheduleNoiseUpdate()
    }

    private func scheduleNoiseUpdate() {
        noiseUpdateWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.updateNoiseParams() }
        noiseUpdateWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
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
        satNode.wetDryMix = min(params.saturation / 100 * m * 25, 20)
        riaaEQ.bands[0].gain = params.riaaVariance / 100 * m * 6 - 3
        roomEQ.bands[0].gain = params.roomResonance / 100 * m * 3
    }

    func updateAmpParams() {
        let pa = preampOn && !isBypassed
        let pw = powerampOn && !isBypassed
        let m = params.masterIntensity / 100
        tubeWarmthEQ.bands[0].gain = pa ? params.saturation / 100 * m * 2.5 : 0
        tubeAirEQ.bands[0].gain = pa ? -(params.hfRolloff / 100 * m * 0.75) : 0
        microEQ.bands[0].gain = pa ? params.roomResonance / 100 * m * 1.2 : 0
        xformerEQ.bands[0].gain = pw ? params.rumble / 100 * m * 1.2 : 0
        speakerEQ.bands[0].gain = pw ? -(params.roomResonance / 100 * m) : 0
    }

    func updateNoiseParams() {
        let w = params.wear / 100
        let m = params.masterIntensity / 100
        let active = !isBypassed
        hissPlayer.volume = active ? Float((0.01 + Double(w) * 0.08) * Double(params.hiss) / 100 * Double(m)) * 8 : 0
        rumblePlayer.volume = active ? Float((0.02 + Double(w) * 0.22) * Double(params.rumble) / 100 * Double(m)) * 5 : 0
        cracklePlayer.volume = active ? Float((0.08 + Double(w) * 0.55) * Double(params.crackle) / 100 * Double(m)) * 3 : 0
    }

    func toggleBypass() {
        isBypassed.toggle()
        updateVinylParams()
        updateAmpParams()
        scheduleNoiseUpdate()
    }
}
