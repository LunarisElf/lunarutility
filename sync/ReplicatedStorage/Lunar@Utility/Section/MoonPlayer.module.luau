--!optimize 2

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

-- // Dependencies
local Signal = require("../Dependencies/Signal")
local EasingFunctions = require("../Dependencies/EasingFunctions")

-- // Shared
local InnerUtility = require("../Shared/InnerUtility")
local TypeCheck = require("../Shared/Typecheck")

-- // Section
local MoonComponents = require("../Section/MoonComponents")

type MoonPlayer = TypeCheck.MoonPlayer

local MoonPlayer = {}
MoonPlayer.__index = MoonPlayer

local function LerpVignette(vignette: ImageLabel, property: any, lerp: any)
	vignette[property] = lerp
	vignette["LL"][property] = lerp
	vignette["UR"][property] = lerp
	vignette["LL"]["LR"][property] = lerp
end

-- // new MA2 format bakes every frame into Values as separate children, old format only ever has "0"
local function IsNewBakedFormat(keyframeFolder: Folder): boolean
	local valuesFolder = keyframeFolder:FindFirstChild("Values")
	if not valuesFolder then return false end
	return valuesFolder:FindFirstChild("1") ~= nil
end

function MoonPlayer.new()
	local self = setmetatable({}, MoonPlayer)
	self.TimePosition = 0
	self.TrackPosition = 0
	self.FrameRate = 60
	self.IsPlaying = false
	self.Camera = workspace.CurrentCamera
	self.Properties = {
		Debug = false,
		AutoComponents = true,
		RootPart = nil,
		AttachedCamera = nil,
		AutoCamType = false
	}

	self._Cache = {
		Keyframe = {},
		ReKeyframe = {},
		Marker = {},
		kfMarker = {},
		Components = {}
	}

	self._ActiveTracks = {
		Keyframe = {},
		Marker = {},
		kfMarker = {}
	}

	self._SaveData = {}
	self._TimeConnection = nil
	self._SyncTrack = nil
	self._Signals = {
		MarkerTrack = {},
		kfMarker = {}
	}
	self._LinkedTracks = {}

	return self
end

function MoonPlayer._ImportSave(self: MoonPlayer, saveValue: StringValue)
	local decodeSave = HttpService:JSONDecode(saveValue.Value)
	local decode_Information = decodeSave["Information"]
	local decode_Items = decodeSave["Items"]

	if self.Properties.AutoComponents then
		self.FrameRate = decode_Information["FPS"] or 60

		local hasScreenCover = false
		local hasVignette = false
		local hasCamera = false

		for _, table in decode_Items do
			local path = table["Path"]
			local itemType = path["ItemType"]
			local instanceNames = path["InstanceNames"]
			local instanceName = instanceNames[#instanceNames]

			if instanceName == "Screen Cover" then
				hasScreenCover = true
			elseif instanceName == "Vignette" then
				hasVignette = true
			elseif instanceName == "CurrentCamera" and itemType == "Camera" then
				hasCamera = true
			end
		end
		
		if hasCamera then
			table.insert(self._Cache.Components, workspace.CurrentCamera)
		end

		if hasScreenCover or hasVignette then
			local screenGui = Instance.new("ScreenGui")
			screenGui.Name = "LunarUtility_MoonPlayer"
			screenGui.ResetOnSpawn = false
			screenGui.IgnoreGuiInset = true
			screenGui.Parent = Players.LocalPlayer.PlayerGui

			local screenCover
			local vignette

			if hasScreenCover then
				screenCover = MoonComponents.GetScreenCover()
				screenCover.Parent = screenGui
			end

			if hasVignette then
				vignette = MoonComponents.GetVignette()
				vignette.Parent = screenGui
			end

			table.insert(self._Cache.Components, screenGui)
			-- Bug fix: table.insert(t, nil) raises in Luau. Only insert the
			-- components we actually created (the save can have just one of
			-- ScreenCover / Vignette).
			if screenCover then
				table.insert(self._Cache.Components, screenCover)
			end
			if vignette then
				table.insert(self._Cache.Components, vignette)
			end
		end

	end

	self._SaveData = decode_Items
end

local function ReadOldFormatEasing(keyframeFolder: Folder): (string, string)
	local keyframeEases = keyframeFolder:FindFirstChild("Eases")
		and keyframeFolder.Eases:FindFirstChild("0")

	local style: string
	local direction: string

	if keyframeEases then
		style = keyframeEases:FindFirstChild("Type")
			and keyframeEases.Type.Value
			or "Linear"

		if keyframeEases:FindFirstChild("Params") and style ~= "Bezier" then
			direction = keyframeEases.Params.Direction.Value
		elseif style == "Bezier" then
			direction = "Bezier"
		else
			direction = "In"
		end
	else
		style = "Linear"
		direction = "In"
	end

	return style, direction
end

local function WrapSequenceValue(rawValue, valuesFolder: Folder): any
	if valuesFolder:FindFirstChild("NumberSequence") then
		return NumberSequence.new(rawValue)
	elseif valuesFolder:FindFirstChild("ColorSequence") then
		return ColorSequence.new(rawValue)
	else
		return rawValue
	end
end

function MoonPlayer._ImportKeyframe(self: MoonPlayer, saveValue: StringValue, data: {[string]: Instance})
	for index, item in self._SaveData do
		local decode_Path = item["Path"]
		local decode_InstanceNames = decode_Path["InstanceNames"]
		local instance_Name = decode_InstanceNames[#decode_InstanceNames]
		local instance_Class = decode_Path["ItemType"]

		for identifier: string, object: Instance in data do
			-- // if it's not the same instance class then skip
			if not (object:IsA(instance_Class)) then continue end

			-- // if it's not the same instance name then skip
			if identifier ~= instance_Name then continue end

			if identifier == "Camera" and not object:IsA("Camera") and instance_Class == "Camera" then
				continue
			end

			if object:GetAttribute("_LunarMoon_Animating") then
				self:_DebugWarn("Skipped "..object.Name.." instance because it's getting animated by another MoonPlayer instance")
				continue
			end

			local folder = saveValue:FindFirstChild(index)

			for _, folder: Folder in folder:GetChildren() do
				local property_Name = folder.Name
				local isAMarkerTrack = property_Name == "MarkerTrack"
				local isAFunction = property_Name == "Emit" or property_Name == "Clear"

				if object:IsA("Camera") and not (property_Name == "FieldOfView") then continue end -- <<<<<<< TODO: add support for camera cframe, for tracking use LunarUtility:AttachCamera(part) for now

				if not isAMarkerTrack then
					if not self._Cache["Keyframe"][object] then
						self._Cache["Keyframe"][object] = {}
					end

					if not self._Cache["Keyframe"][object][property_Name] then
						self._Cache["Keyframe"][object][property_Name] = {}
					end

					local cache_object = self._Cache.Keyframe[object]
					local cache_propInObject = cache_object[property_Name]

					-- // loops through default value and keyframe folders
					-- // defer the default ValueBase so we only commit it if real keyframes exist for this property
					local pendingDefault = nil
					local hasExplicitKeyframes = false

					for _, keyframe: Instance in folder:GetChildren() do
						if keyframe:IsA("Folder") then

							local keyframe: TypeCheck.KeyframeStructure = keyframe
							local valuesFolder = keyframe:FindFirstChild("Values")
							if not valuesFolder then continue end

							hasExplicitKeyframes = true

							-- // new format: each child of Values is a pre-baked frame
							if property_Name == "FieldOfView" and IsNewBakedFormat(keyframe) then
								for _, valueEntry in valuesFolder:GetChildren() do
									local frameNum = tonumber(valueEntry.Name)
									if not frameNum then continue end -- skip sequence type markers
									if cache_propInObject[frameNum] then continue end

									local keyframeTable = {
										EasingStyle = "Linear",
										EasingDirection = "In",
										Value = WrapSequenceValue(valueEntry.Value, valuesFolder),
									}

									cache_propInObject[frameNum] = keyframeTable
								end

							else -- // old format: folder name is the timestamp, Values["0"] is the value
								local keyframeEases = keyframe:FindFirstChild("Eases") and keyframe.Eases["0"]
								local values0 = valuesFolder:FindFirstChild("0")
								if not values0 then continue end

								local keyframe_value = values0.Value
								local keyframe_style, keyframe_styleDirection =
									ReadOldFormatEasing(keyframe)

								local keyframeTable = {
									EasingStyle = keyframe_style,
									EasingDirection = keyframe_styleDirection,
									Value = WrapSequenceValue(keyframe_value, valuesFolder),
								}

								if keyframe_style == "Bezier" then
									local params = keyframe.Eases["0"].Params
									local x1 = params:FindFirstChild("X1")
									local x2 = params:FindFirstChild("X2")
									local y1 = params:FindFirstChild("Y1")
									local y2 = params:FindFirstChild("Y2")
									keyframeTable["X1"] = x1 and x1.Value
									keyframeTable["X2"] = x2 and x2.Value
									keyframeTable["Y1"] = y1 and y1.Value
									keyframeTable["Y2"] = y2 and y2.Value
								elseif keyframe_style == "Back" then
									local overshoot = keyframe.Eases["0"].Params:FindFirstChild("Overshoot")
									keyframeTable["Overshoot"] = overshoot and overshoot.Value
								elseif keyframe_style == "Elastic" then
									local params = keyframe.Eases["0"].Params
									local period    = params:FindFirstChild("Period")
									local amplitude = params:FindFirstChild("Amplitude")
									keyframeTable["Period"]    = period    and period.Value
									keyframeTable["Amplitude"] = amplitude and amplitude.Value
								end

								cache_propInObject[tonumber(keyframe.Name)] = keyframeTable
								keyframeTable = nil
							end

						elseif keyframe:IsA("ValueBase") and keyframe.Name == "default" and not isAFunction then
							pendingDefault = keyframe
						end
					end

					-- // only commit the default if real keyframes exist for this property,
					-- // otherwise MA2's stored defaults create ghost tracks
					if hasExplicitKeyframes and pendingDefault and not cache_propInObject[0] then
						local keyframe = pendingDefault
						local isANumberSequence = keyframe:FindFirstChild("NumberSequence")
						local isAColorSequence = keyframe:FindFirstChild("ColorSequence")

						local keyframeTable = {}

						if isANumberSequence then
							keyframeTable.Value = NumberSequence.new(keyframe.Value)
						elseif isAColorSequence then
							keyframeTable.Value = ColorSequence.new(keyframe.Value)
						else
							keyframeTable.Value = keyframe.Value
						end

						keyframeTable["EasingStyle"] = typeof(object[property_Name]) == "boolean" and "Constant" or "Linear"
						keyframeTable["EasingDirection"] = "In"

						cache_propInObject[0] = keyframeTable
					end

					-- // drop the cache entry if nothing was actually written to it
					if not next(cache_propInObject) then
						cache_object[property_Name] = nil
					end
				end
			end

		end

	end

	for instance: Instance, data in self._Cache.Keyframe do
		for propertyName: string, propertyData in data do
			if not self._Cache.ReKeyframe[instance] then
				self._Cache.ReKeyframe[instance] = {}
			end

			if not self._Cache.ReKeyframe[instance][propertyName] then
				self._Cache.ReKeyframe[instance][propertyName] = {}
			end

			local reKeyframePath = self._Cache.ReKeyframe[instance][propertyName]

			for keyframeTime: number, keyframeData in propertyData do
				if table.find(reKeyframePath, keyframeTime) then continue end
				if not (typeof(keyframeTime) == "number") then continue end

				table.insert(reKeyframePath, keyframeTime)
			end

			table.sort(reKeyframePath, function(a,b)
				return a < b
			end)

			local newKeyframe = propertyData
			for keyframeTime: number, keyframeData in newKeyframe do
				keyframeData["Called"] = false
			end

			local track = {
				Instance = instance,
				Property = propertyName,
				ReKeyframe = reKeyframePath,
				Keyframe = newKeyframe,
				beforeValue = instance[propertyName],
			}

			table.insert(self._ActiveTracks.Keyframe, track)
		end
	end
end

function MoonPlayer._ImportMarkerTrack(self: MoonPlayer, saveValue: StringValue)
	-- // Marker Track
	for _, markerTrack: StringValue in saveValue:QueryDescendants("#width") do
		local markerName = markerTrack.Parent.name and markerTrack.Parent.name.Value
		local markerNumber = tonumber(markerTrack.Parent.Name)

		if markerName then
			-- Bug fix: previously the guard read `[markerName]` but the write
			-- used `[markerNumber]`. Dedup by the storage key so the same
			-- marker can't be inserted twice.
			if not self._Cache["Marker"][markerNumber] then
				self._Cache["Marker"][markerNumber] = markerName
			end
		end

		local kfMarkerFolder = markerTrack.Parent:FindFirstChild("KFMarkers")

		if kfMarkerFolder then
			for _, kfMarker: StringValue in kfMarkerFolder:GetChildren() do
				local kfMarkerName = kfMarker.Value
				local kfMarkerValue = kfMarker.Val.Value

				if not self._Cache.kfMarker[markerNumber] then
					self._Cache.kfMarker[markerNumber] = {
						Name = kfMarkerName,
						Value = kfMarkerValue,
					}
				end
			end
		end
	end

	for keyframeTime: number, markerName: string in self._Cache.Marker do
		self._ActiveTracks.Marker[keyframeTime] = markerName
		self:_DebugWarn("Created "..markerName.." marker track")
	end

	for kfMarkerTime: number, kfMarkerData in self._Cache.kfMarker do
		self._ActiveTracks.kfMarker[kfMarkerTime] = kfMarkerData
		self:_DebugWarn("Created "..kfMarkerData.Name.." keyframe marker")
	end
end

function MoonPlayer._GetZeroAndOneKeyframe(self: MoonPlayer, rearrangedTable, Time: number)
	local indexCount = #rearrangedTable

	if Time > rearrangedTable[indexCount] or indexCount == 1 then
		return rearrangedTable[indexCount], nil, "last"
	end

	if Time < rearrangedTable[1] then
		return rearrangedTable[1], nil, "first"
	end

	local i0, i1 = InnerUtility.getRangeIndices(rearrangedTable, Time)

	local zeroKeyframe = rearrangedTable[i0]
	local oneKeyframe = rearrangedTable[i1]

	return zeroKeyframe, oneKeyframe
end

function MoonPlayer._GetAlphaValue(self: MoonPlayer, TimeAlpha: number, zeroExistance)
	local EasingStyle = zeroExistance.EasingStyle
	local EasingDirection = zeroExistance.EasingDirection

	local BezierX1 = zeroExistance.X1
	local BezierY1 = zeroExistance.Y1
	local BezierX2 = zeroExistance.X2
	local BezierY2 = zeroExistance.Y2

	local BezierVector1 = Vector2.new(BezierX1, BezierY1)
	local BezierVector2 = Vector2.new(BezierX2, BezierY2)

	local Amplitude = zeroExistance.Amplitude
	local Period = zeroExistance.Period

	local Overshoot = zeroExistance.Overshoot

	local AlphaValue

	if EasingStyle == "Linear" then
		AlphaValue = EasingFunctions.Linear(TimeAlpha)
	elseif EasingStyle == "Constant" then
		AlphaValue = EasingFunctions.Constant(TimeAlpha)
	elseif EasingStyle == "Bezier" then
		AlphaValue = EasingFunctions.Bezier(TimeAlpha, BezierVector1, BezierVector2)
	elseif EasingStyle == "Elastic" then
		AlphaValue = EasingFunctions["Elastic"..EasingDirection](TimeAlpha, Amplitude, Period)
	elseif EasingStyle == "Back" then
		AlphaValue = EasingFunctions["Back"..EasingDirection](TimeAlpha, Overshoot)
	else
		AlphaValue = EasingFunctions[EasingStyle..EasingDirection](TimeAlpha)
	end

	return AlphaValue
end

function MoonPlayer._Interpolate(self: MoonPlayer, keyframeTable, object: Instance, property: string, zeroValue: any, oneValue: any, ValueAlpha: number)
	local propertyType = typeof(object[property])

	if propertyType == "boolean" then
		-- Bug fix: the old `and/or` ternary returned `zeroValue` whenever
		-- `oneValue` was false (because false is falsy), so animating a
		-- boolean to false never actually set it. Use an if-expression.
		local targetValue = if ValueAlpha >= 1 then oneValue else zeroValue

		if object[property] ~= targetValue then
			if object.Name == "Vignette" then
				LerpVignette(object, property, targetValue)
			else
				object[property] = targetValue
			end
		end

	elseif propertyType == "number" then
		if object.Name == "Vignette" then
			LerpVignette(object, property, math.lerp(zeroValue, oneValue, ValueAlpha))
		else
			object[property] = math.lerp(zeroValue, oneValue, ValueAlpha)
		end

	elseif propertyType == "NumberSequence" then
		object[property] = InnerUtility.LerpNumberSequence(zeroValue, oneValue, ValueAlpha)

	elseif propertyType == "ColorSequence" then
		object[property] = InnerUtility.LerpColorSequence(zeroValue, oneValue, ValueAlpha)

	elseif zeroValue.Lerp then 
		if object.Name == "Vignette" then
			LerpVignette(object, property, zeroValue:Lerp(oneValue, ValueAlpha))
		else
			if propertyType == "CFrame" and not (self.Properties.RootPart == nil) then
				local newZeroValue = self:_GetNewCFrameValue(keyframeTable, object, zeroValue)
				object[property] = newZeroValue:Lerp(oneValue, ValueAlpha)
			else
				object[property] = zeroValue:Lerp(oneValue, ValueAlpha)
			end
		end
	else
		self:_DebugWarn("Can't interpolate "..object.Name.."."..property.." - property type mismatched")
	end

	object:SetAttribute("_LunarMoon_Animating", true)
end

function MoonPlayer._InterpolateFunction(self: MoonPlayer, keyframeTable, object: Instance, property: string, zeroKeyframe: number, oneKeyframe: number)
	local TrackPosition = self.TrackPosition
	local zeroValue = keyframeTable[zeroKeyframe].Value
	local hasCalled = keyframeTable[zeroKeyframe].Called

	if not hasCalled and TrackPosition >= zeroKeyframe then
		keyframeTable[zeroKeyframe].Called = true

		if property == "Emit" then
			object:Emit(zeroValue)
			self:_DebugWarn(`Emitted Particle: {object.Name} by {zeroValue}`)
		elseif property == "Clear" then
			object:Clear()
			self:_DebugWarn(`Cleared Particle: {object.Name}`)
		end
	end

end

function MoonPlayer._GetNextValue(self: MoonPlayer, keyframeTable, object: BasePart, oneValue)
	local valueType = typeof(oneValue)

	if valueType == "CFrame" and self.Properties.RootPart then
		return self:_GetNewCFrameValue(keyframeTable, object, oneValue)
	else
		return oneValue
	end
end

function MoonPlayer._SetDefaultValue(self: MoonPlayer, Instance: Instance, Property: any, value: any)
	if typeof(value) == "CFrame" and self.Properties.RootPart then
		-- Bug fix: originOffset attribute can be missing. Multiplying a CFrame
		-- by nil errors; fall back to writing the raw value so the property
		-- at least gets initialized.
		local originOffset = Instance:GetAttribute("originOffset")
		if typeof(originOffset) == "CFrame" then
			Instance[Property] = self.Properties.RootPart.CFrame * originOffset
		else
			Instance[Property] = value
		end
	else
		Instance[Property] = value
	end
end

function MoonPlayer._GetNewCFrameValue(self: MoonPlayer, keyframeTable, object: Instance, value: CFrame)
	if not self.Properties.RootPart then return end

	-- Bug fix: keyframeTable[0] can be absent when a CFrame track has
	-- explicit keyframes but no "default" ValueBase in the save. Indexing
	-- .Value on nil would error; fall back to identity so interpolation
	-- degrades to a raw world-space write instead of a crash.
	local defaultKeyframe = keyframeTable[0]
	local defaultValue: CFrame = defaultKeyframe and defaultKeyframe.Value or CFrame.identity
	local rootPartCFrame = self.Properties.RootPart.CFrame
	local originOffset = object:GetAttribute("originOffset")

	-- Bug fix: originOffset attribute can be missing. Return the raw value
	-- so callers get a sane CFrame instead of a runtime error.
	if typeof(originOffset) ~= "CFrame" then
		self:_DebugWarn("Missing originOffset on "..object.Name..", returning raw CFrame")
		return value
	end

	local rootPartOrigin = rootPartCFrame * originOffset
	local deltaOffset = defaultValue:ToObjectSpace(value)
	local newValue = rootPartOrigin * deltaOffset

	return newValue
end

function MoonPlayer._Update(self: MoonPlayer)
	local TrackPosition = self.TrackPosition
	local AttachedCamera = self.Properties.AttachedCamera

	for _, track in self._ActiveTracks.Keyframe do
		local Instance = track.Instance
		local Property = track.Property
		local ReKeyframe = track.ReKeyframe
		local Keyframe = track.Keyframe

		local typeOfProperty = typeof(Instance[Property])
		local zeroKeyframe, oneKeyframe = self:_GetZeroAndOneKeyframe(ReKeyframe, TrackPosition)
		local zeroExistance, oneExistance = Keyframe[zeroKeyframe], Keyframe[oneKeyframe]
		local zeroValue = zeroExistance.Value

		if typeOfProperty == "function" then
			self:_InterpolateFunction(Keyframe, Instance, Property, zeroKeyframe, oneKeyframe)
			continue
		end

		if not oneExistance then
			if typeof(zeroValue) == "CFrame" and self.Properties.RootPart then
				local newCFrame = self:_GetNewCFrameValue(Keyframe, Instance, zeroValue)
				Instance[Property] = newCFrame
			else
				if Instance.Name == "Vignette" then
					LerpVignette(Instance, Property, zeroValue)
				else
					Instance[Property] = zeroValue
				end
			end
			continue
		end

		local oneValue = oneExistance.Value

		local duration = oneKeyframe - zeroKeyframe
		local TimeAlpha = (TrackPosition - zeroKeyframe) / duration

		local ValueAlpha = self:_GetAlphaValue(TimeAlpha, zeroExistance)
		local nextValue = self:_GetNextValue(Keyframe, Instance, oneValue)

		if TrackPosition == 0 then
			self:_SetDefaultValue(Instance, Property, zeroValue)
		end

		self:_Interpolate(Keyframe, Instance, Property, zeroValue, nextValue, ValueAlpha)
	end

	for keyframeTime: number, markerName: string in self._ActiveTracks.Marker do
		local Signal = self._Signals.MarkerTrack[markerName]

		if TrackPosition >= keyframeTime then
			if Signal then
				self:_DebugWarn("Fired "..markerName.." marker track signal")
				Signal:Fire()
			else
				self:_DebugWarn("Marker track signal "..markerName.. " not found")
			end

			self._ActiveTracks.Marker[keyframeTime] = nil
		end
	end

	for kfMarkerTime: number, kfMarkerData in self._ActiveTracks.kfMarker do
		local markerName = kfMarkerData.Name
		local markerValue = kfMarkerData.Value

		local Signal = self._Signals.kfMarker[markerName]

		if TrackPosition >= kfMarkerTime then
			if Signal then
				self:_DebugWarn("Fired "..markerName.." marker signal")
				Signal:Fire(markerValue)
			else
				self:_DebugWarn("Marker signal "..markerName.. " not found")
			end

			self._ActiveTracks.kfMarker[kfMarkerTime] = nil
		end
	end

	-- Bug fix: guard against the attached camera part having been destroyed
	-- mid-playback (accessing .CFrame on a destroyed instance can error).
	if AttachedCamera and AttachedCamera.Parent then
		self.Camera.CFrame = self.Properties.AttachedCamera.CFrame
	end
end

function MoonPlayer.Load(self: MoonPlayer, saveValue: StringValue, data: {[string]: Instance})
	self:_ImportSave(saveValue)

	for _, object in self._Cache.Components do
		if object.Name == "Screen Cover" then
			data["Screen Cover"] = object
		elseif object.Name == "Vignette" then
			data["Vignette"] = object
		elseif object.Name == "Camera" then
			data["CurrentCamera"] = object
		end
	end

	self:_ImportKeyframe(saveValue, data)
	self:_ImportMarkerTrack(saveValue)

	if self.Properties.Debug then
		self:_DebugWarn("Loaded save successfully with this following data")
		print(self._ActiveTracks)
	end
end

function MoonPlayer.PlayBulk(self: MoonPlayer, data: {[Instance | () -> ()]: {folder: Folder, camOrMarkerName: Camera | string}} | Folder)
	for firstArg, secondArg in data do
		if typeof(firstArg) == "Instance" then
			if typeof(secondArg) == "Instance" then
				
			elseif typeof(secondArg) == "table" then
				
			end
		end
	end
end

function MoonPlayer.AttachCamera(self: MoonPlayer, camera: BasePart | nil, AutoCamType: boolean)
	if camera and not (camera:IsA("BasePart")) then
		self:_DebugWarn("Expected camera to be a BasePart")
		return
	end

	if not AutoCamType then
		AutoCamType = false
	end

	if camera and AutoCamType then
		-- Bug fix: save the original CameraType before forcing Scriptable so
		-- we can restore whatever the game was using (Custom / Track / Fixed)
		-- instead of hard-coding Custom on detach.
		if self.Properties._SavedCameraType == nil then
			self.Properties._SavedCameraType = self.Camera.CameraType
		end
		self.Camera.CameraType = Enum.CameraType.Scriptable
	elseif not camera and AutoCamType then
		local saved = self.Properties._SavedCameraType
		self.Camera.CameraType = saved or Enum.CameraType.Custom
		self.Properties._SavedCameraType = nil
	end

	self.Properties.AttachedCamera = camera
	self.Properties.AutoCamType = AutoCamType
end

function MoonPlayer.SyncToTrack(self: MoonPlayer, track: AnimationTrack | nil)
	-- Bug fix: passing nil is a legitimate way to clear the sync, so don't
	-- warn for it. Warn only when the caller passes something that isn't
	-- nil and isn't an Instance.
	if track ~= nil and typeof(track) ~= "Instance" then
		self:_DebugWarn("Expected track to be an AnimationTrack or nil for unsync")
	end

	self._SyncTrack = track
end

function MoonPlayer.Play(self: MoonPlayer)
	self:_DebugWarn("Playing animation")

	-- Bug fix: disconnect any prior PreRender connection so repeat Play()
	-- calls don't stack listeners (each of which would call _Update every
	-- frame, silently multiplying the CPU cost).
	if self._TimeConnection then
		if self._TimeConnection.Connected then
			self._TimeConnection:Disconnect()
		end
		self._TimeConnection = nil
	end

	-- Bug fix: reset `Called` flags on all function-interpolation keyframes
	-- so Emit/Clear fire again on replay. Without this, a second Play()
	-- silently skips every particle emit that already fired on the first run.
	if self._ActiveTracks and self._ActiveTracks.Keyframe then
		for _, track in self._ActiveTracks.Keyframe do
			if track.Keyframe then
				for _, keyframeData in track.Keyframe do
					if typeof(keyframeData) == "table" and keyframeData.Called ~= nil then
						keyframeData.Called = false
					end
				end
			end
		end
	end

	-- Also reset marker tracks so markers re-fire on replay.
	if self._ActiveTracks and self._Cache then
		for keyframeTime, markerName in self._Cache.Marker do
			self._ActiveTracks.Marker[keyframeTime] = markerName
		end
		for kfMarkerTime, kfMarkerData in self._Cache.kfMarker do
			self._ActiveTracks.kfMarker[kfMarkerTime] = kfMarkerData
		end
	end

	self.TimePosition = 0
	self.TrackPosition = 0
	self.IsPlaying = true

	-- Start any tracks registered via LinkTrack so they begin at the
	-- same TimePosition as MoonPlayer. Per-frame drift is corrected in
	-- _SyncLinkedTracks from inside the PreRender connection below.
	if self._LinkedTracks then
		for _, entry in self._LinkedTracks do
			self:_StartLinkedTrack(entry)
		end
	end

	self._TimeConnection = RunService.PreRender:Connect(function(dt)
		if not self.IsPlaying then return end

		self.FrameRate = self.FrameRate or 60

		self:_Update()
		
		if not self._SyncTrack then
			self.TimePosition += dt
		else
			self.TimePosition = self._SyncTrack.TimePosition
		end
		
		self.TrackPosition = self.TimePosition * self.FrameRate

		self:_SyncLinkedTracks()
	end)
end

function MoonPlayer.Destroy(self: MoonPlayer)
	if self._TimeConnection then
		if self._TimeConnection.Connected then
			self._TimeConnection:Disconnect()
		end

		self._TimeConnection = nil
		self:_DebugWarn("Destroyed TimeConnection")
	end

	if self._Cache then
		for _, object in self._Cache.Components do
			if not (object:IsA("Camera")) then
				object:Destroy()
			end
			
			self:_DebugWarn("Destroyed "..object.Name.." Component")
		end
		self._Cache = nil
	end

	if self._ActiveTracks then
		for _, track in self._ActiveTracks.Keyframe do
			-- Bug fix: pcall restore so a destroyed animated instance doesn't
			-- tank cleanup of the remaining tracks. Indexing a destroyed
			-- instance's property can raise.
			local ok, err = pcall(function()
				if not (typeof(track.Instance[track.Property]) == "function") then
					track.Instance[track.Property] = track.beforeValue
				end
				track.Instance:SetAttribute("_LunarMoon_Animating", nil)
				self:_DebugWarn(`Successfully set {track.Instance.Name}.{track.Property} to its previous value ({track.beforeValue})`)
			end)

			if not ok then
				self:_DebugWarn(`Skipped restoring {track.Property}: {err}`)
			end
		end

		self._ActiveTracks = nil
	end

	if self._Signals then
		for signalName, signal in self._Signals.MarkerTrack do
			signal:DisconnectAll()

			self:_DebugWarn("Disconnected "..signalName.." signal")
		end

		for signalName, signal in self._Signals.kfMarker do
			signal:DisconnectAll()

			self:_DebugWarn("Disconnected "..signalName.." signal")
		end

		self._Signals = nil
	end

	if self._LinkedTracks then
		for _, entry in self._LinkedTracks do
			self:_StopLinkedTrack(entry)
		end
		self._LinkedTracks = nil
	end

	if self.Properties and self.Properties.AutoCamType and self.Camera then
		self:AttachCamera(nil, self.Properties.AutoCamType)
	end

	self.Camera = nil
	self.TimePosition = nil
	self.TrackPosition = nil
	self.IsPlaying = nil
	self.FrameRate = nil
	self._SaveData = nil

	self:_DebugWarn("Stopped and cleaned up Moon Player")
	self.Properties = nil
end

function MoonPlayer.Pause(self: MoonPlayer)
	self.IsPlaying = false

	if self._LinkedTracks then
		for _, entry in self._LinkedTracks do
			self:_PauseLinkedTrack(entry)
		end
	end
end

function MoonPlayer.Resume(self: MoonPlayer)
	self.IsPlaying = true

	if self._LinkedTracks then
		for _, entry in self._LinkedTracks do
			if entry.Paused then
				self:_ResumeLinkedTrack(entry)
			else
				-- linked mid-pause or never started yet
				self:_StartLinkedTrack(entry)
			end
		end
	end
end

function MoonPlayer.GetMarkerTrackReachedSignal(self: MoonPlayer, name: string)
	-- Bug fix: previously this returned nil on duplicate calls. Return the
	-- existing signal so callers can connect to it safely whether or not
	-- it's the first request for this name.
	if self._Signals.MarkerTrack[name] then
		return self._Signals.MarkerTrack[name]
	end

	self:_DebugWarn("Listener "..name.." marker track created")
	self._Signals.MarkerTrack[name] = Signal()

	return self._Signals.MarkerTrack[name]
end

function MoonPlayer.GetMarkerReachedSignal(self: MoonPlayer, name: string)
	-- Bug fix: same pattern as GetMarkerTrackReachedSignal — return the
	-- existing signal instead of nil on duplicate requests.
	if self._Signals.kfMarker[name] then
		return self._Signals.kfMarker[name]
	end

	self:_DebugWarn("Listener "..name.." marker created")
	self._Signals.kfMarker[name] = Signal()

	return self._Signals.kfMarker[name]
end

-- // ---------- LinkTrack: sync external AnimationTracks / Sounds ----------
-- // A linked track follows MoonPlayer.TimePosition every frame. Small
-- // drift (< LINKED_DRIFT_EPSILON) is tolerated to avoid setting
-- // TimePosition every frame (which causes audible/visual jitter).

local LINKED_DRIFT_EPSILON = 0.15 -- seconds

local function _kindOfLinkable(obj: Instance): string?
	if obj:IsA("AnimationTrack") then return "AnimationTrack" end
	if obj:IsA("Sound") then return "Sound" end
	return nil
end

-- AnimationTrack.Parent is always nil even when the track is perfectly
-- usable, so the Sound-style `.Parent` guard doesn't work for animations.
-- Trust pcall for AnimationTracks; use .Parent for Sounds (cheap destroyed
-- check).
local function _isLinkedTrackAlive(entry): boolean
	local t = entry.Track
	if not t then return false end
	if entry.Kind == "Sound" then
		return t.Parent ~= nil
	end
	return true
end

function MoonPlayer._StartLinkedTrack(self: MoonPlayer, entry)
	if not _isLinkedTrackAlive(entry) then return end
	local track = entry.Track

	local ok, err = pcall(function()
		if entry.Kind == "AnimationTrack" then
			if not track.IsPlaying then
				track:Play(0) -- no fade-in for accurate sync
			end
			track.TimePosition = self.TimePosition
		elseif entry.Kind == "Sound" then
			if not track.IsPlaying then
				track:Play()
			end
			track.TimePosition = self.TimePosition
		end
	end)

	entry.Paused = false
	entry.SavedSpeed = nil

	if not ok then
		self:_DebugWarn("LinkTrack: failed to start "..tostring(entry.Kind)..": "..tostring(err))
	end
end

function MoonPlayer._PauseLinkedTrack(self: MoonPlayer, entry)
	if not _isLinkedTrackAlive(entry) then return end
	local track = entry.Track

	pcall(function()
		if entry.Kind == "AnimationTrack" then
			if track.IsPlaying then
				entry.SavedSpeed = track.Speed
				track:AdjustSpeed(0) -- AnimationTrack has no Pause; freeze via speed
			end
		elseif entry.Kind == "Sound" then
			if track.IsPlaying then
				track:Pause()
			end
		end
	end)
	entry.Paused = true
end

function MoonPlayer._ResumeLinkedTrack(self: MoonPlayer, entry)
	if not _isLinkedTrackAlive(entry) then return end
	local track = entry.Track

	pcall(function()
		if entry.Kind == "AnimationTrack" then
			local speed = entry.SavedSpeed or 1
			track:AdjustSpeed(speed)
			track.TimePosition = self.TimePosition
		elseif entry.Kind == "Sound" then
			track:Resume()
			track.TimePosition = self.TimePosition
		end
	end)
	entry.Paused = false
	entry.SavedSpeed = nil
end

function MoonPlayer._StopLinkedTrack(self: MoonPlayer, entry)
	if not _isLinkedTrackAlive(entry) then return end
	local track = entry.Track

	pcall(function()
		track:Stop()
	end)
	entry.Paused = false
	entry.SavedSpeed = nil
end

function MoonPlayer._SyncLinkedTracks(self: MoonPlayer)
	if not self._LinkedTracks then return end
	local now = self.TimePosition

	for _, entry in self._LinkedTracks do
		if entry.Paused then continue end
		if not _isLinkedTrackAlive(entry) then continue end
		local track = entry.Track
		if not track.IsPlaying then continue end
		if math.abs(track.TimePosition - now) > LINKED_DRIFT_EPSILON then
			track.TimePosition = now
		end
	end
end

function MoonPlayer._LinkOne(self: MoonPlayer, track)
	if typeof(track) ~= "Instance" then
		self:_DebugWarn("LinkTrack: expected AnimationTrack or Sound, got "..typeof(track))
		return
	end

	local kind = _kindOfLinkable(track)
	if not kind then
		self:_DebugWarn("LinkTrack: "..track.ClassName.." is not supported (expected AnimationTrack or Sound)")
		return
	end

	-- dedupe: ignore double-links of the same track
	for _, existing in self._LinkedTracks do
		if existing.Track == track then
			return
		end
	end

	local entry = {
		Track = track,
		Kind = kind,
		Paused = false,
		SavedSpeed = nil,
	}

	table.insert(self._LinkedTracks, entry)
	self:_DebugWarn("LinkTrack: linked "..kind.." "..track.Name)

	-- If MoonPlayer is already playing (not paused), start this track
	-- immediately so it joins in-sync with the current TimePosition.
	if self.IsPlaying then
		self:_StartLinkedTrack(entry)
	end
end

function MoonPlayer.LinkTrack(self: MoonPlayer, track: AnimationTrack | Sound | {any})
	if not self._LinkedTracks then
		self._LinkedTracks = {}
	end

	if typeof(track) == "Instance" then
		self:_LinkOne(track)
	elseif typeof(track) == "table" then
		for _, inner in track do
			if typeof(inner) == "Instance" then
				self:_LinkOne(inner)
			elseif typeof(inner) == "table" then
				self:LinkTrack(inner) -- supports nested tables
			end
		end
	else
		self:_DebugWarn("LinkTrack: expected AnimationTrack, Sound, or table of those; got "..typeof(track))
	end
end

function MoonPlayer.UnlinkTrack(self: MoonPlayer, track: (AnimationTrack | Sound | {any})?)
	if not self._LinkedTracks then return end

	-- Unlinking does NOT stop the track. The track is simply removed from
	-- the sync list and left in whatever state it currently holds — so a
	-- playing track keeps playing, and a paused track stays paused. If the
	-- caller wants to stop or resume it, they do so themselves on the
	-- underlying AnimationTrack / Sound reference.

	-- nil = unlink everything
	if track == nil then
		table.clear(self._LinkedTracks)
		return
	end

	if typeof(track) == "table" then
		for _, inner in track do
			self:UnlinkTrack(inner)
		end
		return
	end

	for i = #self._LinkedTracks, 1, -1 do
		if self._LinkedTracks[i].Track == track then
			table.remove(self._LinkedTracks, i)
		end
	end
end

function MoonPlayer.AutoComponents(self: MoonPlayer, value: boolean)
	-- Bug fix: `value or true` made it impossible to pass `false`
	-- (false or true = true). Accept explicit false; default to true
	-- only when the caller omits the argument entirely.
	if value == nil then value = true end
	self.Properties.AutoComponents = value
end

function MoonPlayer.Debug(self: MoonPlayer, value: boolean)
	self.Properties.Debug = value or false
end

function MoonPlayer.SetRootPart(self: MoonPlayer, object: Instance)
	if not (object == nil) and not object:IsA("BasePart") then
		self:_DebugWarn("RootPart must be a BasePart or nil")
		return
	end

	self.Properties.RootPart = object
end

function MoonPlayer._DebugWarn(self: MoonPlayer, msg: string)
	if not self.Properties or not self.Properties.Debug then return end
	InnerUtility.warn("MoonPlayer/Debug", msg)
end

return MoonPlayer