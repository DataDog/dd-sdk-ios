# code-index skill

A Claude Code skill that enables semantic Swift codebase navigation using the compiler's index store. Provides compiler-accurate symbol resolution: definitions, call sites, protocol conformers, inheritance hierarchies, and more.

## How it works

The skill wraps `indexstore-query`, a Swift CLI tool that queries the index store produced by Xcode or SwiftPM. It uses [IndexStoreDB](https://github.com/swiftlang/indexstore-db) — the same library powering Xcode's "Jump to Definition" — to answer questions about symbols with compiler-level accuracy.

## Setup

### 1. Build the index

**Xcode (preferred):** Build the project in Xcode (⌘B). The tool auto-discovers the most recently modified DerivedData index.

**SPM (fallback):** Run from the repo root:
```bash
swift build --enable-index-store
```

### 2. Build the CLI tool (one-time)

```bash
cd .claude/skills/code-index/tools && swift build -c release 2>&1 | tail -5
```

The binary is placed at `.claude/skills/code-index/tools/.build/release/indexstore-query`.

## Usage

Claude will use this skill automatically when navigating the Swift codebase. You can also invoke it explicitly by asking questions like:

- "Where is `DatadogCore` defined?"
- "What calls `flush()`?"
- "What types conform to `FeatureMessageReceiver`?"
- "What methods does `RUMMonitor` have?"

## Supported queries

| Category | Examples |
|----------|---------|
| Symbol lookup | Find definition, fuzzy search, all symbols in a file or module |
| References | All usages, callers, accessors |
| Inheritance | Protocol conformers, method overrides |
| Structure | Children of a type, extension declarations |
| Tests | Tests covering a file |
| Compilation | Which targets compiled a file |

See [SKILL.md](SKILL.md) for the full command reference.

## File structure

```
.claude/skills/code-index/
├── README.md       # This file
├── SKILL.md        # Agent-facing instructions
└── tools/          # Swift CLI package (indexstore-query)
    └── Sources/
        └── indexstore-query/
            ├── main.swift                    # CLI commands
            ├── XcodeIndexStoreProvider.swift # DerivedData index discovery
            └── SPMIndexStoreProvider.swift   # SPM index discovery
```

## Compatibility

- Xcode 26+ (uses `UniDB/<Project>.xcindex/` layout)
- SwiftPM (uses `.build/index-build/`)
- Apple Silicon and Intel Macs
