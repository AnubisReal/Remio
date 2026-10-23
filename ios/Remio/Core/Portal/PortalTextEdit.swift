import Foundation

/// Changes only the locally typed tail; never clears or replaces an unknown remote prefix.
struct PortalTextEdit: Sendable, Equatable {
    let previous: String
    let next: String

    private var sharedPrefixCount: Int {
        zip(previous, next).prefix { pair in String(pair.0).utf16.elementsEqual(String(pair.1).utf16) }.count
    }

    // Immortal's backspace drops one Kotlin Char (UTF-16 unit), not a Swift Character.
    var deletedUTF16Count: Int { previous.dropFirst(sharedPrefixCount).utf16.count }
    var appendedText: String { String(next.dropFirst(sharedPrefixCount)) }
    var isEmpty: Bool { previous.utf16.elementsEqual(next.utf16) }

    func validate() throws {
        guard previous.utf8.count <= 8192, next.utf8.count <= 8192,
              deletedUTF16Count <= 256 else { throw PortalError.oversizedResponse }
    }
}
