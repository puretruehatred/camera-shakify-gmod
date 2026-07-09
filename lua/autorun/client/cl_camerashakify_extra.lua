-- extra stuff for camera shakify core... core karamel sutra core
-- re-grips, the layer stack, and the preset save/load junk. Kept all this out of the core since its not core file because it was getting long and its not apart of the core of the camera shakify
CreateClientConVar("camerashakify_regrip_enabled", "1", true, false, "periodic re-grip fumbles", 0, 1)
CreateClientConVar("camerashakify_regrip_intensity", "1", true, false, "re-grip strength", 0, 2)
CreateClientConVar("camerashakify_regrip_volume", "0.6", true, false, "re-grip foley volume", 0, 1)
CreateClientConVar("camerashakify_regrip_long_chance", "0.3", true, false, "chance of a long fumble", 0, 1)

local REGRIP_DEFAULT_ON = { THE_CLOSEUP = true, THE_WEDDING = true, OUT_CAR_WINDOW = true, INVESTIGATION = true }
for _, key in ipairs(CameraShakify.ShakeOrder) do
	CreateClientConVar("camerashakify_regrip_use_" .. key, REGRIP_DEFAULT_ON[key] and "1" or "0", true, false,
		"allow " .. key .. " for re-grips", 0, 1)
end

-- foley stuff, could add foley for running with camera but who knows
local shortFoleys, longFoleys = {}, {}
for i = 1, 7 do
	shortFoleys[i] = "camerashakify/foley" .. i .. ".wav"
	longFoleys[i] = "camerashakify/foleylong" .. i .. ".wav"
end

local lastShortIdx, lastLongIdx = 0, 0
local function PickIndex(last)
	local idx
	repeat idx = math.random(1, 7) until idx ~= last
	return idx
end

local function GetEligiblePresets()
	local pool = {}
	for _, key in ipairs(CameraShakify.ShakeOrder) do
		local cv = GetConVar("camerashakify_regrip_use_" .. key)
		if cv and cv:GetBool() then pool[#pool + 1] = key end
	end
	return pool
end

local nextRegrip, activeRegripID = 0, nil

local function ScheduleNext()
	local lo, hi = 5, 14
	local ply = LocalPlayer()
	if IsValid(ply) and ply:IsOnGround() and ply:GetVelocity():Length2D() > 150 then
		lo, hi = lo * 0.25, hi * 0.25
	end
	nextRegrip = CurTime() + math.Rand(lo, hi)
end

local function FireRegrip()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local pool = GetEligiblePresets()
	if #pool == 0 then return end

	local strength = GetConVar("camerashakify_regrip_intensity"):GetFloat()
	local vol = math.Clamp(GetConVar("camerashakify_regrip_volume"):GetFloat(), 0, 1)
	local isLong = math.Rand(0, 1) < GetConVar("camerashakify_regrip_long_chance"):GetFloat()

	local soundPath, duration
	if isLong then
		local idx = PickIndex(lastLongIdx)
		lastLongIdx = idx
		soundPath = longFoleys[idx]
		duration = math.Rand(2.8, 4.2)
	else
		local idx = PickIndex(lastShortIdx)
		lastShortIdx = idx
		soundPath = shortFoleys[idx]
		duration = math.Rand(0.9, 2.0)
	end

	if vol > 0 then
		local snd = CreateSound(ply, soundPath)
		if snd then
			snd:PlayEx(vol, 100)
			timer.Simple(duration + 1, function() if snd then snd:Stop() end end)
		end
	end

	-- steal a random slice of a captured preset instead of making up random shake math
	-- played back way faster than its normal pace so it reads as a jolt
	local presetKey = pool[math.random(#pool)]
	local preset = CameraShakify.Shakes[presetKey]
	local randomStart = math.Rand(0, preset.frames / preset.fps)
	local playSpeed = isLong and math.Rand(1.6, 2.2) or math.Rand(2.4, 3.4)

	if activeRegripID then CameraShakify.Remove(activeRegripID, 0.2) end

	activeRegripID = CameraShakify.Add(presetKey, {
		influence = strength,
		scale = math.Rand(1.6, 2.4) * strength,
		rotScale = math.Rand(1.8, 2.8) * strength,
		speed = playSpeed,
		offset = randomStart,
		fadeIn = math.Rand(0.25, 0.4),
	})

	local thisID = activeRegripID
	timer.Simple(duration, function()
		if activeRegripID == thisID then
			CameraShakify.Remove(activeRegripID, math.max(duration * 0.35, 0.4))
			activeRegripID = nil
		end
	end)
end

hook.Add("Think", "CameraShakify_RegripThink", function()
	local cv = GetConVar("camerashakify_regrip_enabled")
	if not cv:GetBool() then return end
	if CurTime() >= nextRegrip then
		FireRegrip()
		ScheduleNext()
	end
end)

hook.Add("InitPostEntity", "CameraShakify_RegripInit", ScheduleNext)
hook.Add("Think", "CameraShakify_RegripFirstThink", function()
	if nextRegrip == 0 then ScheduleNext() end
	hook.Remove("Think", "CameraShakify_RegripFirstThink")
end)

-- version of the blender plugin stack/workflow but in source??? im sourcing it bwro...

CameraShakify.Layers = CameraShakify.Layers or {}
CameraShakify.NextLayerID = CameraShakify.NextLayerID or 1

local LAYERS_PATH = "camerashakify_layers.txt"

local function SaveLayers()
	local out = {}
	for i, layer in ipairs(CameraShakify.Layers) do
		out[i] = { id = layer.id, preset = layer.preset, scale = layer.scale, speed = layer.speed, influence = layer.influence }
	end
	file.Write(LAYERS_PATH, util.TableToJSON(out))
end

local function SpawnLayerInstance(layer)
	layer.activeID = CameraShakify.Add(layer.preset, {
		scale = layer.scale, rotScale = layer.scale, speed = layer.speed, influence = layer.influence, fadeIn = 0.4,
	})
end

local function LoadLayers()
	if not file.Exists(LAYERS_PATH, "DATA") then return end
	local data = util.JSONToTable(file.Read(LAYERS_PATH, "DATA") or "")
	if not data then return end

	local maxID = 0
	for _, entry in ipairs(data) do
		if CameraShakify.Shakes[entry.preset] then
			local layer = {
				id = entry.id, preset = entry.preset,
				scale = entry.scale or 1, speed = entry.speed or 1, influence = entry.influence or 1,
			}
			CameraShakify.Layers[#CameraShakify.Layers + 1] = layer
			maxID = math.max(maxID, entry.id)
			SpawnLayerInstance(layer)
		end
	end
	CameraShakify.NextLayerID = maxID + 1
end

function CameraShakify.AddLayer(presetKey)
	if not CameraShakify.Shakes[presetKey] then return end

	local layer = { id = CameraShakify.NextLayerID, preset = presetKey, scale = 1, speed = 1, influence = 1 }
	CameraShakify.NextLayerID = CameraShakify.NextLayerID + 1

	CameraShakify.Layers[#CameraShakify.Layers + 1] = layer
	SpawnLayerInstance(layer)
	SaveLayers()
	if CameraShakify.RebuildMenu then CameraShakify.RebuildMenu() end
end

function CameraShakify.RemoveLayer(layerId)
	for i, layer in ipairs(CameraShakify.Layers) do
		if layer.id == layerId then
			if layer.activeID then CameraShakify.Remove(layer.activeID, 0.4) end
			table.remove(CameraShakify.Layers, i)
			break
		end
	end
	SaveLayers()
	if CameraShakify.RebuildMenu then CameraShakify.RebuildMenu() end
end

function CameraShakify.UpdateLayer(layerId, field, value)
	for _, layer in ipairs(CameraShakify.Layers) do
		if layer.id == layerId then
			layer[field] = value
			local inst = layer.activeID and CameraShakify.Active[layer.activeID]
			if inst then
				if field == "scale" then
					inst.scale, inst.rotScale = value, value
				elseif field == "speed" then
					inst.speed = value
				elseif field == "influence" and not inst.fadeOutTime then
					inst.influence = value
				end
			end
			SaveLayers()
			break
		end
	end
end

LoadLayers()


-- presets - save/load a full snapshot (settings + layer stack) to disk in garrysmod/data
-- two flavors: full ones down here, layer-only ones further down for people who just want to swap their shake stack around without nuking their other settings


local PRESET_CONVARS = {
	"camerashakify_enabled", "camerashakify_scale", "camerashakify_speed", "camerashakify_influence", "camerashakify_variance",
	"camerashakify_tilt_enabled", "camerashakify_tilt_strength", "camerashakify_zoomsmooth_enabled",
	"camerashakify_state_idle_preset", "camerashakify_state_walk_preset", "camerashakify_state_run_preset",
	"camerashakify_regrip_enabled", "camerashakify_regrip_intensity", "camerashakify_regrip_volume", "camerashakify_regrip_long_chance",
}

local function PresetPath(name)
	return "camerashakify/presets/" .. name .. ".txt"
end

local function LayerPresetPath(name)
	return "camerashakify/layer_presets/" .. name .. ".txt"
end

-- console AND chat, so you actually notice it happened instead of wondering if it silently died
local function Notify(msg)
	print("[Camera Shakify] " .. msg)
	if chat and chat.AddText then
		chat.AddText(Color(120, 165, 220), "[Camera Shakify] ", Color(255, 255, 255), msg)
	end
end

function CameraShakify.SavePreset(name)
	if not name or name == "" then return false end

	local convars = {}
	for _, cvName in ipairs(PRESET_CONVARS) do
		convars[cvName] = GetConVar(cvName):GetString()
	end
	for _, key in ipairs(CameraShakify.ShakeOrder) do
		local cvName = "camerashakify_regrip_use_" .. key
		convars[cvName] = GetConVar(cvName):GetString()
	end

	local layers = {}
	for i, layer in ipairs(CameraShakify.Layers) do
		layers[i] = { preset = layer.preset, scale = layer.scale, speed = layer.speed, influence = layer.influence }
	end

	file.CreateDir("camerashakify/presets")
	file.Write(PresetPath(name), util.TableToJSON({ convars = convars, layers = layers }, true))
	Notify("saved preset '" .. name .. "'")
	return true
end

function CameraShakify.LoadPreset(name)
	local path = PresetPath(name)
	if not file.Exists(path, "DATA") then
		Notify("no preset called '" .. tostring(name) .. "'")
		return false
	end

	local ok, data = pcall(util.JSONToTable, file.Read(path, "DATA") or "")
	if not ok or not data then
		Notify("preset '" .. name .. "' is corrupted and couldn't be read")
		return false
	end

	if data.convars then
		for cvName, value in pairs(data.convars) do
			RunConsoleCommand(cvName, tostring(value))
		end
	end

	if data.layers then
		for _, layer in ipairs(CameraShakify.Layers) do
			if layer.activeID then CameraShakify.Remove(layer.activeID) end
		end
		CameraShakify.Layers = {}

		for _, entry in ipairs(data.layers) do
			if CameraShakify.Shakes[entry.preset] then
				CameraShakify.AddLayer(entry.preset)
				local newLayer = CameraShakify.Layers[#CameraShakify.Layers]
				CameraShakify.UpdateLayer(newLayer.id, "scale", entry.scale or 1)
				CameraShakify.UpdateLayer(newLayer.id, "speed", entry.speed or 1)
				CameraShakify.UpdateLayer(newLayer.id, "influence", entry.influence or 1)
			end
		end
	end

	-- RunConsoleCommand QUEUES the change instead of applying it right away, learned that one
	-- the hard way - rebuild the menu next tick or it'll show stale values like nothing happened
	timer.Simple(0, function()
		if CameraShakify.RebuildMenu then CameraShakify.RebuildMenu() end
	end)

	Notify("loaded preset '" .. name .. "'")
	return true
end

function CameraShakify.ListPresets()
	local names = {}
	for _, f in ipairs(file.Find("camerashakify/presets/*.txt", "DATA")) do
		names[#names + 1] = string.StripExtension(f)
	end
	return names
end

function CameraShakify.DeletePreset(name)
	local path = PresetPath(name)
	if not file.Exists(path, "DATA") then return false end
	file.Delete(path)
	Notify("deleted preset '" .. name .. "'")
	return true
end

-- layer presets, you probably aren't reading my schizo babble, and if you are, may god have mercy on you

function CameraShakify.SaveLayerPreset(name)
	if not name or name == "" then return false end

	local layers = {}
	for i, layer in ipairs(CameraShakify.Layers) do
		layers[i] = { preset = layer.preset, scale = layer.scale, speed = layer.speed, influence = layer.influence }
	end

	file.CreateDir("camerashakify/layer_presets")
	file.Write(LayerPresetPath(name), util.TableToJSON(layers, true))
	Notify("saved layer preset '" .. name .. "'")
	return true
end

function CameraShakify.LoadLayerPreset(name)
	local path = LayerPresetPath(name)
	if not file.Exists(path, "DATA") then
		Notify("no layer preset called '" .. tostring(name) .. "'")
		return false
	end

	local ok, data = pcall(util.JSONToTable, file.Read(path, "DATA") or "")
	if not ok or not data then
		Notify("layer preset '" .. name .. "' is corrupted and couldn't be read")
		return false
	end

	for _, layer in ipairs(CameraShakify.Layers) do
		if layer.activeID then CameraShakify.Remove(layer.activeID) end
	end
	CameraShakify.Layers = {}

	for _, entry in ipairs(data) do
		if CameraShakify.Shakes[entry.preset] then
			CameraShakify.AddLayer(entry.preset)
			local newLayer = CameraShakify.Layers[#CameraShakify.Layers]
			CameraShakify.UpdateLayer(newLayer.id, "scale", entry.scale or 1)
			CameraShakify.UpdateLayer(newLayer.id, "speed", entry.speed or 1)
			CameraShakify.UpdateLayer(newLayer.id, "influence", entry.influence or 1)
		end
	end

	if CameraShakify.RebuildMenu then CameraShakify.RebuildMenu() end
	Notify("loaded layer preset '" .. name .. "'")
	return true
end

function CameraShakify.ListLayerPresets()
	local names = {}
	for _, f in ipairs(file.Find("camerashakify/layer_presets/*.txt", "DATA")) do
		names[#names + 1] = string.StripExtension(f)
	end
	return names
end

function CameraShakify.DeleteLayerPreset(name)
	local path = LayerPresetPath(name)
	if not file.Exists(path, "DATA") then return false end
	file.Delete(path)
	Notify("deleted layer preset '" .. name .. "'")
	return true
end

concommand.Add("camerashakify_preset_save", function(_, _, args)
	if not args[1] then print("usage: camerashakify_preset_save <name>") return end
	CameraShakify.SavePreset(args[1])
end)

concommand.Add("camerashakify_preset_load", function(_, _, args)
	if not args[1] then print("usage: camerashakify_preset_load <name>") return end
	CameraShakify.LoadPreset(args[1])
end)

concommand.Add("camerashakify_preset_list", function()
	for _, name in ipairs(CameraShakify.ListPresets()) do print(name) end
end)

concommand.Add("camerashakify_preset_delete", function(_, _, args)
	if not args[1] then print("usage: camerashakify_preset_delete <name>") return end
	CameraShakify.DeletePreset(args[1])
end)

print("[Camera Shakify port by YOUR NAME HERE] loaded, " .. #CameraShakify.ShakeOrder .. " presets, " .. #CameraShakify.Layers .. " layers restored from last time")
