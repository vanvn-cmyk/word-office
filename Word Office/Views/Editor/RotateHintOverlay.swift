import SwiftUI

/// One-time overlay shown on first open of any Word/Excel/PPT file on iPhone.
/// Hints the user that landscape orientation is available for more editing space.
/// Dismissed by tap or auto-dismissed after 3.5 s.
/// Visibility is controlled by the caller; this view owns only its own fade/animation.
struct RotateHintOverlay: View {
    let onDismiss: () -> Void

    @State private var rotation: Double = 0
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.68)
                .ignoresSafeArea()
                .onTapGesture { triggerDismiss() }

            VStack(spacing: 28) {
                Image(systemName: "iphone")
                    .font(.system(size: 84, weight: .thin))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(rotation))
                    .animation(
                        .spring(response: 0.65, dampingFraction: 0.52).delay(0.4),
                        value: rotation
                    )

                VStack(spacing: 8) {
                    Text("Tip: Go landscape")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("You'll have more room to work with")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.72))
                }

                Text("Tap anywhere to dismiss")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .padding(32)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tip: Turn your phone sideways for more editing space")
        }
        .opacity(opacity)
        .animation(.easeIn(duration: 0.22), value: opacity)
        .onAppear {
            opacity = 1
            rotation = 90
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { triggerDismiss() }
        }
    }

    private func triggerDismiss() {
        opacity = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { onDismiss() }
    }
}

#Preview {
    RotateHintOverlay {}
}
