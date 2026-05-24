export type KeyframeStructure = {
	["Eases"]: {
		["0"]: {
			["Type"]: "Constant" | "Bezier" | "Sine" | "Quad" | "Cubic" | "Quart" | "Quint" | "Sextic" | "Expo" | "Circ" | "Elastic" | "Back" | "Bounce" | "Linear",
			["Params"]: {
				["Direction"]: "In" | "Out" | "InOut" | "OutIn",

				-- // for bezier
				["X1"]: {
					["Value"]: number,
					["Name"]: string
				},

				["X2"]: {
					["Value"]: number,
					["Name"]: string
				},
				["Y1"]: {
					["Value"]: number,
					["Name"]: string
				},
				["Y2"]: {
					["Value"]: number,
					["Name"]: string
				},

				-- // for back
				["Overshoot"]: {
					["Value"]: number,
					["Name"]: string
				},

				-- // for elastic
				["Period"]: {
					["Value"]: number,
					["Name"]: string
				},
				["Amplitude"]: {
					["Value"]: number,
					["Name"]: string
				},

			}
		}
	},

	["Values"]: {
		["0"]: {
			["Value"]: any,
			["Name"]: string
		}
	},

	["Name"]: string
}

return nil