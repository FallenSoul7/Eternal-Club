--[[===========================================================================
        Eternal Club — Da Hood (original script)
        by FallenSoul7 (Asimboss0078)

        Game:         Da Hood (PlaceId 2788229376)
        Version:      v1
        Form:         ONE self-contained file — zero external loadstrings.
                     Loaded by the Eternal Club hub as
                     Games/Da Hood/Main.lua from raw.githubusercontent.com.

        Feature surface:
          * Silent aim   — closest-to-cursor target pick, FOV circle, hit
                           chance, visible + team checks, target-part list,
                           blacklist / whitelist, Mouse.Hit/Target spoof
                           (__index) AND server-side MouseUpdatedPos spoof
                           (__namecall), BodyEffects.MousePos spoof.
          * Aimlock      — rebindable key, camera-look-at and bezier-mouse
                           modes, configurable prediction + optional gravity.
          * Anti-cheat   — blocks MainEvent teleport-detection flags
                           (TeleportDetect / CHECKER / CHECKER_1 / OneMoreTime),
                           neutralises the 'crash' function, protects
                           WalkSpeed/JumpPower from the game.
          * Character    — anti-ragdoll / anti-fall, name hide, hoodie + face
                           removal, transparency slider, WalkSpeed/JP guard.
          * Anti-fly bypass (toggle).
          * Teleport     — instant and smooth.
          * Farmers      — money (nearby / all-map), shoes, tools, cashier
                           loop with start/stop + live status.
          * ESP          — boxes, health bars, distance, tracers.
          * UI           — lightweight self-made tabs
                           (Combat / Visual / Character / Farm / World / Settings),
                           draggable, closeable, watermark.
          * Keybinds     — rebindable, persisted.
          * Config       — save / load / reset via writefile / readfile.

        All game facts used are hard-coded from the Da Hood map:
          ReplicatedStorage.MainEvent, Workspace.Cashiers,
          Workspace.Ignored.Drop, Workspace.Ignored.ItemsDrop,
          BodyEffects.MousePos, BodyEffects.Movement, RagdollConstraints,
          GunScript.
=============================================================================]]

local VERSION = "v1"

--===========================================================================
-- 1. SERVICES
--===========================================================================
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")

--===========================================================================
-- 2. PLACE GUARD
--===========================================================================
if game.PlaceId ~= 2788229376 then
    warn("Eternal Club — Da Hood: wrong PlaceId " .. tostring(game.PlaceId)
        .. " (expected 2788229376). Script not loading.")
    return
end

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character
local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
local Backpack = LocalPlayer:FindFirstChild("Backpack") or LocalPlayer:WaitForChild("Backpack")
local Mouse = LocalPlayer:GetMouse()
local MainEvent = ReplicatedStorage:WaitForChild("MainEvent", 15)
local GunScript = ReplicatedStorage:FindFirstChild("GunScript") -- game fact (gun system)

--===========================================================================
-- 3. EXECUTOR COMPAT LAYER (guarded; the script degrades gracefully)
--===========================================================================
local Compat = {}
do
    local function grab(name)
        local ok, v = pcall(function() return rawget(_G, name) end)
        return ok and v or nil
    end
    Compat.hookmetamethod = grab("hookmetamethod")
    Compat.getrawmetatable = grab("getrawmetatable")
    Compat.setreadonly = grab("setreadonly")
    Compat.checkcaller = grab("checkcaller")
    Compat.getnamecallmethod = grab("getnamecallmethod")
    Compat.newcclosure = grab("newcclosure")
    Compat.getgc = grab("getgc")
    Compat.getfenv = grab("getfenv")
    Compat.setfenv = grab("setfenv")
    Compat.getinfo = (grab("debug") or {}).getinfo
    Compat.fireclickdetector = grab("fireclickdetector")
    Compat.getgenv = grab("getgenv")
    Compat.writefile = grab("writefile")
    Compat.readfile = grab("readfile")
    Compat.isfile = grab("isfile")
    Compat.makefolder = grab("makefolder")
    Compat.isfolder = grab("isfolder")
    Compat.mousemoverel = grab("mousemoverel")
end

local Drawing = rawget(_G, "Drawing") -- executor drawing API (ESP + FOV circle)
local HasDraw = Drawing ~= nil

local function IsCaller()
    return Compat.checkcaller and Compat.checkcaller() or false
end

local function Contains(t, v)
    for i = 1, #t do
        if t[i] == v then return true end
    end
    return false
end

--===========================================================================
-- 4. DEFAULT SETTINGS (single source of truth; persisted to disk)
--===========================================================================
local DEFAULT_SETTINGS = {
    silentAim = {
        enabled = false,       -- master switch
        prediction = 0.15,     -- seconds of lead
        fov = 12,              -- degrees (cone from camera look)
        showFov = false,       -- draw FOV circle
        hitChance = 100,       -- %
        teamCheck = true,
        visibleCheck = true,
        whitelistOnly = false,
        blacklist = {},        -- userIds
        whitelist = {},        -- userIds
        targetParts = { "Head", "HumanoidRootPart" },
        spoofMousePos = true,  -- BodyEffects.MousePos spoof
    },
    aimlock = {
        enabled = false,
        mode = "camera",       -- "camera" | "mouse"
        prediction = 0.15,
        gravityPrediction = false,
    },
    character = {
        antiRagdoll = true,
        antiFall = true,
        hideName = true,
        removeHoodie = true,
        removeFace = true,
        protectWalkSpeed = true,
        transparency = 0,
    },
    world = {
        antiFly = false,
        teleportSmooth = false,
    },
    farm = {
        moneyNearby = false,
        moneyAll = false,
        shoes = false,
        tools = false,
        cashiers = false,
        tpBack = true,
    },
    esp = {
        enabled = true,
        boxes = true,
        health = true,
        distance = true,
        tracers = false,
        teamColors = true,
    },
    keybinds = {
        aimlock = "Q",
        ui = "RightShift",
        farm = "F6",
    },
}

local Settings = {}
local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = DeepCopy(v) end
    return out
end
Settings = DeepCopy(DEFAULT_SETTINGS)

if Compat.getgenv then
    local g = Compat.getgenv()
    g.EternalClubDaHood = Settings -- visible for debugging
    g.BypassFlyDaHood = false      -- legacy flag kept for compatibility
end

--===========================================================================
-- 5. MINIMAL JSON (encode + decode) — original, no dependencies
--===========================================================================
local Json = {}

local function JStr(s)
    local out = {}
    for i = 1, #s do
        local c = s:sub(i, i)
        local b = c:byte()
        if c == '"' then
            out[#out + 1] = '\\"'
        elseif c == "\\" then
            out[#out + 1] = "\\\\"
        elseif b == 10 then
            out[#out + 1] = "\\n"
        elseif b == 13 then
            out[#out + 1] = "\\r"
        elseif b == 9 then
            out[#out + 1] = "\\t"
        elseif b and b < 32 then
            out[#out + 1] = string.format("\\u%04x", b)
        else
            out[#out + 1] = c
        end
    end
    return '"' .. table.concat(out) .. '"'
end

function Json.Encode(v)
    local t = type(v)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return v and "true" or "false"
    elseif t == "number" then
        return string.format("%.10g", v)
    elseif t == "string" then
        return JStr(v)
    elseif t == "table" then
        local parts = {}
        local count = 0
        for k, val in pairs(v) do
            if type(k) == "string" then
                count = count + 1
                parts[count] = JStr(k) .. ":" .. Json.Encode(val)
            end
        end
        if count == 0 then return "{}" end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

local function SkipWs(s, i)
    while i <= #s and (s:sub(i, i) == " " or s:sub(i, i) == "\n"
        or s:sub(i, i) == "\r" or s:sub(i, i) == "\t") do
        i = i + 1
    end
    return i
end

local function DecodeStr(s, i)
    -- s[i] == '"'
    i = i + 1
    local out = {}
    while i <= #s do
        local c = s:sub(i, i)
        if c == '"' then
            return table.concat(out), i + 1
        elseif c == "\\" then
            local n = s:sub(i + 1, i + 1)
            if n == "n" then out[#out + 1] = "\n"
            elseif n == "t" then out[#out + 1] = "\t"
            elseif n == "r" then out[#out + 1] = "\r"
            elseif n == "u" then
                local hx = s:sub(i + 2, i + 5)
                local ok, num = pcall(tonumber, hx, 16)
                out[#out + 1] = ok and string.char(num) or "?"
                i = i + 4
            else
                out[#out + 1] = n
            end
            i = i + 2
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out), i
end

local DecodeValue -- forward decl

local function DecodeArr(s, i)
    -- s[i] == '['
    local arr, done = {}, false
    i = SkipWs(s, i + 1)
    if s:sub(i, i) == "]" then return arr, i + 1 end
    while not done do
        local v
        v, i = DecodeValue(s, i)
        arr[#arr + 1] = v
        i = SkipWs(s, i)
        local c = s:sub(i, i)
        if c == "," then
            i = SkipWs(s, i + 1)
        elseif c == "]" then
            done = true
            i = i + 1
        else
            done = true
        end
    end
    return arr, i
end

local function DecodeObj(s, i)
    -- s[i] == '{'
    local obj, done = {}, false
    i = SkipWs(s, i + 1)
    if s:sub(i, i) == "}" then return obj, i + 1 end
    while not done do
        local key
        key, i = DecodeStr(s, i)
        i = SkipWs(s, i)
        if s:sub(i, i) == ":" then i = SkipWs(s, i + 1) end
        local v
        v, i = DecodeValue(s, i)
        obj[key] = v
        i = SkipWs(s, i)
        local c = s:sub(i, i)
        if c == "," then
            i = SkipWs(s, i + 1)
        elseif c == "}" then
            done = true
            i = i + 1
        else
            done = true
        end
    end
    return obj, i
end

function DecodeValue(s, i)
    i = SkipWs(s, i)
    local c = s:sub(i, i)
    if c == "{" then return DecodeObj(s, i) end
    if c == "[" then return DecodeArr(s, i) end
    if c == '"' then return DecodeStr(s, i) end
    if c == "t" then return true, i + 4 end
    if c == "f" then return false, i + 5 end
    if c == "n" then return nil, i + 4 end
    -- number
    local numStr = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    if numStr and #numStr > 0 then
        return tonumber(numStr), i + #numStr
    end
    return nil, i + 1
end

function Json.Decode(s)
    local ok, v, i = pcall(DecodeValue, s, 1)
    if ok and v ~= nil then return v end
    return nil
end

--===========================================================================
-- 6. ON-SCREEN LOG / STATUS
--===========================================================================
local LogLines = {}
local LogLabel = nil -- attached to UI when built
local function Log(msg, isErr)
    local line = tostring(msg)
    if isErr then line = "[!] " .. line end
    table.insert(LogLines, line)
    if #LogLines > 6 then table.remove(LogLines, 1) end
    if LogLabel then LogLabel.Text = table.concat(LogLines, "\n") end
end

--===========================================================================
-- 7. CONFIG SAVE / LOAD (writefile / readfile)
--===========================================================================
local CONFIG_FOLDER = "EternalClub/DaHood"
local CONFIG_FILE = CONFIG_FOLDER .. "/config.json"

local function SaveConfig()
    if not Compat.writefile then return end
    local ok = pcall(function()
        if Compat.makefolder and not (Compat.isfolder and Compat.isfolder(CONFIG_FOLDER)) then
            Compat.makefolder(CONFIG_FOLDER)
        end
        Compat.writefile(CONFIG_FILE, Json.Encode(Settings))
    end)
    if not ok then
        Log("Config save failed (writefile unavailable?)", true)
    end
end

local function MergeSettings(loaded)
    if type(loaded) ~= "table" then return end
    for k, v in pairs(loaded) do
        if type(Settings[k]) == "table" and type(v) == "table" then
            for k2, v2 in pairs(v) do
                Settings[k][k2] = v2
            end
        elseif Settings[k] ~= nil then
            Settings[k] = v
        end
    end
    -- sanitize keybinds
    for name, key in pairs(Settings.keybinds) do
        if type(key) ~= "string" then Settings.keybinds[name] = nil end
    end
    if type(Settings.silentAim.targetParts) ~= "table" or #Settings.silentAim.targetParts == 0 then
        Settings.silentAim.targetParts = { "Head", "HumanoidRootPart" }
    end
end

local function LoadConfig()
    if not (Compat.readfile and Compat.isfile) then return end
    local okFile, exists = pcall(Compat.isfile, CONFIG_FILE)
    if okFile and exists then
        local okRead, data = pcall(Compat.readfile, CONFIG_FILE)
        if okRead and type(data) == "string" and #data > 0 then
            local okDec, decoded = pcall(Json.Decode, data)
            if okDec and type(decoded) == "table" then
                MergeSettings(decoded)
                Log("Config loaded")
            else
                Log("Config corrupt — using defaults", true)
            end
        end
    end
end

--===========================================================================
-- 8. HELPERS
--===========================================================================
local function GetCharacter()
    return LocalPlayer.Character
end

local function InstancePos(inst)
    if inst and (inst:IsA("BasePart") or inst:IsA("Model") or inst:IsA("PVInstance")) then
        return inst:GetPivot().Position
    end
    return Vector3.new()
end

local function GetTargetPart(char, names)
    for i = 1, #names do
        local part = char:FindFirstChild(names[i])
        if part then return part end
    end
    return char:FindFirstChild("HumanoidRootPart")
end

--===========================================================================
-- 9. AIM CORE (pure logic; used by silent aim + aimlock + hooks)
--===========================================================================
local Aim = {
    Selected = nil,   -- { Player, Character, Part, Visible }
    HitOk = false,
    LastScan = 0,
    TARGET_PART_CYCLE = {
        "Head", "HumanoidRootPart", "Torso", "UpperTorso", "LowerTorso",
        "LeftFoot", "RightFoot", "LeftHand", "RightHand",
    },
}

local function FovRadiusPx()
    local cam = Workspace.CurrentCamera
    if not cam then return 100 end
    local vp = cam.ViewportSize
    local tanHalf = math.tan(math.rad(cam.FieldOfView / 2))
    if tanHalf < 0.01 then return 100 end
    return (vp.Y / 2 / tanHalf) * math.tan(math.rad(Settings.silentAim.fov))
end

local function IsPartVisible(fromPos, part, targetChar)
    local myChar = GetCharacter()
    local params = RaycastParams.new()
    if myChar then
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = { myChar }
    end
    local dir = part.Position - fromPos
    if dir.Magnitude < 1 then return true end
    local result = Workspace:Raycast(fromPos, dir, params)
    if not result then return true end
    local inst = result.Instance
    if inst and targetChar then
        return inst:IsDescendantOf(targetChar)
    end
    return true
end

local function PredictedPos(part, prediction, useGravity)
    local pos = part.Position
    local vel = part.Velocity or Vector3.new()
    if vel then pos = pos + vel * prediction end
    if useGravity and Workspace.Gravity and Workspace.Gravity > 0 then
        pos = pos + Vector3.new(0, -0.5 * Workspace.Gravity * prediction * prediction, 0)
    end
    return pos
end

function Aim:Scan()
    Aim.Selected = nil
    local cam = Workspace.CurrentCamera
    local myChar = GetCharacter()
    if not cam or not myChar then return end
    local camPos = cam.CFrame.Position
    local camLook = cam.CFrame.LookVector
    local mousePos = UserInputService:GetMouseLocation()

    local fovDeg = Settings.silentAim.fov
    local teamCheck = Settings.silentAim.teamCheck
    local visibleCheck = Settings.silentAim.visibleCheck
    local whitelistOnly = Settings.silentAim.whitelistOnly
    local whitelist, blacklist = Settings.silentAim.whitelist, Settings.silentAim.blacklist
    local parts = Settings.silentAim.targetParts

    local bestPart, bestPlayer, bestDist = nil, nil, math.huge

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            -- team check (guarded: Da Hood usually has no teams)
            if teamCheck and p.Team and LocalPlayer.Team and p.Team == LocalPlayer.Team then
                -- teammate, skip
            elseif whitelistOnly then
                if Contains(whitelist, p.UserId) then
                    local part = GetTargetPart(p.Character, parts)
                    if part then
                        local screenPos, onScreen = cam:WorldToViewportPoint(part.Position)
                        if onScreen then
                            local delta = Vector2.new(screenPos.X, screenPos.Y) - mousePos
                            local px = delta.Magnitude
                            local dir = part.Position - camPos
                            local len = dir.Magnitude
                            if len > 0.5 and px < bestDist then
                                local dot = camLook:Dot(dir / len)
                                local ang = math.deg(math.acos(math.max(-1, math.min(1, dot))))
                                if ang <= fovDeg then
                                    local hum = p.Character:FindFirstChildOfClass("Humanoid")
                                    if hum and hum.Health > 0 then
                                        bestDist = px
                                        bestPart = part
                                        bestPlayer = p
                                    end
                                end
                            end
                        end
                    end
                end
            elseif not Contains(blacklist, p.UserId) then
                local part = GetTargetPart(p.Character, parts)
                if part then
                    local screenPos, onScreen = cam:WorldToViewportPoint(part.Position)
                    if onScreen then
                        local delta = Vector2.new(screenPos.X, screenPos.Y) - mousePos
                        local px = delta.Magnitude
                        local dir = part.Position - camPos
                        local len = dir.Magnitude
                        if len > 0.5 and px < bestDist then
                            local dot = camLook:Dot(dir / len)
                            local ang = math.deg(math.acos(math.max(-1, math.min(1, dot))))
                            if ang <= fovDeg then
                                local hum = p.Character:FindFirstChildOfClass("Humanoid")
                                if hum and hum.Health > 0 then
                                    bestDist = px
                                    bestPart = part
                                    bestPlayer = p
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if bestPart and bestPlayer then
        local vis = true
        if visibleCheck then
            vis = IsPartVisible(camPos, bestPart, bestPlayer.Character)
        end
        Aim.Selected = {
            Player = bestPlayer,
            Character = bestPlayer.Character,
            Part = bestPart,
            Visible = vis,
        }
    end
    Aim.HitOk = math.random(1, 100) <= Settings.silentAim.hitChance
    Aim.LastScan = os.clock()
end

function Aim:ScanIfStale()
    if os.clock() - Aim.LastScan > 0.05 then
        Aim:Scan()
    end
end

local function ShouldSpoof()
    if not Settings.silentAim.enabled then return false end
    local t = Aim.Selected
    if not t or not t.Part then return false end
    if not Aim.HitOk then return false end
    if Settings.silentAim.visibleCheck and not t.Visible then return false end
    return true
end

--===========================================================================
-- 10. METAMETHOD HOOKS (installed once; every hook is pcall-guarded)
--===========================================================================
local oldIndexHook, oldNamecallHook, oldNewindexHook
local HooksInstalled = false

-- Unified list of server teleport-detection flags to block on MainEvent.
local ANTI_TELEPORT_FLAGS = {
    TeleportDetect = true,
    CHECKER = true,
    CHECKER_1 = true,
    OneMoreTime = true,
}

local function HookIndex(t, k)
    local ok, spoof, value = pcall(function()
        if not IsCaller() and t == Mouse and (k == "Hit" or k == "Target") then
            Aim:ScanIfStale()
            if ShouldSpoof() and Aim.Selected and Aim.Selected.Part then
                if k == "Hit" then
                    local pos = PredictedPos(Aim.Selected.Part, Settings.silentAim.prediction, false)
                    return true, CFrame.new(pos)
                end
                return true, Aim.Selected.Part
            end
        end
        return false, nil
    end)
    if ok and spoof then return value end
    return oldIndexHook(t, k)
end

local function HookNamecall(...)
    local args = {...}
    local ok, spoof, value = pcall(function()
        if not IsCaller() then
            local method = Compat.getnamecallmethod and Compat.getnamecallmethod() or ""
            if method == "FireServer" then
                local selfObj = args[1]
                local flag = args[2]
                if selfObj == MainEvent and type(flag) == "string" then
                    if ANTI_TELEPORT_FLAGS[flag] then
                        return true, nil -- swallow teleport-detection flag
                    end
                    if flag == "MouseUpdatedPos" and typeof(args[3]) == "Vector3" then
                        Aim:ScanIfStale()
                        if ShouldSpoof() and Aim.Selected and Aim.Selected.Part then
                            -- server-side aim: report the target head instead
                            return true, PredictedPos(Aim.Selected.Part, Settings.silentAim.prediction, false)
                        end
                    end
                end
            end
        end
        return false, nil
    end)
    if ok and spoof then return value end

    -- best-effort: neutralise the game's 'crash' function in the caller's env
    if not IsCaller() and Compat.getfenv then
        local okF, fenv = pcall(Compat.getfenv, 2)
        if okF and type(fenv) == "table" and type(fenv.crash) == "function" then
            pcall(function()
                fenv.crash = function() end
                if Compat.setfenv then Compat.setfenv(2, fenv) end
            end)
        end
    end
    return oldNamecallHook(...)
end

local function HookNewindex(t, k, v)
    local ok, spoof = pcall(function()
        if not IsCaller() and Settings.character.protectWalkSpeed
            and typeof(t) == "Instance" and t:IsA("Humanoid")
            and (k == "WalkSpeed" or k == "JumpPower") then
            return true -- block the game from changing our WalkSpeed/JumpPower
        end
        return false
    end)
    if ok and spoof then return end
    return oldNewindexHook(t, k, v)
end

local function InstallHooks()
    if HooksInstalled then return end
    HooksInstalled = true
    local ok = pcall(function()
        if Compat.hookmetamethod then
            oldIndexHook = Compat.hookmetamethod(game, "__index", HookIndex)
            oldNamecallHook = Compat.hookmetamethod(game, "__namecall", HookNamecall)
            oldNewindexHook = Compat.hookmetamethod(game, "__newindex", HookNewindex)
        else
            local mt = Compat.getrawmetatable and Compat.getrawmetatable(game)
            if not mt then error("no raw metatable") end
            if Compat.setreadonly then Compat.setreadonly(mt, false) end
            oldIndexHook, oldNamecallHook, oldNewindexHook = mt.__index, mt.__namecall, mt.__newindex
            mt.__index, mt.__namecall, mt.__newindex = HookIndex, HookNamecall, HookNewindex
        end
    end)
    if not ok then
        Log("Metamethod hooks failed — silent aim / AC bypass disabled", true)
    end
end

--===========================================================================
-- 11. CHARACTER PROTECTIONS (re-applied cleanly on every respawn)
--===========================================================================
local MovementHooked = {} -- per-instance guard so the hook is bound once

local function ApplyTransparency()
    local char = GetCharacter()
    if not char then return end
    local t = Settings.character.transparency
    pcall(function()
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") then
                d.Transparency = t
            end
        end
    end)
end

local function ApplyProtections()
    local char = GetCharacter()
    if not char then return end
    local ok, err = pcall(function()
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            if Settings.character.antiFall then
                hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
            end
            if Settings.character.antiRagdoll then
                hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            end
            if Settings.character.hideName then
                hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            end
        end

        local ragdoll = char:FindFirstChild("RagdollConstraints")
        if ragdoll then
            for _, c in ipairs(ragdoll:GetChildren()) do
                pcall(function() c.Enabled = false end)
            end
        end

        if Settings.character.removeHoodie or Settings.character.removeFace then
            for _, d in ipairs(char:GetDescendants()) do
                pcall(function()
                    if Settings.character.removeHoodie and d:IsA("Accessory") then
                        d:Destroy()
                    elseif Settings.character.removeFace and d:IsA("Decal") and d.Name:lower() == "face" then
                        d:Destroy()
                    elseif Settings.character.removeHoodie and d:IsA("MeshPart") then
                        d.Color = Color3.fromRGB(255, 255, 255)
                    end
                end)
            end
        end

        -- BodyEffects.Movement: destroy anything the game spawns inside it
        local be = char:FindFirstChild("BodyEffects")
        if be then
            local mov = be:FindFirstChild("Movement")
            if mov and not MovementHooked[mov] then
                MovementHooked[mov] = true
                mov.DescendantAdded:Connect(function(desc)
                    task.wait()
                    pcall(function() desc:Destroy() end)
                end)
            end
        end
    end)
    if not ok then
        Log("Character protection error: " .. tostring(err), true)
    end
    ApplyTransparency()
end

local function OnCharacterAdded(char)
    Character = char
    Humanoid = char:WaitForChild("Humanoid", 10)
    HumanoidRootPart = char:WaitForChild("HumanoidRootPart", 10)
    task.wait()
    ApplyProtections()
end

--===========================================================================
-- 12. TELEPORT (instant + smooth)
--===========================================================================
local TeleportBusy = false

local function TeleportTo(cf, smooth)
    if not cf then return false end
    local char = GetCharacter()
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    if not smooth then
        local ok = pcall(function() hrp.CFrame = cf end)
        return ok
    end

    if TeleportBusy then return false end
    TeleportBusy = true
    task.spawn(function()
        local ok = pcall(function()
            local startCF = hrp.CFrame
            for i = 1, 10 do
                if not hrp or not hrp.Parent then break end
                hrp.CFrame = startCF:Lerp(cf, i / 10)
                task.wait()
            end
            if hrp and hrp.Parent then hrp.CFrame = cf end
        end)
        TeleportBusy = false
    end)
    return true
end

--===========================================================================
-- 13. ANTI-FLY BYPASS
--===========================================================================
local AntiFlyWarned = false
local function AntiFlyLoop()
    while true do
        task.wait(0.1)
        if Settings.world.antiFly then
            local ok = pcall(function()
                if Compat.getgc then
                    for _, obj in ipairs(Compat.getgc()) do
                        if type(obj) == "function" then
                            local info = nil
                            if Compat.getinfo then
                                local okI, i2 = pcall(Compat.getinfo, obj)
                                if okI then info = i2 end
                            end
                            if info and info.name == "crash" then
                                local fenv = Compat.getfenv and Compat.getfenv(obj)
                                if fenv and fenv.script then
                                    pcall(function() fenv.script:Destroy() end)
                                end
                            end
                        end
                    end
                elseif not AntiFlyWarned then
                    AntiFlyWarned = true
                    Log("getgc unavailable — anti-fly bypass limited", true)
                end
            end)
        end
    end
end

--===========================================================================
-- 14. FARMERS
--===========================================================================
local Farm = {
    Running = false,
    Status = "Idle",
}

local function GetDrop()
    local ok, ignored = pcall(function()
        return Workspace:WaitForChild("Ignored", 10)
    end)
    if not ok or not ignored then return nil end
    local ok2, drop = pcall(function()
        return ignored:WaitForChild("Drop", 10)
    end)
    return ok2 and drop or nil
end

local function GetItemsDrop()
    local ok, ignored = pcall(function()
        return Workspace:WaitForChild("Ignored", 10)
    end)
    if not ok or not ignored then return nil end
    local ok2, idrop = pcall(function()
        return ignored:WaitForChild("ItemsDrop", 10)
    end)
    return ok2 and idrop or nil
end

local function CollectMoney(nearby, tpBack)
    local drop = GetDrop()
    if not drop then
        Log("Drop folder not found — money farm failed", true)
        return 0
    end
    local hrp = GetCharacter() and GetCharacter():FindFirstChild("HumanoidRootPart")
    local saved = hrp and hrp.CFrame
    local count = 0
    for _, v in ipairs(drop:GetDescendants()) do
        if v:IsA("ClickDetector") then
            local par = v.Parent
            if par and par.Name == "MoneyDrop" then
                local dist = hrp and (InstancePos(par) - hrp.Position).Magnitude or 0
                if (not nearby) or dist <= 20 then
                    if hrp then
                        pcall(function() hrp.CFrame = par:GetPivot() end)
                    end
                    task.wait(0.2)
                    if Compat.fireclickdetector then
                        pcall(Compat.fireclickdetector, v, 0)
                    end
                    count = count + 1
                    task.wait(0.2)
                end
            end
        end
    end
    if tpBack and saved and hrp then
        task.wait(1)
        TeleportTo(saved, Settings.world.teleportSmooth)
    end
    return count
end

local function CollectShoes(tpBack)
    local drop = GetDrop()
    if not drop then
        Log("Drop folder not found — shoe farm failed", true)
        return 0
    end
    local hrp = GetCharacter() and GetCharacter():FindFirstChild("HumanoidRootPart")
    local saved = hrp and hrp.CFrame
    local count = 0
    for _, v in ipairs(drop:GetDescendants()) do
        if v:IsA("ClickDetector") then
            local par = v.Parent
            if par and (par.Name == "MeshPart" or par:IsA("MeshPart")) then
                if hrp then
                    pcall(function() hrp.CFrame = par:GetPivot() end)
                end
                task.wait(0.5)
                if Compat.fireclickdetector then
                    pcall(Compat.fireclickdetector, v, 0)
                end
                count = count + 1
                task.wait(1)
            end
        end
    end
    if tpBack and saved and hrp then
        task.wait(1)
        TeleportTo(saved, Settings.world.teleportSmooth)
    end
    return count
end

local function CollectTools(tpBack)
    local idrop = GetItemsDrop()
    if not idrop then
        Log("ItemsDrop folder not found — tool farm failed", true)
        return 0
    end
    local hrp = GetCharacter() and GetCharacter():FindFirstChild("HumanoidRootPart")
    local saved = hrp and hrp.CFrame
    local count = 0
    for _, v in ipairs(idrop:GetDescendants()) do
        if v:IsA("Tool") then
            local hasTouch = false
            for _, d in ipairs(v:GetDescendants()) do
                if d:IsA("TouchTransmitter") then
                    hasTouch = true
                    break
                end
            end
            if hasTouch and hrp then
                pcall(function() hrp.CFrame = v:GetPivot() end)
                task.wait(0.5)
                count = count + 1
            end
        end
    end
    if tpBack and saved and hrp then
        task.wait(1)
        TeleportTo(saved, Settings.world.teleportSmooth)
    end
    return count
end

-- Cashier loop: start/stop driven from the Farm tab (and the farm hotkey).
local function CashierLoop()
    Farm.Running = true
    Farm.Status = "Cashier farm: starting"
    while Farm.Running do
        local ok, err = pcall(function()
            local cashiers = Workspace:WaitForChild("Cashiers", 10)
            if not cashiers then error("Cashiers folder missing") end
            local hrp = GetCharacter() and GetCharacter():FindFirstChild("HumanoidRootPart")
            local saved = hrp and hrp.CFrame
            for i, v in ipairs(cashiers:GetChildren()) do
                if not Farm.Running then return end
                local hum = v:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    -- loot position is derived per cashier (upstream left it undefined)
                    local lootPos = v:FindFirstChild("HumanoidRootPart")
                        and v.HumanoidRootPart.CFrame or v:GetPivot()
                    Farm.Status = "Cashier " .. i .. ": teleporting"
                    if hrp then
                        pcall(function() hrp.CFrame = lootPos end)
                    end
                    task.wait(0.3)
                    local combat = Backpack:FindFirstChild("Combat")
                    if combat then
                        pcall(function() hum:EquipTool(combat) end)
                    end
                    Farm.Status = "Cashier " .. i .. ": attacking"
                    local started = os.clock()
                    while hum.Health > 0 and Farm.Running and (os.clock() - started) < 20 do
                        pcall(function() VirtualUser:ClickButton1(Vector2.new()) end)
                        task.wait(0.05)
                    end
                    for _ = 1, 3 do
                        if not Farm.Running then return end
                        CollectMoney(true, false)
                        if hrp then
                            pcall(function() hrp.CFrame = lootPos end)
                        end
                        task.wait(1)
                    end
                end
            end
            if saved and hrp then
                task.wait(1)
                pcall(function() hrp.CFrame = saved end)
            end
        end)
        if not ok then
            Farm.Status = "Cashier farm: error, retrying"
            Log("Cashier farm error: " .. tostring(err), true)
            task.wait(2)
        elseif Farm.Running then
            task.wait(1)
        end
    end
    Farm.Status = "Stopped"
end

local function RunFarmJob(name, fn)
    Farm.Status = "Running: " .. name
    local ok, err = pcall(fn)
    if not ok then
        Farm.Status = "Error: " .. name
        Log(name .. " farm error: " .. tostring(err), true)
    else
        Farm.Status = "Done: " .. name
        Log(name .. " farm complete")
    end
end

local function ToggleCashiers(on)
    if on then
        if not Farm.Running then
            task.spawn(CashierLoop)
        end
    else
        Farm.Running = false
        Farm.Status = "Stopped"
    end
end

--===========================================================================
-- 15. ESP (boxes / health / distance / tracers) — missing upstream, added
--===========================================================================
local ESP = { Cache = {} }

local function ESPMake(player)
    local s = { box = {} }
    if not HasDraw then return s end
    for _ = 1, 4 do
        local l = Drawing.new("Line")
        l.Thickness = 1
        s.box[#s.box + 1] = l
    end
    s.healthBg = Drawing.new("Line")
    s.healthBg.Thickness = 3
    s.healthFill = Drawing.new("Line")
    s.healthFill.Thickness = 3
    s.dist = Drawing.new("Text")
    s.dist.Size = 13
    s.dist.Center = true
    s.dist.Outline = true
    s.tracer = Drawing.new("Line")
    s.tracer.Thickness = 1
    return s
end

local function ESPHide(s)
    if not s then return end
    for _, l in ipairs(s.box) do l.Visible = false end
    if s.healthBg then s.healthBg.Visible = false end
    if s.healthFill then s.healthFill.Visible = false end
    if s.dist then s.dist.Visible = false end
    if s.tracer then s.tracer.Visible = false end
end

local function ESPRemove(s)
    if not s then return end
    pcall(function()
        for _, l in ipairs(s.box) do l:Remove() end
        if s.healthBg then s.healthBg:Remove() end
        if s.healthFill then s.healthFill:Remove() end
        if s.dist then s.dist:Remove() end
        if s.tracer then s.tracer:Remove() end
    end)
end

local function ESPUpdate()
    if not (Settings.esp.enabled and HasDraw) then
        for _, s in pairs(ESP.Cache) do ESPHide(s) end
        return
    end
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local vp = cam.ViewportSize
    local myChar = GetCharacter()
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")

    for _, p in ipairs(Players:GetPlayers()) do
        local s = ESP.Cache[p]
        if not s then s = ESPMake(p); ESP.Cache[p] = s end
        local char = p.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local head = char and char:FindFirstChild("Head")
        local show = char and hum and root and hum.Health > 0
        if not show then
            ESPHide(s)
        else
            local headPos = head and head.Position or root.Position
            local topS, topOn = cam:WorldToViewportPoint(headPos + Vector3.new(0, 0.6, 0))
            local botS, botOn = cam:WorldToViewportPoint(root.Position - Vector3.new(0, 2.6, 0))
            if not (topOn or botOn) then
                ESPHide(s)
            else
                local h = math.abs(topS.Y - botS.Y)
                local w = h * 0.55
                local tl = Vector2.new(topS.X - w / 2, topS.Y)
                local tr = Vector2.new(topS.X + w / 2, topS.Y)
                local bl = Vector2.new(topS.X - w / 2, botS.Y)
                local br = Vector2.new(topS.X + w / 2, botS.Y)
                local color = Color3.fromRGB(255, 80, 80)
                if Settings.esp.teamColors and p.TeamColor and p.TeamColor.Color then
                    color = p.TeamColor.Color
                end

                local showBox = Settings.esp.boxes
                s.box[1].From = tl; s.box[1].To = tr; s.box[1].Color = color; s.box[1].Visible = showBox
                s.box[2].From = tr; s.box[2].To = br; s.box[2].Color = color; s.box[2].Visible = showBox
                s.box[3].From = br; s.box[3].To = bl; s.box[3].Color = color; s.box[3].Visible = showBox
                s.box[4].From = bl; s.box[4].To = tl; s.box[4].Color = color; s.box[4].Visible = showBox

                local showHealth = Settings.esp.health
                local hp = math.max(0, hum.Health) / math.max(1, hum.MaxHealth)
                local hx = tl.X - 5
                s.healthBg.From = Vector2.new(hx, tl.Y)
                s.healthBg.To = Vector2.new(hx, bl.Y)
                s.healthBg.Color = Color3.fromRGB(30, 30, 30)
                s.healthBg.Visible = showHealth
                local fillY = bl.Y - (bl.Y - tl.Y) * hp
                s.healthFill.From = Vector2.new(hx, bl.Y)
                s.healthFill.To = Vector2.new(hx, fillY)
                s.healthFill.Visible = showHealth
                s.healthFill.Color = hp > 0.5 and Color3.fromRGB(80, 255, 80)
                    or (hp > 0.25 and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(255, 60, 60))

                local dist = myRoot and (myRoot.Position - root.Position).Magnitude or 0
                s.dist.Text = string.format("%d%% | %.0fm", math.floor(hp * 100 + 0.5), dist)
                s.dist.Position = Vector2.new(tl.X + w / 2, bl.Y + 2)
                s.dist.Color = color
                s.dist.Visible = Settings.esp.distance

                s.tracer.From = Vector2.new(vp.X / 2, vp.Y)
                s.tracer.To = Vector2.new(topS.X, topS.Y + h / 2)
                s.tracer.Color = color
                s.tracer.Visible = Settings.esp.tracers
            end
        end
    end
end

local function ESPOnPlayerAdded(p)
    if HasDraw then
        ESP.Cache[p] = ESPMake(p)
    end
end

local function ESPOnPlayerRemoving(p)
    local s = ESP.Cache[p]
    ESPRemove(s)
    ESP.Cache[p] = nil
end

--===========================================================================
-- 16. AIMLOCK (camera-look-at + bezier-mouse modes)
--===========================================================================
local BezierActive = nil
local MouseModeWarned = false

local function ApplyAimlock()
    if not Settings.aimlock.enabled then return end
    local t = Aim.Selected
    if not t or not t.Part then return end
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local pos = PredictedPos(t.Part, Settings.aimlock.prediction, Settings.aimlock.gravityPrediction)

    if Settings.aimlock.mode == "camera" then
        cam.CFrame = CFrame.lookAt(cam.CFrame.Position, pos)
    else
        if not Compat.mousemoverel then
            if not MouseModeWarned then
                MouseModeWarned = true
                Log("mousemoverel unavailable — mouse mode falls back to camera", true)
            end
            cam.CFrame = CFrame.lookAt(cam.CFrame.Position, pos)
            return
        end
        local screenPos, onScreen = cam:WorldToViewportPoint(pos)
        if not onScreen then return end
        local from = UserInputService:GetMouseLocation()
        BezierActive = {
            from = from,
            control = Vector2.new((from.X + screenPos.X) / 2, math.min(from.Y, screenPos.Y) - 60),
            to = Vector2.new(screenPos.X, screenPos.Y),
            t = 0,
            last = from,
        }
    end
end

local function BezierStep(dt)
    local b = BezierActive
    if not b then return end
    b.t = math.min(1, b.t + dt / 0.12)
    local t = b.t
    local mt = 1 - t
    local p = mt * mt * b.from + 2 * mt * t * b.control + t * t * b.to
    if Compat.mousemoverel then
        pcall(Compat.mousemoverel, p - b.last)
    end
    b.last = p
    if t >= 1 then BezierActive = nil end
end

-- BodyEffects.MousePos spoof: server-side aim assist while holding a gun.
local function SpoofMousePos()
    local t = Aim.Selected
    if not t or not t.Part then return end
    local char = GetCharacter()
    if not char then return end
    if not char:FindFirstChildOfClass("Tool") then return end
    local be = char:FindFirstChild("BodyEffects")
    if not be then return end
    local mv = be:FindFirstChild("MousePos")
    if mv then
        pcall(function() mv.Value = PredictedPos(t.Part, Settings.silentAim.prediction, false) end)
    end
end

-- FOV circle (Drawing)
local FovCircle = nil
if HasDraw then
    pcall(function()
        FovCircle = Drawing.new("Circle")
        FovCircle.Thickness = 1
        FovCircle.NumSides = 64
        FovCircle.Color = Color3.fromRGB(255, 255, 255)
        FovCircle.Transparency = 0.6
        FovCircle.Visible = false
    end)
end

--===========================================================================
-- 17. UI (self-made, lightweight — no external UI library)
--===========================================================================
local UI = { Built = false }
local RefreshFns = {}
local function AddRefresh(fn)
    RefreshFns[#RefreshFns + 1] = fn
end
local function RefreshAll()
    for i = 1, #RefreshFns do
        pcall(RefreshFns[i])
    end
end
UI.RefreshAll = RefreshAll

local UIContainer = nil
local FarmStatusLabel = nil
local Listening = nil -- keybind currently being rebound

local C = {
    bg = Color3.fromRGB(22, 24, 30),
    bar = Color3.fromRGB(40, 44, 54),
    tabOn = Color3.fromRGB(90, 150, 255),
    tabOff = Color3.fromRGB(52, 56, 66),
    on = Color3.fromRGB(40, 150, 90),
    off = Color3.fromRGB(90, 92, 100),
    text = Color3.fromRGB(225, 225, 225),
    dim = Color3.fromRGB(150, 150, 155),
    accent = Color3.fromRGB(90, 150, 255),
    bgBtn = Color3.fromRGB(52, 56, 66),
}

local function NewToggle(parent, y, text, get, set, onChange)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -70, 0, 26)
    label.Position = UDim2.new(0, 0, 0, y)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = C.text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Font = Enum.Font.Gotham
    label.TextSize = 14
    label.Parent = parent

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(54, 22)
    btn.Position = UDim2.new(1, -58, 0, y + 2)
    btn.BackgroundColor3 = C.off
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Parent = parent

    local function Refresh()
        local v = get()
        btn.Text = v and "ON" or "OFF"
        btn.BackgroundColor3 = v and C.on or C.off
    end
    Refresh()
    AddRefresh(Refresh)

    btn.MouseButton1Click:Connect(function()
        set(not get())
        Refresh()
        if onChange then pcall(onChange, get()) end
        SaveConfig()
    end)
    return y + 26
end

local function NewSlider(parent, y, text, min, max, step, fmt, get, set, onChange)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -190, 0, 26)
    label.Position = UDim2.new(0, 0, 0, y)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = C.text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Font = Enum.Font.Gotham
    label.TextSize = 14
    label.Parent = parent

    local val = Instance.new("TextLabel")
    val.Size = UDim2.fromOffset(58, 26)
    val.Position = UDim2.new(1, -186, 0, y)
    val.BackgroundTransparency = 1
    val.Text = ""
    val.TextColor3 = C.dim
    val.Font = Enum.Font.Gotham
    val.TextSize = 13
    val.Parent = parent

    local bar = Instance.new("Frame")
    bar.Size = UDim2.fromOffset(116, 6)
    bar.Position = UDim2.new(1, -120, 0, y + 10)
    bar.BackgroundColor3 = C.bar
    bar.BorderSizePixel = 0
    bar.Parent = parent

    local fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(0.5, 1)
    fill.BackgroundColor3 = C.accent
    fill.BorderSizePixel = 0
    fill.Parent = bar

    local handle = Instance.new("TextButton")
    handle.Size = UDim2.fromOffset(10, 16)
    handle.BackgroundColor3 = Color3.new(1, 1, 1)
    handle.BorderSizePixel = 0
    handle.Text = ""
    handle.Parent = bar

    local function Apply(v)
        local fv = math.max(min, math.min(max, v))
        fv = math.floor(fv / step + 0.5) * step
        fv = math.max(min, math.min(max, fv))
        set(fv)
        val.Text = string.format(fmt, fv)
        local bw = math.max(1, bar.AbsoluteSize.X)
        local frac = (fv - min) / (max - min)
        fill.Size = UDim2.fromScale(frac, 1)
        handle.Position = UDim2.new(frac, -5, 0, -5)
        if onChange then pcall(onChange, fv) end
    end

    local dragging = false
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local rel = input.Position.X - bar.AbsolutePosition.X
            Apply(min + (rel / math.max(1, bar.AbsoluteSize.X)) * (max - min))
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
            dragging = false
            SaveConfig()
        end
    end)

    local function Refresh()
        Apply(get())
    end
    AddRefresh(Refresh)
    Refresh()
    return y + 26
end

local KeybindButtons = {}
local function NewKeybind(parent, y, text, keyName)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -70, 0, 26)
    label.Position = UDim2.new(0, 0, 0, y)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = C.text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Font = Enum.Font.Gotham
    label.TextSize = 14
    label.Parent = parent

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(96, 22)
    btn.Position = UDim2.new(1, -100, 0, y + 2)
    btn.BackgroundColor3 = C.bgBtn
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Parent = parent

    local function Refresh()
        local k = Settings.keybinds[keyName]
        btn.Text = (type(k) == "string" and k ~= "") and k or "?"
    end
    Refresh()
    AddRefresh(Refresh)
    KeybindButtons[keyName] = btn

    btn.MouseButton1Click:Connect(function()
        Listening = keyName
        btn.Text = "..."
        Log("Press a key for " .. text .. " (Esc cancels)")
    end)
    return y + 26
end

local function NewCycle(parent, y, text, options, get, set)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -70, 0, 26)
    label.Position = UDim2.new(0, 0, 0, y)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = C.text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Font = Enum.Font.Gotham
    label.TextSize = 14
    label.Parent = parent

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(120, 22)
    btn.Position = UDim2.new(1, -124, 0, y + 2)
    btn.BackgroundColor3 = C.bgBtn
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Parent = parent

    local function Refresh()
        btn.Text = tostring(get())
    end
    Refresh()
    AddRefresh(Refresh)

    btn.MouseButton1Click:Connect(function()
        local cur = tostring(get())
        local idx = 1
        for i = 1, #options do
            if options[i] == cur then idx = i break end
        end
        idx = idx % #options + 1
        set(options[idx])
        Refresh()
        SaveConfig()
    end)
    return y + 26
end

local function NewButton(parent, y, text, cb)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 26)
    btn.Position = UDim2.new(0, 0, 0, y)
    btn.BackgroundColor3 = C.bgBtn
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Text = text
    btn.Parent = parent
    btn.MouseButton1Click:Connect(function()
        pcall(cb)
    end)
    return y + 26
end

local function NewLabel(parent, y, text, height)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, height or 24)
    lbl.Position = UDim2.new(0, 0, 0, y)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = C.dim
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 13
    lbl.Parent = parent
    return y + (height or 24), lbl
end

-- List editor popup (blacklist / whitelist)
local Popup, PopupTitle, PopupBox, PopupKind
local function OpenListEditor(kind)
    if not Popup then return end
    PopupKind = kind
    local list = (kind == "blacklist") and Settings.silentAim.blacklist or Settings.silentAim.whitelist
    PopupTitle.Text = (kind == "blacklist") and "Blacklist (user IDs, comma-separated)" or "Whitelist (user IDs, comma-separated)"
    PopupBox.Text = table.concat(list, ", ")
    Popup.Visible = true
end
local function ClosePopup()
    if Popup then Popup.Visible = false end
end
local function SavePopup()
    local ids = {}
    for tok in PopupBox.Text:gmatch("%d+") do
        ids[#ids + 1] = tonumber(tok)
    end
    if PopupKind == "blacklist" then
        Settings.silentAim.blacklist = ids
    else
        Settings.silentAim.whitelist = ids
    end
    SaveConfig()
    ClosePopup()
    Log(PopupKind .. " updated (" .. #ids .. " IDs)")
end

-- Tab page builder helpers
local function NewPage(parent, y)
    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.new(1, -12, 1, -8)
    page.Position = UDim2.new(0, 6, 0, y)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 4
    page.ScrollingDirection = Enum.ScrollingDirection.Y
    page.CanvasSize = UDim2.fromOffset(0, 16)
    page.Visible = false
    page.Parent = parent
    return page, function(rows)
        page.CanvasSize = UDim2.fromOffset(0, rows + 8)
    end
end

local Pages = {}
local TabButtons = {}
local currentTab = "Combat"

local function BuildUI()
    if UI.Built then return end
    UI.Built = true

    local gui = Instance.new("ScreenGui")
    gui.Name = "EternalClubDaHood"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    local okCore, core = pcall(function() return game:GetService("CoreGui") end)
    gui.Parent = (okCore and core) or LocalPlayer:WaitForChild("PlayerGui")

    -- Main container frame (draggable / closeable)
    local main = Instance.new("Frame")
    main.Size = UDim2.fromOffset(560, 400)
    main.Position = UDim2.fromOffset(40, 70)
    main.BackgroundColor3 = C.bg
    main.BorderSizePixel = 0
    main.Parent = gui
    UIContainer = main

    -- Title bar (drag handle + close button)
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, 0, 0, 34)
    bar.BackgroundColor3 = C.bar
    bar.BorderSizePixel = 0
    bar.Parent = main

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -70, 1, 0)
    title.Position = UDim2.fromOffset(10, 0)
    title.BackgroundTransparency = 1
    title.Text = "Eternal Club — Da Hood"
    title.TextColor3 = C.text
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.GothamBold
    title.TextSize = 15
    title.Parent = bar

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.fromOffset(26, 22)
    closeBtn.Position = UDim2.new(1, -32, 0.5, -11)
    closeBtn.BackgroundColor3 = C.off
    closeBtn.BorderSizePixel = 0
    closeBtn.Text = "X"
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 13
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.Parent = bar
    closeBtn.MouseButton1Click:Connect(function()
        main.Visible = false
    end)

    local dragging, dragStart, frameStart
    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            frameStart = main.Position
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - dragStart
            main.Position = UDim2.fromOffset(frameStart.X.Offset + d.X, frameStart.Y.Offset + d.Y)
        end
    end)

    -- Watermark (always visible; click to reopen the menu)
    local wm = Instance.new("TextLabel")
    wm.Size = UDim2.fromOffset(230, 26)
    wm.Position = UDim2.fromOffset(8, 8)
    wm.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
    wm.BackgroundTransparency = 0.35
    wm.BorderSizePixel = 0
    wm.Text = "Eternal Club — by FallenSoul7"
    wm.TextColor3 = C.accent
    wm.Font = Enum.Font.GothamBold
    wm.TextSize = 14
    wm.Parent = gui
    wm.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            main.Visible = not main.Visible
        end
    end)

    -- Log panel (bottom of the menu)
    LogLabel = Instance.new("TextLabel")
    LogLabel.Size = UDim2.new(1, -12, 0, 58)
    LogLabel.Position = UDim2.new(0, 6, 1, -62)
    LogLabel.BackgroundColor3 = C.bar
    LogLabel.BackgroundTransparency = 0.4
    LogLabel.BorderSizePixel = 0
    LogLabel.Text = table.concat(LogLines, "\n")
    LogLabel.TextColor3 = C.dim
    LogLabel.TextXAlignment = Enum.TextXAlignment.Left
    LogLabel.TextYAlignment = Enum.TextYAlignment.Bottom
    LogLabel.Font = Enum.Font.Gotham
    LogLabel.TextSize = 11
    LogLabel.Parent = main

    -- Tab row
    local tabs = { "Combat", "Visual", "Character", "Farm", "World", "Settings" }
    local tabRow = Instance.new("Frame")
    tabRow.Size = UDim2.new(1, 0, 0, 30)
    tabRow.Position = UDim2.new(0, 0, 0, 34)
    tabRow.BackgroundTransparency = 1
    tabRow.Parent = main

    local function SwitchTab(name)
        currentTab = name
        for k, pg in pairs(Pages) do
            pg.Visible = (k == name)
        end
        for k, btn in pairs(TabButtons) do
            btn.BackgroundColor3 = (k == name) and C.tabOn or C.tabOff
        end
    end

    for i = 1, #tabs do
        local tb = Instance.new("TextButton")
        tb.Size = UDim2.new(1 / #tabs, 0, 1, 0)
        tb.Position = UDim2.new((i - 1) / #tabs, 0, 0, 0)
        tb.BackgroundColor3 = C.tabOff
        tb.BorderSizePixel = 0
        tb.Text = tabs[i]
        tb.Font = Enum.Font.GothamBold
        tb.TextSize = 13
        tb.TextColor3 = Color3.new(1, 1, 1)
        tb.Parent = tabRow
        TabButtons[tabs[i]] = tb
        local name = tabs[i]
        tb.MouseButton1Click:Connect(function() SwitchTab(name) end)
    end

    -- Pages ---------------------------------------------------------------
    local function makePage(name)
        local page, finish = NewPage(main, 66)
        Pages[name] = page
        return page, finish
    end

    -- Combat
    do
        local pg, fin = makePage("Combat")
        local y = 4
        y = NewToggle(pg, y, "Silent Aim",
            function() return Settings.silentAim.enabled end,
            function(v) Settings.silentAim.enabled = v end)
        y = NewSlider(pg, y, "FOV (degrees)", 2, 60, 1, "%d",
            function() return Settings.silentAim.fov end,
            function(v) Settings.silentAim.fov = v end)
        y = NewToggle(pg, y, "FOV Circle",
            function() return Settings.silentAim.showFov end,
            function(v) Settings.silentAim.showFov = v end)
        y = NewSlider(pg, y, "Hit Chance (%)", 1, 100, 1, "%d%%",
            function() return Settings.silentAim.hitChance end,
            function(v) Settings.silentAim.hitChance = v end)
        y = NewToggle(pg, y, "Team Check",
            function() return Settings.silentAim.teamCheck end,
            function(v) Settings.silentAim.teamCheck = v end)
        y = NewToggle(pg, y, "Visibility Check",
            function() return Settings.silentAim.visibleCheck end,
            function(v) Settings.silentAim.visibleCheck = v end)
        y = NewToggle(pg, y, "Whitelist Only",
            function() return Settings.silentAim.whitelistOnly end,
            function(v) Settings.silentAim.whitelistOnly = v end)
        y = NewButton(pg, y, "Edit Blacklist", function() OpenListEditor("blacklist") end)
        y = NewButton(pg, y, "Edit Whitelist", function() OpenListEditor("whitelist") end)
        y = NewCycle(pg, y, "Target Part", Aim.TARGET_PART_CYCLE,
            function() return Settings.silentAim.targetParts[1] or "Head" end,
            function(v) Settings.silentAim.targetParts = { v } end)
        y = NewSlider(pg, y, "Prediction (aim)", 0, 0.5, 0.01, "%.2fs",
            function() return Settings.silentAim.prediction end,
            function(v) Settings.silentAim.prediction = v end)
        y = NewToggle(pg, y, "Spoof MousePos",
            function() return Settings.silentAim.spoofMousePos end,
            function(v) Settings.silentAim.spoofMousePos = v end)
        y = NewLabel(pg, y, "--- Aimlock ---", 22)
        y = NewToggle(pg, y, "Aimlock",
            function() return Settings.aimlock.enabled end,
            function(v) Settings.aimlock.enabled = v end)
        y = NewCycle(pg, y, "Mode", { "Camera", "Mouse" },
            function() return Settings.aimlock.mode == "camera" and "Camera" or "Mouse" end,
            function(v) Settings.aimlock.mode = (v == "Camera") and "camera" or "mouse" end)
        y = NewSlider(pg, y, "Prediction (lock)", 0, 0.5, 0.01, "%.2fs",
            function() return Settings.aimlock.prediction end,
            function(v) Settings.aimlock.prediction = v end)
        y = NewToggle(pg, y, "Gravity Prediction",
            function() return Settings.aimlock.gravityPrediction end,
            function(v) Settings.aimlock.gravityPrediction = v end)
        y = NewKeybind(pg, y, "Aimlock Key", "aimlock")
        fin(y)
    end

    -- Visual
    do
        local pg, fin = makePage("Visual")
        local y = 4
        y = NewToggle(pg, y, "ESP",
            function() return Settings.esp.enabled end,
            function(v) Settings.esp.enabled = v end)
        y = NewToggle(pg, y, "Boxes",
            function() return Settings.esp.boxes end,
            function(v) Settings.esp.boxes = v end)
        y = NewToggle(pg, y, "Health",
            function() return Settings.esp.health end,
            function(v) Settings.esp.health = v end)
        y = NewToggle(pg, y, "Distance",
            function() return Settings.esp.distance end,
            function(v) Settings.esp.distance = v end)
        y = NewToggle(pg, y, "Tracers",
            function() return Settings.esp.tracers end,
            function(v) Settings.esp.tracers = v end)
        y = NewToggle(pg, y, "Team Colors",
            function() return Settings.esp.teamColors end,
            function(v) Settings.esp.teamColors = v end)
        fin(y)
    end

    -- Character
    do
        local pg, fin = makePage("Character")
        local y = 4
        y = NewToggle(pg, y, "Anti-Ragdoll",
            function() return Settings.character.antiRagdoll end,
            function(v) Settings.character.antiRagdoll = v end,
            function() ApplyProtections() end)
        y = NewToggle(pg, y, "Anti-Fall",
            function() return Settings.character.antiFall end,
            function(v) Settings.character.antiFall = v end,
            function() ApplyProtections() end)
        y = NewToggle(pg, y, "Hide Name",
            function() return Settings.character.hideName end,
            function(v) Settings.character.hideName = v end,
            function() ApplyProtections() end)
        y = NewToggle(pg, y, "Remove Hoodie",
            function() return Settings.character.removeHoodie end,
            function(v) Settings.character.removeHoodie = v end,
            function() ApplyProtections() end)
        y = NewToggle(pg, y, "Remove Face",
            function() return Settings.character.removeFace end,
            function(v) Settings.character.removeFace = v end,
            function() ApplyProtections() end)
        y = NewToggle(pg, y, "Protect WalkSpeed",
            function() return Settings.character.protectWalkSpeed end,
            function(v) Settings.character.protectWalkSpeed = v end)
        y = NewSlider(pg, y, "Transparency", 0, 1, 0.05, "%.2f",
            function() return Settings.character.transparency end,
            function(v) Settings.character.transparency = v end,
            function() ApplyTransparency() end)
        fin(y)
    end

    -- Farm
    do
        local pg, fin = makePage("Farm")
        local y = 4
        y = NewToggle(pg, y, "Money (Nearby)",
            function() return Settings.farm.moneyNearby end,
            function(v)
                Settings.farm.moneyNearby = v
                if v then Settings.farm.moneyAll = false end
                RefreshAll()
            end,
            function(v)
                if v then
                    task.spawn(RunFarmJob, "Money (nearby)", function()
                        CollectMoney(true, Settings.farm.tpBack)
                    end)
                end
            end)
        y = NewToggle(pg, y, "Money (All Map)",
            function() return Settings.farm.moneyAll end,
            function(v)
                Settings.farm.moneyAll = v
                if v then Settings.farm.moneyNearby = false end
                RefreshAll()
            end,
            function(v)
                if v then
                    task.spawn(RunFarmJob, "Money (all map)", function()
                        CollectMoney(false, Settings.farm.tpBack)
                    end)
                end
            end)
        y = NewToggle(pg, y, "Shoes",
            function() return Settings.farm.shoes end,
            function(v) Settings.farm.shoes = v end,
            function(v)
                if v then
                    task.spawn(RunFarmJob, "Shoes", function()
                        CollectShoes(Settings.farm.tpBack)
                    end)
                end
            end)
        y = NewToggle(pg, y, "Tools",
            function() return Settings.farm.tools end,
            function(v) Settings.farm.tools = v end,
            function(v)
                if v then
                    task.spawn(RunFarmJob, "Tools", function()
                        CollectTools(Settings.farm.tpBack)
                    end)
                end
            end)
        y = NewToggle(pg, y, "TP Back",
            function() return Settings.farm.tpBack end,
            function(v) Settings.farm.tpBack = v end)
        y = NewToggle(pg, y, "Cashier Loop",
            function() return Settings.farm.cashiers end,
            function(v) Settings.farm.cashiers = v end,
            function(v)
                ToggleCashiers(v)
                RefreshAll()
            end)
        local ny, farmLbl = NewLabel(pg, y, "Cashier status: idle", 24)
        y = ny
        FarmStatusLabel = farmLbl
        fin(y)
    end

    -- World
    do
        local pg, fin = makePage("World")
        local y = 4
        y = NewToggle(pg, y, "Anti-Fly Bypass",
            function() return Settings.world.antiFly end,
            function(v)
                Settings.world.antiFly = v
                if Compat.getgenv then Compat.getgenv().BypassFlyDaHood = v end
            end)
        y = NewCycle(pg, y, "Teleport Mode", { "Instant", "Smooth" },
            function() return Settings.world.teleportSmooth and "Smooth" or "Instant" end,
            function(v) Settings.world.teleportSmooth = (v == "Smooth") end)
        y = NewLabel(pg, y, "Teleport is used by the farmers", 24)
        fin(y)
    end

    -- Settings
    do
        local pg, fin = makePage("Settings")
        local y = 4
        y = NewKeybind(pg, y, "UI Key", "ui")
        y = NewKeybind(pg, y, "Farm Key", "farm")
        y = NewButton(pg, y, "Save Config", function()
            SaveConfig()
            Log("Config saved")
        end)
        y = NewButton(pg, y, "Load Config", function()
            LoadConfig()
            RefreshAll()
            ApplyProtections()
            Log("Config reloaded")
        end)
        y = NewButton(pg, y, "Reset Config", function()
            Settings = DeepCopy(DEFAULT_SETTINGS)
            RefreshAll()
            ApplyProtections()
            SaveConfig()
            Log("Config reset to defaults")
        end)
        y = NewLabel(pg, y, "PlaceId: 2788229376 (Da Hood)", 24)
        y = NewLabel(pg, y, "Gun system: " .. (GunScript and "found" or "not found"), 24)
        y = NewLabel(pg, y, "Eternal Club Da Hood " .. VERSION, 24)
        fin(y)
    end

    -- Popup (list editor)
    Popup = Instance.new("Frame")
    Popup.Size = UDim2.fromOffset(340, 150)
    Popup.Position = UDim2.new(0.5, -170, 0.5, -75)
    Popup.BackgroundColor3 = C.bg
    Popup.BorderSizePixel = 0
    Popup.ZIndex = 20
    Popup.Visible = false
    Popup.Parent = gui

    PopupTitle = Instance.new("TextLabel")
    PopupTitle.Size = UDim2.new(1, -16, 0, 30)
    PopupTitle.Position = UDim2.fromOffset(8, 8)
    PopupTitle.BackgroundTransparency = 1
    PopupTitle.Text = ""
    PopupTitle.TextColor3 = C.text
    PopupTitle.TextXAlignment = Enum.TextXAlignment.Left
    PopupTitle.Font = Enum.Font.GothamBold
    PopupTitle.TextSize = 14
    PopupTitle.ZIndex = 21
    PopupTitle.Parent = Popup

    PopupBox = Instance.new("TextBox")
    PopupBox.Size = UDim2.new(1, -16, 0, 30)
    PopupBox.Position = UDim2.fromOffset(8, 44)
    PopupBox.BackgroundColor3 = C.bar
    PopupBox.BorderSizePixel = 0
    PopupBox.Text = ""
    PopupBox.PlaceholderText = "123456, 789012, ..."
    PopupBox.TextColor3 = Color3.new(1, 1, 1)
    PopupBox.Font = Enum.Font.Gotham
    PopupBox.TextSize = 14
    PopupBox.ZIndex = 21
    PopupBox.Parent = Popup

    local popupSave = Instance.new("TextButton")
    popupSave.Size = UDim2.fromOffset(80, 26)
    popupSave.Position = UDim2.new(1, -172, 0, 84)
    popupSave.BackgroundColor3 = C.on
    popupSave.BorderSizePixel = 0
    popupSave.Text = "Save"
    popupSave.Font = Enum.Font.GothamBold
    popupSave.TextSize = 13
    popupSave.TextColor3 = Color3.new(1, 1, 1)
    popupSave.ZIndex = 21
    popupSave.Parent = Popup
    popupSave.MouseButton1Click:Connect(SavePopup)

    local popupCancel = Instance.new("TextButton")
    popupCancel.Size = UDim2.fromOffset(80, 26)
    popupCancel.Position = UDim2.new(1, -88, 0, 84)
    popupCancel.BackgroundColor3 = C.off
    popupCancel.BorderSizePixel = 0
    popupCancel.Text = "Cancel"
    popupCancel.Font = Enum.Font.GothamBold
    popupCancel.TextSize = 13
    popupCancel.TextColor3 = Color3.new(1, 1, 1)
    popupCancel.ZIndex = 21
    popupCancel.Parent = Popup
    popupCancel.MouseButton1Click:Connect(ClosePopup)

    SwitchTab("Combat")
    task.defer(RefreshAll)
end

--===========================================================================
-- 18. HOTKEYS + MAIN LOOP
--===========================================================================
local function ResolveKey(name)
    if type(name) ~= "string" then return nil end
    local ok, kc = pcall(function() return Enum.KeyCode[name] end)
    return ok and kc or nil
end

local function OnInputBegan(input, gameProcessedEvent)
    -- keybind rebinding in progress
    if Listening then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            if input.KeyCode == Enum.KeyCode.Escape then
                Listening = nil
                RefreshAll()
                return
            end
            Settings.keybinds[Listening] = tostring(input.KeyCode.Name)
            Listening = nil
            SaveConfig()
            RefreshAll()
            Log("Keybind set")
        end
        return
    end
    -- ignore keyboard input while typing in a TextBox
    if UserInputService:GetFocusedTextBox() then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

    local kcAim = ResolveKey(Settings.keybinds.aimlock)
    local kcUI = ResolveKey(Settings.keybinds.ui)
    local kcFarm = ResolveKey(Settings.keybinds.farm)
    if kcAim and input.KeyCode == kcAim then
        Settings.aimlock.enabled = not Settings.aimlock.enabled
        SaveConfig()
        RefreshAll()
    elseif kcUI and input.KeyCode == kcUI then
        if UIContainer then UIContainer.Visible = not UIContainer.Visible end
    elseif kcFarm and input.KeyCode == kcFarm then
        Settings.farm.cashiers = not Settings.farm.cashiers
        ToggleCashiers(Settings.farm.cashiers)
        SaveConfig()
        RefreshAll()
    end
end

local function OnRenderStepped(dt)
    pcall(function()
        if Settings.silentAim.enabled or Settings.aimlock.enabled then
            Aim:ScanIfStale()
        end
    end)
    pcall(ESPUpdate)
    pcall(function()
        if FovCircle and Settings.silentAim.showFov then
            local cam = Workspace.CurrentCamera
            if cam then
                local vp = cam.ViewportSize
                FovCircle.Position = Vector2.new(vp.X / 2, vp.Y / 2)
                FovCircle.Radius = FovRadiusPx()
            end
            FovCircle.Visible = true
        elseif FovCircle then
            FovCircle.Visible = false
        end
    end)
    pcall(function()
        if Settings.aimlock.enabled then ApplyAimlock() end
    end)
    pcall(function()
        if Settings.silentAim.enabled and Settings.silentAim.spoofMousePos then
            SpoofMousePos()
        end
    end)
    pcall(function() BezierStep(dt) end)
end

--===========================================================================
-- 19. INIT
--===========================================================================
LoadConfig()
BuildUI()
InstallHooks()

LocalPlayer.CharacterAdded:Connect(OnCharacterAdded)
if LocalPlayer.Character then
    Character = LocalPlayer.Character
    Humanoid = Character:FindFirstChildOfClass("Humanoid")
    HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")
    task.wait()
    ApplyProtections()
end

Players.PlayerAdded:Connect(ESPOnPlayerAdded)
Players.PlayerRemoving:Connect(ESPOnPlayerRemoving)
for _, p in ipairs(Players:GetPlayers()) do
    ESPOnPlayerAdded(p)
end

task.spawn(AntiFlyLoop)

task.spawn(function()
    while true do
        task.wait(0.5)
        if FarmStatusLabel then
            FarmStatusLabel.Text = "Cashier status: " .. Farm.Status
        end
    end
end)

UserInputService.InputBegan:Connect(OnInputBegan)
RunService.RenderStepped:Connect(OnRenderStepped)

Log("Eternal Club Da Hood " .. VERSION .. " loaded (PlaceId " .. tostring(game.PlaceId) .. ")")
if not HasDraw then
    Log("Drawing API unavailable — ESP / FOV circle disabled", true)
end
Log(GunScript and "GunScript found — gun aim ready" or "GunScript not found")
