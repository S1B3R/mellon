import SwiftUI

/// Visual language shared by both apps: night sky and moon-silver, after the ithildin on the
/// Doors of Durin.
enum Theme {
    static let night = Color(red: 0.04, green: 0.06, blue: 0.13)
    static let dusk = Color(red: 0.10, green: 0.14, blue: 0.26)
    static let ithildin = Color(red: 0.74, green: 0.82, blue: 0.97)
    static let starlight = Color(red: 0.95, green: 0.97, blue: 1.0)
    static let mist = Color.white.opacity(0.62)
    static let surface = Color.white.opacity(0.06)
    static let border = Color.white.opacity(0.12)
    static let success = Color(red: 0.45, green: 0.88, blue: 0.68)
    static let warning = Color(red: 0.98, green: 0.78, blue: 0.42)

    static let background = LinearGradient(colors: [dusk, night], startPoint: .top, endPoint: .bottom)

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif) }
}

/// The emblem: a star inside an arch, like the doors of Moria.
struct MellonEmblem: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            DoorArch()
                .stroke(Theme.ithildin.opacity(0.85), style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round))
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.32, weight: .light))
                .foregroundStyle(Theme.starlight)
                .offset(y: -size * 0.08)
        }
        .frame(width: size * 0.72, height: size)
        .shadow(color: Theme.ithildin.opacity(0.55), radius: size * 0.12)
    }
}

struct DoorArch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width / 2
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.minY + radius), radius: radius,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

struct StatusDot: View {
    var color: Color
    var pulsing = false
    @State private var animate = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.6), lineWidth: 2)
                    .scaleEffect(animate ? 2.4 : 1)
                    .opacity(animate ? 0 : 1)
                    .opacity(pulsing ? 1 : 0)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { animate = true }
            }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(Theme.night)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(Theme.ithildin, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .medium))
            .foregroundStyle(Theme.starlight)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
