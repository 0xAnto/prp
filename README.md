# prp

**Keep your pull requests moving while you're away from the keyboard.**

prp watches your GitHub repos from your own machine. When reviewers comment on your PRs, it has
[Claude Code](https://docs.claude.com/en/docs/claude-code) or [Codex CLI](https://github.com/openai/codex)
address the feedback and push the fix. When a teammate asks for your review, it drafts one. It uses
your existing checkouts and your existing CLI logins, and it calls a model only when there's real work to do.

```
$ prp run
prp 0.1.0  watching 4 repo(s) as @you
  keys: [a] add repo/folder  [n] check now  [p] pause/resume  [s] status  [q] quit
10:42:07 acme/api#212: ignored 3 item(s) without a model (acknowledgement, CI/deploy bot, thread resolved)
10:42:07 acme/api#212 "Batch settlement writes": 3 new item(s) from @alice, @bob [1 suggestion, 1 light, 1 full]
10:42:08 acme/api#212: applied 1 suggestion(s) directly
10:42:08   -> claude (fix, full tier)
10:44:51   claude finished in 163s
10:44:52 acme/api#212: pushed 9f3c2e1 to batch-settlement
10:45:30 Review requested: acme/web#88 "New onboarding flow" by @carol
10:45:31 acme/web#88: 6 file(s), 112 changed lines -> light tier
10:46:40 acme/web#88: review by codex left as a pending review (submit it on GitHub)
```

## What it does

| When… | prp… |
|---|---|
| Someone reviews **your** PR | applies GitHub `suggestion` blocks directly, has an agent handle the rest, commits, pushes to the PR branch, and replies in each thread |
| Someone **requests your review** | has an agent review the diff and leaves it as a **pending** review that only you can see until you submit it |
| Someone **@mentions** you *(optional)* | drafts an answer from the code and the thread, saved locally or posted (your choice) |

## Why run it locally

- **Your machine, your setup.** Agents run in your real checkout, with your `CLAUDE.md` / `AGENTS.md`,
  project settings, dependencies and toolchain. No CI runners and no GitHub App to install.
- **Your subscriptions.** It calls the `claude` and `codex` CLIs you're already logged in to. No API keys needed.
- **Falls back when a limit is hit.** If one agent reports a usage or rate limit, the next one takes over.

## Requirements

- macOS or Linux, Python 3.9+, git
- [GitHub CLI](https://cli.github.com), logged in (`gh auth login`)
- At least one of: [Claude Code](https://docs.claude.com/en/docs/claude-code) (`claude`) or
  [Codex CLI](https://github.com/openai/codex) (`codex`)

No Python packages to install. prp is a single file that uses only the standard library.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/0xanto/prp/main/install.sh | bash
```

This puts a `prp` command on your PATH. Run it again to update. Or install from a clone:

```bash
git clone https://github.com/0xanto/prp && cd prp && ./install.sh
```

## Quick start

```bash
cd ~/code/my-repo
prp init                    # watch this repo, add others, choose agents
prp run --once --dry-run    # show what it would act on, change nothing
prp run                     # start watching
```

Add more repos at any time. A path can be a checkout or a folder that contains checkouts:

```bash
prp add                         # the repo you're in
prp add ~/code/api ~/code/web
prp add ~/code                  # lists the checkouts inside; pick which to watch
```

While `prp run` is going, press `a` to add a repo, or run `prp add` in another terminal. The running
monitor picks it up on its next check. On macOS, prp runs `caffeinate` while it's watching so the
machine doesn't idle-sleep. A laptop on battery with the lid closed will still sleep.

## How it works

```
every poll_interval (default 2 min)
 ├─ list open PRs per repo ─── PR unchanged since last look? ── skip (no further API calls)
 │                              └─ read new comments → triage ─┬─ skip        (no model)
 │                                                             ├─ suggestion  (applied as a patch, no model)
 │                                                             ├─ light       (small model / low effort)
 │                                                             └─ full        (default model)
 ├─ search: review-requested:@you → size the diff → light / full review, lockfile-only PRs skipped
 └─ search: mentions:@you (optional)
```

**Triage is rule-based** and costs nothing. It skips "LGTM", thanks, emoji, approvals, CI and deploy bots,
resolved threads, comments addressed to someone else, and its own replies. It waits until the reviewer has
been quiet for `settle_seconds`, so a whole review becomes one agent run.

**Agents run non-interactively** (`claude -p …`, `codex exec …`) with a prompt that contains the feedback
and your instructions. This is the same agent, with the same tools and project context, as the interactive
apps. It just can't stop to wait for a person, and it exits when done. **Agents never commit or push.** prp does that after the agent finishes, so every
change goes through the same path. If the push is rejected because the branch moved, the commit is kept on a
local `prp/pr-N-unpushed` branch and you get a notification.

**Every run can be picked up interactively.** Each job gets a short id. prp records the Claude Code /
Codex session id of every agent run, so when you're back you can reopen the agent's conversation in
the full interactive app and continue from where it stopped:

```
$ prp history
  ● 12de25  Nov 03 14:24  fix     acme/api#212    Batch settlement writes     codex   pushed 9dc93e4
  ● 4b037a  Nov 03 13:02  review  acme/web#88     New onboarding flow         codex   pending review
  · 863be3  Nov 03 12:40  review  acme/web#91     Bump deps                   rules   skipped
  ● a9d7ed  Nov 03 11:15  fix     acme/api#205    Retry RPC on timeout        claude  pushed a28f066

$ prp open a9d7ed        # runs `claude --resume <session>` in the folder the agent worked in
```

**Where agents run.** By default (`workspace: auto`), if your checkout has no uncommitted changes, the
PR head is checked out *detached* in your checkout, the agent runs there, and your branch is restored
afterwards. If you have work in progress, prp uses a `git worktree` that shares your `.git` instead,
so your files are untouched and nothing is cloned again.

## Your instructions

Tell the agents how you like things done, globally or per repo:

```bash
prp prompts                     # defaults: handling feedback, reviewing, answering mentions
prp repos edit owner/repo       # per-repo additions, agent order, workspace mode, allowed tools
```

For example, per-repo fix instructions might be:

```
Run `pnpm test --filter api` before finishing.
Never edit files under db/migrations; reply asking me instead.
```

Claude Code runs with a tool allowlist. To let it run your tests unattended, add them per repo,
for example `Bash(pnpm test:*),Bash(forge test:*)`.

## Commands

```
prp                         interactive menu (offers to add the repo you're in)
prp init                    guided setup
prp add [paths...]          watch the current repo, or the checkouts / folders given
prp run [--once] [--dry-run] [--no-caffeinate]
prp history [filter]        past jobs and their agent sessions (--sessions for every attempt)
prp open [id]               reopen a job's Claude Code / Codex session interactively
prp repos                   list watched repos
prp repos edit|rm|on|off owner/repo
prp prompts                 edit default instructions
prp settings                edit settings
prp status                  agent availability and recent jobs
prp doctor                  check gh, agents and repo paths
prp cooldown-reset          mark all agents available again
```

## Configuration

Everything lives in `~/.prp/config.json` (set `PRP_HOME` to move it). The main settings:

| Setting | Default | |
|---|---|---|
| `poll_interval` | `120` | seconds between checks |
| `settle_seconds` | `90` | wait until the reviewer has been quiet this long |
| `fix_agents` / `review_agents` | `claude,codex` / `codex,claude` | tried in order; the next one is used if one hits its limit |
| `workspace` | `auto` | `auto`, `in-place` or `worktree` |
| `auto_push` | `true` | push fixes to the PR branch |
| `reply_mode` | `threads` | `threads`, `summary` or `none` |
| `review_mode` | `pending` | `pending` (only you see it), `comment` or `local` |
| `watch_mentions` / `mention_mode` | `false` / `draft` | answer @mentions; `draft` or `reply` |
| `limit_cooldown_minutes` | `60` | how long to skip an agent after it hits a limit |

Agent command lines are templates under `agents` in the config, so you can adjust flags or models
without touching the code. Placeholders: `{bin}` `{prompt}` `{cwd}` `{out}` `{allowed_tools}` `{light_args}`
`{session_id}`. The `resume` template is what `prp open` runs.

State, logs and copies of every review and mention answer are kept under `~/.prp/`
(`state.json`, `logs/`, `reviews/`, `mentions/`).

## Safety

- **Everything is posted as you**, with a "🤖 via prp" footer. Reviews default to *pending* and mention
  answers default to *draft*, so nothing reaches teammates until you decide.
- Claude Code runs with `--permission-mode acceptEdits` plus a tool allowlist, never with
  `--dangerously-skip-permissions`. Codex runs `--full-auto` for fixes and `--sandbox read-only` for reviews
  and mentions.
- Mention answers are told not to approve, commit to dates, or make decisions on your behalf.
- Comments that existed before your first `prp run` are treated as already handled.
- Fixes are skipped for PRs from forks, because prp only pushes to the repo it watches.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/0xanto/prp/main/install.sh | bash -s -- --uninstall
rm -rf ~/.prp   # optional: settings and history
```

## Contributing

Issues and PRs are welcome. prp is intentionally a single, dependency-free Python file. Please keep it
that way and keep it compatible with Python 3.9.

## License

[MIT](LICENSE)
