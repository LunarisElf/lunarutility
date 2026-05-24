local Signal = require("../.././Dependencies/Signal")

-- // Per-entry state tracked inside self._LinkedTracks.
type LinkedTrackEntry = {
	Track: AnimationTrack | Sound,
	Kind: string, -- "AnimationTrack" | "Sound"
	Paused: boolean,
	SavedSpeed: number?, -- restore target for AnimationTrack after AdjustSpeed(0)
}

export type MoonPlayer = {
	["TimePosition"]: number,
	["FrameRate"]: number,
	["TrackPosition"]: number,
	["IsPlaying"]: number,
	["Camera"]: Camera,
	["Properties"] : {
		Debug: boolean,
		AutoComponents: boolean,
		RootPart: BasePart?,
		AttachedCamera: BasePart?,
		AutoCamType: boolean,
		_SavedCameraType: Enum.CameraType?, -- stashed on AttachCamera, restored on detach
	},

	["_Cache"]: {
		Keyframe: {
			[Instance]: {
				[string]: {
					[number]: {
						Value: ValueBase,
						EasingStyle: string,
						EasingDirection: string,

						X1: number,
						X2: number,
						Y1: number,
						Y2: number,
						Overshoot: number,
						Period: number,
					},
				}
			}
		},
		ReKeyframe:{
			[Instance]: {
				[string]: {
					[number]: number
				}
			}
		},
		Marker: {[number]: string},
		kfMarker: {[number]: {
			Name: string,
			Value: any
		}},
		Components: {Instance}
	},

	["_SyncTrack"]: AnimationTrack?,
	["_LinkedTracks"]: {LinkedTrackEntry},
	["_TimeConnection"]: RBXScriptConnection,
	["_SaveData"]: {},
	["_Signals"]: {
		MarkerTrack: {Signal.Signal<...any>},
		kfMarker: {Signal.Signal<string>}
	},
	["_Debug"]: boolean,
	["_ActiveTracks"]: {
		Keyframe: {
			[number]: {
				Instance: Instance,
				Property: string,
				ReKeyframe: {[number]: number},
				Keyframe: {
					[number]: ValueBase,
					Called: boolean
				},
				beforeValue: any,
			}
		},
		Marker: {
			[number]: string
		},
		kfMarker: {[number]: {
			Name: string,
			Value: any
		}},
	},


	Load: typeof(

		function(self: MoonPlayer, saveValue: StringValue, data: {[string]: Instance}) end
	),

	_ImportSave: typeof(

		function(self: MoonPlayer, saveValue: StringValue) end
	),

	_ImportKeyframe: typeof(

		function(self: MoonPlayer, saveValue: StringValue, data: {[string]: Instance}) end
	),

	_Update: typeof(

		function(self: MoonPlayer) end
	),

	_Interpolate: typeof(

		function(self: MoonPlayer, keyframeTable, object: Instance, property: string, zeroValue: any, oneValue: any, ValueAlpha: number) end
	),
	
	_InterpolateFunction: typeof(

		function(self: MoonPlayer, keyframeTable, object: Instance, property: string, zeroKeyframe: number, oneKeyframe: number) end
	),

	_GetNextValue: typeof(

		function(self: MoonPlayer, oneValue: any): any
			return nil :: any
		end
	),
	
	SyncToTrack: typeof(
		-- synchronizes Lunar's time position to an animation track, or nil for unsync
		function(self: MoonPlayer, track: AnimationTrack | nil) end
	),

	LinkTrack: typeof(
		-- link an AnimationTrack, Sound or table of them and make them sync to the player's TimePosition
		-- can be unlinked by <strong>:UnlinkTrack()</strong>
		function(self: MoonPlayer, track: AnimationTrack | Sound | {AnimationTrack | Sound}) end
	),

	UnlinkTrack: typeof(
		-- unlink a linked track or a table of them, put <strong>nil</strong> to unlink all linked tracks
		function(self: MoonPlayer, track: AnimationTrack | Sound | {AnimationTrack | Sound} | nil) end
	),

	new: typeof(

		function(): MoonPlayer
			return nil :: any
		end
	),

	Play: typeof(

		function(self: MoonPlayer) end
	),

	Destroy: typeof(

		function(self: MoonPlayer) end
	),


	Pause: typeof(

		function(self: MoonPlayer) end
	),

	Resume: typeof(

		function(self: MoonPlayer) end
	),

	GetMarkerTrackReachedSignal: typeof(

		function(self: MoonPlayer, name: string): Signal.Signal<...any> 
			return nil :: any
		end
	),
	
	GetMarkerReachedSignal: typeof(

    function(self: MoonPlayer, name: string): Signal.Signal<string>
        return nil :: any  -- dummy return to satisfy the type checker
    end
),

	--TimeframeWait: typeof( -- <<<<<<<<<<<<<<<<<<<< #TODO move to the main module
		-- does not work as of right now
	--	function(self: MoonPlayer, duration: number): number end
	--),

	AutoComponents: typeof(
		-- <strong>Default: true</strong>
		-- automatically create moon2 components without needing to find one by yourself (vignette, screencover, etc)
		-- > also <strong>automatically set FPS</strong> to save's FPS value
		function(self: MoonPlayer, value: boolean) end
	),

	Debug: typeof(
		-- <strong>Default: false</strong>
		-- for debugging
		function(self: MoonPlayer, value: boolean) end
	),
	
	AttachCamera: typeof(
		
		function(self: MoonPlayer, camera: BasePart, AutoCamType: boolean) end
	),

	SetRootPart: typeof(
		-- <strong>Default: nil</strong>
		-- set root part for cframe property which will be relative to
		-- <strong>setting it to 'nil' will make it relative to the origin cframe</strong>
		function(self: MoonPlayer, value: BasePart) end
	),

	_GetZeroAndOneKeyframe: typeof(
		function(self: MoonPlayer, propertyData, Time: number): (number, number) 
			return 0, 0 :: any
		end
	),

	_NewSortedKeyframe: typeof(
		function(self: MoonPlayer, Table): {[number]: number} 
			return nil :: any
		end
	),

	_GetAlphaValue: typeof(
		function(self: MoonPlayer, TimeAlpha: number, KeyframeData): number
			return nil :: any
		end
	),

	_DebugWarn: typeof(
		function(self: MoonPlayer, msg: string) end
	),

	_SetDefaultValue: typeof(
		function(self: MoonPlayer, Instance: Instance, Property: any, value: any) end
	),

	_GetNewCFrameValue: typeof(
		function(self: MoonPlayer, keyframeTable, object: Instance, value: CFrame): CFrame 
			return nil :: any
		end
	),

	_LinkOne: typeof(
		function(self: MoonPlayer, track: AnimationTrack | Sound) end
	),

	_StartLinkedTrack: typeof(
		function(self: MoonPlayer, entry: LinkedTrackEntry) end
	),

	_PauseLinkedTrack: typeof(
		function(self: MoonPlayer, entry: LinkedTrackEntry) end
	),

	_ResumeLinkedTrack: typeof(
		function(self: MoonPlayer, entry: LinkedTrackEntry) end
	),

	_StopLinkedTrack: typeof(
		function(self: MoonPlayer, entry: LinkedTrackEntry) end
	),

	_SyncLinkedTracks: typeof(
		function(self: MoonPlayer) end
	),

}

return {}