import SwiftUI

struct FeedbackSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DSToastPresenter.self) private var toastPresenter

    @State private var vm = FeedbackViewModel()
    @State private var step = 0
    @State private var goingForward = true

    private let totalSteps = 5

    private var currentDetent: PresentationDetent {
        switch step {
        case 0: return .height(310)   // stars only
        case 1: return .height(670)   // 8 options + subtitle → ~662pt content
        case 2: return .height(780)   // 10 options + subtitle → ~766pt content; no-scroll on ≥iPhone 15
        case 3: return .height(600)   // 7 options, no subtitle → ~588pt content
        case 4: return .height(670)   // 8 options + subtitle → ~662pt content
        default: return .height(670)
        }
    }

    // Gate each step: must pick at least one option (or a star) to advance.
    private var canAdvance: Bool {
        switch step {
        case 0: return vm.rating > 0
        case 1: return !vm.selectedUseCases.isEmpty
        case 2: return !vm.selectedFrictions.isEmpty
        case 3: return !vm.selectedDocTypes.isEmpty
        case 4: return !vm.selectedMissing.isEmpty
        default: return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            dragPill
            progressBar
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, DSSpacing.xs)

            // ScrollView keeps navBar pinned at the bottom regardless of
            // content height: short steps (7 options) don't leave a gap,
            // tall steps (10 options) scroll without needing a taller detent.
            // `.basedOnSize` suppresses bounce when content fits in one screen.
            ScrollView {
                ZStack(alignment: .topLeading) {
                    switch step {
                    case 0: ratingStep.transition(stepTransition).id(0)
                    case 1: useCaseStep.transition(stepTransition).id(1)
                    case 2: frictionStep.transition(stepTransition).id(2)
                    case 3: docTypeStep.transition(stepTransition).id(3)
                    case 4: missingStep.transition(stepTransition).id(4)
                    default: EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, DSSpacing.md)
                .padding(.bottom, DSSpacing.sm)
                .animation(UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.28), value: step)
            }
            .scrollBounceBehavior(.basedOnSize)

            navBar
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.md)
        }
        .presentationDetents([currentDetent])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color.dsBackgroundElevated)
    }

    // MARK: - Top chrome

    private var dragPill: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 36, height: 4)
            .padding(.top, DSSpacing.sm)
            .padding(.bottom, DSSpacing.md)
    }

    private var progressBar: some View {
        HStack(spacing: DSSpacing.xxs) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Color.dsBrandPrimary : Color.dsBorderDefault)
                    .frame(height: 3)
                    .animation(.easeInOut(duration: 0.25), value: step)
            }
        }
    }

    // MARK: - Steps

    private var ratingStep: some View {
        stepShell(title: "How happy are you\nwith Word Office?", stepNumber: 1) {
            HStack(spacing: DSSpacing.sm) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeOut(duration: 0.15)) {
                            vm.rating = star
                        }
                    } label: {
                        Image(systemName: star <= vm.rating ? "star.fill" : "star")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(star <= vm.rating ? Color.dsPremiumGoldEnd : Color.dsBorderDefault)
                            .scaleEffect(star == vm.rating ? 1.2 : 1.0)
                            .frame(width: 52, height: 52)
                            .contentShape(Rectangle())
                            .animation(.easeOut(duration: 0.15), value: vm.rating)
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Rating")
            .accessibilityValue(vm.rating == 0 ? "No rating selected" : "\(vm.rating) of 5 stars")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: if vm.rating < 5 { vm.rating += 1 }
                case .decrement: if vm.rating > 0 { vm.rating -= 1 }
                @unknown default: break
                }
            }
        }
    }

    private var useCaseStep: some View {
        stepShell(title: "Why did you download\nWord Office?", stepNumber: 2,
                  subtitle: "Select all that apply") {
            optionList(
                FeedbackViewModel.useCaseOptions,
                icons: [
                    "Edit docs on the go":      "pencil",
                    "Sign & fill PDFs":         "signature",
                    "Convert or merge files":   "arrow.triangle.2.circlepath",
                    "Organize my documents":    "folder",
                    "Replace another app":      "arrow.left.arrow.right",
                    "Someone recommended it":   "person.2",
                    "Free / affordable option": "tag",
                    "Just browsing":            "eye"
                ],
                isSelected: { vm.selectedUseCases.contains($0) }
            ) { vm.toggleUseCase($0) }
        }
    }

    private var frictionStep: some View {
        stepShell(title: "What's the last thing\nthat frustrated you?", stepNumber: 3,
                  subtitle: "Select all that apply") {
            optionList(
                FeedbackViewModel.frictionOptions,
                icons: [
                    "File didn't open correctly":    "xmark.circle",
                    "Editing felt clunky":           "hand.thumbsdown",
                    "Lost my edits / no autosave":   "clock.arrow.circlepath",
                    "Couldn't find a feature":       "magnifyingglass",
                    "App was too slow":              "tortoise",
                    "Formatting broke after editing":"textformat",
                    "Couldn't sync with cloud":      "icloud.slash",
                    "Feature I need is paywalled":   "lock",
                    "UI was hard to navigate":       "map",
                    "No templates available":        "square.dashed"
                ],
                isSelected: { vm.selectedFrictions.contains($0) }
            ) { vm.toggleFriction($0) }
        }
    }

    private var docTypeStep: some View {
        stepShell(title: "Which feature matters\nmost to your daily work?", stepNumber: 4) {
            optionList(
                FeedbackViewModel.docTypeOptions,
                icons: [
                    "Word / DOCX editing":  "doc.text",
                    "Excel / spreadsheets": "tablecells",
                    "PowerPoint / slides":  "play.rectangle",
                    "PDF sign & fill":      "signature",
                    "PDF convert & merge":  "doc.on.doc",
                    "OCR & scan docs":      "doc.viewfinder",
                    "Compress files":       "archivebox"
                ],
                isSelected: { vm.selectedDocTypes.contains($0) }
            ) { vm.toggleDocType($0) }
        }
    }

    private var missingStep: some View {
        stepShell(title: "What would make you\nrecommend Word Office?", stepNumber: 5,
                  subtitle: "Select all that apply") {
            optionList(
                FeedbackViewModel.missingOptions,
                icons: [
                    "Works offline perfectly":        "wifi.slash",
                    "Syncs with all my clouds":       "icloud",
                    "Better PDF tools":               "doc.fill",
                    "Much faster performance":        "bolt",
                    "Better collaboration & sharing": "person.2",
                    "Simpler, cleaner UI":            "sparkles",
                    "Auto-save & version history":    "clock.arrow.circlepath",
                    "More templates & styles":        "rectangle.grid.2x2"
                ],
                isSelected: { vm.selectedMissing.contains($0) }
            ) { vm.toggleMissing($0) }
        }
    }

    // MARK: - Navigation bar

    private var navBar: some View {
        HStack(spacing: DSSpacing.sm) {
            if step > 0 {
                Button {
                    goingForward = false
                    withAnimation { step -= 1 }
                } label: {
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Back")
                            .font(DSFont.body)
                    }
                    .foregroundStyle(Color.dsTextSecondary)
                    .frame(minHeight: DSSize.buttonHeight)
                    .padding(.horizontal, DSSpacing.md)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            if step < totalSteps - 1 {
                Button {
                    goingForward = true
                    withAnimation { step += 1 }
                } label: {
                    HStack(spacing: DSSpacing.xxs) {
                        Text("Next")
                            .font(DSFont.body.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(canAdvance ? Color.dsBrandPrimary : Color.dsTextDisabled)
                    .frame(minHeight: DSSize.buttonHeight)
                    .padding(.horizontal, DSSpacing.md)
                }
                .buttonStyle(.plain)
                .disabled(!canAdvance)
            } else {
                Button(action: submitFeedback) {
                    HStack(spacing: DSSpacing.xxs) {
                        Text("Submit")
                            .font(DSFont.body.weight(.semibold))
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(canAdvance ? Color.dsBrandPrimary : Color.dsTextDisabled)
                    .frame(minHeight: DSSize.buttonHeight)
                    .padding(.horizontal, DSSpacing.md)
                }
                .buttonStyle(.plain)
                .disabled(!canAdvance)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func stepShell<Content: View>(
        title: String,
        stepNumber: Int,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text("Step \(stepNumber) of \(totalSteps)")
                    .font(DSFont.caption)
                    .foregroundStyle(Color.dsTextTertiary)
                Text(title)
                    .font(DSFont.title2)
                    .foregroundStyle(Color.dsTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(DSFont.subheadline)
                        .foregroundStyle(Color.dsTextSecondary)
                        .padding(.top, 2)
                }
            }
            content()
        }
    }

    @ViewBuilder
    private func optionList(
        _ options: [String],
        icons: [String: String] = [:],
        isSelected: @escaping (String) -> Bool,
        onTap: @escaping (String) -> Void
    ) -> some View {
        VStack(spacing: DSSpacing.xs) {
            ForEach(options, id: \.self) { option in
                SurveyOptionRow(
                    title: option,
                    icon: icons[option],
                    isSelected: isSelected(option),
                    action: { onTap(option) }
                )
            }
        }
    }

    private var stepTransition: AnyTransition {
        let insert: Edge = goingForward ? .trailing : .leading
        let remove: Edge = goingForward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insert).combined(with: .opacity),
            removal: .move(edge: remove).combined(with: .opacity)
        )
    }

    private func submitFeedback() {
        vm.submit()
        dismiss()
        toastPresenter.show(.success, title: "Thanks for your feedback!")
    }
}

// MARK: - Option row

private struct SurveyOptionRow: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(isSelected ? Color.dsBrandPrimary : Color.dsTextSecondary)
                        .frame(width: 20)
                }

                Text(title)
                    .font(DSFont.body)
                    .foregroundStyle(Color.dsTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    Circle()
                        .fill(isSelected ? Color.dsBrandPrimary : Color.clear)
                    Circle()
                        .strokeBorder(isSelected ? Color.dsBrandPrimary : Color.dsBorderDefault,
                                      lineWidth: 1.5)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.dsTextOnBrand)
                    }
                }
                .frame(width: 22, height: 22)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, 11)
            .background(
                isSelected ? Color.dsBrandPrimarySubtle : Color.dsBackgroundElevated,
                in: RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.dsBrandBorder : Color.dsBorderDefault,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            FeedbackSheetView()
                .environment(DSToastPresenter())
        }
}
