import SwiftUI

struct TransportView: View {
    @ObservedObject var engine: VinylEngine
    @State private var isSeeking = false
    @State private var seekValue: Double = 0

    var displayTime: Double { isSeeking ? seekValue : engine.currentTime }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(engine.currentTrack?.title ?? "no track loaded")
                    .font(.custom("Georgia", size: 15))
                    .foregroundColor(Color(hex: "e8e6e0"))
                    .lineLimit(1)
                Spacer()
                Text("\(formatTime(displayTime)) / \(formatTime(engine.duration))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(hex: "5a5856"))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08)).frame(height: 3)
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: "c8b89a")).frame(width: progress * geo.size.width, height: 3)
                    Circle().fill(Color(hex: "c8b89a")).frame(width: 12, height: 12)
                        .offset(x: max(0, progress * geo.size.width - 6)).opacity(isSeeking ? 1 : 0)
                }
                .frame(height: 18).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        isSeeking = true
                        seekValue = max(0, min(1, val.location.x / geo.size.width)) * engine.duration
                    }
                    .onEnded { val in
                        engine.seek(to: max(0, min(1, val.location.x / geo.size.width)) * engine.duration)
                        isSeeking = false
                    })
            }
            .frame(height: 18)
            HStack(spacing: 12) {
                TransportButton(icon: "backward.end.fill", size: 14) { engine.restart() }
                TransportButton(icon: "backward.fill", size: 14) { handlePrevious() }
                Button(action: { engine.togglePlayback() }) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.5).frame(width: 38, height: 38)
                        Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14)).foregroundColor(Color(hex: "e8e6e0"))
                            .offset(x: engine.isPlaying ? 0 : 1)
                    }
                }
                TransportButton(icon: "forward.fill", size: 14) { handleNext() }
                TransportButton(icon: "repeat", size: 14, isActive: true) {}
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(Color(hex: "161616"))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        .cornerRadius(8)
    }

    private var progress: Double {
        guard engine.duration > 0 else { return 0 }
        return displayTime / engine.duration
    }

    private func handlePrevious() {
        if engine.currentTime > 5 {
            engine.restart()
        } else {
            let idx = SampleTrack.library.firstIndex(where: { $0.id == engine.currentTrack?.id }) ?? 0
            let prev = SampleTrack.library[(idx - 1 + SampleTrack.library.count) % SampleTrack.library.count]
            engine.loadTrack(prev)
        }
    }

    private func handleNext() {
        let idx = SampleTrack.library.firstIndex(where: { $0.id == engine.currentTrack?.id }) ?? 0
        let next = SampleTrack.library[(idx + 1) % SampleTrack.library.count]
        engine.loadTrack(next)
    }

    private func formatTime(_ s: Double) -> String {
        String(format: "%d:%02d", Int(s)/60, Int(s)%60)
    }
}

struct TransportButton: View {
    let icon: String; let size: CGFloat; var isActive: Bool = false; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size))
                .foregroundColor(isActive ? Color(hex: "c8b89a") : Color(hex: "9a9690"))
                .frame(width: 32, height: 32)
        }
    }
}
