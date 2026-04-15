# workspace-sync

A [Claude Code](https://claude.ai/code) skill that syncs your working context across multiple devices — conversation history, AI-generated summaries, and uncommitted git changes — so you can pick up exactly where you left off.

**Supports two storage backends: GitLab or MinIO.**

---

## The Problem

Claude Code's conversation context is local. When you switch from your work machine to your home machine, the conversation is gone. This skill solves that by:

1. **Pushing** a workspace snapshot (conversation summary + git state) to cloud storage
2. **Pulling** it on another device so Claude can restore full context and continue

---

## How It Works

```
/workspace-sync push "feature-x"   # on work machine before leaving
/workspace-sync pull "feature-x"   # on home machine to resume
/workspace-sync list                # list all saved workspaces
```

On **push**, the skill:
- Auto-detects all git projects touched in the current conversation
- Asks Claude to summarize the conversation (goals, progress, next steps, key files)
- Captures each project's current branch, HEAD, and uncommitted diff as a patch
- Uploads everything to your configured backend

On **pull**, the skill:
- Downloads the workspace snapshot
- Restores each project's branch and applies the uncommitted patch
- Injects the summary into the current Claude session so it resumes with full context

Works for three scenarios automatically (no mode switching needed):
- **Pure discussion** — no code involved, just conversation context
- **Single project** — one git repo
- **Multi-project** — frontend + backend modified in the same conversation

---

## Requirements

- [Claude Code](https://claude.ai/code) CLI
- Git
- For **GitLab backend**: a Personal Access Token with `api`, `read_repository`, `write_repository` scopes
- For **MinIO backend**: `mc` (MinIO CLI) installed, access to a MinIO instance

### Installing `mc` (MinIO CLI)

```bash
# macOS
brew install minio/stable/mc

# Windows (scoop)
scoop install mc

# Linux
curl https://dl.min.io/client/mc/release/linux-amd64/mc -o mc && chmod +x mc && sudo mv mc /usr/local/bin/
```

---

## Installation

```bash
# Clone into your Claude Code skills directory
git clone https://github.com/<your-username>/workspace-sync ~/.claude/skills/workspace-sync

# Copy and fill in the config template
cp ~/.claude/skills/workspace-sync/config.json.example \
   ~/.claude/skills/workspace-sync/config.json
```

Then open a Claude Code session and run:

```
/workspace-sync push test
```

On first use, Claude will guide you through selecting and configuring a backend (interactive setup). The `config.json` is excluded from git, so your credentials stay local.

---

## Configuration

`~/.claude/skills/workspace-sync/config.json` (created from `config.json.example`):

```json
{
  "backend": "gitlab",
  "gitlab": {
    "host": "gitlab.com",
    "token": "glpat-xxx",
    "project_path": "your-name/claude-workspaces",
    "branch": "main"
  },
  "minio": {
    "endpoint": "https://minio.example.com",
    "access_key": "xxx",
    "secret_key": "xxx",
    "bucket": "claude-workspaces",
    "prefix": "workspaces/",
    "mc_alias": "claude-workspace-sync"
  },
  "cache_dir": "~/.claude/workspace-cache",
  "local_paths_file": "~/.claude/skills/workspace-sync/local-paths.json"
}
```

**Important:**
- The GitLab repo and MinIO bucket **must already exist** — the skill will not create them
- `local_paths_file` stores a mapping of `git remote URL → local path`, built up automatically when you pull on a new device
- `config.json` and `local-paths.json` are git-ignored; keep them local

---

## Workspace Storage Format

Each pushed workspace is a directory:

```
<workspace-name>/
├── manifest.json        — metadata: device, timestamp, project list
├── summary.md           — AI-generated summary, structured by project
├── conversation.jsonl   — full conversation backup
└── projects/
    └── <project-name>/
        ├── meta.json    — remote URL, branch, HEAD commit
        └── uncommitted.patch
```

---

## Multi-Device Path Mapping

Projects are identified by their **git remote URL**, not local path. When you `pull` on a new device for the first time, Claude will ask where each project lives locally and remember it for future pulls.

```
Project 'my-api' not found in local-paths.json.
Where is git@github.com:you/my-api.git cloned on this device?
> /home/user/projects/my-api
```

The mapping is saved to `local-paths.json` (git-ignored, stays local).

---

## Roadmap

- [ ] Skill state sync (`.sdd/`, `.ccb/`, etc.)
- [ ] Concurrent device conflict protection
- [ ] Workspace TTL / auto-cleanup
- [ ] GitHub / S3 backend support

---

## Contributing

Issues and PRs welcome. The skill is defined in `SKILL.md` (instructions Claude follows) and `scripts/detect-projects.sh` (bash helper for extracting touched git repos from a session).

If you add a new storage backend, follow the pattern in `SKILL.md` under `# 后端实现`.

---

## License

MIT
