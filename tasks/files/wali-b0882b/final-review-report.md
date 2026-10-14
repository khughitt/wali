What this change does: It gives the four shell helpers the same resolved library and archive paths that walictl uses. The new `config show` command stays read-only, and each helper fetches settings when invoked.

Reviewer identity: **codex**. Exact model identity was not verifiable.

**Strengths**

- `.worktrees/wali-b0882b/bin/walictl:1066` reuses `load_config`, the existing error handling, and `emit`. Its payload contains exactly the two required fields. The dispatch reaches no wallpaper state or Noctalia methods.
- `.worktrees/wali-b0882b/shell/wali.zsh:85` centralizes JSON decoding for all four consumers. It validates the fields and absolute paths, rejects NUL characters, and avoids evaluating shell syntax.
- All four callers propagate config and decoding failures before their actions. Ingestion additionally rejects an absent or unavailable archive before inspecting images or prompting.
- Reprocessing keeps its explicit source argument. Searches work with an omitted archive. The configured library is used directly, without appending `/3440`.
- Scratch fixtures exercise conflicting and unset old variables, fresh config reads, quoted paths, missing archives, and failure paths. CLI tests cover the exact payload, expansion, output modes, completion, and daemon independence.

**Critical findings:** None.

**Important findings:** None.

**Minor findings:** None.

**Verification**

I traced the changed functions, their callers, parser dispatch, loader, output handling, tests, and usage documentation. An additional in-memory zsh probe confirmed that newline and shell-metacharacter paths survive decoding, null archives become empty shell values, and extra JSON fields fail. `git diff --check` passed.

Assumed load: one person invoking local shell helpers. The extra CLI and JSON-decoder processes are reasonable at that load.

**Declined to judge**

- Pending CLI inventory adoption: explicitly owned by the controller and excluded from this review.
- Real rendering, optimization, desktop previews, and other wallpaper backends: their implementation is unchanged; live execution would exceed this read-only assignment.
- Existing reprocessing removal/write ordering and search-pipeline behavior: inherited behavior without a demonstrated regression from this change.

**Assessment: Yes.** No findings require corrective changes.

Not checked: I did not rerun the suite; the controller still owns the unfiltered verification after inventory adoption. No repository, index, or task mutations were made.

Ruling: Accept. Inventory adoption receives a supplemental scoped review. Real rendering and desktop operations remain scratch-stubbed as required by the task. Existing removal/write ordering and search pipelines are outside this migration and unchanged. No minor (deferred) findings.
