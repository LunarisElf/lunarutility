local AssetService = game:GetService("AssetService")

local InnerUtility = require("../Shared/InnerUtility")

local AccessoryFixer = {}

-- <strong>Turns your blurry accessories into a much more clearer one. (R6)</strong>
-- Works by changing from SpecialMesh to MeshPart like R15 does.
function AccessoryFixer.Apply(Character: Model)
	for _, Accessory in Character:QueryDescendants("> Accessory") do
		local Handle: BasePart = Accessory.Handle

		if Handle:IsA("MeshPart") then
			InnerUtility.warn("AccessoryFixer", "This accessory is already converted to a mesh part. Skipping.")
			continue 
		end
		
		local SpecialMesh = Handle:FindFirstChildOfClass("SpecialMesh")

		task.spawn(function()
			local newHandle = AssetService:CreateMeshPartAsync(SpecialMesh.MeshId)
			newHandle.Name = "Handle"
			newHandle.TextureID = SpecialMesh.TextureId
			newHandle.CFrame = Handle.CFrame
			newHandle.Massless = true
			newHandle.CanCollide = false
			newHandle.Size = newHandle.Size * Character:GetScale()
			newHandle.Parent = Accessory

			local AccessoryWeld = Handle:FindFirstChild("AccessoryWeld")
			
			local weld = Instance.new("WeldConstraint")
			weld.Name = "AccessoryWeld"
			weld.Part0 = Character:FindFirstChild(AccessoryWeld.Part1.Name)
			weld.Part1 = newHandle
			weld.Parent = newHandle

			for _, Stuff in Handle:GetChildren() do
				if Stuff:IsA("Weld") then
					Stuff:Destroy()
					continue
				end
				
				Stuff.Parent = newHandle
			end
			
			Handle:Destroy()
		end)
	end
end

return AccessoryFixer