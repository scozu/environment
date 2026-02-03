-- Check Treesitter HTML installation and syntax highlighting method
vim.defer_fn(function()
  print("=== Treesitter HTML Diagnosis ===")
  
  -- Check if HTML parser is installed
  local parsers = require('nvim-treesitter.parsers').get_parser_configs()
  print("Available parsers:", vim.tbl_keys(parsers))
  
  -- Check if HTML parser is installed
  local html_parser = require('nvim-treesitter.parsers').get_parser('html')
  print("HTML parser installed:", html_parser and true or false)
  
  -- Check if HTML treesitter highlighting is enabled
  local highlight = require('nvim-treesitter.configs').get_module('highlight')
  print("Highlight module:", highlight and vim.inspect(highlight.enable))
  print("Highlight filetypes:", highlight and vim.inspect(highlight.additional_vim_regex_highlighting))
  
  -- Check what happens with an HTML file
  vim.cmd('new')
  vim.cmd('set filetype=html')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {'<h1>Test Heading</h1>'})
  
  -- Check if treesitter highlighting is actually active for this buffer
  local ts_active = vim.treesitter.highlighter.active[0]
  print("Treesitter active in HTML buffer:", ts_active and true or false)
  
  -- Check what syntax method is being used
  local syntax_method = vim.bo.syntax
  print("Syntax setting:", syntax_method)
  
  vim.cmd('qa')
end, 100)