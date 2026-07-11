# Butin & journal — spec v2 (decisions record)

Full narrative spec lives with the author; this file records the binding
decisions from the three review passes, so contributors know what is
MUST, what is roadmap, and what is refused.

## MUST (implemented in v0.10)
- **Collector with coverage** (`adapters/claude-code/butin-collect.sh`):
  wired opt-in on SubagentStop (workers) and Stop `--brain` (main
  session). If tokens can't be extracted → an `unmeasured` event, never
  an invented number. Reports show `measured/total`.
- **Data locale is C**: `export LC_ALL=C` in every script that computes
  or writes. Locale formatting allowed for display only. (A French
  locale writing `0,01` into JSONL corrupts the whole log.)
- **Atomic writes + dedup**: one `printf` per line, line < 4000 chars
  (< PIPE_BUF), every event carries an `id`; the core dedups on read.
- **Category-by-category counterfactual** (never collapse cache into
  input): in×in, out×out, cache_read×cache_read, cache_write×cache_write.
- **Brain premium** (Stop hook event, `agent:"brain"`): penalty =
  max(0, real − counterfactual). Never a credit. Shown as its own row.
- **`verified` in the schema**: the verify gate drops a session marker;
  the collector consumes it (fresh < 5 min). Report shows verified k/N.
- **Journal de bord** (`amiral-journal`): per-repo opt-in git hook →
  trailers `Amiral-Route`, `Amiral-Verified`, `Amiral-Attest`
  (sha256 of verify.sh + staged diff — recomputable, forging it means
  running the real gate). Cost trailer is a separate opt-in with a
  public-remote warning. `FLEET.md` = AI-policy-as-code, read by the
  policy when present, changed by PR.
- **Pavillon thresholds**: no badge under 20 measured tasks; coverage
  always printed. The design encodes honesty, non-negotiable.

## MUST — also implemented in v0.10.1
- `amiral-butin init` / `rebaseline`: first-run config with auto-baseline,
  frontier confirmation (the Fable trap), atomic write; history keeps the
  baseline of its time.
- Escalation heuristic in the collector (same session, cheaper→pricier
  within 15 min, grunt or same agent): the wasted cheap attempt is
  charged AGAINST amiral. Conservative: may over-penalize, never inflates.
- `--haircut=N`: display-time conservative reduction of the
  counterfactual (decomposition bias named in --detail).
- Degenerate-state message (brain=hands=baseline).
- `pricing_version` stamped on every event; staleness warning >3 months;
  refresh is manual-only (nothing phones home).
- Journal `note` mode (git notes ref amiral, survives squash).

**Scope note:** butin & journal are POSIX shell (v1). PowerShell parity is an explicit backlog item, not an implied feature — never re-create the "6 files" class of inconsistency.

## SHOULD (next)
- `amiral-muster` CI action: replay verify.sh, contradict false trailers.
- Statusline (1-line nominal; O(1) cache written atomically via mv).
- Weekly HTML digest (light/dark), N+period+coverage baked in template.
- Monthly log rotation; multi-machine merge = cat + dedup by id.

## ROADMAP (data-gated)
- **La vigie**: escalation-rate drift per route = local model-regression
  canary ("observed on YOUR tasks", min-N, never "provider nerfed X").
- **Le cap**: butin drafts FLEET.md amendments as PRs — suggested, never
  auto-applied, with the justifying number in the description.
- **Fleet Events v1**: the event schema as a small versioned standard.
- in-toto/SLSA alignment for the attestation.

## REFUSED (the line)
No central flag registry (= a server). No "amiral certification". No
compliance claims ("audit-friendly provenance", never "AI-Act
compliant"). No demo mode (a demo screenshot circulating as real data
would destroy the credibility the whole design protects). No FLEET.md
marketplace (v10 talk). Nothing hosted, nothing phones home — the fleet
stays boardable ship by ship.
