# Dojo Salesforce Project Instructions

## Project Context

- This is a Salesforce DX project with the default package directory
  `force-app`, namespace `CareOrch`, and source API version `66.0`.
- Salesforce metadata lives under `force-app/main/default`.
- Follow the repository-specific architecture and output rules in `AGENTS.md`.
- Preserve unrelated working-tree changes and do not edit generated `.sf/` or
  `.sfdx/` state unless explicitly asked to troubleshoot it.

## Salesforce Skills

- Before specialized Salesforce work, read the best matching skill from
  `.github/skills/<skill-name>/SKILL.md` and follow its required workflow.
- When creating or editing Salesforce metadata or any `*-meta.xml` file, also
  read `.github/skills/platform-metadata-api-context-get/SKILL.md` in the same
  turn.
- Load only references needed for the active step. Do not preload the complete
  skill library.
- The installed skills are pinned by `.github/sf-skills.lock.json`; do not
  silently combine them with instructions from another release.

## Dojo Guardrails

- Perform the pre-flight conflict search required by `AGENTS.md` before
  proposing a solution or metadata change.
- Prefer out-of-box Salesforce capability, then declarative metadata and Flow.
  Use Apex only when verified requirements cannot be met declaratively.
- Never modify Profiles. Use appropriately scoped existing Permission Sets.
- Do not create metadata with the `SC_` prefix.
- Protect Case lifecycle transitions, email threading, SLA milestones, Service
  Cloud Voice, Omni Supervisor, Group Account pages, and skills-based routing.
- Keep changes strictly within the acceptance criteria.

## Verification and Safety

- Verify existing metadata, dependencies, licenses, edition support, API
  compatibility, security, data volume, and business impact before proposing
  a Salesforce solution.
- Before any org interaction, run `sf config get target-org --json` and report
  the resolved org.
- Do not deploy, activate, publish, delete, or perform destructive org or data
  changes without explicit approval for the named target org.
- Never hardcode org IDs, credentials, usernames, tokens, or secrets.
- Apply CRUD, FLS, sharing, and user-mode security appropriate to the runtime
  context. Design Apex for bulk execution and governor limits.
- Use the narrowest focused validation from the selected skill. Do not claim
  success without executable evidence.

## Documentation

- Record metadata created or modified, assumptions, target org, validation
  evidence, deployment order, rollback steps, and residual risks.
- Add custom skills as direct children of `.github/skills/`, using
  `.github/skill-templates/my-custom-skill/SKILL.md` as the starter.