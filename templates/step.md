---
step: NN
title: TITLE
status: todo        # todo | in_progress | gate_failed | verifying | failed | done | blocked
iterations: 0
max_iterations: 3
depends_on: []
asserts: []         # contract assertion IDs this step must satisfy, e.g. [A1, A3]
kit_version: KIT_VERSION
---

# Step NN: TITLE

## Spec

(from the plan: what to change, where, acceptance criteria)

## Verify

(how the verifier confirms intent the gate cannot check; cite the asserts above)

## Handoff

<!-- The worker fills this on every iteration. The verifier reads it. Keep it
     factual: it is the record the next agent inherits, not a summary for a human. -->

- **Completed:** (what this iteration actually changed — files/symbols)
- **Left undone:** (anything in scope but not finished, or "nothing")
- **Commands run:** (command → exit code, one per line)
- **Issues discovered:** (surprises, risks, things the next step should know; or "none")
- **Followed procedures:** (yes / no + what deviated)

---

## Iteration history

<!-- The orchestrator appends a block per round below. Do not edit the
     frontmatter status by hand while a run is in progress. -->
