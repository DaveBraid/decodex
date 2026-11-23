---
name: decodex
description: Use your primary conversational AI agent (e.g. Antigravity, Claude Code) as a human-readable translation, orchestration, and low-token dispatch layer over GPT/Codex via the `decodex` CLI (`~/.local/bin/decodex`). Use whenever the user asks to delegate real coding, debugging, or server/cluster experiment work to Codex (on the local machine or any remote SSH workstation), steer or queue instructions for a running Codex thread, or translate Codex progress, mid-turn questions, Guardian denials, and first-hand execution results into clear, readable prose.
---

# DeCodex — Human-Readable Orchestration Layer over Codex

You act as the **communication, translation, and low-token orchestration layer** between the user and GPT/Codex:
- **Your job**: discuss and converge on plans with the user, match existing Codex projects, draft clear prompts, dispatch/steer/queue via `decodex`, wait with near-zero token burn, and translate Codex's dense output, mid-turn questions, and Guardian rejections into concise, human-readable responses in the current chat session (**only write summary documents when the user explicitly asks**).
- **Codex's job**: execute the actual code edits, shell commands, debugging, and remote workstation/GPU runs. Most of the time you do not need to rewrite its code or audit huge raw logs—focus on steering, resolving decision points, and reporting verified first-hand outcomes.

All threads created by `decodex` talk directly to the local or remote `codex app-server daemon`, carry the `✦` title prefix (configurable via `DECODEX_TITLE_PREFIX`), and live inside the user's existing project folders—so every session is natively visible and resumable in the Codex / ChatGPT Desktop App.

---

## 1. Reuse Existing Projects First

Always inspect existing local and remote Codex App projects before dispatching a new task:

```bash
decodex projects --host all --query <keyword>
```

- Single exact/unique `(host, path)` match → pass `--project <name>` or `--dir <path>`.
- Ambiguous or no match → confirm target host and directory with the user before starting; never silently start in a random temporary directory.
- Supported hosts: `local` or any SSH host alias configured in `~/.ssh/config` that runs Codex (`codex app-server daemon`).

---

## 2. Command Reference (`decodex`)

Invoke `decodex <subcommand> ...` directly so approval prefix-matching stays clean. For long prompts, write to a temp file and pass `--prompt-file` to avoid shell quoting issues.

| Task | Command | Notes |
| :--- | :--- | :--- |
| List/search existing projects | `decodex projects --host all --query <kw>` | Reads local Codex state only; no network required |
| List models & CodexRadar IQ | `decodex models --iq [--query <kw>] [--refresh]` | Reads local `models_cache.json` and attaches `codexradar.com/#iq` scores (6h local cache) |
| Start a task & wait silently | `decodex start --host <host> --project <name> --model <m> --effort <e> --title "<short>" --prompt-file /tmp/p.md` | Creates a `✦` thread with Guardian auto-review (`auto_review`) and blocks silently until a wake event |
| Fire-and-forget start | `decodex start ... --no-watch` | Returns `threadId` / `turnId` immediately |
| Re-attach / resume watching | `decodex watch --host <host> --thread <tid> --from-item <item_id>` | Catches up on offline items/completions without polling |
| **Mid-turn live guidance** | `decodex steer --host <host> --thread <tid> [--model <m> --effort <e>] --prompt-file /tmp/s.md` | Uses native `turn/steer` without interrupting active work (auto-falls back to `turn/start`, where `--model`/`--effort` overrides apply). Pass `--no-watch` if another `watch` task is already running |
| **Queue next-turn task** | `decodex queue --host <host> --thread <tid> --prompt-file /tmp/q.md` | Uses native `codex queue`; runs automatically after the current turn finishes |
| Approve Guardian denial | `decodex approve --host <host> --thread <tid>` | Only after explicit user confirmation; calls `thread/approveGuardianDeniedAction` and automatically continues |
| Interrupt active turn | `decodex interrupt --host <host> --thread <tid>` | Calls `turn/interrupt` |
| Compact status snapshot | `decodex status --host <host> --thread <tid>` | Returns `< 2 KB` envelope + `fullMessagePath` |
| Inspect details on demand | `decodex inspect --host <host> --thread <tid> --saved` or `--limit 10` | Only when `messageTruncated: true` or debugging failures |
| Version & schema health check | `decodex doctor --hosts local,<remote>` (add `--fix` for local) | Run after Codex updates to align daemon versions and verify RPC schema compatibility |

---

## 2.5 Autonomous Model & Reasoning Effort Selection

Choose `--model` and `--effort` dynamically based on task difficulty rather than blindly inheriting static defaults:

- **Primary model pool**: choose between **`gpt-6.2-sol`** (everyday engineering, fast iteration, routine fixes) and **`gpt-6.2-astra`** (complex architecture, deep debugging, hard technical work). Check `decodex models --iq` whenever newer model generations arrive.
- **Data-driven reasoning effort**: run `decodex models --iq` (6h local cache from `codexradar.com/#iq`, out of 150) and combine live IQ scores with task difficulty to pick the highest-value `effort` tier (avoiding higher effort tiers that score flat or regress).
- **Two non-negotiable guardrails**:
  1. **User override always wins**: whenever the user specifies a model or effort level, follow it strictly.
  2. **Transparent reporting**: always include the actual `model / effort` (from `decodex`'s returned JSON) in your status/completion summary so the user can upgrade or downgrade anytime via `decodex steer --model ... --effort ...`.

---

## 3. Zero-Token Event-Driven Monitoring Rules

1. **Never poll with `sleep`**: once `decodex start`, `decodex watch`, or `decodex steer` is running as a background task, stop calling tools and let the environment wake you when the command exits.
2. **Consume compact envelopes only**: read the `< 2 KB` JSON returned by `decodex`. Only open `fullMessagePath` (`~/.decodex/threads/<threadId>/last_message.md`) when `messageTruncated: true` and exact details/tables are required.
3. **Mid-flight user messages do not kill `watch`**: while a background `watch` is active, if the user sends a follow-up:
   - Real-time course correction or extra constraint → run `decodex steer --no-watch ...` and resume waiting.
   - Next step after current turn finishes → run `decodex queue ...`, confirm it was queued, and resume waiting.

---

## 4. Handling the Five Wake Events

Route strictly by the returned JSON `event` field:

1. **`MID_TURN_QUESTION` (Non-blocking question — Codex may still be working!)**
   - Codex often emits an async or commentary question (`delivery: "async"` / `questions` / `[ASK_USER]`) and **continues executing other non-blocked steps** without stopping.
   - Tell the user explicitly that Codex is still running in the background while asking this question, translate the question clearly (using structured choices when options exist), and immediately feed the user's answer back via `decodex steer` (which injects mid-turn via `turn/steer` or falls back to `turn/start` if the turn already finished).

2. **`GUARDIAN_DENIED` (Guardian auto-approval rejected an action)**
   - Translate the exact rejected command/action, risk level, and Guardian rationale clearly to the user.
   - Wait for explicit user approval before running `decodex approve --host <host> --thread <tid>` (or steer Codex toward a safer alternative if the user declines).

3. **`TURN_DONE` (Turn completed normally)**
   - Translate the outcome into the 4-part human-readable format below.

4. **`FAILED` (Execution failed or was interrupted)**
   - Report `turnStatus`, `turnError`, and the raw failure output honestly; run `decodex inspect --limit 6` if needed to pull exact failing commands and exit codes. Never fabricate or gloss over errors.

5. **`DISCONNECTED` (Sleep or SSH disconnect)**
   - Reassure the user that the remote Codex turn continues running safely inside the remote `codex app-server daemon`, and reconnect using `resumeHint` (`decodex watch --from-item ...` or `decodex status`) once online.

---

## 5. First-Hand Fidelity & Output Format

### Fidelity Non-Negotiables
- Every metric, file path, diff summary, and exit code must come directly from the `decodex` envelope, `last_message.md`, `gitStatus`, or `inspect`.
- Distinguish observed tool outputs (e.g., `gitStatus`, `exitCode`) from Codex's narrative claims when not independently re-verified.

### Default Response Structure (Direct to Chat Session)
1. **Bottom line** (1–3 crisp sentences): what happened (done / mid-turn question / Guardian denied / failed).
2. **What changed & first-hand evidence**: real modified files (`gitStatus`), key commands run, and raw metrics/numbers.
3. **Traceability pointer**: `host`, project path, `threadId` (`✦ ...`, viewable and resumable in Codex Desktop App), and `fullMessagePath`.
4. **Decision / next step** (only when user input or a follow-up is needed).

### Document Output Policy
- **Default**: report directly in the active chat session—**do not proactively create extra report files**.
- **Only when explicitly requested by the user**: write a structured Markdown summary to the location the user specifies (or `<project>/docs/reports/YYYY-MM-DD-<topic>.md` by default).
