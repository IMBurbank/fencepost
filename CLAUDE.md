# Fencepost

Agent workflow guard — protects AI agents from footguns, not from users.

## Quick reference

```bash
cargo test                           # Unit + integration tests (702)
cargo test --test binary             # E2E binary tests (spawns actual binary)
CARGO_TARGET_DIR=/tmp/fb cargo test  # If target/ volume has stale artifacts
cargo install --path .               # Install binary to PATH
fencepost doctor                     # Verify installation
fencepost init                       # Set up a new project
fencepost list-rules                 # Show all 13 rules
FENCEPOST_LOG=debug fencepost bash   # Debug trace on stderr
```

## Architecture

7-layer pipeline: detection → config → tokenizer → segments → context binding → rules → protocol adapter.

- `src/token.rs` — Single-pass POSIX shell tokenizer. Token::Word vs Token::Operator. Do not flatten this distinction.
- `src/segment.rs` — Splits on control operators. Segment is purely structural (no policy). ContextualSegment binds context.
- `src/context.rs` — ProjectContext: detects .git, loads config, captures CWD once. All checks use ctx, never std::env::current_dir().
- `src/rule.rs` — BashRule/EditRule traits, Violation::new() with 3-part messages (attempted/explanation/suggestion).
- `src/rules/` — 13 rules, each in its own file with collocated tests. See `src/rules/README.md`.
- `src/check.rs` — check_bash(&str) and check_edit(&str). Framework-agnostic — takes plain strings, not JSON.
- `src/protocol/` — Protocol adapters. Claude Code ships built-in. See `src/protocol/README.md`.

## Critical conventions

### Frozen interfaces — do NOT change without migration
- Config path: `.fencepost.json` at project root (legacy `.claude/fencepost.json` also supported)
- Config schema v1 fields (frozen contract test in tests/cli.rs)
- Hook subcommands: `fencepost edit`, `fencepost bash` (FROZEN CONVENTION in main.rs)
- Default protocol: `claude`
- Rule names (used in config `rules` section)

### CWD-gated rules must use is_project_root_cwd()
All rules that gate on CWD use `ctx.is_project_root_cwd()`, NOT `!ctx.is_worktree_cwd()`.
These are semantically different: is_worktree_cwd() is false for /tmp, causing over-blocking.
Peer rules: checkout, clean, branch, reset all use is_project_root_cwd().

### ContextualSegment, not raw Segment
New checks receive ContextualSegment (via ctx.bind()). Use has_arg(), has_short_flag(),
has_arg_starting_with(), has_arg_containing(). Do NOT use Segment's _raw methods.
The _raw methods scan all tokens including command names — the old bug pattern from PR #76.

### Violation::new() — 3-part messages enforced
Every violation requires: attempted (what they tried), explanation (why blocked), suggestion (what to do).
Private fields + debug_assert catches vague messages. Meta-tests in tests/cli.rs verify every rule.

### confirm_token — do NOT generalize prematurely
The generic confirm_token() on BashRule skips the ENTIRE rule. WorktreeRemove does NOT use it because
tier-1 (own CWD) must never be overridable. If adding confirm to a new rule, verify no internal tier
should be exempt from the override.

### || true on hook commands
Hook commands in settings.json MUST have || true. Fencepost handles internal errors (exit 0), but
"command not found" is a shell error outside fencepost's control. Without || true, missing binary
bricks the session.

### Config extends defaults
protected_files in config EXTEND built-in defaults (.env*, *.lock). Do not replace unless
protected_files_override: true is set. Projects shouldn't redeclare universal protections.

## Testing

### Test pyramid
- Unit tests: collocated in each source file (#[cfg(test)] mod tests)
- Integration tests: tests/cross_root.rs, tests/integration.rs (tempfile)
- E2E binary tests: tests/binary.rs (spawn actual binary, pipe stdin)
- CLI/meta tests: tests/cli.rs (quality enforcement)

### Meta-tests (tests/cli.rs) — these enforce quality
- meta_every_registered_rule_is_exercised — fails if a rule has no triggering test input
- meta_all_bash_rules_produce_three_part_messages — fails if messages lack structure
- meta_confirm_tokens_follow_convention — I_*=1, >= 15 chars
- meta_all_protocols_pass_smoke_test — every adapter verified automatically
- meta_default_protocol_is_claude — FROZEN
- config_v1_frozen_contract — FROZEN schema test

### Adding a rule triggers automatic failures
Add to BASH_RULES → meta_every_registered_rule_is_exercised fails → add triggering input →
meta_all_bash_rules_produce_three_part_messages verifies message quality. Follow the errors.

## Docker dev environment

The target/ directory is a Docker named volume. If you get stale binary issues:
```bash
CARGO_TARGET_DIR=/tmp/fb cargo build --release
CARGO_TARGET_DIR=/tmp/fb cargo install --path .
```

## What NOT to do

- Do not use std::env::current_dir() in check logic — use ctx.cwd
- Do not add methods to Segment that need ProjectContext — use ContextualSegment
- Do not construct Violation with struct literals — fields are private, use Violation::new()
- Do not change config field names — frozen v1 contract test will fail with migration instructions
- Do not remove || true from hook commands
- Do not use confirm_token() for rules with internal tiers that have different override semantics
