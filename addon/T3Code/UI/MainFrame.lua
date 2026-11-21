-- The T3 Code window: a standard portrait frame with the thread list on the left,
-- the selected thread on the right, and side tabs for usage and settings.

local _, ns = ...
local UI = ns.UI
local Theme = ns.Theme

local M = {}
ns.Main = M

local WIDTH, HEIGHT = 940, 640
local MIN_W, MIN_H = 760, 480
local LIST_W = 300
local LIST_MIN = 180
local LIST_KEEP = 420 -- the conversation keeps at least this much of the window
local COMPOSER_H = 92
local BAND_H = 22 -- one short row for the title
-- The modern footer sits 16px up. The classic frame keeps the
-- buttons in its own bottom border (4px). The pages end above the row.
local BAR_Y_MODERN = 16
local BAR_CLEAR = 52

M.page = "threads"
M.mode = "thread" -- "thread" | "new"

-- The bottom bar's buttons, left to right.
M.BAR_KEYS = { "Refresh", "New", "Back", "Stop", "Mic", "Speak", "Shot", "Insert", "Send" }

-- A corner grip: drag it to resize the window, and the size is kept for next
-- time. Made after the button bar so its corner sits on top of it.
local function CreateResizeGrip(f)
	f:SetResizable(true)
	local minW, minH = M:MinSize()
	if f.SetResizeBounds then f:SetResizeBounds(minW, minH) end
	local grip = CreateFrame("Frame", nil, f)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:EnableMouse(true)
	grip:RegisterForDrag("LeftButton")
	grip:SetScript("OnDragStart", function() f:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		local w, h = f:GetWidth(), f:GetHeight()
		w, h = math.max(minW, math.floor(w)), math.max(minH, math.floor(h))
		f:SetSize(w, h)
		ns.db.settings.windowSize = { w, h }
	end)
	local theme = Theme.Get()
	if theme then
		-- Three strokes, shorter toward the corner, so the mark reads as a triangle.
		grip:SetSize(18, 18)
		local mark = grip:CreateTexture(nil, "ARTWORK")
		mark:SetAllPoints()
		mark:SetTexture(UI.LineIcon("grip"))
		mark:SetVertexColor(theme.muted[1], theme.muted[2], theme.muted[3], 1)
	else
		-- The game's own corner grip. Drawn lines rotate into a red square on this
		-- client and sit badly on the gold frame.
		grip:SetSize(16, 16)
		grip:ClearAllPoints()
		grip:SetPoint("BOTTOMRIGHT", -6, 6)
		local mark = grip:CreateTexture(nil, "ARTWORK")
		mark:SetAllPoints()
		mark:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
		grip:SetScript("OnEnter", function() mark:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight") end)
		grip:SetScript("OnLeave", function() mark:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up") end)
	end
	f.ResizeGrip = grip
end

-- The modern window can shrink. The classic pages are laid out for the default
-- size and don't scroll, so the game's frame only grows.
function M:MinSize()
	if Theme.Get() then return MIN_W, MIN_H end
	return WIDTH, HEIGHT
end

---------------------------------------------------------------------------
-- Frame

local function CreateSideTab(f, index, icon, tooltip, page)
	local theme = Theme.Get()
	local tab
	if theme then
		-- A flat square; the active page's tab carries the accent down its left edge.
		tab = CreateFrame("Button", nil, f)
		tab:SetSize(40, 40)
		-- The tab stands outside the window, so it carries the window's ground (and its
		-- transparency, see ApplyOpacity) under the glass; the glass alone barely shows.
		tab.Ground = Theme.Solid(tab, theme.windowBg)
		tab.Ground:SetDrawLayer("BACKGROUND", -1)
		tab.Ground:SetAllPoints()
		local bg = Theme.Solid(tab, theme.panelAlt)
		bg:SetAllPoints()
		-- No left rule: the tab grows out of the window's own border.
		Theme.Edges(tab, theme.hairline, true)
		local bar = Theme.Solid(tab, theme.accent, "ARTWORK")
		bar:SetWidth(2)
		bar:SetPoint("TOPLEFT")
		bar:SetPoint("BOTTOMLEFT")
		bar:Hide()
		function tab:SetChecked(on)
			bar:SetShown(on and true or false)
			local c = on and theme.text or theme.muted
			self.Icon:SetVertexColor(c[1], c[2], c[3], 1)
		end
		local hl = Theme.Solid(tab, theme.hover, "HIGHLIGHT")
		hl:SetAllPoints()
		tab.Icon = tab:CreateTexture(nil, "ARTWORK")
		tab.Icon:SetSize(18, 18)
		tab.Icon:SetPoint("CENTER")
		tab.Icon:SetTexture(icon)
		tab.Icon:SetVertexColor(theme.muted[1], theme.muted[2], theme.muted[3], 1)
		UI.Tooltip(tab, tooltip)
		tab:SetScript("OnClick", function() M:ShowPage(page) end)
	else
		tab = CreateFrame("Frame", nil, f, "LargeSideTabButtonTemplate")
		tab.Icon:SetTexture(icon)
		tab:SetFillToInterior(true, 40)
		tab.tooltipText = tooltip
		tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
			if button == "LeftButton" and upInside then M:ShowPage(page) end
		end)
		tab:EnableMouse(true)
	end
	tab:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, -36 - (index - 1) * 48)
	tab.page = page
	return tab
end

function M:Create()
	if self.frame then return self.frame end
	local f = CreateFrame("Frame", "T3CodeFrame", UIParent, "ButtonFrameTemplate")
	self.frame = f
	f:SetSize(WIDTH, HEIGHT)
	local savedSize = ns.db.settings.windowSize
	if savedSize then
		local minW, minH = self:MinSize()
		f:SetSize(math.max(minW, savedSize[1] or WIDTH), math.max(minH, savedSize[2] or HEIGHT))
	end
	f:SetPoint("CENTER", 0, 20)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:Hide()
	f:SetTitle("T3 Code")
	f:SetPortraitToAsset(ns.media .. "portrait")
	-- The modern design hides the game's ornate frame and paints its own: the
	-- theme's background, an accent edge, and the title on that same ground. The
	-- template's top streaks are a black gradient; they stay hidden.
	local theme = Theme.Get()
	if theme then
		local function HideArt(frame)
			if not frame or not frame.GetRegions then return end
			for _, region in ipairs({ frame:GetRegions() }) do
				if region.Hide then region:Hide() end
			end
		end
		-- By name: a piece the template doesn't have must not stop the loop.
		for _, key in ipairs({ "NineSlice", "Bg", "PortraitContainer", "Portrait", "TitleContainer", "CloseButton", "TopTileStreaks", "TitleBg" }) do
			local piece = f[key]
			if piece then piece:Hide() end
		end
		HideArt(f)
		if f.Inset then
			if f.Inset.NineSlice then f.Inset.NineSlice:Hide() end
			HideArt(f.Inset)
		end
		-- One ground for the whole window. Its alpha is the transparency setting.
		local ground = { theme.windowBg[1], theme.windowBg[2], theme.windowBg[3], 1 }
		f.ModernBg = Theme.Solid(f, ground)
		f.ModernBg:SetAllPoints()
		-- The window's edge is the theme's accent, as Hyprland draws the active window.
		f.ModernEdges = { Theme.Edges(f, theme.popupBorder) }
		f.ModernBand = Theme.Solid(f, ground)
		f.ModernBand:SetHeight(BAND_H)
		f.ModernBand:SetPoint("TOPLEFT")
		f.ModernBand:SetPoint("TOPRIGHT")
		f.ModernBandRule = Theme.Solid(f, theme.hairline, "ARTWORK")
		f.ModernBandRule:SetHeight(1)
		f.ModernBandRule:SetPoint("TOPLEFT", 0, -BAND_H)
		f.ModernBandRule:SetPoint("TOPRIGHT", 0, -BAND_H)
		M:ApplyOpacity()
		if f.Inset then
			if f.Inset.Bg then f.Inset.Bg:Hide() end
			-- The template's inset runs down into the button row. Lift its bottom
			-- edge so the list and the message box stop above Refresh and Send.
			local n = f.Inset.GetNumPoints and f.Inset:GetNumPoints() or 0
			local pts, sawBottom = {}, false
			local topCap = -(BAND_H + 2)
			for i = 1, n do
				local point, relTo, relPoint, x, y = f.Inset:GetPoint(i)
				if point == "BOTTOM" or point == "BOTTOMLEFT" or point == "BOTTOMRIGHT" then
					sawBottom = true
					y = math.max(y or 0, BAR_CLEAR)
				elseif point == "TOP" or point == "TOPLEFT" or point == "TOPRIGHT" then
					-- The portrait frame starts the pages far below the title. The thin
					-- bar doesn't need that gap.
					y = math.max(y or topCap, topCap)
				end
				pts[i] = { point, relTo, relPoint, x, y }
			end
			if sawBottom then
				f.Inset:ClearAllPoints()
				for _, p in ipairs(pts) do
					if p[1] then f.Inset:SetPoint(p[1], p[2], p[3], p[4] or 0, p[5] or 0) end
				end
			else
				f.Inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, BAR_CLEAR)
			end
		end
		f.ModernTitle = f:CreateFontString(nil, "ARTWORK", "T3ModernTitle")
		f.ModernTitle:SetPoint("LEFT", f, "TOPLEFT", 12, -(BAND_H / 2))
		f.ModernTitle:SetText("T3 Code")
		-- Near-white. The accent stays on what's selected.
		Theme.SetText(f.ModernTitle, theme.text)
		-- A quiet × in the band's corner, no button chrome.
		local close = CreateFrame("Button", nil, f)
		close:SetSize(16, 16)
		close:SetPoint("TOPRIGHT", -6, -3)
		close.Text = close:CreateFontString(nil, "ARTWORK", "T3ModernBody")
		close.Text:SetPoint("CENTER", 0, 0)
		close.Text:SetText("×")
		local closeHl = Theme.Solid(close, theme.hover, "HIGHLIGHT")
		closeHl:SetAllPoints()
		close:SetScript("OnClick", function() f:Hide() end)
		UI.Tooltip(close, "Close")
		f.ModernClose = close
	end
	-- The name is what matters in UISpecialFrames, and it survives rebuilds.
	local named
	for _, n in ipairs(UISpecialFrames) do if n == "T3CodeFrame" then named = true end end
	if not named then tinsert(UISpecialFrames, "T3CodeFrame") end

	-- Drag by the title bar.
	local drag = CreateFrame("Frame", nil, f)
	drag:SetPoint("TOPLEFT", 60, 0)
	drag:SetPoint("TOPRIGHT", -30, 0)
	drag:SetHeight(24)
	drag:EnableMouse(true)
	drag:RegisterForDrag("LeftButton")
	drag:SetScript("OnDragStart", function() f:StartMoving() end)
	drag:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		local point, _, rel, x, y = f:GetPoint()
		ns.db.settings.windowPoint = { point, rel, x, y }
	end)
	local wp = ns.db.settings.windowPoint
	if wp then
		f:ClearAllPoints()
		f:SetPoint(wp[1], UIParent, wp[2], wp[3], wp[4])
	end

	-- Subtitle: the thread you're looking at, and the link status under it.
	f.Subtitle = UI.Text(f, "GameFontNormalLarge", "CENTER")
	f.Subtitle:SetPoint("TOP", 20, -30)
	f.Subtitle:SetWidth(WIDTH - 220)
	f.Subtitle:SetWordWrap(false)
	f.Status = UI.Text(f, "GameFontGreenSmall", "CENTER")
	f.Status:SetPoint("TOP", f.Subtitle, "BOTTOM", 0, -2)
	f.Status:SetWidth(WIDTH - 220)
	if theme then
		-- Same row as the title, so the thread name doesn't take a second line.
		f.Subtitle:SetFontObject("T3ModernSmallDim")
		f.Subtitle:ClearAllPoints()
		f.Subtitle:SetPoint("LEFT", f.ModernTitle, "RIGHT", 12, 0)
		f.Subtitle:SetJustifyH("LEFT")
		f.Subtitle:SetWordWrap(false)
		f.Status:SetFontObject("T3ModernSmall")
		f.Status:ClearAllPoints()
		f.Status:SetJustifyH("RIGHT")
		f.Status:SetWordWrap(false)
		f.Status:SetWidth(240)
	end
	-- The centered texts are sized for the default window; keep up with a resize.
	f:HookScript("OnSizeChanged", ns.Safe(function(self)
		if Theme.Get() then
			local room = math.max(80, self:GetWidth() - 320)
			self.Subtitle:SetWidth(math.min(280, room))
			M:ApplyListWidth(ns.db.settings.listWidth)
			return
		end
		M:ApplyListWidth(ns.db.settings.listWidth)
		local w = math.max(200, self:GetWidth() - 220)
		self.Subtitle:SetWidth(w)
		self.Status:SetWidth(w)
	end))

	-- Collapse the thread list (arrow under the close button).
	f.SidebarToggle = UI.IconButton(f, "common-icon-backarrow", theme and 18 or 24, "Hide the thread list", function() M:ToggleSidebar() end)
	-- A line icon has no atlas. The fallback is only for the classic button, whose
	-- first atlas is missing on some clients. Applying it here replaced the chevron
	-- with the game's yellow triangle.
	if not Theme.Get() and not f.SidebarToggle.Icon:GetAtlas() then f.SidebarToggle.Icon:SetAtlas("common-dropdown-icon-back") end
	f.SidebarToggle:SetPoint("TOPRIGHT", -10, -32)
	if theme then
		-- In the modern band, beside the close. The drag strip used to run across
		-- this button, so the chevron itself moved the window and only the empty
		-- edge of the button toggled the list.
		f.SidebarToggle:ClearAllPoints()
		f.SidebarToggle:SetPoint("TOPRIGHT", -28, -2)
		-- Flush to the chevron, not stretched across the bar.
		f.Status:SetPoint("RIGHT", f.SidebarToggle, "LEFT", -8, 0)
		drag:ClearAllPoints()
		drag:SetPoint("TOPLEFT", 8, 0)
		drag:SetPoint("TOPRIGHT", -52, 0)
		drag:SetHeight(BAND_H)
		f.SidebarToggle:SetFrameLevel(drag:GetFrameLevel() + 5)
		if f.ModernClose then f.ModernClose:SetFrameLevel(drag:GetFrameLevel() + 5) end
	end

	-- Shown when the session's live updates are running low: a reload frees them.
	f.RefreshSlots = UI.Button(f, "Refresh live updates", 170, function() ReloadUI() end)
	f.RefreshSlots:SetPoint("TOPRIGHT", f.SidebarToggle, "TOPLEFT", -8, 0)
	f.RefreshSlots:Hide()
	UI.Tooltip(f.RefreshSlots, "Refresh live updates", "Reloads the interface (a couple of seconds) to free a fresh set of live updates.")

	-- Pages live inside the inset.
	f.Pages = {}
	f.Pages.threads = CreateFrame("Frame", nil, f.Inset)
	f.Pages.threads:SetAllPoints()
	self:CreateThreadsPage(f.Pages.threads)
	f.Pages.usage = CreateFrame("Frame", nil, f.Inset)
	f.Pages.usage:SetAllPoints()
	f.Pages.settings = CreateFrame("Frame", nil, f.Inset)
	f.Pages.settings:SetAllPoints()

	-- Bottom button bar.
	self:CreateButtonBar(f)
	CreateResizeGrip(f)

	-- Side tabs.
	f.Tabs = {
		CreateSideTab(f, 1, theme and UI.LineIcon("threads") or (ns.media .. "icon"), "Threads", "threads"),
		CreateSideTab(f, 2, theme and UI.LineIcon("chart") or "Interface\\Icons\\INV_Scroll_08", "Usage limits", "usage"),
		CreateSideTab(f, 3, theme and UI.LineIcon("gear") or "Interface\\Icons\\INV_Misc_Gear_01", "Settings", "settings"),
	}

	f:SetScript("OnShow", ns.Safe(function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
		ns.windowOpen = true
		ns.Interacted()
		ns.Transport:Touch()
		M:Refresh()
		ns:Fire("WindowShown", f)
	end))
	f:SetScript("OnHide", ns.Safe(function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
		M:SaveDraft()
		ns.windowOpen = false
		ns.Transport:Touch()
		ns:Fire("WindowHidden", f)
	end))

	self:ApplyScale()
	ns.Usage:Create(f.Pages.usage)
	ns.Settings:Create(f.Pages.settings)
	self:ShowPage("threads")
	return f
end

-- The widest the list may be in the window as it is now.
function M:ListMax()
	local f = self.frame
	if not f then return math.huge end
	return math.max(LIST_MIN, (f:GetWidth() or WIDTH) - LIST_KEEP)
end

-- The list's width as drawn: the width the player chose, narrowed while the window
-- is too small for it.
function M:ListWidth()
	local w = (ns.db and ns.db.settings.listWidth) or LIST_W
	return math.max(LIST_MIN, math.min(self:ListMax(), w))
end

-- The thread list's width, kept between a readable minimum and whatever still
-- leaves the conversation room. Moves the Back button with it. Only a drag on the
-- divider (`save`) changes the width kept for next time; a smaller window narrows
-- the list without forgetting it.
function M:ApplyListWidth(w, save)
	local f = self.frame
	local page = f and f.Pages and f.Pages.threads
	if not page or not page.Left then return end
	w = math.max(LIST_MIN, math.min(self:ListMax(), math.floor(w or LIST_W)))
	if save then ns.db.settings.listWidth = w end
	page.Left:SetWidth(w)
	if page.Left:IsShown() and f.Bar and f.Bar.Back then
		local barY = Theme.Get() and BAR_Y_MODERN or 4
		f.Bar.Back:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", w + 18, barY)
	end
end

function M:CreateThreadsPage(page)
	-- Left: project filter + thread list.
	local left = CreateFrame("Frame", nil, page)
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(self:ListWidth())
	page.Left = left

	local divider = page:CreateTexture(nil, "ARTWORK")
	local theme = Theme.Get()
	if theme then
		Theme.Paint(divider, theme.hairline)
		divider:SetWidth(1)
	else
		divider:SetAtlas("UI-Frame-Divider-Vertical") -- harmless if missing
		if not divider:GetAtlas() then
			divider:SetColorTexture(0.45, 0.36, 0.2, 0.6)
			divider:SetWidth(2)
		end
	end
	divider:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, -2)
	divider:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 0, 2)
	page.Divider = divider

	-- A wider invisible grip on the divider: drag it to make the list wider.
	local split = CreateFrame("Frame", nil, page)
	split:SetWidth(7)
	split:SetPoint("TOP", left, "TOPRIGHT", 0, 0)
	split:SetPoint("BOTTOM", left, "BOTTOMRIGHT", 0, 0)
	split:SetFrameLevel((page:GetFrameLevel() or 1) + 5)
	split:EnableMouse(true)
	local hint = split:CreateTexture(nil, "BACKGROUND")
	if theme then
		Theme.Paint(hint, theme.hover)
	else
		hint:SetColorTexture(1, 0.82, 0, 0.45)
	end
	hint:SetAllPoints()
	hint:Hide()
	split:SetScript("OnEnter", function() hint:Show() end)
	split:SetScript("OnLeave", function(self) if not self.dragging then hint:Hide() end end)
	split:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" then return end
		self.dragging = true
		hint:Show()
		self:SetScript("OnUpdate", function()
			local scale = page:GetEffectiveScale() or 1
			local x = GetCursorPosition() / scale
			local origin = page:GetLeft() or 0
			M:ApplyListWidth(x - origin, true)
		end)
	end)
	split:SetScript("OnMouseUp", function(self)
		self.dragging = false
		self:SetScript("OnUpdate", nil)
		if not self:IsMouseOver() then hint:Hide() end
	end)
	page.Split = split

	ns.ThreadList:Create(left)

	-- Right: header bar, transcript, composer.
	local right = CreateFrame("Frame", nil, page)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 4, 0)
	right:SetPoint("BOTTOMRIGHT")
	page.Right = right

	local header = CreateFrame("Frame", nil, right)
	header:SetPoint("TOPLEFT", 4, -4)
	header:SetPoint("TOPRIGHT", -4, -4)
	header:SetHeight(30)
	local hbg = header:CreateTexture(nil, "BACKGROUND")
	if theme then
		Theme.Paint(hbg, theme.panelAlt)
	else
		hbg:SetAtlas("common-button-list-collapseExpand")
	end
	hbg:SetAllPoints()
	header.Text = UI.Text(header, "GameFontHighlight", "CENTER")
	header.Text:SetPoint("LEFT", 12, 0)
	header.Text:SetPoint("RIGHT", -110, 0)
	header.Text:SetWordWrap(false)
	header.Action = UI.Button(header, "Settle", 96, function() M:HeaderAction() end)
	header.Action:SetPoint("RIGHT", -4, 0)
	header.Archive = UI.Button(header, "Archive", 86, function()
		if ns.viewId then
			ns.Transport:Send("archive", ns.viewId)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		end
	end)
	header.Archive:SetPoint("RIGHT", header.Action, "LEFT", -4, 0)
	header.Archive:Hide()
	-- Snooze: a button that opens the shared list of T3's snooze presets, so it carries
	-- what the list reads from its owner. On a snoozed thread it wakes it instead.
	header.Snooze = UI.Button(header, "Snooze", 86, function() M:SnoozeAction() end)
	header.Snooze:SetPoint("RIGHT", header.Action, "LEFT", -4, 0)
	header.Snooze:Hide()
	header.Snooze.options = {}
	header.Snooze.listWidth = 220
	header.Snooze.Update = function(self) self.value = nil end
	header.Snooze.onChange = function(value)
		if value == "custom" then
			M:OpenCustomSnooze()
		elseif ns.viewId and value then
			M:SendSnooze(ns.viewId, value)
		end
	end
	UI.Tooltip(header.Snooze, function(self) return self:GetText() end, function()
		local t = ns.Store:Thread(ns.viewId)
		if t and t.s == "snoozed" then return "Bring this thread back to the Open list now." end
		return "Hide this thread until a time you pick. The times are the snooze presets from T3 Code's settings."
	end)
	UI.Tooltip(header.Archive, "Archive", "Hide this thread from the list (it stays in T3 Code's archive).")
	header.Project = UI.Dropdown(header, 176, function(value)
		M.newProject = value
		M.newModel, M.newEffort = nil, nil
		M:Refresh()
	end)
	header.Project:SetPoint("RIGHT", -6, 0)
	header.Project:Hide()
	-- The model: for the new thread, or the open thread's next runs. Only a deliberate
	-- pick from the list changes it (no wheel or right-click stepping), because each
	-- change on a thread is a command to T3.
	local function ListOnly(dd)
		dd:SetScript("OnClick", function(self) UI.OpenList(self) end)
		dd:EnableMouseWheel(false)
		dd:SetScript("OnMouseWheel", nil)
		dd:Hide()
		return dd
	end
	header.Model = ListOnly(UI.Dropdown(header, 176, function(value) M:PickModel(value) end))
	header.Model.listWidth = 300 -- room for "Model · Provider" rows
	-- How hard the model reasons, when it has levels to pick from.
	header.Effort = ListOnly(UI.Dropdown(header, 92, function(value) M:PickEffort(value) end))
	right.Header = header

	local composer = UI.Inset(right)
	composer:SetPoint("BOTTOMLEFT", 2, 2)
	composer:SetPoint("BOTTOMRIGHT", -2, 2)
	composer:SetHeight(COMPOSER_H)
	right.ComposerInset = composer

	local box = CreateFrame("Frame", nil, composer, theme and "T3CodeComposerModernTemplate" or "T3CodeComposerTemplate")
	box:SetPoint("TOPLEFT", 8, -6)
	box:SetPoint("BOTTOMRIGHT", -8, 18)
	box:RegisterCallback("OnEnterPressed", function()
		if IsShiftKeyDown() then
			box:Insert("\n")
		elseif not ns.Suggest:Accept() then
			M:Send()
		end
	end, M)
	box:RegisterCallback("OnTextChanged", function(_, _, userChanged)
		M:UpdateCounter()
		ns.Interacted()
		ns.Suggest:OnTextChanged(userChanged)
	end, M)
	box:RegisterCallback("OnEscapePressed", function()
		if not ns.Suggest:Close() then box:ClearFocus() end
	end, M)
	ns.Suggest:Attach(box)
	right.Composer = box
	self.composer = box
	self:SetPlaceholder("Message the agent  (Shift+Enter for a new line)")

	local counter = UI.Text(composer, "GameFontDisableSmall", "RIGHT")
	counter:SetPoint("BOTTOMRIGHT", theme and -12 or -8, 6)
	right.Counter = counter

	local hint = UI.Text(composer, "GameFontDisableSmall", "LEFT")
	hint:SetPoint("BOTTOMLEFT", 10, 5)
	right.Hint = hint

	ns.Family:Create(right, header)
	ns.Transcript:Create(right, header, composer)
end

function M:CreateButtonBar(f)
	local bar = {}
	-- The modern icon buttons are flat squares edge to edge; give them a little
	-- more air than the game's own padded art needs.
	local gap = Theme.Get() and 9 or 6
	bar.Refresh = UI.Button(f, "Refresh", 110, function()
		ns.Transport:Send("ping")
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end)
	local barY = Theme.Get() and BAR_Y_MODERN or 4
	bar.Refresh:SetPoint("BOTTOMLEFT", 6, barY)
	UI.Tooltip(bar.Refresh, "Refresh", "Ask the bridge for a fresh update now.")

	bar.New = UI.Button(f, "New Thread", 130, function() M:StartNewThread() end)
	bar.New:SetPoint("LEFT", bar.Refresh, "RIGHT", 60, 0)

	bar.Back = UI.Button(f, "Back", 110, function() M:Back() end)
	bar.Back:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", self:ListWidth() + 18, barY)

	bar.Stop = UI.IconButton(f, "common-icon-redx", 26, "Stop the agent", function()
		if ns.viewId then
			ns.Transport:Send("stop", ns.viewId)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		end
	end)
	bar.Stop:SetPoint("LEFT", bar.Back, "RIGHT", 18, 0)

	bar.Mic = UI.IconButton(f, "voicechat-icon-mic", 26, "Dictate", function() M:ToggleDictation() end)
	bar.Mic:SetPoint("LEFT", bar.Stop, "RIGHT", gap, 0)
	UI.Tooltip(bar.Mic, nil, function()
		local b = ns.Store.data.bridge or {}
		if b.dictationHint then return b.dictationHint end
		if not b.dictation then return "No dictation backend found on the desktop." end
		return "Click, speak, click again: your words are typed into the message box (" .. b.dictation .. " on your desktop). On a controller, hold Y."
	end)

	bar.Speak = UI.IconButton(f, "voicechat-icon-speaker", 26, "Read aloud", function()
		if ns.Reading() then
			ns.Hush()
			return
		end
		local v = ns.Store:View()
		local last
		if v and v.msgs then
			for i = #v.msgs, 1, -1 do
				if v.msgs[i].r == "a" then last = v.msgs[i] break end
			end
		end
		if last then ns.Speak(last.t, ns.viewId, last.n) end
	end)
	bar.Speak:SetPoint("LEFT", bar.Mic, "RIGHT", gap, 0)

	bar.Shot = UI.IconButton(f, "Interface\\Icons\\INV_Misc_Spyglass_03", 26, nil, nil)
	bar.Shot:SetPoint("LEFT", bar.Speak, "RIGHT", gap, 0)
	bar.Shot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	bar.Shot:SetScript("OnClick", function(_, button)
		if button == "RightButton" then M:RemoveScreenshots() else M:AttachScreenshot() end
	end)
	UI.Tooltip(bar.Shot, "Attach a screenshot", "Adds a screenshot of the game to your next message. Right-click to remove it. /t3 report also adds diagnostics.")
	UI.Tooltip(bar.Speak, nil, function()
		return ns.Reading() and "Stop reading aloud." or "Read the latest reply aloud."
	end)

	-- The "/" and "$" suggestions as a list, for a controller, which can't type them.
	-- It opens the shared list, so it carries what the list reads from its owner.
	bar.Insert = UI.IconButton(f, "Interface\\Icons\\INV_Misc_Book_09", 26, nil, function(self) M:OpenCommandList(self) end)
	bar.Insert:SetPoint("LEFT", bar.Shot, "RIGHT", gap, 0)
	bar.Insert.options = {}
	bar.Insert.listWidth = 360
	bar.Insert.listAbove = true
	bar.Insert.Update = function(self) self.value = nil end
	bar.Insert.onChange = function(value) M:InsertCommand(value) end
	UI.Tooltip(bar.Insert, "Insert a command or skill", function(self)
		if self:IsEnabled() then return "Adds it to your message. Typing / or $ in the message box lists them too." end
		if not M:NextProvider() then return "Pick a thread, or start a new one, first." end
		return "The model this message goes to has no commands or skills."
	end)

	bar.Send = UI.Button(f, "Send", 110, function() M:Send() end, true)
	bar.Send:SetPoint("BOTTOMRIGHT", -26, barY) -- clear of the resize grip
	f.Bar = bar
end

---------------------------------------------------------------------------
-- Pages, sidebar

function M:ShowPage(page)
	local f = self.frame
	self.page = page
	for name, p in pairs(f.Pages) do p:SetShown(name == page) end
	for _, tab in ipairs(f.Tabs) do tab:SetChecked(tab.page == page) end
	local threads = page == "threads"
	for _, key in ipairs(M.BAR_KEYS) do
		-- Refresh and New belong to the thread list: they follow the sidebar instead.
		if key ~= "Refresh" and key ~= "New" then f.Bar[key]:SetShown(threads) end
	end
	f.SidebarToggle:SetShown(threads)
	if page == "usage" then ns.Usage:Refresh() end
	if page == "settings" then ns.Settings:Refresh() end
	self:Refresh()
	ns:Fire("PageChanged", page)
end

function M:ToggleSidebar(show)
	local page = self.frame.Pages.threads
	if show == nil then show = not page.Left:IsShown() end
	page.Left:SetShown(show)
	page.Divider:SetShown(show)
	if page.Split then page.Split:SetShown(show) end
	page.Right:ClearAllPoints()
	if show then
		page.Right:SetPoint("TOPLEFT", page.Left, "TOPRIGHT", 4, 0)
	else
		page.Right:SetPoint("TOPLEFT", 0, 0)
	end
	page.Right:SetPoint("BOTTOMRIGHT")
	self.frame.Bar.Refresh:SetShown(show)
	self.frame.Bar.New:SetShown(show)
	self.frame.Bar.Back:ClearAllPoints()
	local barY = Theme.Get() and BAR_Y_MODERN or 4
	if show then
		self.frame.Bar.Back:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", self:ListWidth() + 18, barY)
	else
		self.frame.Bar.Back:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 6, barY)
	end
	self.frame.SidebarToggle.Icon:SetRotation(show and 0 or math.pi)
	ns.Transcript:Relayout()
end

---------------------------------------------------------------------------
-- Selecting threads, drafts

function M:SaveDraft()
	if not self.composer then return end
	local key = self.mode == "new" and "__new" or ns.viewId
	if key then
		local text = self.composer:GetInputText()
		ns.db.drafts[key] = (text and text ~= "") and text or nil
	end
end

function M:LoadDraft()
	local key = self.mode == "new" and "__new" or ns.viewId
	self.composer:SetText(key and ns.db.drafts[key] or "")
	self:UpdateCounter()
end

function M:SelectThread(id, opts)
	self:Create()
	if id == ns.viewId and self.mode == "thread" then
		if opts and opts.show then self:Open() end
		return
	end
	self:SaveDraft()
	self.mode = "thread"
	self.previous = ns.viewId
	ns.viewId = id
	local t = ns.Store:Thread(id)
	if t and t.un then ns.Transport:Send("read", id) end
	ns.Transport:Touch()
	self:LoadDraft()
	if opts and opts.show then self:Open() end
	if self.page ~= "threads" then self:ShowPage("threads") end
	self:Refresh()
	ns:Fire("ViewSelected", id)
end

function M:Back()
	if self.mode == "new" then
		self.mode = "thread"
		self:LoadDraft()
		self:Refresh()
		return
	end
	if not self.frame.Pages.threads.Left:IsShown() then
		self:ToggleSidebar(true)
		return
	end
	self:CloseThread()
end

-- Back to no thread selected.
function M:CloseThread()
	self:SaveDraft()
	ns.viewId = nil
	ns.Transport:Touch()
	self:LoadDraft()
	self:Refresh()
	ns:Fire("ViewSelected", nil)
end

-- Snooze a thread and remember the command: once the thread is snoozed it leaves the
-- screen (see ThreadTransition below), and a refused command leaves it open.
function M:SendSnooze(threadId, ...)
	local cmd = ns.Transport:Send("snooze", threadId, ...)
	if cmd then self.pendingSnooze = { cmd = cmd, thread = threadId, at = GetTime() } end
end

function M:StartNewThread(projectId)
	self:Create()
	self:SaveDraft()
	self.mode = "new"
	self.newModel, self.newEffort = nil, nil
	local filter = ns.db.settings.project
	self.newProject = projectId or (filter ~= "all" and filter) or ns.db.settings.lastProject
	if not ns.Store.projectsById[self.newProject or ""] then
		local first = ns.Store.data.projects[1]
		self.newProject = first and first.id
	end
	self:LoadDraft()
	if self.page ~= "threads" then self:ShowPage("threads") end
	self:Open()
	self:Refresh()
	self.composer:SetFocus()
end

-- T3's snooze presets as the bridge resolved them: { k = id, l = label, w = time }.
function M:SnoozeOptions()
	local options = {}
	local bridge = ns.Store.data.bridge
	for _, c in ipairs(type(bridge.snz) == "table" and bridge.snz or {}) do
		table.insert(options, { value = c.k, label = c.w and (c.l .. "  " .. ns.Color("grey", c.w)) or c.l, text = c.l })
	end
	-- A bridge that sends presets also reads a typed time.
	if type(bridge.snz) == "table" then table.insert(options, { value = "custom", label = "Custom…" }) end
	return options
end

-- A small box under the Snooze button for typing a time. The bridge reads it, on the
-- desktop's clock, so the text goes over as typed.
function M:OpenCustomSnooze()
	local t = ns.Store:Thread(ns.viewId)
	if not t then return end
	local p = self.snoozePanel
	if not p then
		local header = self.frame.Pages.threads.Right.Header
		p = CreateFrame("Frame", "T3CodeSnoozePanel", self.frame)
		p:SetFrameStrata("FULLSCREEN_DIALOG")
		p:SetToplevel(true)
		p:SetSize(272, 112)
		p:SetPoint("TOPRIGHT", header.Snooze, "BOTTOMRIGHT", 0, -2)
		p:EnableMouse(true)
		p:SetClampedToScreen(true)
		local theme = Theme.Get()
		local bg = p:CreateTexture(nil, "BACKGROUND")
		if theme then
			Theme.Paint(bg, theme.overlay)
			bg:SetAllPoints()
			Theme.Edges(p, theme.popupBorder)
		else
			bg:SetAtlas("common-dropdown-bg")
			bg:SetPoint("TOPLEFT", -10, 3)
			bg:SetPoint("BOTTOMRIGHT", 10, -3)
			bg:SetAlpha(0.95)
			if not bg:GetAtlas() then bg:SetColorTexture(0.05, 0.05, 0.05, 0.95) end
			-- Solid behind the text: the transcript underneath would show through the art.
			local solid = p:CreateTexture(nil, "BACKGROUND", nil, -1)
			solid:SetAllPoints()
			solid:SetColorTexture(0.03, 0.03, 0.03, 1)
		end
		p.Title = UI.Text(p, "GameFontNormal", "LEFT")
		p.Title:SetPoint("TOPLEFT", 14, -12)
		p.Title:SetText("Snooze until")
		p.Box = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
		p.Box:SetSize(150, 20)
		p.Box:SetPoint("TOPLEFT", 20, -32)
		p.Box:SetAutoFocus(false)
		p.Box:SetMaxLetters(40)
		p.Box:SetScript("OnEnterPressed", function() M:SubmitCustomSnooze() end)
		p.Box:SetScript("OnEscapePressed", function() p:Hide() end)
		if theme then
			-- The kit's input: glass with a border, the text in the foreground.
			for _, key in ipairs({ "Left", "Middle", "Right" }) do
				if p.Box[key] then p.Box[key]:Hide() end
			end
			local well = Theme.Solid(p.Box, theme.panel)
			well:SetPoint("TOPLEFT", -6, 0)
			well:SetPoint("BOTTOMRIGHT")
			p.Box:SetFontObject("T3ModernBody")
			p.Box:SetTextInsets(0, 4, 0, 0)
			local edge = CreateFrame("Frame", nil, p.Box)
			edge:SetPoint("TOPLEFT", -6, 0)
			edge:SetPoint("BOTTOMRIGHT")
			Theme.Edges(edge, theme.controlBorder)
		end
		p.Go = UI.Button(p, "Snooze", 76, function() M:SubmitCustomSnooze() end)
		p.Go:SetPoint("LEFT", p.Box, "RIGHT", 6, 0)
		p.Hint = UI.Text(p, "GameFontDisableSmall", "LEFT")
		p.Hint:SetPoint("TOPLEFT", 14, -62)
		p.Hint:SetPoint("RIGHT", -14, 0)
		p.Hint:SetJustifyV("TOP")
		p.Hint:SetWordWrap(true)
		p.Hint:SetText("Try 45m, 3h, 2d, 5pm, tomorrow 9am or fri 3pm.")
		p:SetScript("OnHide", function() p.Box:ClearFocus() end)
		p:Hide()
		tinsert(UISpecialFrames, "T3CodeSnoozePanel")
		self.snoozePanel = p
	end
	p.threadId = t.id
	p:Show()
	p.Box:SetFocus()
	p.Box:HighlightText()
end

function M:SubmitCustomSnooze()
	local p = self.snoozePanel
	if not p or not p.threadId then return end
	local text = strtrim(p.Box:GetText() or "")
	if text == "" then return end
	-- The text stays in the box, so a time the bridge couldn't read is easy to fix.
	self:SendSnooze(p.threadId, "custom", text)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	p:Hide()
end

function M:SnoozeAction()
	local t = ns.Store:Thread(ns.viewId)
	if not t then return end
	if t.s == "snoozed" then
		ns.Transport:Send("unsnooze", t.id)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		return
	end
	local button = self.frame.Pages.threads.Right.Header.Snooze
	button.options = self:SnoozeOptions()
	button.value = nil
	if #button.options > 0 then UI.OpenList(button) end
end

function M:HeaderAction()
	local t = ns.Store:Thread(ns.viewId)
	if not t then return end
	if t.s == "settled" then
		ns.Transport:Send("unsettle", t.id)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	else
		ns.Transport:Send("settle", t.id)
		PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end
end

---------------------------------------------------------------------------
-- Sending

function M:UpdateCounter()
	local right = self.frame and self.frame.Pages.threads.Right
	if not right then return end
	local text = self.composer:GetInputText() or ""
	right.Counter:SetText(2000 - strlenutf8(text))
end

function M:Send(textOverride)
	local text = textOverride or self.composer:GetInputText() or ""
	text = strtrim(text)
	if text == "" then return end
	local fam = self.mode ~= "new" and ns.Store:Family()
	if fam and fam.ro then
		ns.Print("This subagent is read only: it can't take messages. Message the thread that started it instead.")
		return
	end
	if self.mode == "new" then
		if not self.newProject then
			ns.Print("Pick a project for the new thread first.")
			return
		end
		local instanceId, slug = ns.Store.SplitModelKey(self:ChosenNewModel())
		local effort = self:ChosenNewEffort()
		local worktree = ns.db.settings.newWorktree and "1" or nil
		local id
		if effort or worktree then
			-- An empty model means T3 Code's default, at this level.
			id = ns.Transport:Send("new", self.newProject, text, instanceId or "", slug or "", effort or "", worktree)
		else
			id = ns.Transport:Send("new", self.newProject, text, instanceId, slug)
		end
		if not id then return end -- too long; the composer keeps it
		ns.db.settings.lastProject = self.newProject
		self.pendingNew = id
		self.pendingNewText = text
		ns.db.drafts.__new = nil
	elseif ns.viewId and not textOverride and ns.Transcript:CustomAnswer(text) then
		ns.db.drafts[ns.viewId] = nil
	elseif ns.viewId then
		local id
		if ns.db.settings.steerFollowUps then
			id = ns.Transport:Send("send", ns.viewId, text, "steer")
		else
			id = ns.Transport:Send("send", ns.viewId, text)
		end
		if not id then return end -- too long; the composer keeps it
		ns.Transcript:AddLocalEcho(ns.viewId, text)
		ns.db.drafts[ns.viewId] = nil
	else
		ns.Print("Pick a thread, or start a new one.")
		return
	end
	if not textOverride then
		self.composer:SetText("")
		self.composer:ClearFocus()
	end
	PlaySound(SOUNDKIT.TELL_MESSAGE or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	self:Refresh()
end

-- The next message's provider's commands and skills in the shared list, each group
-- under its header.
function M:OpenCommandList(button)
	local list = ns.Store:Commands(self:NextProvider())
	if not list then return end
	local groups = { { label = "Commands", items = {} }, { label = "Skills", items = {} } }
	for _, e in ipairs(list) do
		local group = e.t:sub(1, 1) == "/" and groups[1] or groups[2]
		table.insert(group.items, { value = e.t, label = e.d and (e.t .. "  " .. ns.Color("grey", e.d)) or e.t, group = group.label })
	end
	local options = {}
	for _, group in ipairs(groups) do
		if #group.items > 0 then
			table.insert(options, { header = true, label = group.label })
			for _, o in ipairs(group.items) do table.insert(options, o) end
		end
	end
	button.options = options
	button.value = nil
	UI.OpenList(button)
end

function M:InsertCommand(text)
	ns.Suggest:InsertAtCursor(text)
	if ns.Gamepad.capturing then
		-- Closing the list puts the controller's cursor back on its button a frame
		-- later; land on the message box after that, where A sends.
		C_Timer.After(0, function()
			C_Timer.After(0, function()
				if ns.Gamepad.capturing then ns.Gamepad:Highlight(self.composer) end
			end)
		end)
	end
end

---------------------------------------------------------------------------
-- Screenshots and reports

function M:ShotKey()
	if self.mode == "new" then return "new" end
	return ns.viewId
end

function M:ShotCount()
	if self.mode == "new" then return ns.Store.data.newShots or 0 end
	local v = ns.Store:View()
	return v and v.shots or 0
end

function M:ShotHint()
	local n = self:ShotCount()
	if n > 0 then
		return ns.Color("gold", string.format("%d screenshot%s attached", n, n == 1 and "" or "s")) .. ns.Color("grey", " (right-click the spyglass to remove)")
	end
end

-- The line under the message box: the screenshots attached, else on a thread what the
-- controller's buttons do.
function M:ShowHint()
	local hint = self:ShotHint()
	if not hint and self.mode ~= "new" and ns.Gamepad and ns.Gamepad:IsActive() then hint = ns.Gamepad:HintText() end
	self.frame.Pages.threads.Right.Hint:SetText(hint or "")
end

function M:AttachScreenshot()
	local key = self:ShotKey()
	if not key then
		ns.Print("Open a thread (or start a new one) first, then attach the screenshot.")
		return
	end
	ns.Transport:Send("shot", key)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

function M:RemoveScreenshots()
	local key = self:ShotKey()
	if key then ns.Transport:Send("unshot", key) end
end

-- Fill the message box with diagnostics (and attach a screenshot) for a bug report.
function M:Report(note)
	self:Open()
	if not ns.viewId and self.mode ~= "new" then self:StartNewThread() end
	local T = ns.Transport
	local b = ns.Store.data.bridge or {}
	local lines = { "--- T3 Code for World of Warcraft diagnostics ---" }
	table.insert(lines, string.format("addon %s, bridge %s, T3 %s (%s)", ns.version, b.version or "?", b.t3 or "?", b.server or "?"))
	table.insert(lines, string.format("link %s, signals %s via %s, live updates left %d/%d, queued %d", T:BridgeState(), T.signals, tostring(T.channel), T:SlotsLeft(), T.slotCount, #T.queue))
	if b.envs then
		local m = {}
		for _, e in ipairs(b.envs) do table.insert(m, e.label .. "=" .. e.state) end
		table.insert(lines, "machines " .. table.concat(m, ", "))
	end
	table.insert(lines, string.format("page %s, mode %s, gamepad %s, window scale %.2f", self.page, self.mode, tostring(ns.Gamepad:IsActive()), self.frame:GetScale() or 1))
	local errs = ns.db.errors or {}
	for i = math.max(1, #errs - 2), #errs do
		table.insert(lines, "error " .. date("%H:%M:%S", errs[i].t) .. ": " .. errs[i].msg)
	end
	local text = table.concat(lines, "\n")
	if note and note ~= "" then text = note .. "\n\n" .. text end
	local current = self.composer:GetInputText() or ""
	self.composer:SetText(current ~= "" and (current .. "\n\n" .. text) or text)
	self:AttachScreenshot()
	self.composer:SetFocus()
end

local SCALES = { normal = 1, large = 1.15, xlarge = 1.3 }

function M:ApplyScale()
	if not self.frame then return end
	local pref = ns.db.settings.windowScale or "auto"
	local scale = SCALES[pref] or ((ns.Gamepad and ns.Gamepad:IsActive()) and 1.15 or 1)
	self.frame:SetScale(scale)
end

-- The modern window's ground. 0 is solid; 100 lets the world show through.
-- The game's own frames have no ground to change.
function M:ApplyOpacity()
	local f = self.frame
	local theme = Theme.Get()
	if not f or not theme or not f.ModernBg then return end
	local clear = ns.db.settings.windowClear
	if type(clear) ~= "number" then clear = 6 end
	clear = math.max(0, math.min(100, clear))
	local alpha = 1 - clear / 100
	local bg = theme.windowBg
	f.ModernBg:SetColorTexture(bg[1], bg[2], bg[3], alpha)
	if f.ModernBand then f.ModernBand:SetColorTexture(bg[1], bg[2], bg[3], alpha) end
	for _, tab in ipairs(f.Tabs or {}) do
		if tab.Ground then tab.Ground:SetColorTexture(bg[1], bg[2], bg[3], alpha) end
	end
end

-- Switching designs rebuilds the window: each frame's look is chosen when it is
-- made, so a fresh window is simpler and safer than re-skinning frames built under
-- the other design. The open page, the draft in the message box and the window's
-- place on screen all survive.
function M:ApplyTheme()
	local shown = self.frame and self.frame:IsShown() or false
	local page = self.page or "threads"
	local section = ns.Settings.section
	self:SaveDraft()
	ns.Suggest:Teardown()
	if self.frame then self.frame:Hide() end
	self.frame, self.composer, self.placeholder, self.snoozePanel = nil, nil, nil, nil
	ns.ThreadList:Teardown()
	ns.Transcript:Teardown()
	ns.Family:Teardown()
	ns.Usage:Teardown()
	ns.Settings:Teardown()
	ns.Gamepad:ResetCursor()
	UI.ResetList()
	ns.Toasts:ApplyTheme()
	if ns.Tracker then ns.Tracker:Refresh() end
	self:Create()
	self:LoadDraft()
	self:ShowPage(page)
	-- Changing the accent rebuilds the window. Stay on the settings section
	-- that was open, instead of landing back on Notices.
	if section and ns.db.settings.theme == "modern" and ns.Settings.section then
		ns.Settings.section = section
		ns.Settings:Layout()
	end
	self.frame:SetShown(shown)
end

function M:ToggleDictation()
	if self.dictating then
		self.dictating = false
		ns.Transport:Send("dictate", "stop")
	else
		local b = ns.Store.data.bridge
		if b and b.dictationHint then
			-- Push-to-talk repeats while the key is held; say this once, not every time.
			local now = GetTime()
			if not self.dictNoteAt or now - self.dictNoteAt > 5 then
				self.dictNoteAt = now
				ns.Print(b.dictationHint)
			end
			return
		end
		self.dictating = true
		self:Open()
		self.composer:SetFocus()
		self.dictCmd = ns.Transport:Send("dictate", "start")
	end
	self:Refresh()
end

---------------------------------------------------------------------------
-- Status line and refresh

local LINK_TEXT = {
	connected = { "green", "Connected" },
	waiting = { "orange", "Waiting for the bridge… (run t3code-wow install on your desktop)" },
	stale = { "red", "Bridge not responding — is t3code-wow running?" },
	t3offline = { "red", "Bridge connected, but T3 Code is offline" },
	unheard = { "red", "T3 Code can't hear the game. Keep its top-left corner uncovered, and check t3code-wow status on your desktop." },
	exhausted = { "orange", "Live updates paused — /reload to resume" },
}

function M:StatusLine()
	local T = ns.Transport
	if T.slotError == "MISSING" then
		return ns.Color("red", "Live-update files missing — run t3code-wow install, then restart WoW")
	end
	local state = T:BridgeState()
	local entry = LINK_TEXT[state] or LINK_TEXT.waiting
	local text = ns.Color(entry[1], entry[2])
	if #T.queue > 0 and state ~= "unheard" then
		text = text .. ns.Color("grey", "  ·  sending…")
	end
	local left = T:SlotsLeft()
	if state == "connected" and left > 0 and left < math.max(40, T.slotCount * 0.15) then
		text = text .. ns.Color("orange", string.format("  ·  %d live updates left", left))
	end
	if self.dictating then
		text = text .. ns.Color("orange", "  ·  listening… release to finish")
	elseif self.dictState == "transcribing" then
		text = text .. ns.Color("orange", "  ·  transcribing…")
	elseif ns.Reading() then
		text = text .. ns.Color("orange", "  ·  reading aloud…")
	end
	return text
end

function M:UpdateRefreshButton()
	local f = self.frame
	if not f then return end
	local T = ns.Transport
	local low = T.exhausted or (T.slotCount > 0 and T:SlotsLeft() < T.slotCount * 0.15)
	f.RefreshSlots:SetShown(low and not InCombatLockdown())
end

-- Blizzard's edit box keeps a shown placeholder as the box's text, and only swaps
-- it while the box is empty. Changed in place, the old placeholder stayed behind as
-- text that focusing no longer cleared, so typing went after it. Set it again on an
-- empty box so the new one replaces the old.
function M:SetPlaceholder(text)
	if self.placeholder == text then return end
	self.placeholder = text
	self.composer:SetDefaultText(text)
	if self.composer:GetInputText() == "" then self.composer:SetText("") end
end

-- The open thread's header line: status, project, and how long it has been running
-- or how long ago it finished.
function M:HeaderText(t)
	local age = ((t.s == "working" or t.s == "waiting") and t.st) and ns.Duration(time() - t.st) or ns.Ago(t.u)
	-- A snoozed thread says when it's back, and little else: the Wake button already
	-- says it's snoozed, and beside the pickers there's only room for the time.
	if t.s == "snoozed" then
		return string.format("%s  ·  %s", ns.Color("grey", "Back " .. ns.Until(t.w)), ns.Store:ProjectName(t.p))
	end
	return string.format("%s  ·  %s  ·  %s",
		ns.Color(ns.Store.StatusColor(t.s), ns.Store.StatusText(t.s)), ns.Store:ProjectName(t.p), age)
end

function M:Refresh()
	local f = self.frame
	if not f or not f:IsShown() then return end
	f.Status:SetText(self:StatusLine())
	self.bridgeState = ns.Transport:BridgeState()
	self:UpdateRefreshButton()

	local right = f.Pages.threads.Right
	local header = right.Header
	local t = ns.Store:Thread(ns.viewId)
	-- The typed-time box belongs to the thread it was opened on.
	local panel = self.snoozePanel
	if panel and panel:IsShown() and (panel.threadId ~= ns.viewId or self.mode == "new" or not t or t.s == "snoozed") then panel:Hide() end
	if self.mode == "new" then
		f.Subtitle:SetText("New Thread")
		header.Text:SetText(ns.Color("gold", "New thread in"))
		header.Action:Hide()
		header.Archive:Hide()
		header.Snooze:Hide()
		header.Project:Show()
		self:SetupProjectDropdown()
		local withModel = self:SetupModelDropdown()
		local withEffort = withModel and self:SetupEffortDropdown()
		if not withEffort then header.Effort:Hide() end
		header.Model.tipBody = "The model the new thread starts on. It's remembered for this project."
		header.Effort.tipBody = "How hard the model reasons on the new thread. It's remembered for this project."
		header.Effort:ClearAllPoints()
		header.Effort:SetPoint("RIGHT", -6, 0)
		header.Model:ClearAllPoints()
		header.Model:SetPoint("RIGHT", withEffort and header.Effort or header, withEffort and "LEFT" or "RIGHT", withEffort and -4 or -6, 0)
		header.Project:ClearAllPoints()
		if withModel then
			header.Project:SetPoint("RIGHT", header.Model, "LEFT", -6, 0)
		else
			header.Project:SetPoint("RIGHT", -6, 0)
		end
		header.Text:ClearAllPoints()
		header.Text:SetPoint("LEFT", 12, 0)
		header.Text:SetPoint("RIGHT", header.Project, "LEFT", -8, 0)
		header.Text:SetJustifyH("RIGHT")
		self:SetPlaceholder("Describe what the agent should do  (Shift+Enter for a new line)")
		self:ShowHint()
		f.Bar.Send:SetText("Start")
	else
		header.Text:ClearAllPoints()
		header.Text:SetPoint("LEFT", 12, 0)
		header.Text:SetPoint("RIGHT", -110, 0)
		header.Text:SetJustifyH("CENTER")
		header.Project:Hide()
		f.Bar.Send:SetText("Send")
		if t then
			-- A subagent is run by the thread that started it, as in T3 Code, so it has
			-- no Settle, Snooze or model of its own to pick here.
			local fam = ns.Store:Family()
			local subagent = fam and fam.up and fam.up.k == "sub" or false
			f.Subtitle:SetText(t.title)
			header.Text:SetText(self:HeaderText(t))
			header.Action:SetShown(not subagent)
			header.Action:SetText(t.s == "settled" and "Reopen" or "Settle")
			header.Archive:SetShown(not subagent and t.s == "settled")
			-- Snooze shares Archive's place: a settled thread is archived, any other
			-- snoozed. Without presets from the bridge there's nothing to offer.
			local snoozable = not subagent and t.s ~= "settled" and (t.s == "snoozed" or #self:SnoozeOptions() > 0)
			header.Snooze:SetShown(snoozable)
			header.Snooze:SetText(t.s == "snoozed" and "Wake" or "Snooze")
			local withModel = not subagent and self:SetupModelDropdown()
			if not withModel then header.Model:Hide() end
			local withEffort = withModel and self:SetupEffortDropdown()
			if not withEffort then header.Effort:Hide() end
			header.Model.tipBody = "The model for this thread. A change applies from the next reply on."
			header.Effort.tipBody = "How hard the model reasons on this thread. A change applies from the next reply on."
			local anchor = t.s == "settled" and header.Archive or (snoozable and header.Snooze or header.Action)
			header.Effort:ClearAllPoints()
			header.Effort:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
			header.Model:ClearAllPoints()
			header.Model:SetPoint("RIGHT", withEffort and header.Effort or anchor, "LEFT", -4, 0)
			local pickers = (withModel and header.Model:GetWidth() + 4 or 0) + (withEffort and header.Effort:GetWidth() + 4 or 0)
			local buttons = subagent and 6 or ((t.s == "settled" or snoozable) and 200 or 110)
			header.Text:SetPoint("RIGHT", -buttons - pickers, 0)
			local busy = ns.db.settings.steerFollowUps and "Steer the agent" or "Queue a follow-up"
			if fam and fam.ro then
				self:SetPlaceholder("Read only: this subagent can't take messages.")
			else
				self:SetPlaceholder(((t.s == "working" or t.run) and busy or "Message the agent") .. "  (Shift+Enter for a new line)")
			end
		else
			if ns.viewId then
				-- Not in the list and its snapshot hasn't come yet: a relative just opened
				-- from the family bar shows what the family we hold says about it.
				local rel = ns.Store:Relative(ns.viewId)
				local status = rel and rel.s and (ns.Color(ns.Store.StatusColor(rel.s), ns.Store.StatusText(rel.s)) .. "  ·  ") or ""
				f.Subtitle:SetText(rel and rel.t or ns.Color("grey", "Loading…"))
				header.Text:SetText(status .. ns.Color("grey", "Loading…"))
			else
				f.Subtitle:SetText(ns.Color("grey", "No thread selected"))
				header.Text:SetText(ns.Color("grey", "Pick a thread on the left, or start a new one"))
			end
			header.Action:Hide()
			header.Archive:Hide()
			header.Snooze:Hide()
			header.Model:Hide()
			header.Effort:Hide()
		end
		self:ShowHint()
	end
	f.Bar.Stop:SetEnabled(t ~= nil and (t.s == "working" or t.run) and self.mode ~= "new")
	local fam = self.mode ~= "new" and ns.Store:Family()
	f.Bar.Send:SetEnabled(not (fam and fam.ro))
	f.Bar.Stop.Icon:SetDesaturated(not f.Bar.Stop:IsEnabled())
	local bridge = ns.Store.data.bridge
	local canDictate = self.dictating or not (bridge and bridge.dictationHint)
	f.Bar.Mic:SetEnabled(canDictate)
	f.Bar.Mic.Icon:SetDesaturated(not canDictate)
	UI.TintActive(f.Bar.Mic.Icon, self.dictating)
	local reading = ns.Reading()
	UI.TintActive(f.Bar.Speak.Icon, reading)
	f.Bar.Back:SetEnabled(self.mode == "new" or ns.viewId ~= nil or not f.Pages.threads.Left:IsShown())
	local commands = ns.Store:Commands(self:NextProvider())
	f.Bar.Insert:SetEnabled(commands ~= nil)
	f.Bar.Insert.Icon:SetDesaturated(commands == nil)
	self:UpdateCounter()
	ns.Suggest:Sync()
	ns.ThreadList:Refresh()
	ns.Family:Refresh()
	ns.Transcript:Refresh()
	ns.Transcript:ShowReading()
	-- The thread title belongs to the threads page. The other pages name themselves.
	if Theme.Get() and self.page ~= "threads" then
		f.Subtitle:SetText(self.page == "usage" and "Usage" or "Settings")
	end
end

---------------------------------------------------------------------------
-- Model picker

-- The model the player picked for the new thread, now or last time in this project.
-- Nil means T3 Code picks when the thread starts.
function M:ChosenNewModel()
	if self.newModel then return self.newModel end
	local saved = self.newProject and ns.db.models[self.newProject]
	if ns.Store:Offers(ns.Store.EnvOf(self.newProject), saved) then return saved end
end

-- What the picker shows: the chosen model, else T3 Code's default for the project.
function M:NewThreadModel()
	local chosen = self:ChosenNewModel()
	if chosen then return chosen end
	local env = ns.Store.EnvOf(self.newProject)
	local p = ns.Store.projectsById[self.newProject or ""]
	if p and p.dm then return p.dm end
	for _, o in ipairs(ns.Store:ModelOptions(env) or {}) do
		if not o.header then return o.value end
	end
end

-- The open thread's model, or the one just picked for it until T3 confirms it.
function M:ThreadModel(t)
	local current = ns.Store.ModelKey(t.mi, t.m)
	local pending = self.pendingModel
	if pending and pending.thread == t.id then
		if pending.value == current or GetTime() - pending.at > 30 then
			self.pendingModel = nil
		else
			return pending.value
		end
	end
	return current
end

-- The machine and provider instance the next message goes to, or nil when no model
-- is known. Threads on another machine use that machine's providers.
function M:NextProvider()
	local env, key
	if self.mode == "new" then
		env, key = ns.Store.EnvOf(self.newProject), self:NewThreadModel()
	else
		local t = ns.Store:Thread(ns.viewId)
		if not t then return nil end
		env, key = ns.Store.EnvOf(t.id), self:ThreadModel(t)
	end
	local instanceId = ns.Store.SplitModelKey(key)
	if not instanceId then return nil end
	return env, instanceId
end

-- Fill the model dropdown for what's on screen. Returns whether it's shown.
function M:SetupModelDropdown()
	local dd = self.frame.Pages.threads.Right.Header.Model
	local env, current
	if self.mode == "new" then
		env, current = ns.Store.EnvOf(self.newProject), self:NewThreadModel()
	else
		local t = ns.Store:Thread(ns.viewId)
		if t then env, current = ns.Store.EnvOf(t.id), self:ThreadModel(t) end
	end
	local options = env and ns.Store:ModelOptions(env, current)
	if not options or (self.mode ~= "new" and not current) then
		dd:Hide()
		return false
	end
	dd.value = current
	dd:SetOptions(options)
	-- Wide enough for "Model · Provider" where it fits, so the provider isn't cut off.
	local textW = dd.Text:GetUnboundedStringWidth() or 0
	dd:SetWidth(math.min(self.mode == "new" and 200 or 220, math.max(150, math.ceil(textW) + 40)))
	dd:Show()
	return true
end

-- The reasoning level picked for the new thread, now or last time in this project,
-- when the model it starts on offers it. Nil means the model's own.
function M:ChosenNewEffort()
	local options = ns.Store:EffortOptions(ns.Store.EnvOf(self.newProject), self:NewThreadModel())
	if ns.Store.HasOption(options, self.newEffort) then return self.newEffort end
	local saved = self.newProject and ns.db.efforts[self.newProject]
	if ns.Store.HasOption(options, saved) then return saved end
end

-- The open thread's reasoning level, or the one just picked for it until T3 confirms it.
function M:ThreadEffort(t)
	local pending = self.pendingEffort
	if pending and pending.thread == t.id then
		if pending.value == t.re or GetTime() - pending.at > 30 then
			self.pendingEffort = nil
		else
			return pending.value
		end
	end
	return t.re
end

-- Fill the reasoning dropdown for the model on screen. Returns whether it's shown.
function M:SetupEffortDropdown()
	local dd = self.frame.Pages.threads.Right.Header.Effort
	local env, model, current
	if self.mode == "new" then
		env, model = ns.Store.EnvOf(self.newProject), self:NewThreadModel()
		current = self:ChosenNewEffort()
		local p = ns.Store.projectsById[self.newProject or ""]
		if not current then
			-- What the bridge would carry over: T3's own pick when it's this model,
			-- else the level last used with the model.
			if p and p.dm == model then current = p.de else current = ns.Store:LastEffort(env, model) end
		end
	else
		local t = ns.Store:Thread(ns.viewId)
		if t then
			env, model, current = ns.Store.EnvOf(t.id), self:ThreadModel(t), self:ThreadEffort(t)
			-- Just switched to another model: it brings the level last used with it.
			if model ~= ns.Store.ModelKey(t.mi, t.m) and not (self.pendingEffort and self.pendingEffort.thread == t.id) then
				current = ns.Store:LastEffort(env, model)
			end
		end
	end
	local options, default = ns.Store:EffortOptions(env, model)
	if not options then
		dd:Hide()
		return false
	end
	-- A level the model doesn't have (after a model switch, say) shows as its default.
	dd.value = ns.Store.HasOption(options, current) and current or default
	dd:SetOptions(options)
	dd:Show()
	return true
end

function M:PickEffort(value)
	if self.mode == "new" then
		self.newEffort = value
		if self.newProject then ns.db.efforts[self.newProject] = value end
	else
		local t = ns.Store:Thread(ns.viewId)
		if not t or value == self:ThreadEffort(t) then return end
		local instanceId, slug = ns.Store.SplitModelKey(self:ThreadModel(t))
		if not instanceId then return end
		self.pendingEffort = { thread = t.id, value = value, at = GetTime(), cmd = ns.Transport:Send("model", t.id, instanceId, slug, value) }
	end
	self:Refresh()
end

function M:PickModel(value)
	if self.mode == "new" then
		self.newModel = value
		if self.newProject then ns.db.models[self.newProject] = value end
	else
		local t = ns.Store:Thread(ns.viewId)
		if not t or value == self:ThreadModel(t) then return end
		local instanceId, slug = ns.Store.SplitModelKey(value)
		if not instanceId then return end
		self.pendingModel = { thread = t.id, value = value, at = GetTime(), cmd = ns.Transport:Send("model", t.id, instanceId, slug) }
	end
	self:Refresh()
end

function M:SetupProjectDropdown()
	local options = {}
	for _, p in ipairs(ns.Store.data.projects) do table.insert(options, { value = p.id, label = p.name }) end
	self.frame.Pages.threads.Right.Header.Project:SetOptions(options, M.newProject)
end

---------------------------------------------------------------------------

function M:Open()
	self:Create()
	if not self.frame:IsShown() then self.frame:Show() end
end

function M:Toggle()
	self:Create()
	self.frame:SetShown(not self.frame:IsShown())
end

ns:On("Login", function()
	M:Create()
end)
-- Dictation results arrive in the snapshot; type them into the message box.
function M:HandleDictation(d)
	if type(d) ~= "table" or type(d.n) ~= "number" then return end
	if d.n <= (ns.db.lastDictN or 0) then return end
	ns.db.lastDictN = d.n
	if time() - math.floor(d.n / 1000) > 90 then return end -- left over from before a /reload
	-- A failed start (no backend, the bridge dropped it) must not leave the mic stuck
	-- "on", or the next press sends stop instead of start.
	if d.state ~= "listening" and d.state ~= "transcribing" then self.dictating = false end
	self.dictState = d.state
	if d.state == "done" and d.text and d.text ~= "" then
		self:Create()
		local box = self.composer
		local current = (box:GetInputText() or ""):gsub("%s+$", "")
		-- The backend also sends a paste keystroke; if that did land, don't add it twice.
		if not current:find(d.text, 1, true) then
			box:SetText(current ~= "" and (current .. " " .. d.text) or d.text)
		end
		self.dictState = nil
		PlaySound(SOUNDKIT.TELL_MESSAGE or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		if ns.db.settings.dictateSend then
			self:Send()
		elseif ns.Gamepad.capturing then
			ns.Gamepad:Highlight(box) -- A sends it
			box:SetFocus()
		else
			box:SetFocus()
		end
	elseif d.state == "empty" then
		self.dictState = nil
		ns.Print("Didn't catch anything — hold to talk and try again.")
	elseif d.state == "error" then
		self.dictState = nil
		ns.Print(ns.ChatColor("red", "Dictation: " .. (d.err or "failed")))
	elseif d.state == "cancelled" then
		self.dictState = nil
	end
	if self.frame and self.frame:IsShown() then self.frame.Status:SetText(self:StatusLine()) end
end

ns:On("DataChanged", function()
	M:HandleDictation(ns.Store.data.dict)
end)

ns:On("DataChanged", function()
	if M.frame and M.frame:IsShown() then M:Refresh() end
end)
ns:On("ReadingChanged", function()
	if M.frame and M.frame:IsShown() then M:Refresh() end
end)
ns:On("LinkChanged", function()
	if M.frame and M.frame:IsShown() then
		M.frame.Status:SetText(M:StatusLine())
		M:UpdateRefreshButton()
	end
end)
-- A thread the player just snoozed is out of the way now: clear it off the screen so
-- the next one can be picked. Opening a snoozed thread from the list still shows it.
ns:On("ThreadTransition", function(t, _, after)
	local pending = M.pendingSnooze
	if after ~= "snoozed" or not pending or pending.thread ~= t.id then return end
	M.pendingSnooze = nil
	-- Only right after the pick: a busy thread that turns snoozed minutes later, when
	-- its run ends, shouldn't vanish from under the player.
	if GetTime() - pending.at > 20 then return end
	if ns.viewId == t.id and M.mode == "thread" and M.frame then M:CloseThread() end
end)

ns:On("CommandResult", function(r)
	if r.ok == false and r.id == M.dictCmd then
		-- The start was refused before the bridge sent a dictation state; put the
		-- mic back so the next press starts instead of sending stop.
		M.dictCmd = nil
		M.dictating = false
		if M.frame and M.frame:IsShown() then M:Refresh() end
	end
	if r.ok == false and M.pendingSnooze and r.id == M.pendingSnooze.cmd then M.pendingSnooze = nil end
	if r.ok == false and r.msg then
		ns.Print(ns.ChatColor("red", r.msg))
		if UIErrorsFrame then UIErrorsFrame:AddMessage("T3 Code: " .. r.msg, 1, 0.2, 0.2) end
	end
	if r.ok == false then
		local refused
		if M.pendingModel and r.id == M.pendingModel.cmd then M.pendingModel, refused = nil, true end
		if M.pendingEffort and r.id == M.pendingEffort.cmd then M.pendingEffort, refused = nil, true end
		if refused and M.frame and M.frame:IsShown() then M:Refresh() end
	end
	if r.id == M.pendingNew then
		M.pendingNew = nil
		if r.ok and r.open then
			M.mode = "thread"
			M:SelectThread(r.open)
		end
	end
end)

-- Live elapsed timers in the header and the visible rows. Only the text changes: the
-- list and the transcript refresh their rows in place, so this is much cheaper than a
-- full Refresh, which rebuilds both from the snapshot.
function M:RefreshTimers()
	local f = self.frame
	if not f or not f:IsShown() then return end
	local t = ns.Store:Thread(ns.viewId)
	if t and self.mode == "thread" then
		f.Pages.threads.Right.Header.Text:SetText(self:HeaderText(t))
	end
	ns.ThreadList:Refresh()
	ns.Transcript:Refresh()
end

C_Timer.NewTicker(1, ns.Safe(function()
	if not (M.frame and M.frame:IsShown()) then return end
	-- The link can go stale on its own clock, with no update arriving to say so.
	local state = ns.Transport:BridgeState()
	if state ~= M.bridgeState then
		M.bridgeState = state
		if M.page == "threads" then
			M:Refresh()
		else
			M.frame.Status:SetText(M:StatusLine())
			M:UpdateRefreshButton()
		end
		return
	end
	if M.page ~= "threads" then return end
	for _, t in ipairs(ns.Store.data.threads) do
		if t.s == "working" or t.s == "waiting" then
			M:RefreshTimers()
			return
		end
	end
end))
