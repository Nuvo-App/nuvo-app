import SwiftUI

// MARK: - Theme Tokens

private extension Color {
    static let premiumBackground = Color(red: 248 / 255, green: 249 / 255, blue: 250 / 255)
    static let premiumSurface = Color.white
    static let premiumAccent = Color(red: 58 / 255, green: 151 / 255, blue: 255 / 255)
    static let premiumTextPrimary = Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255)
    static let premiumSubtleText = Color(red: 71 / 255, green: 85 / 255, blue: 105 / 255)
    static let premiumOverlay = Color.black.opacity(0.04)
}

private struct PremiumStyle {
    static let shadow = ShadowStyle(color: Color.black.opacity(0.05), radius: 20, x: 0, y: 8)
    static let cornerRadius: CGFloat = 28
    static let accentGradient = LinearGradient(
        gradient: Gradient(colors: [Color.premiumAccent.opacity(0.95), Color.premiumAccent.opacity(0.55)]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

private extension View {
    func premiumSurfaceStyle() -> some View {
        self
            .background(Color.premiumSurface)
            .clipShape(RoundedRectangle(cornerRadius: PremiumStyle.cornerRadius, style: .continuous))
            .shadow(color: PremiumStyle.shadow.color, radius: PremiumStyle.shadow.radius, x: PremiumStyle.shadow.x, y: PremiumStyle.shadow.y)
    }
}

private let premiumSpring = Animation.spring(response: 0.45, dampingFraction: 0.75, blendDuration: 0)

// MARK: - Custom Shapes

private struct GoalMountainShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let baseline = height * 0.84
        let peak = height * 0.18
        let current = baseline - (baseline - peak) * progress

        var path = Path()
        path.move(to: CGPoint(x: 0, y: baseline))
        path.addCurve(
            to: CGPoint(x: width * 0.35, y: baseline * 0.55),
            control1: CGPoint(x: width * 0.18, y: baseline * 0.90),
            control2: CGPoint(x: width * 0.26, y: baseline * 0.60)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.62, y: current),
            control1: CGPoint(x: width * 0.44, y: baseline * 0.34),
            control2: CGPoint(x: width * 0.52, y: current + height * 0.08)
        )
        path.addCurve(
            to: CGPoint(x: width, y: baseline),
            control1: CGPoint(x: width * 0.73, y: current - height * 0.05),
            control2: CGPoint(x: width * 0.86, y: baseline * 0.92)
        )
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
        return path
    }
}

private struct SoftReticle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) * 0.45
        path.addRoundedRect(in: CGRect(x: rect.midX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2), cornerSize: CGSize(width: radius * 0.3, height: radius * 0.3))
        return path
    }
}

// MARK: - Dashboard Widgets

private struct GoalProgressWidget: View {
    var title: String
    var subtitle: String
    var progress: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.premiumTextPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.premiumSubtleText)
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.premiumBackground)
                    .frame(height: 144)

                GoalMountainShape(progress: progress)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.premiumAccent, Color.premiumAccent.opacity(0.34)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 18)
                    .shadow(color: Color.premiumAccent.opacity(0.22), radius: 22, x: 0, y: 10)

                Circle()
                    .fill(Color.white)
                    .frame(width: 42, height: 42)
                    .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 5)
                    .overlay(
                        Circle()
                            .stroke(Color.premiumAccent.opacity(0.25), lineWidth: 2)
                    )
                    .overlay(
                        Text(String(format: "%d%%", Int(progress * 100)))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.premiumTextPrimary)
                    )
                    .offset(x: progress * 210, y: -14)
                    .animation(premiumSpring, value: progress)
            }
            .frame(height: 170)
        }
        .padding(22)
        .premiumSurfaceStyle()
    }
}

private struct MetricTile: View {
    var label: String
    var value: String
    var icon: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.premiumAccent.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.premiumAccent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.premiumTextPrimary)
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.premiumSubtleText)
            }
            Spacer()
        }
        .padding(18)
        .background(Color.premiumBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.02), radius: 12, x: 0, y: 4)
    }
}

private struct ActionWidget: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Focus Rhythm")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.premiumTextPrimary)
                    Text("Set a quick sprint for your most important goal.")
                        .font(.subheadline)
                        .foregroundColor(.premiumSubtleText)
                }
                Spacer()
                Image(systemName: "bolt.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .padding(14)
                    .background(Color.premiumAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            HStack(spacing: 14) {
                Capsule()
                    .fill(Color.premiumAccent.opacity(0.12))
                    .overlay(Text("Launch" ).font(.caption.weight(.semibold)).foregroundColor(.premiumAccent))
                    .frame(height: 44)
                Capsule()
                    .fill(Color.premiumBackground)
                    .overlay(Text("Review steps").font(.caption.weight(.semibold)).foregroundColor(.premiumTextPrimary))
                    .frame(height: 44)
            }
        }
        .padding(22)
        .premiumSurfaceStyle()
    }
}

// MARK: - Main Premium Dashboard

struct PremiumDashboardView: View {
    @State private var currentProgress: CGFloat = 0.72

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                header
                GoalProgressWidget(title: "Goal Journey", subtitle: "Progress across your premium goal map", progress: currentProgress)
                HStack(spacing: 16) {
                    MetricTile(label: "Weekly Wins", value: "8", icon: "star.fill")
                    MetricTile(label: "Milestones", value: "3", icon: "flag.fill")
                }
                ActionWidget()
                MiniProgressRow()
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, 40)
        }
        .background(Color.premiumBackground.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Morning Planning")
                    .font(.largeTitle.weight(.bold))
                    .foregroundColor(.premiumTextPrimary)
                Text("A premium view of what matters today.")
                    .font(.subheadline)
                    .foregroundColor(.premiumSubtleText)
                    .lineLimit(2)
            }
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.premiumSurface)
                    .frame(width: 56, height: 56)
                    .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.premiumAccent)
            }
        }
    }
}

private struct MiniProgressRow: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Today’s cadence")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.premiumTextPrimary)
                Spacer()
            }
            HStack(spacing: 14) {
                MiniProgressBubble(title: "Focus", value: "92%", accent: .blue)
                MiniProgressBubble(title: "Habit", value: "67%", accent: .purple)
                MiniProgressBubble(title: "Energy", value: "81%", accent: .orange)
            }
        }
        .padding(18)
        .premiumSurfaceStyle()
    }
}

private struct MiniProgressBubble: View {
    var title: String
    var value: String
    var accent: Color

    var body: some View {
        VStack(spacing: 10) {
            Circle()
                .trim(from: 0, to: 0.82)
                .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 54, height: 54)
                .rotationEffect(.degrees(-90))
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(.premiumTextPrimary)
            Text(title)
                .font(.caption2)
                .foregroundColor(.premiumSubtleText)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - AI Camera Overlay

struct AICameraOverlayView: View {
    var isGoalValidated: Bool

    var body: some View {
        ZStack {
            Color.clear
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color.premiumBackground.opacity(0.23))
                )
                .blendMode(.overlay)
                .overlay(
                    VStack(spacing: 24) {
                        HStack {
                            Text("Camera Validation")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(.white)
                            Spacer()
                            Label("Live", systemImage: "dot.radiowaves.left.and.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white.opacity(0.92))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                        Spacer()

                        GeometryReader { geometry in
                            let width = geometry.size.width
                            let height = geometry.size.height
                            CameraOverlayPaths(width: width, height: height, isValidated: isGoalValidated)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Spacer()

                        HStack {
                            Label("Goal target aligned", systemImage: "checkmark.seal.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white.opacity(0.95))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.black.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)
                    }
                )
                .overlay(
                    Circle()
                        .stroke(Color.premiumAccent.opacity(isGoalValidated ? 0.72 : 0.30), lineWidth: 2)
                        .frame(width: 118, height: 118)
                        .scaleEffect(isGoalValidated ? 1.12 : 1.0)
                        .opacity(isGoalValidated ? 1 : 0.6)
                        .animation(premiumSpring, value: isGoalValidated)
                )
                .overlay(
                    Circle()
                        .fill(Color.premiumAccent.opacity(0.18))
                        .frame(width: 76, height: 76)
                        .scaleEffect(isGoalValidated ? 1.08 : 1)
                        .opacity(isGoalValidated ? 0.8 : 0.0)
                        .animation(premiumSpring, value: isGoalValidated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                )
        }
        .padding(20)
        .background(Color.black.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 28, x: 0, y: 16)
    }
}

private struct CameraOverlayPaths: View {
    let width: CGFloat
    let height: CGFloat
    let isValidated: Bool

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: width * 0.14, y: height * 0.30))
                path.addQuadCurve(to: CGPoint(x: width * 0.86, y: height * 0.30), control: CGPoint(x: width * 0.50, y: height * 0.14))
                path.addQuadCurve(to: CGPoint(x: width * 0.14, y: height * 0.30), control: CGPoint(x: width * 0.50, y: height * 0.52))
            }
            .stroke(Color.white.opacity(0.42), lineWidth: 2.2)
            .blur(radius: 0.2)

            Path { path in
                path.move(to: CGPoint(x: width * 0.17, y: height * 0.75))
                path.addQuadCurve(to: CGPoint(x: width * 0.83, y: height * 0.73), control: CGPoint(x: width * 0.50, y: height * 0.62))
            }
            .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))

            SoftReticle()
                .stroke(Color.white.opacity(0.88), lineWidth: 1.5)
                .frame(width: width * 0.32, height: width * 0.32)
                .position(x: width * 0.52, y: height * 0.48)

            VStack(spacing: 8) {
                Capsule()
                    .fill(Color.premiumAccent.opacity(0.30))
                    .frame(width: 92, height: 8)
                Capsule()
                    .fill(Color.white.opacity(0.24))
                    .frame(width: 52, height: 5)
            }
            .position(x: width * 0.65, y: height * 0.24)

            if isValidated {
                Group {
                    Circle()
                        .stroke(Color.premiumAccent.opacity(0.18), lineWidth: 6)
                        .frame(width: 130, height: 130)
                    Circle()
                        .stroke(Color.premiumAccent.opacity(0.10), lineWidth: 12)
                        .frame(width: 170, height: 170)
                }
                .animation(premiumSpring, value: isValidated)
            }
        }
    }
}

// MARK: - Preview Container

struct PremiumDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        PremiumDashboardEcosystemPreview()
            .preferredColorScheme(.light)
    }
}

private struct PremiumDashboardEcosystemPreview: View {
    @State private var validated = true

    var body: some View {
        VStack(spacing: 28) {
            PremiumDashboardView()
                .frame(maxHeight: 640)
                .padding(.horizontal, 0)
            AICameraOverlayView(isGoalValidated: validated)
                .frame(height: 340)
                .padding(.horizontal, 24)
        }
        .background(Color.premiumBackground.edgesIgnoringSafeArea(.all))
        .onAppear {
            withAnimation(Animation.spring(response: 0.45, dampingFraction: 0.75, blendDuration: 0).delay(0.3)) {
                validated.toggle()
            }
        }
    }
}
