import SwiftUI

extension Notification.Name {
    static let mascotScrollToReviewed = Notification.Name("mascotScrollToReviewed")
    static let mascotScrollToDraft    = Notification.Name("mascotScrollToDraft")
}

// MARK: - Main View

struct MascotAssistantView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: State
    @State private var phase: MascotPhase = .intro
    @State private var floatOffset: CGFloat = 0
    @State private var ringScale: CGFloat = 1.0
    @State private var ringOpacity: Double = 0.35
    @State private var isExiting: Bool = false
    /// Incremented to restart the `.task(id:)` message cycle (e.g. on re-show).
    @State private var cycleID: Int = 0
    /// Persisted: intro greeting shown only on the very first appearance.
    @AppStorage("mascot.hasSeenIntro") private var hasSeenIntro: Bool = false
    /// Session-only: user tapped X to hide the mascot for this launch.
    /// Not persisted — on next launch or when new pending files arrive
    /// the mascot re-surfaces automatically.
    @State private var isDismissed: Bool = false
    @State private var mascotScale: CGFloat = 1.0

    // MARK: Derived
    private var draftCount: Int    { store.draftCount }
    private var reviewedCount: Int { store.reviewedCount }
    private var pendingCount: Int  { draftCount + reviewedCount }

    /// Plain-string version — used only as `animation(value:)` trigger.
    private var currentMessage: String {
        switch phase {
        case .intro:   return "intro"
        case .cycling: return "status-\(draftCount)-\(reviewedCount)"
        case .allDone: return "allDone"
        }
    }

    /// Styled Text — numbers bold + orange, rest normal.
    private var currentText: Text {
        switch phase {
        case .intro:
            return Text("Hi! I'm your task assistant — here to keep your work on track")
                .foregroundStyle(Color.dsTextPrimary)
        case .cycling:
            return statusText
        case .allDone:
            return Text("Great job! You've cleared all your pending work 🎉")
                .foregroundStyle(Color.dsTextPrimary)
        }
    }

    private var statusText: Text {
        let d = draftCount, r = reviewedCount, p = pendingCount
        func num(_ n: Int) -> Text {
            Text("\(n)").bold().foregroundStyle(Color.red)
        }
        func plain(_ s: String) -> Text {
            Text(s).foregroundStyle(Color.dsTextPrimary)
        }
        if d > 0 && r > 0 {
            return plain("You have ") + num(d)
                + plain(" draft\(d == 1 ? "" : "s") and ") + num(r)
                + plain(" file\(r == 1 ? "" : "s") awaiting review")
        } else if d > 0 {
            return plain("You have ") + num(d)
                + plain(" draft file\(d == 1 ? "" : "s") waiting to be finalized")
        } else if r > 0 {
            return num(r) + plain(" file\(r == 1 ? "" : "s") ready for your review")
        } else {
            return plain("You have ") + num(p)
                + plain(" pending file\(p == 1 ? "" : "s")")
        }
    }

    // MARK: Body

    var body: some View {
        if !isDismissed && (pendingCount > 0 || phase == .allDone) {
            // X is inside the Button label so iOS 26's long-press highlight
            // dims it together with the speech bubble and avatar.
            // The inner Button intercepts its own tap → isDismissed fires,
            // outer onTapMascot does not.
            Button {
                onTapMascot()
            } label: {
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .trailing, spacing: 10) {
                        speechBubble
                            .transition(
                                .scale(scale: 0.72, anchor: .bottomTrailing)
                                .combined(with: .opacity)
                            )

                        mascotAvatar
                    }

                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                            isDismissed = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.dsTextSecondary)
                            .frame(width: 20, height: 20)
                            .background(Color.secondary.opacity(0.14), in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(mascotScale, anchor: .bottomTrailing)
            .opacity(isExiting ? 0 : 1)
            .scaleEffect(isExiting ? 0.75 : 1, anchor: .bottomTrailing)
            .animation(
                reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.7),
                value: isExiting
            )
            .task(id: cycleID) { await runMessageCycle() }
            .onAppear {
                // Skip greeting on repeat visits — jump straight to status message
                if hasSeenIntro { phase = .cycling }
                startIdleAnimations()
            }
            .onChange(of: pendingCount) { oldCount, newCount in
                if newCount == 0, phase != .allDone {
                    // All files done → congratulate then hide
                    withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.75)) {
                        phase = .allDone
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(3.5))
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            isExiting = true
                        }
                    }
                } else if newCount > oldCount, isDismissed {
                    // New files added after user dismissed → re-surface
                    phase = hasSeenIntro ? .cycling : .intro
                    withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.7)) {
                        isDismissed = false
                    }
                    cycleID += 1
                }
            }
        }
    }

    // MARK: Speech Bubble

    private var speechBubble: some View {
        VStack(alignment: .trailing, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                if phase != .allDone {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.dsBrandPrimary)
                            .frame(width: 6, height: 6)
                            .opacity(phase == .cycling ? 1 : 0.5)
                        Text("TASK ASSISTANT")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.dsBrandPrimary)
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: phase)
                }

                currentText
                    .font(DSFont.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: currentMessage)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: 175)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 3)
                    .shadow(color: .black.opacity(0.04), radius: 18, x: 0, y: 8)
            }

            // Tail pointing down toward avatar
            MascotBubbleTail()
                .fill(.regularMaterial)
                .frame(width: 15, height: 9)
                .padding(.trailing, 28)
        }
    }

    // MARK: Avatar

    private var mascotAvatar: some View {
        ZStack {
            // Expanding pulse ring
            Circle()
                .strokeBorder(Color.dsBrandPrimary.opacity(ringOpacity), lineWidth: 1.5)
                .frame(width: 84, height: 84)
                .scaleEffect(ringScale)

            // Mascot image
            Image("MascotAssistant")
                .resizable()
                .scaledToFit()
                .frame(width: 74, height: 74)
                .clipShape(Circle())
        }
        .offset(y: floatOffset)
    }

    // MARK: Tap

    private func onTapMascot() {
        // Scroll to the most actionable pending section:
        // Draft takes priority (user must finalize before review); fall back to Reviewed.
        let notification: Notification.Name = draftCount > 0 ? .mascotScrollToDraft : .mascotScrollToReviewed
        NotificationCenter.default.post(name: notification, object: nil)
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
            mascotScale = 0.92
        }
        Task {
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                mascotScale = 1.0
            }
        }
    }

    // MARK: Animations

    private func startIdleAnimations() {
        guard !reduceMotion else { return }
        // Gentle float up-down
        withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
            floatOffset = -7
        }
        // Expanding pulse ring
        withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) {
            ringScale   = 1.4
            ringOpacity = 0
        }
    }

    // MARK: Message Cycle

    private func runMessageCycle() async {
        // First-ever launch: show greeting for 3s, then persist the flag
        if !hasSeenIntro {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, pendingCount > 0 else { return }
            hasSeenIntro = true
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { phase = .cycling }
        }
        // No auto-hide timer — mascot stays visible until user taps X or all
        // pending docs are cleared. The X button is the explicit dismiss affordance.
    }
}

// MARK: - Phase

private enum MascotPhase: Equatable {
    case intro, cycling, allDone
}

// MARK: - Bubble tail shape

private struct MascotBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: 0))
        p.addLine(to: CGPoint(x: rect.width / 2, y: rect.height))
        p.closeSubpath()
        return p
    }
}

// MARK: - Preview

#Preview {
    let store = LibraryStore()
    return ZStack(alignment: .bottomTrailing) {
        Color.dsBackgroundSecondary.ignoresSafeArea()
        MascotAssistantView()
            .padding(.trailing, 16)
            .padding(.bottom, 120)
    }
    .environment(store)
}
