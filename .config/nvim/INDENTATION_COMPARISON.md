# Indentation Setup Comparison

## Current Setup (snacks.nvim)

### Plugin
- `folke/snacks.nvim` with `indent` and `scope` modules

### What It Does
- **Visual indent guides** - Shows `│` characters at each indentation level
- **Scope highlighting** - Highlights the scope containing your cursor
- **Animations** - Smooth animated transitions when changing scopes (Neovim >= 0.10)
- **Treesitter-aware** - Detects scopes using treesitter (or indent as fallback)

### What It DOESN'T Do
- ❌ Does NOT auto-detect if a file uses tabs vs spaces
- ❌ Does NOT auto-detect indent size (2 vs 4 vs 8 spaces)
- ❌ Does NOT adapt to existing file patterns

### Default Behavior
- **All files** use your hardcoded defaults:
  - 2 spaces per indent
  - Spaces (not tabs)
  - Smart indenting enabled

## Previous Setup (guess-indent.nvim)

### Plugin
- `NMAC427/guess-indent.nvim`

### What It Did
- ✅ Auto-detected tabs vs spaces in existing files
- ✅ Auto-detected indent size (2/4/8 spaces)
- ✅ Adapted buffer settings to match file's pattern
- ✅ Fell back to your defaults for new/empty files

### What It DIDN'T Do
- ❌ No visual feedback
- ❌ No indent guides
- ❌ No scope highlighting

## Key Conflicts & Overrides

### 1. Indentation Detection
**Before (guess-indent):**
- Open a 4-space indented file → automatically uses 4 spaces
- Open a tab-indented file → automatically uses tabs
- Create new file → uses 2-space defaults

**Now (snacks.nvim):**
- Open a 4-space indented file → **still uses 2 spaces** (doesn't adapt)
- Open a tab-indented file → **still uses spaces** (doesn't adapt)
- Create new file → uses 2-space defaults ✅

### 2. Visual Display
**Before (guess-indent):**
- No visual indicators
- Relied on `listchars` to show whitespace (`→ `, `·`)

**Now (snacks.nvim):**
- Shows `│` indent guides at every level
- Highlights current scope's indent guide
- Listchars still work alongside guides

### 3. Buffer-local vs Global Settings
**Before (guess-indent):**
- Set buffer-local settings per file: `vim.bo.expandtab`, `vim.bo.shiftwidth`
- Each file could have different settings

**Now (snacks.nvim):**
- Uses global defaults only: `vim.o.expandtab`, `vim.o.shiftwidth`
- All files share the same settings

## When Each Approach Works Best

### Use snacks.nvim (current) if:
- ✅ You want visual feedback and scope awareness
- ✅ You work mostly on your own projects with consistent style
- ✅ You enforce 2-space indentation everywhere
- ✅ You want treesitter-based scope navigation
- ✅ You like animated UI elements

### Use guess-indent.nvim (previous) if:
- ✅ You work on many different codebases
- ✅ Files have inconsistent indentation styles
- ✅ You contribute to open-source with varying standards
- ✅ You want automatic adaptation without manual intervention
- ✅ You prefer minimal UI changes

### Use BOTH together if:
- ✅ You want automatic detection AND visual guides
- ✅ Best of both worlds
- ✅ Minimal conflicts (see below)

## Using Both Together (Recommended?)

Add both plugins:

```lua
{ 'NMAC427/guess-indent.nvim', opts = {} },
{
  'folke/snacks.nvim',
  priority = 1000,
  lazy = false,
  opts = {
    indent = { enabled = true },
    scope = { enabled = true },
  },
},
```

**Result:**
- guess-indent detects and sets indentation automatically
- snacks.nvim draws visual guides based on detected settings
- No conflicts (they work on different layers)

## Performance Comparison

### guess-indent.nvim
- Runs once per file on `BufReadPost`
- Minimal performance impact (~1-2ms)
- No ongoing overhead

### snacks.nvim
- Continuous rendering of indent guides
- Treesitter parsing for scope detection
- Animation overhead (if enabled)
- Higher memory usage for visual elements

## Revert Command

To switch back to guess-indent only:

```bash
cd ~/.config/nvim
git log --oneline -5  # Find the snapshot commit
git revert HEAD       # Revert the snacks.nvim change
```

Or see `SNACKS_MIGRATION.md` for manual instructions.
