import Foundation

/// The string literals of a Swift source file, as a person could see them: comments and identifiers are skipped, and
/// each interpolation `\( ... )` becomes a space, so code inside it is never read as words. Handles `"..."`,
/// multi-line `"""..."""`, raw strings (`#"..."#`), escapes and nested block comments. The same lexer as
/// `scripts/lint_copy.py`.
enum SwiftLiterals {
    struct Literal: Equatable {
        var text: String
        var line: Int
    }

    static func extract(from source: String) -> [Literal] {
        let chars = Array(source.unicodeScalars)
        var out: [Literal] = []
        var i = 0
        var line = 1
        let n = chars.count

        func peek(_ offset: Int) -> Unicode.Scalar? { i + offset < n ? chars[i + offset] : nil }

        // Reads a string literal starting at `i` (at its opening quotes, after any `#`s); returns its text with
        // interpolations as spaces. `hashes` is the raw-string delimiter count.
        func readString(hashes: Int) -> String {
            let multiline = peek(0) == "\"" && peek(1) == "\"" && peek(2) == "\""
            i += multiline ? 3 : 1
            var text = String.UnicodeScalarView()
            while i < n {
                let c = chars[i]
                if c == "\n" { line += 1 }
                // closing quote(s) followed by the right number of #
                if c == "\"" {
                    let quotes = multiline ? 3 : 1
                    var matches = true
                    for k in 0..<quotes where peek(k) != "\"" { matches = false }
                    if matches {
                        var hashOK = true
                        for k in 0..<hashes where peek(quotes + k) != "#" { hashOK = false }
                        if hashOK {
                            i += quotes + hashes
                            return String(text)
                        }
                    }
                }
                if c == "\\" {
                    // an escape only counts with the raw delimiter after the backslash
                    var hashOK = true
                    for k in 0..<hashes where peek(1 + k) != "#" { hashOK = false }
                    if hashOK {
                        let next = peek(1 + hashes)
                        if next == "(" {
                            i += 2 + hashes
                            skipInterpolation()
                            text.append(" ")
                            continue
                        }
                        i += 2 + hashes
                        if let next {
                            switch next {
                            case "n": text.append("\n")
                            case "t": text.append("\t")
                            case "u":
                                // \u{XXXX}
                                if peek(0) == "{" {
                                    var hex = ""
                                    i += 1
                                    while i < n, chars[i] != "}" {
                                        hex.unicodeScalars.append(chars[i])
                                        i += 1
                                    }
                                    i += 1
                                    if let v = UInt32(hex, radix: 16), let s = Unicode.Scalar(v) { text.append(s) }
                                }
                            default: text.append(next)
                            }
                        }
                        continue
                    }
                }
                text.append(c)
                i += 1
            }
            return String(text)
        }

        // After `\(`: skip balanced parentheses, including strings and comments inside.
        func skipInterpolation() {
            var depth = 1
            while i < n, depth > 0 {
                let c = chars[i]
                if c == "\n" { line += 1 }
                if c == "(" { depth += 1; i += 1; continue }
                if c == ")" { depth -= 1; i += 1; continue }
                if c == "\"" {
                    _ = readString(hashes: 0)
                    continue
                }
                i += 1
            }
        }

        while i < n {
            let c = chars[i]
            if c == "\n" {
                line += 1
                i += 1
                continue
            }
            // comments
            if c == "/", peek(1) == "/" {
                while i < n, chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/", peek(1) == "*" {
                var depth = 1
                i += 2
                while i < n, depth > 0 {
                    if chars[i] == "\n" { line += 1 }
                    if chars[i] == "/", peek(1) == "*" {
                        depth += 1
                        i += 2
                    } else if chars[i] == "*", peek(1) == "/" {
                        depth -= 1
                        i += 2
                    } else {
                        i += 1
                    }
                }
                continue
            }
            // raw strings: #"..."#, ##"..."##
            if c == "#" {
                var hashes = 0
                while peek(hashes) == "#" { hashes += 1 }
                if peek(hashes) == "\"" {
                    let start = line
                    i += hashes
                    out.append(Literal(text: readString(hashes: hashes), line: start))
                    continue
                }
                i += hashes
                continue
            }
            if c == "\"" {
                let start = line
                out.append(Literal(text: readString(hashes: 0), line: start))
                continue
            }
            i += 1
        }
        return out
    }
}
