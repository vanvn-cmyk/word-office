import Foundation

/// Writes a known-good blank PPTX (one empty slide) to `url`.
///
/// The file is embedded as base64 rather than generated from OOXML scratch because
/// ONLYOFFICE's x2t converter requires `docProps/app.xml`, `presProps.xml`,
/// `tableStyles.xml`, and a 9-level `defaultTextStyle` in `presentation.xml`.
/// Omitting any of these causes x2t to "repair" the file and produce unexpected
/// extra slides. The embedded file (Aspose.Slides 19.11, 4:3, 1 slide) is verified
/// to open correctly with ONLYOFFICE.
enum PPTXCodec {

    static func writeBlank(to url: URL) throws {
        guard let data = Data(base64Encoded: blankPPTXBase64, options: .ignoreUnknownCharacters) else {
            throw PPTXCodecError.archiveCreationFailed
        }
        if FileManager.default.fileExists(atPath: url.path) {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".pptx")
            try data.write(to: tmp)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try data.write(to: url)
        }
    }

    // MARK: - Embedded blank PPTX

    // swiftlint:disable line_length
    private static let blankPPTXBase64 =
        "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" +
        "+6LcAusvon5Oem5lVJ7z27vNPZpHpotz5GuB//h/AmW/7kb8I3EMqMKjf3+M6gtQSwMEFAAAAAAA" +
        "0YyeT3PzvA7OCgAAzgoAABcAAABkb2NQcm9wcy90aHVtYm5haWwuanBlZ//Y/+AAEEpGSUYAAQEB" +
        "AGAAYAAA/9sAQwAIBgYHBgUIBwcHCQkICgwUDQwLCwwZEhMPFB0aHx4dGhwcICQuJyAiLCMcHCg3" +
        "KSwwMTQ0NB8nOT04MjwuMzQy/9sAQwEJCQkMCwwYDQ0YMiEcITIyMjIyMjIyMjIyMjIyMjIyMjIy" +
        "MjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy/8AAEQgAwAEAAwEiAAIRAQMRAf/EAB8AAAEF" +
        "AQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFB" +
        "BhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RV" +
        "VldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrC" +
        "w8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAA" +
        "AAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRC" +
        "kaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdo" +
        "aWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT" +
        "1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/aAAwDAQACEQMRAD8A9/ooooAKKKKACiiigAooooAK" +
        "KKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAoo" +
        "ooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiii" +
        "gAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKA" +
        "CiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAK" +
        "KKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKz4tVjkkdWTYqZySwPfHSpzf2/Z8" +
        "5JA+U4JzjGfrSuh8rLNFVYr+CSJHJKlgDgg8ZGaY+pwDGwM3X+EjBAzRdBysu0VVOoWoDbpQNo+b" +
        "g8f5zUn2uDyXl34RDhiQRg07hZk1FVjf2wIBkxkZ+6eOcc+nNNh1GGVASSjFtu0gnncQP5UroLMt" +
        "0UUUxBRRRQAUUUUAFFFFABRRRQAUUUUAFFFIwDKVPQjBoAgivbeZiqSDIGeRjIzjIz1Gam8xME71" +
        "wOpz0ql/Z8rQeQ9wphAVVQR9gQeefTion0cGWVkkRQ44Xy+nIOOvtS1KtE0PPiLFfMXIG489qHmj" +
        "jKhmALEAD61nf2N8m0zKeOSU6kMT69Of0FPj0ny5Y3EqnbszlOfl9Dnge1GoWiaG9B1ZePeofttv" +
        "xl8ZIGCCDycfzqtcaUtxcNIZdqsQSm3r2bv3FRx6YjEATRuoPzfJnPz7sdfTijULRNKSaOKEysw2" +
        "AZzQssbKjBxhxleeoqodPJtI7fziqrIXJVRk8kgc9Ov6VH/ZbLJEwnBER43JzjOcdf6UahZGh5ib" +
        "S29do6nNLvXdt3DdjOM1kQaYxtVZ3iUkK23YCvGT83PPX9KkXSvnRxcAjZtzs5PykcHPTmi7Cy7k" +
        "5t7eCCR2mkMBByucrz6ACqxi04mE7pMxjAXac8EE54znJFSw2PkW8lss8fzZYjZnHQDgnpx+tRf2" +
        "ZviCm6X5gwUBcgZxwOfb9aQ/mSi0s0mWLzXDLHnbu4wvGT7805NNtUAjWRs8nGRk5GPT0qA6QGkf" +
        "E6dCMbOeWDfNzz0xToNPSGaGYXEZCcE7ep54yTx1oC/mOazsZZJomd+OCCcBSRjg+tWfs0BWaIMf" +
        "3j72w3IPH+AqvcaekkkknmxqxfeQyZAG3HPP1NS2tolpuxIrSSABXYc4CgY9+mfxpiZA0NijPGzv" +
        "vyI3J6ksQf1OKhUWxkSRDMIYg2CIXzkk85xjAyasyaZ5kwmaUeZ5iuSE6gY46+q0QaaYEkXzFO9C" +
        "u7Yc8/8AAqVmO67lgXcItlmy+xsBcocn8MZpyXcEn3ZV6bueOM4pklqXsktw65QAZZcg49qpPpoV" +
        "FElzHnbty69fmz3PTt+Ap6iSTNTehIAZcnpzTBcwmR08xcoAWz05zjn8DVBNHA5M4LBkOQmCMEnH" +
        "XvkflTBpGMp9oj3ELgeV2XIz16/N1/xo1C0TUMiDOXXjrzUbXkCxJKXO1/u/KeapDSkjt8NLGWDA" +
        "73TjAAGDz681O9i7WMdqJwFUYY7D8w9OvFGoWRO91DGUDSAbxkd+PX6c0r3MMcqxO4DsCQPoM/0N" +
        "VZ9PedlLTKPl2NtTHy5BwOeDxVie2E00UmQNmcjbnOQR/WjUWgsd1DLE0iSDYvUnjHfvSJeW8jRq" +
        "sgJkztGOuM5/kahs7FrUEGRXDfeBU9AOByTSx2Hli3xICYWZs7fvZz79s0aj0LlFIu4IoYgtjkgY" +
        "BNLTJCiiigAooooAKKKKAGyKXjZQcEggGstLW5jttsdusRQIG2OA0gHX6Z/OtailYadjHSO/+0BH" +
        "aQ7QpZg3yhcnI9zjjjvS20V1cFJGlk8rft4YjKgcH8TWvRRYfMzDZbtZEtyX3MFAUE4A7+1TQ2V1" +
        "G1tuDMkZj+UP0+UhvwzitaiiwczMq8sZrm5lKxhVKEBwRycY57+2Kj/s+4MqOIlXLZAyP3Q3A/07" +
        "etbNFFg5mZlvaXsUkrGSMFyCSRu39cjtjrVY6dcMmfs67snCbhtwVIH5evWtyiiwczM2Wxf9+VUv" +
        "uROrfeYEk9fw46VALC92xn5MwglAW6ktn/AVs0UWQczMeZL5GkJEhRpBja/PJ6DngY78VIsOoboi" +
        "zMemfn4UbiTn1OMCtSiiwczMfyNTELAMchxjL8kc+/07/hVm5s5Lk24dh8qkO+AecDoDV+iiwczM" +
        "WWCe1LRwtIrPIFjOchgVAyfp1zV2aOaO8jmiiMoWIoQXAPUHv9Ku0UWDmMWayu2hliVG2sXAHmDB" +
        "yQQevTHGPxrYUsR8y7Tk8ZzTqKErCbuFFFFMQUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFF" +
        "FFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUU" +
        "UAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQ" +
        "AUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFAB" +
        "RRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFF" +
        "FFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUU" +
        "UAFFFFABRRRQAUUUUAf/2VBLAwQUAAAACADRjJ5POyF06hABAABYBAAAHwAAAHBwdC9fcmVscy9w" +
        "cmVzZW50YXRpb24ueG1sLnJlbHOtlEFOwzAQRa9izZ44KVAQqtsNmy6QEHABk0wSC8e2PG4hZ2PB" +
        "kbgCLqCQVFXEwst59nw/aUb+fP9Ybd46zfboSVkjoMhyYGhKWynTCNiF+uwaGAVpKqmtQQE9EmzW" +
        "qwfUMsQWapUjFjMMCWhDcDecU9liJymzDk08qa3vZIilb7iT5YtskC/yfMn9OAOmmWxbCfDbqgD2" +
        "1Dv8T7ata1XirS13HZpw4glOWlV4Jymgj7HSNxgEjODkRpHFfGD8tNciudeR0S+dtzhPaRFkQ38S" +
        "h+qA5gUuUgo4j3TvrRtZDGjW4jKlxV7h65HFgGYtlkmHEXtHK/Fd/sD5gVyl3YhnjY+h1zhZjAEO" +
        "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" +
        "cHB0L3ByZXNQcm9wcy54bWxQSwECLQAUAAAACADRjJ5PopcW5rsAAAA5AQAALAAAAAAAAAAAAAAA" +
        "AAA3FgAAcHB0L3NsaWRlTGF5b3V0cy9fcmVscy9zbGlkZUxheW91dDEueG1sLnJlbHNQSwECLQAU" +
        "AAAACADRjJ5PlZdfgrcCAADIBwAAIQAAAAAAAAAAAAAAAAA8FwAAcHB0L3NsaWRlTGF5b3V0cy9z" +
        "bGlkZUxheW91dDEueG1sUEsBAi0AFAAAAAgA0YyeTz/WSwXPAAAAwQEAACwAAAAAAAAAAAAAAAAA" +
        "MhoAAHBwdC9zbGlkZU1hc3RlcnMvX3JlbHMvc2xpZGVNYXN0ZXIxLnhtbC5yZWxzUEsBAi0AFAAA" +
        "AAgA0YyeTwA1uMKDBgAABy8AACEAAAAAAAAAAAAAAAAASxsAAHBwdC9zbGlkZU1hc3RlcnMvc2xp" +
        "ZGVNYXN0ZXIxLnhtbFBLAQItABQAAAAIANGMnk+WMFHEuwAAADkBAAAgAAAAAAAAAAAAAAAAAA0i" +
        "AABwcHQvc2xpZGVzL19yZWxzL3NsaWRlMS54bWwucmVsc1BLAQI/ABQAAAAIAECTnk+bKKFdCQMA" +
        "AIUHAAAVACQAAAAAAAAAIAAAAAYjAABwcHQvc2xpZGVzL3NsaWRlMS54bWwKACAAAAAAAAEAGACW" +
        "Akxi4r7VAZYCTGLivtUBvjmt2uG+1QFQSwECLQAUAAAACADRjJ5PviCx2skAAAAGAQAAEwAAAAAA" +
        "AAAAAAAAAABCJgAAcHB0L3RhYmxlU3R5bGVzLnhtbFBLAQItABQAAAAIANGMnk8qafDA/gAAAJAB" +
        "AAARAAAAAAAAAAAAAAAAADwnAABwcHQvdGFncy90YWcxLnhtbFBLAQItABQAAAAIANGMnk/jta50" +
        "4QUAAN4cAAAUAAAAAAAAAAAAAAAAAGkoAABwcHQvdGhlbWUvdGhlbWUxLnhtbFBLAQItABQAAAAI" +
        "ANGMnk+QpecrPAEAAPwCAAARAAAAAAAAAAAAAAAAAHwuAABwcHQvdmlld1Byb3BzLnhtbFBLBQYA" +
        "AAAAEgASABIFAADnLwAAAAA="
    // swiftlint:enable line_length
}

enum PPTXCodecError: LocalizedError {
    case archiveCreationFailed
    var errorDescription: String? { "Failed to create blank presentation file." }
}
