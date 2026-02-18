---
inclusion: always
---

# Workflow Rules

## Git

- **Local commits**: Agent may create local commits freely.
- **Push to remote**: NEVER push without explicit user consent. Always ask first.
- **Force push**: NEVER. Explain the need and wait for approval.
- **Branch**: `feature/opencode-skills` unless told otherwise.

## Repository Layout

- Skills (canonical): `opencode/skills/`
- Claude Code commands: `claude-commands/`
- Kiro skills/steering: `kiro/`
- Training code: `FSDP/`
- All skill directories live at `pytorch/` level, NOT inside `FSDP/`.

## Original Code Protection

- Do NOT modify original repo files without explicit approval.
- When adding to shared files (e.g., README.md), preserve original content and append below a `---` separator.

## Training Specifics

- torchrun path: `/opt/conda/bin/torchrun`
- Public tokenizer: `hf-internal-testing/llama-tokenizer`
- Environment variables: RANK, WORLD_SIZE, LOCAL_RANK, MASTER_ADDR, MASTER_PORT
- CodeBuild is default; local Docker if available
