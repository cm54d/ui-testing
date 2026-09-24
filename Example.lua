local repo = "https://raw.githubusercontent.com/cm54d/ui-testing/main/"

local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = getgenv().Options
local Toggles = getgenv().Toggles

Library.ShowToggleFrameInKeybinds = true -- Make toggle keybinds work inside the keybinds UI (aka adds a toggle to the UI). Good for mobile users (Default value = true)
Library.ShowCustomCursor = true -- Toggles the Linoria cursor globaly (Default value = true)
Library.NotifySide = "Left" -- Changes the side of the notifications globaly (Left, Right) (Default value = Left)

local Window = Library:CreateWindow({
	Title = "Example menu",
	Center = true,
	AutoShow = true,
	Resizable = true,
	ShowCustomCursor = true,
	UnlockMouseWhileOpen = true,
	NotifySide = "Left",
	TabPadding = 8,
	MenuFadeTime = 0.2
})

local Tabs = {
	Main = Window:AddTab("Main"),
	["UI Settings"] = Window:AddTab("UI Settings"),
}

local LeftGroupBox = Tabs.Main:AddLeftGroupbox("Groupbox")

LeftGroupBox:AddToggle("MyToggle", {
	Text = "This is a toggle",
	Tooltip = "This is a tooltip",
	DisabledTooltip = "I am disabled!",
	Default = true,
	Disabled = false,
	Visible = true,
	Risky = false,
	Callback = function(Value)
		print("[cb] MyToggle changed to:", Value)
	end
}):AddColorPicker("ColorPicker1", {
	Default = Color3.new(1, 0, 0),
	Title = "Some color1",
	Transparency = 0,
	Callback = function(Value, Transparency)
		print("[cb] Color changed!", Value, "| Transparency changed to:", Transparency)
	end
}):AddColorPicker("ColorPicker2", {
	Default = Color3.new(0, 1, 0),
	Title = "Some color2",
	Transparency = 0,
	Callback = function(Value, Transparency)
		print("[cb] Color changed!", Value, "| Transparency changed to:", Transparency)
	end
}):AddColorPicker("ColorPicker3", {
	Default = Color3.new(0, 0, 1),
	Title = "Some color3",
	Transparency = 0,
	Callback = function(Value, Transparency)
		print("[cb] Color changed!", Value, "| Transparency changed to:", Transparency)
	end
})

Toggles.MyToggle:OnChanged(function()
	print("MyToggle changed to:", Toggles.MyToggle.Value)
end)
Toggles.MyToggle:SetValue(false)

local MyButton = LeftGroupBox:AddButton({
	Text = "Button",
	Func = function()
		print("You clicked a button!")
		Library:Notify("This is a notification")
	end,
	DoubleClick = false,
	Tooltip = "This is the main button",
	DisabledTooltip = "I am disabled!",
	Disabled = false,
	Visible = true
})

local MyButton2 = MyButton:AddButton({
	Text = "Sub button",
	Func = function()
		print("You clicked a sub button!")
		Library:Notify("This is a notification with sound", nil, 4590657391)
	end,
	DoubleClick = true,
	Tooltip = "This is the sub button (double click me!)"
})

local MyDisabledButton = LeftGroupBox:AddButton({
	Text = "Disabled Button",
	Func = function()
		print("You somehow clicked a disabled button!")
	end,
	DoubleClick = false,
	Tooltip = "This is a disabled button",
	DisabledTooltip = "I am disabled!",
	Disabled = true
})

LeftGroupBox:AddLabel("This is a label")
LeftGroupBox:AddLabel("This is a label\n\nwhich wraps its text!", true)
LeftGroupBox:AddLabel("This is a label exposed to Labels", true, "TestLabel")
LeftGroupBox:AddLabel("SecondTestLabel", {
	Text = "This is a label made with table options and an index",
	DoesWrap = true
})
LeftGroupBox:AddLabel("SecondTestLabel", {
	Text = "This is a label that doesn\"t wrap it\"s own text",
	DoesWrap = false
})

LeftGroupBox:AddDivider()

LeftGroupBox:AddSlider("MySlider", {
	Text = "This is my slider!",
	Default = 0,
	Min = 0,
	Max = 5,
	Rounding = 1,
	Compact = false,
	Callback = function(Value)
		print("[cb] MySlider was changed! New value:", Value)
	end,
	Tooltip = "I am a slider!",
	DisabledTooltip = "I am disabled!",
	Disabled = false,
	Visible = true,
})

local Number = Options.MySlider.Value
Options.MySlider:OnChanged(function()
	print("MySlider was changed! New value:", Options.MySlider.Value)
end)
Options.MySlider:SetValue(3)

LeftGroupBox:AddSlider("MySlider2", {
	Text = "This is my custom display slider!",
	Default = 0,
	Min = 0,
	Max = 5,
	Rounding = 1,
	Compact = false,
	FormatDisplayValue = function(slider, value)
		if value == slider.Max then return "Everything" end
		if value == slider.Min then return "Nothing" end
	end,
	Tooltip = "I am a slider!",
	DisabledTooltip = "I am disabled!",
	Disabled = false,
	Visible = true,
})

LeftGroupBox:AddInput("MyTextbox", {
	Default = "My textbox!",
	Numeric = false,
	Finished = false,
	ClearTextOnFocus = true,
	Text = "This is a textbox",
	Tooltip = "This is a tooltip",
	Placeholder = "Placeholder text",
	Callback = function(Value)
		print("[cb] Text updated. New text:", Value)
	end
})

Options.MyTextbox:OnChanged(function()
	print("Text updated. New text:", Options.MyTextbox.Value)
end)

local DropdownGroupBox = Tabs.Main:AddRightGroupbox("Dropdowns")

DropdownGroupBox:AddDropdown("MyDropdown", {
	Values = { "This", "is", "a", "dropdown" },
	Default = 1,
	Multi = false,
	Text = "A dropdown",
	Tooltip = "This is a tooltip",
	DisabledTooltip = "I am disabled!",
	Searchable = false,
	Callback = function(Value)
		print("[cb] Dropdown got changed. New value:", Value)
	end,
	Disabled = false,
	Visible = true,
})

Options.MyDropdown:OnChanged(function()
	print("Dropdown got changed. New value:", Options.MyDropdown.Value)
end)
Options.MyDropdown:SetValue("This")

DropdownGroupBox:AddDropdown("MySearchableDropdown", {
	Values = { "This", "is", "a", "searchable", "dropdown" },
	Default = 1,
	Multi = false,
	Text = "A searchable dropdown",
	Tooltip = "This is a tooltip",
	DisabledTooltip = "I am disabled!",
	Searchable = true,
	Callback = function(Value)
		print("[cb] Dropdown got changed. New value:", Value)
	end,
	Disabled = false,
	Visible = true,
})

DropdownGroupBox:AddDropdown("MyDisplayFormattedDropdown", {
	Values = { "This", "is", "a", "formatted", "dropdown" },
	Default = 1,
	Multi = false,
	Text = "A display formatted dropdown",
	Tooltip = "This is a tooltip",
	DisabledTooltip = "I am disabled!",
	FormatDisplayValue = function(Value)
		if Value == "formatted" then
			return "display formatted"
		end;
		return Value
	end,
	Searchable = false,
	Callback = function(Value)
		print("[cb] Display formatted dropdown got changed. New value:", Value)
	end,
	Disabled = false,
	Visible = true,
})

DropdownGroupBox:AddDropdown("MyMultiDropdown", {
	Values = { "This", "is", "a", "dropdown" },
	Default = 1,
	Multi = true,
	Text = "A multi dropdown",
	Tooltip = "This is a tooltip",
	Callback = function(Value)
		print("[cb] Multi dropdown got changed:")
		for key, value in next, Options.MyMultiDropdown.Value do
			print(key, value)
		end
	end
})

Options.MyMultiDropdown:SetValue({
	This = true,
	is = true,
})

DropdownGroupBox:AddDropdown("MyDisabledDropdown", {
    Values = { "This", "is", "a", "dropdown" },
    Default = 1,
    Multi = false,
    Text = "A disabled dropdown",
    Tooltip = "This is a tooltip",
    DisabledTooltip = "I am disabled!",
    Callback = function(Value)
        print("[cb] Disabled dropdown got changed. New value:", Value)
    end,
    Disabled = true,
    Visible = true,
})

DropdownGroupBox:AddDropdown("MyDisabledValueDropdown", {
    Values = { "This", "is", "a", "dropdown", "with", "disabled", "value" },
    DisabledValues = { "disabled" },
    Default = 1,
    Multi = false,
    Text = "A dropdown with disabled value",
    Tooltip = "This is a tooltip",
    DisabledTooltip = "I am disabled!",
    Callback = function(Value)
        print("[cb] Dropdown with disabled value got changed. New value:", Value)
    end,
    Disabled = false,
    Visible = true,
})

DropdownGroupBox:AddDropdown("MyVeryLongDropdown", {
	Values = { "This", "is", "a", "very", "long", "dropdown", "with", "a", "lot", "of", "values", "but", "you", "can", "see", "more", "than", "8", "values" },
	Default = 1,
	Multi = false,
	MaxVisibleDropdownItems = 12,
	Text = "A very long dropdown",
	Tooltip = "This is a tooltip",
	DisabledTooltip = "I am disabled!",
	Searchable = false,
	Callback = function(Value)
		print("[cb] Very long dropdown got changed. New value:", Value)
	end,
	Disabled = false,
	Visible = true,
})

DropdownGroupBox:AddDropdown("MyPlayerDropdown", {
	SpecialType = "Player",
	ExcludeLocalPlayer = true,
	Text = "A player dropdown",
	Tooltip = "This is a tooltip",
	Callback = function(Value)
		print("[cb] Player dropdown got changed:", Value)
	end
})

DropdownGroupBox:AddDropdown("MyTeamDropdown", {
	SpecialType = "Team",
	Text = "A team dropdown",
	Tooltip = "This is a tooltip",
	Callback = function(Value)
		print("[cb] Team dropdown got changed:", Value)
	end
})

LeftGroupBox:AddLabel("Color"):AddColorPicker("ColorPicker", {
	Default = Color3.new(0, 1, 0),
	Title = "Some color",
	Transparency = 0,
	Callback = function(Value)
		print("[cb] Color changed!", Value)
	end
})

Options.ColorPicker:OnChanged(function()
	print("Color changed!", Options.ColorPicker.Value)
	print("Transparency changed!", Options.ColorPicker.Transparency)
end)
Options.ColorPicker:SetValueRGB(Color3.fromRGB(0, 255, 140))

LeftGroupBox:AddLabel("Keybind"):AddKeyPicker("KeyPicker", {
	Default = "MB2",
	SyncToggleState = false,
	Mode = "Toggle",
	Text = "Auto lockpick safes",
	NoUI = false,
	Callback = function(Value)
		print("[cb] Keybind clicked!", Value)
	end,
	ChangedCallback = function(NewKey, NewModifiers)
		print("[cb] Keybind changed!", NewKey, table.unpack(NewModifiers or {}))
	end,
})

Options.KeyPicker:OnClick(function()
	print("Keybind clicked!", Options.KeyPicker:GetState())
end)
Options.KeyPicker:OnChanged(function()
	print("Keybind changed!", Options.KeyPicker.Value, table.unpack(Options.KeyPicker.Modifiers or {}))
end)

task.spawn(function()
	while task.wait(1) do
		local state = Options.KeyPicker:GetState()
		if state then
			print("KeyPicker is being held down")
		end
		if Library.Unloaded then break end
	end
end)
Options.KeyPicker:SetValue({ "MB2", "Hold" })

local KeybindNumber = 0
LeftGroupBox:AddLabel("Press Keybind"):AddKeyPicker("KeyPicker2", {
	Default = "X",
	Mode = "Press",
	WaitForCallback = false,
	Text = "Increase Number",
	Callback = function()
		KeybindNumber = KeybindNumber + 1
		print("[cb] Keybind clicked! Number increased to:", KeybindNumber)
	end
})

LeftGroupBox:AddDropdown("MyDropdown2", {
	Text = "Compact Dropdown",
	Values = { "Addon", "Dropdown" },
	Default = 1,
	Multi = false,
	Tooltip = "This is a tooltip",
	DisabledTooltip = "I am disabled!",
	Searchable = false,
	Callback = function(Value)
		print("[cb] Dropdown got changed. New value:", Value)
	end,
	Disabled = false,
	Visible = true,
})

local LeftGroupBox2 = Tabs.Main:AddLeftGroupbox("Groupbox #2");
LeftGroupBox2:AddLabel("Oh no...\nThis label spans multiple lines!\n\nWe\'re gonna run out of UI space...\nJust kidding! Scroll down!\n\n\nHello from below!", true)

local TabBox = Tabs.Main:AddRightTabbox()
local Tab1 = TabBox:AddTab("Tab 1")
Tab1:AddToggle("Tab1Toggle", { Text = "Tab1 Toggle" });
local Tab2 = TabBox:AddTab("Tab 2")
Tab2:AddToggle("Tab2Toggle", { Text = "Tab2 Toggle" });

local RightGroupbox = Tabs.Main:AddRightGroupbox("Groupbox #3");
RightGroupbox:AddToggle("ControlToggle", { Text = "Dependency box toggle" });
local Depbox = RightGroupbox:AddDependencyBox();
Depbox:AddToggle("DepboxToggle", { Text = "Sub-dependency box toggle" });
local SubDepbox = Depbox:AddDependencyBox();
SubDepbox:AddSlider("DepboxSlider", { Text = "Slider", Default = 50, Min = 0, Max = 100, Rounding = 0 });
SubDepbox:AddDropdown("DepboxDropdown", { Text = "Dropdown", Default = 1, Values = {"a", "b", "c"} });
local SecretDepbox = SubDepbox:AddDependencyBox();
SecretDepbox:AddLabel("You found a seĉret!")
Depbox:SetupDependencies({
	{ Toggles.ControlToggle, true }
});
SubDepbox:SetupDependencies({
	{ Toggles.DepboxToggle, true }
});
SecretDepbox:SetupDependencies({
	{ Options.DepboxDropdown, "ĉ"}
})

Library:SetWatermarkVisibility(true)

local FrameTimer = tick()
local FrameCounter = 0;
local FPS = 60;
local GetPing = (function() return math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()) end)
local CanDoPing = pcall(function() return GetPing(); end)

local WatermarkConnection = game:GetService("RunService").RenderStepped:Connect(function()
	FrameCounter += 1;
	if (tick() - FrameTimer) >= 1 then
		FPS = FrameCounter;
		FrameTimer = tick();
		FrameCounter = 0;
	end;
	if CanDoPing then
		Library:SetWatermark(("LinoriaLib demo | %d fps | %d ms"):format(math.floor(FPS), GetPing()));
	else
		Library:SetWatermark(("LinoriaLib demo | %d fps"):format(math.floor(FPS)));
	end
end);

-- UI Settings
local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu")
MenuGroup:AddToggle("KeybindMenuOpen", { Default = Library.KeybindFrame.Visible, Text = "Open Keybind Menu", Callback = function(value) Library.KeybindFrame.Visible = value end})
MenuGroup:AddToggle("ShowCustomCursor", {Text = "Custom Cursor", Default = true, Callback = function(Value) Library.ShowCustomCursor = Value end})
MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
MenuGroup:AddButton("Unload", function() Library:Unload() end)
Library.ToggleKeybind = Options.MenuKeybind

-- Addons
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("MyScriptHub")
SaveManager:SetFolder("MyScriptHub/specific-game")
SaveManager:BuildConfigSection(Tabs["UI Settings"])

local SettingsTabbox = Tabs["UI Settings"]:AddLeftTabbox()
local ThemesTab = SettingsTabbox:AddTab("Themes")
ThemeManager:ApplyToGroupbox(ThemesTab)

SaveManager:LoadAutoloadConfig()

-- cleanup leftover background from previous version (if any)
pcall(function()
	if getgenv()._BackgroundSys and getgenv()._BackgroundSys.Destroy then
		getgenv()._BackgroundSys:Destroy()
	end
	if Library.ScreenGui and Library.ScreenGui:FindFirstChild("BackgroundHolder") then
		Library.ScreenGui.BackgroundHolder:Destroy()
	end
	local _l = game:GetService("Lighting")
	if _l:FindFirstChild("BackgroundBlur") then _l.BackgroundBlur:Destroy() end
	if _l:FindFirstChild("BackgroundCC") then _l.BackgroundCC:Destroy() end
	getgenv()._BackgroundSys = nil
end)

Library:OnUnload(function()
	WatermarkConnection:Disconnect()
	print("Unloaded!")
	Library.Unloaded = true
end)
