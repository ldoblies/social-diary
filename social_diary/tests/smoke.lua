-- Run from the addon folder:  /opt/homebrew/bin/luajit tests/smoke.lua
--
-- The original entry point, kept so muscle memory still works. The tests
-- now live one file per module, each against a freshly loaded addon; this
-- runs all of them through run.lua, with the same arguments.

local here = (arg and arg[0] or "tests/smoke.lua"):match("^(.*)[/\\]") or "."
dofile(here .. "/run.lua")
