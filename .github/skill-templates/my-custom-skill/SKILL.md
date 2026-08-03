---
name: my-custom-skill
description: "Use when: the user asks to perform [specific workflow], mentions [trigger phrases], or works with [relevant file types]. Do not use when: [closely related request owned elsewhere]."
argument-hint: "Describe the task and target files"
---

# My Custom Skill

## Purpose

Describe the single repeatable workflow this skill owns and the outcome it
should produce.

## Prerequisites

1. Identify the target project, files, environment, or org.
2. Verify required tools and permissions without exposing secrets.
3. Confirm any approval gate required before making changes.

## Procedure

1. Inspect the smallest relevant implementation surface.
2. State the expected behavior and a check that can disprove the hypothesis.
3. Make the smallest grounded change.
4. Run the most focused available validation.
5. Repair local failures and rerun the same validation.
6. Report changed files, validation evidence, and remaining risks.

## Guardrails

- Do not invent files, APIs, metadata, org capabilities, or validation results.
- Do not store credentials or other secrets in the skill or its resources.
- Do not perform destructive or production actions without explicit approval.
- Follow repository conventions and preserve unrelated user changes.

## Optional Resources

Add resources only when they make the workflow more reliable:

- `scripts/` for deterministic executable helpers.
- `references/` for detailed documentation loaded only when needed.
- `assets/` for templates, schemas, and static input files.