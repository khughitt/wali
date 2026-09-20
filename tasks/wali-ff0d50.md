---
id: wali-ff0d50
title: Live-test the Noctalia panel from a worktree without repointing the installed plugin link
status: idea
priority: 2
created: 2026-09-20T00:57:17Z
updated: 2026-09-20T00:57:17Z
depends: []
tags: [noctalia]
source: session 2026-09-19 super-n debugging
agent: "claude-code/claude-opus-5[1m]"
---

On 2026-09-19 Super+N stopped working: ~/.local/share/noctalia/plugins/wali-panel
had been repointed at .worktrees/quick-edit/integrations/noctalia-plugin during the
quick-edit work, the worktree was removed after the merge, and Noctalia silently
skipped the dangling link at its next start (no log line; only the bar's
'unknown widget "khughitt/wali-panel:widget"' warning). Fixed by hand:
ln -sfn ~/d/wali/integrations/noctalia-plugin ~/.local/share/noctalia/plugins/wali-panel
then `noctalia msg plugins disable/enable khughitt/wali-panel` (plugins list rescans
manifests, but panel/widget entries only register on load).

Every worktree-based panel change repeats this. Options to scope:
- a dev copy under a distinct id (e.g. khughitt/wali-panel-dev linked to the
  worktree), so the installed link never moves; a justfile recipe to link/unlink it;
- or a `just verify`/dotfiles-health check that the installed link resolves into
  this checkout's main tree, not a worktree.
Wherever it lands, the plugin README's dev section should say how to test live.

Related observation, not this task: ~/.config/noctalia/plugins/wali-panel is a
stale dangling link to an old dotfiles path (safe to rm), and
~/.local/share/noctalia/plugins/prism is a real directory rather than the symlink
dotfiles setup.sh expects.
