---
slug: SLUG
title: TITLE
status: planning   # planning | ready | running | blocked | done
created: CREATED
kit_version: KIT_VERSION
max_iterations: 3
---

# Mission: TITLE

## Goal

GOAL

## Constraints

- (anything the loop must respect: don't touch X, keep public API stable, etc.)

## Acceptance

- (how you, the human, will know the whole mission is done)

## Validation contract

> Written by the `planner` DURING planning, BEFORE any code, and independent of
> how it will be implemented. Each line is one objective assertion about correct
> behavior. Steps reference these IDs in their `asserts:` field. Every assertion
> must be covered by at least one step. This is what stops the loop from drifting:
> tests written to match the code only confirm decisions; these come first.

- A1: (an observable behavior that must hold when the mission is done)
- A2: (another; prefer behavior over implementation — "login with a wrong
       password returns 401", not "the handler calls bcrypt.compare")

## Notes

(free-form context for the planner)
