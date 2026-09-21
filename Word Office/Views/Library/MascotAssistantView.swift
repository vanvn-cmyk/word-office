import SwiftUI

// MARK: - Main View

struct MascotAssistantView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: State
    @State private var phase: MascotPhase = .intro
    @State private var floatOffset: CGFloat = 0
    @State private var ringScale: CGFloat = 1.0
    @State private var ringOpacity: Double = 0.55
    @State private var isExiting: Bool = false
    /// Incremented to restart the `.task(id:)` message cycle (e.g. on re-show).
    @State private var cycleID: Int = 0
    /// Persisted: intro greeting shown only on the very first appearance.
    @AppStorage("mascot.hasSeenIntro") private var hasSeenIntro: Bool = false

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
        if pendingCount > 0 || phase == .allDone {
            // ZStack layers the display content (non-interactive) under the
            // dismiss X (interactive). `.allowsHitTesting(false)` on the inner
            // VStack lets taps on the bubble/avatar fall through to library
            // content below — only the X button intercepts touches.
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 10) {
                    speechBubble
                        .transition(
                            .scale(scale: 0.72, anchor: .bottomTrailing)
                            .combined(with: .opacity)
                        )

                    mascotAvatar
                }
                .allowsHitTesting(false)

                // Small dismiss button at the bubble's top-right corner.
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
                        isExiting = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.dsTextSecondary)
                        .frame(width: 20, height: 20)
                        .background(Color.secondary.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .padding(.trailing, 4)
            }
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
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) {
                            isExiting = true
                        }
                    }
                } else if newCount > oldCount, isExiting {
                    // New files added after auto-hide → re-show
                    phase = hasSeenIntro ? .cycling : .intro
                    withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.7)) {
                        isExiting = false
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
            .frame(maxWidth: 210)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.dsBackgroundElevated)
                    .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 3)
                    .shadow(color: .black.opacity(0.04), radius: 18, x: 0, y: 8)
            }

            // Tail pointing down toward avatar
            MascotBubbleTail()
                .fill(Color.dsBackgroundElevated)
                .frame(width: 15, height: 9)
                .padding(.trailing, 28)
        }
    }

    // MARK: Avatar

    private var mascotAvatar: some View {
        ZStack {
            // Expanding pulse ring
            Circle()
                .strokeBorder(Color.dsBrandPrimary.opacity(ringOpacity), lineWidth: 2.5)
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

    // MARK: Animations

    private func startIdleAnimations() {
        guard !reduceMotion else { return }
        // Gentle float up-down
        withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
            floatOffset = -7
        }
        // Expanding pulse ring
        withAnimation(.easeOut(duration: 1.9).repeatForever(autoreverses: false)) {
            ringScale   = 1.7
            ringOpacity = 0
        }
    }

    // MARK: Message Cycle

    private func runMessageCycle() async {
        // First-ever launch: show greeting for 5s, then persist the flag
        if !hasSeenIntro {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, pendingCount > 0 else { return }
            hasSeenIntro = true
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { phase = .cycling }
        }

        // Display the single unified status message for 40s, then auto-hide
        try? await Task.sleep(for: .seconds(40))
        guard !Task.isCancelled, phase == .cycling else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { isExiting = true }
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
