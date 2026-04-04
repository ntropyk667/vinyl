import SwiftUI

struct TransportView: View {
    @ObservedObject var engine: VinylEngine
    @State private var isSeeking = false
    @State private var seekValue: Double = 0

    /// Needle drop offset in seconds
    private var ndOffset: Double {
        Double(engine.needleDropFrameCount) / engine.sampleRate
    }

    /// Music-relative current time (hides needle drop pre-roll)
    private var musicTime: Double { max(0, engine.currentTime - ndOffset) }

    /// Music-only duration
    private var musicDur: Double { engine.musicDuration }

    var displayTime: Double { isSeeking ? seekValue : musicTime }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(engine.displayTitle)
                    .font(.custom("Georgia", size: 15))
                    .foregroundColor(Color(hex: "e8e6e0"))
                    .lineLimit(1)
                Spacer()
                if engine.isConverting {
                    Text("converting \(Int(engine.convertProgress * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(hex: "5a9a78"))
                } else {
                    Text("\(formatTime(displayTime)) / \(formatTime(musicDur))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(hex: "5a5856"))
                }
            }
            GeometryReader { geo in
                if engine.isConverting {
                    // Green progress bar during conversion
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08)).frame(height: 3)
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: "5a9a78"))
                            .frame(width: max(0, engine.convertProgress * geo.size.width), height: 3)
                    }
                    .frame(height: 18)
                } else {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08)).frame(height: 3)
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: "c8b89a")).frame(width: progress * geo.size.width, height: 3)
                        Circle().fill(Color(hex: "c8b89a")).frame(width: 12, height: 12)
                            .offset(x: max(0, progress * geo.size.width - 6)).opacity(isSeeking ? 1 : 0)
                    }
                    .frame(height: 18).contentShape(Rectangle())
                    .highPriorityGesture(DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            isSeeking = true
                            seekValue = max(0, min(1, val.location.x / geo.size.width)) * musicDur
                        }
                        .onEnded { val in
                            let musicPos = max(0, min(1, val.location.x / geo.size.width)) * musicDur
                            engine.seek(to: musicPos + ndOffset)
                            isSeeking = false
                        })
                }
            }
            .frame(height: 18)
            HStack(spacing: 12) {
                // Skip back: previous episode in podcast mode, restart otherwise
                Button(action: { handlePrev() }) {
                    Image(systemName: "backward.end.fill").font(.system(size: 14))
                        .foregroundColor(prevButtonEnabled ? Color(hex: "9a9690") : Color(hex: "3a3836"))
                        .frame(width: 32, height: 32)
                }
                .disabled(!prevButtonEnabled)
                TransportButton(icon: "gobackward.10", size: 14) { engine.seek(to: max(ndOffset, engine.currentTime - 10)) }
                Button(action: { engine.togglePlayback() }) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.5).frame(width: 38, height: 38)
                        Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14)).foregroundColor(Color(hex: "e8e6e0"))
                            .offset(x: engine.isPlaying ? 0 : 1)
                    }
                }
                TransportButton(icon: "goforward.10", size: 14) { engine.seek(to: min(engine.duration - 0.1, engine.currentTime + 10)) }
                // Skip forward: next episode in podcast mode, next sample track otherwise
                Button(action: { handleNext() }) {
                    Image(systemName: "forward.end.fill").font(.system(size: 14))
                        .foregroundColor(nextButtonEnabled ? Color(hex: "9a9690") : Color(hex: "3a3836"))
                        .frame(width: 32, height: 32)
                }
                .disabled(!nextButtonEnabled)

                // Speed button with overlay menu
                Button(action: { engine.showSpeedMenu.toggle() }) {
                    Text(VinylEngine.speedLabel(engine.playbackSpeed))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(engine.playbackSpeed == 1.0 ? Color(hex: "5a5856") : Color(hex: "c8b89a"))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(engine.playbackSpeed == 1.0 ? Color.clear : Color(hex: "1e1a14"))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(
                            engine.playbackSpeed == 1.0 ? Color.white.opacity(0.12) : Color(hex: "c8b89a").opacity(0.4),
                            lineWidth: 0.5))
                        .cornerRadius(4)
                }
            }
            .frame(maxWidth: .infinity)
            .disabled(engine.isConverting)
            .opacity(engine.isConverting ? 0.4 : 1.0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Color(hex: "161616"))
        )
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        .overlay(alignment: .topTrailing) {
            if engine.showSpeedMenu {
                VStack(spacing: 0) {
                    // Up arrow indicator
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Color(hex: "5a5856"))
                        .frame(height: 14)

                    // Speed list with 1x centered
                    ScrollViewReader { reader in
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(VinylEngine.speedOptions.reversed(), id: \.self) { speed in
                                    Button(action: {
                                        engine.setSpeed(speed)
                                        engine.showSpeedMenu = false
                                    }) {
                                        Text(VinylEngine.speedLabel(speed))
                                            .font(.system(size: 11, weight: engine.playbackSpeed == speed ? .bold : .semibold, design: .monospaced))
                                            .foregroundColor(engine.playbackSpeed == speed ? Color(hex: "c8b89a") : Color(hex: "5a5856"))
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 28)
                                            .background(engine.playbackSpeed == speed ? Color(hex: "1e1a14") : Color.clear)
                                    }
                                    .id(speed)
                                }
                            }
                        }
                        .frame(height: 140)
                        .onChange(of: engine.playbackSpeed) { newSpeed in
                            withAnimation {
                                reader.scrollTo(newSpeed, anchor: .center)
                            }
                        }
                        .onAppear {
                            reader.scrollTo(engine.playbackSpeed, anchor: .center)
                        }
                    }
                    Image(systemName: "chevron.down")
                        .frame(height: 14)
                }
                .frame(width: 56)
                .background(Color(hex: "1a1a1a"))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                .cornerRadius(6)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                .offset(x: -10, y: 0)
            }
        }
        .onTapGesture {
            if engine.showSpeedMenu {
                engine.showSpeedMenu = false
            }
        }
    }

    private var progress: Double {
        guard musicDur > 0 else { return 0 }
        return displayTime / musicDur
    }

    /// Whether the skip-back button should be enabled
    private var prevButtonEnabled: Bool {
        if engine.isPodcastMode { return engine.canPodcastSkipBack }
        return true  // restart always works for non-podcast
    }

    /// Whether the skip-forward button should be enabled
    private var nextButtonEnabled: Bool {
        if engine.isPodcastMode { return engine.canPodcastSkipForward }
        return engine.activeMode == .library  // sample library can skip tracks
    }

    private func handlePrev() {
        if engine.isPodcastMode {
            engine.podcastSkipBack()
        } else {
            engine.restart()
        }
    }

    private func handleNext() {
        if engine.isPodcastMode {
            engine.podcastSkipForward()
            return
        }
        guard engine.activeMode == .library else { return }
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
