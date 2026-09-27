# review-comments.nvim

Durable, location-aware review notes for Neovim.

`review-comments.nvim` lets you attach feedback to code, keep it synchronized
while code moves, review it through native quickfix/location lists, and copy it
into any agent or CLI. It deliberately has no AI provider, transport, Git host,
or prompt-format dependency.

The JSON document is durable state. Extmarks and quickfix/location lists are
live editor projections; Neovim IDs are never persistent review IDs.

## Requirements

- Neovim 0.10+
- Git
- A clipboard provider when `clipboard.register = "+"` or `"*"`

## Install with lazy.nvim

```lua
{
  "yourname/review-comments.nvim",
  main = "review_comments",
  cmd = {
    "ReviewComment", "ReviewEdit", "ReviewDelete",
    "ReviewResolve", "ReviewReopen", "ReviewRelocate",
    "ReviewCopy", "ReviewList", "ReviewStatus", "ReviewReload",
    "ReviewStart", "ReviewDiff", "ReviewClear",
    "ReviewNext", "ReviewPrevious", "ReviewJump", "ReviewListClose",
  },
  opts = {},
}
```

For a local checkout, replace the repository string with:

```lua
dir = vim.fn.expand("~/src/review-comments.nvim"),
name = "review-comments.nvim",
```

The explicit `main` is required because the Lua module is `review_comments`.

## Basic workflow

1. Select code and run `:ReviewComment`.
2. Write the note in the scratch editor and save it with `:write` or `<C-s>`.
3. Continue editing; an extmark follows the reviewed range.
4. Run `:ReviewList` when you want a navigable native-list projection.
5. Run `:ReviewCopy` and paste the provider-neutral text into any agent.
6. Resolve/delete individual notes, or `:ReviewClear` to archive the session.

Inline text is also supported:

```vim
:'<,'>ReviewComment Drop these fields; they belong on the identity object.
```

Characterwise visual selections create exact byte ranges, including multiline
ranges. Linewise selections track complete lines. Blockwise selections are
refused because they are discontiguous.

Copied exact locations use `file:line:start-end`; displayed columns are 1-based
for humans while the final value identifies the exclusive stored byte boundary.

### The comment editor

Omitting text from `:ReviewComment` or `:ReviewEdit` opens a Markdown scratch
buffer:

- `:write` or `<C-s>` validates and saves the complete multiline note.
- `:ReviewCancel` cancels; `:ReviewCancel!` also cancels a pending async save.
- `:q` cancels an unmodified draft; normal Neovim safeguards still refuse it
  after edits. `:q!` discards a modified draft. Neither leaves hidden state.
- A failed or concurrently stale edit remains open with its text intact.

The reviewed source range is captured when the editor opens. If that source
changes before a new note is saved, the operation is refused so the note cannot
silently attach to different code.

## Commands

| Command | Action |
| --- | --- |
| `:[range]ReviewComment [text]` | Add a linewise or exact-range note; open the editor when text is omitted. |
| `:ReviewEdit [text]` | Edit the selected note; open the editor when text is omitted. |
| `:ReviewDelete[!] [id]` | Confirm and delete a note; `!` skips confirmation. |
| `:ReviewResolve [id]` | Resolve a note while retaining a subdued live mark. |
| `:ReviewReopen [id]` | Return a resolved note to active status. |
| `:[range]ReviewRelocate [id]` | Confirm a candidate/orphan at a newly selected exact range. |
| `:ReviewCopy[!]` | Copy active notes; `!` includes resolved notes. |
| `:ReviewList[!]` | Open active notes; `!` includes resolved notes. |
| `:ReviewStatus` | Report the session scope and anchor-health counts. |
| `:ReviewReload[!]` | Reload disk state; `!` discards pending local anchor state. |
| `:ReviewStart[!] [base-ref]` | Start a Git-scoped session; `!` archives a non-empty current session. |
| `:ReviewDiff` | Ask the configured adapter/event listener to open the scoped diff. |
| `:ReviewClear` | Archive the current session and start an unscoped empty session. |
| `:ReviewNext` / `:ReviewPrevious` | Navigate the owned review projection safely. |
| `:ReviewJump` | Jump from the selected review-list row after source validation. |
| `:ReviewListClose` | Close the review list and restore preceding quickfix history. |

Without an explicit ID, lifecycle commands use the selected owned-list row or
the sole live note under the source cursor. Overlapping notes require selecting
a list row or supplying the stable comment ID.

## Reliable anchors

The plugin stores immutable original text and context separately from the last
trusted current text. Live extmarks track edits made in Neovim. When a file was
changed while Neovim was closed, reconciliation is conservative:

1. An unchanged file fingerprint keeps the stored exact location.
2. A globally unique exact-text match is moved and trusted.
3. Duplicate exact matches require uniquely identifying context.
4. Unique surrounding context may identify changed/expanded/contracted text,
   but the result is an untrusted candidate until explicitly relocated.
5. Ambiguous or missing locations become orphans; the plugin never guesses.

Anchor health is visible everywhere:

- Healthy notes use the normal `R` sign and region highlight.
- Context candidates use a warning region and `?` sign. They are navigable, but
  exports disclose that their location needs confirmation.
- Orphans use an `!` sign when their old file is loaded and are targetless in
  quickfix, so native navigation cannot jump to an obsolete line.
- `:ReviewRelocate` confirms a candidate/orphan while preserving its ID,
  creation time, original text, and original context.

An externally renamed file does not steal a note from an unsaved modified
buffer. Recovery waits until that local edit is saved or discarded.

### Git-aware file moves

Worktree anchors retain a Git path identity. If the stored path disappears,
the plugin first inspects Git rename records from the anchor's tracking commit.
If needed, it performs a bounded search over current tracked and non-ignored
untracked files. The destination must contain one safe exact/context match;
otherwise the note remains orphaned. Every accepted path change is retained in
anchor history. This potentially broad recovery runs at explicit command/reload
boundaries, not on every `BufWinEnter`. Snapshot notes are never repository-wide
relocated.

### Source identity

Every anchor records what its code represents:

- `{ kind = "worktree" }` for a normal file or a DiffTool side backed by the
  actual worktree path.
- `{ kind = "snapshot", side = "left"|"right", content_sha256 = "…" }` for
  an immutable/temporary comparison buffer.

Snapshot comments only attach to the matching side and buffer-content hash;
they never silently rebind to the working-tree file or another diff snapshot.
The durable `file` is always repository-relative, never a temporary filename.

Custom buffer integrations can return this source model:

```lua
resolve_target = function(ctx)
  if vim.bo[ctx.bufnr].buftype == "nofile" then
    return {
      root = "/absolute/path/to/repo",
      file = "src/generated.lua",
      source = { kind = "worktree" },
    }
  end
  return nil -- use built-in Git/DiffTool resolution
end
```

The callback receives `bufnr`, `buffer_path`, `cwd`, and optional `difftool`
metadata. `repository_root` can be a path or callback for temporary diff
buffers whose location cannot reveal their repository.

## Git-scoped review sessions

Use a Git revision to declare what is being reviewed:

```vim
:ReviewStart HEAD~1
```

The revision is resolved once with argv-safe Git invocation and stored as a
full immutable commit ID. `HEAD~1` means “that base commit to the current
worktree”, so the scope includes later manual and agent edits as well as the
last commit. The starting HEAD and branch are provenance only; moving them does
not silently change the base.

Starting over with existing comments is explicit:

```vim
:ReviewStart! origin/main
```

That archives the old session and creates the new scoped document atomically.
An invalid ref, lock, concurrent write, or storage failure leaves the old
session, marks, and review list intact.

`ReviewDiff` is intentionally an adapter hook, not a hard dependency on one
diff plugin. Configure a callback:

```lua
require("review_comments").setup({
  session = {
    open_on_start = false,
    open_diff = function(ctx)
      -- Call your preferred diff UI here.
      -- ctx.root, ctx.base_commit, ctx.head_commit, and ctx.scope are stable.
      return require("my_diff_adapter").open(ctx)
    end,
  },
})
```

Alternatively listen for `User ReviewDiffRequested`. With no callback,
`:ReviewDiff` emits that event and does nothing else.

## Quickfix ownership and DiffTool

Adding a comment never creates or activates a quickfix list. `:ReviewList` is
the explicit opt-in that materializes one. Once it exists, every successful
add/edit/delete/resolve/reopen/relocate and durable anchor update refreshes that
exact list by ID—even while another list is current—without activating it.

In normal editing, the plugin pushes and reuses one quickfix history entry
rather than replacing diagnostics/tests. Standard `:cnext`/`:cprev` work while
the review list is current. The plugin refuses operations that would truncate
newer quickfix history.

Neovim's built-in DiffTool owns global quickfix. While it is active, reviews
use a location list and never alter or advance the DiffTool list:

- `:cnext`/`:cprev` remain DiffTool file navigation.
- Every review location-list row is targetless; native `<CR>`/`:lnext` cannot
  tear apart a paired diff after it advances.
- `:ReviewJump`, `:ReviewNext`, and `:ReviewPrevious` validate the current file,
  side, owner pane, and snapshot identity before moving.
- Other-file/other-side notes remain visible but are labeled unavailable.

Run `:ReviewList` in the desired DiffTool pane after switching sides/files.
Set `list.difftool_fallback = false` to refuse listing during DiffTool.

## Persistence and concurrency

Each worktree uses:

```text
.local/review/
  current.json
  archive/
  recovery/
```

The plugin normally adds `/.local/review/` to `.git/info/exclude`, never the
repository `.gitignore`. Linked worktrees use Git's common directory.

Schema v3 stores:

- document revision plus session ID/timestamps and immutable Git scope;
- stable comment IDs, multiline review text, lifecycle state, and timestamps;
- repository-relative path plus linewise/exact byte geometry;
- immutable original text/hash/context and separate current trusted metadata;
- worktree/snapshot identity, Git path history, validity, staleness, and reason.

Writes use an exclusive `current.json.lock`, exact-byte digest compare-and-swap,
and atomic temporary-file rename. Clean sessions reload external changes at
command boundaries. A concurrent writer is never silently overwritten:
conflicting valid local state is preserved under `recovery/conflict-*.json`.
Locks are never deleted automatically.

Malformed supported-schema state is moved intact to `recovery/corrupt-*.json`.
Schema v1/v2 documents migrate to v3 only after an exact pre-migration backup.
Future schema versions are refused and left untouched. Archives use UTC
timestamp/session IDs and the same lock/CAS discipline.

## Configuration defaults

```lua
require("review_comments").setup({
  storage = {
    directory = ".local/review",
    current_file = "current.json",
    archive_directory = "archive",
    recovery_directory = "recovery",
    add_to_git_exclude = true,
  },
  context_lines = 2,
  relocation = {
    enabled = true,
    min_context_lines = 2,
    context_score_margin = 1,
    max_candidate_lines = 200,
    git_renames = true,
    file_search = true,
    max_candidate_files = 2000,
    max_file_bytes = 2 * 1024 * 1024,
  },
  clipboard = {
    register = "+",
    include_original_text = false,
    include_current_text = false,
  },
  display = {
    highlight = "ReviewCommentRegion",
    sign_highlight = "ReviewCommentSign",
    sign_text = "R",
    resolved_highlight = "ReviewCommentResolved",
    resolved_sign_highlight = "ReviewCommentResolvedSign",
    resolved_sign_text = "✓",
    candidate_highlight = "ReviewCommentCandidate",
    candidate_sign_highlight = "ReviewCommentCandidateSign",
    candidate_sign_text = "?",
    orphaned_sign_highlight = "ReviewCommentOrphanedSign",
    orphaned_sign_text = "!",
  },
  list = {
    open = true,
    height = 12,
    difftool_fallback = "loclist",
  },
  editor = {
    start_insert = true,
    spell = false,
    window = {},
  },
  session = {
    open_on_start = false,
    open_diff = nil,
  },
  notify = true,
  repository_root = nil,
  resolve_target = nil,
})
```

Default active/candidate/resolved/orphan groups link to standard Neovim groups;
override the named highlights normally.

## Lua API and events

```lua
local review = require("review_comments")

review.setup(opts)
review.add_comment({
  bufnr = 0,
  line1 = 10,
  line2 = 10,
  mode = "char",
  start_column = 4,
  end_column = 12, -- exclusive byte column
  text = "Fix this.",
})
review.edit_comment({ root = root, id = id, text = "Updated note." })
review.delete_comment({ root = root, id = id, force = true })
review.resolve_review({ root = root, id = id })
review.reopen_review({ root = root, id = id })
review.relocate_comment({ root = root, id = id, bufnr = 0, line1 = 20, line2 = 22 })

local text = review.copy({ include_resolved = false })
local kind = review.list({ include_resolved = false }) -- quickfix|loclist|nil
local counts = review.status(root)
review.reload({ root = root, force = false })

local session, archive = review.start_session({ root = root, base_ref = "HEAD~1" })
local current_session = review.get_session(root)
review.open_diff({ root = root })

review.next(); review.previous(); review.jump(); review.close_list()
local archive_path = review.clear()
local comments = review.get_comments(root) -- deep copy
```

When `text` is omitted, add/edit return an editor handle. Mutations persist a
validated candidate before replacing in-memory state, so failed writes leave
the current model/projection intact.

User events:

- `ReviewCommentsChanged` — `{ root, action, comment_id? }`
- `ReviewCommentsExported` — `{ root, count }`
- `ReviewSessionStarted` — `{ root, scope, archive_path? }`
- `ReviewDiffRequested` — `{ root, scope }`
- `ReviewSessionCleared` — `{ root, archive_path }`

Run `:checkhealth review-comments` (or `:checkhealth review_comments`) to check
configuration, Git, clipboard availability, storage state, and locks.

## Deliberate limitations

- Context candidates are never auto-promoted after their text changes; confirm
  them with `:ReviewRelocate`.
- Git/content relocation is conservative and bounded, not a fuzzy whole-repo
  search or symbol-aware refactor engine.
- Blockwise selections are unsupported.
- Quickfix/location lists are read-only projections; commands own mutations.
- There is one current session per worktree and no archive-browser UI yet.
- Concurrent sessions reload or conflict; they are not automatically merged.
- Historical snapshots require the matching buffer; non-built-in diff plugins
  may need `resolve_target`.
- There is intentionally no AI/CLI transport, spinner, or agent process manager.
