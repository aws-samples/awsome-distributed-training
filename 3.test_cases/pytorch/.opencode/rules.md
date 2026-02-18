# Project Rules

## Git Workflow

- **Local commits**: You may create local git commits freely as you work.
- **Pushing to remote**: NEVER push to the remote repository without explicit consent from the user. Always ask before running `git push`.
- **Force push**: NEVER force push. If a force push is needed, explain why and wait for explicit approval.
- **Branch**: Work on `feature/opencode-skills` unless told otherwise.

## Repository Structure

- **Skills location**: `3.test_cases/pytorch/opencode/skills/` (canonical source, one level above FSDP/)
- **Claude Code commands**: `3.test_cases/pytorch/claude-commands/`
- **Kiro skills**: `3.test_cases/pytorch/kiro/`
- **FSDP training code**: `3.test_cases/pytorch/FSDP/`
- Do NOT place skills inside `pytorch/FSDP/` -- they go at the `pytorch/` level.

## Original Code

- Do NOT modify original repo files (e.g., `FSDP/src/train.py`, `FSDP/README.md`) without explicit approval.
- When modifying shared files, preserve original content and append new sections below a separator (`---`).

## Skill Sync

- When updating skills, sync to all three locations:
  1. Repo: `pytorch/opencode/skills/` (canonical)
  2. `~/.config/opencode/skills/`
  3. `~/.opencode/skills/`
- When adding Kiro skills, also update `pytorch/kiro/skills/`.

## Docker / Training

- torchrun path: `/opt/conda/bin/torchrun`
- Public tokenizer: `hf-internal-testing/llama-tokenizer` (avoid gated model auth issues)
- Use environment variables (RANK, WORLD_SIZE, etc.) for PyTorchJob compatibility
- CodeBuild is the default build architecture; local Docker is used if available
