import SwiftUI

enum AppSection { case converter, library, podcast }

struct ContentView: View {
    @StateObject private var engine = VinylEngine()
    @StateObject private var podcastStorage = PodcastStorageManager()
    @State private var showFilePicker = false
    @State private var showSettings = false
    @State private var expandedSection: AppSection? = nil
    @State private var tabRowHeight: CGFloat = 34

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: "0e0e0e").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        HeaderView(showSettings: $showSettings)
                        if geo.size.width < 600 {
                            portraitContent
                        } else {
                            landscapeContent
                        }
                    }
                }
                .allowsHitTesting(!engine.showSpeedMenu)

                // Speed menu lives outside ScrollView — no gesture conflicts
                // Dismiss layer and positioning handled inside SpeedMenuView
                SpeedMenuView(engine: engine)
            }
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPickerView { url in
                engine.loadFile(url: url)
                showFilePicker = false
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            if let sagan = SampleTrack.library.first(where: { $0.id == "sagan" }) {
                engine.loadTrack(sagan)
            }
        }
    }

    private var isConverterMode: Bool { engine.activeMode == .converter }

    private func sectionTab(_ label: String, section: AppSection) -> some View {
        let isActive = expandedSection == section
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedSection = isActive ? nil : section
            }
        }) {
            HStack(spacing: 4) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .kerning(1.0)
                Spacer()
                Image(systemName: isActive ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(isActive ? Color(hex: "1e1a14") : Color(hex: "161616"))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(
                isActive ? Color(hex: "c8b89a").opacity(0.4) : Color.white.opacity(0.08),
                lineWidth: 0.5))
            .cornerRadius(6)
        }
    }

    // Portrait: transport + converter + library full-width, then tubes/bypass | presets side-by-side
    private var portraitContent: some View {
        VStack(spacing: 10) {
            TransportView(engine: engine)
            // Section tab row
            HStack(spacing: 6) {
                sectionTab("converter", section: .converter)
                sectionTab("library", section: .library)
                sectionTab("podcasts", section: .podcast)
            }
            .background(GeometryReader { geo in
                Color.clear.onAppear { tabRowHeight = geo.size.height }
                              .onChange(of: geo.size.height) { tabRowHeight = $0 }
            })
            .onChange(of: engine.converterSourceLoaded) { loaded in
                if loaded { withAnimation(.easeInOut(duration: 0.2)) { expandedSection = .converter } }
            }
            // Converter and podcasts expand inline — kept in hierarchy always so
            // SwiftUI initializes the views at launch, not on first open. This prevents
            // the first-open CPU spike that causes audio static during playback.
            ConverterView(engine: engine)
                .frame(height: expandedSection == .converter ? nil : 0)
                .opacity(expandedSection == .converter ? 1 : 0)
                .clipped()
            PodcastView(engine: engine, storage: podcastStorage)
                .frame(height: expandedSection == .podcast ? nil : 0)
                .opacity(expandedSection == .podcast ? 1 : 0)
                .clipped()
            // Library overlays content below (just picking a track, no effects needed)
            if expandedSection == .library {
                Color.clear.frame(height: 0)
                    .zIndex(10)
                    .overlay(alignment: .top) {
                        SampleLibraryView(engine: engine, onSelect: {
                            withAnimation(.easeInOut(duration: 0.2)) { expandedSection = nil }
                        }).equatable()
                            .background(Color(hex: "0e0e0e"))
                            .shadow(color: .black.opacity(0.6), radius: 8, y: 4)
                            .offset(y: 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .zIndex(10)
                            .transition(.opacity)
                    }
            }
            // Controls — disabled during preview or when library is open
            Group {
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 8) {
                        TubeControlsView(engine: engine)
                            .disabled(engine.isBypassed)
                            .opacity(engine.isBypassed ? 0.35 : 1.0)
                        portraitBypass
                    }
                    .frame(width: 130)
                    PresetsView(engine: engine)
                        .disabled(engine.isBypassed)
                        .opacity(engine.isBypassed ? 0.35 : 1.0)
                }
                MasterControlsView(engine: engine)
                    .disabled(engine.isBypassed)
                    .opacity(engine.isBypassed ? 0.35 : 1.0)
                EffectSectionsView(engine: engine)
                    .disabled(engine.isBypassed)
                    .opacity(engine.isBypassed ? 0.35 : 1.0)
            }
            .disabled(engine.isPreviewing || expandedSection == .library)
            .opacity(engine.isPreviewing ? 0.4 : expandedSection == .library ? 0.35 : 1.0)
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
                    .foregroundColor(Color(hex: "9a9690"))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(Color(hex: "161616"))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                    .cornerRadius(6)
            }
            HStack(spacing: 5) {
                Circle().fill(engine.isBypassed ? Color(hex: "5a9a78") : Color(hex: "5a9a78")).frame(width: 6, height: 6)
                Text(engine.isBypassed ? "bypassed" : "vinyl on")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "9a9690"))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(Color(hex: "161616"))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            .cornerRadius(6)
            StereoMonoToggle(engine: engine)
            NeedleDropButton(engine: engine)
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
                NeedleDropButton(engine: engine)
            }
            .frame(width: 200)
            .disabled(engine.isPreviewing)
            .opacity(engine.isPreviewing ? 0.4 : 1.0)
            VStack(spacing: 10) {
                TransportView(engine: engine)
                // Converter section
                ConverterView(engine: engine)
                    .disabled(!isConverterMode)
                    .opacity(!isConverterMode ? 0.35 : 1.0)
                    .contentShape(Rectangle())
                    .onTapGesture { if !isConverterMode { engine.switchToConverter() } }
                // Sample library section
                SampleLibraryView(engine: engine, onSelect: {
                            withAnimation(.easeInOut(duration: 0.2)) { expandedSection = nil }
                        }).equatable()
                    .disabled(isConverterMode)
                    .opacity(isConverterMode ? 0.35 : 1.0)
                    .contentShape(Rectangle())
                    .onTapGesture { if isConverterMode { engine.switchToLibrary() } }
                // Podcast section
                PodcastView(engine: engine, storage: podcastStorage)
                // Controls
                Group {
                    PresetsView(engine: engine)
                        .disabled(engine.isBypassed)
                        .opacity(engine.isBypassed ? 0.35 : 1.0)
                    MasterControlsView(engine: engine)
                        .disabled(engine.isBypassed)
                        .opacity(engine.isBypassed ? 0.35 : 1.0)
                    EffectSectionsView(engine: engine)
                        .disabled(engine.isBypassed)
                        .opacity(engine.isBypassed ? 0.35 : 1.0)
                }
                .disabled(engine.isPreviewing)
                .opacity(engine.isPreviewing ? 0.4 : 1.0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 40)
    }
}

struct HeaderView: View {
    @Binding var showSettings: Bool
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            HStack(spacing: 0) {
                Text("V").font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                Text("ynl").font(.system(size: 22, weight: .bold)).foregroundColor(Color(hex: "FF9500"))
            }
            Text("analog emulation").font(.system(size: 11, design: .monospaced)).foregroundColor(Color(hex: "5a5856")).kerning(1.2)
            Spacer()
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape").font(.system(size: 14)).foregroundColor(Color(hex: "5a5856"))
            }
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
                    .foregroundColor(Color(hex: "9a9690"))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color(hex: "161616"))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                    .cornerRadius(6)
            }
            HStack(spacing: 6) {
                Circle().fill(Color(hex: "5a9a78")).frame(width: 6, height: 6)
                Text(engine.isBypassed ? "bypassed" : "vinyl on").font(.system(size: 11, design: .monospaced)).foregroundColor(Color(hex: "9a9690"))
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

struct NeedleDropButton: View {
    @ObservedObject var engine: VinylEngine
    var body: some View {
        Button(action: { engine.cycleNeedleDrop() }) {
            HStack(spacing: 6) {
                Circle()
                    .fill(engine.needleDropMode != .bypass ? Color(hex: "c8b89a") : Color(hex: "5a5856"))
                    .frame(width: 6, height: 6)
                Text("needle drop")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(engine.needleDropMode != .bypass ? Color(hex: "c8b89a") : Color(hex: "5a5856"))
                Spacer()
                Text(engine.needleDropMode.label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(engine.needleDropMode != .bypass ? Color(hex: "c8b89a") : Color(hex: "5a5856"))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(engine.needleDropMode != .bypass ? Color(hex: "1e1a14") : Color(hex: "161616"))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(
                engine.needleDropMode != .bypass ? Color(hex: "c8b89a").opacity(0.4) : Color.white.opacity(0.08),
                lineWidth: 0.5))
            .cornerRadius(6)
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("outputFolder") private var outputFolder: String = ""
    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "0e0e0e").ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("output folder").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(Color(hex: "9a9690"))
                        Text(outputFolder.isEmpty ? "default (share sheet)" : outputFolder)
                            .font(.system(size: 10, design: .monospaced)).foregroundColor(Color(hex: "5a5856"))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "161616"))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                    .cornerRadius(8)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("about").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(Color(hex: "9a9690"))
                        Text("vinyl analog emulation").font(.system(size: 10, design: .monospaced)).foregroundColor(Color(hex: "5a5856"))
                        Text("32-bit float stereo WAV output").font(.system(size: 10, design: .monospaced)).foregroundColor(Color(hex: "5a5856"))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "161616"))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                    .cornerRadius(8)
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color(hex: "c8b89a"))
                }
            }
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
