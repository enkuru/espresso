import EspressoKit
import Foundation

let arguments = CommandLine.arguments.dropFirst()

guard arguments.count == 2, let command = arguments.first, let path = arguments.last else {
    FileHandle.standardError.write(Data("usage: espresso-render app-icon <AppIcon.iconset> | previews <dir>\n".utf8))
    exit(2)
}

let folder = URL(fileURLWithPath: path, isDirectory: true)

do {
    try MainActor.assumeIsolated {
        switch command {
        case "app-icon": try Artwork.writeIconSet(to: folder)
        case "previews": try Artwork.writePreviews(to: folder)
        default:
            FileHandle.standardError.write(Data("unknown command \(command)\n".utf8))
            exit(2)
        }
    }
} catch {
    FileHandle.standardError.write(Data("espresso-render: \(error.localizedDescription)\n".utf8))
    exit(1)
}
