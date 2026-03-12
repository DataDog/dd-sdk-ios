---
name: code-index
description: Use when you need to navigate the Swift codebase semantically — finding symbol definitions, call sites, protocol conformers, method overrides, module dependencies, or nesting relationships. Prefer this over grep-based search when you need precise, compiler-level symbol resolution.
---

# Code Index — Swift Index Store Queries

The `indexstore` tool queries the Xcode/SwiftPM index store that is built alongside the project. It provides compiler-accurate symbol information: exact definitions, all references, call graphs, inheritance hierarchies, and module dependency graphs.

## Prerequisites

### 1. Build the index

The tool automatically finds the best available index:

1. **Xcode (preferred)** — build in Xcode (⌘B). The tool auto-discovers the most recently modified DerivedData index.
2. **SPM (fallback)** — if no Xcode index is found, run `swift build --enable-index-store` from the repo root.

### 2. Build the CLI tool

Build the `indexstore` binary from the tools package (one-time setup):

```bash
cd .claude/skills/code-index/tools && swift build -c release 2>&1 | tail -5
```

The compiled binary will be at:
```
.claude/skills/code-index/tools/.build/arm64-apple-macosx/release/indexstore-query
```

## Running Queries

All subcommands output JSON. Pipe to `jq` for readable formatting.

### Binary path

```
.claude/skills/code-index/tools/.build/release/indexstore-query
```

> **IMPORTANT**: Always invoke the binary using its literal path — never assign it to a shell variable first, and never wrap it in `bash -c "..."`. Use the literal path directly so the command matches the pre-approved permission rule.

### Subcommand reference

#### Symbol lookup

| Goal | Command |
|------|---------|
| Find a symbol definition by name | `.claude/skills/code-index/tools/.build/release/indexstore-query find <Name> --path .` |
| Fuzzy search across all symbols | `.claude/skills/code-index/tools/.build/release/indexstore-query search <pattern> --path .` |
| All symbols defined in a file | `.claude/skills/code-index/tools/.build/release/indexstore-query file-symbols <relative/path.swift> --path .` |
| All symbols in a module | `.claude/skills/code-index/tools/.build/release/indexstore-query module-symbols <ModuleName> --path .` |

#### References and call graph

| Goal | Command |
|------|---------|
| All references to a symbol | `.claude/skills/code-index/tools/.build/release/indexstore-query usages <USR> --path .` |
| Declaration sites of a symbol (ObjC/protocols only) | `.claude/skills/code-index/tools/.build/release/indexstore-query declarations <USR> --path .` |
| Who calls a function | `.claude/skills/code-index/tools/.build/release/indexstore-query callers <USR> --path .` |
| Accessor symbols (get/set/willSet/didSet) | `.claude/skills/code-index/tools/.build/release/indexstore-query accessors <USR> --path .` |

#### Inheritance and conformance

| Goal | Command |
|------|---------|
| Types conforming to a protocol | `.claude/skills/code-index/tools/.build/release/indexstore-query conformers <USR> --path .` |
| Extension declarations on a type | `.claude/skills/code-index/tools/.build/release/indexstore-query extends <extensionUSR> --path .` |
| Methods overriding a method | `.claude/skills/code-index/tools/.build/release/indexstore-query overrides <USR> --path .` |
| Specializations of a generic (C++ only) | `.claude/skills/code-index/tools/.build/release/indexstore-query specializations <USR> --path .` |

#### Nesting and structure

| Goal | Command |
|------|---------|
| Symbols lexically inside a type or function | `.claude/skills/code-index/tools/.build/release/indexstore-query children <USR> --path .` |

#### Objective-C and Interface Builder

| Goal | Command |
|------|---------|
| Objective-C method dispatch receivers | `.claude/skills/code-index/tools/.build/release/indexstore-query received-by <USR> --path .` |
| Interface Builder type relationships | `.claude/skills/code-index/tools/.build/release/indexstore-query ib-types <USR> --path .` |

#### Tests

| Goal | Command |
|------|---------|
| Tests that reference a source file | `.claude/skills/code-index/tools/.build/release/indexstore-query unit-tests <relative/path.swift> --path .` |
| All test symbols in the index | `.claude/skills/code-index/tools/.build/release/indexstore-query all-tests --path .` |

#### Compilation units and includes

| Goal | Command |
|------|---------|
| Which compilation units compiled a file | `.claude/skills/code-index/tools/.build/release/indexstore-query units <relative/path.swift> --path .` |
| Translation-unit (main) files for a file | `.claude/skills/code-index/tools/.build/release/indexstore-query main-files <relative/path.swift> --path .` |
| Files #included by a file (C/Objective-C) | `.claude/skills/code-index/tools/.build/release/indexstore-query includes <relative/path.swift> --path .` |
| Files that #include a file (C/Objective-C) | `.claude/skills/code-index/tools/.build/release/indexstore-query included-by <relative/path.swift> --path .` |
| Detailed #include entries for a unit | `.claude/skills/code-index/tools/.build/release/indexstore-query unit-includes <UnitName> --path .` |

### Typical workflows

#### 1. Find a symbol and drill into its usages

```bash
# Step 1: get USR
.claude/skills/code-index/tools/.build/release/indexstore-query find DatadogContext --path . | jq '.[] | {name, kind, path, line, usr}'

# Step 2: all reference sites
.claude/skills/code-index/tools/.build/release/indexstore-query usages 's:14DatadogInternal0A7ContextV' --path . | jq '.[] | {path, line}'
```

#### 2. Find all conformers of a protocol

```bash
.claude/skills/code-index/tools/.build/release/indexstore-query find FeatureMessageReceiver --path . | jq '.[0].usr' -r | \
  xargs -I{} .claude/skills/code-index/tools/.build/release/indexstore-query conformers {} --path . | jq '.[] | {name, path}'
```

#### 3. Inspect the nesting structure of a type

```bash
.claude/skills/code-index/tools/.build/release/indexstore-query find DatadogCore --path . | jq '.[0].usr' -r | \
  xargs -I{} .claude/skills/code-index/tools/.build/release/indexstore-query children {} --path . | jq '.[] | {name, kind, line}'
```

#### 4. Find tests for a source file

```bash
.claude/skills/code-index/tools/.build/release/indexstore-query unit-tests DatadogCore/Sources/Core/DatadogCore.swift --path . | \
  jq '.[] | {name, path}'
```

#### 5. Understand which targets compiled a file

```bash
# Step 1: list compilation unit names
.claude/skills/code-index/tools/.build/release/indexstore-query units DatadogCore/Sources/Core/DatadogCore.swift --path . | jq '.[].path'

# Step 2: inspect a unit's #include graph (for C/Objective-C files)
.claude/skills/code-index/tools/.build/release/indexstore-query unit-includes "SomeUnitName" --path . | jq '.[] | {sourcePath, targetPath, line}'
```

#### 6. Find where a symbol is declared vs. defined

```bash
# Declaration sites (e.g. protocol requirement, Objective-C forward declarations)
.claude/skills/code-index/tools/.build/release/indexstore-query declarations 's:14DatadogInternal...' --path . | jq '.[] | {path, line, kind}'
# Definition site (the implementation)
.claude/skills/code-index/tools/.build/release/indexstore-query find SomeSymbol --path . | jq '.[]'
```

#### 7. Explore specializations of a generic

```bash
.claude/skills/code-index/tools/.build/release/indexstore-query find encode --path . | jq '.[] | select(.properties[]? == "generic") | {name, usr}' | \
  head -1 | jq -r '.usr' | \
  xargs -I{} .claude/skills/code-index/tools/.build/release/indexstore-query specializations {} --path . | jq '.[] | {name, path, line}'
```

#### 8. Objective-C method dispatch — who receives a selector

```bash
.claude/skills/code-index/tools/.build/release/indexstore-query find viewDidLoad --path . | jq '.[0].usr' -r | \
  xargs -I{} .claude/skills/code-index/tools/.build/release/indexstore-query received-by {} --path . | jq '.[] | {name, path, line}'
```

### Output shape

Every result object has:

| Field | Description |
|-------|-------------|
| `name` | Symbol name |
| `kind` | `class`, `struct`, `protocol`, `function`, `instanceMethod`, etc. |
| `usr` | Unified Symbol Reference — stable compiler identifier, use for follow-up queries |
| `language` | `swift` or `objc` (Objective-C) |
| `module` | Module the symbol belongs to |
| `path` | Absolute path to the file |
| `line` | Line number |
| `column` | Column (UTF-8 offset) |
| `properties` | Optional array: `local`, `generic`, `swiftAsync`, `unitTest`, `protocolInterface` |
| `relations` | Optional array of related symbols, each with `roles`, `name`, `kind`, `usr` |

`unit-includes` returns a different shape:

| Field | Description |
|-------|-------------|
| `sourcePath` | Absolute path to the file that contains the `#include` directive |
| `targetPath` | Absolute path to the file being included |
| `line` | Line number of the `#include` directive |

## When to Use This vs. Grep

| Situation | Tool |
|-----------|------|
| "Where is `X` defined?" | `find X` — compiler-accurate, handles overloads |
| "What calls `X`?" | `callers <USR>` — only real call sites, not string matches |
| "What conforms to protocol `X`?" | `conformers <USR>` |
| "What is declared inside type `X`?" | `children <USR>` |
| "Where is `X` declared (ObjC forward decl / protocol requirement)?" | `declarations <USR>` |
| "Which targets compiled this file?" | `units <path>` |
| "What files mention the word `X`?" | Grep — faster for text patterns |
| "Where is this string literal used?" | Grep |
| "Do any tests cover this file?" | `unit-tests <path>` |

## Handling Large Output

When a query returns a large result, Claude's context infrastructure automatically truncates the inline output and saves the full result to a temp file:

```
Output too large (66.4KB). Full output saved to: /Users/.../.claude/projects/.../tool-results/abc123.txt
Preview (first 2KB): ...
```

**When this happens, run `jq` directly on the saved file:**

```bash
jq '.[] | select(.path | contains("Sources"))' /path/to/saved-output.txt
```

Or use `Read` on the saved path if you need to inspect the raw JSON first.

**NEVER fall back to `grep` or `Bash` for Swift symbol lookups because output was large.** That violates the Swift symbol navigation rules regardless of reason.

If results are still too many, narrow the query instead:
- Use `find <ExactName>` instead of `search <pattern>`
- Add a `jq` select filter inline in the original command
- Use a more specific subcommand (e.g. `children <USR>` instead of `find`)

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| `Index not found` error | Run `swift build` or build in Xcode first |
| Binary not found | Build the CLI tool with `swift build -c release` inside `tools/` |
| `module-symbols` is slow | Add `--limit 100` to cap results |
| Using `search` when you know the exact name | Use `find` — it's faster and deduplicates exact + fuzzy matches |
| Passing absolute path to `unit-tests` / `file-symbols` / `units` / `main-files` | These take a **repo-relative** path, e.g. `DatadogCore/Sources/Core/DatadogCore.swift` |
| `extends` returns 0 results | Pass an **extension USR** (starts with `s:e:s:`), not the base type USR |
| `unit-tests` returns 0 for a production source file | Pass a **test** source file that is its own compilation unit (verify with `main-files`) |
| `unit-includes` returns nothing | The unit name must come verbatim from `units` output; it is not a file path |
| Output was large → used `grep` | **Wrong.** Run `jq '...' /path/to/saved-output.txt` on the saved temp file. Large output is never a reason to use `grep` for Swift symbols. |
