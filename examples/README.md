# examples — real routed tasks, end to end

Not hypotheticals. Every task below actually ran while amiral was built
(this repo's own development sessions), and every dollar figure is a real
`~/.amiral/butin.jsonl` event: the tokens the worker actually spent, and
the same tokens priced at the author's baseline model (Opus) as the
counterfactual. Usernames and absolute paths are stripped; nothing else
is touched. If a number couldn't be traced to a real event, it's not here.

**How to read the cost lines.** `real` = what the routed worker cost on
its actual model (Sonnet 5). `counterfactual` = the identical token volume
priced at the Opus baseline — what the same work would have cost with no
routing. `saved` = the difference. This is *observational* (what was
actually spent vs the same tokens at baseline), not an A/B trial — see
[BENCHMARKS.md](../BENCHMARKS.md) for the distinction, and the
decomposition-bias caveat that applies to every counterfactual here.

| # | Task | Triage → route | Model | Real | Baseline (Opus) | Saved |
| --- | --- | --- | --- | --- | --- | --- |
| [1](01-implementer-statusline.md) | Build the butin statusline | real feature → `implementer` | Sonnet 5 | $28.70 | $143.49 | **$114.79** |
| [2](02-corsaire-premortem.md) | Pre-mortem the statusline before shipping | risky/unreviewable → `corsaire` | Sonnet 5 | $9.78 | $48.91 | **$39.13** |
| [3](03-implementer-attribution.md) | Split amiral-routed vs other savings | multi-file logic → `implementer` | Sonnet 5 | $4.47 | $22.35 | **$17.88** |
| [4](04-reviewer-fresh-context.md) | Fresh-context review before staging | after implementation → `reviewer` | Sonnet 5 | $3.66 | $18.30 | **$14.64** |
| [5](05-refusal-trivial-tier.md) | Fix a stale file-count + version string | **trivial → the admiral did it itself** | — | — | — | — |

The discipline is the product as much as the routing. Example 5 is the
one where the admiral *refused* to delegate: a one-line correction costs
less to make than to hand off, so no worker was spawned and no receipt
was written — by design.

Reproduce this on your own machine — it's two commands, not a leap of faith:

```bash
amiral-butin backfill --all   # mint receipts for your past sessions' real transcripts
amiral-butin                  # measure them cold and print the report
```
