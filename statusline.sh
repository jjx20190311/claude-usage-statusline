#!/usr/bin/env bash
# Claude Code statusline script
# Outputs: ctx XX% | 5h XX% | $X.XX / XXk tok

set -euo pipefail

# ── Read stdin JSON ──────────────────────────────────────────────────────────
INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('transcript_path',''))" 2>/dev/null || true)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null || true)

# ── 1. Context window usage from transcript ──────────────────────────────────
CTX_PART="ctx n/a"
if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
  CTX_PART=$(python3 - "$TRANSCRIPT" <<'PYEOF'
import sys, json

path = sys.argv[1]
CONTEXT_WINDOW = 200_000

# Claude pricing (per million tokens, as of 2025)
# claude-opus-4:      input $15, output $75, cache_write $18.75, cache_read $1.50
# claude-sonnet-4:    input $3,  output $15, cache_write $3.75,  cache_read $0.30
# claude-haiku-3-5:   input $0.80, output $4, cache_write $1.00, cache_read $0.08
# We'll use a generic fallback and try to detect model from entries
PRICING = {
    "claude-opus-4":         {"input": 15.00, "output": 75.00, "cache_write": 18.75, "cache_read": 1.50},
    "claude-sonnet-4":       {"input":  3.00, "output": 15.00, "cache_write":  3.75, "cache_read": 0.30},
    "claude-sonnet-4-5":     {"input":  3.00, "output": 15.00, "cache_write":  3.75, "cache_read": 0.30},
    "claude-sonnet-3-5":     {"input":  3.00, "output": 15.00, "cache_write":  3.75, "cache_read": 0.30},
    "claude-haiku-3-5":      {"input":  0.80, "output":  4.00, "cache_write":  1.00, "cache_read": 0.08},
    "claude-haiku-3":        {"input":  0.25, "output":  1.25, "cache_write":  0.30, "cache_read": 0.03},
    "default":               {"input":  3.00, "output": 15.00, "cache_write":  3.75, "cache_read": 0.30},
}

def get_price(model_id):
    if not model_id:
        return PRICING["default"]
    mid = model_id.lower()
    for key in PRICING:
        if key != "default" and key in mid:
            return PRICING[key]
    return PRICING["default"]

try:
    lines = open(path).readlines()
except Exception:
    print("ctx n/a | n/a | n/a")
    sys.exit(0)

# Parse all JSONL entries
entries = []
for line in lines:
    line = line.strip()
    if not line:
        continue
    try:
        entries.append(json.loads(line))
    except Exception:
        pass

if not entries:
    print("ctx n/a | n/a | n/a")
    sys.exit(0)

# Find latest assistant message with usage info for ctx %
latest_usage = None
model_id = None
for entry in reversed(entries):
    msg = entry.get("message", {})
    if msg.get("role") == "assistant":
        u = msg.get("usage")
        if u:
            latest_usage = u
            model_id = msg.get("model") or entry.get("model")
            break

# Sum ALL usage across session for cost calculation
total_input = 0
total_output = 0
total_cache_write = 0
total_cache_read = 0
last_model_id = model_id

for entry in entries:
    msg = entry.get("message", {})
    if msg.get("role") == "assistant":
        u = msg.get("usage")
        if u:
            total_input += u.get("input_tokens", 0)
            total_output += u.get("output_tokens", 0)
            total_cache_write += u.get("cache_creation_input_tokens", 0)
            total_cache_read += u.get("cache_read_input_tokens", 0)
            if not last_model_id:
                last_model_id = msg.get("model") or entry.get("model")

# ctx % — use latest assistant message usage (current context size)
if latest_usage:
    ctx_tokens = (
        latest_usage.get("input_tokens", 0)
        + latest_usage.get("cache_read_input_tokens", 0)
        + latest_usage.get("cache_creation_input_tokens", 0)
    )
    ctx_pct = round(ctx_tokens / CONTEXT_WINDOW * 100)
    ctx_str = f"ctx {ctx_pct}%"
else:
    ctx_str = "ctx n/a"

# cost — sum all usage
price = get_price(last_model_id)
cost = (
    total_input      * price["input"]        / 1_000_000
    + total_output   * price["output"]       / 1_000_000
    + total_cache_write * price["cache_write"] / 1_000_000
    + total_cache_read  * price["cache_read"]  / 1_000_000
)
total_all_tokens = total_input + total_output + total_cache_write + total_cache_read
tok_k = total_all_tokens / 1000

if tok_k >= 1:
    tok_str = f"{tok_k:.0f}k tok"
else:
    tok_str = f"{total_all_tokens} tok"

cost_str = f"${cost:.2f} / {tok_str}"

print(f"{ctx_str}|{cost_str}")
PYEOF
  ) 2>/dev/null || CTX_PART="ctx n/a|n/a"

  # Split the two parts returned by python
  CTX_DISPLAY="${CTX_PART%%|*}"
  COST_DISPLAY="${CTX_PART##*|}"
else
  CTX_DISPLAY="ctx n/a"
  COST_DISPLAY="n/a"
fi

# ── 2. 5h / 7d remaining via Anthropic OAuth usage endpoint ──────────────────
# Cached for 30s. Endpoint returns instantly (~200ms) so no async needed.
CACHE_FILE="/tmp/.anthropic_usage.txt"
CACHE_TTL=30

QUOTA_PART="5h n/a"
WEEK_PART="7d n/a"

USE_CACHE=0
if [[ -f "$CACHE_FILE" ]]; then
  AGE=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
  [[ $AGE -lt $CACHE_TTL ]] && USE_CACHE=1
fi

if [[ $USE_CACHE -eq 1 ]]; then
  CACHED=$(cat "$CACHE_FILE" 2>/dev/null || true)
  [[ -n "$CACHED" ]] && { QUOTA_PART="${CACHED%%|*}"; WEEK_PART="${CACHED##*|}"; }
else
  TOKEN=$(python3 -c "import json; print(json.load(open('/root/.claude/.credentials.json'))['claudeAiOauth']['accessToken'])" 2>/dev/null || true)
  if [[ -n "$TOKEN" ]]; then
    USAGE_JSON=$(curl -s --max-time 3 \
      -H "Authorization: Bearer $TOKEN" \
      -H "anthropic-beta: oauth-2025-04-20" \
      https://api.anthropic.com/api/oauth/usage 2>/dev/null || true)
    if [[ -n "$USAGE_JSON" ]]; then
      RESULT=$(USAGE_DATA="$USAGE_JSON" python3 - <<'PYEOF' 2>/dev/null
import os, json
try:
    d = json.loads(os.environ["USAGE_DATA"])
    fh = d.get("five_hour") or {}
    sd = d.get("seven_day") or {}
    fh_u = fh.get("utilization")
    sd_u = sd.get("utilization")
    fh_str = f"5h {round(fh_u)}%" if fh_u is not None else "5h n/a"
    sd_str = f"7d {round(sd_u)}%" if sd_u is not None else "7d n/a"
    print(f"{fh_str}|{sd_str}")
except Exception:
    print("5h n/a|7d n/a")
PYEOF
)
      if [[ -n "$RESULT" ]]; then
        echo "$RESULT" > "$CACHE_FILE"
        QUOTA_PART="${RESULT%%|*}"
        WEEK_PART="${RESULT##*|}"
      fi
    fi
  fi
fi

# ── Output ───────────────────────────────────────────────────────────────────
echo "${CTX_DISPLAY} | ${QUOTA_PART} | ${WEEK_PART} | ${COST_DISPLAY}"
