import Foundation

/// Line based diff (longest common subsequence) between two texts.
enum TextDiff {
    enum Kind: Equatable {
        case unchanged, added, removed
    }

    struct Line: Identifiable, Equatable {
        let id: Int
        let kind: Kind
        let text: String
        /// 1-based line numbers in the old/new text (nil if the line does not exist there).
        let oldNumber: Int?
        let newNumber: Int?
    }

    /// Above this many cells of the LCS table the diff falls back to "everything changed".
    static let maxCells = 4_000_000

    static func diff(old: String, new: String) -> [Line] {
        let a = old.components(separatedBy: "\n")
        let b = new.components(separatedBy: "\n")
        let n = a.count, m = b.count

        var result: [Line] = []
        func append(_ kind: Kind, _ text: String, _ oldNumber: Int?, _ newNumber: Int?) {
            result.append(Line(id: result.count, kind: kind, text: text, oldNumber: oldNumber, newNumber: newNumber))
        }

        guard n * m <= maxCells else {
            for (i, line) in a.enumerated() { append(.removed, line, i + 1, nil) }
            for (j, line) in b.enumerated() { append(.added, line, nil, j + 1) }
            return result
        }

        // lcs[i][j] = length of LCS of a[i...] and b[j...]
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }

        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] {
                append(.unchanged, a[i], i + 1, j + 1)
                i += 1; j += 1
            } else if j < m, i == n || lcs[i][j + 1] >= lcs[i + 1][j] {
                append(.added, b[j], nil, j + 1)
                j += 1
            } else {
                append(.removed, a[i], i + 1, nil)
                i += 1
            }
        }
        return result
    }
}
