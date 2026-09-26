import SwiftUI

struct DSShadow {
    let color: Color
    let radius: CGFloat
    let y: CGFloat

    /// File-row card elevation: a crisp contact edge plus a short ambient lift.
    /// Ambient reach (radius + y ≈ 8pt) stays inside the 8pt gap between stacked
    /// rows, so one card's shadow never smears onto the next.
    static let cardContact = DSShadow(color: .black.opacity(0.05), radius: 1.5, y: 1)
    static let cardAmbient = DSShadow(color: .black.opacity(0.05), radius: 6, y: 2)
}

extension View {
    func dsShadow(_ shadow: DSShadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
    }

    func dsCardShadow() -> some View {
        dsShadow(.cardContact).dsShadow(.cardAmbient)
    }
}
