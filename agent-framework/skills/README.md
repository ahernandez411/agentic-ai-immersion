# Agent Framework Skills

This section demonstrates how to use **Agent Skills** with the Microsoft Agent Framework. Skills are portable packages of instructions, scripts, and resources that give agents specialized capabilities.

## Notebooks

| # | Notebook | Description |
|---|----------|-------------|
| 1 | [Agent with Skills](./1-agent-with-skills.ipynb) | File-based and code-defined skills for FSI (credit risk, compliance) |

## Skill Structure

```
fsi-skills/
├── credit-risk-calculator/
│   ├── SKILL.md              # Instructions + frontmatter
│   └── scripts/
│       └── calculate_risk.py # Executable script
└── compliance-checker/
    ├── SKILL.md              # Instructions + frontmatter
    └── references/
        └── REGULATIONS.md    # Reference material
```

## Key Concepts

- **Progressive Disclosure**: Skills advertise (name + description) → load (full instructions) → read resources → run scripts
- **File-based Skills**: Discovered from `SKILL.md` files in directories
- **Code-defined Skills**: Created inline with `Skill()` and decorated `@skill.resource` / `@skill.script`
- **SkillsProvider**: Context provider that makes skills available to agents

## Prerequisites

- `microsoft-agent-framework` package installed
- Azure CLI authenticated (`az login`)
- `.env` with `FOUNDRY_PROJECT_ENDPOINT` and `AZURE_AI_MODEL_DEPLOYMENT_NAME`
