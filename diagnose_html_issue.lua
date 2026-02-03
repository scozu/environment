-- Test HTML highlighting to identify the exact issue
vim.cmd('colorscheme karasu')

-- Create an HTML buffer
vim.cmd('new')
vim.cmd('set filetype=html')
local lines = {
  '<h1>Test H1</h1>',
  '<h2>Test H2</h2>',
  '<h3>Test H3</h3>',
  '<p>Normal text</p>',
}
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

-- Check what highlight groups are actually applied
vim.defer_fn(function()
  print("=== HTML H1 White Text Diagnosis ===")
  print("1. Traditional HTML highlight groups:")
  
  -- Check traditional syntax groups
  local html_groups = {'htmlH1', 'htmlH2', 'htmlH3', 'htmlTag', 'htmlTagName'}
  for _, group in ipairs(html_groups) do
    local success, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
    if success and next(hl) then
      print(group .. ': ' .. vim.inspect(hl))
    else
      print(group .. ': [NOT DEFINED]')
    end
  end
  
  print("\n2. TreeSitter markup groups:")
  -- Check TreeSitter groups
  local ts_groups = {'@markup.heading.1', '@markup.heading.2', '@markup.heading.3'}
  for _, group in ipairs(ts_groups) do
    local success, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
    if success and next(hl) then
      print(group .. ': ' .. vim.inspect(hl))
    else
      print(group .. ': [NOT DEFINED]')
    end
  end
  
  print("\n3. Checking actual captures in H1 text:")
  -- Check what captures are applied to the first H1
  local h1_line = lines[1]
  local text_start = h1_line:find('>') + 1
  local text_end = h1_line:find('</') - 1
  
  for pos = text_start, text_end do
    local captures = vim.treesitter.get_captures_at_pos(0, 0, pos - 1)
    if captures and #captures > 0 then
      print("H1 text captures:", vim.inspect(captures))
      break
    end
  end
  
  print("\n4. Checking highlight group links:")
  -- Check if htmlH1 links to something
  local success, hl = pcall(vim.api.nvim_get_hl, 0, { name = 'htmlH1' })
  if success and hl.link then
    print("htmlH1 links to:", hl.link)
  else
    print("htmlH1 has no link")
  end
  
  print("\n5. Treesitter active for HTML:")
  print("Treesitter active:", vim.treesitter.highlighter.active[0] and true or false)
  
  vim.cmd('qa')
end, 500)