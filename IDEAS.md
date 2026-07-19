# Ideas & feedback log

Suggestions from real conversations, kept so the roadmap follows the
terrain rather than guesses. Each entry: the idea, who raised it, and an
honest note on whether it fits amiral's line (discipline, not a runtime;
nothing hosted). Not commitments — signal to weigh against votes on the
issues.

## Context optimization (a layer beyond model routing)
- **Raised by:** Krishna Challa (Founder/CEO, MonkDB) on LinkedIn.
- **The idea:** amiral optimizes the *model* layer (which model does which
  work). The next axis is optimizing *context* before the model even
  runs: persistent memory, reusable operational context, semantic reuse,
  governed retrieval. These attack the token bill from the other side and
  compound with routing rather than compete.
- **Fit:** genuinely different axis, deliberately out of amiral's current
  scope. Worth a docs section positioning amiral as the model layer and
  naming context optimization as complementary (not something amiral
  claims to do). Building retrieval/memory ourselves would be a runtime —
  against the line. But documenting the two-layer view is honest and
  useful. The "explainability / governed retrieval" angle is the
  underrated part: what makes cost optimization defensible in enterprise.

## Token-efficiency framing ("optimal token use is the way")
- **Raised by:** Venugopala Krishna Kotipalli (VP/Delivery Head) on
  LinkedIn; echoed by several commenters.
- **The idea:** the community narrative is shifting from model capability
  to token efficiency. amiral should lead with the *benefit* (cost cut),
  not the mechanism, because the feed is saturated with "how it works"
  posts.
- **Fit:** marketing/positioning, not code. Lead posts with the sourced
  ~2.5x figure (Anthropic's cookbook) and the "no account/proxy/dashboard"
  differentiator. Already reflected in launch messaging.

## The landscape amiral sits in (harness optimizers)
- **Observed:** Tokenade / THOL leaderboard (pi-infected), plus RTK,
  Caveman, Headroom, Context-mode, Graphify, token-optimizer, etc.
- **The insight worth keeping:** most of these optimize tokens *at a fixed
  model* (compression, context eviction, cache-safe tool output). Their
  headline "-90%" often fails to survive a real end-to-end session
  (unadopted custom funcs, lossy compression → re-queries, provider cache
  breakage on proxies). This is empirical backing for amiral's own
  "measure real sessions, not isolated compression" stance.
- **How amiral differs:** orthogonal axis — routing *between* models, not
  compressing *within* one. Some tools (e.g. Tokenade) also do routing;
  amiral's edge there is minimalism: 7 files, nothing hosted, no account,
  no hooks intercepting every call, fully auditable.
- **Fit:** a short "where amiral sits" note in landscape.md could help
  people place it. Do NOT integrate any of these (commercial services or
  hosted proxies = a runtime + a dependency; against the line). Combining
  them is the *user's* choice, run side by side.

## Persistent enterprise memory / reusable context
- **Raised by:** Krishna Challa (as above), as a distinct opportunity.
- **The idea:** cross-session memory and semantic reuse so the agent
  doesn't re-pay for context it already computed.
- **Fit:** powerful, but this is squarely a hosted/stateful system —
  exactly what amiral avoids. Best treated as "complementary layer,
  someone else's tool" in docs, not a feature to build. If ever explored,
  it would have to stay local/config, not a service.

---

*How to use this file:* when an idea here also shows up as a GitHub issue
with community 👍, that's the signal to build it (within the line). Ideas
that stay quiet stay here. The line is non-negotiable: discipline in
markdown, nothing hosted, nothing that phones home.

## Adoption counting — WITHOUT telemetry (validated 2026-07-10)
- **Problem:** most people don't star or fork; they copy the repo URL and
  hand it to their agent. So stars undercount real adoption.
- **Decision — the intelligent alternative:** never a home-grown ping in
  install.sh (that's telemetry; it kills "nothing phones home", the whole
  edge over hosted rivals). Instead:
  1. **Publish on npm + the Claude Code plugin marketplace.** The registry
     counts installs natively and publicly — the platform counts, not us.
     Gives a real install number AND a distribution channel. (Ponytail
     does exactly this: `publish.yml` auto-publishes to npm on release.)
  2. **GitHub traffic API** (clones ≈ installs, views, popular paths) as
     the honest proxy already available: `gh api repos/.../traffic/clones`.
- **The line:** counting must come from platforms that count natively,
  never from amiral calling home.

## Community benchmark data — opt-in, WITHOUT a server (validated 2026-07-10)
- **Want:** enrich the public benchmark with real community numbers, with
  a frictionless in-terminal "proceed?" opt-in (not the user doing manual
  work).
- **The trap (non-negotiable):** the moment user data flows to an endpoint
  WE control — even with consent — three irreversible things happen:
  (1) we're now hosting → "nothing hosted" dies; (2) we hold third-party
  data → GDPR burden + breach liability; (3) an author-collected,
  author-hosted table is LESS credible, not more ("collected by the
  author, unverifiable").
- **Decision — same UX, no poison:** `amiral-report --contribute` shows
  the EXACT few fields (net_saved, coverage, baseline, cheap_route_success,
  cc_version — no repo names, no paths, no prompts), then a "proceed?"
  that OPENS A PRE-FILLED GITHUB ISSUE the user submits themselves. Same
  one-keystroke flow the user wanted; data lands in a PUBLIC space, never
  our machine. Each contribution is public + attributed → MORE credible.
- **The rule (write in spec, it's a selling point):** consent never
  justifies a proprietary endpoint; user data transits only to a public
  space the user submits. Nothing phones home, ever.

## A SERIOUS benchmark from the start (direction set 2026-07-10)
- Romain's call: no "bricole then fix" — a serious, reproducible bench.
- What "serious" actually requires (ponytail is the bar): a reproducible
  harness (run/judge/tasks), a real agent on fixed real tasks, objective
  git-diff scoring, control arms, n>=4, published method. PLUS neutralize
  amiral's two contaminations: global policy leaking into the "naive" run
  (baseline run must disable the amiral import) and Claude Code memory
  recognizing the task (fresh clone per run).
- **Sequencing (technical, not optional):** the benchmark scores on real
  cost per task — which IS the butin. So: prove the butin on real data
  FIRST (current dogfood run), THEN build benchmarks/ ON TOP of the butin.
  Not "bricole then fix" — foundation (measure) before wall (benchmark).
  Model to follow: ponytail benchmarks/agentic/ (run.py, judge.py,
  tasks.py). This is a multi-day dedicated chantier, not a graft.

## Future monetization — anticipate, don't compromise (direction set 2026-07-10)
- Anticipating something to sell later = yes. Compromising the line now =
  no. Compatible via **open-core**: core stays MIT/free/local/auditable
  (that's what drives adoption + beats MonkDB/Tokenade); what sells later
  is marginal-value-for-teams, not for the solo dev — e.g. multi-machine
  aggregation, an OPTIONAL hosted dashboard (others keep local), support,
  a "fleet" org edition.
- **Cheap to do now, decide later:** keep a clean core/periphery split
  (core never depends on a service) and a stable, documented event schema
  (ports/BUTIN.md → future "Fleet Events") — a team-aggregation product
  would consume it. Note commercial extension points in the spec; do NOT
  build them. Do NOT decide the product now — no traction yet to say what
  or to whom. Anticipate = keep doors open architecturally.

## Salvage from ponytail — engineering, not identity (re-analyzed on disk 2026-07-10)
Priority order (by real value to amiral):
1. **CI anti-drift check** (HIGH — fixes our most painful recurring wound:
   silently-failed patches, duplicate blocks, doc drift). Ponytail:
   scripts/check-rule-copies.js + check-versions.js run in test.yml,
   verifying all per-harness copies agree and version is consistent
   everywhere. Adapt for amiral: a CI test asserting dogfood
   (agents/skills copies match), versions aligned, no duplicated case arms.
2. **publish.yml (npm)** (HIGH — executes the validated install-count
   idea). Adapt package.json + a publish workflow → public npm install
   counter + distribution.
3. **examples/ dir** (MED — the presentation lesson). 12 before/after
   files make ponytail concrete in 5s. amiral equivalent: real routed
   sessions (task → route → butin receipt) to materialize value.
4. **build-from-source multi-harness** (MED — when widening portability):
   ponytail generates per-harness copies from ONE source
   (build-openclaw-skills.js), verified in CI. Apply to 2-3 REAL targets
   (Cursor, Codex, OpenCode — where users are), NOT a speculative catalog.
   Scope discipline: they earned 15 configs one request at a time.
5. **Reproducible bench harness** (ROADMAP — see serious-benchmark above):
   benchmarks/agentic/ is the model when we build the real bench.
- **NOT taken:** all ~15 harness configs at once (scope); MCP server +
  pi-extension + .env (they're prepping hosted commercial — not our line);
  the multiple audit/debt/gain skills (their product, not ours); the
  character/branding (we have our own, maritime). Salvage engineering,
  not identity.

