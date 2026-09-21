import Foundation
import ZIPFoundation

/// Writes a minimal blank XLSX (one empty Sheet1) using raw OOXML + ZIPFoundation.
/// Mirrors `DOCXCodec`'s approach so the blank spreadsheet is a genuine, openable
/// OOXML package — not a 0-byte stub — before the Artifex SDK arrives.
enum XLSXCodec {

    static func writeBlank(to url: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let xlDir        = tempDir.appendingPathComponent("xl", isDirectory: true)
        let xlRelsDir    = xlDir.appendingPathComponent("_rels", isDirectory: true)
        let sheetsDir    = xlDir.appendingPathComponent("worksheets", isDirectory: true)
        let rootRelsDir  = tempDir.appendingPathComponent("_rels", isDirectory: true)
        for dir in [xlRelsDir, sheetsDir, rootRelsDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try contentTypesXML .write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        try rootRelsXML     .write(to: rootRelsDir.appendingPathComponent(".rels"),             atomically: true, encoding: .utf8)
        try workbookXML     .write(to: xlDir.appendingPathComponent("workbook.xml"),            atomically: true, encoding: .utf8)
        try workbookRelsXML .write(to: xlRelsDir.appendingPathComponent("workbook.xml.rels"),   atomically: true, encoding: .utf8)
        try stylesXML       .write(to: xlDir.appendingPathComponent("styles.xml"),              atomically: true, encoding: .utf8)
        try sheet1XML       .write(to: sheetsDir.appendingPathComponent("sheet1.xml"),          atomically: true, encoding: .utf8)

        let tempZip = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".xlsx")
        guard let archive = try? Archive(url: tempZip, accessMode: .create) else {
            throw XLSXCodecError.archiveCreationFailed
        }
        try archive.addEntry(with: "[Content_Types].xml",          relativeTo: tempDir, compressionMethod: .deflate)
        try archive.addEntry(with: "_rels/.rels",                  relativeTo: tempDir, compressionMethod: .deflate)
        try archive.addEntry(with: "xl/workbook.xml",              relativeTo: tempDir, compressionMethod: .deflate)
        try archive.addEntry(with: "xl/_rels/workbook.xml.rels",   relativeTo: tempDir, compressionMethod: .deflate)
        try archive.addEntry(with: "xl/styles.xml",                relativeTo: tempDir, compressionMethod: .deflate)
        try archive.addEntry(with: "xl/worksheets/sheet1.xml",     relativeTo: tempDir, compressionMethod: .deflate)
        defer { try? FileManager.default.removeItem(at: tempZip) }

        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempZip)
        } else {
            try FileManager.default.moveItem(at: tempZip, to: url)
        }
    }

    // MARK: - OOXML templates

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\
    <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\
    </Types>
    """

    private static let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
    </Relationships>
    """

    private static let workbookXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
    <sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>\
    </workbook>
    """

    private static let workbookRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>\
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
    </Relationships>
    """

    // Minimal styles.xml — required for modern Excel/ONLYOFFICE; defines default font + fills + borders + cell formats.
    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
    <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>\
    <fills count="2">\
    <fill><patternFill patternType="none"/></fill>\
    <fill><patternFill patternType="gray125"/></fill>\
    </fills>\
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
    <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>\
    </styleSheet>
    """

    private static let sheet1XML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData/></worksheet>
    """
}

enum XLSXCodecError: Error {
    case archiveCreationFailed
}
