---
status: current
last_reviewed: 2026-08-04
---

# Agent guardrails — shielding secrets from Claude Code

An agent CLI such as Claude Code is a process that reads and writes your
filesystem with your own permissions. For an audit, the relevant question is
not "what did I ask the agent to do" but **"what *can* the agent do, and where
is that enforced"**.

This layer answers that with a deny-list in `~/.claude/settings.json`, a
canonical rule set in this repository
(`common/templates/claude-deny-secrets.json`), and a checker that verifies the
two still agree (`common/check-claude-guardrails.sh`).

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

## What this layer does *not* cover

- **Shell commands.** The rules apply to the Read/Edit tools, not to what a
  process does by itself. `cat ~/.env` inside a Bash tool call is governed by
  Bash rules, not file rules. Closing that gap needs a `PreToolUse` hook that
  inspects commands — such a hook is not (yet) part of this repository.
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

Exit code 0 means fine, 1 means one problem, 2 means two or more (capped, so
cron/CI can work with it). A missing `jq` or an unreadable settings file also
yields 2: "could not verify" must never be reported as "fine" in an audit.

The script is read-only and installs nothing. Adding a missing rule is manual
work in `~/.claude/settings.json` — deliberately so, because that file also
holds machine-local settings (plugins, theme, hook paths) that an installer has
no business overwriting.
