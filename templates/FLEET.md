# Fleet policy — this repo

<!-- AI-policy-as-code: commit this file; change it by PR like any code.
     amiral reads it when present; it overrides personal defaults for
     everyone who clones. -->

## Routing
- Brain (plans, judges, verifies): opus
- Hands (implementer, reviewer): sonnet
- Grunt (mechanical bulk): haiku

## Gates
- Nothing ships until `./verify.sh` passes (build + tests).
- Adversarial pass (corsaire) REQUIRED for: auth, payments, migrations,
  user input handling, or any change the reviewer flags as risky.

## Provenance (journal de bord)
- Commit trailers: enabled (Route + Verified + Attest). Cost trailer: off.
