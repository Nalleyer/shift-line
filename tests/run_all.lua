package.path = './src/?.lua;./src/?/init.lua;' .. package.path

local suites = {
  'tests/combat_test.lua',
  'tests/progression_test.lua',
  'tests/ui_screens_test.lua',
  'tests/i18n_test.lua',
  'tests/architecture_test.lua',
}

local passed = 0
for _, path in ipairs(suites) do
  local ok, err = xpcall(function()
    dofile(path)
  end, debug.traceback)
  if not ok then
    io.stderr:write('FAILED: ' .. path .. '\n' .. tostring(err) .. '\n')
    os.exit(1)
  end
  passed = passed + 1
end

print(string.format('ALL %d TEST SUITES PASSED', passed))
