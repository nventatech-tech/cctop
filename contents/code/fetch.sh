#!/usr/bin/env bash
# Copyright (C) 2026 NventaTech — GPL-3.0-or-later
# cctop - multi-provider AI cost collector.
# Everything is read locally, no account setup:
#   - Claude cost: local JSONL files via ccusage
#   - Claude session/weekly limits: usage endpoint with the OAuth token the
#     Claude Code CLI already keeps in ~/.claude/.credentials.json
#   - Subscription: rate limit tier stored in ~/.claude.json
#   - OpenAI (Codex CLI) and Gemini (Gemini CLI): local log readers below,
#     dormant until the CLI is installed — provider only shows up when its
#     directory exists and has parseable usage data
export PATH="$HOME/.bun/bin:/usr/local/bin:/usr/bin:$PATH"
CREDS="$HOME/.claude/.credentials.json"
CLAUDE_CFG="$HOME/.claude.json"

# ccusage runner: bun if available, plain node otherwise
if command -v bunx >/dev/null 2>&1; then CCU="bunx ccusage"; else CCU="npx -y ccusage"; fi

# ----------------- date windows (current month + last 7 days) -----------------
since=$(date +%Y%m01)
today=$(date +%Y-%m-%d)
monthStart=$(date +%Y-%m-01)
week=$(date -d '6 days ago' +%Y%m%d)
fetchSince=$(printf '%s\n%s\n' "$since" "$week" | sort | head -1)
days=$(for i in 6 5 4 3 2 1 0; do date -d "-$i days" +%Y-%m-%d; done | jq -Rc . | jq -cs .)

# ----------------- claude cost (local logs) -----------------
daily=$($CCU daily --json --since "$fetchSince" 2>/dev/null)
[ -z "$daily" ] && daily='{}'
block=$($CCU blocks --active --json 2>/dev/null)
[ -z "$block" ] && block='{}'
claude=$(jq -cn --argjson d "$daily" --arg today "$today" --arg ms "$monthStart" '{
  id: "claude", name: "Claude", color: "#e8a33d",
  costMonth: ((($d.daily // []) | map(select(.period >= $ms) | .totalCost) | add) // 0),
  today: (($d.daily // []) | map(select(.period == $today)) | (.[0].totalCost // 0))
}')

# last 7 days, zero-filled (claude only — other providers are marginal here)
spark=$(jq -cn --argjson d "$daily" --argjson days "$days" \
  '[ $days[] as $day | {d: $day, c: ((($d.daily // []) | map(select(.period == $day) | .totalCost) | add) // 0)} ]')

# ----------------- claude live limits (local OAuth token) -----------------
live='null'
tok=$(jq -r '.claudeAiOauth.accessToken // empty' "$CREDS" 2>/dev/null)
if [ -n "$tok" ]; then
  resp=$(curl -sf --max-time 15 "https://api.anthropic.com/api/oauth/usage" \
    -H "Authorization: Bearer $tok" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "Content-Type: application/json" 2>/dev/null)
  if [ -n "$resp" ]; then
    live=$(jq -c '{
      session: {pct: (.five_hour.utilization // 0), resets_at: .five_hour.resets_at},
      weekly:  {pct: (.seven_day.utilization // 0), resets_at: .seven_day.resets_at},
      weekly_model: ((.limits // []) | map(select(.kind == "weekly_scoped")) | (.[0] // null)
                    | if . then {pct: .percent, resets_at: .resets_at} else null end)
    }' <<<"$resp" 2>/dev/null) || live='null'
  fi
fi
[ -z "$live" ] && live='null'

# ----------------- subscription (local Claude Code config) -----------------
sub='null'
tier=$(jq -r '.oauthAccount.organizationRateLimitTier // empty' "$CLAUDE_CFG" 2>/dev/null)
case "$tier" in
  *max_20x*) sub='{"name":"Claude Max 20x","price":200,"currency":"US$"}' ;;
  *max_5x*)  sub='{"name":"Claude Max 5x","price":100,"currency":"US$"}' ;;
  *pro*)     sub='{"name":"Claude Pro","price":20,"currency":"US$"}' ;;
esac

# ----------------- openai (Codex CLI local session logs) -----------------
# ~/.codex/sessions/**/rollout-*.jsonl: one token_count event per turn with
# last_token_usage {input_tokens, cached_input_tokens, output_tokens}.
# Pricing: gpt-5 family list price (in 1.25, cached 0.125, out 10.00 per M).
codex_cost() {
  find "$HOME/.codex/sessions" -name 'rollout-*.jsonl' "$@" 2>/dev/null \
    | xargs -r cat 2>/dev/null \
    | jq -s '
      [ .[] | select(.type == "event_msg" and .payload.type == "token_count")
            | .payload.info.last_token_usage | select(.) ] as $ev
      | (($ev | map(.input_tokens // 0) | add // 0) -
         ($ev | map(.cached_input_tokens // 0) | add // 0)) as $in
      | ($ev | map(.cached_input_tokens // 0) | add // 0) as $cached
      | ($ev | map(.output_tokens // 0) | add // 0) as $out
      | ($in * 1.25 + $cached * 0.125 + $out * 10) / 1000000'
}
openai='null'
if [ -d "$HOME/.codex/sessions" ]; then
  cm=$(codex_cost -newermt "$(date +%Y-%m-01)"); ctd=$(codex_cost -newermt "$today")
  if [ -n "$cm" ] && [ "$cm" != "0" ]; then
    openai=$(jq -cn --argjson c "$cm" --argjson t "${ctd:-0}" \
      '{id: "openai", name: "OpenAI", color: "#10a37f", costMonth: $c, today: $t}')
  fi
fi

# ----------------- gemini (Gemini CLI local telemetry) -----------------
# Needs telemetry enabled in the CLI (~/.gemini/telemetry.log, OTLP JSON
# lines). Token counts come as gemini_cli.token.usage data points with a
# token_type attribute. Pricing: gemini-2.5-pro list price (in 1.25, out 10 per M).
gemini='null'
if [ -s "$HOME/.gemini/telemetry.log" ]; then
  g=$(jq -s --arg today "$today" '
    [ .[] | .. | objects | select(.name? == "gemini_cli.token.usage") | .dataPoints? // [] | .[] ] as $pts
    | def total(f): [$pts[] | select(f) | (.asInt // .value // 0)] | add // 0;
      { inp: total(.attributes?[]?.value?.stringValue == "input"),
        out: total(.attributes?[]?.value?.stringValue == "output") }
    | (.inp * 1.25 + .out * 10) / 1000000' "$HOME/.gemini/telemetry.log" 2>/dev/null)
  if [ -n "$g" ] && [ "$g" != "0" ] && [ "$g" != "null" ]; then
    gemini=$(jq -cn --argjson c "$g" \
      '{id: "gemini", name: "Gemini", color: "#4285f4", costMonth: $c, today: 0}')
  fi
fi

# ----------------- session history (local logs) -----------------
hist=$($CCU session --json 2>/dev/null | jq -c '
  [ (.session // []) | sort_by(.metadata.lastActivity) | reverse | .[0:8][]
    | { last: .metadata.lastActivity, cost: .totalCost, models: (.modelsUsed // []) } ]')
[ -z "$hist" ] && hist='[]'

# ----------------- output -----------------
jq -cn --argjson c "$claude" --argjson oa "$openai" --argjson ge "$gemini" \
      --argjson b "$block" --argjson live "$live" --argjson sub "$sub" \
      --argjson h "$hist" --argjson sp "$spark" '
  ([$c] + [$oa, $ge | select(. != null)]) as $ps | {
    providers: $ps,
    totalMonth: ($ps | map(.costMonth) | add),
    totalToday: ($ps | map(.today // 0) | add),
    block: (($b.blocks // []) | .[0] // null),
    sessionModels: (($b.blocks // []) | (.[0].models // [])),
    live: $live,
    subscription: $sub,
    history: $h,
    spark: $sp
  }'
