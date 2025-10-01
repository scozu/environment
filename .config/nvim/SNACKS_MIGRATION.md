# Snacks.nvim Migration Notes

## Changes Made

### Removed
- `guess-indent.nvim` - Automatic indentation detection plugin

### Added
- `snacks.nvim` with `indent` and `scope` modules enabled

## Revert Instructions

To revert back to the previous setup without snacks.nvim:

```bash
cd ~/.config/nvim
git revert HEAD
```

Or manually change line ~167 in `init.lua` from:

```lua
{
  'folke/snacks.nvim',
  priority = 1000,
  lazy = false,
  opts = {
    indent = { enabled = true, ... },
    scope = { enabled = true, ... },
  },
},
```

Back to:

```lua
{ 'NMAC427/guess-indent.nvim', opts = {} },
```

## Conflicts & Overrides

### What You're Losing
1. **Automatic indentation detection** - snacks.nvim does NOT detect existing file indentation patterns like guess-indent does
2. **Adaptive tab/space behavior** - Files with different indentation won't auto-adjust

### What You're Gaining
1. **Visual indent guides** - Vertical lines showing indentation levels
2. **Scope highlighting** - Animated highlighting of current code scope (based on treesitter)
3. **Scope text objects** - `ii`, `ai` for inner/around scope
4. **Scope navigation** - `]i`, `[i` to jump between scopes

### Behavior Comparison

| Feature | guess-indent.nvim | snacks.nvim |
|---------|------------------|-------------|
| Auto-detect tabs vs spaces | ✅ Yes | ❌ No |
| Auto-detect indent size (2/4/8) | ✅ Yes | ❌ No |
| Visual indent guides | ❌ No | ✅ Yes |
| Scope highlighting | ❌ No | ✅ Yes |
| Treesitter integration | ❌ No | ✅ Yes |
| Works on existing files | ✅ Yes | ⚠️ Visual only |

### Settings That Still Work

Your default indentation settings (lines 70-74) still apply:
- `expandtab = true` - Use spaces (2 spaces per tab)
- `shiftwidth = 2` - 2-space indents
- `tabstop = 2` - Tab width of 2 spaces
- `smartindent = true` - Smart auto-indenting

**However**: These are now ALWAYS used (no automatic detection of existing patterns)

### New Visual Features

After installing snacks.nvim, you'll see:
- `│` characters showing indent levels
- Highlighted `│` for current scope
- Animated scope transitions when moving cursor

## Configuration Details

### Snacks Indent Module
- Shows indent guides as vertical bars (`│`)
- Uses `SnacksIndent` highlight group
- Priority: 1 (renders before most things)

### Snacks Scope Module  
- Highlights current scope with different color
- Uses `SnacksIndentScope` highlight group
- Priority: 200 (renders on top of indent guides)
- Treesitter-based detection (falls back to indent-based)

## Recommendation

**If you want both visual guides AND automatic detection:**

You can use both plugins together:

```lua
{ 'NMAC427/guess-indent.nvim', opts = {} },
{
  'folke/snacks.nvim',
  priority = 1000,
  lazy = false,
  opts = {
    indent = { enabled = true, ... },
    scope = { enabled = true, ... },
  },
},
```

This gives you:
- Auto-detection from guess-indent
- Visual feedback from snacks
