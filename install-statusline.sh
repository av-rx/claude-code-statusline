#!/usr/bin/env bash
#
# Claude Code status line installer (macOS / Linux).
#
# WHAT THIS DOES:
#   1. Writes the status line script to ~/.claude/statusline-command.sh
#   2. Adds the "statusLine" setting to ~/.claude/settings.json,
#      MERGING into any existing settings (a timestamped .bak backup is made first).
#
# HOW TO RUN IT:
#   Hand this file to Claude Code and say: "run this file to set up my status line".
#   (Or in a terminal:  bash install-statusline.sh )
#
# Safe to run more than once — it just refreshes the files.

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SCRIPT_PATH="$CLAUDE_DIR/statusline-command.sh"
SETTINGS_PATH="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR"

# ── 1. Write the status line script ───────────────────────────────────────────
cat > "$SCRIPT_PATH" <<'STATUSLINE_EOF'
#!/usr/bin/env bash
# Claude Code Status Line

input=$(cat)

# ── Colour palette ────────────────────────────────────────────────────────────
RESET="\033[0m"
DIM="\033[2m"

C_MODEL="\033[38;5;183m"      # soft lavender   — model name
C_EFFORT="\033[38;5;139m"     # dusty mauve     — effort suffix
C_BAR_NEUT="\033[38;5;248m"   # light gray      — bar fill, low usage
C_BAR_WARN="\033[38;5;221m"   # golden yellow   — bar fill, mid usage
C_BAR_CRIT="\033[38;5;210m"   # soft coral      — bar fill, high usage
C_BAR_EMPTY="\033[38;5;240m"  # dark gray       — empty bar cells
C_VALUE="\033[97m"             # bright white    — primary values
C_MUTED="\033[38;5;242m"      # dim gray        — secondary / token counts
C_LOCATION="\033[38;5;110m"   # muted sky blue  — repo / dir name
C_SESSION="\033[38;5;252m"    # near-white      — session name
C_OK="\033[38;5;150m"         # sage green      — PR approved
C_WARN="\033[38;5;221m"       # golden yellow   — open PR, mid rate limit
C_CRIT="\033[38;5;210m"       # soft coral      — changes requested, high rate limit
C_DRAFT="\033[38;5;242m"      # dim gray        — PR draft

SEP=" \033[38;5;244m│\033[0m "

# ── JSON helper ───────────────────────────────────────────────────────────────
json_get() {
    echo "$input" | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  try{
    let obj=JSON.parse(d);
    const keys='$1'.split('.');
    for(const k of keys){if(k&&obj&&typeof obj==='object')obj=obj[k];else{obj=undefined;break;}}
    if(obj!=null&&obj!==undefined)process.stdout.write(String(obj));
  }catch(e){}
});
" 2>/dev/null
}

# ── Progress bar (fills left-to-right as value increases) ────────────────────
make_bar() {
    local pct=$1 width=$2
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local color
    if   [ "$pct" -ge 85 ]; then color="$C_BAR_CRIT"
    elif [ "$pct" -ge 60 ]; then color="$C_BAR_WARN"
    else                         color="$C_BAR_NEUT"
    fi
    local bar="${color}"
    for i in $(seq 1 $filled 2>/dev/null); do bar="${bar}█"; done
    bar="${bar}${C_BAR_EMPTY}"
    for i in $(seq 1 $empty 2>/dev/null); do bar="${bar}▒"; done
    bar="${bar}${RESET}"
    printf "%b" "$bar"
}

# ── Colour for a percentage value (only highlights when elevated) ─────────────
pct_color() {
    local pct=$1
    if   [ "$pct" -ge 85 ]; then printf "%b" "$C_CRIT"
    elif [ "$pct" -ge 60 ]; then printf "%b" "$C_WARN"
    else                         printf "%b" "\033[38;5;73m"
    fi
}

# ── 1. MODEL + EFFORT ─────────────────────────────────────────────────────────
model_name=$(json_get 'model.display_name')
effort_level=$(json_get 'effort.level')

model_part=""
if [ -n "$model_name" ]; then
    model_part="${C_MODEL}${model_name}${RESET}"
    [ -n "$effort_level" ] && model_part="${model_part} ${C_EFFORT}${effort_level}${RESET}"
fi

# ── 2. CONTEXT BAR (shows how much context has been USED) ────────────────────
ctx_part=""
used_pct=$(json_get 'context_window.used_percentage')
if [ -n "$used_pct" ]; then
    used_int=$(printf "%.0f" "$used_pct")
    ctx_bar=$(make_bar "$used_int" 10)

    pct_c=$(pct_color "$used_int")

    total_input=$(json_get 'context_window.total_input_tokens')
    ctx_size=$(json_get 'context_window.context_window_size')
    token_str=""
    if [ -n "$total_input" ] && [ -n "$ctx_size" ]; then
        used_k=$(echo "$total_input $ctx_size" | awk 'function fmt(n){ if(n>=1000000){v=n/1000000; if(v==int(v)) return sprintf("%dM",v); return sprintf("%.1fM",v)} return sprintf("%dk",n/1000)}
{printf "%s/%s", fmt($1), fmt($2)}')
        token_str=" ${C_MUTED}${used_k}${RESET}"
    fi

    ctx_part="${ctx_bar} ${pct_c}${used_int}%${RESET}${token_str}"
fi

# ── 3. LOCATION ───────────────────────────────────────────────────────────────
repo_owner=$(json_get 'workspace.repo.owner')
repo_name=$(json_get 'workspace.repo.name')
project_dir=$(json_get 'workspace.project_dir')
cwd=$(json_get 'cwd')

location_part=""
if [ -n "$repo_owner" ] && [ -n "$repo_name" ]; then
    location_part="${C_MUTED}${repo_owner}/${RESET}${C_LOCATION}${repo_name}${RESET}"
    worktree=$(json_get 'workspace.git_worktree')
    [ -n "$worktree" ] && location_part="${location_part}${C_MUTED}@${worktree}${RESET}"
elif [ -n "$project_dir" ]; then
    location_part="${C_LOCATION}$(basename "$project_dir")${RESET}"
elif [ -n "$cwd" ]; then
    location_part="${C_LOCATION}$(basename "$cwd")${RESET}"
fi

# ── 4. SESSION ────────────────────────────────────────────────────────────────
session_part=""
session_name=$(json_get 'session_name')
[ -n "$session_name" ] && session_part="${C_SESSION}${session_name}${RESET}"

# ── 5. PR ─────────────────────────────────────────────────────────────────────
pr_part=""
pr_num=$(json_get 'pr.number')
if [ -n "$pr_num" ]; then
    pr_state=$(json_get 'pr.review_state')
    [ -z "$pr_state" ] && pr_state="open"
    case "$pr_state" in
        approved)           pr_color="$C_OK"    pr_label="✓" ;;
        changes_requested)  pr_color="$C_CRIT"  pr_label="✗" ;;
        draft)              pr_color="$C_DRAFT"  pr_label="~" ;;
        *)                  pr_color="$C_WARN"   pr_label="·" ;;
    esac
    pr_part="${C_MUTED}#${RESET}${pr_color}${pr_num} ${pr_label} ${pr_state}${RESET}"
fi

# ── 6. RATE LIMITS (only shown/coloured when elevated) ───────────────────────
rate_part=""
five_pct=$(json_get 'rate_limits.five_hour.used_percentage')
five_resets=$(json_get 'rate_limits.five_hour.resets_at')
week_pct=$(json_get 'rate_limits.seven_day.used_percentage')
week_resets=$(json_get 'rate_limits.seven_day.resets_at')
if [ -n "$five_pct" ] || [ -n "$week_pct" ]; then
    rate_pieces=""
    if [ -n "$five_pct" ]; then
        five_int=$(printf "%.0f" "$five_pct")
        rc=$(pct_color "$five_int")
        rate_pieces="${C_MUTED}5h ${RESET}${rc}${five_int}%${RESET}"
        if [ -n "$five_resets" ]; then
            now=$(date +%s)
            mins_left=$(( (five_resets - now + 59) / 60 ))
            if [ "$mins_left" -gt 0 ]; then
                countdown_c="$C_MUTED"
                reset_time=$(date -d "@${five_resets}" +"%H:%M" 2>/dev/null)
                [ -z "$reset_time" ] && reset_time=$(date -r "${five_resets}" +"%H:%M" 2>/dev/null)
                [ -n "$reset_time" ] && rate_pieces="${rate_pieces} ${countdown_c}${reset_time}${RESET}"
            fi
        fi
    fi
    if [ -n "$week_pct" ]; then
        week_int=$(printf "%.0f" "$week_pct")
        rc=$(pct_color "$week_int")
        [ -n "$rate_pieces" ] && rate_pieces="${rate_pieces}  "
        rate_pieces="${rate_pieces}${C_MUTED}7d ${RESET}${rc}${week_int}%${RESET}"
        if [ -n "$week_resets" ]; then
            now=$(date +%s)
            mins_left=$(( (week_resets - now + 59) / 60 ))
            if [ "$mins_left" -gt 0 ]; then
                reset_time=$(date -d "@${week_resets}" +"%b %-d %-I%p" 2>/dev/null | awk '{sub(/AM$/,"am"); sub(/PM$/,"pm"); print}')
                [ -z "$reset_time" ] && reset_time=$(date -r "${week_resets}" +"%b %e %I%p" 2>/dev/null | sed 's/  / /; s/0\([0-9][AP]M\)/\1/' | awk '{sub(/AM$/,"am"); sub(/PM$/,"pm"); print}')
                [ -n "$reset_time" ] && rate_pieces="${rate_pieces} ${C_MUTED}${reset_time}${RESET}"
            fi
        fi
    fi
    rate_part="$rate_pieces"
fi

# ── ASSEMBLE ──────────────────────────────────────────────────────────────────
parts=()
[ -n "$model_part"    ] && parts+=("$model_part")
[ -n "$ctx_part"      ] && parts+=("$ctx_part")
[ -n "$location_part" ] && parts+=("$location_part")
[ -n "$session_part"  ] && parts+=("$session_part")
[ -n "$pr_part"       ] && parts+=("$pr_part")
[ -n "$rate_part"     ] && parts+=("$rate_part")

line=""
for i in "${!parts[@]}"; do
    [ "$i" -eq 0 ] && line="${parts[$i]}" || line="${line}${SEP}${parts[$i]}"
done

printf "%b\n" "$line"
STATUSLINE_EOF

chmod +x "$SCRIPT_PATH"
echo "✓ Wrote status line script → $SCRIPT_PATH"

# ── 2. Merge the statusLine setting into settings.json (non-destructive) ──────
# Back up any existing settings first.
if [ -f "$SETTINGS_PATH" ]; then
    BACKUP_PATH="$SETTINGS_PATH.bak.$(date +%Y%m%d%H%M%S)"
    cp "$SETTINGS_PATH" "$BACKUP_PATH"
    echo "✓ Backed up existing settings → $BACKUP_PATH"
fi

node -e '
const fs = require("fs");
const p = process.argv[1];
let obj = {};
if (fs.existsSync(p)) {
  const raw = fs.readFileSync(p, "utf8");
  if (raw.trim()) {
    try { obj = JSON.parse(raw); }
    catch (e) {
      console.error("✗ Existing settings.json is not valid JSON — aborting so nothing is lost.");
      console.error("  Fix or remove " + p + " and re-run.");
      process.exit(3);
    }
  }
}
obj.statusLine = { type: "command", command: "bash ~/.claude/statusline-command.sh" };
fs.writeFileSync(p, JSON.stringify(obj, null, 2) + "\n");
' "$SETTINGS_PATH"

echo "✓ Added statusLine to → $SETTINGS_PATH"
echo ""
echo "Done. Restart Claude Code (or open a new session) to see the status line."
