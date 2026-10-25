# Desktop ownership and coordination

This directory contains the native macOS application. Do not edit website files outside it.

- Codex owns `Sources/HowdoeyCore/`, `Sources/Howdoey/` outside `UI/`, `Tests/`, scripts, package configuration, and backend documentation.
- Claude Code owns only `Sources/Howdoey/UI/` after the user authorizes implementation.
- Both agents may read all source files. Do not edit another owner's files without explicit coordination through the user.
- `UI_CONTRACT.md` and `Sources/Howdoey/UIContract.swift` define the shared interface; Codex owns both. Ask for contract changes rather than creating competing types.
- Never discard other agents' uncommitted changes or run repository-wide formatters.
- Keep credentials out of source, logs, tests, and committed configuration.
- No fake model responses, simulated success, or controls wired to empty callbacks in the running app.
