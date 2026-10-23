import Foundation
import Testing
@testable import RemioCore

@Test func typingOnlyAppendsNewCharacters() {
    let edit = PortalTextEdit(previous: "hol", next: "hola")
    #expect(edit.deletedUTF16Count == 0)
    #expect(edit.appendedText == "a")
}

@Test func deletingRemovesOnlyTheTail() {
    let edit = PortalTextEdit(previous: "hola", next: "hol")
    #expect(edit.deletedUTF16Count == 1)
    #expect(edit.appendedText.isEmpty)
}

@Test func middleEditsPreserveRemotePrefix() {
    let edit = PortalTextEdit(previous: "hola mundo", next: "hola Mundo")
    #expect(edit.deletedUTF16Count == 5)
    #expect(edit.appendedText == "Mundo")
}

@Test func emojiDeletionUsesImmortalUTF16Units() {
    let edit = PortalTextEdit(previous: "Hola 👩🏽‍💻", next: "Hola ")
    #expect(edit.deletedUTF16Count == "👩🏽‍💻".utf16.count)
    #expect(edit.appendedText.isEmpty)
}

@Test func accentChangesKeepExactUnicodeRepresentation() {
    let edit = PortalTextEdit(previous: "cafe", next: "café")
    #expect(edit.deletedUTF16Count == 1)
    #expect(edit.appendedText == "é")
    let normalized = PortalTextEdit(previous: "é", next: "e\u{301}")
    #expect(!normalized.isEmpty)
    #expect(normalized.deletedUTF16Count == 1)
    #expect(normalized.appendedText.utf16.count == 2)
}

@Test func rejectsUnboundedNativeEdits() {
    #expect(throws: PortalError.oversizedResponse) {
        try PortalTextEdit(previous: "", next: String(repeating: "x", count: 8193)).validate()
    }
    #expect(throws: PortalError.oversizedResponse) {
        try PortalTextEdit(previous: String(repeating: "x", count: 257), next: "").validate()
    }
}
