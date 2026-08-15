--[[===========================================================================
	Eternal Club — Hub / Loader
	by FallenSoul7 (Asimboss0078)

	One self-contained script that turns the Eternal Club repository
	(https://github.com/FallenSoul7/Eternal-Club1) into a selectable hub:

	  * A clean, minimal ScreenGui menu is built from scratch — no external
	    UI library, no copy-pasted code. Everything below is original.
	  * The menu mirrors the repository skeleton 1:1: the Games / Universal /
	    Other categories and every subcategory folder become selectable
	    options, exactly as they exist in the repo.
	  * Folders with subfolders open a sub-menu. Each sub-menu also offers a
	    "load from this folder" option so folder-level scripts stay reachable.
	  * Selecting an option fetches the script at the convention URL
	        https://raw.githubusercontent.com/FallenSoul7/Eternal-Club1/main/<folder-path>/Main.lua
	    (spaces and special characters URL-encoded) and executes it.
	  * The repo is still being filled in, so missing scripts show a friendly
	    "Coming soon" notice instead of an error stack.

	Requirements: any Roblox executor with HTTP access (request() /
	http_request / syn.request, falling back to HttpService).
=============================================================================]]

-- ============================== Configuration ==============================

local REPO_OWNER   = "FallenSoul7"
local REPO_NAME    = "Eternal-Club1"
local REPO_BRANCH  = "main"
local REPO_BASE    = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(
	REPO_OWNER, REPO_NAME, REPO_BRANCH
)

-- Hub branding (shown in the UI header).
local HUB_TITLE    = "Eternal Club"
local HUB_SUBTITLE = "by FallenSoul7 (Asimboss0078)"

-- ============================== Script list ================================
-- The repository skeleton, mirrored exactly. A plain string is a leaf folder
-- (a script that will live at <folder>/Main.lua). A table
-- { Label = ..., Children = ... } is a folder containing more folders.
-- Keeping this list in sync with the repo means the hub always shows
-- exactly what the repository offers.

local HUB_TREE = {
	{
		Label = "Games",
		Children = {
			"Anomic",
			"Build A Boat For Treasure",
			"CS Prison Life",
			{ Label = "Criminality", Children = {
				"Combat", "ESP", "Player", "Random Dumps",
			} },
			"D-Day",
			"Da Hood",
			"Dawn of Aurora",
			{ Label = "Decaying Winter", Children = {
				"FallenSoul-ified",
			} },
			"Field Trip Z",
			"Frontlines",
			"Funky Friday",
			"Furry Hunting Simulator",
			"Hood Duels",
			"Identity Fraud",
			"Infinite Autocorrect",
			"Island Royale",
			{ Label = "Kohls Admin House", Children = {
				{ Label = "Archive", Children = {
					"oofkohlsv1", "oofkohlsv2",
				} },
				"AudioVisualiser",
				"ClickMove",
				"DarkKohls",
				"MusicCommands",
				{ Label = "Signals", Children = {
					"Modules",
				} },
			} },
			"Lumberjack",
			"Mega Miners",
			{ Label = "Notoriety", Children = {
				"Autofarm",
			} },
			"Obliteration Orbs",
			{ Label = "PLS DONATE", Children = {
				"Scripts",
			} },
			"Phantom Forces",
			{ Label = "Piggy", Children = {
				"v2",
			} },
			"Project Lazarus Zombies",
			"Relinquit",
			"Rolling Thunder",
			"Rush Point",
			"Stay alive and flex your time on others",
			"Weaponry",
			"Wonder Woman The Themyscira Experience",
			"[USA] Washington, District of Columbia",
			"ببجي للعرب",
		},
	},
	{
		Label = "Universal",
		Children = {
			{ Label = "Aiming", Children = {
				"Examples", "GamePatches",
			} },
			"Benchmark",
			"Commands",
			{ Label = "ESP", Children = {
				"Archive", "Examples",
			} },
			{ Label = "Music API", Children = {
				{ Label = "JavaScript Version", Children = {
					"Examples",
				} },
				"Web Version",
			} },
			"Notifications",
			"SongLyrics",
			"UI Libraries",
			"Word Bypass",
		},
	},
	{
		Label = "Other",
		Children = {
			"FallenSoul-ified",
			"GitHubAPI",
			"SynapseVulnerabilitiesBugs",
		},
	},
}

-- ---------------------------------------------------------------------------
-- Offline self-check (skipped inside Roblox). Running this file under a plain
-- Lua interpreter prints the full option tree so it can be diffed against the
-- actual repository layout to prove every folder is listed. Harmless in-game
-- because `game` always exists there.
-- ---------------------------------------------------------------------------
if not game then
	local function walk(items, prefix)
		for _, item in ipairs(items) do
			local segment = (type(item) == "string") and item or item.Label
			local path = (prefix == "") and segment or (prefix .. "/" .. segment)
			print(path)
			if type(item) == "table" then
				walk(item.Children, path)
			end
		end
	end
	walk(HUB_TREE, "")
	return
end

-- ============================ Executor HTTP API ============================

-- Pick the strongest HTTP facility the executor provides.
local REQUEST
if type(request) == "function" then
	REQUEST = request                                    -- Synapse X / Fluxus / Script-Ware...
elseif type(http_request) == "function" then
	REQUEST = http_request                               -- older executors
elseif type(syn) == "table" and type(syn.request) == "function" then
	REQUEST = syn.request                                -- legacy Synapse wrapper
end

-- Fetch a URL's body. Returns (body) on success, or (nil, reason) on failure,
-- where reason is "http_404" when the resource simply does not exist yet.
local function fetchUrl(url)
	if REQUEST then
		local ok, res = pcall(REQUEST, { Url = url, Method = "GET" })
		if ok and type(res) == "table" then
			if res.Success and res.StatusCode == 200 and type(res.Body) == "string" then
				return res.Body
			end
			return nil, "http_" .. tostring(res.StatusCode or "error")
		end
	end
	-- Fallback: Roblox HttpService (raises on non-200, so pcall it).
	local HttpService = game:GetService("HttpService")
	local ok, body = pcall(function()
		return HttpService:GetAsync(url)
	end)
	if ok and type(body) == "string" then
		return body
	end
	local msg = tostring(body)
	if msg:find("404", 1, true) then
		return nil, "http_404"
	end
	return nil, "http_error"
end

-- ============================ URL building =================================

-- Percent-encode a path segment (spaces -> %20, UTF-8 bytes, brackets, etc.).
-- Only unreserved characters pass through untouched.
local function urlEncode(segment)
	local out = {}
	for i = 1, #segment do
		local byte = segment:byte(i)
		if (byte >= 0x30 and byte <= 0x39)      -- 0-9
			or (byte >= 0x41 and byte <= 0x5A)  -- A-Z
			or (byte >= 0x61 and byte <= 0x7A)  -- a-z
			or segment:sub(i, i) == "-"
			or segment:sub(i, i) == "_"
			or segment:sub(i, i) == "."
			or segment:sub(i, i) == "~"
		then
			out[#out + 1] = segment:sub(i, i)
		else
			out[#out + 1] = string.format("%%%02X", byte)
		end
	end
	return table.concat(out)
end

-- Convention URL for a folder:
-- https://raw.githubusercontent.com/<owner>/<repo>/<branch>/<path>/Main.lua
local function scriptUrl(pathParts)
	local encoded = {}
	for _, part in ipairs(pathParts) do
		encoded[#encoded + 1] = urlEncode(part)
	end
	return REPO_BASE .. table.concat(encoded, "/") .. "/Main.lua"
end

-- ================================ UI colors ================================

local COLORS = {
	bg          = Color3.fromRGB(23, 26, 34),
	panel       = Color3.fromRGB(30, 34, 45),
	button      = Color3.fromRGB(41, 46, 60),
	buttonHover = Color3.fromRGB(56, 63, 82),
	folder      = Color3.fromRGB(47, 52, 70),
	folderHover = Color3.fromRGB(63, 70, 92),
	accent      = Color3.fromRGB(240, 195, 85),   -- gold accent
	text        = Color3.fromRGB(235, 237, 243),
	dim         = Color3.fromRGB(150, 156, 170),
	ok          = Color3.fromRGB(120, 220, 140),  -- status: success
	info        = Color3.fromRGB(140, 190, 255),  -- status: loading
	warn        = Color3.fromRGB(255, 190, 90),   -- status: coming soon
	err         = Color3.fromRGB(255, 110, 110),  -- status: error
}

-- ============================ UI construction ==============================

local Players = game:GetService("Players")

-- Tiny instance factory to keep the UI-building code short and readable.
local function make(class, parent, props)
	local obj = Instance.new(class)
	obj.Parent = parent
	for key, value in pairs(props) do
		obj[key] = value
	end
	return obj
end

-- Build the hub screen and return its interactive parts.
local function buildUI()
	-- Put the UI in CoreGui when possible so it survives death/respawn.
	local parentGui
	pcall(function() parentGui = game:GetService("CoreGui") end)
	if not parentGui then
		parentGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	end

	local gui = make("ScreenGui", parentGui, {
		Name = "EternalClubHub",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 99,
	})

	-- Root frame: fixed-size dark panel, centered on screen.
	local root = make("Frame", gui, {
		Name = "Hub",
		Size = UDim2.fromOffset(420, 600),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = COLORS.bg,
		BorderSizePixel = 0,
	})
	make("UICorner", root, { CornerRadius = UDim.new(0, 10) })
	make("UIStroke", root, { Color = COLORS.panel, Thickness = 2 })

	-- Close button (top-right corner).
	local closeBtn = make("TextButton", root, {
		Name = "Close",
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(1, -38, 0, 10),
		Text = "X",
		TextColor3 = COLORS.dim,
		TextSize = 16,
		Font = Enum.Font.Gotham,
		BackgroundColor3 = COLORS.panel,
		AutoButtonColor = false,
		BorderSizePixel = 0,
	})
	make("UICorner", closeBtn, { CornerRadius = UDim.new(0, 6) })

	-- Header: title + subtitle.
	make("TextLabel", root, {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 18, 0, 10),
		Text = HUB_TITLE,
		TextColor3 = COLORS.accent,
		TextSize = 24,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
	})
	make("TextLabel", root, {
		Name = "Subtitle",
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 18, 0, 44),
		Text = HUB_SUBTITLE,
		TextColor3 = COLORS.dim,
		TextSize = 13,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
	})

	-- Toolbar: back button + current-path breadcrumb.
	local backBtn = make("TextButton", root, {
		Name = "Back",
		Size = UDim2.fromOffset(64, 26),
		Position = UDim2.new(0, 12, 0, 84),
		Text = "< Back",
		TextColor3 = COLORS.text,
		TextSize = 13,
		Font = Enum.Font.Gotham,
		BackgroundColor3 = COLORS.panel,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Visible = false,
	})
	make("UICorner", backBtn, { CornerRadius = UDim.new(0, 6) })
	local pathLabel = make("TextLabel", root, {
		Name = "Path",
		Size = UDim2.new(1, -92, 0, 26),
		Position = UDim2.new(0, 84, 0, 84),
		Text = "",
		TextColor3 = COLORS.dim,
		TextSize = 13,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		BackgroundTransparency = 1,
	})

	-- Scrollable option list.
	local scroller = make("ScrollingFrame", root, {
		Name = "List",
		Size = UDim2.new(1, -24, 0, 600 - 84 - 26 - 58),
		Position = UDim2.new(0, 12, 0, 116),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = COLORS.panel,
		CanvasSize = UDim2.new(0, 0, 0, 0),
	})
	local list = make("Frame", scroller, {
		Name = "Rows",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})

	-- Status / message bar at the bottom.
	local statusLabel = make("TextLabel", root, {
		Name = "Status",
		Size = UDim2.new(1, -24, 0, 42),
		Position = UDim2.new(0, 12, 1, -50),
		Text = "Pick a script to load it.",
		TextColor3 = COLORS.dim,
		TextSize = 13,
		Font = Enum.Font.Gotham,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
	})
	make("UICorner", statusLabel, { CornerRadius = UDim.new(0, 8) })

	return {
		gui = gui,
		closeBtn = closeBtn,
		backBtn = backBtn,
		pathLabel = pathLabel,
		scroller = scroller,
		list = list,
		statusLabel = statusLabel,
	}
end

-- ============================ Menu navigation ==============================

local ROW_HEIGHT = 40

-- Shallow-copy a path array and append one segment.
local function pathPush(pathParts, segment)
	local out = {}
	for _, part in ipairs(pathParts) do
		out[#out + 1] = part
	end
	if segment then
		out[#out + 1] = segment
	end
	return out
end

-- Rebuild the visible option list for a given level of the tree.
-- items:      HUB_TREE children (strings and/or {Label, Children} tables)
-- pathParts:  folder path segments from the repo root down to this level
local function showMenu(ui, items, pathParts)
	-- Clear previous rows.
	for _, child in ipairs(ui.list:GetChildren()) do
		child:Destroy()
	end

	-- Breadcrumb + back-button visibility.
	local crumb = table.concat(pathParts, "  >  ")
	ui.pathLabel.Text = (crumb == "") and "Home" or crumb
	ui.backBtn.Visible = (#pathParts > 0)

	local y = 0

	local function addRow(text, kind, onClick)
		local baseColor = (kind == "folder") and COLORS.folder or COLORS.button
		local hoverColor = (kind == "folder") and COLORS.folderHover or COLORS.buttonHover
		local row = make("TextButton", ui.list, {
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT - 4),
			Position = UDim2.new(0, 0, 0, y),
			Text = "",
			BackgroundColor3 = baseColor,
			AutoButtonColor = false,
			BorderSizePixel = 0,
		})
		make("UICorner", row, { CornerRadius = UDim.new(0, 6) })
		make("TextLabel", row, {
			Size = UDim2.new(1, -16, 1, 0),
			Position = UDim2.new(0, 8, 0, 0),
			Text = text,
			TextColor3 = (kind == "load") and COLORS.accent or COLORS.text,
			TextSize = 15,
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			BackgroundTransparency = 1,
		})
		row.MouseEnter:Connect(function()
			row.BackgroundColor3 = hoverColor
		end)
		row.MouseLeave:Connect(function()
			row.BackgroundColor3 = baseColor
		end)
		row.MouseButton1Click:Connect(onClick)
		y = y + ROW_HEIGHT
	end

	-- On every sub-menu, offer the folder's own Main.lua as the first option
	-- (some categories keep a script at their own level, e.g. Kohls Admin House).
	if #pathParts > 0 then
		local folderName = pathParts[#pathParts]
		addRow(">> Load " .. folderName .. "/Main.lua", "load", function()
			loadScript(pathParts) -- no extra segment: this folder itself
		end)
	end

	for _, item in ipairs(items) do
		if type(item) == "string" then
			-- Leaf: load the script from this folder.
			addRow(item, "leaf", function()
				loadScript(pathPush(pathParts, item))
			end)
		else
			-- Folder: open its sub-menu.
			addRow(item.Label .. "  >", "folder", function()
				navigate(item.Children, pathPush(pathParts, item.Label))
			end)
		end
	end

	-- Resize the scroll canvas to fit the rows.
	ui.list.Size = UDim2.new(1, 0, 0, y)
	ui.scroller.CanvasSize = UDim2.new(0, 0, 0, y)
end

-- Navigation stack: remembers the menus we came from so "Back" can restore
-- them in exact LIFO order. Each entry is {items = ..., path = ...}.
local navStack = {}

local function navigate(items, pathParts)
	table.insert(navStack, { items = items, path = pathParts })
	showMenu(ui, items, pathParts)
end

local function goBack()
	if #navStack == 0 then return end
	local previous = table.remove(navStack)
	showMenu(ui, previous.items, previous.path)
end

-- ============================ Loading scripts ==============================

local busy = false -- guards against double-clicks mid-fetch

local function setStatus(text, color)
	ui.statusLabel.Text = text
	ui.statusLabel.TextColor3 = color or COLORS.dim
end

-- Fetch and execute the script for the given folder path. All failures are
-- turned into friendly status messages, never a raw error stack.
local function loadScript(pathParts)
	if busy then return end
	busy = true

	local rel = table.concat(pathParts, "/")
	local url = scriptUrl(pathParts)

	setStatus("Loading " .. rel .. "/Main.lua ...", COLORS.info)
	local body, reason = fetchUrl(url)

	if not body then
		if reason == "http_404" then
			setStatus("\"Coming soon\" — " .. rel .. " isn't in the repo yet. Check back later!", COLORS.warn)
		else
			setStatus("Could not reach GitHub (" .. tostring(reason) .. "). Check your internet and retry.", COLORS.err)
		end
		warn("[Eternal Club] failed to fetch " .. url .. " (" .. tostring(reason) .. ")")
		busy = false
		return
	end

	setStatus("Executing " .. rel .. " ...", COLORS.info)
	local loader = loadstring or load -- every executor exposes loadstring
	local fn, compileError = loader(body, "=" .. rel .. "/Main.lua")
	if not fn then
		setStatus("Could not compile the script: " .. tostring(compileError), COLORS.err)
		busy = false
		return
	end

	local ok, runError = pcall(fn)
	if not ok then
		setStatus("The script errored at runtime: " .. tostring(runError), COLORS.err)
		busy = false
		return
	end

	setStatus("Done — " .. rel .. " ran successfully.", COLORS.ok)
	busy = false
end

-- ================================ Bootstrap ================================

local ui = buildUI()

ui.closeBtn.MouseButton1Click:Connect(function()
	ui.gui:Destroy()
end)

ui.backBtn.MouseButton1Click:Connect(goBack)

-- Start at the root menu (Games / Universal / Other).
navigate(HUB_TREE, {})

print("[Eternal Club] hub loaded — pick a script from the menu.")
