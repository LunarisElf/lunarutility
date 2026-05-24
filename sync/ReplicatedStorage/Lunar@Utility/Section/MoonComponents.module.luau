local MoonComponents = {}

local Components = script.Parent.Parent.Shared:WaitForChild("Components")
local Vignette = Components.Vignette
local ScreenCover = Components["Screen Cover"]

function MoonComponents.GetVignette()
	return Vignette:Clone()
end

function MoonComponents.GetScreenCover()
	return ScreenCover:Clone()
end

return MoonComponents