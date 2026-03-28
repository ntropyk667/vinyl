import SwiftUI

struct SampleLibraryView: View {
    @ObservedObject var engine: VinylEngine
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("sample library")
            Menu {
                ForEach(SampleTrack.library) { track in
                    let presetName = VinylPreset.all.first(where: { $0.id == track.defaultPresetID })?.name ?? ""
                    Button("\(track.title) — \(track.artist) [\(presetName)]") {
                        engine.loadTrack(track)
                    }
                }
            } label: {
                HStack {
                    Text(menuLabel).font(.system(size: 11, design: .monospaced)).foregroundColor(Color(hex: "e8e6e0"))
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 10)).foregroundColor(Color(hex: "5a5856"))
                }
                .padding(.horizontal, 10).padding(.vertical, 9)
                .background(Color(hex: "161616"))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                .cornerRadius(6)
            }
        }
    }
    private var menuLabel: String {
        guard let t = engine.currentTrack else { return "— select a track —" }
        let p = VinylPreset.all.first(where: { $0.id == t.defaultPresetID })?.name ?? ""
        return "\(t.title) — \(t.artist) [\(p)]"
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
            .frame(maxWidth: .infinity, alignment: .leading)
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
                EffectSlider(label: "wow depth", sub: "slow pitch drift", value: Binding(get: { engine.params.wowDepth }, set: { engine.params.wowDepth=$0; engine.updateVinylParams() }))
                EffectSlider(label: "flutter", sub: "fast shimmer ~8hz", value: Binding(get: { engine.params.flutter }, set: { engine.params.flutter=$0; engine.updateVinylParams() }))
                EffectSlider(label: "warp wow", sub: "warped record ~0.3hz", value: Binding(get: { engine.params.warpWow }, set: { engine.params.warpWow=$0; engine.updateVinylParams() }))
                EffectSlider(label: "speed drift", sub: "motor creep over time", value: Binding(get: { engine.params.speedDrift }, set: { engine.params.speedDrift=$0; engine.updateVinylParams() }))
                EffectSlider(label: "tracking weight", sub: "0=light / 100=heavy dist", value: Binding(get: { engine.params.trackingWeight }, set: { engine.params.trackingWeight=$0; engine.updateVinylParams() }))
            }
            EffectSection(title: "noise floor", badge: "4 controls", id: "noise", open: $open) {
                EffectSlider(label: "crackle", sub: "dust & scratches", value: Binding(get: { engine.params.crackle }, set: { engine.params.crackle=$0; engine.updateNoiseParams() }))
                EffectSlider(label: "hiss", sub: "phono stage noise", value: Binding(get: { engine.params.hiss }, set: { engine.params.hiss=$0; engine.updateNoiseParams() }))
                EffectSlider(label: "rumble", sub: "motor & bearing", value: Binding(get: { engine.params.rumble }, set: { engine.params.rumble=$0; engine.updateNoiseParams() }))
                EffectSlider(label: "pressed noise", sub: "manufacturing haze", value: Binding(get: { engine.params.pressedNoise }, set: { engine.params.pressedNoise=$0; engine.updateNoiseParams() }))
            }
            EffectSection(title: "tonal character", badge: "3 controls", id: "tone", open: $open) {
                EffectSlider(label: "hf rolloff", sub: "groove wear / treble loss", value: Binding(get: { engine.params.hfRolloff }, set: { engine.params.hfRolloff=$0; engine.updateVinylParams() }))
                EffectSlider(label: "riaa variance", sub: "eq curve imperfection", value: Binding(get: { engine.params.riaaVariance }, set: { engine.params.riaaVariance=$0; engine.updateVinylParams() }))
                EffectSlider(label: "stereo width", sub: "0=mono / 100=full stereo", value: Binding(get: { engine.params.stereoWidth }, set: { engine.params.stereoWidth=$0; engine.updateVinylParams() }))
            }
            EffectSection(title: "cartridge & room", badge: "3 controls", id: "cart", open: $open) {
                EffectSlider(label: "inner groove dist", sub: "distortion near label", value: Binding(get: { engine.params.innerGrooveDistortion }, set: { engine.params.innerGrooveDistortion=$0; engine.updateVinylParams() }))
                EffectSlider(label: "azimuth error", sub: "channel phase mismatch", value: Binding(get: { engine.params.azimuthError }, set: { engine.params.azimuthError=$0; engine.updateVinylParams() }))
                EffectSlider(label: "room resonance", sub: "turntable coupling", value: Binding(get: { engine.params.roomResonance }, set: { engine.params.roomResonance=$0; engine.updateVinylParams() }))
            }
            EffectSection(title: "amplifier", badge: "tube simulation", id: "amp", open: $open) {
                AmpSubLabel("preamp tube")
                EffectSlider(label: "tube warmth", sub: "upper bass fullness", value: Binding(get: { engine.params.saturation }, set: { engine.params.saturation=$0; engine.updateAmpParams() }))
                EffectSlider(label: "air rolloff", sub: "soft treble above 10kHz", value: Binding(get: { engine.params.hfRolloff }, set: { engine.params.hfRolloff=$0; engine.updateAmpParams() }))
                EffectSlider(label: "microphonics", sub: "tube vibration resonance", value: Binding(get: { engine.params.roomResonance }, set: { engine.params.roomResonance=$0; engine.updateAmpParams() }))
                AmpSubLabel("power amp")
                EffectSlider(label: "output transformer", sub: "low-end bloom", value: Binding(get: { engine.params.rumble }, set: { engine.params.rumble=$0; engine.updateAmpParams() }))
                EffectSlider(label: "class A drive", sub: "dynamic compression", value: Binding(get: { engine.params.saturation }, set: { engine.params.saturation=$0; engine.updateAmpParams() }))
                EffectSlider(label: "speaker coupling", sub: "impedance interaction", value: Binding(get: { engine.params.roomResonance }, set: { engine.params.roomResonance=$0; engine.updateAmpParams() }))
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
    let label: String; let sub: String; @Binding var value: Float
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 11, design: .monospaced)).foregroundColor(Color(hex: "9a9690"))
                Text(sub).font(.system(size: 9, design: .monospaced)).foregroundColor(Color(hex: "5a5856"))
            }.frame(width: 130, alignment: .leading)
            Slider(value: $value, in: 0...100).accentColor(Color(hex: "c8b89a"))
            Text("\(Int(value))").font(.system(size: 10, design: .monospaced)).foregroundColor(Color(hex: "5a5856")).frame(width: 24, alignment: .trailing)
        }
    }
}

struct AmpSubLabel: View {
    let text: String; init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 9, design: .monospaced)).foregroundColor(Color(hex: "5a5856")).kerning(1.2)
            .padding(.bottom, 2).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(Divider().opacity(0.15), alignment: .bottom)
    }
}

struct SectionLabel: View {
    let text: String; init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 9, design: .monospaced)).foregroundColor(Color(hex: "5a5856")).kerning(1.2)
    }
}
