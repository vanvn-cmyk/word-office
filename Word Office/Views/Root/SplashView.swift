import SwiftUI

/// Brief in-app splash shown right after launch, before `RootView` — not the
/// system launch screen itself (that stays the minimal auto-generated one
/// per `INFOPLIST_KEY_UILaunchScreen_Generation`, per Apple HIG guidance
/// against dressing up the true launch screen with marketing copy). This is
/// the common "first screen for ~1s while the app settles" pattern instead,
/// owned entirely by `Word_OfficeApp`.
struct SplashView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.dsBackgroundPrimary
                .ignoresSafeArea()

            // Logo + text truly centered on screen — a single VStack filling the
            // frame (not the old Spacer/Spacer-at-bottom trick, which biased the
            // block upward instead of centering it).
            VStack(spacing: DSSpacing.lg) {
                Image("SplashLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 108, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 24, y: 12)

                VStack(spacing: DSSpacing.xxs) {
                    Text("Word Office")
                        .font(DSFont.title1)
                        .foregroundStyle(Color.dsTextPrimary)

                    Text("From draft to signed — all on your device")
                        .font(DSFont.subheadline)
                        .foregroundStyle(Color.dsTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DSSpacing.xxxl)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Loading indicator, bottom-center — native `ProgressView` rather than
            // a hand-rolled spin animation, so it respects Reduce Motion and
            // Dynamic Type automatically instead of needing that gating by hand.
            ProgressView()
                .controlSize(.large)
                .tint(Color.dsBrandPrimary)
                .padding(.bottom, DSSpacing.xxl)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Word Office — from draft to signed, all on your device")
    }
}

#Preview {
    SplashView()
}
