-- The two looks the window can wear. "classic" is Blizzard's own ornate templates,
-- used exactly as the game draws them. "modern" follows Omarchy's UI kit
-- (omarchy-ui, spec/tokens.md and spec/components.md) in one of Omarchy's own
-- themes: the theme's background, foreground glass for controls (the foreground
-- at a low alpha), hairlines in the foreground at 12%, square corners, and the
-- accent only on what is chosen. Every modern surface is a plain colored texture,
-- so nothing depends on an atlas resolving.

local _, ns = ...

local Theme = {}
ns.Theme = Theme

Theme.DEFAULT_PALETTE = "tokyo-night"

---------------------------------------------------------------------------
-- Colors

-- "#rrggbb" as { r, g, b } in 0..1.
local function Parse(hex)
	if type(hex) ~= "string" then return end
	local r, g, b = hex:match("^#?(%x%x)(%x%x)(%x%x)$")
	if not r then return end
	return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
end

local function Byte(n) return math.max(0, math.min(255, math.floor((n or 0) * 255 + 0.5))) end

-- { r, g, b } as WoW font markup ("ffrrggbb").
local function Hex(c)
	return string.format("ff%02x%02x%02x", Byte(c[1]), Byte(c[2]), Byte(c[3]))
end
Theme.Hex = Hex

-- Qt's darker(): the same hue, value divided by `f`, kept to 8-bit channels.
local function Darker(c, f)
	return { Byte(c[1] / f) / 255, Byte(c[2] / f) / 255, Byte(c[3] / f) / 255 }
end

-- `t` of the way from a to b, per 8-bit channel, rounded.
local function Mix(a, b, t)
	local out = {}
	for i = 1, 3 do out[i] = Byte(a[i] + (b[i] - a[i]) * t) / 255 end
	return out
end

-- WCAG relative luminance and contrast ratio.
local function Luminance(c)
	local sum = 0
	for i, w in ipairs({ 0.2126, 0.7152, 0.0722 }) do
		local v = c[i]
		v = v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
		sum = sum + w * v
	end
	return sum
end

function Theme.Contrast(a, b)
	local la, lb = Luminance(a), Luminance(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

-- A class color under this ratio against the background reads poorly (WCAG's
-- minimum for large text and UI parts), so the theme's accent stands in.
Theme.MIN_ACCENT_CONTRAST = 3

-- A theme's colors as omarchy-ui resolves them (spec/tokens.md, "Palette" and
-- "Roles"), from what its colors.toml gives. The defaults are the kit's.
function Theme.Resolve(p)
	p = p or {}
	local light = p.mode == "light"
	local function pick(...)
		for i = 1, select("#", ...) do
			local c = Parse(select(i, ...))
			if c then return c end
		end
	end
	local bg = pick(p.background, p.color0, "#101315")
	local fg = pick(p.foreground, p.color7, "#cacccc")
	local r = {
		id = p.id,
		label = p.label,
		mode = light and "light" or "dark",
		background = bg,
		foreground = fg,
		accent = pick(p.accent, p.color4, "#cacccc"),
		-- Secondary text, then disabled and placeholder text. Without the theme's own,
		-- they fade toward the background: darker in a dark theme, mixed in a light one,
		-- where darker would make them stronger than the foreground.
		textDim = pick(p.dark_foreground, p.dark_fg) or (light and Mix(fg, bg, 1 / 3) or Darker(fg, 1.5)),
		textFaint = pick(p.muted, p.color8) or (light and Mix(fg, bg, 1 / 2) or Darker(fg, 2)),
		red = pick(p.red, p.color1, "#a55555"),
		green = pick(p.green, p.color2, "#7f9f6f"),
		yellow = pick(p.yellow, p.color3, "#c0a060"),
	}
	-- The kit names no orange or blue; these stand closest.
	r.orange = pick(p.orange) or r.yellow
	r.blue = pick(p.blue, p.color4) or r.accent
	return r
end

local function FindPalette(id)
	local list = ns.PALETTES or {}
	for _, p in ipairs(list) do
		if p.id == id then return p end
	end
	for _, p in ipairs(list) do
		if p.id == Theme.DEFAULT_PALETTE then return p end
	end
	return list[1]
end

-- The themes Settings offers, Tokyo Night first.
function Theme.Palettes()
	local out = {}
	for _, p in ipairs(ns.PALETTES or {}) do table.insert(out, { value = p.id, label = p.label }) end
	return out
end

---------------------------------------------------------------------------
-- Accent

-- The game's own class colors, for a client that has no table of them.
local CLASS_COLORS = {
	WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 },
	ROGUE = { 1, 0.96, 0.41 }, PRIEST = { 1, 1, 1 }, SHAMAN = { 0, 0.44, 0.87 },
	MAGE = { 0.25, 0.78, 0.92 }, WARLOCK = { 0.53, 0.53, 0.93 }, DRUID = { 1, 0.49, 0.04 },
}

-- The player's class file and localized name, once they're in the world.
local function PlayerClass()
	if not UnitClass then return end
	local name, file = UnitClass("player")
	if file and file ~= "" then return file, name end
end

-- A class's color: the client's, which a class-color addon may change, else ours.
local function ClassRGB(file)
	local c = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(file)
	if not (c and type(c.r) == "number") then c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[file] end
	if c and type(c.r) == "number" then return { c.r, c.g, c.b } end
	local own = CLASS_COLORS[file]
	if own then return { own[1], own[2], own[3] } end
end

-- The accent for a choice ("class" or "theme") on a resolved palette. Returns the
-- color and why it was picked: "class", "theme", "unknown" (no class yet) or
-- "faint" (the class color is too close to the background).
function Theme.PickAccent(choice, pal)
	if choice == "class" then
		local file = PlayerClass()
		local c = file and ClassRGB(file)
		if not c then return pal.accent, "unknown" end
		if Theme.Contrast(c, pal.background) < Theme.MIN_ACCENT_CONTRAST then return pal.accent, "faint" end
		return c, "class"
	end
	return pal.accent, "theme"
end

-- The Accent choices, with the class named once it's known, and why it isn't used
-- when it reads too faintly on this theme.
function Theme.Accents()
	local file, name = PlayerClass()
	local class = "Class color"
	if name then class = "Class color (" .. name .. ")" end
	if Theme.accentWhy == "faint" then class = class .. ", too faint here: theme accent" end
	return { { value = "class", label = class }, { value = "theme", label = "Theme accent" } }
end

---------------------------------------------------------------------------
-- Tokens

-- One table the whole window paints from. Its entries are filled in place by
-- Apply, so a widget holding a token sees the current theme's color.
local function Token() return { 0, 0, 0, 1 } end
Theme.MODERN = {
	windowBg = Token(), -- the theme's background; its alpha is the transparency setting
	panel = Token(), -- cards and the composer: the controls' normal glass
	panelAlt = Token(), -- buttons and dropdowns: the same glass
	controlBorder = Token(), -- the border of inputs, dropdowns and bordered buttons
	overlay = Token(), -- popups over everything: the background, solid
	popupBorder = Token(), -- popups: the accent, as Hyprland's active border
	hairline = Token(), -- rules and borders: the foreground at 12%
	track = Token(), -- the unfilled part of a bar or slider: the same
	hover = Token(), -- under the pointer or the controller's cursor
	selected = Token(), -- the chosen row
	pressed = Token(), -- a button held down
	accent = Token(), -- what is chosen: a check, a switch that's on, the selected thread
	onAccent = Token(), -- text on an accent fill: the background
	text = Token(), -- the foreground
	muted = Token(), -- textDim: subtitles, values, hints, status lines
	faint = Token(), -- textFaint: disabled and placeholder text
	knob = Token(), -- a switch's knob when off: the foreground, darker 1.25
	switchOff = Token(), -- a switch's track when off: the normal glass
	red = Token(), green = Token(), yellow = Token(), orange = Token(), blue = Token(),
}

local function Set(token, c, a)
	token[1], token[2], token[3], token[4] = c[1], c[2], c[3], a or 1
end

-- Hex markup for the colors text carries ("ffrrggbb"), by ns.COLORS key.
Theme.MARKUP = {}
-- `accent` as WoW font markup. Headings and the bridge's markdown use the game's
-- gold; in this window that gold means the accent.
Theme.ACCENT_HEX = "ff7aa2f7"

-- Fill the tokens from a palette and an accent choice.
function Theme.Apply(paletteId, accentChoice, clear)
	local pal = Theme.Resolve(FindPalette(paletteId))
	local accent, why = Theme.PickAccent(accentChoice, pal)
	Theme.palette, Theme.accentWhy = pal, why
	local M, fg, bg = Theme.MODERN, pal.foreground, pal.background
	if type(clear) ~= "number" then clear = 6 end
	Set(M.windowBg, bg, 1 - math.max(0, math.min(100, clear)) / 100)
	Set(M.panel, fg, 0.04)
	Set(M.panelAlt, fg, 0.04)
	Set(M.controlBorder, fg, 0.4)
	Set(M.overlay, bg, 1)
	Set(M.popupBorder, accent)
	Set(M.hairline, fg, 0.12)
	Set(M.track, fg, 0.12)
	Set(M.hover, fg, 0.08)
	Set(M.selected, fg, 0.18)
	Set(M.pressed, fg, 0.22)
	Set(M.accent, accent)
	Set(M.onAccent, bg)
	Set(M.text, fg)
	Set(M.muted, pal.textDim)
	Set(M.faint, pal.textFaint)
	Set(M.knob, Darker(fg, 1.25))
	Set(M.switchOff, fg, 0.04)
	for _, k in ipairs({ "red", "green", "yellow", "orange", "blue" }) do Set(M[k], pal[k]) end
	M.mode = pal.mode
	Theme.ACCENT_HEX = Hex(accent)
	local mk = Theme.MARKUP
	mk.gold, mk.white, mk.grey = Theme.ACCENT_HEX, Hex(fg), Hex(pal.textDim)
	mk.green, mk.red, mk.orange = Hex(pal.green), Hex(pal.red), Hex(pal.orange)
	mk.blue, mk.agent = Hex(pal.blue), Hex(pal.blue)
	if Theme.UpdateFonts then Theme.UpdateFonts() end
	return M
end

-- The palette for the chosen design; nil means the game's own templates. The
-- tokens are worked out again only when a setting they come from changes.
local appliedKey
function Theme.Get()
	local s = ns.db and ns.db.settings
	if not (s and s.theme == "modern") then return end
	local key = tostring(s.palette) .. "|" .. tostring(s.accent) .. "|" .. tostring(s.windowClear) .. "|" .. tostring((PlayerClass()))
	if key ~= appliedKey then
		appliedKey = key
		Theme.Apply(s.palette, s.accent, s.windowClear)
	end
	return Theme.MODERN
end

-- Forget the applied tokens, so the next Get works them out again (a class-color
-- addon may have changed the table they came from).
function Theme.Invalidate()
	appliedKey = nil
end

---------------------------------------------------------------------------
-- Fonts

-- The kit's type scale (spec/tokens.md, "Typography"): one family at token sizes,
-- bold only for what is selected and for titles. Each is a font object of ours,
-- colored from the theme, so no text keeps the game's white on a light theme.
local FONTS = {
	T3ModernCaption = { size = 10, ink = "muted" },
	T3ModernSmall = { size = 11, ink = "text" },
	T3ModernSmallDim = { size = 11, ink = "muted" },
	T3ModernSmallFaint = { size = 11, ink = "faint" },
	T3ModernSmallAccent = { size = 11, ink = "accent" },
	T3ModernSmallGreen = { size = 11, ink = "green" },
	T3ModernBody = { size = 12, ink = "text" },
	T3ModernBodyDim = { size = 12, ink = "muted" },
	T3ModernBodyAccent = { size = 12, ink = "accent" },
	T3ModernBodyBold = { size = 12, ink = "text", bold = true },
	T3ModernSubtitle = { size = 13, ink = "text" },
	T3ModernTitle = { size = 14, ink = "text", bold = true },
	T3ModernHeading = { size = 16, ink = "text", bold = true },
}
Theme.FONTS = FONTS

-- The game's font templates the window uses, and the kit font that stands in for
-- each. The game's gold (Normal) is the accent; Disable is the dim text.
local STAND_IN = {
	GameFontHighlight = "T3ModernBody",
	GameFontHighlightSmall = "T3ModernSmall",
	GameFontHighlightMedium = "T3ModernSubtitle",
	GameFontNormal = "T3ModernBodyAccent",
	GameFontNormalSmall = "T3ModernSmallAccent",
	GameFontNormalMed2 = "T3ModernTitle",
	GameFontNormalLarge = "T3ModernTitle",
	Game15Font_Shadow = "T3ModernTitle",
	GameFontDisable = "T3ModernBodyDim",
	GameFontDisableSmall = "T3ModernSmallDim",
	GameFontGreenSmall = "T3ModernSmallGreen",
	ObjectiveTrackerHeaderFont = "T3ModernBodyBold",
	ObjectiveTrackerLineFont = "T3ModernSmallDim",
	ChatFontNormal = "T3ModernBody",
}

-- The font files: JetBrains Mono, Omarchy's default monospace (Media/fonts, under
-- the SIL Open Font License in OFL.txt). Without them, the game's own font.
Theme.FONT_REGULAR = ns.media .. "fonts\\JetBrainsMono-Regular.ttf"
Theme.FONT_BOLD = ns.media .. "fonts\\JetBrainsMono-Bold.ttf"

local function GameFont()
	local path = GameFontHighlight and GameFontHighlight.GetFont and GameFontHighlight:GetFont()
	return path or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

-- Point a font object at `file`, or at the game's font when the file won't load:
-- SetFont answers false for a file it can't use, and the object keeps no font.
local function SetFace(obj, file, size)
	if file then
		local ok = obj:SetFont(file, size, "")
		if ok ~= false and obj:GetFont() then return true end
	end
	obj:SetFont(GameFont(), size, "")
	return false
end

-- Create the kit's font objects, or bring their colors up to the current theme.
function Theme.UpdateFonts()
	if not CreateFont then return end
	local M = Theme.MODERN
	Theme.fontOk = true
	for name, spec in pairs(FONTS) do
		local obj = _G[name] or CreateFont(name)
		if not SetFace(obj, spec.bold and Theme.FONT_BOLD or Theme.FONT_REGULAR, spec.size) and Theme.FONT_REGULAR then
			Theme.fontOk = false
		end
		obj:SetShadowOffset(0, 0)
		local ink = M[spec.ink]
		obj:SetTextColor(ink[1], ink[2], ink[3], 1)
	end
end

-- Game fonts that Classic Era doesn't have, and the closest one it does.
local CLASSIC_FALLBACK = {
	Game15Font_Shadow = "GameFontHighlightMedium",
}

-- The font for `template`: the template itself on the classic look (or its fallback
-- where the client lacks it), the kit's stand-in on the modern one. A kit font's own
-- name is accepted too.
function Theme.Font(template)
	if not Theme.Get() then
		if _G[template] == nil and CLASSIC_FALLBACK[template] then return CLASSIC_FALLBACK[template] end
		return template
	end
	if FONTS[template] then return template end
	return STAND_IN[template] or "T3ModernBody"
end

---------------------------------------------------------------------------
-- Painting

-- Paint a texture flat with a palette color.
function Theme.Paint(tex, token)
	tex:SetColorTexture(token[1], token[2], token[3], token[4] or 1)
	return tex
end

-- The same palette color on a font string.
function Theme.SetText(fs, token)
	fs:SetTextColor(token[1], token[2], token[3], token[4] or 1)
	return fs
end

-- The game's colors inside a string the window is about to draw, as this theme's:
-- gold is the accent, white the foreground, grey the dim text, and so on, so a
-- light theme stays readable. Left alone on the classic look.
function Theme.Markup(text)
	if not text or not Theme.Get() then return text end
	return (text:gsub("|c(%x%x%x%x%x%x%x%x)", function(hex)
		local key = Theme.colorKeys[hex:lower()]
		return key and ("|c" .. Theme.MARKUP[key]) or nil
	end))
end

-- ns.COLORS values back to their keys, for Markup.
Theme.colorKeys = {}
for key, hex in pairs(ns.COLORS or {}) do Theme.colorKeys[hex:lower()] = key end

-- A flat colored layer; the caller anchors it.
function Theme.Solid(parent, token, layer)
	return Theme.Paint(parent:CreateTexture(nil, layer or "BACKGROUND"), token)
end

-- Four 1px rules around the parent's edge: a border that stays crisp at any
-- window scale, without any art. `skipLeft` drops the left rule, for a tab that
-- grows out of the border it attaches to.
function Theme.Edges(parent, token, skipLeft)
	local function rule(vertical)
		local t = parent:CreateTexture(nil, "ARTWORK")
		Theme.Paint(t, token)
		if vertical then t:SetWidth(1) else t:SetHeight(1) end
		return t
	end
	local top, bottom = rule(false), rule(false)
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	bottom:SetPoint("BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT")
	local left
	if not skipLeft then
		left = rule(true)
		left:SetPoint("TOPLEFT")
		left:SetPoint("BOTTOMLEFT")
	end
	local right = rule(true)
	right:SetPoint("TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT")
	return top, bottom, left, right
end
