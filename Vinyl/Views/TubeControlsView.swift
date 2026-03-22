import SwiftUI

struct TubeControlsView: View {
    @ObservedObject var engine: VinylEngine
    var body: some View {
        HStack(spacing: 24) {
            TubeButton(label: "preamp", isOn: engine.preampOn) {
                engine.preampOn.toggle(); engine.updateAmpParams()
            }
            TubeButton(label: "power amp", isOn: engine.powerampOn) {
                engine.powerampOn.toggle(); engine.updateAmpParams()
            }
        }
        .padding(.vertical, 8)
    }
}

struct TubeButton: View {
    let label: String; let isOn: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                TubeShape(isOn: isOn).frame(width: 40, height: 75)
                Text(label).font(.system(size: 9, design: .monospaced)).kerning(1.0).textCase(.uppercase)
                    .foregroundColor(isOn ? Color(hex: "c8b89a") : Color(hex: "5a5856"))
                Text(isOn ? "on" : "off").font(.system(size: 9, design: .monospaced)).kerning(1.0).textCase(.uppercase)
                    .foregroundColor(isOn ? Color(hex: "c8b89a") : Color(hex: "5a5856"))
            }
        }.buttonStyle(PlainButtonStyle())
    }
}

struct TubeShape: View {
    let isOn: Bool
    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let stroke = isOn ? Color(hex: "c8b89a") : Color(hex: "5a5856")
            let inner = isOn ? Color(hex: "e8c878") : Color(hex: "5a5856")
            let fil = isOn ? Color(hex: "ffaa44") : Color(hex: "5a5856")
            if isOn {
                ctx.fill(Ellipse().path(in: CGRect(x: cx-18, y: 8, width: 36, height: 52)),
                    with: .color(Color(hex: "ff9922").opacity(0.25)))
            }
            ctx.stroke(RoundedRectangle(cornerRadius: 14).path(in: CGRect(x: cx-14, y: 8, width: 28, height: 48)),
                with: .color(stroke), lineWidth: 1.2)
            ctx.fill(RoundedRectangle(cornerRadius: 1).path(in: CGRect(x: cx-8, y: 14, width: 16, height: 4)),
                with: .color(inner))
            ctx.fill(RoundedRectangle(cornerRadius: 1).path(in: CGRect(x: cx-8, y: 46, width: 16, height: 4)),
                with: .color(inner))
            for y in [22.0, 26.0, 30.0] {
                var p = Path()
                p.move(to: CGPoint(x: cx-10, y: y))
                p.addLine(to: CGPoint(x: cx+10, y: y))
                ctx.stroke(p, with: .color(inner.opacity(0.6)), lineWidth: 0.8)
            }
            var f = Path()
            f.move(to: CGPoint(x: cx-7, y: 38))
            f.addQuadCurve(to: CGPoint(x: cx+7, y: 38), control: CGPoint(x: cx, y: 34))
            f.addQuadCurve(to: CGPoint(x: cx-7, y: 38), control: CGPoint(x: cx, y: 42))
            ctx.stroke(f, with: .color(fil), lineWidth: 1.0)
            if isOn { ctx.stroke(f, with: .color(Color(hex: "ff8800").opacity(0.4)), lineWidth: 3.0) }
            for px in [cx-8, cx, cx+8] {
                var pin = Path()
                pin.move(to: CGPoint(x: px, y: 56))
                pin.addLine(to: CGPoint(x: px, y: 68))
                ctx.stroke(pin, with: .color(stroke), lineWidth: 1.5)
            }
        }
    }
}
