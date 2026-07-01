# claude-code-statusline

A compact, color-coded status line for [Claude Code](https://claude.com/claude-code). It shows your model, context usage, location, session, PR review state, and rate limits — at a glance, on a single line.

![Status line preview](preview.svg)

> The colors and segments above are rendered exactly as they appear in your terminal. Segments only show up when Claude Code provides the data, so the line stays as short as your situation allows.

## What each segment means

| Segment | Example | Notes |
| --- | --- | --- |
| **Model + effort** | `Opus 4.8 high` | The active model and reasoning effort level. |
| **Context bar** | `██████░░░░ 62% 124k/200k` | How much of the context window is used. Bar fills left→right and shifts **gray → yellow → coral** as it climbs (≥60% yellow, ≥85% coral). |
| **Location** | `av-rx/claude-code-statusline@fix-auth` | `owner/repo` when in a git repo (with `@worktree` if applicable); otherwise the directory name. |
| **Session** | `morning-session` | The current session name, if set. |
| **PR** | `#142 ✓ approved` | Pull request number and review state: `✓ approved`, `✗ changes_requested`, `~ draft`, or `· open`. |
| **Rate limits** | `5h 88% 16:05  7d 73% Jul 3 9am` | 5-hour and 7-day usage with reset times. Percentages highlight when elevated. |

Empty segments are omitted, and the separators (` │ `) collapse accordingly.

## Pick your version

There are two identical status lines — same output, different runtime — so you can use the one that's native to your OS:

| File | For | Needs |
| --- | --- | --- |
| `statusline-command.sh` | **macOS / Linux** (and Windows via Git Bash / WSL) | `bash` + `Node.js` |
| `statusline-command.ps1` | **native Windows** — zero extra installs | PowerShell (built into Windows) |

> **Why two?** On Windows, Claude Code runs the status line through Git Bash if it's installed, otherwise through PowerShell. The bash version needs Unix tools (`bash`, `date`, `awk`) that only exist on a plain Windows box if you've installed Git for Windows or WSL. The PowerShell version needs none of that — it runs on any Windows machine as-is.

## Requirements

- **Claude Code** (the status line uses its [status line feature](https://docs.claude.com/en/docs/claude-code/statusline)).
- **macOS / Linux:** `bash` and `Node.js` on your `PATH` (Node parses the JSON Claude Code pipes to the script).
- **Windows:** nothing extra — Windows PowerShell 5.1 (built in) or PowerShell 7+ is enough.

## Install — macOS / Linux (bash)

### Easiest — let Claude Code do it

Download `install-statusline.sh`, then in a Claude Code session say:

> run install-statusline.sh to set up my status line

### Run it yourself

```bash
bash install-statusline.sh
```

This will:

1. Write the status line script to `~/.claude/statusline-command.sh`.
2. Merge a `statusLine` entry into `~/.claude/settings.json`, **preserving any existing settings** (a timestamped `.bak` backup is made first).

Then **restart Claude Code** (or open a new session) to see it. Safe to re-run.

### Manual

Copy `statusline-command.sh` to `~/.claude/statusline-command.sh`, `chmod +x` it, and add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
```

## Install — Windows (PowerShell)

### Easiest — let Claude Code do it

Download `install-statusline.ps1`, then in a Claude Code session say:

> run install-statusline.ps1 to set up my status line

### Run it yourself

```powershell
powershell -ExecutionPolicy Bypass -File install-statusline.ps1
```

This will:

1. Write the status line script to `%USERPROFILE%\.claude\statusline-command.ps1`.
2. Merge a `statusLine` entry into `%USERPROFILE%\.claude\settings.json`, **preserving any existing settings** (a timestamped `.bak` backup is made first).

Then **restart Claude Code** (or open a new session) to see it. Safe to re-run.

### Manual

Copy `statusline-command.ps1` to `%USERPROFILE%\.claude\statusline-command.ps1` and add to `settings.json` (use **forward slashes** in the path — this works whether Claude Code routes the command through Git Bash or PowerShell):

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -File C:/Users/YOU/.claude/statusline-command.ps1"
  }
}
```

## Customizing

Both scripts share the same `Colour palette` block near the top, written as [256-color ANSI codes](https://en.wikipedia.org/wiki/ANSI_escape_code#8-bit). Edit those to restyle any segment; the yellow/coral thresholds live in the bar/percentage helpers (`make_bar` / `pct_color` in bash, `New-Bar` / `Get-PctColor` in PowerShell). After editing, re-run the installer (or re-copy the file) and start a new session.

## Uninstall

Remove the `statusLine` key from your `settings.json` (restore a `.bak` if you'd like), and optionally delete the `statusline-command.*` file from your `~/.claude` (`%USERPROFILE%\.claude` on Windows).

## License

[MIT](LICENSE)
