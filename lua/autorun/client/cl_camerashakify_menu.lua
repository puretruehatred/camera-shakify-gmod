--keep this in sync with the CreateClientConVar defaults in the other two files or Reset to Defaults will lie to people, which would be funny but bad, a "convar" is probably hieroglyphics to the average gmod player
local DEFAULTS = {
	camerashakify_enabled = "1",
	camerashakify_scale = "1",
	camerashakify_speed = "1",
	camerashakify_influence = "1",
	camerashakify_variance = "0.4",
	camerashakify_tilt_enabled = "1",
	camerashakify_tilt_strength = "1",
	camerashakify_zoomsmooth_enabled = "1",
	camerashakify_state_idle_preset = "INVESTIGATION",
	camerashakify_state_walk_preset = "WALK_TO_THE_STORE",
	camerashakify_state_run_preset = "HANDYCAM_RUN",
	camerashakify_regrip_enabled = "1",
	camerashakify_regrip_intensity = "1",
	camerashakify_regrip_volume = "0.6",
	camerashakify_regrip_long_chance = "0.3",
}

local function CreatePresetCombo(panel, label, cvarName)
	panel:Help(label)

	local combo = vgui.Create("DComboBox")
	combo:SetSortItems(false)
	for _, key in ipairs(CameraShakify.ShakeOrder) do
		combo:AddChoice(CameraShakify.Shakes[key].name, key)
	end

	local current = GetConVar(cvarName):GetString()
	if CameraShakify.Shakes[current] then
		combo:SetValue(CameraShakify.Shakes[current].name)
	end

	combo.OnSelect = function(_, _, _, data)
		RunConsoleCommand(cvarName, data)
	end

	panel:AddItem(combo)
end

-- not copy-pasting the same three buttons twice
local function CreatePresetControls(panel, label, listFn, saveFn, loadFn, deleteFn)
	panel:Help(label)

	local saveBtn = vgui.Create("DButton")
	saveBtn:SetText("Save As...")
	saveBtn.DoClick = function()
		Derma_StringRequest(
			"Save Preset",
			"Name this preset:",
			"",
			function(text)
				if text ~= "" then
					saveFn(text)
					if CameraShakify.RebuildMenu then CameraShakify.RebuildMenu() end
				end
			end
		)
	end
	panel:AddItem(saveBtn)

	local loadRow = vgui.Create("DPanel")
	loadRow:SetTall(24)
	loadRow.Paint = function() end

	local deleteBtn = vgui.Create("DButton", loadRow)
	deleteBtn:Dock(RIGHT)
	deleteBtn:SetWide(60)
	deleteBtn:SetText("Delete")

	local loadBtn = vgui.Create("DButton", loadRow)
	loadBtn:Dock(RIGHT)
	loadBtn:SetWide(60)
	loadBtn:DockMargin(0, 0, 6, 0)
	loadBtn:SetText("Load")

	local combo = vgui.Create("DComboBox", loadRow)
	combo:Dock(FILL)
	combo:DockMargin(0, 0, 6, 0)
	combo:SetValue(#listFn() > 0 and "Choose a shake..." or "No presets saved yet")
	for _, name in ipairs(listFn()) do
		combo:AddChoice(name)
	end

	loadBtn.DoClick = function()
		local name = combo:GetSelected()
		if name then loadFn(name) end
	end

	deleteBtn.DoClick = function()
		local name = combo:GetSelected()
		if not name then return end
		Derma_Query(
			"Delete preset \"" .. name .. "\"? This can be undone if you send me £500",
			"Delete Preset",
			"Delete", function()
				deleteFn(name)
				if CameraShakify.RebuildMenu then CameraShakify.RebuildMenu() end
			end,
			"Cancel", function() end
		)
	end

	panel:AddItem(loadRow)
end

local function BuildGeneral(panel)
	panel:ClearControls()

	panel:CheckBox("Enable Automatic Shake (idle/walk/run)", "camerashakify_enabled")
	panel:NumSlider("Scale", "camerashakify_scale", 0, 3, 2)
	panel:NumSlider("Speed", "camerashakify_speed", 0.25, 3, 2)
	panel:NumSlider("Influence", "camerashakify_influence", 0, 2, 2)
	panel:NumSlider("Variance", "camerashakify_variance", 0, 1, 2)

	CreatePresetCombo(panel, "Idle preset:", "camerashakify_state_idle_preset")
	CreatePresetCombo(panel, "Walk preset:", "camerashakify_state_walk_preset")
	CreatePresetCombo(panel, "Run preset:", "camerashakify_state_run_preset")

	local resetBtn = vgui.Create("DButton")
	resetBtn:SetText("Reset to Defaults")
	resetBtn.DoClick = function()
		for cvar, value in pairs(DEFAULTS) do
			RunConsoleCommand(cvar, value)
		end
		for _, key in ipairs(CameraShakify.ShakeOrder) do
			RunConsoleCommand("camerashakify_regrip_use_" .. key, ({
				THE_CLOSEUP = "1", THE_WEDDING = "1", OUT_CAR_WINDOW = "1", INVESTIGATION = "1",
			})[key] or "0")
		end

		-- don't rebuild the menu in the same breath or it'll show the old values
		timer.Simple(0, function()
			if CameraShakify.RebuildMenu then CameraShakify.RebuildMenu() end
		end)
	end
	panel:AddItem(resetBtn)

	panel:Help(" ")
	CreatePresetControls(
		panel,
		"Full presets (all settings + shake layers):",
		CameraShakify.ListPresets,
		CameraShakify.SavePreset,
		CameraShakify.LoadPreset,
		CameraShakify.DeletePreset
	)
end

local function BuildLayers(panel)
	panel:ClearControls()
	panel:Help("Stack extra presets on top of everything else, each with its own scale/speed/influence.")

	for i, layer in ipairs(CameraShakify.Layers) do
		local header = vgui.Create("DPanel")
		header:SetTall(22)
		header.Paint = function() end

		local nameLbl = vgui.Create("DLabel", header)
		nameLbl:Dock(LEFT)
		nameLbl:SetText(CameraShakify.Shakes[layer.preset].name)
		nameLbl:SetFont("DermaDefault")
		nameLbl:SetDark(true) 
		nameLbl:SizeToContents()

		local removeBtn = vgui.Create("DButton", header)
		removeBtn:Dock(RIGHT)
		removeBtn:SetWide(60)
		removeBtn:SetText("Remove")
		removeBtn.DoClick = function() CameraShakify.RemoveLayer(layer.id) end

		panel:AddItem(header)

		local scaleSlider = vgui.Create("DNumSlider")
		scaleSlider:SetText("Scale")
		scaleSlider:SetMin(0)
		scaleSlider:SetMax(3)
		scaleSlider:SetDecimals(2)
		scaleSlider:SetDark(true)
		scaleSlider:SetValue(layer.scale)
		scaleSlider.OnValueChanged = function(_, v) CameraShakify.UpdateLayer(layer.id, "scale", v) end
		panel:AddItem(scaleSlider)

		local speedSlider = vgui.Create("DNumSlider")
		speedSlider:SetText("Speed")
		speedSlider:SetMin(0.25)
		speedSlider:SetMax(3)
		speedSlider:SetDecimals(2)
		speedSlider:SetDark(true)
		speedSlider:SetValue(layer.speed)
		speedSlider.OnValueChanged = function(_, v) CameraShakify.UpdateLayer(layer.id, "speed", v) end
		panel:AddItem(speedSlider)

		local influenceSlider = vgui.Create("DNumSlider")
		influenceSlider:SetText("Influence")
		influenceSlider:SetMin(0)
		influenceSlider:SetMax(2)
		influenceSlider:SetDecimals(2)
		influenceSlider:SetDark(true)
		influenceSlider:SetValue(layer.influence)
		influenceSlider.OnValueChanged = function(_, v) CameraShakify.UpdateLayer(layer.id, "influence", v) end
		panel:AddItem(influenceSlider)

		if i < #CameraShakify.Layers then
			local divider = vgui.Create("DPanel")
			divider:SetTall(1)
			divider.Paint = function(self, w, h)
				surface.SetDrawColor(80, 80, 80, 255)
				surface.DrawRect(0, 0, w, h)
			end
			panel:AddItem(divider)
		end
	end

	if #CameraShakify.Layers > 0 then panel:Help(" ") end
	panel:Help("Add a shake layer:")

	local addRow = vgui.Create("DPanel")
	addRow:SetTall(24)
	addRow.Paint = function() end

	local addBtn = vgui.Create("DButton", addRow)
	addBtn:Dock(RIGHT)
	addBtn:SetWide(70)
	addBtn:SetText("Add")

	local addCombo = vgui.Create("DComboBox", addRow)
	addCombo:Dock(FILL)
	addCombo:DockMargin(0, 0, 6, 0)
	addCombo:SetSortItems(false)
	addCombo:SetValue("Choose a preset...")
	for _, key in ipairs(CameraShakify.ShakeOrder) do
		addCombo:AddChoice(CameraShakify.Shakes[key].name, key)
	end

	addBtn.DoClick = function()
		local _, presetKey = addCombo:GetSelected()
		if presetKey then CameraShakify.AddLayer(presetKey) end
	end
	panel:AddItem(addRow)

	panel:Help(" ")
	CreatePresetControls(
		panel,
		"Layer presets (just this stack):",
		CameraShakify.ListLayerPresets,
		CameraShakify.SaveLayerPreset,
		CameraShakify.LoadLayerPreset,
		CameraShakify.DeleteLayerPreset
	)
end

local function BuildMisc(panel)
	panel:ClearControls()
	panel:Help("Everything below isn't part of the original Blender addon.")

	panel:CheckBox("View Tilt (ambient camera lean)", "camerashakify_tilt_enabled")
	panel:NumSlider("Tilt Strength", "camerashakify_tilt_strength", 0, 2, 2)

	panel:CheckBox("Smooth Zoom Transitions", "camerashakify_zoomsmooth_enabled")

	panel:CheckBox("Camera Re-Grips", "camerashakify_regrip_enabled")
	panel:NumSlider("Re-Grip Intensity", "camerashakify_regrip_intensity", 0, 2, 2)
	panel:NumSlider("Re-Grip Foley Volume", "camerashakify_regrip_volume", 0, 1, 2)
	panel:NumSlider("Long Fumble Chance", "camerashakify_regrip_long_chance", 0, 1, 2)

	panel:Help("Presets eligible for camera re-grips:")
	for _, key in ipairs(CameraShakify.ShakeOrder) do
		panel:CheckBox(CameraShakify.Shakes[key].name, "camerashakify_regrip_use_" .. key)
	end
end

hook.Add("PopulateToolMenu", "CameraShakify_ToolMenu", function()
	spawnmenu.AddToolMenuOption("Options", "Camera Shakify", "CameraShakifyGeneral", "General", "", "", function(panel)
		CameraShakify.GeneralMenuPanel = panel
		BuildGeneral(panel)
	end)

	spawnmenu.AddToolMenuOption("Options", "Camera Shakify", "CameraShakifyLayers", "Shake Layers", "", "", function(panel)
		CameraShakify.LayersMenuPanel = panel
		BuildLayers(panel)
	end)

	spawnmenu.AddToolMenuOption("Options", "Camera Shakify", "CameraShakifyMisc", "Misc", "", "", function(panel)
		BuildMisc(panel)
	end)
end)

function CameraShakify.RebuildMenu()
	if IsValid(CameraShakify.LayersMenuPanel) then BuildLayers(CameraShakify.LayersMenuPanel) end
	if IsValid(CameraShakify.GeneralMenuPanel) then BuildGeneral(CameraShakify.GeneralMenuPanel) end
end
