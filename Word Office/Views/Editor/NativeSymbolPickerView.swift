import SwiftUI

struct NativeSymbolPickerView: View {

    let onCommit: (String) -> Void
    let onCancel: () -> Void

    private static let categories: [(name: String, symbols: [String])] = [
        ("Math",       ["≤","≥","≠","≈","∞","∑","√","π","÷","×","±","∂","∫","°","∝","∈","∉","∅","∀","∃"]),
        ("Greek",      ["α","β","γ","δ","ε","ζ","η","θ","λ","μ","ν","ξ","ρ","σ","τ","φ","χ","ψ","ω","Δ","Σ","Ω","Π","Λ"]),
        ("Arrows",     ["→","←","↑","↓","↔","↕","⇒","⇐","⇑","⇓","⇔","↗","↘","↙","↖","⟹","⟸","↺","↻","⟲"]),
        ("Currency",   ["€","£","¥","₹","₽","₩","₪","₺","₫","¢","$","₴","₦","৳","₱","฿","₭","₲","₵","₡"]),
        ("Punctuation",["«","»","\u{201C}","\u{201D}","\u{2018}","\u{2019}","…","—","–","•","§","¶","†","‡","‰","‱","※","·","¬","¦"]),
        ("Marks",      ["©","®","™","℃","℉","№","℅","℞","℗","℘","Å","ℓ","ℏ","℮","℺","⁰","¹","²","³","⁴"]),
    ]

    @State private var selectedCategory = 0

    var body: some View {
        VStack(spacing: 0) {
            dragHandle

            HStack {
                Text("Insert Symbol")
                    .font(.headline)
                    .foregroundStyle(Color.dsTextPrimary)
                Spacer()
                Button("Cancel") { onCancel() }
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            categoryPicker
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            symbolGrid
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .background(Color.dsBackgroundElevated)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Category

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(Self.categories.enumerated()), id: \.offset) { idx, cat in
                    Button(cat.name) { selectedCategory = idx }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selectedCategory == idx ? Color.dsTextOnBrand : Color.dsTextSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(selectedCategory == idx ? Color.accentColor : Color.dsBackgroundTertiary)
                        )
                }
            }
        }
    }

    // MARK: - Grid

    private var symbolGrid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let syms = Self.categories[selectedCategory].symbols
        return LazyVGrid(columns: cols, spacing: 6) {
            ForEach(syms, id: \.self) { sym in
                Button {
                    onCommit(sym)
                } label: {
                    Text(sym)
                        .font(.system(size: 20))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.dsBackgroundTertiary,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Chrome

    private var dragHandle: some View {
        Capsule()
            .fill(Color.dsBorderDefault)
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 16)
    }
}
