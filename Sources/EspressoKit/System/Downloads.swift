import Foundation

enum Downloads {
    /// Partial-file extensions used by Chrome and Edge, Safari, Firefox, older Edge, and Opera.
    static let partialExtensions: Set<String> = ["crdownload", "download", "part", "partial", "opdownload"]

    static var folder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    static func inProgressCount(in folder: URL = folder) -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter(isInProgress).count
    }

    static func isInProgress(_ name: String) -> Bool {
        partialExtensions.contains((name as NSString).pathExtension.lowercased())
    }
}
