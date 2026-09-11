import SwiftUI

/// Native SwiftUI format panel presented as a bottom sheet while editing.
/// Sends formatting commands back to the ONLYOFFICE inner iframe via `onCommand`.
struct FormatStudioView: View {
    var onCommand: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                paragraphStyleSection
                characterSection
                alignmentSection
                listSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Format")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private var paragraphStyleSection: some View {
        Section("Paragraph Style") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    styleChip("Normal",  cmd: "style:Normal",    font: .body)
                    styleChip("Title",   cmd: "style:Title",     font: .title3.bold())
                    styleChip("H1",      cmd: "style:Heading 1", font: .headline)
                    styleChip("H2",      cmd: "style:Heading 2", font: .subheadline.weight(.semibold))
                    styleChip("H3",      cmd: "style:Heading 3", font: .footnote.weight(.semibold))
                    styleChip("Quote",   cmd: "style:Quote",     font: .body.italic())
                }
                .padding(.vertical, 6)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
    }

    private var characterSection: some View {
        Section("Character") {
            HStack(spacing: 12) {
                iconFormatButton("bold",                 cmd: "bold")
                iconFormatButton("italic",               cmd: "italic")
                iconFormatButton("underline",            cmd: "underline")
                iconFormatButton("strikethrough",        cmd: "strikeout")
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var alignmentSection: some View {
        Section("Alignment") {
            HStack(spacing: 12) {
                iconFormatButton("text.alignleft",   cmd: "align-left")
                iconFormatButton("text.aligncenter", cmd: "align-center")
                iconFormatButton("text.alignright",  cmd: "align-right")
                iconFormatButton("text.justify",     cmd: "align-justify")
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var listSection: some View {
        Section("Lists") {
            HStack(spacing: 12) {
                iconFormatButton("list.bullet",  cmd: "list-bullet")
                iconFormatButton("list.number",  cmd: "list-numbered")
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    private func styleChip(_ label: String, cmd: String, font: Font) -> some View {
        Button {
            onCommand(cmd)
        } label: {
            Text(label)
                .font(font)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func iconFormatButton(_ systemImage: String, cmd: String) -> some View {
        Button {
            onCommand(cmd)
        } label: {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}
