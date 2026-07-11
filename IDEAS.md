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
