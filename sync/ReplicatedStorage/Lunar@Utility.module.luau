--!nocheck
local LunarUtility = {}

--[[

-# Lunar Utility @v3.0.0-unreleased
-- unfinished and unreleased - expect lots of changes and more compatibility support

--]]

local Typecheck = require(script.Shared.Typecheck)
local MoonPlayer = require(script.Section.MoonPlayer)

LunarUtility.MoonPlayer = MoonPlayer :: Typecheck.MoonPlayer

return LunarUtility