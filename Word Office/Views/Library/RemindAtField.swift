import SwiftUI

/// In-app reminder field. Reminders are surfaced by filtering the library at open time —
/// no `UNUserNotificationCenter`, no background tasks (product decision, 2026-08-27).
/// Tap opens a date-picker sheet; save propagates through `onChange`.
struct RemindAtField: View {
    let current: Date?
    let onChange: (Date?) -> Void

    @State private var isEditing = false

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            Button {
                isEditing = true
            } label: {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: current == nil ? "bell.badge.plus" : "bell.fill")
                        .foregroundStyle(current == nil ? Color.dsTextTertiary : Color.dsBrandPrimary)
                    if let current {
                        Text(current, format: .dateTime.month().day().hour().minute())
                            .font(DSFont.subheadline)
                            .foregroundStyle(Color.dsTextPrimary)
                    } else {
                        Text("Add reminder")
                            .font(DSFont.subheadline)
                            .foregroundStyle(Color.dsTextSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if current != nil {
                Button {
                    onChange(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.dsTextTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear reminder")
            }
        }
        .sheet(isPresented: $isEditing) {
            RemindEditSheet(initial: current ?? Date().addingTimeInterval(3600)) { newDate in
                onChange(newDate)
            }
        }
    }
}

// MARK: - Edit sheet

private struct RemindEditSheet: View {
    let initial: Date
    let onSave: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Date

    init(initial: Date, onSave: @escaping (Date) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _draft = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            DatePicker(
                "Reminder",
                selection: $draft,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .padding(DSSpacing.md)
            .navigationTitle("Set reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Preview

private struct RemindAtFieldPreview: View {
    @State private var date: Date?

    init(initial: Date? = nil) {
        _date = State(initialValue: initial)
    }

    var body: some View {
        Form {
            RemindAtField(current: date) { date = $0 }
        }
    }
}

#Preview("Empty") {
    RemindAtFieldPreview()
}

#Preview("With reminder") {
    RemindAtFieldPreview(initial: Date().addingTimeInterval(3600))
}
