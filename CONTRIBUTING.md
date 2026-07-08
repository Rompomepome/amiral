# Contributing

The most valuable contribution right now is **real-world quota data**:
open a "Quota report" issue with before/after numbers. It's what turns
this pattern from anecdote into evidence.

Also welcome:
- New worker agent definitions (keep them single-job, tools-minimal)
- Stack-specific policy variants (Python, Rust, mobile)
- Windows/PowerShell launch profiles
- Fixes to keep up with Claude Code releases (model IDs, flags, menus)

Rules of the house:
- Installer must stay idempotent and non-destructive (CLAUDE.md is
  backed up, imported via `@`, never overwritten)
- Test with a fake HOME: `HOME=/tmp/x bash install.sh` twice, check no
  duplicate import
- English in repo files; README.fr.md mirrors the essentials

> Tip: run `amiral-report` after a benchmark — it formats your numbers and prefills the quota-report issue.
