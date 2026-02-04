-- Globals
-- Leader keys
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Nerd Font installed in terminal
vim.g.have_nerd_font = true

-- Options

-- Line numbers
vim.o.number = true
vim.o.relativenumber = true

-- Mouse support (e.g. resize splits)
vim.o.mouse = 'a'

-- True color
vim.o.termguicolors = true

-- Statusline shows mode
vim.o.showmode = false

-- OS clipboard sync after UI enter (avoid startup cost)
vim.schedule(function()
  vim.o.clipboard = 'unnamedplus'
end)

-- Wrapped lines keep indent
vim.o.breakindent = true

-- Persistent undo
vim.o.undofile = true

-- Smartcase search
vim.o.ignorecase = true
vim.o.smartcase = true

-- Always show signcolumn
vim.o.signcolumn = 'yes'

-- Faster updates
vim.o.updatetime = 250

-- Faster mapped sequence timeout
vim.o.timeoutlen = 300

-- Open splits right/below
vim.o.splitright = true
vim.o.splitbelow = true

-- Visible whitespace
vim.o.list = true
vim.opt.listchars = { tab = '→ ', trail = '·', nbsp = '␣' }

-- Default indentation (4 spaces)
vim.o.expandtab = true
vim.o.shiftwidth = 4
vim.o.tabstop = 4
vim.o.smartindent = true

-- Live substitution preview
vim.o.inccommand = 'split'

-- Highlight cursor line
vim.o.cursorline = true

-- Keep context around cursor
vim.o.scrolloff = 10

-- Confirm before abandoning changes
vim.o.confirm = true

-- Keymaps

-- Clear search highlights
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Diagnostics
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })

-- Easier terminal escape (may not work in all terminals)
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- Ctrl+hjkl window navigation
vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

-- Autocommands

-- Highlight on yank
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.hl.on_yank()
  end,
})

-- Plugins
-- Manage with :Lazy
-- Specs: 'owner/repo', opts, config, dependencies

-- Install `lazy.nvim`
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
  if vim.v.shell_error ~= 0 then
    error('Error cloning lazy.nvim:\n' .. out)
  end
end

-- Add `lazypath` to beginning of runtime path
---@type vim.Option
local rtp = vim.opt.rtp
rtp:prepend(lazypath)

require('lazy').setup({

  {
    'windwp/nvim-ts-autotag',
    event = 'InsertEnter',
    opts = {},
  },

  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    opts = {
      indent = {
        enabled = true,
        animate = { enabled = false },
      },
      dashboard = {
        enabled = true,
        preset = {
          header = [[
                           
                           
 /'\,  /'\  /'\\ /\\ \\ \\ 
||_.  ||   || ||  /  || || 
 ~ || ||   || || /\\ || || 
,-_-  \\,/ \\,/   || \\/\\ 
                  /        
                 (,        
]],
          formats = {
            header = { '%s', align = 'center', hl = 'SnacksDashboardHeader' },
            icon = function(item)
              return { item.icon, width = 2, hl = 'SnacksDashboardIcon' }
            end,
            key = { '[%s]', hl = 'SnacksDashboardKey' },
            desc = { '%s', hl = 'SnacksDashboardDesc' },
            footer = { '%s', align = 'center', hl = 'SnacksDashboardFooter' },
          },
          keys = {
            { icon = ' ', key = 'f', desc = 'Find File', action = ':Telescope find_files' },
            { icon = ' ', key = 'n', desc = 'Notebook', action = ':cd ~/Documents/notebook | Telescope find_files' },
            { icon = ' ', key = 'g', desc = 'Find Text', action = ':Telescope live_grep' },
            { icon = ' ', key = 'r', desc = 'Recent Files', action = ':Telescope oldfiles' },
            { icon = ' ', key = 'c', desc = 'Config', action = ':e $MYVIMRC' },
            { icon = ' ', key = 'q', desc = 'Quit', action = ':qa' },
          },
        },
        sections = {
          { section = 'header' },
          { section = 'keys', gap = 1, padding = 1 },
          { section = 'startup' },
        },
        win = {
          winhighlight = 'Normal:SnacksDashboardNormal,NormalFloat:SnacksDashboardNormal',
          border = 'rounded',
        },
      },
    },
  },

  { -- Git signs + hunk actions
    'lewis6991/gitsigns.nvim',
    opts = {
      signs = {
        add = { text = '+' },
        change = { text = '~' },
        delete = { text = '_' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
      },
    },
  },

  { -- Keybinding hints
    'folke/which-key.nvim',
    event = 'VimEnter',
    opts = {
      delay = 0,
      icons = {
        -- Enable icon mappings if Nerd Font is present
        mappings = vim.g.have_nerd_font,
        -- Use Nerd Font icons or fallback text
        keys = vim.g.have_nerd_font and {} or {
          Up = '<Up> ',
          Down = '<Down> ',
          Left = '<Left> ',
          Right = '<Right> ',
          C = '<C-…> ',
          M = '<M-…> ',
          D = '<D-…> ',
          S = '<S-…> ',
          CR = '<CR> ',
          Esc = '<Esc> ',
          ScrollWheelDown = '<ScrollWheelDown> ',
          ScrollWheelUp = '<ScrollWheelUp> ',
          NL = '<NL> ',
          BS = '<BS> ',
          Space = '<Space> ',
          Tab = '<Tab> ',
          F1 = '<F1>',
          F2 = '<F2>',
          F3 = '<F3>',
          F4 = '<F4>',
          F5 = '<F5>',
          F6 = '<F6>',
          F7 = '<F7>',
          F8 = '<F8>',
          F9 = '<F9>',
          F10 = '<F10>',
          F11 = '<F11>',
          F12 = '<F12>',
        },
      },

      -- Group labels
      spec = {
        { '<leader>s', group = '[S]earch' },
        { '<leader>t', group = '[T]oggle' },
        { '<leader>h', group = 'Git [H]unk', mode = { 'n', 'v' } },
      },
    },
  },

  { -- Fuzzy Finder (files, lsp, etc)
    'nvim-telescope/telescope.nvim',
    event = 'VimEnter',
    dependencies = {
      'nvim-lua/plenary.nvim',
      { -- Native fzf sorter
        'nvim-telescope/telescope-fzf-native.nvim',
        build = 'make',
        cond = function()
          return vim.fn.executable 'make' == 1
        end,
      },
      { 'nvim-telescope/telescope-ui-select.nvim' },

      -- Icons (Nerd Font)
      { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
    },
    config = function()
      -- Telescope setup and keymaps
      -- See :help telescope and :help telescope.setup()
      require('telescope').setup {
        -- defaults = { mappings = { i = { ['<c-enter>'] = 'to_fuzzy_refine' } } },
        extensions = {
          ['ui-select'] = {
            require('telescope.themes').get_dropdown(),
          },
        },
      }

      -- Enable extensions if installed
      pcall(require('telescope').load_extension, 'fzf')
      pcall(require('telescope').load_extension, 'ui-select')

      -- Builtins
      local builtin = require 'telescope.builtin'
      vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
      vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
      vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = '[S]earch [F]iles' })
      vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = '[S]earch [S]elect Telescope' })
      vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
      vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = '[S]earch by [G]rep' })
      vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
      vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
      vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[S]earch Recent Files ("." for repeat)' })
      vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })

      -- Current buffer search
      vim.keymap.set('n', '<leader>/', function()
        builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
          winblend = 10,
          previewer = false,
        })
      end, { desc = '[/] Fuzzily search in current buffer' })

      -- Live grep in open files
      vim.keymap.set('n', '<leader>s/', function()
        builtin.live_grep {
          grep_open_files = true,
          prompt_title = 'Live Grep in Open Files',
        }
      end, { desc = '[S]earch [/] in Open Files' })

      -- Search Neovim config
      vim.keymap.set('n', '<leader>sn', function()
        builtin.find_files { cwd = vim.fn.stdpath 'config' }
      end, { desc = '[S]earch [N]eovim files' })
    end,
  },

  -- LSP Plugins
  {
    -- Lua LSP extras for Neovim config
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {
      library = {
        -- Load luvit types when `vim.uv` appears
        { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
      },
    },
  },
  {
    -- Main LSP Configuration
    'neovim/nvim-lspconfig',
    dependencies = {
      -- Mason bootstrap
      { 'mason-org/mason.nvim', opts = {} },
      'mason-org/mason-lspconfig.nvim',
      'WhoIsSethDaniel/mason-tool-installer.nvim',

      -- LSP status
      { 'j-hui/fidget.nvim', opts = {} },

      -- Extra capabilities from blink.cmp
      'saghen/blink.cmp',
    },
    config = function()
      -- LSP attach: buffer-local keymaps and features
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
        callback = function(event)
          -- Helper for buffer-local LSP maps
          local map = function(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end

          -- Rename symbol
          map('grn', vim.lsp.buf.rename, '[R]e[n]ame')

          -- Code action
          map('gra', vim.lsp.buf.code_action, '[G]oto Code [A]ction', { 'n', 'x' })

          -- References
          map('grr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')

          -- Implementation
          map('gri', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')

          -- Definition
          map('grd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')

          -- Declaration (e.g. C headers)
          map('grD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

          -- Document symbols
          map('gO', require('telescope.builtin').lsp_document_symbols, 'Open Document Symbols')

          -- Workspace symbols
          map('gW', require('telescope.builtin').lsp_dynamic_workspace_symbols, 'Open Workspace Symbols')

          -- Type definition
          map('grt', require('telescope.builtin').lsp_type_definitions, '[G]oto [T]ype Definition')

          -- Normalize method support across Neovim 0.10/0.11
          ---@param client vim.lsp.Client
          ---@param method vim.lsp.protocol.Method
          ---@param bufnr? integer some lsp support methods only in specific files
          ---@return boolean
          local function client_supports_method(client, method, bufnr)
            if vim.fn.has 'nvim-0.11' == 1 then
              return client:supports_method(method, bufnr)
            else
              return client.supports_method(method, { bufnr = bufnr })
            end
          end

          -- Highlight symbol under cursor; clear on move
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client_supports_method(client, vim.lsp.protocol.Methods.textDocument_documentHighlight, event.buf) then
            local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.document_highlight,
            })

            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.clear_references,
            })

            vim.api.nvim_create_autocmd('LspDetach', {
              group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
              callback = function(event2)
                vim.lsp.buf.clear_references()
                vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
              end,
            })
          end

          -- Toggle inlay hints (if supported)
          if client and client_supports_method(client, vim.lsp.protocol.Methods.textDocument_inlayHint, event.buf) then
            map('<leader>th', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
            end, '[T]oggle Inlay [H]ints')
          end
        end,
      })

      -- Diagnostic config
      vim.diagnostic.config {
        severity_sort = true,
        float = { border = 'rounded', source = 'if_many' },
        underline = { severity = vim.diagnostic.severity.ERROR },
        signs = vim.g.have_nerd_font and {
          text = {
            [vim.diagnostic.severity.ERROR] = '󰅚 ',
            [vim.diagnostic.severity.WARN] = '󰀪 ',
            [vim.diagnostic.severity.INFO] = '󰋽 ',
            [vim.diagnostic.severity.HINT] = '󰌶 ',
          },
        } or {},
        virtual_text = {
          source = 'if_many',
          spacing = 2,
          format = function(diagnostic)
            local diagnostic_message = {
              [vim.diagnostic.severity.ERROR] = diagnostic.message,
              [vim.diagnostic.severity.WARN] = diagnostic.message,
              [vim.diagnostic.severity.INFO] = diagnostic.message,
              [vim.diagnostic.severity.HINT] = diagnostic.message,
            }
            return diagnostic_message[diagnostic.severity]
          end,
        },
      }

      -- Extend LSP capabilities with blink.cmp
      local capabilities = require('blink.cmp').get_lsp_capabilities()

      -- LSP servers to install/configure
      local servers = {
        -- clangd = {},
        -- gopls = {},
        -- pyright = {},
        -- rust_analyzer = {},
        -- ... See :help lspconfig-all for more servers
        -- ts_ls = {},
        --

        tailwindcss = {
          -- filetypes = { 'html', 'css', 'scss', 'javascript', 'typescript', 'javascriptreact', 'typescriptreact', 'vue', 'svelte', 'astro' },
          settings = {
            tailwindCSS = {
              -- Include additional filetypes
              includeLanguages = {
                elixir = 'html-eex',
                eelixir = 'html-eex',
                heex = 'html-eex',
              },
              -- Exclude filetypes from Tailwind CSS IntelliSense
              -- filetypes_exclude = { "markdown" },
              -- Show pixel equivalents for rem values
              showPixelEquivalents = true,
              -- Root font size for pixel conversion
              rootFontSize = 16,
              -- Enable hover previews
              hovers = true,
              -- Enable suggestions
              suggestions = true,
              -- Enable code actions
              codeActions = true,
              -- Enable validation/linting
              validate = true,
            },
          },
        },

        lua_ls = {
          -- cmd = { ... },
          -- filetypes = { ... },
          -- capabilities = {},
          settings = {
            Lua = {
              completion = {
                callSnippet = 'Replace',
              },
              -- You can toggle below to ignore Lua_LS's noisy `missing-fields` warnings
              -- diagnostics = { disable = { 'missing-fields' } },
            },
          },
        },
      }

      -- Ensure servers/tools above are installed (:Mason)
      local ensure_installed = vim.tbl_keys(servers or {})
      vim.list_extend(ensure_installed, {
        'stylua', -- Used to format Lua code
        'prettier', -- Used to format CSS, JavaScript, TypeScript, and other web files
      })
      require('mason-tool-installer').setup { ensure_installed = ensure_installed }

      require('mason-lspconfig').setup {
        ensure_installed = {}, -- explicitly set to an empty table (Kickstart populates installs via mason-tool-installer)
        automatic_installation = false,
        handlers = {
          function(server_name)
            local server = servers[server_name] or {}
            -- Only override values explicitly set above
            server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})
            require('lspconfig')[server_name].setup(server)
          end,
        },
      }
    end,
  },

  { -- Autoformat
    'stevearc/conform.nvim',
    event = { 'BufWritePre' },
    cmd = { 'ConformInfo' },
    keys = {
      {
        '<leader>f',
        function()
          require('conform').format { async = true, lsp_format = 'fallback' }
        end,
        mode = '',
        desc = '[F]ormat buffer',
      },
    },
    opts = {
      notify_on_error = false,
      format_on_save = function(bufnr)
        -- Skip LSP fallback for languages without a standard style
        local disable_filetypes = { c = true, cpp = true }
        if disable_filetypes[vim.bo[bufnr].filetype] then
          return nil
        else
          return {
            timeout_ms = 500,
            lsp_format = 'fallback',
          }
        end
      end,
      formatters_by_ft = {
        lua = { 'stylua' },
        -- Example:
        -- python = { 'isort', 'black' },
        css = { 'prettier' },
        scss = { 'prettier' },
        javascript = { 'prettier' },
        typescript = { 'prettier' },
        javascriptreact = { 'prettier' },
        typescriptreact = { 'prettier' },
        html = { 'prettier' },
        vue = { 'prettier' },
        svelte = { 'prettier' },
        astro = { 'prettier' },
      },
      formatters = {
        prettier = {
          prepend_args = { '--tab-width', '4' },
        },
      },
    },
  },

  { -- Autocompletion
    'saghen/blink.cmp',
    event = 'VimEnter',
    version = '1.*',
    dependencies = {
      -- Snippet Engine
      {
        'L3MON4D3/LuaSnip',
        version = '2.*',
        build = (function()
          -- Build for regex snippets (skip on Windows/no make)
          if vim.fn.has 'win32' == 1 or vim.fn.executable 'make' == 0 then
            return
          end
          return 'make install_jsregexp'
        end)(),
        dependencies = {
          -- Optional: friendly-snippets
          -- {
          --   'rafamadriz/friendly-snippets',
          --   config = function()
          --     require('luasnip.loaders.from_vscode').lazy_load()
          --   end,
          -- },
        },
        opts = {},
      },
      'folke/lazydev.nvim',
    },
    --- @module 'blink.cmp'
    --- @type blink.cmp.Config
    opts = {
      keymap = {
        -- Preset: 'default' (recommended), 'super-tab', 'enter', 'none'
        -- See :h blink-cmp-config-keymap for custom mappings
        preset = 'default',

        -- LuaSnip keymaps: see README
      },

      appearance = {
        -- Nerd Font variant: 'mono' or 'normal'
        nerd_font_variant = 'mono',
      },

      completion = {
        -- Docs popup behavior
        documentation = { auto_show = false, auto_show_delay_ms = 500 },
      },

      sources = {
        default = { 'lsp', 'path', 'snippets', 'lazydev' },
        providers = {
          lazydev = { module = 'lazydev.integrations.blink', score_offset = 100 },
        },
      },

      snippets = { preset = 'luasnip' },

      -- Fuzzy matcher: 'lua' or 'prefer_rust_with_warning'
      fuzzy = { implementation = 'lua' },

      -- Signature help
      signature = { enabled = true },
    },
  },

  {
    -- Color Settings
    -- Karasu colorscheme (local)
    dir = '/Users/scozu/Developer/karasu',
    name = 'karasu',
    lazy = false,
    priority = 1000,
    config = function()
      require('karasu').setup { mode = 'night' }
    end,
  },

  {
    -- Auto Dark Mode to switch Karasu with system settings
    'f-person/auto-dark-mode.nvim',
    lazy = false,
    config = function()
      local auto_dark_mode = require 'auto-dark-mode'

      auto_dark_mode.setup {
        update_interval = 100, -- Check every .1 second
        set_dark_mode = function()
          vim.o.background = 'dark'
          vim.cmd.colorscheme 'karasu-night'
        end,
        set_light_mode = function()
          vim.o.background = 'light'
          vim.cmd.colorscheme 'karasu-snow'
        end,
      }

      auto_dark_mode.init()
    end,
  },

  -- Highlight todo, notes, etc in comments
  { 'folke/todo-comments.nvim', event = 'VimEnter', dependencies = { 'nvim-lua/plenary.nvim' }, opts = { signs = false } },

  { -- Collection of various small independent plugins/modules
    'echasnovski/mini.nvim',
    config = function()
      -- Textobjects
      require('mini.ai').setup { n_lines = 500 }

      -- Surround actions
      require('mini.surround').setup()

      -- Statusline
      local statusline = require 'mini.statusline'
      statusline.setup { use_icons = vim.g.have_nerd_font }

      -- Cursor location format
      ---@diagnostic disable-next-line: duplicate-set-field
      statusline.section_location = function()
        return '%2l:%-2v'
      end
    end,
  },
  { -- Highlight, edit, and navigate code
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    main = 'nvim-treesitter.configs', -- Sets main module to use for opts
    -- Treesitter config
    opts = {
      ensure_installed = {
        'bash',
        'c',
        'diff',
        'html',
        'lua',
        'luadoc',
        'markdown',
        'markdown_inline',
        'query',
        'vim',
        'vimdoc',
        'css',
        'scss',
        'javascript',
        'typescript',
        'tsx',
      },
      -- Auto-install missing parsers
      auto_install = true,
      highlight = {
        enable = true,
        -- Keep regex highlights for Ruby indenting
        additional_vim_regex_highlighting = { 'ruby' },
      },
      indent = { enable = true, disable = { 'ruby' } },
    },
  },

  -- Optional Kickstart modules (uncomment to enable)
  -- require 'kickstart.plugins.debug',
  -- require 'kickstart.plugins.indent_line',
  -- require 'kickstart.plugins.lint',
  require 'kickstart.plugins.autopairs',
  -- require 'kickstart.plugins.neo-tree',
  -- require 'kickstart.plugins.gitsigns', -- adds gitsigns recommend keymaps

  -- Optional: load `lua/custom/plugins/*.lua`
  { import = 'custom.plugins' },
}, {
  ui = {
    -- Nerd Font icons or unicode fallback
    icons = vim.g.have_nerd_font and {} or {
      cmd = '⌘',
      config = '🛠',
      event = '📅',
      ft = '📂',
      init = '⚙',
      keys = '🗝',
      plugin = '🔌',
      runtime = '💻',
      require = '🌙',
      source = '📄',
      start = '🚀',
      task = '📌',
      lazy = '💤 ',
    },
  },
})

-- Modeline
-- vim: ts=4 sts=4 sw=4 et
