import SwiftUI

struct ContentView: View {
    @StateObject private var engine = VinylEngine()
    @State private var showFilePicker = false

    var body: some View {
        ZStack {
            Color(hex: "0e0e0e").ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    HeaderView()
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 12) {
                            RecordView(engine: engine, onDropTap: { showFilePicker = true })
                            TubeControlsView(engine: engine)
                            BypassButton(engine: engine)
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
