import SwiftUI

struct SampleLibraryView: View, Equatable {
    var engine: VinylEngine
    var onSelect: (() -> Void)? = nil
    static func == (lhs: SampleLibraryView, rhs: SampleLibraryView) -> Bool {
        lhs.engine.currentTrack?.id == rhs.engine.currentTrack?.id &&
        lhs.engine.convertedFiles.map(\.lastPathComponent) == rhs.engine.convertedFiles.map(\.lastPathComponent)
    }
    var body: some View {
        VStack(spacing: 4) {
            ForEach(SampleTrack.library) { track in
                let preset = VinylPreset.all.first(where: { $0.id == track.defaultPresetID })?.name ?? ""
                let isSelected = engine.currentTrack?.id == track.id
                Button(action: {
                    engine.loadTrack(track)
                    engine.startPlayback()
                    onSelect?()
                }) {
                    libraryRow(label: "\(track.title) — \(track.artist) [\(preset)]", isSelected: isSelected)
                }
            }

            if !engine.convertedFiles.isEmpty {
                Text("CONVERTED".uppercased())
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .kerning(1.0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)

                ForEach(engine.convertedFiles, id: \.lastPathComponent) { url in
                    let name = url.deletingPathExtension().lastPathComponent
                    let isSelected = engine.convertedFileURL == url
                    Button(action: {
                        engine.loadFile(url: url)
                        engine.startPlayback()
                        onSelect?()
                    }) {
                        libraryRow(label: name, isSelected: isSelected)
                    }
                }
            }
        }
    }

    private func libraryRow(label: String, isSelected: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(isSelected ? Color(hex: "c8b89a") : Color(hex: "e8e6e0"))
                .lineLimit(1)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(hex: "c8b89a"))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(isSelected ? Color(hex: "1e1a14") : Color(hex: "161616"))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(
            isSelected ? Color(hex: "c8b89a").opacity(0.4) : Color.white.opacity(0.08),
            lineWidth: 0.5))
        .cornerRadius(6)
    }
}

struct PresetsView: View {
    @ObservedObject var engine: VinylEngine
    let columns = [GridItem(.adaptive(minimum: 90), spacing: 5)]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("presets")
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(VinylPreset.all) { preset in
                    PresetButton(preset: preset, isActive: engine.currentPreset.id == preset.id) {
                        engine.applyPreset(preset)
                    }
                }
            }
        }
    }
}

struct PresetButton: View {
    let preset: VinylPreset; let isActive: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name).font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isActive ? Color(hex: "c8b89a") : Color(hex: "9a9690"))
                Text(preset.description).font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(hex: "5a5856")).lineLimit(2).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            // Fill the full width AND height of the LazyVGrid row cell so every
            // preset button matches its row-mates. LazyVGrid sizes each row to
            // the tallest cell; without `maxHeight: .infinity` a button with a
            // shorter description (e.g. "custom / default settings" — 1 line
            // vs. the 2-line descriptions on every other preset) renders
            // shorter than its neighbor. `alignment: .topLeading` keeps the
            // text pinned to the top-left so layout inside the button is
            // unchanged for the already-2-line presets.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(isActive ? Color(hex: "1e1e1e") : Color(hex: "161616"))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isActive ? Color(hex: "c8b89a") : Color.white.opacity(0.08), lineWidth: 0.5))
            .cornerRadius(6)
        }
    }
}

struct MasterControlsView: View {
    @ObservedObject var engine: VinylEngine
    var body: some View {
        VStack(spacing: 6) {
            MasterSliderRow(label: "record wear", sub: "shifts all effect floors",
                value: Binding(get: { engine.params.wear }, set: { engine.params.wear = $0; engine.updateVinylParams() }),
                display: { v in "\(Int(v))% — \(wearLabel(v))" })
            MasterSliderRow(label: "master intensity", sub: "scales all effects",
                value: Binding(get: { engine.params.masterIntensity }, set: { engine.params.masterIntensity = $0; engine.updateAllParams() }),
                display: { v in "\(Int(v))" })
        }
    }
    private func wearLabel(_ v: Float) -> String {
        let l = ["pristine","pristine","lightly worn","lightly worn","lightly worn","well played","well played","heavily worn","heavily worn","degraded"]
        return l[min(9, Int(v/10))]
    }
}

struct MasterSliderRow: View {
    let label: String; let sub: String; @Binding var value: Float; let display: (Float) -> String
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(Color(hex: "9a9690"))
                Text(sub).font(.system(size: 10, design: .monospaced)).foregroundColor(Color(hex: "5a5856"))
            }.frame(width: 120, alignment: .leading)
            Slider(value: $value, in: 0...100).accentColor(Color(hex: "c8b89a"))
            Text(display(value)).font(.system(size: 10, design: .monospaced)).foregroundColor(Color(hex: "5a5856")).frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(hex: "161616"))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        .cornerRadius(8)
    }
}

struct EffectSectionsView: View {
    @ObservedObject var engine: VinylEngine
    @State private var open: Set<String> = []
    var body: some View {
        VStack(spacing: 6) {
            EffectSection(title: "playback mechanics", badge: "5 controls", id: "playback", open: $open) {
                EffectSlider(label: "wow depth", sub: "slow pitch drift", info: "Slow pitch drift from the motor spinning at uneven speed. Speeds up and slows down about once every 2 seconds.", value: Binding(get: { engine.params.wowDepth }, set: { engine.params.wowDepth=$0; engine.updateVinylParams() }))
                EffectSlider(label: "flutter", sub: "fast shimmer ~8hz", info: "Fast pitch shimmer around 8Hz from bearing wobble. Sounds like a rapid tremolo on sustained notes.", value: Binding(get: { engine.params.flutter }, set: { engine.params.flutter=$0; engine.updateVinylParams() }))
                EffectSlider(label: "warp wow", sub: "warped record ~0.3hz", info: "Very slow pitch cycle (~0.3Hz) from a physically warped record. One long rise and fall per revolution.", value: Binding(get: { engine.params.warpWow }, set: { engine.params.warpWow=$0; engine.updateVinylParams() }))
                EffectSlider(label: "speed drift", sub: "motor creep over time", info: "Gradual motor speed creep over a session. Pitch slowly wanders flat then corrects.", value: Binding(get: { engine.params.speedDrift }, set: { engine.params.speedDrift=$0; engine.updateVinylParams() }))
                EffectSlider(label: "tracking weight", sub: "0=light / 100=heavy dist", info: "Tracking weight. Low = stylus skipping. High = heavy pressure causing groove distortion.", value: Binding(get: { engine.params.trackingWeight }, set: { engine.params.trackingWeight=$0; engine.updateVinylParams() }))
            }
            EffectSection(title: "noise floor", badge: "4 controls", id: "noise", open: $open) {
                EffectSlider(label: "crackle", sub: "dust & scratches", info: "Random noise bursts from dust and groove scratches. Controls both volume and frequency of pops. Each pop is unique and probabilistic.", value: Binding(get: { engine.params.crackle }, set: { engine.params.crackle=$0; engine.updateNoiseParams(); engine.scheduleCrackleUpdate() }))
                EffectSlider(label: "hiss", sub: "phono stage noise", info: "Broadband high-frequency noise from the phono preamp and cartridge. Always present beneath the music.", value: Binding(get: { engine.params.hiss }, set: { engine.params.hiss=$0; engine.updateNoiseParams() }))
                EffectSlider(label: "rumble", sub: "motor & bearing", info: "Very low frequency vibration (~25Hz) from the motor and bearing transferring through the platter.", value: Binding(get: { engine.params.rumble }, set: { engine.params.rumble=$0; engine.updateNoiseParams() }))
                EffectSlider(label: "pressed noise", sub: "manufacturing haze", info: "Mid-frequency haze baked into the vinyl during manufacturing. Never cleans off.", value: Binding(get: { engine.params.pressedNoise }, set: { engine.params.pressedNoise=$0; engine.updateNoiseParams() }))
            }
            EffectSection(title: "tonal character", badge: "3 controls", id: "tone", open: $open) {
                EffectSlider(label: "hf rolloff", sub: "groove wear / treble loss", info: "Low-pass filter sweeping down with wear. Cymbals go soft, air disappears.", value: Binding(get: { engine.params.hfRolloff }, set: { engine.params.hfRolloff=$0; engine.updateVinylParams() }))
                EffectSlider(label: "riaa variance", sub: "eq curve imperfection", info: "Imperfection in the RIAA equalization curve. Gives each pressing a slightly different tonal character.", value: Binding(get: { engine.params.riaaVariance }, set: { engine.params.riaaVariance=$0; engine.updateVinylParams() }))
                EffectSlider(label: "stereo width", sub: "0=mono / 100=full stereo", info: "Narrows the stereo field toward mono, simulating limited channel separation on vinyl.", value: Binding(get: { engine.params.stereoWidth }, set: { engine.params.stereoWidth=$0; engine.updateVinylParams() }))
            }
            EffectSection(title: "cartridge & room", badge: "3 controls", id: "cart", open: $open) {
                EffectSlider(label: "inner groove dist", sub: "distortion near label", info: "As the stylus tracks toward the label, the groove tightens and high frequencies distort and smear.", value: Binding(get: { engine.params.innerGrooveDistortion }, set: { engine.params.innerGrooveDistortion=$0; engine.updateVinylParams() }))
                EffectSlider(label: "azimuth error", sub: "channel phase mismatch", info: "Cartridge misalignment delays one channel slightly, causing phase smear and a hollow stereo image.", value: Binding(get: { engine.params.azimuthError }, set: { engine.params.azimuthError=$0; engine.updateVinylParams() }))
                EffectSlider(label: "room resonance", sub: "turntable coupling", info: "Narrow resonant peak around 180Hz from the turntable plinth vibrating on the shelf.", value: Binding(get: { engine.params.roomResonance }, set: { engine.params.roomResonance=$0; engine.updateVinylParams() }))
            }
            EffectSection(title: "amplifier", badge: "tube simulation", id: "amp", open: $open) {
                AmpSubLabel("preamp tube")
                EffectSlider(label: "tube warmth", sub: "upper bass fullness", info: "Real tubes clip asymmetrically - harder on one phase than the other. This produces even-order harmonics (octaves) which sound musical and warm rather than harsh.", value: Binding(get: { engine.params.saturation }, set: { engine.params.saturation=$0; engine.updateAmpParams() }))
                EffectSlider(label: "air rolloff", sub: "soft treble above 10kHz", info: "Tube stages saturate more at high frequencies. A pre-emphasis boost before the waveshaper and compensating cut after makes highs distort before lows - the key difference between real tube warmth and digital clipping.", value: Binding(get: { engine.params.hfRolloff }, set: { engine.params.hfRolloff=$0; engine.updateAmpParams() }))
                EffectSlider(label: "microphonics", sub: "tube vibration resonance", info: "Tubes are physically sensitive to vibration. The stylus groove noise mechanically excites the tube, which re-amplifies that resonance back into the signal - a subtle feedback bloom.", value: Binding(get: { engine.params.roomResonance }, set: { engine.params.roomResonance=$0; engine.updateAmpParams() }))
                AmpSubLabel("power amp")
                EffectSlider(label: "output transformer", sub: "low-end bloom", info: "Output transformers saturate on bass transients, creating a low-end bloom and compression around 80-120Hz. Bass notes swell and breathe rather than hitting a hard wall.", value: Binding(get: { engine.params.rumble }, set: { engine.params.rumble=$0; engine.updateAmpParams() }))
                EffectSlider(label: "class A drive", sub: "dynamic compression", info: "Class A amplifiers run at constant high bias, compressing dynamics musically. The amp breathes with the music - loud transients get gently squashed in a way that feels alive.", value: Binding(get: { engine.params.saturation }, set: { engine.params.saturation=$0; engine.updateAmpParams() }))
                EffectSlider(label: "speaker coupling", sub: "impedance interaction", info: "Tube amps have high output impedance, so the speaker impedance curve shapes the frequency response. Certain frequencies get boosted depending on the speaker - the sound of a specific amp/speaker pairing.", value: Binding(get: { engine.params.roomResonance }, set: { engine.params.roomResonance=$0; engine.updateAmpParams() }))
            }
        }
    }
}

struct EffectSection<Content: View>: View {
    let title: String; let badge: String; let id: String
    @Binding var open: Set<String>
    @ViewBuilder let content: Content
    var isOpen: Bool { open.contains(id) }
    var body: some View {
        VStack(spacing: 0) {
            Button(action: { if isOpen { open.remove(id) } else { open.insert(id) } }) {
                HStack {
                    Text(title.uppercased()).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(Color(hex: "9a9690")).kerning(1.0)
                    Spacer()
                    Text(badge).font(.system(size: 10, design: .monospaced)).foregroundColor(Color(hex: "5a5856"))
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.system(size: 10)).foregroundColor(Color(hex: "5a5856"))
                }
                .padding(.horizontal, 14).padding(.vertical, 11).background(Color(hex: "161616"))
            }
            if isOpen {
                VStack(spacing: 8) { content }.padding(10).background(Color(hex: "0e0e0e"))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        .cornerRadius(10)
    }
}

struct EffectSlider: View {
    let label: String; let sub: String; let info: String; @Binding var value: Float
    @State private var showInfo = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.system(size: 11, design: .monospaced)).foregroundColor(Color(hex: "9a9690"))
                    Text(sub).font(.system(size: 9, design: .monospaced)).foregroundColor(Color(hex: "5a5856"))
                }.frame(width: 130, alignment: .leading)
                Slider(value: $value, in: 0...100).accentColor(Color(hex: "c8b89a"))
                Text("\(Int(value))").font(.system(size: 10, design: .monospaced)).foregroundColor(Color(hex: "5a5856")).frame(width: 24, alignment: .trailing)
                Button(action: { showInfo.toggle() }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundColor(showInfo ? Color(hex: "c8b89a") : Color(hex: "3a3836"))
                }
            }
            if showInfo {
                Text(info)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "9a9690"))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "0e0e0e"))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(hex: "c8b89a").opacity(0.2), lineWidth: 0.5))
                    .cornerRadius(5)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showInfo)
    }
}

struct AmpSubLabel: View {
    let text: String; init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 9, design: .monospaced)).foregroundColor(.white).kerning(1.2)
            .padding(.bottom, 2).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(Divider().opacity(0.15), alignment: .bottom)
    }
}

struct SectionLabel: View {
    let text: String; init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 9, design: .monospaced)).foregroundColor(.white).kerning(1.2)
    }
}
