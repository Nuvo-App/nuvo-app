import SwiftUI

// Standalone SwiftUI reference for a premium light-mode Nuvo-style interface.
// This file is not wired into the Flutter app.

enum PremiumLightTokens {
    static let background = Color(hex: 0xF8F9FA)
    static let surface = Color.white
    static let surfaceWarm = Color(hex: 0xFDFDFB)
    static let accent = Color(hex: 0x3A97FF)
    static let accentSoft = Color(hex: 0xDCEEFF)
    static let textPrimary = Color(hex: 0x111827)
    static let textSecondary = Color(hex: 0x6B7280)
    static let hairline = Color(hex: 0xE8EDF3)
    static let success = Color(hex: 0x14B8A6)

    static let fluidSpring = Animation.spring(
        response: 0.45,
        dampingFraction: 0.75,
        blendDuration: 0
    )
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct PremiumSquircle: ViewModifier {
    var radius: CGFloat = 28
    var fill: Color = PremiumLightTokens.surface
    var shadowOpacity: Double = 0.05

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
                    .shadow(
                        color: Color.black.opacity(shadowOpacity),
                        radius: 22,
                        x: 0,
                        y: 8
                    )
            )
    }
}

extension View {
    func premiumSquircle(
        radius: CGFloat = 28,
        fill: Color = PremiumLightTokens.surface,
        shadowOpacity: Double = 0.05
    ) -> some View {
        modifier(PremiumSquircle(radius: radius, fill: fill, shadowOpacity: shadowOpacity))
    }
}

struct PremiumDashboardView: View {
    @State private var selectedGoal = 0
    @State private var validated = false

    private let goals = [
        GoalSnapshot(title: "Morning run", finishLine: "30 miles", progress: 0.72, crew: ["AS", "MK", "JL"]),
        GoalSnapshot(title: "Study sprint", finishLine: "20 sessions", progress: 0.45, crew: ["NR", "VP"])
    ]

    var body: some View {
        ZStack {
            PremiumLightTokens.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {
                    dashboardHeader

                    GoalHeroWidget(goal: goals[selectedGoal])
                        .animation(PremiumLightTokens.fluidSpring, value: selectedGoal)

                    GoalSwitchRail(
                        goals: goals,
                        selectedGoal: $selectedGoal
                    )

                    HStack(spacing: 14) {
                        ProofPulseWidget(validated: validated) {
                            validated.toggle()
                        }
                        WeeklyFlowWidget()
                    }

                    TheCrewPanelUntouched()
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.light)
    }

    private var dashboardHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Arena")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(PremiumLightTokens.textPrimary)
                Text("One finish line at a time.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(PremiumLightTokens.textSecondary)
            }

            Spacer()

            Button {} label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(PremiumLightTokens.accent))
                    .shadow(color: PremiumLightTokens.accent.opacity(0.28), radius: 18, x: 0, y: 8)
            }
            .buttonStyle(.plain)
        }
    }
}

struct GoalSnapshot: Identifiable {
    let id = UUID()
    let title: String
    let finishLine: String
    let progress: Double
    let crew: [String]
}

struct GoalHeroWidget: View {
    let goal: GoalSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(goal.title)
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .foregroundStyle(PremiumLightTokens.textPrimary)
                    Text("Finish line \(goal.finishLine)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PremiumLightTokens.textSecondary)
                }
                Spacer()
                Text("\(Int(goal.progress * 100))%")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(PremiumLightTokens.accent)
            }

            MountainProgressView(progress: goal.progress)
                .frame(height: 132)

            HStack {
                AvatarStack(initials: goal.crew)
                Spacer()
                Button {} label: {
                    Label("Submit proof", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(PremiumLightTokens.accent)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .premiumSquircle(radius: 32)
    }
}

struct MountainProgressView: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .leading) {
                MountainLine()
                    .stroke(PremiumLightTokens.accentSoft, style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round))

                MountainLine()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(PremiumLightTokens.accent, style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round))
                    .shadow(color: PremiumLightTokens.accent.opacity(0.24), radius: 14, x: 0, y: 6)

                Circle()
                    .fill(PremiumLightTokens.surface)
                    .overlay(Circle().stroke(PremiumLightTokens.accent, lineWidth: 5))
                    .frame(width: 32, height: 32)
                    .position(point(on: size, progress: progress))
            }
        }
        .padding(.vertical, 10)
    }

    private func point(on size: CGSize, progress: Double) -> CGPoint {
        let p = CGFloat(min(max(progress, 0), 1))
        let x = 16 + (size.width - 32) * p
        let wave = sin(p * .pi * 1.6) * 28
        let y = size.height * 0.66 - wave
        return CGPoint(x: x, y: y)
    }
}

struct MountainLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 16, y: rect.maxY * 0.68))
        path.addCurve(
            to: CGPoint(x: rect.midX * 0.92, y: rect.maxY * 0.34),
            control1: CGPoint(x: rect.width * 0.20, y: rect.maxY * 0.74),
            control2: CGPoint(x: rect.width * 0.28, y: rect.maxY * 0.22)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.74, y: rect.maxY * 0.50),
            control1: CGPoint(x: rect.width * 0.54, y: rect.maxY * 0.48),
            control2: CGPoint(x: rect.width * 0.56, y: rect.maxY * 0.72)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - 16, y: rect.maxY * 0.40),
            control1: CGPoint(x: rect.width * 0.84, y: rect.maxY * 0.28),
            control2: CGPoint(x: rect.width * 0.90, y: rect.maxY * 0.42)
        )
        return path
    }
}

struct GoalSwitchRail: View {
    let goals: [GoalSnapshot]
    @Binding var selectedGoal: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(goals.indices, id: \.self) { index in
                Button {
                    withAnimation(PremiumLightTokens.fluidSpring) {
                        selectedGoal = index
                    }
                } label: {
                    Text(goals[index].title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(index == selectedGoal ? .white : PremiumLightTokens.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(index == selectedGoal ? PremiumLightTokens.accent : PremiumLightTokens.surface)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ProofPulseWidget: View {
    let validated: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    Circle()
                        .fill(PremiumLightTokens.accent.opacity(validated ? 0.22 : 0.10))
                        .frame(width: validated ? 76 : 58, height: validated ? 76 : 58)
                        .blur(radius: validated ? 4 : 0)
                    Image(systemName: validated ? "checkmark.seal.fill" : "camera.viewfinder")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(PremiumLightTokens.accent)
                }
                .frame(height: 76)

                VStack(alignment: .leading, spacing: 4) {
                    Text(validated ? "Proof verified" : "AI Motion Proof")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(validated ? "Ready to move the leaderboard." : "Frame the rep path.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PremiumLightTokens.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .premiumSquircle(radius: 26)
        }
        .buttonStyle(.plain)
        .animation(PremiumLightTokens.fluidSpring, value: validated)
    }
}

struct WeeklyFlowWidget: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Progress")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            HStack(alignment: .bottom, spacing: 8) {
                ForEach([0.36, 0.62, 0.44, 0.78, 0.66], id: \.self) { value in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(PremiumLightTokens.accent.opacity(value))
                        .frame(width: 16, height: 74 * value)
                }
            }
            Text("5 moves this week")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PremiumLightTokens.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .premiumSquircle(radius: 26)
    }
}

struct TheCrewPanelUntouched: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The Crew")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(PremiumLightTokens.textPrimary)
            Text("Existing Crew feed/panel stays exactly as implemented.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PremiumLightTokens.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AvatarStack: View {
    let initials: [String]

    var body: some View {
        HStack(spacing: -10) {
            ForEach(initials, id: \.self) { item in
                Text(item)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PremiumLightTokens.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(PremiumLightTokens.background))
                    .overlay(Circle().stroke(PremiumLightTokens.surface, lineWidth: 3))
            }
        }
    }
}

struct AICameraOverlayView: View {
    let isTracking: Bool
    let isValidated: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(PremiumLightTokens.surface.opacity(0.70), lineWidth: 2)
                .padding(26)

            SoftTrackingPath()
                .stroke(
                    isValidated ? PremiumLightTokens.accent : PremiumLightTokens.surface.opacity(0.72),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                )
                .padding(54)
                .shadow(color: PremiumLightTokens.accent.opacity(isValidated ? 0.55 : 0), radius: 22, x: 0, y: 0)

            FocusReticle(validated: isValidated)
                .frame(width: isValidated ? 118 : 92, height: isValidated ? 118 : 92)

            VStack {
                Spacer()
                Label(
                    isValidated ? "AI Motion Proof verified" : isTracking ? "Tracking movement" : "Frame your body",
                    systemImage: isValidated ? "checkmark.circle.fill" : "viewfinder"
                )
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isValidated ? .white : PremiumLightTokens.textPrimary)
                .padding(.horizontal, 16)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isValidated ? PremiumLightTokens.accent : PremiumLightTokens.surface.opacity(0.88))
                )
                .shadow(color: PremiumLightTokens.accent.opacity(isValidated ? 0.35 : 0.08), radius: 18, x: 0, y: 8)
                .padding(.bottom, 34)
            }
        }
        .animation(PremiumLightTokens.fluidSpring, value: isTracking)
        .animation(PremiumLightTokens.fluidSpring, value: isValidated)
    }
}

struct SoftTrackingPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + 12))
        path.addCurve(
            to: CGPoint(x: rect.maxX - 20, y: rect.midY),
            control1: CGPoint(x: rect.maxX - 54, y: rect.minY + 22),
            control2: CGPoint(x: rect.maxX - 6, y: rect.midY - 44)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY - 12),
            control1: CGPoint(x: rect.maxX - 32, y: rect.midY + 50),
            control2: CGPoint(x: rect.midX + 46, y: rect.maxY - 2)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + 20, y: rect.midY),
            control1: CGPoint(x: rect.midX - 44, y: rect.maxY - 20),
            control2: CGPoint(x: rect.minX + 10, y: rect.midY + 42)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + 12),
            control1: CGPoint(x: rect.minX + 34, y: rect.midY - 50),
            control2: CGPoint(x: rect.midX - 52, y: rect.minY + 4)
        )
        return path
    }
}

struct FocusReticle: View {
    let validated: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(PremiumLightTokens.accent.opacity(validated ? 0.22 : 0.12), lineWidth: 18)
                .blur(radius: validated ? 8 : 2)

            ForEach(0..<4) { index in
                Capsule()
                    .fill(validated ? PremiumLightTokens.accent : PremiumLightTokens.surface.opacity(0.88))
                    .frame(width: 34, height: 5)
                    .offset(y: -42)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
        }
    }
}

struct PremiumLightModeEcosystemPreview: View {
    @State private var validated = false

    var body: some View {
        TabView {
            PremiumDashboardView()
                .tabItem { Label("Dashboard", systemImage: "circle.grid.2x2.fill") }

            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0xDDEAF8), Color(hex: 0xF8F9FA)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                AICameraOverlayView(isTracking: true, isValidated: validated)
                    .padding(18)

                VStack {
                    Spacer()
                    Button("Toggle validation") {
                        validated.toggle()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(PremiumLightTokens.surface)
                    )
                    .padding(.bottom, 94)
                }
            }
            .tabItem { Label("AI Proof", systemImage: "camera.aperture") }
        }
        .tint(PremiumLightTokens.accent)
        .preferredColorScheme(.light)
    }
}

#Preview("Premium Light Mode Ecosystem") {
    PremiumLightModeEcosystemPreview()
}
