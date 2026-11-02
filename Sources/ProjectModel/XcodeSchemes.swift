internal import Foundation

/// A shared or user scheme of an Xcode project or workspace: the test targets its test action runs, directly or through
/// its test plans (ADR-0030).
public struct XcodeScheme: Sendable, Hashable, Comparable {
    public let name: String
    /// The `.xcscheme` file.
    public let path: String
    /// The test targets the test action lists and does not skip, by name.
    public let testTargets: [String]
    /// The test plans the test action names, as absolute paths.
    public let testPlans: [String]

    public init(name: String, path: String, testTargets: [String], testPlans: [String]) {
        self.name = name
        self.path = path
        self.testTargets = testTargets
        self.testPlans = testPlans
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { (lhs.name, lhs.path) < (rhs.name, rhs.path) }

    /// Every test target the scheme runs: its own, then those of its test plans that are enabled, without repeats.
    public var allTestTargets: [String] {
        var seen: Set<String> = []
        var targets: [String] = []
        for name in testTargets + testPlans.flatMap({ XcodeSchemeReader.testPlanTargets($0) ?? [] })
        where seen.insert(name).inserted {
            targets.append(name)
        }
        return targets
    }
}

/// Reads `.xcscheme` and `.xctestplan` files as text, never running Xcode.
///
/// A scheme Xcode generates on the fly (no `.xcscheme` on disk) is not seen; nor is a test plan's configuration beyond
/// which targets are enabled.
public enum XcodeSchemeReader {
    /// The schemes of a `.xcodeproj` or `.xcworkspace`: `xcshareddata/xcschemes`, then each user's `xcuserdata`.
    public static func schemes(in container: String) -> [XcodeScheme] {
        var directories = [container + "/xcshareddata/xcschemes"]
        let users = container + "/xcuserdata"
        for user in (try? FileManager.default.contentsOfDirectory(atPath: users)) ?? []
        where user.hasSuffix(".xcuserdatad") {
            directories.append(users + "/" + user + "/xcschemes")
        }
        var schemes: [XcodeScheme] = []
        for directory in directories {
            for file in (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            where file.hasSuffix(".xcscheme") {
                let path = directory + "/" + file
                guard let data = FileManager.default.contents(atPath: path) else { continue }
                schemes.append(
                    scheme(
                        named: String(file.dropLast(".xcscheme".count)),
                        path: path,
                        text: String(decoding: data, as: UTF8.self),
                        containerDirectory: ProjectPaths.parent(container)
                    )
                )
            }
        }
        return schemes.sorted()
    }

    /// A scheme from its XML: the test action's testable references and test plan references.
    static func scheme(named name: String, path: String, text: String, containerDirectory: String) -> XcodeScheme {
        var targets: [String] = []
        var plans: [String] = []
        if let testAction = element("TestAction", in: text) {
            for testable in elements("TestableReference", in: testAction) {
                guard attribute("skipped", in: testable) != "YES",
                    let reference = element("BuildableReference", in: testable),
                    let target = attribute("BlueprintName", in: reference)
                else { continue }
                targets.append(target)
            }
            for plan in elements("TestPlanReference", in: testAction) {
                guard let reference = attribute("reference", in: plan) else { continue }
                // `container:Relative/Path.xctestplan`, relative to the directory holding the project.
                let relative =
                    reference.hasPrefix("container:") ? String(reference.dropFirst("container:".count)) : reference
                plans.append(ProjectPaths.join(containerDirectory, relative))
            }
        }
        return XcodeScheme(name: name, path: path, testTargets: targets, testPlans: plans)
    }

    /// The enabled test targets of a `.xctestplan`, by name; nil when it cannot be read.
    public static func testPlanTargets(_ path: String) -> [String]? {
        guard let data = FileManager.default.contents(atPath: path),
            let plan = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = plan["testTargets"] as? [[String: Any]]
        else { return nil }
        return entries.compactMap { entry in
            guard (entry["enabled"] as? Bool) != false, let target = entry["target"] as? [String: Any] else {
                return nil
            }
            return target["name"] as? String
        }
    }

    // MARK: - A small reader for the scheme format's XML

    /// The text of the first `<name …>…</name>` or `<name …/>` element.
    static func element(_ name: String, in text: String) -> Substring? {
        elements(name, in: text).first
    }

    /// The texts of the `<name …>…</name>` and `<name …/>` elements, outermost first; nested elements of the same name
    /// are inside their parent's text.
    static func elements(_ name: String, in text: Substring) -> [Substring] {
        var found: [Substring] = []
        var cursor = text.startIndex
        while let open = text.range(of: "<" + name, range: cursor..<text.endIndex) {
            // The name must end there: `<TestAction` is not `<TestActionFoo`.
            guard open.upperBound < text.endIndex,
                let following = text[open.upperBound...].first,
                following == " " || following == "\n"
                    || following == "\t" || following == ">" || following == "/"
            else {
                cursor = open.upperBound
                continue
            }
            guard let tagEnd = text.range(of: ">", range: open.upperBound..<text.endIndex) else { break }
            if text[text.index(before: tagEnd.lowerBound)] == "/" {
                found.append(text[open.lowerBound..<tagEnd.upperBound])
                cursor = tagEnd.upperBound
                continue
            }
            guard let close = text.range(of: "</" + name + ">", range: tagEnd.upperBound..<text.endIndex) else { break }
            found.append(text[open.lowerBound..<close.upperBound])
            cursor = close.upperBound
        }
        return found
    }

    static func elements(_ name: String, in text: String) -> [Substring] {
        elements(name, in: text[...])
    }

    static func element(_ name: String, in text: Substring) -> Substring? {
        elements(name, in: text).first
    }

    /// The value of `name = "value"` in the element's opening tag, XML entities for quotes and ampersands decoded.
    static func attribute(_ name: String, in element: Substring) -> String? {
        guard let tagEnd = element.firstIndex(of: ">") else { return nil }
        let tag = element[element.startIndex..<tagEnd]
        var cursor = tag.startIndex
        while let match = tag.range(of: name, range: cursor..<tag.endIndex) {
            cursor = match.upperBound
            // A whole attribute name, preceded by whitespace.
            guard match.lowerBound > tag.startIndex, tag[tag.index(before: match.lowerBound)].isWhitespace else {
                continue
            }
            var rest = tag[match.upperBound...].drop { $0.isWhitespace }
            guard rest.first == "=" else { continue }
            rest = rest.dropFirst().drop { $0.isWhitespace }
            guard rest.first == "\"" else { continue }
            rest = rest.dropFirst()
            guard let end = rest.firstIndex(of: "\"") else { return nil }
            return String(rest[..<end])
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&apos;", with: "'")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&amp;", with: "&")
        }
        return nil
    }
}
