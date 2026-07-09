-- handles the actual shake math, the idle/walk/run auto-switcher, and the ambient tilt, this that the other
-- ported the shake curves over from the Blender addon of the same name (all credit to those fellows for the actual motion data, I just made it work in Source engine, which was not as annoying as i'd think it would be)

CreateClientConVar("camerashakify_enabled", "1", true, false, "auto idle/walk/run shake", 0, 1)
CreateClientConVar("camerashakify_scale", "1", true, false, "shake amplitude", 0, 3)
CreateClientConVar("camerashakify_speed", "1", true, false, "shake playback speed", 0.25, 3)
CreateClientConVar("camerashakify_influence", "1", true, false, "shake strength", 0, 2)
CreateClientConVar("camerashakify_variance", "0.4", true, false, "loop-to-loop drift amount", 0, 1)
CreateClientConVar("camerashakify_tilt_enabled", "1", true, false, "ambient camera lean", 0, 1)
CreateClientConVar("camerashakify_tilt_strength", "1", true, false, "tilt strength", 0, 2)
CreateClientConVar("camerashakify_zoomsmooth_enabled", "1", true, false, "smooth fov transitions", 0, 1)
CreateClientConVar("camerashakify_state_idle_preset", "INVESTIGATION", true, false, "idle state preset")
CreateClientConVar("camerashakify_state_walk_preset", "WALK_TO_THE_STORE", true, false, "walk state preset")
CreateClientConVar("camerashakify_state_run_preset", "HANDYCAM_RUN", true, false, "run state preset")

CameraShakify = CameraShakify or {}
CameraShakify.Active = CameraShakify.Active or {}
CameraShakify.NextID = CameraShakify.NextID or 0

local active = CameraShakify.Active

-- caching these up here so I'm not doing a GetConVar lookup every single frame
local SCALE     = GetConVar("camerashakify_scale")
local SPEED     = GetConVar("camerashakify_speed")
local INFLUENCE = GetConVar("camerashakify_influence")
local VARIANCE  = GetConVar("camerashakify_variance")

local function LerpFrame(a, b, t)
	return
		Lerp(t, a[1], b[1]), Lerp(t, a[2], b[2]), Lerp(t, a[3], b[3]),
		Lerp(t, a[4], b[4]), Lerp(t, a[5], b[5]), Lerp(t, a[6], b[6])
end

-- basic polynomial that just makes stuff feel a lot less jank
local function Smoothstep(t)
	t = math.Clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- grabs the (right, up, fwd, pitch, yaw, roll) offset for a preset at time t, looping forever.
-- data is baked per-frame so this is just an array lookup + lerp
function CameraShakify.Sample(shakeKey, t)
	local shake = CameraShakify.Shakes[shakeKey]
	if not shake then return 0, 0, 0, 0, 0, 0 end

	local frameCount = shake.frames
	local fdata = shake.data
	local frame = (t * shake.fps) % frameCount
	local i0 = math.floor(frame)
	local i1 = (i0 + 1) % frameCount
	local f = frame - i0

	local b0, b1 = i0 * 6, i1 * 6
	local a = { fdata[b0+1], fdata[b0+2], fdata[b0+3], fdata[b0+4], fdata[b0+5], fdata[b0+6] }
	local b = { fdata[b1+1], fdata[b1+2], fdata[b1+3], fdata[b1+4], fdata[b1+5], fdata[b1+6] }
	return LerpFrame(a, b, f)
end

-- spins up a new active shake layer. call this from wherever lol it just returns an ID
function CameraShakify.Add(shakeKey, opts)
	if not CameraShakify.Shakes[shakeKey] then
		error("CameraShakify: unknown preset '" .. tostring(shakeKey) .. "' - typo somewhere?")
	end
	opts = opts or {}

	CameraShakify.NextID = CameraShakify.NextID + 1
	local id = CameraShakify.NextID

	active[id] = {
		key = shakeKey,
		influence = opts.influence or 1,
		scale = opts.scale or 1,
		rotScale = opts.rotScale or 1,
		speed = opts.speed or 1,
		startTime = CurTime() - (opts.offset or 0),
		fadeIn = opts.fadeIn or 0,
		fadeOutTime = nil,
		fadeOutDuration = 0,
		removeAt = nil,
		varSeed1 = math.Rand(0, 1000),
		varSeed2 = math.Rand(0, 1000),
		varFreq1 = math.Rand(0.05, 0.11),
		varFreq2 = math.Rand(0.13, 0.21),
	}

	return id
end

-- fadetime so it doesn't yank or something...
function CameraShakify.Remove(id, fadeTime)
	local inst = active[id]
	if not inst then return end

	if fadeTime and fadeTime > 0 then
		inst.fadeOutTime = CurTime()
		inst.fadeOutDuration = fadeTime
		inst.fadeOutStartInfluence = inst.influence
		inst.removeAt = CurTime() + fadeTime
	else
		active[id] = nil
	end
end

function CameraShakify.Clear()
	table.Empty(active)
end

-- sums up every active shake into one offset. this runs every single frame, good luck if you have a cpu below 2 cor es
local function GetCombinedOffset()
	local rt, up, fwd, pitch, yaw, roll = 0, 0, 0, 0, 0, 0
	local now = CurTime()
	local varAmt = VARIANCE:GetFloat()

	for id, inst in pairs(active) do
		if inst.removeAt and now >= inst.removeAt then
			active[id] = nil
		else
			local infl = inst.influence
			if inst.fadeOutTime then
				local t = (now - inst.fadeOutTime) / inst.fadeOutDuration
				infl = Lerp(Smoothstep(t), inst.fadeOutStartInfluence, 0)
			elseif inst.fadeIn > 0 then
				local t = (now - inst.startTime) / inst.fadeIn
				infl = infl * Smoothstep(t)
			end

			if infl > 0 then
				local speedDrift = 1 + varAmt * 0.18 * (
					math.sin(now * inst.varFreq1 + inst.varSeed1) * 0.6 +
					math.sin(now * inst.varFreq2 + inst.varSeed2) * 0.4
				)
				local scaleDrift = 1 + varAmt * 0.12 * math.sin(now * inst.varFreq2 * 0.7 + inst.varSeed1 * 1.7)

				local t = (now - inst.startTime) * inst.speed * speedDrift
				local r, u, f, p, y, ro = CameraShakify.Sample(inst.key, t)
				local scale = inst.scale * scaleDrift
				rt   = rt   + r  * scale    * infl
				up   = up   + u  * scale    * infl
				fwd  = fwd  + f  * scale    * infl
				pitch = pitch + p * inst.rotScale * infl
				yaw   = yaw   + y * inst.rotScale * infl
				roll  = roll  + ro * inst.rotScale * infl
			end
		end
	end

	return rt, up, fwd, pitch, yaw, roll
end



-- ambient tilt, just slow leaning that goes left/right, thought it'd be weird not to implement this

CameraShakify.TiltRoll = 0
local curTiltRoll = 0
local tiltPhase = math.Rand(0, 10)
local TILT_ENABLED = GetConVar("camerashakify_tilt_enabled")
local TILT_STRENGTH = GetConVar("camerashakify_tilt_strength")

hook.Add("Think", "CameraShakify_Tilt", function()
	local target = 0
	if TILT_ENABLED:GetBool() then
		local t = CurTime() * 0.4 + tiltPhase
		target = math.sin(t + 1.3) * 3.2 * TILT_STRENGTH:GetFloat()
	end
	curTiltRoll = Lerp(math.Clamp(FrameTime() * 4, 0, 1), curTiltRoll, target)
	CameraShakify.TiltRoll = curTiltRoll
end)

-- auto switcher for running walking and idle, i could add stuff for mid air here later WITH noclip ignore, incredibly auspicious

local ENABLED = GetConVar("camerashakify_enabled")
local FADE_TIME = 0.5
local DEBOUNCE = 0.12
local STATE_FALLBACK = { IDLE = "INVESTIGATION", WALK = "WALK_TO_THE_STORE", RUN = "HANDYCAM_RUN" }

local currentState, currentID, currentPreset
local pendingState, pendingSince = nil, 0

local function GetStatePreset(stateName)
	local cv = GetConVar("camerashakify_state_" .. string.lower(stateName) .. "_preset")
	local key = cv and cv:GetString()
	if key and CameraShakify.Shakes[key] then return key end
	return STATE_FALLBACK[stateName]
end

local function DetermineState(ply)
	if not IsValid(ply) or not ply:Alive() then return "OFF" end
	if ply:InVehicle() then return "OFF" end

	local mt = ply:GetMoveType()
	if mt == MOVETYPE_NOCLIP or mt == MOVETYPE_OBSERVER then return "OFF" end
	if not ply:IsOnGround() then return currentState or "IDLE" end --putting this here for future midair shakes

	local vel = ply:GetVelocity()
	local spd = Vector(vel.x, vel.y, 0):Length()
	local walkSpeed = ply:GetWalkSpeed()
	local runSpeed = ply:GetRunSpeed()
	-- some gamemodes report 0 for these, no idea why, just fall back to sane defaults
	if walkSpeed <= 0 then walkSpeed = 200 end
	if runSpeed <= 0 then runSpeed = 400 end

	if spd < walkSpeed * 0.3 then return "IDLE"
	elseif spd < runSpeed * 0.7 then return "WALK"
	else return "RUN" end
end

local function SwitchTo(newState)
	currentState = newState
	if currentID then
		CameraShakify.Remove(currentID, FADE_TIME)
		currentID = nil
	end

	if newState ~= "OFF" then
		currentPreset = GetStatePreset(newState)
		currentID = CameraShakify.Add(currentPreset, {
			influence = INFLUENCE:GetFloat(),
			scale = SCALE:GetFloat(),
			rotScale = SCALE:GetFloat(),
			speed = SPEED:GetFloat(),
			fadeIn = FADE_TIME,
		})
	else
		currentPreset = nil
	end
end

hook.Add("Think", "CameraShakify_StateMachine", function()
	if not ENABLED:GetBool() then
		if currentState ~= "OFF" then SwitchTo("OFF") end
		return
	end

	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local wanted = DetermineState(ply)

	if wanted ~= currentState then
		if wanted ~= pendingState then
			pendingState = wanted
			pendingSince = CurTime()
		elseif CurTime() - pendingSince >= DEBOUNCE then
			SwitchTo(wanted)
			pendingState = nil
		end
	else
		pendingState = nil
		if currentState ~= "OFF" and GetStatePreset(currentState) ~= currentPreset then
			SwitchTo(currentState)
		end
	end

	local inst = currentID and CameraShakify.Active[currentID]
	if inst then
		inst.scale = SCALE:GetFloat()
		inst.rotScale = SCALE:GetFloat()
		inst.speed = SPEED:GetFloat()
		if not inst.fadeOutTime then
			inst.influence = INFLUENCE:GetFloat()
		end
	end
end)

-- the calcening

local smoothedFOV = nil
local smRT, smUp, smFwd, smPitch, smYaw, smRoll = 0, 0, 0, 0, 0, 0
local SMOOTH_TIME = 0.12 

hook.Add("CalcView", "CameraShakify", function(ply, pos, angles, fov)
	local rt, up, fwd, pitch, yaw, roll = 0, 0, 0, 0, 0, 0

	if next(active) ~= nil then
		rt, up, fwd, pitch, yaw, roll = GetCombinedOffset()
	end

	roll = roll + CameraShakify.TiltRoll

	-- final low-pass on top of everything else. this is the thing that actually kills the pops when a regrip or a state-switch starts mid-curve at some big value, 
	-- personal note dont remove even though it looks redundant with the smoothstep fades above, trust me you tried
	
	local smoothFrac = 1 - math.exp(-FrameTime() / SMOOTH_TIME)
	smRT    = Lerp(smoothFrac, smRT, rt)
	smUp    = Lerp(smoothFrac, smUp, up)
	smFwd   = Lerp(smoothFrac, smFwd, fwd)
	smPitch = Lerp(smoothFrac, smPitch, pitch)
	smYaw   = Lerp(smoothFrac, smYaw, yaw)
	smRoll  = Lerp(smoothFrac, smRoll, roll)

	local outFOV = fov
	local zoomCV = GetConVar("camerashakify_zoomsmooth_enabled")
	if zoomCV:GetBool() then
		if not smoothedFOV then smoothedFOV = fov end
		smoothedFOV = Lerp(math.Clamp(FrameTime() * 8, 0, 1), smoothedFOV, fov)
		outFOV = smoothedFOV
	else
		smoothedFOV = nil
	end

	if smRT == 0 and smUp == 0 and smFwd == 0 and smPitch == 0 and smYaw == 0 and smRoll == 0 and outFOV == fov then
		return
	end

	local ang = angles
	return {
		origin = pos + ang:Right() * smRT + ang:Up() * smUp + ang:Forward() * smFwd,
		angles = Angle(ang.p + smPitch, ang.y + smYaw, ang.r + smRoll),
		fov = outFOV,
	}
end)

-- debug stuff goes here, just stuff that belongs to layers but you can also access through console

local testID = nil

concommand.Add("camerashakify_add", function(ply, cmd, args)
	local key = string.upper(args[1] or "")
	if not CameraShakify.Shakes[key] then
		print("no idea what that preset is. options:")
		for _, k in ipairs(CameraShakify.ShakeOrder) do
			print("  " .. k .. "  (\"" .. CameraShakify.Shakes[k].name .. "\")")
		end
		return
	end

	if testID then CameraShakify.Remove(testID) end
	testID = CameraShakify.Add(key, {
		influence = tonumber(args[2]) or 1,
		scale = tonumber(args[3]) or 1,
		speed = tonumber(args[4]) or 1,
		fadeIn = 0.3,
	})
end, nil, "camerashakify_add <PRESET> [influence] [scale] [speed]")

concommand.Add("camerashakify_list", function()
	for _, k in ipairs(CameraShakify.ShakeOrder) do
		local s = CameraShakify.Shakes[k]
		print(string.format("  %-20s \"%s\" (%d frames @ %.0ffps)", k, s.name, s.frames, s.fps))
	end
end, nil, "list available presets")

concommand.Add("camerashakify_clear", function()
	if testID then
		CameraShakify.Remove(testID, 0.4)
		testID = nil
	end
end, nil, "stop the test effect")
