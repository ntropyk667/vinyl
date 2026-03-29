import SwiftUI

struct ContentView: View {
    @StateObject private var engine = VinylEngine()
    @State private var showFilePicker = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: "0e0e0e").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        HeaderView()
                        if geo.size.width < 600 {
                            portraitContent
                        } else {
                            landscapeContent
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPickerView { url in
                engine.loadFile(url: url)
                showFilePicker = false
            }
        }
        .onAppear {
            if let france = SampleTrack.library.first(where: { $0.id == "france" }) {
                engine.loadTrack(france)
            }
        }
    }

    // Portrait: transport + library full-width, then tubes/bypass | presets side-by-side
    private var portraitContent: some View {
        VStack(spacing: 10) {
            TransportView(engine: engine)
            SampleLibraryView(engine: engine)
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 8) {
                    TubeControlsView(engine: engine)
                    portraitBypass
                }
                .frame(width: 130)
                PresetsView(engine: engine)
            }
            MasterControlsView(engine: engine)
            EffectSectionsView(engine: engine)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 40)
    }

    // Compact vertical bypass + mono for the narrow left column in portrait
    private var portraitBypass: some View {
        VStack(spacing: 5) {
            Button(action: { engine.toggleBypass() }) {
                Text(engine.isBypassed ? "enable effects" : "bypass effects")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(engine.isBypassed ? Color(hex: "5a5856") : Color(hex: "9a9690"))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(Color(hex: "161616"))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                    .cornerRadius(6)
            }
            HStack(spacing: 5) {
                Circle().fill(engine.isBypassed ? Color(hex: "5a5856") : Color(hex: "5a9a78")).frame(width: 6, height: 6)
                Text(engine.isBypassed ? "bypassed" : "vinyl on")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "5a5856"))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(Color(hex: "161616"))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            .cornerRadius(6)
            StereoMonoToggle(engine: engine)
        }
    }

    // Landscape / iPad: original side-by-side with record view
    private var landscapeContent: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 12) {
                RecordView(engine: engine, onDropTap: { showFilePicker = true })
                TubeControlsView(engine: engine)
                BypassButton(engine: engine)
                StereoMonoToggle(engine: engine)
            }
            .frame(width: 200)
            VStack(spacing: 10) {
                TransportView(engine: engine)
                SampleLibraryView(engine: engine)
                PresetsView(engine: engine)
                MasterControlsView(engine: engine)
                EffectSectionsView(engine: engine)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 40)
    }
}

struct HeaderView: View {
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text("Vinyl").font(.custom("Georgia", size: 22)).foregroundColor(Color(hex: "e8e6e0"))
            Text("analog emulation").font(.system(size: 11, design: .monospaced)).foregroundColor(Color(hex: "5a5856")).kerning(1.2)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .overlay(Divider().opacity(0.15), alignment: .bottom)
    }
}

struct BypassButton: View {
    @ObservedObject var engine: VinylEngine
    var body: some View {
        HStack(spacing: 8) {
            Button(action: { engine.toggleBypass() }) {
                Text(engine.isBypassed ? "enable effects" : "bypass effects")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(engine.isBypassed ? Color(hex: "5a5856") : Color(hex: "9a9690"))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color(hex: "161616"))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                    .cornerRadius(6)
            }
            HStack(spacing: 6) {
                Circle().fill(engine.isBypassed ? Color(hex: "5a5856") : Color(hex: "5a9a78")).frame(width: 6, height: 6)
                Text(engine.isBypassed ? "bypassed" : "vinyl on").font(.system(size: 11, design: .monospaced)).foregroundColor(Color(hex: "5a5856"))
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color(hex: "161616"))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            .cornerRadius(6)
        }
    }
}

struct StereoMonoToggle: View {
    @ObservedObject var engine: VinylEngine
    var body: some View {
        HStack(spacing: 4) {
            modeButton(label: "stereo", active: !engine.monoMode) { engine.monoMode = false; if engine.isPlaying { engine.seek(to: engine.currentTime) } }
            modeButton(label: "mono",   active:  engine.monoMode) { engine.monoMode = true;  if engine.isPlaying { engine.seek(to: engine.currentTime) } }
        }
    }

    private func modeButton(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(active ? Color(hex: "c8b89a") : Color(hex: "5a5856"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(active ? Color(hex: "1e1a14") : Color(hex: "161616"))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(active ? Color(hex: "c8b89a").opacity(0.4) : Color.white.opacity(0.08), lineWidth: 0.5))
                .cornerRadius(6)
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
