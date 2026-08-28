import Foundation

struct DocumentContent: Equatable, Sendable {
    var attributedText: AttributedString
    var kind: DocumentKind

    init(attributedText: AttributedString = AttributedString(""), kind: DocumentKind) {
        self.attributedText = attributedText
        self.kind = kind
    }
}
