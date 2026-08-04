---
status: current
last_reviewed: 2026-08-04
---

# Agent guardrails — shielding secrets from Claude Code

An agent CLI such as Claude Code is a process that reads and writes your
filesystem with your own permissions. For an audit, the relevant question is
not "what did I ask the agent to do" but **"what *can* the agent do, and where
is that enforced"**.

This layer answers that with three parts: a deny-list in
`~/.claude/settings.json` for the file tools, a `PreToolUse` hook
(`common/claude-pre-tool-use.sh`) for the shell, and a checker
(`common/check-claude-guardrails.sh`) that verifies both are actually in place
and still match the canonical rule set in this repository
(`common/templates/claude-deny-secrets.json`).

## The trap that made this necessary

A deny-list that looks right but does nothing is more dangerous than no
deny-list at all, because it stops the search. This rule is exactly that:

    "Write(**/.env)"

Claude Code matches file-permission rules on `Edit(...)` — that pattern covers
every file-editing tool (Edit, Write, NotebookEdit). A `Write(...)` rule is
**not** considered during the file-permission check. It sits in your config, it
reads as though it protects `.env` files, and it blocks nothing.

The CLI does warn about this at session start, but that warning scrolls away.
Hence the checker: one command that says it out loud, every time.

## Which files, and why

| Category | Read | Write | Reason |
|---|---|---|---|
| `.env`, `.env.*` | no | no | credentials in plain text, by definition |
| `*.key`, `*_rsa` | no | no | private key material |
| `~/.ssh/`, `~/.kube/`, `~/.aws/`, `~/.gnupg/` | no | no | credential stores; a kubeconfig holds client certs and tokens |
| `*.pem` | **yes** | no | often a cert chain, just as often a private key — the extension says nothing about the contents |
| `*.crt`, `*.csr`, public keys | yes | yes | public by definition; blocking them only creates friction |

The `*.pem` split is deliberately asymmetric. Inspecting a certificate is
ordinary work; creating or modifying key material is not. Anyone who knows a
specific `.pem` holds a private key should not have an agent read it — but a
glob cannot make that judgement, and an over-tight pattern leads to
turn-it-off-and-forget.

## Two pattern forms per rule

Every rule appears twice:

    Edit(**/*.key)
    Edit(//**/*.key)

Patterns without a prefix match relative to the project directory. The `//`
prefix matches absolute paths. In a session with multiple working directories
(a cockpit repository with sibling repos next to it, say), the relative form
covers only the main directory. The double notation is redundant; a deny that
fires twice costs nothing, while a deny that silently fails to match is the bug
described above.

## The shell layer

A deny-list governs the Read/Edit tools. It says nothing about what a *command*
does: `cat ~/.env` is a Bash call and slips straight past it. That gap is closed
by `common/claude-pre-tool-use.sh`, a `PreToolUse` hook that receives every tool
call as JSON on stdin before it runs and answers with an exit code — 2 blocks,
0 allows.

The hook grades in two tiers, deliberately unequal:

- **Tier 1 — secret files** (`.env`, `*.key`, `*_rsa`, `*.p12`, `*.pfx`): any
  Bash call mentioning one is blocked. Such paths have no legitimate reason to
  appear in an agent's command.
- **Tier 2 — credential directories** (`~/.ssh`, `~/.aws`, `~/.gnupg`,
  `~/.kube`): blocked only in combination with a reading or copying verb
  (`cat`, `base64`, `cp`, `scp`, `curl`, …). Without that distinction
  `kubectl --kubeconfig ~/.kube/config get pods` would die, and that is exactly
  the legitimate case: the process reads its own config, and the contents never
  enter the model's context.

The hook also refuses to let the agent edit its own guard files — the hook
directory and any `.claude/*allowlist`. A fence the agent can move is not a
fence.

Wire it up in `~/.claude/settings.json`:

    "hooks": {
      "PreToolUse": [
        { "matcher": "", "hooks": [
          { "type": "command", "command": "/path/to/common/claude-pre-tool-use.sh" }
        ]}
      ]
    }

`bash common/claude-pre-tool-use.sh --self-test` runs 21 fixtures through the
same decision function a live call takes — both directions, because a hook that
blocks everything is as broken as one that blocks nothing.
`check-claude-guardrails.sh` reports whether the hook is registered at all and
whether the registered copy still matches the one in this repository.

## What this layer does *not* cover

- **A determined agent.** The hook sees the command string, so it catches the
  obvious forms. Variable indirection, a path assembled at runtime, or a helper
  script that reads the file will pass. This is a guardrail against accident and
  drift, not a sandbox: the agent runs with your permissions, and only the OS can
  change that.
- **Destructive commands.** `git push --force`, `kubectl delete`,
  `terraform destroy` — deliberately out of scope here. That is workstation
  policy, not a security baseline; put it in a second hook next to this one if
  you want it.
- **What the agent legitimately executes.** `kubectl get` keeps working with a
  blocked `~/.kube/`: kubectl reads its own config as a process. That is
  intended — the block only stops the credential file itself from ending up in
  the model's context.
- **Policy written as prose.** Rules in `CLAUDE.md` are instructions to the
  model, not enforcement. They are useful as explanation, but an auditor asking
  "where is that enforced" must be pointed at the deny-list.

That last point is the key maintenance rule: **prose and deny-list must say the
same thing.** Change one, change the other, in the same commit. Drifted apart
is worse than both being wrong — then the reader believes the wrong half.

## Usage

    bash common/check-claude-guardrails.sh                          # audit the current user
    bash common/check-claude-guardrails.sh --settings /path/x.json  # a different settings file
    bash common/check-claude-guardrails.sh --rules /path/r.json     # your own rule set
    bash common/claude-pre-tool-use.sh --self-test                  # verify the hook's decisions

Exit code 0 means fine, 1 means one problem, 2 means two or more (capped, so
cron/CI can work with it). A missing `jq` or an unreadable settings file also
yields 2: "could not verify" must never be reported as "fine" in an audit.

The script is read-only and installs nothing. Adding a missing rule is manual
work in `~/.claude/settings.json` — deliberately so, because that file also
holds machine-local settings (plugins, theme, hook paths) that an installer has
no business overwriting.
