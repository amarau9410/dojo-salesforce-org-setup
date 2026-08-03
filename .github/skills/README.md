# Workspace Agent Skills

VS Code discovers project-scoped agent skills from this directory:

```text
.github/skills/<skill-name>/SKILL.md
```

Each skill must be a direct child of `skills`. Do not place custom skills in
an extra `custom/` directory because VS Code will not discover them there.

Skills provide reusable runtime instructions, scripts, references, and assets.
They do not retrain or change the model's weights. The agent discovers a skill
from its frontmatter description and loads its detailed instructions only when
the current request matches.

## Add a Custom Skill

1. Copy `.github/skill-templates/my-custom-skill` into
   `.github/skills/<your-skill-name>`.
2. Rename the `name` in `SKILL.md` to exactly match the folder name.
3. Write a specific `description` containing the request phrases and file types
   that should trigger the skill.
4. Replace the template procedure with concrete, ordered instructions.
5. Add optional `scripts/`, `references/`, or `assets/` folders inside the skill.
6. Start a new chat or reload the VS Code window if the skill does not appear
   immediately.

Use lowercase letters, numbers, and hyphens for skill and folder names. Keep
each skill focused on one repeatable workflow. Put always-on project rules in
`.github/copilot-instructions.md` or an agent instruction file instead.

## Required Structure

```text
.github/skills/my-custom-skill/
|-- SKILL.md
|-- scripts/       # Optional executable helpers
|-- references/    # Optional detailed documentation
`-- assets/        # Optional templates and static resources
```

The minimum valid manifest is:

```yaml
---
name: my-custom-skill
description: "Use when: the user asks for the specific workflow this skill owns."
---
```

## Validation Checklist

- The folder name and frontmatter `name` match exactly.
- The name uses lowercase alphanumeric characters and hyphens only.
- `SKILL.md` begins and ends its YAML frontmatter with `---`.
- The quoted `description` explains both what the skill does and when to use it.
- Resource links are relative, for example `[guide](./references/guide.md)`.
- The procedure identifies prerequisites, approval gates, edits, and validation.
- No secrets, access tokens, passwords, usernames, or org credentials are stored.

The official Salesforce skills in this directory are pinned by
`.github/sf-skills.lock.json`. Keep custom skill names distinct from those
upstream names to prevent collisions during future library updates.