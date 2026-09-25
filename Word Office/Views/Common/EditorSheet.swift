import SwiftUI

extension Notification.Name {
    static let editorSaveRequested = Notification.Name("editorSaveRequested")
    /// Posted by the Done button in OfficeEditorView after the save delay.
    /// EditorSheet listens and calls onDone + dismiss — only this path sets .done.
    /// The ✕ button path (closeEditor) does NOT call onDone.
    static let editorDoneRequested = Notification.Name("editorDoneRequested")
}

/// Full-screen cover wrapper for `EditorPlaceholderView`.
///
/// Owns dismiss so the Done button closes via `dismiss()` (swiftui-expert-skill
/// convention: "sheets own their actions"). Intercepts dismiss when the document
/// has unsaved changes — shows a destructive confirmation dialog first.
///
/// When the Done button fires for Word/Excel files, shows `EditorStatusPickerSheet`
/// before dismissing so the user can tag the document as Draft or Done.
///
/// Receives dirty state via `EditorDirtyPreferenceKey` which bubbles up through
/// the view hierarchy from `OfficeEditorView` without requiring a direct binding
/// through the intermediate `EditorPlaceholderView`.
///
/// Hosts its own `.toastHost(_:)` overlay so success toasts fired while the
/// cover is up remain visible above the cover's z-order.
struct EditorSheet: View {
    let container: DependencyContainer
    let ref: DocumentRef
    /// Called immediately before dismiss — receives the status the user chose.
    /// Nil when the ✕ path is used (no status recorded).
    var onDone: ((DocumentStatus) -> Void)? = nil
    /// Called (before dismiss) when the user wants to Sign the current PDF.
    var onSign: ((URL) -> Void)? = nil
    /// Called (before dismiss) when the user wants to Print the current PDF.
    var onPrint: ((URL) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(DSToastPresenter.self) private var toaster

    @AppStorage("hasSeenRotateHint") private var hasSeenRotateHint = false

    @State private var isDirty = false
    @State private var showDiscardAlert = false
    @State private var showStatusPicker = false
    @State private var showRotateHint = false

    var body: some View {
        NavigationStack {
            EditorPlaceholderView(container: container, ref: ref)
                .toolbar {
                    // x — plain icon, no extra background (nav bar already provides hit area)
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            if isDirty && ref.kind.isOnlyOfficeEditable {
                                showDiscardAlert = true
                            } else {
                                closeEditor()
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .fontWeight(.light)
                        }
                    }
                    // Sign & Print quick actions — only for PDFs (read-only in editor)
                    if ref.url.pathExtension.lowercased() == "pdf", onSign != nil || onPrint != nil {
                        ToolbarItem(placement: .primaryAction) {
                            HStack(spacing: DSSpacing.xs) {
                                if let onSign {
                                    Button {
                                        onSign(ref.url)
                                        closeEditor()
                                    } label: {
                                        Label("Sign", systemImage: "signature")
                                    }
                                }
                                if let onPrint {
                                    Button {
                                        onPrint(ref.url)
                                        closeEditor()
                                    } label: {
                                        Label("Print", systemImage: "printer")
                                    }
                                }
                            }
                        }
                    }
                }
        }
        // Static — value never changes after presentation so no sheet-presenter
        // reconfiguration stutter when isDirty flips false→true mid-session.
        .interactiveDismissDisabled(ref.kind.isOnlyOfficeEditable)
        .onPreferenceChange(EditorDirtyPreferenceKey.self) { isDirty = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .editorDoneRequested)) { _ in
            if ref.kind.isOnlyOfficeEditable {
                // Show status picker so user can tag Draft or Done before closing.
                showStatusPicker = true
            } else {
                finishEditing(.done)
            }
        }
        .sheet(isPresented: $showStatusPicker) {
            EditorStatusPickerSheet(ref: ref) { status in
                finishEditing(status)
            } onCancel: {
                showStatusPicker = false
            }
            .presentationDetents([.height(330)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(DSRadius.large)
            // Solid background covers the safe-area extension on iPad home-indicator
            // and prevents the system material from bleeding through on large screens.
            .presentationBackground(Color.dsBackgroundPrimary)
        }
        .alert("Discard Changes?", isPresented: $showDiscardAlert) {
            Button("Discard Changes", role: .destructive) { closeEditor() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your unsaved edits will be lost.")
        }
        .overlay {
            if showRotateHint {
                RotateHintOverlay { showRotateHint = false }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: showRotateHint)
        .toastHost(toaster)
        .onAppear {
            OrientationManager.shared.allowAll()
            scheduleRotateHintIfNeeded()
        }
        .onDisappear { OrientationManager.shared.lockToPortrait() }
    }

    private func finishEditing(_ status: DocumentStatus) {
        onDone?(status)
        if ref.kind.isOnlyOfficeEditable {
            // Dismiss the status picker sheet immediately so its slide-out animation
            // completes before the full-screen cover closes — prevents a double-close
            // visual stutter where both the sheet and the editor dismiss at once.
            showStatusPicker = false
            NotificationCenter.default.post(name: .editorSaveRequested, object: nil)
            // Delay editor dismiss until the sheet slide-out finishes (~0.35s spring).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { dismiss() }
        } else {
            dismiss()
        }
    }

    private func closeEditor() {
        dismiss()
    }

    private func scheduleRotateHintIfNeeded() {
        guard !hasSeenRotateHint,
              ref.kind.isOnlyOfficeEditable,
              UIDevice.current.userInterfaceIdiom == .phone
        else { return }
        hasSeenRotateHint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            showRotateHint = true
        }
    }
}

// MARK: - Editor status picker sheet

/// Appears when the user taps Done in any ONLYOFFICE-editable file (Word/Excel/PPT).
/// Lets the user tag the document as Draft or Done before saving and closing,
/// so the Library reflects real workflow state.
private struct EditorStatusPickerSheet: View {
    let ref: DocumentRef
    var onConfirm: (DocumentStatus) -> Void
    var onCancel: () -> Void

    /// Tracks the tapped option so we can show a brief selected state before dismissing.
    @State private var tappedStatus: DocumentStatus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Constrain width on iPad — form sheet is ~540pt wide on 12.9-inch;
        // 420pt keeps the two-card layout tight and centred on any device.
        VStack(spacing: 0) {
            // Header
            VStack(spacing: DSSpacing.xxs) {
                Text("Save & Close")
                    .font(DSFont.headline)
                    .foregroundStyle(Color.dsTextPrimary)
                Text("How far along is this document?")
                    .font(DSFont.footnote)
                    .foregroundStyle(Color.dsTextSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, DSSpacing.md)
            .padding(.bottom, DSSpacing.sm)

            Divider()
                .padding(.horizontal, DSSpacing.md)
                .padding(.bottom, DSSpacing.sm)

            // Status options
            VStack(spacing: DSSpacing.xs) {
                statusButton(.reviewed, label: "Still in progress", subtitle: "I'll come back to edit")
                statusButton(.done,     label: "All done",          subtitle: "No more edits needed")
            }
            .padding(.horizontal, DSSpacing.md)

            // Continue Editing — secondary button with subtle fill; disabled while a status is being confirmed
            Button { onCancel() } label: {
                Text("Continue Editing")
                    .font(DSFont.subheadline.weight(.medium))
                    .foregroundStyle(Color.dsTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Color.dsTextSecondary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
                            .strokeBorder(Color.dsBorderSubtle, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, DSSpacing.sm)
            .padding(.bottom, DSSpacing.md)
            .disabled(tappedStatus != nil)
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        // presentationBackground covers the pull-handle area and safe-area extension;
        // this fill ensures the card corners match during the sheet's slide-in animation.
        .background(Color.dsBackgroundPrimary)
    }

    @ViewBuilder
    private func statusButton(_ status: DocumentStatus, label: String, subtitle: String) -> some View {
        let isSelected = tappedStatus == status
        Button {
            guard tappedStatus == nil else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.75)) {
                tappedStatus = status
            }
            // Dismiss after the selected-state flash so the user sees confirmation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { onConfirm(status) }
        } label: {
            HStack(spacing: DSSpacing.md) {
                // Circular icon badge — solid on selection, light tint otherwise
                Image(systemName: isSelected ? "checkmark.circle.fill" : status.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : status.tintColor)
                    .frame(width: 44, height: 44)
                    .background(
                        isSelected ? status.tintColor : status.tintColor.opacity(0.12),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(label)
                        .font(DSFont.body.weight(.semibold))
                        .foregroundStyle(Color.dsTextPrimary)
                    Text(subtitle)
                        .font(DSFont.caption)
                        .foregroundStyle(Color.dsTextSecondary)
                }

                Spacer(minLength: 0)

                // Checkmark only appears when selected — no chevron (this is a picker, not navigation)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(status.tintColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.md)
            .background(
                isSelected ? status.tintColor.opacity(0.07) : Color.dsBackgroundElevated,
                in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                    .strokeBorder(
                        isSelected ? status.tintColor.opacity(0.45) : Color.dsBorderSubtle.opacity(0.6),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.75), value: isSelected)
        }
        .buttonStyle(StatusPickerBtnStyle())
        .disabled(tappedStatus != nil)
    }
}

// Scale + brightness press animation, same physics as PressableCardButtonStyle
// (which is private to ToolsTabView, so we keep a local copy here).
private struct StatusPickerBtnStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
            .sensoryFeedback(.selection, trigger: configuration.isPressed) { _, isPressed in isPressed }
    }
}
