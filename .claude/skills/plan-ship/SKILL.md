---
name: plan-ship
description: Quota-optimized feature workflow - plan, delegated implementation, verification, review. Run with /plan-ship <feature description>.
disable-model-invocation: true
---
Feature goal: $ARGUMENTS

Run this workflow as an ORCHESTRATOR, minimizing consumption:

1. PLAN. Explore the repo (Explore agent if needed), understand existing
   patterns, write a concise, verifiable plan: files to touch, steps,
   "done" criteria (build/typecheck/lint/tests). Do not code yet.

2. DELEGATE. Hand the implementation to the `implementer` agent with the
   plan. Mass mechanical work goes to `grunt`. You do not write the bulk.

3. VERIFY. Ensure build + typecheck + lint pass. For UI, verify the
   render, not just the tests.

4. REVIEW. Hand the review to the `reviewer` agent (fresh context).
   Address CRITICAL findings before concluding.
   If the change touches auth, payments, user input, data migrations or
   anything the human cannot review themselves: also send the
   `corsaire` agent (adversarial pre-mortem) and address its top
   findings.

5. SUMMARIZE. Return: what was done, touched files, verification
   results, remaining review items, and the diff ready to commit. Do NOT
   commit or push without my OK.

Reminder: no useless fan-out. A simple feature does not justify 7 agents.
