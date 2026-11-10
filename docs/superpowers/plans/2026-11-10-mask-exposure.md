# Mask Exposure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Add local exposure and one scandal per court to the first test build.

**Architecture:** Keep campaign memory and evidence rules in `disguise/mask_exposure.lua`. Let the existing masked dialogue validate the plan, manage its pending confirmation and call the engine. The build loads both modules, and the Lua harness exercises the normal dialogue entry points.

**Tech Stack:** Campaign Lua, TalkHammer, Node.js PFH5 builder.

**Spec:** [Разоблачение Перевёртыша](../specs/2026-11-10-mask-exposure-design.md)

## Global Constraints

- Evidence, refusal and warning windows use five campaign turns, with the current turn included.
- A scandal needs two different forms independently exposed by the same court and attempts a one-time −4 diplomatic bonus against the player faction.
- Keep the TalkHammer byte-safe text path, campaign-save storage and existing action validation. Package and install only the local overlay.

## Review Focus

- A rejected or partially applied plan can only leave records for steps that took effect.
- A changed campaign, turn, form, court or apply setting makes pending actions unsafe.
- Two warnings are one prompt. A warning-assisted exposure alone cannot start a scandal.
- A model error or unsolicited outcome cannot bypass the local block, stale state checks or confirmation.
- A refused attitude change leaves the local exposure and the independently established scandal recorded exactly once.

### Task 1 — Evidence and pre-deal confirmation

**Files**

- Create `disguise/mask_exposure.lua` for `assess(pair, session, plan, allied)`, `record(pair, turn, outcome, clue)` and `blocked_until(pair, turn)`.
- Modify `disguise/mask.lua` to assess plans after live validation and before application. Pass the assessed per-outcome clues into `apply_plan`, and record confirmed outcomes from its successful branch.
- Modify `disguise/build.mjs` to load and package the additional module. Modify `disguise/mask.test.lua` to load both modules and exercise normal dialogues.

- [ ] Write tests that a first ally-war clue applies, another ally-war clue still applies, a subsequent break of a recently signed pact pauses the whole package, and withdrawal leaves the pact and preexisting clue intact.
- [ ] Run the Lua harness and verify the baseline fails at the expected pause assertion.
- [ ] Implement the three clue categories, per-category dates and local block. Add `/mask explain <new offer>`, `/mask withdraw` and `/mask insist`. An explanation runs the same negotiation with a replacement offer and the same court. A safe replacement can pass. An unsafe one pauses again. Check pending state before accepting any answer and show the Lua result in the panel.
- [ ] Run the Lua harness. Assert replacement, refusal through turn T+4, availability at T+5, no side effects after switching context, and per-step recording after a partial result.

### Task 2 — Scandal and allied warnings

**Files**

- Extend `disguise/mask_exposure.lua` with `expose(pair, session, assessment)` to persist the block and return the two independently exposed form keys on first scandal. Add `warn(campaign, court, form_keys, source, turn)`.
- Extend `disguise/mask.lua` to use live AI allies and TalkHammer's configured diplomatic bonus argument order. Update `disguise/mask.test.lua` and `disguise/README.md`.

- [ ] Write tests with two exposed forms at one court, a defensive ally, a military ally and a non-ally. Assert one −4 attempt against Obmanщики, one warning per form and court, and zero campaign mutations on a warning-only prompt until the player insists.
- [ ] Run the harness and verify the baseline fails at the expected scandal or warning assertion.
- [ ] Implement warnings, exposure reasons, one-shot scandal and explicit panel and log output. Use two local clue categories for independent exposure even when a warning is present. Keep the record and warnings if the attitude call fails.
- [ ] Run the harness for warning expiry, save reload, overlapping warnings, warning-assisted exposure, later independent exposure and an engine refusal. Update the README with commands and scope.

### Task 3 — Verify and release

- [ ] Run the Lua harness, also with TalkHammer's byte-safe implementation, and `node --test ../talkhammer-codex.test.mjs` from the main clone. Confirm no stale or mismatched action executes.
- [ ] Build with `node disguise/build.mjs`, verify the resulting package and obtain its SHA-256. Review the complete diff against the spec.
- [ ] Commit the sources as one test build. Tag with the next unused `v0.1.0-test.N` and annotate it with the hash. Push the commit and tag per AGENTS.md. Install the verified overlay at the existing local destination and compare hashes. Record any cases that still need a campaign playthrough.
