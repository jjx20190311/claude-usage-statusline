---
name: usage-statusline
description: Install a Claude Code statusline that shows context %, 5-hour quota remaining, 7-day quota remaining, and session cost in real time. Use when the user asks to "install the usage statusline", "set up the usage display", or wants real-time quota visibility on Claude Code.
allowed-tools: Bash, Read, Write, Edit
---

# usage-statusline

Installs a custom Claude Code statusline that displays:

```
ctx 47% | 5h 51% | 7d 65% | $0.42 / 38k tok
```

- **ctx XX%** — current context window usage (parsed from session transcript JSONL)
- **5h XX%** — 5-hour billing window remaining (from Anthropic OAuth `usage` endpoint, same data as `/status`)
- **7d XX%** — 7-day window remaining (same endpoint)
- **$X.XX / XXk tok** — session-to-date cost and total tokens (computed from transcript with hard-coded Claude pricing)

## How it works

The statusline script reads:
1. `transcript_path` from stdin JSON (Claude Code passes this on every statusline render) → context % and session cost
2. `~/.claude/.credentials.json` for the OAuth access token → calls `https://api.anthropic.com/api/oauth/usage` for 5h/7d remaining (cached 30s)

No external dependencies (no ccusage, no npm). Pure bash + python3 + curl.

## Installation steps

When the user invokes this skill:

1. **Copy the script** from this skill directory to `~/.claude/statusline.sh`:
   ```bash
   cp "$(dirname "$0")/statusline.sh" ~/.claude/statusline.sh
   ```
   (In practice, read `statusline.sh` from the skill directory and Write it to `~/.claude/statusline.sh`.)

2. **Update `~/.claude/settings.json`** to register the statusline. Read the existing file, merge in:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash /root/.claude/statusline.sh"
     }
   }
   ```
   Replace `/root/` with the user's actual `$HOME` if different. Preserve any other keys already in settings.json.

3. **Verify** by piping a sample stdin JSON to the script:
   ```bash
   echo '{"transcript_path":"/nonexistent","session_id":"test"}' | bash ~/.claude/statusline.sh
   ```
   Expected output looks like `ctx n/a | 5h XX% | 7d XX% | n/a` (5h/7d will have real values; ctx and cost are n/a because the test transcript path doesn't exist — they'll work in real sessions).

4. **Tell the user**: the statusline activates on next prompt render. They can test it by hitting Enter on an empty prompt.

## Troubleshooting

- **`5h n/a | 7d n/a`** — OAuth token in `~/.claude/.credentials.json` is missing or expired. Have the user re-login to Claude Code (`claude login` or relaunch) which refreshes the token. The statusline picks up the new token automatically (no restart needed).
- **First run takes ~3 seconds** — that's the cold curl call to `api.anthropic.com`. Subsequent renders within 30 seconds hit the cache instantly.
- **`ctx n/a`** in a real session — the transcript JSONL hasn't been written yet (very first message). It'll populate after the first assistant turn.

## Customization

Edit `~/.claude/statusline.sh` to change format. Common tweaks:

- Show model name: parse `model` field from stdin JSON
- Show git branch: add `git branch --show-current 2>/dev/null` to the output
- Use absolute remaining tokens instead of %: replace `100 - utilization` with raw token math
- Adjust cache TTL: change `CACHE_TTL=30` near the top of the OAuth section
