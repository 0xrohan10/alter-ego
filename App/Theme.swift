import SwiftUI

enum Theme {
    static let midnight = Color(red: 16/255, green: 29/255, blue: 43/255)
    static let deep = Color(red: 8/255, green: 16/255, blue: 25/255)
    static let cream = Color(red: 244/255, green: 233/255, blue: 210/255)
    static let brass = Color(red: 214/255, green: 184/255, blue: 125/255)
    static let muted = Color(red: 161/255, green: 179/255, blue: 192/255)
    static let crimson = Color(red: 192/255, green: 74/255, blue: 79/255)
    static let line = Color.white.opacity(0.16)
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 21, weight: .semibold))
            .padding(.horizontal, 24).frame(maxWidth: .infinity).frame(height: 68)
            .foregroundStyle(Theme.midnight)
            .background(Theme.cream.opacity(enabled ? 1 : 0.30), in: RoundedRectangle(cornerRadius: 13))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct OrbitalBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Theme.midnight, Theme.deep], startPoint: .topLeading, endPoint: .bottomTrailing)
                Canvas { context, size in
                    let center = CGPoint(x: size.width * 0.89, y: size.height * 0.12)
                    for radius in [120.0, 210.0, 310.0, 440.0] {
                        let rect = CGRect(x: center.x-radius, y: center.y-radius, width: radius*2, height: radius*2)
                        context.stroke(Path(ellipseIn: rect), with: .color(Theme.brass.opacity(0.075)), lineWidth: 1)
                    }
                    for i in 0..<52 {
                        let x = Double((i * 137 + 29) % 997) / 997 * size.width
                        let y = Double((i * 229 + 71) % 983) / 983 * size.height
                        let r = i % 7 == 0 ? 2.0 : 0.85
                        context.fill(Path(ellipseIn: CGRect(x:x,y:y,width:r*2,height:r*2)), with: .color(Theme.brass.opacity(i%7 == 0 ? 0.37 : 0.15)))
                    }
                }.allowsHitTesting(false)
                RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.brass.opacity(0.14), lineWidth: 1).padding(18).allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }.ignoresSafeArea()
    }
}

struct KioskStepIndicator: View {
    let step: Int
    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(["NAME", "FACT", "SELFIE"].enumerated()), id: \.offset) { index, label in
                HStack(spacing: 7) {
                    Text(String(format: "%02d", index + 1)).font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(index == step ? Theme.midnight : Theme.brass)
                        .frame(width: 29, height: 29)
                        .background(index == step ? Theme.brass : Color.clear, in: Circle())
                        .overlay(Circle().stroke(Theme.brass.opacity(0.55), lineWidth: 1))
                    Text(label).font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1)
                        .foregroundStyle(index == step ? Theme.cream : Theme.muted)
                }
                if index < 2 { Rectangle().fill(Theme.line).frame(width: 24, height: 1) }
            }
        }.accessibilityLabel("Step \(step + 1) of 3")
    }
}
