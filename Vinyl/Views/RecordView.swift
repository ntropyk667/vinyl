import SwiftUI

struct RecordView: View {
    @ObservedObject var engine: VinylEngine
    var onDropTap: () -> Void
    @State private var rotation: Double = 0
    @State private var rotationTimer: Timer?

    var body: some View {
        ZStack {
            RecordCanvas(trackTitle: engine.currentTrack?.title ?? "", wear: engine.params.wear, rotation: rotation)
                .frame(width: 200, height: 200)
            if !engine.isPlaying {
                VStack {
                    Spacer()
                    Text("drop file here")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(hex: "c8b89a").opacity(0.75))
                        .kerning(1.0)
                    Spacer().frame(height: 36)
                }
                .frame(width: 200, height: 200)
                .contentShape(Circle())
                .onTapGesture { onDropTap() }
            }
        }
        .frame(width: 200, height: 200)
        .clipShape(Circle())
        .onReceive(engine.$isPlaying) { playing in
            if playing { startSpinning() } else { stopSpinning() }
        }
    }

    private func startSpinning() {
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            let wobble = engine.isBypassed ? 0.0 : Double.random(in: -0.002...0.002) * Double(engine.params.wear) / 100
            rotation += 0.9 + wobble
            if rotation >= 360 { rotation -= 360 }
        }
    }

    private func stopSpinning() {
        rotationTimer?.invalidate()
        rotationTimer = nil
    }
}

struct RecordCanvas: View {
    let trackTitle: String
    let wear: Float
    let rotation: Double

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let radius = size.width / 2
            ctx.translateBy(x: cx, y: size.height / 2)
            ctx.rotate(by: .degrees(rotation))
            ctx.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: size.width, height: size.height)), with: .color(Color(hex: "141414")))
            for r in stride(from: 28.0, through: 92.0, by: 2.3) {
                let alpha = r.truncatingRemainder(dividingBy: 4.6) < 2.3 ? 0.06 : 0.0
                ctx.stroke(Path(ellipseIn: CGRect(x: -r, y: -r, width: r*2, height: r*2)), with: .color(Color.white.opacity(alpha)), lineWidth: 0.5)
            }
            let lr: CGFloat = 28
            ctx.fill(Path(ellipseIn: CGRect(x: -lr, y: -lr, width: lr*2, height: lr*2)), with: .color(Color(hex: "1e2d4a")))
            if !trackTitle.isEmpty {
                let short = String(trackTitle.prefix(14).uppercased())
                ctx.draw(Text(short).font(.system(size: 5, weight: .medium, design: .monospaced)).foregroundColor(Color(hex: "c8b89a").opacity(0.7)), at: CGPoint(x: 0, y: -4))
                ctx.draw(Text("SIDE A").font(.system(size: 5, design: .monospaced)).foregroundColor(Color(hex: "c8b89a").opacity(0.35)), at: CGPoint(x: 0, y: 4))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: -3, y: -3, width: 6, height: 6)), with: .color(Color(hex: "555555")))
        }
    }
}
