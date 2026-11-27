internal import Foundation

/// The projects an `.xcworkspace` lists in its `contents.xcworkspacedata`, never running Xcode: the members a
/// workspace scheme can reference, which a directory scan cannot tell apart from unrelated projects beside it.
public enum XcodeWorkspace {
    /// The `.xcodeproj` directories `workspace` lists, absolute and canonical (`.` and `..` resolved), in document
    /// order without repeats; nil when the workspace data cannot be read.
    ///
    /// Locations resolve as Xcode resolves them: `group:` against the enclosing groups (the workspace's directory at
    /// the top), `container:` against the workspace's directory, `absolute:` as is. `self:` (the project embedding the
    /// workspace) and `developer:` (inside Xcode) are not members.
    /// - Complexity: O(*n*) in the file's length.
    public static func projects(workspace: String) -> [String]? {
        guard let data = FileManager.default.contents(atPath: workspace + "/contents.xcworkspacedata") else {
            return nil
        }
        let directory = (workspace as NSString).deletingLastPathComponent
        return projects(xml: String(decoding: data, as: UTF8.self), directory: directory)
    }

    /// The `.xcodeproj` paths `xml` lists, resolved against `directory` (the workspace's parent directory).
    static func projects(xml: String, directory: String) -> [String] {
        var groups: [String] = [directory]
        var found: [String] = []
        var seen: Set<String> = []
        var rest = Substring(xml)
        while let open = rest.firstIndex(of: "<") {
            guard let close = rest[open...].firstIndex(of: ">") else { break }
            let tag = rest[rest.index(after: open)..<close]
            rest = rest[rest.index(after: close)...]
            let name = tag.prefix { !$0.isWhitespace && $0 != "/" && $0 != ">" }
            if tag.hasPrefix("/") {
                if tag.dropFirst().hasPrefix("Group"), groups.count > 1 { groups.removeLast() }
                continue
            }
            guard name == "Group" || name == "FileRef" else { continue }
            let resolved = location(in: tag).flatMap { resolve($0, group: groups[groups.count - 1], root: directory) }
            if name == "Group" {
                // A group without a usable location keeps its parent's base; a self-closing group opens nothing.
                if !tag.hasSuffix("/") { groups.append(resolved ?? groups[groups.count - 1]) }
            } else if let resolved, resolved.hasSuffix(".xcodeproj"), seen.insert(resolved).inserted {
                found.append(resolved)
            }
        }
        return found
    }

    /// The unescaped value of the tag's `location` attribute.
    private static func location(in tag: Substring) -> String? {
        guard let key = tag.firstRange(of: "location") else { return nil }
        var cursor = tag[key.upperBound...].drop { $0.isWhitespace }
        guard cursor.first == "=" else { return nil }
        cursor = cursor.dropFirst().drop { $0.isWhitespace }
        guard let quote = cursor.first, quote == "\"" || quote == "'" else { return nil }
        let value = cursor.dropFirst().prefix { $0 != quote }
        return unescaped(value)
    }

    private static func resolve(_ location: String, group: String, root: String) -> String? {
        guard let colon = location.firstIndex(of: ":") else { return nil }
        let kind = location[..<colon]
        let path = String(location[location.index(after: colon)...])
        // Lexical, as the project reader resolves its paths: `.` and `..` collapsed, links not followed.
        switch kind {
        case "group": return ProjectPaths.join(group, path)
        case "container": return ProjectPaths.join(root, path)
        case "absolute": return ProjectPaths.join("/", path)
        default: return nil
        }
    }

    private static func unescaped(_ text: Substring) -> String {
        guard text.contains("&") else { return String(text) }
        var result = String(text)
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&amp;", "&")] {
            while let range = result.firstRange(of: entity) { result.replaceSubrange(range, with: character) }
        }
        return result
    }
}
