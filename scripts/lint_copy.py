#!/usr/bin/env python3
"""Scan every Swift string literal under Sources/ for words that never reach the screen.

The banned words and retired phrases are Pebble's own (src/jargon.test.mjs `BANNED` and `NOWHERE`, ported in
Sources/PebbleDesign/Copy/BannedWords.swift). Comments and identifiers are skipped; each string interpolation
`\\( ... )` counts as a space, so code inside it is never read as words. Words that are internal to this app
("bridge", "payload", ...) are reported as warnings.

    python3 -I scripts/lint_copy.py            # exit 0 clean, 1 banned words found, 2 usage error
    python3 -I scripts/lint_copy.py --quiet    # print only problems
    python3 -I scripts/lint_copy.py PATH ...   # scan these files or folders instead of Sources/

A literal that must keep such a word (a protocol header, a test fixture) carries `// lint-copy: allow` on its line.
Standard library only; same lexer as Tests/PebbleDesignTests/SwiftLiterals.swift.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BANNED = re.compile(r"\b(inference|receipts?|host|runtime|capacity|E-B1)\b", re.IGNORECASE)
NOWHERE = ["Activity & review", "Windows Pebble can use", "Pebble's browser", "Settings → Mods",
           "Settings → Extensions"]
DISCOURAGED = re.compile(r"\b(bridge|payload|endpoints?|epoch|RPC|JSON|idempotency)\b")
# The list of banned words itself.
SKIP_FILES = {os.path.join("Sources", "PebbleDesign", "Copy", "BannedWords.swift")}
ALLOW_MARK = "lint-copy: allow"


def literals(source):
    """Yield (line, text) for every string literal in Swift `source`."""
    n = len(source)
    i = 0
    line = 1

    def read_string(hashes):
        nonlocal i, line
        multi = source.startswith('"""', i)
        i += 3 if multi else 1
        quotes = 3 if multi else 1
        out = []
        while i < n:
            c = source[i]
            if c == "\n":
                line += 1
            if c == '"' and source.startswith('"' * quotes + "#" * hashes, i):
                i += quotes + hashes
                return "".join(out)
            if c == "\\" and source.startswith("#" * hashes, i + 1):
                nxt = source[i + 1 + hashes] if i + 1 + hashes < n else ""
                if nxt == "(":
                    i += 2 + hashes
                    skip_interpolation()
                    out.append(" ")
                    continue
                i += 2 + hashes
                if nxt == "n":
                    out.append("\n")
                elif nxt == "t":
                    out.append("\t")
                elif nxt == "u" and i < n and source[i] == "{":
                    end = source.find("}", i)
                    try:
                        out.append(chr(int(source[i + 1:end], 16)))
                    except ValueError:
                        pass
                    i = end + 1
                else:
                    out.append(nxt)
                continue
            out.append(c)
            i += 1
        return "".join(out)

    def skip_interpolation():
        nonlocal i, line
        depth = 1
        while i < n and depth > 0:
            c = source[i]
            if c == "\n":
                line += 1
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            elif c == '"':
                read_string(0)
                continue
            i += 1

    while i < n:
        c = source[i]
        if c == "\n":
            line += 1
            i += 1
        elif source.startswith("//", i):
            end = source.find("\n", i)
            i = n if end < 0 else end
        elif source.startswith("/*", i):
            depth = 1
            i += 2
            while i < n and depth > 0:
                if source[i] == "\n":
                    line += 1
                if source.startswith("/*", i):
                    depth += 1
                    i += 2
                elif source.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
        elif c == "#":
            hashes = 0
            while i + hashes < n and source[i + hashes] == "#":
                hashes += 1
            if i + hashes < n and source[i + hashes] == '"':
                start = line
                i += hashes
                yield start, read_string(hashes)
            else:
                i += hashes
        elif c == '"':
            start = line
            yield start, read_string(0)
        else:
            i += 1


def scan(path, rel):
    with open(path, encoding="utf-8") as handle:
        source = handle.read()
    lines = source.split("\n")
    problems, warnings = [], []
    for number, text in literals(source):
        if ALLOW_MARK in lines[number - 1] if number - 1 < len(lines) else False:
            continue
        found = [m.group(0) for m in BANNED.finditer(text)] + [p for p in NOWHERE if p in text]
        if found:
            problems.append(f"{rel}:{number}: {', '.join(found)} in {text[:80]!r}")
        # Warnings only for literals that read as words (Pebble's `readsAsWords`), not keys such as "epoch".
        stripped = text.strip()
        reads_as_words = bool(re.search(r"\s", stripped)) or bool(re.match(r"[A-Z][a-z]", stripped))
        soft = [m.group(0) for m in DISCOURAGED.finditer(text)] if reads_as_words else []
        if soft:
            warnings.append(f"{rel}:{number}: {', '.join(soft)} in {text[:80]!r}")
    return problems, warnings


def swift_files(targets):
    for target in targets:
        if os.path.isfile(target):
            yield target
            continue
        for folder, _, names in os.walk(target):
            for name in sorted(names):
                if name.endswith(".swift"):
                    yield os.path.join(folder, name)


def main(argv):
    quiet = "--quiet" in argv
    targets = [a for a in argv if not a.startswith("--")] or [os.path.join(ROOT, "Sources")]
    if not all(os.path.exists(t) for t in targets):
        print("lint_copy: no such file or folder: " + ", ".join(t for t in targets if not os.path.exists(t)))
        return 2
    problems, warnings, count = [], [], 0
    for path in swift_files(targets):
        rel = os.path.relpath(path, ROOT)
        if rel in SKIP_FILES:
            continue
        count += 1
        p, w = scan(path, rel)
        problems += p
        warnings += w
    for line in warnings:
        print("warning: " + line)
    for line in problems:
        print("banned: " + line)
    if not quiet or problems:
        print(f"lint_copy: {count} files, {len(problems)} banned, {len(warnings)} warnings")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
