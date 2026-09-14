import SwiftUI

/// Excel (`.xlsx`) mock templates. See `DocumentTemplate.swift` for why this
/// is its own file.
extension TemplateCatalog {
    static let excelTemplates: [DocumentTemplate] = [
        DocumentTemplate(
            id: "xlsx.budgetTracker",
            kind: .xlsx,
            title: "Budget Tracker",
            accentColor: .dsDocumentSpreadsheet,
            thumbnail: .lines(hasAccentTitle: true)
        ),
        DocumentTemplate(
            id: "xlsx.expenseReport",
            kind: .xlsx,
            title: "Expense Report",
            accentColor: .dsStatusSuccess,
            thumbnail: .linesWithHighlight
        ),
        DocumentTemplate(
            id: "xlsx.invoiceTracker",
            kind: .xlsx,
            title: "Invoice Tracker",
            accentColor: .dsStatusWarning,
            thumbnail: .lines(hasAccentTitle: false)
        ),
        DocumentTemplate(
            id: "xlsx.timesheet",
            kind: .xlsx,
            title: "Timesheet",
            accentColor: .dsBrandPrimary,
            thumbnail: .lines(hasAccentTitle: true)
        ),
        DocumentTemplate(
            id: "xlsx.inventoryList",
            kind: .xlsx,
            title: "Inventory List",
            accentColor: .dsStatusError,
            thumbnail: .lines(hasAccentTitle: false)
        ),
        DocumentTemplate(
            id: "xlsx.projectTracker",
            kind: .xlsx,
            title: "Project Tracker",
            accentColor: .dsDocumentPresentation,
            thumbnail: .linesWithHighlight
        ),
        DocumentTemplate(
            id: "xlsx.salesReport",
            kind: .xlsx,
            title: "Sales Report",
            accentColor: .dsPremiumGoldStart,
            thumbnail: .lines(hasAccentTitle: true)
        ),
    ]
}
