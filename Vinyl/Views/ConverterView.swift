import SwiftUI
import UniformTypeIdentifiers

struct ConverterView: View {
    @ObservedObject var engine: VinylEngine
    @State private var showLoadPicker = false
    @State private var showShareSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusLine
            HStack(spacing: 6) {
                converterButton(label: "load", icon: "doc.badge.plus", enabled: !engine.isConverting && !engine.isPreviewing) {
                    showLoadPicker = true
                }
                converterButton(label: "convert", icon: "waveform.path", enabled: engine.converterSourceLoaded && !engine.isConverting && !engine.isPreviewing) {
                    engine.performOfflineRender()
                }
                converterButton(label: engine.isPreviewing ? "stop" : "preview", icon: engine.isPreviewing ? "stop.fill" : "play.fill", enabled: engine.hasConvertedFile && !engine.isConverting) {
                    if engine.isPreviewing { engine.stopPreview() } else { engine.previewConverted() }
                }
                converterButton(label: "save", icon: "square.and.arrow.up", enabled: engine.hasConvertedFile && !engine.isConverting && !engine.isPreviewing) {
                    showShareSheet = true
                }
            }
            if engine.isConverting {
                convertProgressBar
            }
        }
        .sheet(isPresented: $showLoadPicker) {
            DocumentPickerView { url in
                engine.loadForConversion(url: url)
                showLoadPicker = false
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = engine.convertedFileURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if engine.convertFailed {
            statusText("\(engine.converterSourceName)", instruction: "conversion failed, try again", color: Color(hex: "cc3333"))
        } else if engine.isPreviewing {
            if let url = engine.convertedFileURL {
                statusText(url.lastPathComponent, instruction: "previewing, stop before saving", color: Color(hex: "c8b89a"))
            }
        } else if let url = engine.convertedFileURL {
            statusText(url.lastPathComponent, instruction: "build successful, preview before saving", color: Color(hex: "5a9a78"))
        } else if engine.isConverting {
            statusText(engine.converterSourceName, instruction: "converting...", color: Color(hex: "5a9a78"))
        } else if engine.converterSourceLoaded {
            statusText(engine.converterSourceName, instruction: "loaded, choose preset or customize", color: Color(hex: "9a9690"))
        } else {
            EmptyView()
        }
    }

    private func statusText(_ name: String, instruction: String, color: Color) -> some View {
        (Text(name)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(color)
        + Text("  \(instruction)")
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(Color(hex: "5a5856")))
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func converterButton(label: String, icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 14))
                Text(label).font(.system(size: 9, design: .monospaced))
            }
            .foregroundColor(enabled ? Color(hex: "c8b89a") : Color(hex: "3a3836"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(hex: "161616"))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(enabled ? Color(hex: "c8b89a").opacity(0.3) : Color.white.opacity(0.08), lineWidth: 0.5))
            .cornerRadius(6)
        }
        .disabled(!enabled)
    }

    private var convertProgressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08)).frame(height: 3)
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: "5a9a78"))
                    .frame(width: max(0, engine.convertProgress * geo.size.width), height: 3)
            }
        }
        .frame(height: 6)
        .padding(.top, 2)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
