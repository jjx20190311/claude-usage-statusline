# claude-usage-statusline

A [Claude Code](https://claude.com/claude-code) skill that installs a real-time statusline showing context %, 5-hour quota, 7-day quota, and session cost.

```
ctx 47% | 5h 59% | 7d 36% | $0.42 / 38k tok
```

- **ctx XX%** — current context window used
- **5h XX%** — 5-hour billing window used (matches `/status`)
- **7d XX%** — 7-day window used (matches `/status`)
- **$X.XX / XXk tok** — session-to-date cost and tokens

The 5h/7d numbers come from Anthropic's official `usage` endpoint — the same data shown in `/status`, identical framing (% used).

## Install

```bash
git clone https://github.com/jjx20190311/claude-usage-statusline ~/.claude/skills/usage-statusline
```

Then in a Claude Code session, run:

```
/usage-statusline
```

Claude will copy the script to `~/.claude/statusline.sh` and update `~/.claude/settings.json`. New statusline activates on next prompt render.

## How it works

The skill is just a `SKILL.md` (instructions for Claude) plus `statusline.sh` (the actual script). The script:

1. Reads `transcript_path` from stdin JSON Claude Code passes on every render → context % + session cost
2. Reads OAuth token from `~/.claude/.credentials.json` → calls `https://api.anthropic.com/api/oauth/usage` → 5h/7d remaining (cached 30s)

No external dependencies (no `ccusage`, no `npm`). Pure bash + python3 + curl.

## Uninstall

```bash
rm -rf ~/.claude/skills/usage-statusline ~/.claude/statusline.sh
```

Then remove the `statusLine` block from `~/.claude/settings.json`.

## License

MIT
