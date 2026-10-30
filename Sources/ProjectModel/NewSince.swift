/// `--report-new-since <baseline file>` (ADR-0019, ADR-0028): in a pull request, `--only` reports the changed files. A
/// change that removes the last use of a declaration in an unchanged file leaves a finding there, and the scope hides
/// it. Promoting each out-of-scope finding whose fingerprint the base branch's baseline does not hold reports what the
/// change created and leaves the debt that was already there out of scope. From deadwood's `NewFindings`.
public enum NewSince {
    /// The findings to report and to keep out of scope after promotion, and the fingerprints promoted.
    public struct Promotion<Item> {
        /// The in-scope findings, then the promoted ones, each in input order; the caller sorts as its report does.
        public let reported: [Item]
        public let outOfScope: [Item]
        public let promoted: Set<String>
    }

    /// Moves each finding of `outOfScope` whose fingerprint is not in `baseline` to the reported findings.
    /// - Complexity: O(*n*) in the out-of-scope findings.
    public static func promote<Item>(
        inScope: [Item], outOfScope: [Item], notIn baseline: Set<String>, fingerprint: (Item) -> String
    ) -> Promotion<Item> {
        var reported = inScope
        var kept: [Item] = []
        var promoted: Set<String> = []
        for item in outOfScope {
            let print = fingerprint(item)
            if baseline.contains(print) {
                kept.append(item)
            } else {
                reported.append(item)
                promoted.insert(print)
            }
        }
        return Promotion(reported: reported, outOfScope: kept, promoted: promoted)
    }

    /// Whether `baseline` holds none of the findings' fingerprints, so it may have been written for another corpus.
    /// False when either side is empty: an empty baseline or report cannot be a mismatch. Read before promoting.
    public static func matchesNothing<Item>(
        _ findings: [Item], in baseline: Set<String>, fingerprint: (Item) -> String
    ) -> Bool {
        guard !baseline.isEmpty, !findings.isEmpty else { return false }
        return !findings.contains { baseline.contains(fingerprint($0)) }
    }

    /// The run notes of a promotion, as the report and stderr carry them: how many findings were promoted (counted
    /// after `--baseline`), and a warning when the baseline matched nothing.
    public static func notes(promoted: Int, matchesNothing: Bool, baseline: String) -> [String] {
        var notes: [String] = []
        if promoted > 0 { notes.append("\(promoted) finding(s) outside --only are new since \(baseline)") }
        if matchesNothing {
            notes.append(
                "every out-of-scope finding is new since \(baseline); the baseline may not match this corpus "
                    + "(check --relative-to and the analyzed paths)")
        }
        return notes
    }
}
