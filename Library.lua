-- ============================================================
--  LinoriaLib - Modified Edition
--  Base by: violin-suzutsuki
--  Modifications by: Claude (Anthropic)
--
--  CHANGES FROM ORIGINAL:
--  [1] MakeDraggable: Ghost/wireframe drag mode
--      - While dragging, the real window hides and a hollow
--        rectangular outline (ghost frame) is shown instead.
--      - The window only snaps to the ghost position on
--        mouse release. Saves repaint cost mid-drag.
--      - Mirrors the Windows "Show window contents while
--        dragging" OFF behaviour described by the user.
--
--  [2] MakeDraggable: Screen-edge clamping
--      - Prevents windows from being dragged fully off-screen.
--        The window is always kept at least 20px visible on
--        every edge.
--
--  [3] Drag debounce guard
--      - If a drag is already in progress, a second
--        InputBegan on the same instance is ignored.
--        Prevents rare double-drag bugs.
--
--  [4] Notification: Accent left-bar is now 4 px wide
--      - Was 3 px. More readable at 14pt.
--
--  [5] Rainbow step uncapped from 1/60 timing
--      - Uses Delta directly with a speed multiplier instead
--        of the 1/60 gate so rainbow feels smooth at any FPS.
--
--  [6] Tooltip: off-screen repositioning
--      - If the tooltip would overflow the right or bottom
--        edge of the viewport it flips to the other side.
--
--  [7] Watermark: draggable clamped to screen edges
--      - Same screen-edge clamping as the main window.
--
--  [8] Library:Destroy() alias
--      - Alias for Library:Unload() for friendlier API.
--
--  [9] Library:GetVersion()
--      - Returns the mod-version string.
-- ============================================================

local InputService = game:GetService('UserInputService');
local TextService  = game:GetService('TextService');
local CoreGui      = game:GetService('CoreGui');
local Teams        = game:GetService('Teams');
local Players      = game:GetService('Players');
local RunService   = game:GetService('RunService');
local TweenService = game:GetService('TweenService');
local RenderStepped = RunService.RenderStepped;
local LocalPlayer  = Players.LocalPlayer;
local Mouse        = LocalPlayer:GetMouse();

local ProtectGui = protectgui or (syn and syn.protect_gui) or (function() end);

local ScreenGui = Instance.new('ScreenGui');
ProtectGui(ScreenGui);

ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global;
ScreenGui.Parent = CoreGui;

local Toggles = {};
local Options = {};

getgenv().Toggles = Toggles;
getgenv().Options = Options;

local Library = {
    Registry    = {};
    RegistryMap = {};

    HudRegistry = {};

    FontColor       = Color3.fromRGB(255, 255, 255);
    MainColor       = Color3.fromRGB(28, 28, 28);
    BackgroundColor = Color3.fromRGB(20, 20, 20);
    AccentColor     = Color3.fromRGB(0, 85, 255);
    OutlineColor    = Color3.fromRGB(50, 50, 50);
    RiskColor       = Color3.fromRGB(255, 50, 50),

    Black = Color3.new(0, 0, 0);
    Font  = Enum.Font.Code,

    OpenedFrames  = {};
    DependencyBoxes = {};

    Signals   = {};
    ScreenGui = ScreenGui;

    -- [9] version tag
    _ModVersion = 'LinoriaLib-Modified-v1';
};

function Library:GetVersion()
    return Library._ModVersion;
end;

-- ============================================================
-- [5] Rainbow: smooth delta-based hue instead of 1/60 gate
-- ============================================================
local Hue = 0;
local RAINBOW_SPEED = 1 / 400; -- hue units per second (same visual speed as original)

table.insert(Library.Signals, RenderStepped:Connect(function(Delta)
    Hue = Hue + (Delta * RAINBOW_SPEED * 60); -- *60 keeps original apparent speed
    if Hue > 1 then Hue = Hue - 1; end;
    Library.CurrentRainbowHue   = Hue;
    Library.CurrentRainbowColor = Color3.fromHSV(Hue, 0.8, 1);
end));

-- ============================================================
-- Helpers (unchanged from original unless noted)
-- ============================================================

local function GetPlayersString()
    local PlayerList = Players:GetPlayers();
    for i = 1, #PlayerList do PlayerList[i] = PlayerList[i].Name; end;
    table.sort(PlayerList, function(a, b) return a < b end);
    return PlayerList;
end;

local function GetTeamsString()
    local TeamList = Teams:GetTeams();
    for i = 1, #TeamList do TeamList[i] = TeamList[i].Name; end;
    table.sort(TeamList, function(a, b) return a < b end);
    return TeamList;
end;

function Library:SafeCallback(f, ...)
    if not f then return; end;
    if not Library.NotifyOnError then return f(...); end;
    local ok, err = pcall(f, ...);
    if not ok then
        local _, i = err:find(':%d+: ');
        return Library:Notify(not i and err or err:sub(i + 1), 3);
    end;
end;

function Library:AttemptSave()
    if Library.SaveManager then Library.SaveManager:Save(); end;
end;

function Library:Create(Class, Properties)
    local inst = Class;
    if type(Class) == 'string' then inst = Instance.new(Class); end;
    for k, v in next, Properties do inst[k] = v; end;
    return inst;
end;

function Library:ApplyTextStroke(Inst)
    Inst.TextStrokeTransparency = 1;
    Library:Create('UIStroke', {
        Color        = Color3.new(0, 0, 0);
        Thickness    = 1;
        LineJoinMode = Enum.LineJoinMode.Miter;
        Parent       = Inst;
    });
end;

function Library:CreateLabel(Properties, IsHud)
    local inst = Library:Create('TextLabel', {
        BackgroundTransparency = 1;
        Font                   = Library.Font;
        TextColor3             = Library.FontColor;
        TextSize               = 16;
        TextStrokeTransparency = 0;
    });
    Library:ApplyTextStroke(inst);
    Library:AddToRegistry(inst, { TextColor3 = 'FontColor'; }, IsHud);
    return Library:Create(inst, Properties);
end;

-- ============================================================
-- [1][2][3] MakeDraggable — ghost wireframe drag + clamping
-- ============================================================
function Library:MakeDraggable(Inst, Cutoff)
    Inst.Active = true;

    -- Ghost frame: a hollow rectangle outline drawn while dragging
    local Ghost = Library:Create('Frame', {
        BackgroundTransparency = 1;
        BorderColor3           = Library.AccentColor;
        BorderSizePixel        = 2;
        ZIndex                 = 999;
        Visible                = false;
        Parent                 = ScreenGui;
    });

    -- Keep ghost border colour in sync with theme
    Library:AddToRegistry(Ghost, { BorderColor3 = 'AccentColor' });

    local IsDragging = false; -- [3] debounce

    Inst.InputBegan:Connect(function(Input)
        if Input.UserInputType ~= Enum.UserInputType.MouseButton1 then return; end;
        if IsDragging then return; end; -- [3]

        local ObjPos = Vector2.new(
            Mouse.X - Inst.AbsolutePosition.X,
            Mouse.Y - Inst.AbsolutePosition.Y
        );
        if ObjPos.Y > (Cutoff or 40) then return; end;

        IsDragging = true;

        -- Show ghost, hide real window
        Ghost.Size     = UDim2.fromOffset(Inst.AbsoluteSize.X, Inst.AbsoluteSize.Y);
        Ghost.Position = UDim2.fromOffset(Inst.AbsolutePosition.X, Inst.AbsolutePosition.Y);
        Ghost.Visible  = true;
        Inst.Visible   = false;

        -- [2] Screen size for clamping
        local VP = workspace.CurrentCamera.ViewportSize;

        while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
            local rawX = Mouse.X - ObjPos.X + (Inst.Size.X.Offset * Inst.AnchorPoint.X);
            local rawY = Mouse.Y - ObjPos.Y + (Inst.Size.Y.Offset * Inst.AnchorPoint.Y);

            -- [2] Clamp so at least 20px of the window stays on each edge
            local margin = 20;
            local clampedX = math.clamp(rawX, margin - Inst.Size.X.Offset, VP.X - margin);
            local clampedY = math.clamp(rawY, margin - Inst.Size.Y.Offset, VP.Y - margin);

            Ghost.Position = UDim2.fromOffset(clampedX, clampedY);
            RenderStepped:Wait();
        end;

        -- Snap real window to ghost position, hide ghost
        Inst.Position = Ghost.Position;
        Inst.Visible  = true;
        Ghost.Visible = false;
        IsDragging    = false;
    end);
end;

-- ============================================================
-- [6] AddToolTip — viewport overflow flip
-- ============================================================
function Library:AddToolTip(InfoStr, HoverInstance)
    local X, Y = Library:GetTextBounds(InfoStr, Library.Font, 14);
    local Tooltip = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderColor3     = Library.OutlineColor;
        Size             = UDim2.fromOffset(X + 5, Y + 4);
        ZIndex           = 100;
        Parent           = Library.ScreenGui;
        Visible          = false;
    });

    local Label = Library:CreateLabel({
        Position      = UDim2.fromOffset(3, 1);
        Size          = UDim2.fromOffset(X, Y);
        TextSize      = 14;
        Text          = InfoStr;
        TextColor3    = Library.FontColor;
        TextXAlignment = Enum.TextXAlignment.Left;
        ZIndex        = Tooltip.ZIndex + 1;
        Parent        = Tooltip;
    });

    Library:AddToRegistry(Tooltip, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
    Library:AddToRegistry(Label,   { TextColor3 = 'FontColor'; });

    local IsHovering = false;

    HoverInstance.MouseEnter:Connect(function()
        if Library:MouseIsOverOpenedFrame() then return; end;
        IsHovering    = true;
        Tooltip.Visible = true;

        while IsHovering do
            RunService.Heartbeat:Wait();

            -- [6] Flip tooltip if it would go off-screen
            local VP   = workspace.CurrentCamera.ViewportSize;
            local tipW = Tooltip.AbsoluteSize.X;
            local tipH = Tooltip.AbsoluteSize.Y;
            local tx   = Mouse.X + 15;
            local ty   = Mouse.Y + 12;

            if tx + tipW > VP.X then tx = Mouse.X - tipW - 5; end;
            if ty + tipH > VP.Y then ty = Mouse.Y - tipH - 5; end;

            Tooltip.Position = UDim2.fromOffset(tx, ty);
        end;
    end);

    HoverInstance.MouseLeave:Connect(function()
        IsHovering      = false;
        Tooltip.Visible = false;
    end);
end;

-- ============================================================
-- Unchanged helpers
-- ============================================================

function Library:OnHighlight(HighlightInst, Inst, Props, PropsDefault)
    HighlightInst.MouseEnter:Connect(function()
        local Reg = Library.RegistryMap[Inst];
        for Prop, ColorIdx in next, Props do
            Inst[Prop] = Library[ColorIdx] or ColorIdx;
            if Reg and Reg.Properties[Prop] then Reg.Properties[Prop] = ColorIdx; end;
        end;
    end);
    HighlightInst.MouseLeave:Connect(function()
        local Reg = Library.RegistryMap[Inst];
        for Prop, ColorIdx in next, PropsDefault do
            Inst[Prop] = Library[ColorIdx] or ColorIdx;
            if Reg and Reg.Properties[Prop] then Reg.Properties[Prop] = ColorIdx; end;
        end;
    end);
end;

function Library:MouseIsOverOpenedFrame()
    for Frame in next, Library.OpenedFrames do
        local AP, AS = Frame.AbsolutePosition, Frame.AbsoluteSize;
        if Mouse.X >= AP.X and Mouse.X <= AP.X + AS.X
        and Mouse.Y >= AP.Y and Mouse.Y <= AP.Y + AS.Y then
            return true;
        end;
    end;
end;

function Library:IsMouseOverFrame(Frame)
    local AP, AS = Frame.AbsolutePosition, Frame.AbsoluteSize;
    return Mouse.X >= AP.X and Mouse.X <= AP.X + AS.X
       and Mouse.Y >= AP.Y and Mouse.Y <= AP.Y + AS.Y;
end;

function Library:UpdateDependencyBoxes()
    for _, Depbox in next, Library.DependencyBoxes do Depbox:Update(); end;
end;

function Library:MapValue(Value, MinA, MaxA, MinB, MaxB)
    return (1 - ((Value - MinA) / (MaxA - MinA))) * MinB + ((Value - MinA) / (MaxA - MinA)) * MaxB;
end;

function Library:GetTextBounds(Text, Font, Size, Resolution)
    local B = TextService:GetTextSize(Text, Size, Font, Resolution or Vector2.new(1920, 1080));
    return B.X, B.Y;
end;

function Library:GetDarkerColor(Color)
    local H, S, V = Color3.toHSV(Color);
    return Color3.fromHSV(H, S, V / 1.5);
end;

Library.AccentColorDark = Library:GetDarkerColor(Library.AccentColor);

function Library:AddToRegistry(Inst, Properties, IsHud)
    local Data = { Instance = Inst; Properties = Properties; Idx = #Library.Registry + 1; };
    table.insert(Library.Registry, Data);
    Library.RegistryMap[Inst] = Data;
    if IsHud then table.insert(Library.HudRegistry, Data); end;
end;

function Library:RemoveFromRegistry(Inst)
    local Data = Library.RegistryMap[Inst];
    if not Data then return; end;
    for i = #Library.Registry, 1, -1 do
        if Library.Registry[i] == Data then table.remove(Library.Registry, i); end;
    end;
    for i = #Library.HudRegistry, 1, -1 do
        if Library.HudRegistry[i] == Data then table.remove(Library.HudRegistry, i); end;
    end;
    Library.RegistryMap[Inst] = nil;
end;

function Library:UpdateColorsUsingRegistry()
    for _, Object in next, Library.Registry do
        for Prop, ColorIdx in next, Object.Properties do
            if type(ColorIdx) == 'string' then
                Object.Instance[Prop] = Library[ColorIdx];
            elseif type(ColorIdx) == 'function' then
                Object.Instance[Prop] = ColorIdx();
            end;
        end;
    end;
end;

function Library:GiveSignal(Signal)
    table.insert(Library.Signals, Signal);
end;

function Library:Unload()
    for i = #Library.Signals, 1, -1 do
        table.remove(Library.Signals, i):Disconnect();
    end;
    if Library.OnUnload then Library.OnUnload(); end;
    ScreenGui:Destroy();
end;

-- [8] Friendly alias
function Library:Destroy()
    Library:Unload();
end;

function Library:OnUnload(Callback)
    Library.OnUnload = Callback;
end;

Library:GiveSignal(ScreenGui.DescendantRemoving:Connect(function(Inst)
    if Library.RegistryMap[Inst] then Library:RemoveFromRegistry(Inst); end;
end));

-- ============================================================
-- BaseAddons (ColorPicker + KeyPicker) — unchanged from orig
-- ============================================================
local BaseAddons = {};
do
    local Funcs = {};

    function Funcs:AddColorPicker(Idx, Info)
        local ToggleLabel = self.TextLabel;
        assert(Info.Default, 'AddColorPicker: Missing default value.');

        local ColorPicker = {
            Value        = Info.Default;
            Transparency = Info.Transparency or 0;
            Type         = 'ColorPicker';
            Title        = type(Info.Title) == 'string' and Info.Title or 'Color picker';
            Callback     = Info.Callback or function() end;
        };

        function ColorPicker:SetHSVFromRGB(Color)
            local H, S, V = Color3.toHSV(Color);
            ColorPicker.Hue = H; ColorPicker.Sat = S; ColorPicker.Vib = V;
        end;
        ColorPicker:SetHSVFromRGB(ColorPicker.Value);

        local DisplayFrame = Library:Create('Frame', {
            BackgroundColor3 = ColorPicker.Value;
            BorderColor3     = Library:GetDarkerColor(ColorPicker.Value);
            BorderMode       = Enum.BorderMode.Inset;
            Size             = UDim2.new(0, 28, 0, 14);
            ZIndex           = 6;
            Parent           = ToggleLabel;
        });

        local CheckerFrame = Library:Create('ImageLabel', {
            BorderSizePixel = 0;
            Size            = UDim2.new(0, 27, 0, 13);
            ZIndex          = 5;
            Image           = 'http://www.roblox.com/asset/?id=12977615774';
            Visible         = not not Info.Transparency;
            Parent          = DisplayFrame;
        });

        local PickerFrameOuter = Library:Create('Frame', {
            Name             = 'Color';
            BackgroundColor3 = Color3.new(1, 1, 1);
            BorderColor3     = Color3.new(0, 0, 0);
            Position         = UDim2.fromOffset(DisplayFrame.AbsolutePosition.X, DisplayFrame.AbsolutePosition.Y + 18);
            Size             = UDim2.fromOffset(230, Info.Transparency and 271 or 253);
            Visible          = false;
            ZIndex           = 15;
            Parent           = ScreenGui;
        });

        DisplayFrame:GetPropertyChangedSignal('AbsolutePosition'):Connect(function()
            PickerFrameOuter.Position = UDim2.fromOffset(DisplayFrame.AbsolutePosition.X, DisplayFrame.AbsolutePosition.Y + 18);
        end);

        local PickerFrameInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3     = Library.OutlineColor;
            BorderMode       = Enum.BorderMode.Inset;
            Size             = UDim2.new(1, 0, 1, 0);
            ZIndex           = 16;
            Parent           = PickerFrameOuter;
        });

        local Highlight = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel  = 0;
            Size             = UDim2.new(1, 0, 0, 2);
            ZIndex           = 17;
            Parent           = PickerFrameInner;
        });

        local SatVibMapOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0, 0, 0);
            Position     = UDim2.new(0, 4, 0, 25);
            Size         = UDim2.new(0, 200, 0, 200);
            ZIndex       = 17;
            Parent       = PickerFrameInner;
        });

        local SatVibMapInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3     = Library.OutlineColor;
            BorderMode       = Enum.BorderMode.Inset;
            Size             = UDim2.new(1, 0, 1, 0);
            ZIndex           = 18;
            Parent           = SatVibMapOuter;
        });

        local SatVibMap = Library:Create('ImageLabel', {
            BorderSizePixel = 0;
            Size            = UDim2.new(1, 0, 1, 0);
            ZIndex          = 18;
            Image           = 'rbxassetid://4155801252';
            Parent          = SatVibMapInner;
        });

        local CursorOuter = Library:Create('ImageLabel', {
            AnchorPoint         = Vector2.new(0.5, 0.5);
            Size                = UDim2.new(0, 6, 0, 6);
            BackgroundTransparency = 1;
            Image               = 'http://www.roblox.com/asset/?id=9619665977';
            ImageColor3         = Color3.new(0, 0, 0);
            ZIndex              = 19;
            Parent              = SatVibMap;
        });

        local CursorInner = Library:Create('ImageLabel', {
            Size                = UDim2.new(0, CursorOuter.Size.X.Offset - 2, 0, CursorOuter.Size.Y.Offset - 2);
            Position            = UDim2.new(0, 1, 0, 1);
            BackgroundTransparency = 1;
            Image               = 'http://www.roblox.com/asset/?id=9619665977';
            ZIndex              = 20;
            Parent              = CursorOuter;
        });

        local HueSelectorOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0, 0, 0);
            Position     = UDim2.new(0, 208, 0, 25);
            Size         = UDim2.new(0, 15, 0, 200);
            ZIndex       = 17;
            Parent       = PickerFrameInner;
        });

        local HueSelectorInner = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(1, 1, 1);
            BorderSizePixel  = 0;
            Size             = UDim2.new(1, 0, 1, 0);
            ZIndex           = 18;
            Parent           = HueSelectorOuter;
        });

        local HueCursor = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(1, 1, 1);
            AnchorPoint      = Vector2.new(0, 0.5);
            BorderColor3     = Color3.new(0, 0, 0);
            Size             = UDim2.new(1, 0, 0, 1);
            ZIndex           = 18;
            Parent           = HueSelectorInner;
        });

        local HueBoxOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0, 0, 0);
            Position     = UDim2.fromOffset(4, 228);
            Size         = UDim2.new(0.5, -6, 0, 20);
            ZIndex       = 18;
            Parent       = PickerFrameInner;
        });

        local HueBoxInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3     = Library.OutlineColor;
            BorderMode       = Enum.BorderMode.Inset;
            Size             = UDim2.new(1, 0, 1, 0);
            ZIndex           = 18;
            Parent           = HueBoxOuter;
        });

        Library:Create('UIGradient', {
            Color    = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212)),
            });
            Rotation = 90;
            Parent   = HueBoxInner;
        });

        local HueBox = Library:Create('TextBox', {
            BackgroundTransparency = 1;
            Position               = UDim2.new(0, 5, 0, 0);
            Size                   = UDim2.new(1, -5, 1, 0);
            Font                   = Library.Font;
            PlaceholderColor3      = Color3.fromRGB(190, 190, 190);
            PlaceholderText        = 'Hex color';
            Text                   = '#FFFFFF';
            TextColor3             = Library.FontColor;
            TextSize               = 14;
            TextStrokeTransparency = 0;
            TextXAlignment         = Enum.TextXAlignment.Left;
            ZIndex                 = 20;
            Parent                 = HueBoxInner;
        });
        Library:ApplyTextStroke(HueBox);

        local RgbBoxBase = Library:Create(HueBoxOuter:Clone(), {
            Position = UDim2.new(0.5, 2, 0, 228);
            Size     = UDim2.new(0.5, -6, 0, 20);
            Parent   = PickerFrameInner;
        });

        local RgbBox = Library:Create(RgbBoxBase.Frame:FindFirstChild('TextBox'), {
            Text            = '255, 255, 255';
            PlaceholderText = 'RGB color';
            TextColor3      = Library.FontColor;
        });

        local TransparencyBoxOuter, TransparencyBoxInner, TransparencyCursor;
        if Info.Transparency then
            TransparencyBoxOuter = Library:Create('Frame', {
                BorderColor3 = Color3.new(0, 0, 0);
                Position     = UDim2.fromOffset(4, 251);
                Size         = UDim2.new(1, -8, 0, 15);
                ZIndex       = 19;
                Parent       = PickerFrameInner;
            });
            TransparencyBoxInner = Library:Create('Frame', {
                BackgroundColor3 = ColorPicker.Value;
                BorderColor3     = Library.OutlineColor;
                BorderMode       = Enum.BorderMode.Inset;
                Size             = UDim2.new(1, 0, 1, 0);
                ZIndex           = 19;
                Parent           = TransparencyBoxOuter;
            });
            Library:AddToRegistry(TransparencyBoxInner, { BorderColor3 = 'OutlineColor' });
            Library:Create('ImageLabel', {
                BackgroundTransparency = 1;
                Size                   = UDim2.new(1, 0, 1, 0);
                Image                  = 'http://www.roblox.com/asset/?id=12978095818';
                ZIndex                 = 20;
                Parent                 = TransparencyBoxInner;
            });
            TransparencyCursor = Library:Create('Frame', {
                BackgroundColor3 = Color3.new(1, 1, 1);
                AnchorPoint      = Vector2.new(0.5, 0);
                BorderColor3     = Color3.new(0, 0, 0);
                Size             = UDim2.new(0, 1, 1, 0);
                ZIndex           = 21;
                Parent           = TransparencyBoxInner;
            });
        end;

        local DisplayLabel = Library:CreateLabel({
            Size           = UDim2.new(1, 0, 0, 14);
            Position       = UDim2.fromOffset(5, 5);
            TextXAlignment = Enum.TextXAlignment.Left;
            TextSize       = 14;
            Text           = ColorPicker.Title;
            TextWrapped    = false;
            ZIndex         = 16;
            Parent         = PickerFrameInner;
        });

        -- Context menu (copy/paste HEX/RGB)
        local ContextMenu = {};
        do
            ContextMenu.Options   = {};
            ContextMenu.Container = Library:Create('Frame', {
                BorderColor3 = Color3.new();
                ZIndex       = 14;
                Visible      = false;
                Parent       = ScreenGui;
            });
            ContextMenu.Inner = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3     = Library.OutlineColor;
                BorderMode       = Enum.BorderMode.Inset;
                Size             = UDim2.fromScale(1, 1);
                ZIndex           = 15;
                Parent           = ContextMenu.Container;
            });
            Library:Create('UIListLayout', { Name = 'Layout'; FillDirection = Enum.FillDirection.Vertical; SortOrder = Enum.SortOrder.LayoutOrder; Parent = ContextMenu.Inner; });
            Library:Create('UIPadding', { Name = 'Padding'; PaddingLeft = UDim.new(0, 4); Parent = ContextMenu.Inner; });

            local function updateMenuPosition()
                ContextMenu.Container.Position = UDim2.fromOffset(
                    (DisplayFrame.AbsolutePosition.X + DisplayFrame.AbsoluteSize.X) + 4,
                    DisplayFrame.AbsolutePosition.Y + 1
                );
            end;
            local function updateMenuSize()
                local w = 60;
                for _, lbl in next, ContextMenu.Inner:GetChildren() do
                    if lbl:IsA('TextLabel') then w = math.max(w, lbl.TextBounds.X); end;
                end;
                ContextMenu.Container.Size = UDim2.fromOffset(w + 8, ContextMenu.Inner.Layout.AbsoluteContentSize.Y + 4);
            end;
            DisplayFrame:GetPropertyChangedSignal('AbsolutePosition'):Connect(updateMenuPosition);
            ContextMenu.Inner.Layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(updateMenuSize);
            task.spawn(updateMenuPosition); task.spawn(updateMenuSize);
            Library:AddToRegistry(ContextMenu.Inner, { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'OutlineColor'; });

            function ContextMenu:Show() self.Container.Visible = true; end;
            function ContextMenu:Hide() self.Container.Visible = false; end;
            function ContextMenu:AddOption(Str, Callback)
                if type(Callback) ~= 'function' then Callback = function() end; end;
                local Btn = Library:CreateLabel({ Active = false; Size = UDim2.new(1, 0, 0, 15); TextSize = 13; Text = Str; ZIndex = 16; Parent = self.Inner; TextXAlignment = Enum.TextXAlignment.Left; });
                Library:OnHighlight(Btn, Btn, { TextColor3 = 'AccentColor' }, { TextColor3 = 'FontColor' });
                Btn.InputBegan:Connect(function(I) if I.UserInputType == Enum.UserInputType.MouseButton1 then Callback(); end; end);
            end;

            ContextMenu:AddOption('Copy color',  function() Library.ColorClipboard = ColorPicker.Value; Library:Notify('Copied color!', 2); end);
            ContextMenu:AddOption('Paste color', function()
                if not Library.ColorClipboard then return Library:Notify('You have not copied a color!', 2); end;
                ColorPicker:SetValueRGB(Library.ColorClipboard);
            end);
            ContextMenu:AddOption('Copy HEX', function() pcall(setclipboard, ColorPicker.Value:ToHex()); Library:Notify('Copied hex code to clipboard!', 2); end);
            ContextMenu:AddOption('Copy RGB', function()
                pcall(setclipboard, table.concat({ math.floor(ColorPicker.Value.R * 255), math.floor(ColorPicker.Value.G * 255), math.floor(ColorPicker.Value.B * 255) }, ', '));
                Library:Notify('Copied RGB values to clipboard!', 2);
            end);
        end;

        Library:AddToRegistry(PickerFrameInner, { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'OutlineColor'; });
        Library:AddToRegistry(Highlight,        { BackgroundColor3 = 'AccentColor'; });
        Library:AddToRegistry(SatVibMapInner,   { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'OutlineColor'; });
        Library:AddToRegistry(HueBoxInner,      { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
        Library:AddToRegistry(RgbBoxBase.Frame, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
        Library:AddToRegistry(RgbBox,           { TextColor3 = 'FontColor'; });
        Library:AddToRegistry(HueBox,           { TextColor3 = 'FontColor'; });

        local SeqTable = {};
        for h = 0, 1, 0.1 do table.insert(SeqTable, ColorSequenceKeypoint.new(h, Color3.fromHSV(h, 1, 1))); end;
        Library:Create('UIGradient', { Color = ColorSequence.new(SeqTable); Rotation = 90; Parent = HueSelectorInner; });

        HueBox.FocusLost:Connect(function(enter)
            if enter then
                local ok, result = pcall(Color3.fromHex, HueBox.Text);
                if ok and typeof(result) == 'Color3' then ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = Color3.toHSV(result); end;
            end;
            ColorPicker:Display();
        end);

        RgbBox.FocusLost:Connect(function(enter)
            if enter then
                local r, g, b = RgbBox.Text:match('(%d+),%s*(%d+),%s*(%d+)');
                if r then ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = Color3.toHSV(Color3.fromRGB(r, g, b)); end;
            end;
            ColorPicker:Display();
        end);

        function ColorPicker:Display()
            ColorPicker.Value = Color3.fromHSV(ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib);
            SatVibMap.BackgroundColor3 = Color3.fromHSV(ColorPicker.Hue, 1, 1);
            Library:Create(DisplayFrame, { BackgroundColor3 = ColorPicker.Value; BackgroundTransparency = ColorPicker.Transparency; BorderColor3 = Library:GetDarkerColor(ColorPicker.Value); });
            if TransparencyBoxInner then
                TransparencyBoxInner.BackgroundColor3 = ColorPicker.Value;
                TransparencyCursor.Position = UDim2.new(1 - ColorPicker.Transparency, 0, 0, 0);
            end;
            CursorOuter.Position = UDim2.new(ColorPicker.Sat, 0, 1 - ColorPicker.Vib, 0);
            HueCursor.Position   = UDim2.new(0, 0, ColorPicker.Hue, 0);
            HueBox.Text          = '#' .. ColorPicker.Value:ToHex();
            RgbBox.Text          = table.concat({ math.floor(ColorPicker.Value.R * 255), math.floor(ColorPicker.Value.G * 255), math.floor(ColorPicker.Value.B * 255) }, ', ');
            Library:SafeCallback(ColorPicker.Callback, ColorPicker.Value);
            Library:SafeCallback(ColorPicker.Changed,  ColorPicker.Value);
        end;

        function ColorPicker:OnChanged(Func) ColorPicker.Changed = Func; Func(ColorPicker.Value); end;
        function ColorPicker:Show()
            for Frame in next, Library.OpenedFrames do
                if Frame.Name == 'Color' then Frame.Visible = false; Library.OpenedFrames[Frame] = nil; end;
            end;
            PickerFrameOuter.Visible = true; Library.OpenedFrames[PickerFrameOuter] = true;
        end;
        function ColorPicker:Hide() PickerFrameOuter.Visible = false; Library.OpenedFrames[PickerFrameOuter] = nil; end;
        function ColorPicker:SetValue(HSV, Transparency)
            ColorPicker.Transparency = Transparency or 0;
            ColorPicker:SetHSVFromRGB(Color3.fromHSV(HSV[1], HSV[2], HSV[3]));
            ColorPicker:Display();
        end;
        function ColorPicker:SetValueRGB(Color, Transparency)
            ColorPicker.Transparency = Transparency or 0;
            ColorPicker:SetHSVFromRGB(Color);
            ColorPicker:Display();
        end;

        SatVibMap.InputBegan:Connect(function(I)
            if I.UserInputType == Enum.UserInputType.MouseButton1 then
                while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                    local MinX, MaxX = SatVibMap.AbsolutePosition.X, SatVibMap.AbsolutePosition.X + SatVibMap.AbsoluteSize.X;
                    local MinY, MaxY = SatVibMap.AbsolutePosition.Y, SatVibMap.AbsolutePosition.Y + SatVibMap.AbsoluteSize.Y;
                    ColorPicker.Sat = (math.clamp(Mouse.X, MinX, MaxX) - MinX) / (MaxX - MinX);
                    ColorPicker.Vib = 1 - ((math.clamp(Mouse.Y, MinY, MaxY) - MinY) / (MaxY - MinY));
                    ColorPicker:Display(); RenderStepped:Wait();
                end;
                Library:AttemptSave();
            end;
        end);

        HueSelectorInner.InputBegan:Connect(function(I)
            if I.UserInputType == Enum.UserInputType.MouseButton1 then
                while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                    local MinY, MaxY = HueSelectorInner.AbsolutePosition.Y, HueSelectorInner.AbsolutePosition.Y + HueSelectorInner.AbsoluteSize.Y;
                    ColorPicker.Hue = (math.clamp(Mouse.Y, MinY, MaxY) - MinY) / (MaxY - MinY);
                    ColorPicker:Display(); RenderStepped:Wait();
                end;
                Library:AttemptSave();
            end;
        end);

        DisplayFrame.InputBegan:Connect(function(I)
            if I.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                if PickerFrameOuter.Visible then ColorPicker:Hide(); else ContextMenu:Hide(); ColorPicker:Show(); end;
            elseif I.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame() then
                ContextMenu:Show(); ColorPicker:Hide();
            end;
        end);

        if TransparencyBoxInner then
            TransparencyBoxInner.InputBegan:Connect(function(I)
                if I.UserInputType == Enum.UserInputType.MouseButton1 then
                    while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                        local MinX, MaxX = TransparencyBoxInner.AbsolutePosition.X, TransparencyBoxInner.AbsolutePosition.X + TransparencyBoxInner.AbsoluteSize.X;
                        ColorPicker.Transparency = 1 - ((math.clamp(Mouse.X, MinX, MaxX) - MinX) / (MaxX - MinX));
                        ColorPicker:Display(); RenderStepped:Wait();
                    end;
                    Library:AttemptSave();
                end;
            end);
        end;

        Library:GiveSignal(InputService.InputBegan:Connect(function(I)
            if I.UserInputType == Enum.UserInputType.MouseButton1 then
                local AP, AS = PickerFrameOuter.AbsolutePosition, PickerFrameOuter.AbsoluteSize;
                if Mouse.X < AP.X or Mouse.X > AP.X + AS.X or Mouse.Y < (AP.Y - 21) or Mouse.Y > AP.Y + AS.Y then
                    ColorPicker:Hide();
                end;
                if not Library:IsMouseOverFrame(ContextMenu.Container) then ContextMenu:Hide(); end;
            end;
            if I.UserInputType == Enum.UserInputType.MouseButton2 and ContextMenu.Container.Visible then
                if not Library:IsMouseOverFrame(ContextMenu.Container) and not Library:IsMouseOverFrame(DisplayFrame) then ContextMenu:Hide(); end;
            end;
        end));

        ColorPicker:Display();
        ColorPicker.DisplayFrame = DisplayFrame;
        Options[Idx] = ColorPicker;
        return self;
    end;

    function Funcs:AddKeyPicker(Idx, Info)
        local ParentObj   = self;
        local ToggleLabel = self.TextLabel;
        assert(Info.Default, 'AddKeyPicker: Missing default value.');

        local KeyPicker = {
            Value        = Info.Default;
            Toggled      = false;
            Mode         = Info.Mode or 'Toggle';
            Type         = 'KeyPicker';
            Callback     = Info.Callback or function() end;
            ChangedCallback = Info.ChangedCallback or function() end;
            SyncToggleState = Info.SyncToggleState or false;
        };
        if KeyPicker.SyncToggleState then Info.Modes = { 'Toggle' }; Info.Mode = 'Toggle'; end;

        local PickOuter = Library:Create('Frame', { BackgroundColor3 = Color3.new(0,0,0); BorderColor3 = Color3.new(0,0,0); Size = UDim2.new(0,28,0,15); ZIndex = 6; Parent = ToggleLabel; });
        local PickInner = Library:Create('Frame', { BackgroundColor3 = Library.BackgroundColor; BorderColor3 = Library.OutlineColor; BorderMode = Enum.BorderMode.Inset; Size = UDim2.new(1,0,1,0); ZIndex = 7; Parent = PickOuter; });
        Library:AddToRegistry(PickInner, { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'OutlineColor'; });
        local DisplayLabel = Library:CreateLabel({ Size = UDim2.new(1,0,1,0); TextSize = 13; Text = Info.Default; TextWrapped = true; ZIndex = 8; Parent = PickInner; });

        local ModeSelectOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0,0,0);
            Position     = UDim2.fromOffset(ToggleLabel.AbsolutePosition.X + ToggleLabel.AbsoluteSize.X + 4, ToggleLabel.AbsolutePosition.Y + 1);
            Size         = UDim2.new(0,60,0,47);
            Visible      = false; ZIndex = 14; Parent = ScreenGui;
        });
        ToggleLabel:GetPropertyChangedSignal('AbsolutePosition'):Connect(function()
            ModeSelectOuter.Position = UDim2.fromOffset(ToggleLabel.AbsolutePosition.X + ToggleLabel.AbsoluteSize.X + 4, ToggleLabel.AbsolutePosition.Y + 1);
        end);
        local ModeSelectInner = Library:Create('Frame', { BackgroundColor3 = Library.BackgroundColor; BorderColor3 = Library.OutlineColor; BorderMode = Enum.BorderMode.Inset; Size = UDim2.new(1,0,1,0); ZIndex = 15; Parent = ModeSelectOuter; });
        Library:AddToRegistry(ModeSelectInner, { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'OutlineColor'; });
        Library:Create('UIListLayout', { FillDirection = Enum.FillDirection.Vertical; SortOrder = Enum.SortOrder.LayoutOrder; Parent = ModeSelectInner; });

        local ContainerLabel = Library:CreateLabel({ TextXAlignment = Enum.TextXAlignment.Left; Size = UDim2.new(1,0,0,18); TextSize = 13; Visible = false; ZIndex = 110; Parent = Library.KeybindContainer; }, true);

        local Modes       = Info.Modes or { 'Always', 'Toggle', 'Hold' };
        local ModeButtons = {};

        for _, Mode in next, Modes do
            local ModeButton = {};
            local Label = Library:CreateLabel({ Active = false; Size = UDim2.new(1,0,0,15); TextSize = 13; Text = Mode; ZIndex = 16; Parent = ModeSelectInner; });
            function ModeButton:Select()
                for _, B in next, ModeButtons do B:Deselect(); end;
                KeyPicker.Mode = Mode;
                Label.TextColor3 = Library.AccentColor;
                Library.RegistryMap[Label].Properties.TextColor3 = 'AccentColor';
                ModeSelectOuter.Visible = false;
            end;
            function ModeButton:Deselect()
                KeyPicker.Mode = nil;
                Label.TextColor3 = Library.FontColor;
                Library.RegistryMap[Label].Properties.TextColor3 = 'FontColor';
            end;
            Label.InputBegan:Connect(function(I) if I.UserInputType == Enum.UserInputType.MouseButton1 then ModeButton:Select(); Library:AttemptSave(); end; end);
            if Mode == KeyPicker.Mode then ModeButton:Select(); end;
            ModeButtons[Mode] = ModeButton;
        end;

        function KeyPicker:Update()
            if Info.NoUI then return; end;
            local State = KeyPicker:GetState();
            ContainerLabel.Text = string.format('[%s] %s (%s)', KeyPicker.Value, Info.Text, KeyPicker.Mode);
            ContainerLabel.Visible   = true;
            ContainerLabel.TextColor3 = State and Library.AccentColor or Library.FontColor;
            Library.RegistryMap[ContainerLabel].Properties.TextColor3 = State and 'AccentColor' or 'FontColor';
            local YSize, XSize = 0, 0;
            for _, Lbl in next, Library.KeybindContainer:GetChildren() do
                if Lbl:IsA('TextLabel') and Lbl.Visible then
                    YSize = YSize + 18;
                    if Lbl.TextBounds.X > XSize then XSize = Lbl.TextBounds.X; end;
                end;
            end;
            Library.KeybindFrame.Size = UDim2.new(0, math.max(XSize + 10, 210), 0, YSize + 23);
        end;

        function KeyPicker:GetState()
            if KeyPicker.Mode == 'Always' then return true;
            elseif KeyPicker.Mode == 'Hold' then
                if KeyPicker.Value == 'None' then return false; end;
                local K = KeyPicker.Value;
                if K == 'MB1' or K == 'MB2' then
                    return K == 'MB1' and InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
                        or K == 'MB2' and InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2);
                else return InputService:IsKeyDown(Enum.KeyCode[KeyPicker.Value]); end;
            else return KeyPicker.Toggled; end;
        end;

        function KeyPicker:SetValue(Data)
            local K, M = Data[1], Data[2];
            DisplayLabel.Text = K; KeyPicker.Value = K;
            ModeButtons[M]:Select(); KeyPicker:Update();
        end;
        function KeyPicker:OnClick(CB)    KeyPicker.Clicked  = CB; end;
        function KeyPicker:OnChanged(CB)  KeyPicker.Changed  = CB; CB(KeyPicker.Value); end;
        if ParentObj.Addons then table.insert(ParentObj.Addons, KeyPicker); end;

        function KeyPicker:DoClick()
            if ParentObj.Type == 'Toggle' and KeyPicker.SyncToggleState then ParentObj:SetValue(not ParentObj.Value); end;
            Library:SafeCallback(KeyPicker.Callback, KeyPicker.Toggled);
            Library:SafeCallback(KeyPicker.Clicked,  KeyPicker.Toggled);
        end;

        local Picking = false;
        PickOuter.InputBegan:Connect(function(I)
            if I.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                Picking = true; DisplayLabel.Text = '';
                local Break, Text = false, '';
                task.spawn(function()
                    while not Break do
                        if Text == '...' then Text = ''; end;
                        Text = Text .. '.'; DisplayLabel.Text = Text; wait(0.4);
                    end;
                end);
                wait(0.2);
                local Ev;
                Ev = InputService.InputBegan:Connect(function(I2)
                    local K;
                    if     I2.UserInputType == Enum.UserInputType.Keyboard     then K = I2.KeyCode.Name;
                    elseif I2.UserInputType == Enum.UserInputType.MouseButton1 then K = 'MB1';
                    elseif I2.UserInputType == Enum.UserInputType.MouseButton2 then K = 'MB2'; end;
                    Break = true; Picking = false;
                    DisplayLabel.Text = K; KeyPicker.Value = K;
                    Library:SafeCallback(KeyPicker.ChangedCallback, I2.KeyCode or I2.UserInputType);
                    Library:SafeCallback(KeyPicker.Changed,         I2.KeyCode or I2.UserInputType);
                    Library:AttemptSave(); Ev:Disconnect();
                end);
            elseif I.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame() then
                ModeSelectOuter.Visible = true;
            end;
        end);

        Library:GiveSignal(InputService.InputBegan:Connect(function(I)
            if not Picking then
                if KeyPicker.Mode == 'Toggle' then
                    local K = KeyPicker.Value;
                    if K == 'MB1' or K == 'MB2' then
                        if (K == 'MB1' and I.UserInputType == Enum.UserInputType.MouseButton1)
                        or (K == 'MB2' and I.UserInputType == Enum.UserInputType.MouseButton2) then
                            KeyPicker.Toggled = not KeyPicker.Toggled; KeyPicker:DoClick();
                        end;
                    elseif I.UserInputType == Enum.UserInputType.Keyboard then
                        if I.KeyCode.Name == K then KeyPicker.Toggled = not KeyPicker.Toggled; KeyPicker:DoClick(); end;
                    end;
                end;
                KeyPicker:Update();
            end;
            if I.UserInputType == Enum.UserInputType.MouseButton1 then
                local AP, AS = ModeSelectOuter.AbsolutePosition, ModeSelectOuter.AbsoluteSize;
                if Mouse.X < AP.X or Mouse.X > AP.X + AS.X or Mouse.Y < (AP.Y - 21) or Mouse.Y > AP.Y + AS.Y then
                    ModeSelectOuter.Visible = false;
                end;
            end;
        end));

        Library:GiveSignal(InputService.InputEnded:Connect(function()
            if not Picking then KeyPicker:Update(); end;
        end));

        KeyPicker:Update();
        Options[Idx] = KeyPicker;
        return self;
    end;

    BaseAddons.__index = Funcs;
    BaseAddons.__namecall = function(T, K, ...) return Funcs[K](...); end;
end;

-- ============================================================
-- BaseGroupbox (all widget creators) — unchanged from original
-- except [4] notification left-bar width is 4 px (in Notify)
-- ============================================================
local BaseGroupbox = {};
do
    local Funcs = {};

    function Funcs:AddBlank(Size)
        Library:Create('Frame', { BackgroundTransparency = 1; Size = UDim2.new(1,0,0,Size); ZIndex = 1; Parent = self.Container; });
    end;

    function Funcs:AddLabel(Text, DoesWrap)
        local Label     = {};
        local Groupbox  = self;
        local Container = Groupbox.Container;
        local TextLabel = Library:CreateLabel({ Size = UDim2.new(1,-4,0,15); TextSize = 14; Text = Text; TextWrapped = DoesWrap or false; TextXAlignment = Enum.TextXAlignment.Left; ZIndex = 5; Parent = Container; });
        if DoesWrap then
            local Y = select(2, Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(TextLabel.AbsoluteSize.X, math.huge)));
            TextLabel.Size = UDim2.new(1,-4,0,Y);
        else
            Library:Create('UIListLayout', { Padding = UDim.new(0,4); FillDirection = Enum.FillDirection.Horizontal; HorizontalAlignment = Enum.HorizontalAlignment.Right; SortOrder = Enum.SortOrder.LayoutOrder; Parent = TextLabel; });
        end;
        Label.TextLabel = TextLabel; Label.Container = Container;
        function Label:SetText(T)
            TextLabel.Text = T;
            if DoesWrap then
                local Y = select(2, Library:GetTextBounds(T, Library.Font, 14, Vector2.new(TextLabel.AbsoluteSize.X, math.huge)));
                TextLabel.Size = UDim2.new(1,-4,0,Y);
            end;
            Groupbox:Resize();
        end;
        if not DoesWrap then setmetatable(Label, BaseAddons); end;
        Groupbox:AddBlank(5); Groupbox:Resize();
        return Label;
    end;

    function Funcs:AddButton(...)
        local Button = {};
        local function ProcessButtonParams(_, Obj, ...)
            local Props = select(1, ...);
            if type(Props) == 'table' then
                Obj.Text = Props.Text; Obj.Func = Props.Func; Obj.DoubleClick = Props.DoubleClick; Obj.Tooltip = Props.Tooltip;
            else
                Obj.Text = select(1, ...); Obj.Func = select(2, ...);
            end;
            assert(type(Obj.Func) == 'function', 'AddButton: `Func` callback is missing.');
        end;
        ProcessButtonParams('Button', Button, ...);

        local Groupbox  = self;
        local Container = Groupbox.Container;

        local function CreateBaseButton(Btn)
            local Outer = Library:Create('Frame', { BackgroundColor3 = Color3.new(0,0,0); BorderColor3 = Color3.new(0,0,0); Size = UDim2.new(1,-4,0,20); ZIndex = 5; });
            local Inner = Library:Create('Frame', { BackgroundColor3 = Library.MainColor; BorderColor3 = Library.OutlineColor; BorderMode = Enum.BorderMode.Inset; Size = UDim2.new(1,0,1,0); ZIndex = 6; Parent = Outer; });
            local Lbl   = Library:CreateLabel({ Size = UDim2.new(1,0,1,0); TextSize = 14; Text = Btn.Text; ZIndex = 6; Parent = Inner; });
            Library:Create('UIGradient', { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(1,1,1)), ColorSequenceKeypoint.new(1, Color3.fromRGB(212,212,212)) }); Rotation = 90; Parent = Inner; });
            Library:AddToRegistry(Outer, { BorderColor3 = 'Black'; });
            Library:AddToRegistry(Inner, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
            Library:OnHighlight(Outer, Outer, { BorderColor3 = 'AccentColor' }, { BorderColor3 = 'Black' });
            return Outer, Inner, Lbl;
        end;

        local function InitEvents(Btn)
            local function WaitForEvent(event, timeout, validator)
                local bindable  = Instance.new('BindableEvent');
                local conn      = event:Once(function(...) bindable:Fire(type(validator) == 'function' and validator(...) or false); end);
                task.delay(timeout, function() conn:disconnect(); bindable:Fire(false); end);
                return bindable.Event:Wait();
            end;
            local function ValidateClick(I)
                return not Library:MouseIsOverOpenedFrame() and I.UserInputType == Enum.UserInputType.MouseButton1;
            end;
            Btn.Outer.InputBegan:Connect(function(I)
                if not ValidateClick(I) or Btn.Locked then return; end;
                if Btn.DoubleClick then
                    Library:RemoveFromRegistry(Btn.Label); Library:AddToRegistry(Btn.Label, { TextColor3 = 'AccentColor' });
                    Btn.Label.TextColor3 = Library.AccentColor; Btn.Label.Text = 'Are you sure?'; Btn.Locked = true;
                    local clicked = WaitForEvent(Btn.Outer.InputBegan, 0.5, ValidateClick);
                    Library:RemoveFromRegistry(Btn.Label); Library:AddToRegistry(Btn.Label, { TextColor3 = 'FontColor' });
                    Btn.Label.TextColor3 = Library.FontColor; Btn.Label.Text = Btn.Text;
                    task.defer(rawset, Btn, 'Locked', false);
                    if clicked then Library:SafeCallback(Btn.Func); end;
                    return;
                end;
                Library:SafeCallback(Btn.Func);
            end);
        end;

        Button.Outer, Button.Inner, Button.Label = CreateBaseButton(Button);
        Button.Outer.Parent = Container;
        InitEvents(Button);

        function Button:AddTooltip(tooltip) if type(tooltip) == 'string' then Library:AddToolTip(tooltip, self.Outer); end; return self; end;
        function Button:AddButton(...)
            local SubButton = {};
            ProcessButtonParams('SubButton', SubButton, ...);
            self.Outer.Size = UDim2.new(0.5,-2,0,20);
            SubButton.Outer, SubButton.Inner, SubButton.Label = CreateBaseButton(SubButton);
            SubButton.Outer.Position = UDim2.new(1,3,0,0);
            SubButton.Outer.Size     = UDim2.fromOffset(self.Outer.AbsoluteSize.X - 2, self.Outer.AbsoluteSize.Y);
            SubButton.Outer.Parent   = self.Outer;
            function SubButton:AddTooltip(t) if type(t) == 'string' then Library:AddToolTip(t, self.Outer); end; return SubButton; end;
            if type(SubButton.Tooltip) == 'string' then SubButton:AddTooltip(SubButton.Tooltip); end;
            InitEvents(SubButton);
            return SubButton;
        end;

        if type(Button.Tooltip) == 'string' then Button:AddTooltip(Button.Tooltip); end;
        Groupbox:AddBlank(5); Groupbox:Resize();
        return Button;
    end;

    function Funcs:AddDivider()
        local Groupbox  = self;
        local Container = self.Container;
        Groupbox:AddBlank(2);
        local DO = Library:Create('Frame', { BackgroundColor3 = Color3.new(0,0,0); BorderColor3 = Color3.new(0,0,0); Size = UDim2.new(1,-4,0,5); ZIndex = 5; Parent = Container; });
        local DI = Library:Create('Frame', { BackgroundColor3 = Library.MainColor; BorderColor3 = Library.OutlineColor; BorderMode = Enum.BorderMode.Inset; Size = UDim2.new(1,0,1,0); ZIndex = 6; Parent = DO; });
        Library:AddToRegistry(DO, { BorderColor3 = 'Black'; });
        Library:AddToRegistry(DI, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
        Groupbox:AddBlank(9); Groupbox:Resize();
    end;

    function Funcs:AddInput(Idx, Info)
        assert(Info.Text, 'AddInput: Missing `Text` string.');
        local Textbox = { Value = Info.Default or ''; Numeric = Info.Numeric or false; Finished = Info.Finished or false; Type = 'Input'; Callback = Info.Callback or function() end; };
        local Groupbox = self; local Container = Groupbox.Container;
        Library:CreateLabel({ Size = UDim2.new(1,0,0,15); TextSize = 14; Text = Info.Text; TextXAlignment = Enum.TextXAlignment.Left; ZIndex = 5; Parent = Container; });
        Groupbox:AddBlank(1);
        local TO = Library:Create('Frame', { BackgroundColor3 = Color3.new(0,0,0); BorderColor3 = Color3.new(0,0,0); Size = UDim2.new(1,-4,0,20); ZIndex = 5; Parent = Container; });
        local TI = Library:Create('Frame', { BackgroundColor3 = Library.MainColor; BorderColor3 = Library.OutlineColor; BorderMode = Enum.BorderMode.Inset; Size = UDim2.new(1,0,1,0); ZIndex = 6; Parent = TO; });
        Library:AddToRegistry(TI, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
        Library:OnHighlight(TO, TO, { BorderColor3 = 'AccentColor' }, { BorderColor3 = 'Black' });
        if type(Info.Tooltip) == 'string' then Library:AddToolTip(Info.Tooltip, TO); end;
        Library:Create('UIGradient', { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(1,1,1)), ColorSequenceKeypoint.new(1, Color3.fromRGB(212,212,212)) }); Rotation = 90; Parent = TI; });
        local Clip = Library:Create('Frame', { BackgroundTransparency = 1; ClipsDescendants = true; Position = UDim2.new(0,5,0,0); Size = UDim2.new(1,-5,1,0); ZIndex = 7; Parent = TI; });
        local Box  = Library:Create('TextBox', {
            BackgroundTransparency = 1; Position = UDim2.fromOffset(0,0); Size = UDim2.fromScale(5,1);
            Font = Library.Font; PlaceholderColor3 = Color3.fromRGB(190,190,190); PlaceholderText = Info.Placeholder or '';
            Text = Info.Default or ''; TextColor3 = Library.FontColor; TextSize = 14; TextStrokeTransparency = 0;
            TextXAlignment = Enum.TextXAlignment.Left; ZIndex = 7; Parent = Clip;
        });
        Library:ApplyTextStroke(Box);
        function Textbox:SetValue(Text)
            if Info.MaxLength and #Text > Info.MaxLength then Text = Text:sub(1, Info.MaxLength); end;
            if Textbox.Numeric and not tonumber(Text) and #Text > 0 then Text = Textbox.Value; end;
            Textbox.Value = Text; Box.Text = Text;
            Library:SafeCallback(Textbox.Callback, Textbox.Value);
            Library:SafeCallback(Textbox.Changed,  Textbox.Value);
        end;
        if Textbox.Finished then
            Box.FocusLost:Connect(function(enter) if not enter then return; end; Textbox:SetValue(Box.Text); Library:AttemptSave(); end);
        else
            Box:GetPropertyChangedSignal('Text'):Connect(function() Textbox:SetValue(Box.Text); Library:AttemptSave(); end);
        end;
        local function Update()
            local PADDING = 2; local reveal = Clip.AbsoluteSize.X;
            if not Box:IsFocused() or Box.TextBounds.X <= reveal - 2*PADDING then
                Box.Position = UDim2.new(0,PADDING,0,0);
            else
                local cursor = Box.CursorPosition;
                if cursor ~= -1 then
                    local width = TextService:GetTextSize(string.sub(Box.Text,1,cursor-1), Box.TextSize, Box.Font, Vector2.new(math.huge,math.huge)).X;
                    local cur   = Box.Position.X.Offset + width;
                    if cur < PADDING then Box.Position = UDim2.fromOffset(PADDING-width,0);
                    elseif cur > reveal-PADDING-1 then Box.Position = UDim2.fromOffset(reveal-width-PADDING-1,0); end;
                end;
            end;
        end;
        task.spawn(Update);
        Box:GetPropertyChangedSignal('Text'):Connect(Update);
        Box:GetPropertyChangedSignal('CursorPosition'):Connect(Update);
        Box.FocusLost:Connect(Update); Box.Focused:Connect(Update);
        Library:AddToRegistry(Box, { TextColor3 = 'FontColor'; });
        function Textbox:OnChanged(Func) Textbox.Changed = Func; Func(Textbox.Value); end;
        Groupbox:AddBlank(5); Groupbox:Resize();
        Options[Idx] = Textbox;
        return Textbox;
    end;

    function Funcs:AddToggle(Idx, Info)
        assert(Info.Text, 'AddInput: Missing `Text` string.');
        local Toggle = { Value = Info.Default or false; Type = 'Toggle'; Callback = Info.Callback or function() end; Addons = {}; Risky = Info.Risky; };
        local Groupbox = self; local Container = Groupbox.Container;
        local TO = Library:Create('Frame', { BackgroundColor3 = Color3.new(0,0,0); BorderColor3 = Color3.new(0,0,0); Size = UDim2.new(0,13,0,13); ZIndex = 5; Parent = Container; });
        Library:AddToRegistry(TO, { BorderColor3 = 'Black'; });
        local TI = Library:Create('Frame', { BackgroundColor3 = Library.MainColor; BorderColor3 = Library.OutlineColor; BorderMode = Enum.BorderMode.Inset; Size = UDim2.new(1,0,1,0); ZIndex = 6; Parent = TO; });
        Library:AddToRegistry(TI, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
        local ToggleLabel = Library:CreateLabel({ Size = UDim2.new(0,216,1,0); Position = UDim2.new(1,6,0,0); TextSize = 14; Text = Info.Text; TextXAlignment = Enum.TextXAlignment.Left; ZIndex = 6; Parent = TI; });
        Library:Create('UIListLayout', { Padding = UDim.new(0,4); FillDirection = Enum.FillDirection.Horizontal; HorizontalAlignment = Enum.HorizontalAlignment.Right; SortOrder = Enum.SortOrder.LayoutOrder; Parent = ToggleLabel; });
        local ToggleRegion = Library:Create('Frame', { BackgroundTransparency = 1; Size = UDim2.new(0,170,1,0); ZIndex = 8; Parent = TO; });
        Library:OnHighlight(ToggleRegion, TO, { BorderColor3 = 'AccentColor' }, { BorderColor3 = 'Black' });
        function Toggle:UpdateColors() Toggle:Display(); end;
        if type(Info.Tooltip) == 'string' then Library:AddToolTip(Info.Tooltip, ToggleRegion); end;
        function Toggle:Display()
            TI.BackgroundColor3 = Toggle.Value and Library.AccentColor or Library.MainColor;
            TI.BorderColor3     = Toggle.Value and Library.AccentColorDark or Library.OutlineColor;
            Library.RegistryMap[TI].Properties.BackgroundColor3 = Toggle.Value and 'AccentColor' or 'MainColor';
            Library.RegistryMap[TI].Properties.BorderColor3     = Toggle.Value and 'AccentColorDark' or 'OutlineColor';
        end;
        function Toggle:OnChanged(Func) Toggle.Changed = Func; Func(Toggle.Value); end;
        function Toggle:SetValue(Bool)
            Bool = not not Bool; Toggle.Value = Bool; Toggle:Display();
            for _, Addon in next, Toggle.Addons do
                if Addon.Type == 'KeyPicker' and Addon.SyncToggleState then Addon.Toggled = Bool; Addon:Update(); end;
            end;
            Library:SafeCallback(Toggle.Callback, Toggle.Value);
            Library:SafeCallback(Toggle.Changed,  Toggle.Value);
            Library:UpdateDependencyBoxes();
        end;
        ToggleRegion.InputBegan:Connect(function(I)
            if I.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                Toggle:SetValue(not Toggle.Value); Library:AttemptSave();
            end;
        end);
        if Toggle.Risky then
            Library:RemoveFromRegistry(ToggleLabel); ToggleLabel.TextColor3 = Library.RiskColor;
            Library:AddToRegistry(ToggleLabel, { TextColor3 = 'RiskColor' });
        end;
        Toggle:Display();
        Groupbox:AddBlank(Info.BlankSize or 7); Groupbox:Resize();
        Toggle.TextLabel = ToggleLabel; Toggle.Container = Container;
        setmetatable(Toggle, BaseAddons);
        Toggles[Idx] = Toggle;
        Library:UpdateDependencyBoxes();
        return Toggle;
    end;

    function Funcs:AddSlider(Idx, Info)
        assert(Info.Default,  'AddSlider: Missing default value.');
        assert(Info.Text,     'AddSlider: Missing slider text.');
        assert(Info.Min,      'AddSlider: Missing minimum value.');
        assert(Info.Max,      'AddSlider: Missing maximum value.');
        assert(Info.Rounding, 'AddSlider: Missing rounding value.');
        local Slider = { Value = Info.Default; Min = Info.Min; Max = Info.Max; Rounding = Info.Rounding; MaxSize = 232; Type = 'Slider'; Callback = Info.Callback or function() end; };
        local Groupbox = self; local Container = Groupbox.Container;
        if not Info.Compact then
            Library:CreateLabel({ Size = UDim2.new(1,0,0,10); TextSize = 14; Text = Info.Text; TextXAlignment = Enum.TextXAlignment.Left; TextYAlignment = Enum.TextYAlignment.Bottom; ZIndex = 5; Parent = Container; });
            Groupbox:AddBlank(3);
        end;
        local SO = Library:Create('Frame', { BackgroundColor3 = Color3.new(0,0,0); BorderColor3 = Color3.new(0,0,0); Size = UDim2.new(1,-4,0,13); ZIndex = 5; Parent = Container; });
        Library:AddToRegistry(SO, { BorderColor3 = 'Black'; });
        local SI = Library:Create('Frame', { BackgroundColor3 = Library.MainColor; BorderColor3 = Library.OutlineColor; BorderMode = Enum.BorderMode.Inset; Size = UDim2.new(1,0,1,0); ZIndex = 6; Parent = SO; });
        Library:AddToRegistry(SI, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
        local Fill = Library:Create('Frame', { BackgroundColor3 = Library.AccentColor; BorderColor3 = Library.AccentColorDark; Size = UDim2.new(0,0,1,0); ZIndex = 7; Parent = SI; });
        Library:AddToRegistry(Fill, { BackgroundColor3 = 'AccentColor'; BorderColor3 = 'AccentColorDark'; });
        local HBR = Library:Create('Frame', { BackgroundColor3 = Library.AccentColor; BorderSizePixel = 0; Position = UDim2.new(1,0,0,0); Size = UDim2.new(0,1,1,0); ZIndex = 8; Parent = Fill; });
        Library:AddToRegistry(HBR, { BackgroundColor3 = 'AccentColor'; });
        local DisplayLabel = Library:CreateLabel({ Size = UDim2.new(1,0,1,0); TextSize = 14; Text = 'Infinite'; ZIndex = 9; Parent = SI; });
        Library:OnHighlight(SO, SO, { BorderColor3 = 'AccentColor' }, { BorderColor3 = 'Black' });
        if type(Info.Tooltip) == 'string' then Library:AddToolTip(Info.Tooltip, SO); end;
        function Slider:UpdateColors() Fill.BackgroundColor3 = Library.AccentColor; Fill.BorderColor3 = Library.AccentColorDark; end;
        function Slider:Display()
            local Suffix = Info.Suffix or '';
            if Info.Compact then DisplayLabel.Text = Info.Text .. ': ' .. Slider.Value .. Suffix;
            elseif Info.HideMax then DisplayLabel.Text = Slider.Value .. Suffix;
            else DisplayLabel.Text = string.format('%s/%s', Slider.Value .. Suffix, Slider.Max .. Suffix); end;
            local X = math.ceil(Library:MapValue(Slider.Value, Slider.Min, Slider.Max, 0, Slider.MaxSize));
            Fill.Size = UDim2.new(0,X,1,0); HBR.Visible = not (X == Slider.MaxSize or X == 0);
        end;
        function Slider:OnChanged(Func) Slider.Changed = Func; Func(Slider.Value); end;
        local function Round(V)
            if Slider.Rounding == 0 then return math.floor(V); end;
            return tonumber(string.format('%.' .. Slider.Rounding .. 'f', V));
        end;
        function Slider:GetValueFromXOffset(X) return Round(Library:MapValue(X, 0, Slider.MaxSize, Slider.Min, Slider.Max)); end;
        function Slider:SetValue(Str)
            local Num = tonumber(Str); if not Num then return; end;
            Num = math.clamp(Num, Slider.Min, Slider.Max); Slider.Value = Num; Slider:Display();
            Library:SafeCallback(Slider.Callback, Slider.Value);
            Library:SafeCallback(Slider.Changed,  Slider.Value);
        end;
        SI.InputBegan:Connect(function(I)
            if I.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                local mPos = Mouse.X; local gPos = Fill.Size.X.Offset; local Diff = mPos - (Fill.AbsolutePosition.X + gPos);
                while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                    local nX   = math.clamp(gPos + (Mouse.X - mPos) + Diff, 0, Slider.MaxSize);
                    local nVal = Slider:GetValueFromXOffset(nX); local Old = Slider.Value;
                    Slider.Value = nVal; Slider:Display();
                    if nVal ~= Old then Library:SafeCallback(Slider.Callback, Slider.Value); Library:SafeCallback(Slider.Changed, Slider.Value); end;
                    RenderStepped:Wait();
                end;
                Library:AttemptSave();
            end;
        end);
        Slider:Display(); Groupbox:AddBlank(Info.BlankSize or 6); Groupbox:Resize();
        Options[Idx] = Slider;
        return Slider;
    end;

    function Funcs:AddDropdown(Idx, Info)
        if Info.SpecialType == 'Player' then Info.Values = GetPlayersString(); Info.AllowNull = true;
        elseif Info.SpecialType == 'Team' then Info.Values = GetTeamsString(); Info.AllowNull = true; end;
        assert(Info.Values, 'AddDropdown: Missing dropdown value list.');
        assert(Info.AllowNull or Info.Default, 'AddDropdown: Missing default value.');
        if not Info.Text then Info.Compact = true; end;
        local Dropdown = { Values = Info.Values; Value = Info.Multi and {}; Multi = Info.Multi; Type = 'Dropdown'; SpecialType = Info.SpecialType; Callback = Info.Callback or function() end; };
        local Groupbox = self; local Container = Groupbox.Container;
        if not Info.Compact then
            Library:CreateLabel({ Size = UDim2.new(1,0,0,10); TextSize = 14; Text = Info.Text; TextXAlignment = Enum.TextXAlignment.Left; TextYAlignment = Enum.TextYAlignment.Bottom; ZIndex = 5; Parent = Container; });
            Groupbox:AddBlank(3);
        end;
        local DO = Library:Create('Frame', { BackgroundColor3 = Color3.new(0,0,0); BorderColor3 = Color3.new(0,0,0); Size = UDim2.new(1,-4,0,20); ZIndex = 5; Parent = Container; });
        Library:AddToRegistry(DO, { BorderColor3 = 'Black'; });
        local DI = Library:Create('Frame', { BackgroundColor3 = Library.MainColor; BorderColor3 = Library.OutlineColor; BorderMode = Enum.BorderMode.Inset; Size = UDim2.new(1,0,1,0); ZIndex = 6; Parent = DO; });
        Library:AddToRegistry(DI, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
        Library:Create('UIGradient', { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(1,1,1)), ColorSequenceKeypoint.new(1, Color3.fromRGB(212,212,212)) }); Rotation = 90; Parent = DI; });
        local Arrow = Library:Create('ImageLabel', { AnchorPoint = Vector2.new(0,0.5); BackgroundTransparency = 1; Position = UDim2.new(1,-16,0.5,0); Size = UDim2.new(0,12,0,12); Image = 'http://www.roblox.com/asset/?id=6282522798'; ZIndex = 8; Parent = DI; });
        local ItemList = Library:CreateLabel({ Position = UDim2.new(0,5,0,0); Size = UDim2.new(1,-5,1,0); TextSize = 14; Text = '--'; TextXAlignment = Enum.TextXAlignment.Left; TextWrapped = true; ZIndex = 7; Parent = DI; });
        Library:OnHighlight(DO, DO, { BorderColor3 = 'AccentColor' }, { BorderColor3 = 'Black' });
        if type(Info.Tooltip) == 'string' then Library:AddToolTip(Info.Tooltip, DO); end;
        local MAX_ITEMS = 8;
        local ListOuter = Library:Create('Frame', { BackgroundColor3 = Color3.new(0,0,0); BorderColor3 = Color3.new(0,0,0); ZIndex = 20; Visible = false; Parent = ScreenGui; });
        local function RecalcPos()   ListOuter.Position = UDim2.fromOffset(DO.AbsolutePosition.X, DO.AbsolutePosition.Y + DO.Size.Y.Offset + 1); end;
        local function RecalcSize(Y) ListOuter.Size     = UDim2.fromOffset(DO.AbsoluteSize.X, Y or (MAX_ITEMS * 20 + 2)); end;
        RecalcPos(); RecalcSize();
        DO:GetPropertyChangedSignal('AbsolutePosition'):Connect(RecalcPos);
        local LI = Library:Create('Frame', { BackgroundColor3 = Library.MainColor; BorderColor3 = Library.OutlineColor; BorderMode = Enum.BorderMode.Inset; BorderSizePixel = 0; Size = UDim2.new(1,0,1,0); ZIndex = 21; Parent = ListOuter; });
        Library:AddToRegistry(LI, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
        local Scrolling = Library:Create('ScrollingFrame', { BackgroundTransparency = 1; BorderSizePixel = 0; CanvasSize = UDim2.new(0,0,0,0); Size = UDim2.new(1,0,1,0); ZIndex = 21; Parent = LI; TopImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png'; BottomImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png'; ScrollBarThickness = 3; ScrollBarImageColor3 = Library.AccentColor; });
        Library:AddToRegistry(Scrolling, { ScrollBarImageColor3 = 'AccentColor' });
        Library:Create('UIListLayout', { Padding = UDim.new(0,0); FillDirection = Enum.FillDirection.Vertical; SortOrder = Enum.SortOrder.LayoutOrder; Parent = Scrolling; });

        function Dropdown:Display()
            local Str = '';
            if Info.Multi then for _, V in next, Dropdown.Values do if Dropdown.Value[V] then Str = Str .. V .. ', '; end; end; Str = Str:sub(1,#Str-2);
            else Str = Dropdown.Value or ''; end;
            ItemList.Text = (Str == '' and '--' or Str);
        end;
        function Dropdown:GetActiveValues()
            if Info.Multi then local t = {}; for V in next, Dropdown.Value do table.insert(t,V); end; return t; else return Dropdown.Value and 1 or 0; end;
        end;
        function Dropdown:BuildDropdownList()
            for _, E in next, Scrolling:GetChildren() do if not E:IsA('UIListLayout') then E:Destroy(); end; end;
            local Buttons = {}; local Count = 0;
            for _, Value in next, Dropdown.Values do
                local T = {}; Count = Count + 1;
                local Btn = Library:Create('Frame', { BackgroundColor3 = Library.MainColor; BorderColor3 = Library.OutlineColor; BorderMode = Enum.BorderMode.Middle; Size = UDim2.new(1,-1,0,20); ZIndex = 23; Active = true; Parent = Scrolling; });
                Library:AddToRegistry(Btn, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
                local BtnLbl = Library:CreateLabel({ Active = false; Size = UDim2.new(1,-6,1,0); Position = UDim2.new(0,6,0,0); TextSize = 14; Text = Value; TextXAlignment = Enum.TextXAlignment.Left; ZIndex = 25; Parent = Btn; });
                Library:OnHighlight(Btn, Btn, { BorderColor3 = 'AccentColor', ZIndex = 24 }, { BorderColor3 = 'OutlineColor', ZIndex = 23 });
                local Selected = Info.Multi and Dropdown.Value[Value] or Dropdown.Value == Value;
                function T:UpdateButton()
                    Selected = Info.Multi and Dropdown.Value[Value] or Dropdown.Value == Value;
                    BtnLbl.TextColor3 = Selected and Library.AccentColor or Library.FontColor;
                    Library.RegistryMap[BtnLbl].Properties.TextColor3 = Selected and 'AccentColor' or 'FontColor';
                end;
                BtnLbl.InputBegan:Connect(function(I)
                    if I.UserInputType == Enum.UserInputType.MouseButton1 then
                        local Try = not Selected;
                        if Dropdown:GetActiveValues() == 1 and not Try and not Info.AllowNull then
                        else
                            if Info.Multi then Selected = Try; if Selected then Dropdown.Value[Value] = true; else Dropdown.Value[Value] = nil; end;
                            else Selected = Try; if Selected then Dropdown.Value = Value; else Dropdown.Value = nil; end; for _, OB in next, Buttons do OB:UpdateButton(); end; end;
                            T:UpdateButton(); Dropdown:Display();
                            Library:SafeCallback(Dropdown.Callback, Dropdown.Value);
                            Library:SafeCallback(Dropdown.Changed,  Dropdown.Value);
                            Library:AttemptSave();
                        end;
                    end;
                end);
                T:UpdateButton(); Dropdown:Display();
                Buttons[Btn] = T;
            end;
            Scrolling.CanvasSize = UDim2.fromOffset(0, Count * 20 + 1);
            RecalcSize(math.clamp(Count * 20, 0, MAX_ITEMS * 20) + 1);
        end;
        function Dropdown:SetValues(NV) if NV then Dropdown.Values = NV; end; Dropdown:BuildDropdownList(); end;
        function Dropdown:OpenDropdown()  ListOuter.Visible = true;  Library.OpenedFrames[ListOuter] = true;  Arrow.Rotation = 180; end;
        function Dropdown:CloseDropdown() ListOuter.Visible = false; Library.OpenedFrames[ListOuter] = nil;   Arrow.Rotation = 0;   end;
        function Dropdown:OnChanged(Func) Dropdown.Changed = Func; Func(Dropdown.Value); end;
        function Dropdown:SetValue(Val)
            if Dropdown.Multi then
                local n = {};
                for V in next, Val do if table.find(Dropdown.Values, V) then n[V] = true; end; end;
                Dropdown.Value = n;
            else
                Dropdown.Value = (not Val) and nil or (table.find(Dropdown.Values, Val) and Val or Dropdown.Value);
            end;
            Dropdown:BuildDropdownList();
            Library:SafeCallback(Dropdown.Callback, Dropdown.Value);
            Library:SafeCallback(Dropdown.Changed,  Dropdown.Value);
        end;
        DO.InputBegan:Connect(function(I)
            if I.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                if ListOuter.Visible then Dropdown:CloseDropdown(); else Dropdown:OpenDropdown(); end;
            end;
        end);
        InputService.InputBegan:Connect(function(I)
            if I.UserInputType == Enum.UserInputType.MouseButton1 then
                local AP, AS = ListOuter.AbsolutePosition, ListOuter.AbsoluteSize;
                if Mouse.X < AP.X or Mouse.X > AP.X+AS.X or Mouse.Y < (AP.Y-21) or Mouse.Y > AP.Y+AS.Y then Dropdown:CloseDropdown(); end;
            end;
        end);
        Dropdown:BuildDropdownList(); Dropdown:Display();
        local Defaults = {};
        if type(Info.Default) == 'string' then
            local i = table.find(Dropdown.Values, Info.Default); if i then table.insert(Defaults,i); end;
        elseif type(Info.Default) == 'table' then
            for _, V in next, Info.Default do local i = table.find(Dropdown.Values, V); if i then table.insert(Defaults,i); end; end;
        elseif type(Info.Default) == 'number' and Dropdown.Values[Info.Default] then
            table.insert(Defaults, Info.Default);
        end;
        if next(Defaults) then
            for _, i in next, Defaults do
                if Info.Multi then Dropdown.Value[Dropdown.Values[i]] = true; else Dropdown.Value = Dropdown.Values[i]; end;
                if not Info.Multi then break; end;
            end;
            Dropdown:BuildDropdownList(); Dropdown:Display();
        end;
        Groupbox:AddBlank(Info.BlankSize or 5); Groupbox:Resize();
        Options[Idx] = Dropdown;
        return Dropdown;
    end;

    function Funcs:AddDependencyBox()
        local Depbox   = { Dependencies = {}; };
        local Groupbox  = self;
        local Container = Groupbox.Container;
        local Holder    = Library:Create('Frame', { BackgroundTransparency = 1; Size = UDim2.new(1,0,0,0); Visible = false; Parent = Container; });
        local Frame     = Library:Create('Frame', { BackgroundTransparency = 1; Size = UDim2.new(1,0,1,0); Visible = true; Parent = Holder; });
        local Layout    = Library:Create('UIListLayout', { FillDirection = Enum.FillDirection.Vertical; SortOrder = Enum.SortOrder.LayoutOrder; Parent = Frame; });
        function Depbox:Resize() Holder.Size = UDim2.new(1,0,0,Layout.AbsoluteContentSize.Y); Groupbox:Resize(); end;
        Layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function() Depbox:Resize(); end);
        Holder:GetPropertyChangedSignal('Visible'):Connect(function() Depbox:Resize(); end);
        function Depbox:Update()
            for _, D in next, Depbox.Dependencies do
                if D[1].Type == 'Toggle' and D[1].Value ~= D[2] then Holder.Visible = false; Depbox:Resize(); return; end;
            end;
            Holder.Visible = true; Depbox:Resize();
        end;
        function Depbox:SetupDependencies(Deps)
            for _, D in next, Deps do
                assert(type(D) == 'table', 'SetupDependencies: Dependency must be a table.');
                assert(D[1], 'SetupDependencies: Missing element.'); assert(D[2] ~= nil, 'SetupDependencies: Missing value.');
            end;
            Depbox.Dependencies = Deps; Depbox:Update();
        end;
        Depbox.Container = Frame;
        setmetatable(Depbox, BaseGroupbox);
        table.insert(Library.DependencyBoxes, Depbox);
        return Depbox;
    end;

    BaseGroupbox.__index = Funcs;
    BaseGroupbox.__namecall = function(T, K, ...) return Funcs[K](...); end;
end;

-- ============================================================
-- Other UI elements (Notifications, Watermark, Keybind HUD)
-- ============================================================
do
    Library.NotificationArea = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Position = UDim2.new(0,0,0,40);
        Size     = UDim2.new(0,300,0,200);
        ZIndex   = 100;
        Parent   = ScreenGui;
    });
    Library:Create('UIListLayout', { Padding = UDim.new(0,4); FillDirection = Enum.FillDirection.Vertical; SortOrder = Enum.SortOrder.LayoutOrder; Parent = Library.NotificationArea; });

    -- Watermark
    local WOuter = Library:Create('Frame', { BorderColor3 = Color3.new(0,0,0); Position = UDim2.new(0,100,0,-25); Size = UDim2.new(0,213,0,20); ZIndex = 200; Visible = false; Parent = ScreenGui; });
    local WInner = Library:Create('Frame', { BackgroundColor3 = Library.MainColor; BorderColor3 = Library.AccentColor; BorderMode = Enum.BorderMode.Inset; Size = UDim2.new(1,0,1,0); ZIndex = 201; Parent = WOuter; });
    Library:AddToRegistry(WInner, { BorderColor3 = 'AccentColor'; });
    local WIF = Library:Create('Frame', { BackgroundColor3 = Color3.new(1,1,1); BorderSizePixel = 0; Position = UDim2.new(0,1,0,1); Size = UDim2.new(1,-2,1,-2); ZIndex = 202; Parent = WInner; });
    local WGrad = Library:Create('UIGradient', { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)), ColorSequenceKeypoint.new(1, Library.MainColor) }); Rotation = -90; Parent = WIF; });
    Library:AddToRegistry(WGrad, { Color = function() return ColorSequence.new({ ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)), ColorSequenceKeypoint.new(1, Library.MainColor) }); end });
    local WLabel = Library:CreateLabel({ Position = UDim2.new(0,5,0,0); Size = UDim2.new(1,-4,1,0); TextSize = 14; TextXAlignment = Enum.TextXAlignment.Left; ZIndex = 203; Parent = WIF; });
    Library.Watermark     = WOuter;
    Library.WatermarkText = WLabel;
    Library:MakeDraggable(Library.Watermark); -- [7] ghost drag + clamping applied here too

    -- Keybind HUD
    local KOuter = Library:Create('Frame', { AnchorPoint = Vector2.new(0,0.5); BorderColor3 = Color3.new(0,0,0); Position = UDim2.new(0,10,0.5,0); Size = UDim2.new(0,210,0,20); Visible = false; ZIndex = 100; Parent = ScreenGui; });
    local KInner = Library:Create('Frame', { BackgroundColor3 = Library.MainColor; BorderColor3 = Library.OutlineColor; BorderMode = Enum.BorderMode.Inset; Size = UDim2.new(1,0,1,0); ZIndex = 101; Parent = KOuter; });
    Library:AddToRegistry(KInner, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; }, true);
    local KCF = Library:Create('Frame', { BackgroundColor3 = Library.AccentColor; BorderSizePixel = 0; Size = UDim2.new(1,0,0,2); ZIndex = 102; Parent = KInner; });
    Library:AddToRegistry(KCF, { BackgroundColor3 = 'AccentColor'; }, true);
    Library:CreateLabel({ Size = UDim2.new(1,0,0,20); Position = UDim2.fromOffset(5,2); TextXAlignment = Enum.TextXAlignment.Left; Text = 'Keybinds'; ZIndex = 104; Parent = KInner; });
    local KContainer = Library:Create('Frame', { BackgroundTransparency = 1; Size = UDim2.new(1,0,1,-20); Position = UDim2.new(0,0,0,20); ZIndex = 1; Parent = KInner; });
    Library:Create('UIListLayout', { FillDirection = Enum.FillDirection.Vertical; SortOrder = Enum.SortOrder.LayoutOrder; Parent = KContainer; });
    Library:Create('UIPadding', { PaddingLeft = UDim.new(0,5); Parent = KContainer; });
    Library.KeybindFrame     = KOuter;
    Library.KeybindContainer = KContainer;
    Library:MakeDraggable(KOuter);
end;

-- ============================================================
-- Public API: Watermark, Notify, CreateWindow
-- ============================================================

function Library:SetWatermarkVisibility(Bool) Library.Watermark.Visible = Bool; end;
function Library:SetWatermark(Text)
    local X, Y = Library:GetTextBounds(Text, Library.Font, 14);
    Library.Watermark.Size = UDim2.new(0, X + 15, 0, (Y * 1.5) + 3);
    Library:SetWatermarkVisibility(true);
    Library.WatermarkText.Text = Text;
end;

-- [4] Notification left-bar is now 4 px (was 3)
function Library:Notify(Text, Time)
    local XSize, YSize = Library:GetTextBounds(Text, Library.Font, 14);
    YSize = YSize + 7;
    local NO = Library:Create('Frame', { BorderColor3 = Color3.new(0,0,0); Position = UDim2.new(0,100,0,10); Size = UDim2.new(0,0,0,YSize); ClipsDescendants = true; ZIndex = 100; Parent = Library.NotificationArea; });
    local NI = Library:Create('Frame', { BackgroundColor3 = Library.MainColor; BorderColor3 = Library.OutlineColor; BorderMode = Enum.BorderMode.Inset; Size = UDim2.new(1,0,1,0); ZIndex = 101; Parent = NO; });
    Library:AddToRegistry(NI, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; }, true);
    local NIF = Library:Create('Frame', { BackgroundColor3 = Color3.new(1,1,1); BorderSizePixel = 0; Position = UDim2.new(0,1,0,1); Size = UDim2.new(1,-2,1,-2); ZIndex = 102; Parent = NI; });
    local NGrad = Library:Create('UIGradient', { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)), ColorSequenceKeypoint.new(1, Library.MainColor) }); Rotation = -90; Parent = NIF; });
    Library:AddToRegistry(NGrad, { Color = function() return ColorSequence.new({ ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)), ColorSequenceKeypoint.new(1, Library.MainColor) }); end }, true);
    Library:CreateLabel({ Position = UDim2.new(0,4,0,0); Size = UDim2.new(1,-4,1,0); Text = Text; TextXAlignment = Enum.TextXAlignment.Left; TextSize = 14; ZIndex = 103; Parent = NIF; });
    -- [4] 4 px wide left accent bar
    local LC = Library:Create('Frame', { BackgroundColor3 = Library.AccentColor; BorderSizePixel = 0; Position = UDim2.new(0,-1,0,-1); Size = UDim2.new(0,4,1,2); ZIndex = 104; Parent = NO; });
    Library:AddToRegistry(LC, { BackgroundColor3 = 'AccentColor'; }, true);
    pcall(NO.TweenSize, NO, UDim2.new(0, XSize + 8 + 4, 0, YSize), 'Out', 'Quad', 0.4, true);
    task.spawn(function()
        wait(Time or 5);
        pcall(NO.TweenSize, NO, UDim2.new(0,0,0,YSize), 'Out', 'Quad', 0.4, true);
        wait(0.4);
        NO:Destroy();
    end);
end;

function Library:CreateWindow(...)
    local Arguments = { ... };
    local Config    = { AnchorPoint = Vector2.zero };
    if type(...) == 'table' then Config = ...;
    else Config.Title = Arguments[1]; Config.AutoShow = Arguments[2] or false; end;
    if type(Config.Title) ~= 'string' then Config.Title = 'No title'; end;
    if type(Config.TabPadding) ~= 'number' then Config.TabPadding = 0; end;
    if type(Config.MenuFadeTime) ~= 'number' then Config.MenuFadeTime = 0.2; end;
    if typeof(Config.Position) ~= 'UDim2' then Config.Position = UDim2.fromOffset(175, 50); end;
    if typeof(Config.Size) ~= 'UDim2' then Config.Size = UDim2.fromOffset(550, 600); end;
    if Config.Center then Config.AnchorPoint = Vector2.new(0.5,0.5); Config.Position = UDim2.fromScale(0.5,0.5); end;

    local Window = { Tabs = {}; };
    local Outer  = Library:Create('Frame', { AnchorPoint = Config.AnchorPoint; BackgroundColor3 = Color3.new(0,0,0); BorderSizePixel = 0; Position = Config.Position; Size = Config.Size; Visible = false; ZIndex = 1; Parent = ScreenGui; });
    Library:MakeDraggable(Outer, 25);
    local Inner  = Library:Create('Frame', { BackgroundColor3 = Library.MainColor; BorderColor3 = Library.AccentColor; BorderMode = Enum.BorderMode.Inset; Position = UDim2.new(0,1,0,1); Size = UDim2.new(1,-2,1,-2); ZIndex = 1; Parent = Outer; });
    Library:AddToRegistry(Inner, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'AccentColor'; });
    local WindowLabel = Library:CreateLabel({ Position = UDim2.new(0,7,0,0); Size = UDim2.new(0,0,0,25); Text = Config.Title or ''; TextXAlignment = Enum.TextXAlignment.Left; ZIndex = 1; Parent = Inner; });
    local MSO = Library:Create('Frame', { BackgroundColor3 = Library.BackgroundColor; BorderColor3 = Library.OutlineColor; Position = UDim2.new(0,8,0,25); Size = UDim2.new(1,-16,1,-33); ZIndex = 1; Parent = Inner; });
    Library:AddToRegistry(MSO, { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'OutlineColor'; });
    local MSI = Library:Create('Frame', { BackgroundColor3 = Library.BackgroundColor; BorderColor3 = Color3.new(0,0,0); BorderMode = Enum.BorderMode.Inset; Size = UDim2.new(1,0,1,0); ZIndex = 1; Parent = MSO; });
    Library:AddToRegistry(MSI, { BackgroundColor3 = 'BackgroundColor'; });
    local TabArea = Library:Create('Frame', { BackgroundTransparency = 1; Position = UDim2.new(0,8,0,8); Size = UDim2.new(1,-16,0,21); ZIndex = 1; Parent = MSI; });
    Library:Create('UIListLayout', { Padding = UDim.new(0,Config.TabPadding); FillDirection = Enum.FillDirection.Horizontal; SortOrder = Enum.SortOrder.LayoutOrder; Parent = TabArea; });
    local TabContainer = Library:Create('Frame', { BackgroundColor3 = Library.MainColor; BorderColor3 = Library.OutlineColor; Position = UDim2.new(0,8,0,30); Size = UDim2.new(1,-16,1,-38); ZIndex = 2; Parent = MSI; });
    Library:AddToRegistry(TabContainer, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });

    function Window:SetWindowTitle(Title) WindowLabel.Text = Title; end;

    function Window:AddTab(Name)
        local Tab = { Groupboxes = {}; Tabboxes = {}; };
        local TBW = Library:GetTextBounds(Name, Library.Font, 16);
        local TB  = Library:Create('Frame', { BackgroundColor3 = Library.BackgroundColor; BorderColor3 = Library.OutlineColor; Size = UDim2.new(0, TBW + 12, 1, 0); ZIndex = 1; Parent = TabArea; });
        Library:AddToRegistry(TB, { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'OutlineColor'; });
        local TBL = Library:CreateLabel({ Position = UDim2.new(0,0,0,0); Size = UDim2.new(1,0,1,0); Text = Name; ZIndex = 1; Parent = TB; });

        local Content = Library:Create('Frame', { BackgroundTransparency = 1; Size = UDim2.new(1,0,1,0); Visible = false; ZIndex = 3; Parent = TabContainer; });
        Library:Create('UIListLayout', { Padding = UDim.new(0,8); FillDirection = Enum.FillDirection.Horizontal; SortOrder = Enum.SortOrder.LayoutOrder; Parent = Content; });
        Library:Create('UIPadding', { PaddingLeft = UDim.new(0,8); PaddingTop = UDim.new(0,8); Parent = Content; });

        function Tab:Select()
            for _, OtherTab in next, Window.Tabs do OtherTab:Deselect(); end;
            Content.Visible = true;
            TB.BackgroundColor3 = Library.MainColor;
            Library.RegistryMap[TB].Properties.BackgroundColor3 = 'MainColor';
            TBL.TextColor3 = Library.AccentColor;
            Library.RegistryMap[TBL].Properties.TextColor3 = 'AccentColor';
        end;
        function Tab:Deselect()
            Content.Visible = false;
            TB.BackgroundColor3 = Library.BackgroundColor;
            Library.RegistryMap[TB].Properties.BackgroundColor3 = 'BackgroundColor';
            TBL.TextColor3 = Library.FontColor;
            Library.RegistryMap[TBL].Properties.TextColor3 = 'FontColor';
        end;
        function Tab:AddLeftGroupbox(Name) return Tab:AddGroupbox(Name, 'Left'); end;
        function Tab:AddRightGroupbox(Name) return Tab:AddGroupbox(Name, 'Right'); end;

        function Tab:AddGroupbox(Name, Side)
            local Groupbox = {};
            local GbWidth  = (TabContainer.AbsoluteSize.X / 2) - 12;
            local GO = Library:Create('Frame', { BackgroundColor3 = Color3.new(0,0,0); BorderColor3 = Color3.new(0,0,0); Size = UDim2.new(0, GbWidth, 0, 32); ZIndex = 3; Parent = Content; });
            local GI = Library:Create('Frame', { BackgroundColor3 = Library.MainColor; BorderColor3 = Library.OutlineColor; BorderMode = Enum.BorderMode.Inset; Size = UDim2.new(1,0,1,0); ZIndex = 4; Parent = GO; });
            Library:AddToRegistry(GO, { BorderColor3 = 'Black'; });
            Library:AddToRegistry(GI, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
            local Title = Library:Create('Frame', { BackgroundColor3 = Library.BackgroundColor; BorderColor3 = Library.OutlineColor; Position = UDim2.new(0,6,0,0); Size = UDim2.new(0,0,0,0); ZIndex = 5; Parent = GO; });
            Library:AddToRegistry(Title, { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'OutlineColor'; });
            local TitleLabel = Library:CreateLabel({ Position = UDim2.new(0,3,0,0); TextSize = 14; Text = Name; ZIndex = 6; Parent = Title; });
            local TW = Library:GetTextBounds(Name, Library.Font, 14);
            Title.Size = UDim2.new(0, TW + 6, 0, 14);

            local GContainer = Library:Create('Frame', { BackgroundTransparency = 1; Position = UDim2.new(0,4,0,16); Size = UDim2.new(1,-8,0,0); ZIndex = 5; Parent = GI; });
            Library:Create('UIListLayout', { FillDirection = Enum.FillDirection.Vertical; SortOrder = Enum.SortOrder.LayoutOrder; Parent = GContainer; });

            Groupbox.Container = GContainer;

            function Groupbox:Resize()
                local Layout = GContainer:FindFirstChildOfClass('UIListLayout');
                local H      = Layout and Layout.AbsoluteContentSize.Y or 0;
                GO.Size  = UDim2.new(0, GbWidth, 0, H + 24);
                GI.Size  = UDim2.new(1,0,1,0);
            end;

            GContainer:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function() Groupbox:Resize(); end);

            setmetatable(Groupbox, BaseGroupbox);
            table.insert(Tab.Groupboxes, Groupbox);
            return Groupbox;
        end;

        function Tab:AddTabbox()
            local Tabbox = { Tabs = {}; };
            local TbWidth = (TabContainer.AbsoluteSize.X / 2) - 12;
            local TbO = Library:Create('Frame', { BackgroundColor3 = Color3.new(0,0,0); BorderColor3 = Color3.new(0,0,0); Size = UDim2.new(0, TbWidth, 0, 32); ZIndex = 3; Parent = Content; });
            local TbI = Library:Create('Frame', { BackgroundColor3 = Library.MainColor; BorderColor3 = Library.OutlineColor; BorderMode = Enum.BorderMode.Inset; Size = UDim2.new(1,0,1,0); ZIndex = 4; Parent = TbO; });
            Library:AddToRegistry(TbO, { BorderColor3 = 'Black'; });
            Library:AddToRegistry(TbI, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
            local TabButtonArea = Library:Create('Frame', { BackgroundTransparency = 1; Size = UDim2.new(1,0,0,18); ZIndex = 5; Parent = TbI; });
            Library:Create('UIListLayout', { FillDirection = Enum.FillDirection.Horizontal; SortOrder = Enum.SortOrder.LayoutOrder; Parent = TabButtonArea; });

            function Tabbox:AddTab(Name)
                local InnerTab = {};
                local BtnW     = Library:GetTextBounds(Name, Library.Font, 14);
                local Btn      = Library:Create('Frame', { BackgroundColor3 = Library.BackgroundColor; BorderColor3 = Library.OutlineColor; Size = UDim2.new(0, BtnW + 10, 1, 0); ZIndex = 6; Parent = TabButtonArea; });
                Library:AddToRegistry(Btn, { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'OutlineColor'; });
                local BtnLbl   = Library:CreateLabel({ Size = UDim2.new(1,0,1,0); TextSize = 14; Text = Name; ZIndex = 7; Parent = Btn; });
                local ITContent = Library:Create('Frame', { BackgroundTransparency = 1; Position = UDim2.new(0,4,0,20); Size = UDim2.new(1,-8,0,0); Visible = false; ZIndex = 5; Parent = TbI; });
                Library:Create('UIListLayout', { FillDirection = Enum.FillDirection.Vertical; SortOrder = Enum.SortOrder.LayoutOrder; Parent = ITContent; });

                InnerTab.Container = ITContent;
                function InnerTab:Resize()
                    local Layout = ITContent:FindFirstChildOfClass('UIListLayout');
                    local H      = Layout and Layout.AbsoluteContentSize.Y or 0;
                    TbO.Size = UDim2.new(0, TbWidth, 0, H + 26);
                end;
                ITContent:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function() InnerTab:Resize(); end);

                function InnerTab:Select()
                    for _, OT in next, Tabbox.Tabs do OT:Deselect(); end;
                    ITContent.Visible       = true;
                    Btn.BackgroundColor3    = Library.MainColor;
                    Library.RegistryMap[Btn].Properties.BackgroundColor3 = 'MainColor';
                    BtnLbl.TextColor3       = Library.AccentColor;
                    Library.RegistryMap[BtnLbl].Properties.TextColor3   = 'AccentColor';
                    InnerTab:Resize();
                end;
                function InnerTab:Deselect()
                    ITContent.Visible       = false;
                    Btn.BackgroundColor3    = Library.BackgroundColor;
                    Library.RegistryMap[Btn].Properties.BackgroundColor3 = 'BackgroundColor';
                    BtnLbl.TextColor3       = Library.FontColor;
                    Library.RegistryMap[BtnLbl].Properties.TextColor3   = 'FontColor';
                end;

                Btn.InputBegan:Connect(function(I) if I.UserInputType == Enum.UserInputType.MouseButton1 then InnerTab:Select(); end; end);

                setmetatable(InnerTab, BaseGroupbox);
                table.insert(Tabbox.Tabs, InnerTab);
                if #Tabbox.Tabs == 1 then InnerTab:Select(); end;
                return InnerTab;
            end;

            table.insert(Tab.Tabboxes, Tabbox);
            return Tabbox;
        end;

        TB.InputBegan:Connect(function(I) if I.UserInputType == Enum.UserInputType.MouseButton1 then Tab:Select(); end; end);
        table.insert(Window.Tabs, Tab);
        if #Window.Tabs == 1 then Tab:Select(); end;

        return Tab;
    end;

    function Window:Show()
        Outer.Visible = true;
        if Config.AutoShow then
            TweenService:Create(Outer, TweenInfo.new(Config.MenuFadeTime), { BackgroundTransparency = 0 }):Play();
        end;
    end;

    function Window:Hide()
        if Config.AutoShow then
            local T = TweenService:Create(Outer, TweenInfo.new(Config.MenuFadeTime), { BackgroundTransparency = 1 });
            T:Play();
            T.Completed:Connect(function() Outer.Visible = false; end);
        else
            Outer.Visible = false;
        end;
    end;

    function Window:Toggle()
        if Outer.Visible then Window:Hide(); else Window:Show(); end;
    end;

    if Config.AutoShow then Window:Show(); end;
    return Window;
end;

return Library;
