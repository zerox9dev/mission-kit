# mission-kit

A small planner → worker → verifier loop for [Claude Code](https://claude.com/claude-code). You describe a task, approve a plan, and Claude grinds through it step by step: writing code, running your tests, and checking its own work before moving on. Everything lives as markdown in your repo, so your editor is the dashboard. No server, no database, no `claude -p`.

Built for a solo engineer. Borrows the three-role idea from [Factory's Missions](https://factory.ai), shrunk down to something you can read in an afternoon.

## The loop

```
/mission new "add OAuth login"          /mission run <slug>
        │                                       │
        ▼                                       ▼
    planner                          ┌──> worker ──> gate ──> verifier ──┐
  writes the plan +                  │   (edits)   (tests)   (reviews)    │
  a validation contract              └────────── FAIL, retry (≤N) ────────┘
        │                                              │
   you approve it                            PASS ──> commit, next step
                                                       │
                                          all steps done ──> you accept
```

Three subagents, each with its own clean context:

- **planner** (opus, read-only): breaks the task into small steps and writes a *validation contract* up front, a list of assertions about what "done" means, before any code exists.
- **worker** (sonnet): implements one step from its spec. Nothing else.
- **verifier** (opus, read-only): sees only the diff and the spec, never the worker's history, so it doesn't inherit its blind spots. Returns PASS or FAIL.

Your `/mission` session is the conductor. It hands work to the subagents and runs the gate between them. Subagents can't spawn subagents, so the conductor is always you-in-the-session. No hidden recursion.

## Why bother

The bottleneck in shipping isn't the model being dumb. It's your attention: every step needs your eyes. This loop spends cheap, objective checks (tests, types, lint) before it spends an expensive LLM review, caps how many times it retries before tapping you on the shoulder, and writes everything down so nothing drifts on a long run. You step in twice: to approve the plan, and to accept the result.

## Tool vs. state

Two things, kept apart on purpose:

- **The tool**: subagents, the `/mission` command, the gate, templates. Lives in `.claude/`. Update it without touching your work.
- **The state**: the `missions/` folder with your actual tasks. Gitignored by default. Yours, per-project.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/zerox9dev/mission-kit/main/install.sh | sh
```

Run it from inside the project you want to equip. It's idempotent, so re-run it to update. Or clone the repo and run `./install.sh` from your project dir.

## Use

Open Claude Code in the project:

```
/mission new "add OAuth login"   # scaffolds the mission, planner drafts the plan
                                 # → read missions/<slug>/PLAN.md, set status: approved
/mission run <slug>              # runs the loop, stops when done or stuck
/mission status                  # what's in the queue
```

That's the whole interface. The `mission` helper under `.claude/mission-kit/bin/` is plain bash for the bookkeeping. You can poke it in a terminal (`mission status`, `mission coverage <slug>`), but the loop only runs through `/mission`.

## The gate

`gate.sh` runs your lint / types / tests after every edit, and again before the verifier sees anything. It sniffs out the stack on its own:

| if it sees | it runs |
|---|---|
| `package.json` | npm/pnpm/yarn `lint`, `typecheck`, `test` |
| `pyproject.toml` / `requirements.txt` | ruff, mypy, pytest |
| `go.mod` | `go vet`, `go test` |
| `Cargo.toml` | clippy, `cargo test` |

Pin your own commands with a `.mission.yml` at the repo root:

```yaml
lint:  npm run lint
types: npm run typecheck
test:  npm test
```

A red gate means the worker fixes it before the step can close.

## Good to know

- **Billing.** It all runs in your normal Claude Code session, on your subscription. One gotcha: if `ANTHROPIC_API_KEY` is exported, Claude Code bills that key per-token instead of your sub. `unset` it. (`mission check` will tell you.)
- **Rate limits.** A run fires a lot of subagent calls. Comfortable on Max, tight on Pro.
- **Commits.** Each verified step gets committed. The kit's own install files are excluded automatically, but any other uncommitted change in the tree gets swept into the step commit, so start runs from a clean tree. Set `MISSION_COMMIT=0` to turn it off.

## Not built yet

Factory's killer feature is a fourth role that drives the live app: clicking buttons, filling forms, checking flows actually work end to end. That's the obvious v2 here, a `behavior` role on a Playwright MCP. Skipped for now because it's the heaviest thing to build and run, and this stays a personal tool until someone else picks it up.

## License

[MIT](LICENSE).
