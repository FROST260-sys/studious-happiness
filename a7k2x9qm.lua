local PRODUCT = "Frost Hub"
local VERSION = "Frost Hub v1.0"

local ENV = getgenv and getgenv() or _G
local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local function tagFrom(seed, n)
    local h = 5381
    local s = tostring(seed)
    for i = 1, #s do
        h = (h * 33 + string.byte(s, i)) % 2147483647
    end
    local cs = "abcdefghijklmnopqrstuvwxyz0123456789"
    local out = {}
    for i = 1, n do
        h = (h * 48271) % 2147483647
        local idx = (h % #cs) + 1
        out[i] = string.sub(cs, idx, idx)
    end
    return table.concat(out)
end

local STABLE_TAG = tagFrom(LP and LP.UserId or os.time(), 8)
local SENTINEL_KEY = "frost_" .. STABLE_TAG
local CONFIG_FILE = "frosthub_" .. STABLE_TAG .. ".json"

pcall(function() print("[Frost Hub] " .. VERSION .. " loading") end)

local function pick(...)
    local names = { ... }
    for i = 1, #names do
        local v = ENV[names[i]]
        if type(v) == "function" then return v end
    end
    return nil
end

local CAP = {
    cloneref = pick("cloneref"),
    gethui = pick("gethui"),
    protect = pick("protect_gui"),
    hookfunction = pick("hookfunction"),
    hookmetamethod = pick("hookmetamethod"),
    getconnections = pick("getconnections"),
    firetouchinterest = pick("firetouchinterest"),
    setclipboard = pick("setclipboard"),
    identifyexecutor = pick("identifyexecutor"),
    gethiddenproperty = pick("gethiddenproperty"),
    sethiddenproperty = pick("sethiddenproperty"),
    setreadonly = pick("setreadonly"),
    getrawmetatable = pick("getrawmetatable"),
    newcclosure = pick("newcclosure"),
    checkcaller = pick("checkcaller"),
    getnamecallmethod = pick("getnamecallmethod"),
    queue_on_teleport = pick("queue_on_teleport", "queueonteleport"),
    isfile = pick("isfile"),
    writefile = pick("writefile"),
    readfile = pick("readfile"),
    delfile = pick("delfile"),
    isfolder = pick("isfolder"),
    makefolder = pick("makefolder"),
    request = pick("request", "http_request"),
    isnetworkowner = pick("isnetworkowner"),
}

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return false, nil end
    local packed = table.pack(pcall(fn, ...))
    if not packed[1] then return false, packed[2] end
    return true, table.unpack(packed, 2, packed.n)
end

local function grab(name)
    local ok, svc = pcall(function() return game:GetService(name) end)
    if not ok or not svc then return nil end
    if CAP.cloneref then
        local ok2, c = pcall(CAP.cloneref, svc)
        if ok2 and c then return c end
    end
    return svc
end

local ReplicatedStorage = grab("ReplicatedStorage")
local RunService = grab("RunService")
local UserInputService = grab("UserInputService")
local TweenService = grab("TweenService")
local Lighting = grab("Lighting")
local Workspace = grab("Workspace")
local VirtualUser = grab("VirtualUser")
local CoreGui = grab("CoreGui")
local TeleportService = grab("TeleportService")
local HttpService = grab("HttpService")
local GuiService = grab("GuiService")
local Stats = grab("Stats")

local PLATFORM = {
    os = "unknown",
    hasTouch = false,
    hasKeyboard = false,
    mobile = false,
    drawing = false,
    fs = false,
    hz = 60,
    guiParent = nil,
    executor = "unknown",
}

do
    local okName, name = safeCall(CAP.identifyexecutor)
    if okName and type(name) == "string" then
        PLATFORM.executor = string.lower(name)
    end
    if UserInputService then
        PLATFORM.hasTouch = UserInputService.TouchEnabled and true or false
        PLATFORM.hasKeyboard = UserInputService.KeyboardEnabled and true or false
    end
    local ex = PLATFORM.executor
    local iosHint = string.find(ex, "ios", 1, true) or string.find(ex, "iphone", 1, true) or string.find(ex, "ipad", 1, true)
    local androidHint = string.find(ex, "android", 1, true) or string.find(ex, "arceus", 1, true) or string.find(ex, "hydrogen", 1, true)
    if iosHint then
        PLATFORM.os = "ios"
    elseif androidHint then
        PLATFORM.os = "android"
    elseif PLATFORM.hasKeyboard and not PLATFORM.hasTouch then
        PLATFORM.os = "windows"
    elseif PLATFORM.hasTouch and not PLATFORM.hasKeyboard then
        PLATFORM.os = "android"
    elseif PLATFORM.hasKeyboard then
        PLATFORM.os = "windows"
    end
    PLATFORM.mobile = PLATFORM.os == "android" or PLATFORM.os == "ios" or (PLATFORM.hasTouch and not PLATFORM.hasKeyboard)
    PLATFORM.fs = (CAP.isfile ~= nil and CAP.writefile ~= nil and CAP.readfile ~= nil)
end

do
    local okDraw, drawLib = pcall(function() return Drawing end)
    if okDraw and type(drawLib) == "table" then
        local okTest, sq = pcall(function() return drawLib.new("Square") end)
        if okTest and sq then
            local okUse = pcall(function()
                sq.Visible = false
                sq.Size = Vector2.new(4, 4)
                sq.Color = Color3.fromRGB(255, 255, 255)
            end)
            pcall(function() sq:Destroy() end)
            PLATFORM.drawing = okUse and true or false
        end
    end
end

do
    local samples, total = 0, 0
    local conn
    local finished = false
    local startT = os.clock()
    conn = RunService.Heartbeat:Connect(function(dt)
        if finished then return end
        samples = samples + 1
        total = total + dt
        if samples >= 30 or (os.clock() - startT) > 2.0 then
            finished = true
            if conn then conn:Disconnect() end
            local avg = (samples > 0) and (total / samples) or (1 / 60)
            if avg > 0 then
                PLATFORM.hz = math.clamp(math.floor(1 / avg + 0.5), 20, 240)
            end
        end
    end)
    task.wait(0.05)
    if PLATFORM.mobile then
        PLATFORM.hz = math.min(PLATFORM.hz, 60)
    end
end

do
    local resolved
    if CAP.gethui then
        local ok, h = safeCall(CAP.gethui)
        if ok and h then resolved = h end
    end
    if not resolved and CAP.protect and CoreGui then
        local holder = Instance.new("Folder")
        holder.Name = "g" .. STABLE_TAG
        local ok = safeCall(CAP.protect, holder)
        if ok then
            pcall(function() holder.Parent = CoreGui end)
            resolved = holder
        end
    end
    if not resolved and CoreGui then
        local ok = pcall(function() return CoreGui:GetChildren() end)
        if ok then resolved = CoreGui end
    end
    if not resolved and LP then
        local pg = LP:FindFirstChildOfClass("PlayerGui")
        if pg then resolved = pg end
    end
    PLATFORM.guiParent = resolved
end

local TICK = 1 / math.max(PLATFORM.hz, 20)
local MIN_YIELD = PLATFORM.mobile and (1 / 30) or (1 / 60)
local SCAN_TICK = PLATFORM.mobile and math.max(TICK * 3, 1 / 30) or math.max(TICK, 1 / 60)

local Util = {}

function Util.humanWait(base)
    local v = base * (1 + (math.random() * 0.6 - 0.3))
    if v < MIN_YIELD then v = MIN_YIELD end
    task.wait(v)
end

function Util.jitter(base, spread)
    return base * (1 + (math.random() * 2 - 1) * (spread or 0.3))
end

function Util.clamp(v, lo, hi)
    if type(v) ~= "number" then return lo end
    if v ~= v then return lo end
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function Util.round(v, places)
    local m = 10 ^ (places or 0)
    return math.floor(v * m + 0.5) / m
end

function Util.isAlive(c)
    if not c then return false end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    return hum.Health > 0
end

function Util.newLRU(capacity)
    local store, order = {}, {}
    local api = {}
    function api.get(key)
        local entry = store[key]
        if not entry then return nil end
        entry.tick = os.clock()
        return entry.value
    end
    function api.set(key, value)
        if not store[key] then
            table.insert(order, key)
            if #order > capacity then
                local oldest, idx = math.huge, 1
                for i = 1, #order do
                    local e = store[order[i]]
                    if e and e.tick < oldest then oldest, idx = e.tick, i end
                end
                local victim = table.remove(order, idx)
                store[victim] = nil
            end
        end
        store[key] = { value = value, tick = os.clock() }
    end
    function api.clear() store, order = {}, {} end
    function api.size() return #order end
    return api
end

function Util.deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = Util.deepCopy(val) end
    return out
end

function Util.deepMerge(base, over)
    local out = Util.deepCopy(base)
    for k, v in pairs(over or {}) do
        if type(v) == "table" and type(out[k]) == "table" then
            out[k] = Util.deepMerge(out[k], v)
        else
            out[k] = Util.deepCopy(v)
        end
    end
    return out
end

local TEARDOWN_HOOKS = {}

local function registerTeardown(fn)
    table.insert(TEARDOWN_HOOKS, fn)
end

local function runTeardown()
    for i = #TEARDOWN_HOOKS, 1, -1 do
        local fn = TEARDOWN_HOOKS[i]
        TEARDOWN_HOOKS[i] = nil
        pcall(fn)
    end
end

do
    local victims = {}
    for k in pairs(ENV) do
        if type(k) == "string" and string.match(k, "^frost_[a-z0-9]+$") then
            table.insert(victims, k)
        end
    end
    for i = 1, #victims do
        local key = victims[i]
        local prev = ENV[key]
        if type(prev) == "table" then
            if type(prev.teardown) == "function" then pcall(prev.teardown) end
            if prev.gui then pcall(function() prev.gui:Destroy() end) end
            if prev.blur then pcall(function() prev.blur:Destroy() end) end
        end
        ENV[key] = nil
    end
end

local DEFAULTS = {
    version = 1,
    ui = {
        visible = true, minimized = false, x = 0.5, y = 0.5,
        width = 620, height = 460, tab = "Farm",
        snow = false, blur = false,
    },
    leveling = {
        enabled = false, targetLevel = 3000, preferBoss = true,
        hopForBoss = false, hopCapPerMinute = 6, privateServer = "",
        useCodes = true, statPlan = "balanced", convertAt1900 = false,
    },
    stats = { melee = 0, defense = 0, sword = 0, gun = 0, fruit = 0, autoAllocate = false },
    farm = {
        mobs = false, bosses = false, chests = false, bones = false,
        mastery = false, fruit = false, fishing = false, seaBeast = false,
        elites = false, magnet = false,
        masteryCap = 600, levelFloor = 1, levelCeil = 3000, ignoreList = {},
    },
    events = {
        raid = false, factory = false, seaEvents = false, mirage = false,
        kitsune = false, haunted = false, cursedShip = false, castleSea = false,
        raceTrial = false, raceV4 = false, raidFruit = "Dragon",
    },
    progression = {
        buso = false, ken = false, trainHaki = false, styles = {}, guns = {},
        swords = {}, legendaries = {}, sanguine = false, awaken = false,
        races = {}, valkyrie = false, fragments = false,
    },
    util = {
        espPlayers = false, espEnemies = false, espFruits = false,
        espChests = false, espNpcs = false, espSeaBeasts = false,
        espDistance = 0, espCap = 0,
        aimbot = false, aimFov = 120, aimSmooth = 0.22, aimPart = "Head", aimTeam = false,
        fruitSniper = false, fruitFilter = "", autoStore = false, autoSell = false,
        antiAfk = true, autoRejoin = false, serverHop = false,
        hopMinPlayers = 0, hopMaxPing = 200,
    },
    keys = { toggleUi = "RightShift", toggleFarm = "RightControl", panic = "F1" },
}

local Config = {
    data = Util.deepCopy(DEFAULTS),
    dirty = false,
    fromDisk = false,
}

local function clampAll()
    local c = Config.data
    c.ui.width = Util.clamp(c.ui.width, 320, 1200)
    c.ui.height = Util.clamp(c.ui.height, 240, 900)
    c.ui.x = Util.clamp(c.ui.x, 0, 1)
    c.ui.y = Util.clamp(c.ui.y, 0, 1)
    c.leveling.targetLevel = Util.clamp(c.leveling.targetLevel, 1, 3000)
    c.leveling.hopCapPerMinute = Util.clamp(c.leveling.hopCapPerMinute, 1, 10)
    c.farm.masteryCap = Util.clamp(c.farm.masteryCap, 1, 600)
    c.farm.levelFloor = Util.clamp(c.farm.levelFloor, 1, 3000)
    c.farm.levelCeil = Util.clamp(c.farm.levelCeil, c.farm.levelFloor, 3000)
    c.stats.melee = Util.clamp(c.stats.melee, 0, 4000)
    c.stats.defense = Util.clamp(c.stats.defense, 0, 4000)
    c.stats.sword = Util.clamp(c.stats.sword, 0, 4000)
    c.stats.gun = Util.clamp(c.stats.gun, 0, 4000)
    c.stats.fruit = Util.clamp(c.stats.fruit, 0, 4000)
    c.util.aimFov = Util.clamp(c.util.aimFov, 10, 400)
    c.util.aimSmooth = Util.clamp(c.util.aimSmooth, 0.02, 1)
    c.util.espDistance = Util.clamp(c.util.espDistance, 0, 2000)
    c.util.espCap = Util.clamp(c.util.espCap, 0, 300)
    c.util.hopMinPlayers = Util.clamp(c.util.hopMinPlayers, 0, 50)
    c.util.hopMaxPing = Util.clamp(c.util.hopMaxPing, 20, 999)
end

local function configSet(path, value)
    local node = Config.data
    for i = 1, #path - 1 do
        local key = path[i]
        if type(node[key]) ~= "table" then node[key] = {} end
        node = node[key]
    end
    node[path[#path]] = value
    Config.dirty = true
    clampAll()
end

local function configGet(path)
    local node = Config.data
    for i = 1, #path do
        if type(node) ~= "table" then return nil end
        node = node[path[i]]
    end
    return node
end

local function pruneUnknown(template, candidate)
    local out = {}
    for k, v in pairs(template) do
        local got = candidate[k]
        if type(v) == "table" then
            if type(got) == "table" then out[k] = pruneUnknown(v, got) else out[k] = Util.deepCopy(v) end
        else
            if type(got) == type(v) then out[k] = got else out[k] = v end
        end
    end
    return out
end

local function configLoad()
    if not PLATFORM.fs then return end
    local okExists, exists = safeCall(CAP.isfile, CONFIG_FILE)
    if not okExists or not exists then return end
    local okRead, raw = safeCall(CAP.readfile, CONFIG_FILE)
    if not okRead or type(raw) ~= "string" or #raw == 0 then return end
    local okDec, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
    if not okDec or type(decoded) ~= "table" then return end
    Config.data = pruneUnknown(DEFAULTS, decoded)
    Config.fromDisk = true
end

local function configSave()
    if not PLATFORM.fs then return false end
    local okEnc, encoded = pcall(function() return HttpService:JSONEncode(Config.data) end)
    if not okEnc then return false end
    local ok = safeCall(CAP.writefile, CONFIG_FILE, encoded)
    if ok then Config.dirty = false end
    return ok
end

configLoad()
clampAll()

local Discovery = {
    remoteCache = {},
    folderCache = {},
    guiCache = {},
    lru = Util.newLRU(PLATFORM.mobile and 400 or 800),
    lastSweep = 0,
}

local REMOTE_ROOT = ReplicatedStorage and (ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage)

local function matchPattern(name, pattern)
    name = string.lower(name)
    pattern = string.lower(pattern)
    if string.find(name, pattern, 1, true) then return true end
    local stripped = string.gsub(name, "[^%a]", "")
    local ps = string.gsub(pattern, "[^%a]", "")
    if ps ~= "" and string.find(stripped, ps, 1, true) then return true end
    return false
end

function Discovery.resolveRemote(patterns)
    local key = table.concat(patterns, "|")
    local cached = Discovery.remoteCache[key]
    if cached and cached.Parent then return cached end
    local roots = { REMOTE_ROOT, ReplicatedStorage }
    for r = 1, #roots do
        local root = roots[r]
        if root then
            local ok, kids = pcall(function() return root:GetDescendants() end)
            if ok and kids then
                for i = 1, #kids do
                    local inst = kids[i]
                    if inst and (inst:IsA("RemoteFunction") or inst:IsA("RemoteEvent")) then
                        for p = 1, #patterns do
                            if matchPattern(inst.Name, patterns[p]) then
                                Discovery.remoteCache[key] = inst
                                return inst
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

function Discovery.resolveFolder(paths)
    local key = table.concat(paths, "/")
    local cached = Discovery.folderCache[key]
    if cached and cached.Parent then return cached end
    for i = 1, #paths do
        local segments = {}
        for seg in string.gmatch(paths[i], "[^%.]+") do table.insert(segments, seg) end
        local node = (segments[1] == "workspace" or segments[1] == "Workspace") and Workspace or ReplicatedStorage
        local startIdx = 1
        if segments[1] == "workspace" or segments[1] == "Workspace" then startIdx = 2 end
        local valid = true
        for s = startIdx, #segments do
            local ok, child = pcall(function() return node:FindFirstChild(segments[s]) end)
            if not ok or not child then valid = false break end
            node = child
        end
        if valid and node then
            Discovery.folderCache[key] = node
            return node
        end
    end
    return nil
end

function Discovery.resolveGuiPath(...)
    local segments = { ... }
    local key = table.concat(segments, "/")
    local cached = Discovery.guiCache[key]
    if cached and cached.Parent then return cached end
    local pg = LP and LP:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil end
    local node = pg
    for i = 1, #segments do
        local ok, child = pcall(function() return node:FindFirstChild(segments[i]) end)
        if not ok or not child then return nil end
        node = child
    end
    Discovery.guiCache[key] = node
    return node
end

function Discovery.sweep()
    local now = os.clock()
    if now - Discovery.lastSweep < 30 then return end
    Discovery.lastSweep = now
    for key, inst in pairs(Discovery.remoteCache) do
        if not inst or not inst.Parent then Discovery.remoteCache[key] = nil end
    end
    for key, inst in pairs(Discovery.folderCache) do
        if not inst or not inst.Parent then Discovery.folderCache[key] = nil end
    end
    for key, inst in pairs(Discovery.guiCache) do
        if not inst or not inst.Parent then Discovery.guiCache[key] = nil end
    end
end

local REMOTE_PATTERNS = {
    cmd = { "CommF_", "CommF", "RemoteFunction", "Main" },
    event = { "CommE_", "CommE", "RemoteEvent" },
}

local STRIKE = { cmd = 0, event = 0 }
local STRIKE_LIMIT = 3

function Discovery.command() return Discovery.resolveRemote(REMOTE_PATTERNS.cmd) end
function Discovery.event() return Discovery.resolveRemote(REMOTE_PATTERNS.event) end

function Discovery.invoke(...)
    if STRIKE.cmd >= STRIKE_LIMIT then return nil end
    local r = Discovery.command()
    if not r then return nil end
    local ok, a, b, c = pcall(function(...) return r:InvokeServer(...) end, ...)
    if ok then
        STRIKE.cmd = 0
        return a, b, c
    end
    STRIKE.cmd = STRIKE.cmd + 1
    return nil
end

function Discovery.fire(...)
    if STRIKE.event >= STRIKE_LIMIT then return false end
    local e = Discovery.event()
    if not e then return false end
    local ok = pcall(function(...) e:FireServer(...) end, ...)
    if ok then
        STRIKE.event = 0
        return true
    end
    STRIKE.event = STRIKE.event + 1
    return false
end

local ISLANDS = {
    { name = "Bandits", sea = 1, min = 1, max = 9, mobs = { "Bandit" }, xp = 150 },
    { name = "Monkeys", sea = 1, min = 10, max = 14, mobs = { "Monkey" }, xp = 500 },
    { name = "Brutes", sea = 1, min = 15, max = 29, mobs = { "Brute" }, xp = 900 },
    { name = "Pirates", sea = 1, min = 30, max = 59, mobs = { "Pirate" }, xp = 1800 },
    { name = "Marines", sea = 1, min = 60, max = 89, mobs = { "Marine" }, xp = 3200 },
    { name = "Knuckles", sea = 1, min = 90, max = 99, mobs = { "Knuckles" }, xp = 6000 },
    { name = "Desert Bandits", sea = 1, min = 100, max = 119, mobs = { "Desert Bandit" }, xp = 7400 },
    { name = "Desert Officers", sea = 1, min = 120, max = 149, mobs = { "Desert Officer" }, xp = 9800 },
    { name = "Desert Soldiers", sea = 1, min = 150, max = 174, mobs = { "Desert Soldier" }, xp = 12400 },
    { name = "Snow Bandits", sea = 1, min = 175, max = 189, mobs = { "Snow Bandit" }, xp = 15000 },
    { name = "Snowmen", sea = 1, min = 190, max = 199, mobs = { "Snowman" }, xp = 17800 },
    { name = "Snow Troops", sea = 1, min = 200, max = 224, mobs = { "Snow Troop" }, xp = 20500 },
    { name = "Marine Captain", sea = 1, min = 225, max = 239, mobs = { "Marine Captain" }, xp = 23800 },
    { name = "Marine Commander", sea = 1, min = 240, max = 249, mobs = { "Marine Commander" }, xp = 26400 },
    { name = "Marine Officer", sea = 1, min = 250, max = 274, mobs = { "Marine Officer" }, xp = 29800 },
    { name = "Marine General", sea = 1, min = 275, max = 299, mobs = { "Marine General" }, xp = 33500 },
    { name = "Sky Bandits", sea = 1, min = 300, max = 324, mobs = { "Sky Bandit" }, xp = 38000 },
    { name = "Sky Pirates", sea = 1, min = 325, max = 349, mobs = { "Sky Pirate" }, xp = 42000 },
    { name = "Galley Pirates", sea = 1, min = 350, max = 374, mobs = { "Galley Pirate" }, xp = 46000 },
    { name = "Galley Captains", sea = 1, min = 375, max = 399, mobs = { "Galley Captain" }, xp = 50500 },
    { name = "Upper Sky", sea = 1, min = 400, max = 449, mobs = { "Fighter" }, xp = 58000 },
    { name = "Fountain City", sea = 1, min = 450, max = 624, mobs = { "Fountain Guard" }, xp = 72000 },
    { name = "Fountain City Raid", sea = 1, min = 625, max = 699, mobs = { "Fountain Guard" }, xp = 96000 },
    { name = "Kingdom of Rose", sea = 2, min = 700, max = 849, mobs = { "Raider" }, xp = 130000 },
    { name = "Green Zone", sea = 2, min = 850, max = 999, mobs = { "Mercenary" }, xp = 158000 },
    { name = "Graveyard", sea = 2, min = 1000, max = 1099, mobs = { "Zombie" }, xp = 186000 },
    { name = "Snow Mountain", sea = 2, min = 1100, max = 1249, mobs = { "Snow Trooper" }, xp = 224000 },
    { name = "Hot and Cold", sea = 2, min = 1250, max = 1349, mobs = { "Magma Ninja" }, xp = 262000 },
    { name = "Cursed Ship", sea = 2, min = 1350, max = 1424, mobs = { "Cursed Zombie" }, xp = 298000 },
    { name = "Ice Castle", sea = 2, min = 1425, max = 1499, mobs = { "Ice Guardian" }, xp = 334000 },
    { name = "Forgotten Island", sea = 2, min = 1500, max = 1599, mobs = { "Forgotten Warrior" }, xp = 372000 },
    { name = "Port Town", sea = 3, min = 1600, max = 1749, mobs = { "Pirate Raider" }, xp = 412000 },
    { name = "Hydra Island", sea = 3, min = 1750, max = 1849, mobs = { "Hydra Raider" }, xp = 458000 },
    { name = "Great Tree", sea = 3, min = 1850, max = 1949, mobs = { "Tree Guard" }, xp = 502000 },
    { name = "Floating Turtle", sea = 3, min = 1950, max = 2049, mobs = { "Turtle Warrior" }, xp = 548000 },
    { name = "Haunted Castle", sea = 3, min = 2050, max = 2149, mobs = { "Castle Guard" }, xp = 596000 },
    { name = "Sea of Treats", sea = 3, min = 2150, max = 2249, mobs = { "Candy Warrior" }, xp = 644000 },
    { name = "Castle on the Sea", sea = 3, min = 2250, max = 2349, mobs = { "Sea Castle Knight" }, xp = 694000 },
    { name = "Kitsune Island", sea = 3, min = 2350, max = 2449, mobs = { "Kitsune Guard" }, xp = 748000 },
    { name = "Tiki Outpost", sea = 3, min = 2450, max = 2549, mobs = { "Tiki Warrior" }, xp = 802000 },
    { name = "Sanguine Valley", sea = 3, min = 2550, max = 2699, mobs = { "Sanguine Cultist" }, xp = 872000 },
    { name = "Island Secrets I", sea = 3, min = 2700, max = 2849, mobs = { "Secret Sentinel" }, xp = 948000 },
    { name = "Island Secrets II", sea = 3, min = 2850, max = 2999, mobs = { "Secret Sentinel" }, xp = 1040000 },
    { name = "Island Secrets III", sea = 3, min = 3000, max = 3000, mobs = { "Overcharged Elite" }, xp = 1120000 },
}

local BOSSES = {
    { name = "The Gorilla King", island = "Jungle", level = 28, respawn = 180 },
    { name = "Gorilla King", island = "Pirates", level = 40, respawn = 180 },
    { name = "Diamond", island = "Marines", level = 75, respawn = 240 },
    { name = "Don Swan", island = "Kingdom of Rose", level = 800, respawn = 300 },
    { name = "Darkbeard", island = "Graveyard", level = 1000, respawn = 360 },
    { name = "Zioles", island = "Middletown", level = 1200, respawn = 900 },
    { name = "Frost King", island = "Snow Mountain", level = 1250, respawn = 300 },
    { name = "Order", island = "Ice Castle", level = 1400, respawn = 420 },
    { name = "Cursed Rota", island = "Cursed Ship", level = 1450, respawn = 420 },
    { name = "Hydra Leader", island = "Hydra Island", level = 1800, respawn = 420 },
    { name = "Soul Reaper", island = "Haunted Castle", level = 2100, respawn = 540 },
    { name = "Cake Prince", island = "Sea of Treats", level = 2180, respawn = 600 },
    { name = "Dough King", island = "Sea of Treats", level = 2200, respawn = 600 },
    { name = "Rip Indra", island = "Castle on the Sea", level = 2300, respawn = 600 },
    { name = "Longma", island = "Kitsune Island", level = 2400, respawn = 660 },
}

local FIGHTING_STYLES = {
    { name = "Dark Step", cost = 150000, level = 90 },
    { name = "Water Kung Fu", cost = 750000, level = 250 },
    { name = "Dragon Breath", cost = 1500000, level = 400 },
    { name = "Electric Claw", cost = 3000000, level = 450 },
    { name = "Superhuman", cost = 3000000, level = 300 },
    { name = "Death Step", cost = 3500000, level = 850 },
    { name = "Sharkman Karate", cost = 4000000, level = 1000 },
    { name = "Dragon Talon", cost = 5000000, level = 1500 },
    { name = "Godhuman", cost = 8000000, level = 2200 },
}

local GUNS = {
    { name = "Flintlock", cost = 3200, level = 1 },
    { name = "Musket", cost = 9000, level = 30 },
    { name = "Dual Flintlock", cost = 15000, level = 50 },
    { name = "Serpent Bow", cost = 850000, level = 400 },
    { name = "Soul Cane", cost = 1200000, level = 600 },
    { name = "Cannon", cost = 1800000, level = 800 },
    { name = "Kabucha", cost = 2400000, level = 1000 },
    { name = "Bazooka", cost = 3200000, level = 1200 },
}

local SWORDS = {
    { name = "Pipe", cost = 100, level = 1 },
    { name = "Katana", cost = 1000, level = 1 },
    { name = "Cutlass", cost = 5000, level = 1 },
    { name = "Iron Mace", cost = 30000, level = 15 },
    { name = "Triple Katana", cost = 120000, level = 60 },
    { name = "Dual Katana", cost = 300000, level = 120 },
    { name = "Shark Saw", cost = 900000, level = 450 },
    { name = "Soul Cane", cost = 1200000, level = 600 },
    { name = "Saber", cost = 0, level = 200 },
}

local LEGENDARY = {
    { name = "Dark Blade", level = 900 },
    { name = "Dragon Trident", level = 1100 },
    { name = "Shark Anchor", level = 1300 },
    { name = "Bisento", level = 1400 },
    { name = "Pole v2", level = 1900 },
    { name = "Hollow Scythe", level = 2000 },
    { name = "Yama", level = 2300 },
    { name = "Tushita", level = 2300 },
    { name = "Cursed Dual Katana", level = 2400 },
    { name = "True Triple Katana", level = 2500 },
}

local LEGENDARY_STEPS = {
    ["Dark Blade"] = { "Bandit", "Buy", "Claim" },
    ["Dragon Trident"] = { "Boss", "Claim" },
    ["Shark Anchor"] = { "Hunt", "Claim" },
    ["Bisento"] = { "Quest", "Claim" },
    ["Pole v2"] = { "Thunder", "Claim" },
    ["Hollow Scythe"] = { "Graveyard", "Awaken", "Claim" },
    ["Yama"] = { "Underwater", "TalkNPC", "CollectSword", "Sacrifice", "Claim" },
    ["Tushita"] = { "Portal", "TorchOrder", "GateOpen", "Claim" },
    ["Cursed Dual Katana"] = { "Yama", "Tushita", "Combine", "Claim" },
    ["True Triple Katana"] = { "Cursed", "TrueTriple", "Claim" },
}

local RACES = { "Human", "Rabbit", "Shark", "Angel", "Cyborg", "Ghoul", "Draco" }

local State = {
    level = 1,
    beli = 0,
    fragments = 0,
    bones = 0,
    tokens = 0,
    levelsGained = 0,
    multiplier = 1,
    currentTarget = "-",
    stateText = "idle",
    generation = 0,
    pausedUntil = 0,
    ping = 0,
    deaths = {},
}

local function char() return LP and LP.Character end

local function rootPart()
    local c = char()
    if not c then return nil end
    return c:FindFirstChild("HumanoidRootPart")
end

local function humanoid()
    local c = char()
    if not c then return nil end
    return c:FindFirstChildOfClass("Humanoid")
end

local function readLevel()
    local pg = LP and LP:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil end
    local ok, node = pcall(function()
        local main = pg:FindFirstChild("Main")
        if not main then return nil end
        return main:FindFirstChild("Level")
    end)
    if ok and node then
        local ok2, txt = pcall(function() return node:FindFirstChildOfClass("TextLabel") end)
        if ok2 and txt then
            local n = tonumber(string.match(txt.Text, "%d+"))
            if n then return n end
        end
    end
    local ok3, n3 = pcall(function()
        local c = LP.Character
        if not c then return nil end
        local ds = c:FindFirstChild("Data")
        if not ds then return nil end
        local lv = ds:FindFirstChild("Level")
        return lv and lv.Value
    end)
    if ok3 and type(n3) == "number" then return n3 end
    return nil
end

local function readBeli()
    local pg = LP and LP:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil end
    local ok, node = pcall(function()
        local main = pg:FindFirstChild("Main")
        if not main then return nil end
        return main:FindFirstChild("Beli")
    end)
    if ok and node then
        local ok2, txt = pcall(function() return node:FindFirstChildOfClass("TextLabel") end)
        if ok2 and txt then
            return tonumber(string.gsub(txt.Text, "[^%d]", ""))
        end
    end
    return nil
end

local function refreshState()
    local lv = readLevel()
    if lv then
        if lv > State.level then
            State.levelsGained = State.levelsGained + (lv - State.level)
        end
        State.level = lv
    end
    local b = readBeli()
    if b then State.beli = b end
    if Stats then
        local ok, v = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
        if ok and type(v) == "number" then State.ping = math.floor(v) end
    end
end

local Movement = {
    gen = 0,
    boosted = false,
}

function Movement.setWalkSpeed(v)
    local hum = humanoid()
    if not hum then return false end
    return pcall(function() hum.WalkSpeed = Util.clamp(v, 0, 50) end)
end

function Movement.setJumpPower(v)
    local hum = humanoid()
    if not hum then return false end
    if hum.UseJumpPower ~= nil then pcall(function() hum.UseJumpPower = true end) end
    return pcall(function() hum.JumpPower = Util.clamp(v, 0, 50) end)
end

function Movement.restore()
    Movement.setWalkSpeed(16)
    Movement.setJumpPower(50)
    Movement.boosted = false
end

function Movement.cframeTo(pos)
    local rp = rootPart()
    if not rp then return false end
    return pcall(function() rp.CFrame = CFrame.new(pos) end)
end

function Movement.stepTo(pos, generation)
    if generation and generation ~= State.generation then return false end
    local rp = rootPart()
    if not rp then return false end
    local from = rp.Position
    local delta = pos - from
    local dist = delta.Magnitude
    if dist <= 40 then return Movement.cframeTo(pos) end
    local steps = math.ceil(dist / 40)
    local dir = delta.Unit
    for i = 1, steps do
        if generation and generation ~= State.generation then return false end
        local target = from + dir * math.min(dist, 40 * i)
        if not Movement.cframeTo(target) then return false end
        task.wait(TICK * 2)
    end
    return true
end

function Movement.snapTo(pos) return Movement.cframeTo(pos) end

function Movement.boost(amount, duration)
    local hum = humanoid()
    if not hum then return end
    Movement.boosted = true
    local start = os.clock()
    while os.clock() - start < duration do
        local t = (os.clock() - start) / duration
        local v = 16 + (Util.clamp(amount, 16, 50) - 16) * math.min(t * 4, 1)
        pcall(function() hum.WalkSpeed = v end)
        task.wait(0.25)
    end
    pcall(function() hum.WalkSpeed = 16 end)
    Movement.boosted = false
end

local Combat = {
    measuredCooldown = 0.55,
    lastAttack = 0,
    attackCount = 0,
}

function Combat.ensureMelee()
    local c = char()
    if not c then return nil end
    local equipped = c:FindFirstChildOfClass("Tool")
    if equipped then return equipped end
    local backpack = c:FindFirstChildOfClass("Backpack")
    if not backpack then return nil end
    for _, t in ipairs(backpack:GetChildren()) do
        if t:IsA("Tool") then
            local hum = c:FindFirstChildOfClass("Humanoid")
            if hum then
                local ok = pcall(function() hum:EquipTool(t) end)
                if ok then
                    task.wait(TICK * 2)
                    return t
                end
            end
            return nil
        end
    end
    return nil
end

function Combat.attack(target, generation)
    if generation and generation ~= State.generation then return false end
    local now = os.clock()
    if now - Combat.lastAttack < Combat.measuredCooldown * 0.92 then return false end
    local fired = false
    if target and target.Parent then
        local e = Discovery.event()
        if e then
            local ok = pcall(function() e:FireServer("Attack", target) end)
            if ok then fired = true end
        end
    end
    if not fired and VirtualUser then
        local ok = pcall(function()
            VirtualUser:Button1Down(Vector2.new(0.5, 0.5))
        end)
        if ok then
            task.wait(0.05)
            pcall(function() VirtualUser:Button1Up(Vector2.new(0.5, 0.5)) end)
            fired = true
        end
    end
    if fired then
        local dt = now - Combat.lastAttack
        if Combat.lastAttack > 0 and dt > 0.05 and dt < 3 then
            Combat.measuredCooldown = Combat.measuredCooldown * 0.8 + dt * 0.2
        end
        Combat.lastAttack = now
        Combat.attackCount = Combat.attackCount + 1
    end
    return fired
end

function Combat.measure()
    local samples = 6
    local total = 0
    for i = 1, samples do
        local t0 = os.clock()
        Combat.attack(nil, State.generation)
        total = total + (os.clock() - t0)
        task.wait(TICK * 3)
    end
    Combat.measuredCooldown = Util.clamp(total / samples + 0.08, 0.15, 2.0)
    return Combat.measuredCooldown
end

local function nearestEnemy(maxDist, filterFn)
    local folder = Discovery.resolveFolder({ "workspace.Enemies", "workspace.Living", "workspace.Mobs" })
    if not folder then return nil end
    local rp = rootPart()
    if not rp then return nil end
    local best, bestDist = nil, maxDist or math.huge
    local ok, kids = pcall(function() return folder:GetChildren() end)
    if not ok or not kids then return nil end
    for i = 1, math.min(#kids, 200) do
        local m = kids[i]
        local hum = m:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            local allowed = true
            if filterFn then
                local okF, res = pcall(filterFn, m, hum)
                allowed = okF and res or false
            end
            if allowed then
                local part = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Head")
                if part then
                    local d = (part.Position - rp.Position).Magnitude
                    if d < bestDist then bestDist, best = d, m end
                end
            end
        end
    end
    return best, bestDist
end

local Quests = {
    active = nil,
    killTimes = {},
    completed = 0,
}

local function questGui() return Discovery.resolveGuiPath("Main", "Quest") end

function Quests.readState()
    local g = questGui()
    if not g then return "unknown" end
    local ok, txt = pcall(function()
        local t = g:FindFirstChildOfClass("TextLabel") or g:FindFirstChild("Title")
        return t and t.Text or nil
    end)
    if not ok or not txt then return "unknown" end
    local low = string.lower(txt)
    if string.find(low, "no quest", 1, true) then return "none" end
    if string.find(low, "complete", 1, true) then return "complete" end
    if string.find(low, "progress", 1, true) then return "progress" end
    return "unknown"
end

function Quests.accept(island)
    if not island then return false end
    local ok = Discovery.invoke("StartQuest", island.name, island.min)
    if ok then
        Quests.active = island
        return true
    end
    return false
end

function Quests.turnIn()
    local ok = Discovery.invoke("CompleteQuest")
    if ok then
        Quests.completed = Quests.completed + 1
        Quests.active = nil
        return true
    end
    return false
end

function Quests.islandPosition(island)
    if not island then return nil end
    local map = Workspace and Workspace:FindFirstChild("Map")
    if not map then return nil end
    local names = { island.name, string.gsub(island.name, "%s+", "") }
    for i = 1, #names do
        local ok, node = pcall(function() return map:FindFirstChild(names[i], true) end)
        if ok and node then
            local okP, cf = pcall(function()
                if node:IsA("Model") then return node:GetPivot() end
                if node:IsA("BasePart") then return node.CFrame end
                return nil
            end)
            if okP and cf then return cf.Position end
            local okC, kids = pcall(function() return node:GetChildren() end)
            if okC and kids then
                for k = 1, #kids do
                    if kids[k]:IsA("BasePart") then return kids[k].Position end
                end
            end
        end
    end
    return nil
end

local Router = {
    lastPick = 0,
    cooldown = 1.0,
    current = nil,
}

local function ema(prev, sample, weight)
    if not prev then return sample end
    return prev * (1 - weight) + sample * weight
end

function Router.scoreIsland(island, pos)
    local rp = rootPart()
    if not rp or not pos then return 0 end
    local travel = (pos - rp.Position).Magnitude / 50
    local kill = Quests.killTimes[island.mobs[1]] or 12
    local cycle = kill * 8 + travel * 2 + 4
    if cycle <= 0 then return 0 end
    return island.xp / cycle
end

function Router.pick()
    local now = os.clock()
    if now - Router.lastPick < Router.cooldown then return Router.current end
    Router.lastPick = now
    local level = State.level
    local best, bestScore = nil, -1
    for i = 1, #ISLANDS do
        local isl = ISLANDS[i]
        if level >= isl.min and level <= isl.max then
            local s = Router.scoreIsland(isl, Quests.islandPosition(isl))
            if s > bestScore then bestScore, best = s, isl end
        end
    end
    if not best then
        for i = #ISLANDS, 1, -1 do
            if ISLANDS[i].min <= level then best = ISLANDS[i] break end
        end
    end
    Router.current = best
    return best
end

local Leveling = {
    active = false,
    startedAt = os.clock(),
    bossTimers = {},
    hopLog = {},
}

function Leveling.xpPerHour()
    local elapsed = os.clock() - Leveling.startedAt
    if elapsed < 5 then return 0 end
    if State.levelsGained <= 0 then return 0 end
    return math.floor(State.levelsGained * 50000 / elapsed * 3600)
end

function Leveling.canHop()
    local now = os.clock()
    local count = 0
    for i = 1, #Leveling.hopLog do
        if Leveling.hopLog[i] >= now - 60 then count = count + 1 end
    end
    return count < Config.data.leveling.hopCapPerMinute
end

function Leveling.recordHop()
    local now = os.clock()
    table.insert(Leveling.hopLog, now)
    local kept = {}
    for i = 1, #Leveling.hopLog do
        if Leveling.hopLog[i] >= now - 60 then table.insert(kept, Leveling.hopLog[i]) end
    end
    Leveling.hopLog = kept
    return #kept
end

function Leveling.routeOnce(generation)
    if generation ~= State.generation then return end
    local island = Router.pick()
    if not island then
        State.stateText = "no route"
        return
    end
    local pos = Quests.islandPosition(island)
    if not pos then
        State.stateText = "island unresolved"
        return
    end
    local rp = rootPart()
    if not rp then return end
    if (pos - rp.Position).Magnitude > 80 then
        State.stateText = "travel " .. island.name
        Movement.stepTo(pos, generation)
        Util.humanWait(0.4)
    end
    local qs = Quests.readState()
    if qs == "complete" then
        Quests.turnIn()
        Util.humanWait(0.6)
        return
    end
    if qs ~= "progress" then
        Quests.accept(island)
        Util.humanWait(0.8)
    end
    State.stateText = "farm " .. island.name
    local killStart = os.clock()
    local kills = 0
    while kills < 8 do
        if generation ~= State.generation then return end
        if not Leveling.active then return end
        if State.pausedUntil > 0 and os.clock() < State.pausedUntil then
            Util.humanWait(0.4)
            continue
        end
        local target = nearestEnemy(300, function(mob, hum)
            local lvl = 0
            local lv = mob:FindFirstChild("Level")
            if lv and type(lv.Value) == "number" then lvl = lv.Value end
            if lvl > 0 and (lvl < Config.data.farm.levelFloor or lvl > Config.data.farm.levelCeil) then
                return false
            end
            for _, ignored in ipairs(Config.data.farm.ignoreList) do
                if string.find(string.lower(mob.Name), string.lower(ignored), 1, true) then return false end
            end
            return true
        end)
        if target then
            State.currentTarget = target.Name
            local tp = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Head")
            local th = target:FindFirstChildOfClass("Humanoid")
            if th then pcall(function() th.BreakJointsOnDeath = false end) end
            if tp then Movement.stepTo(tp.Position + Vector3.new(0, 2, 0), generation) end
            Combat.ensureMelee()
            Combat.attack(target, generation)
            Util.humanWait(Combat.measuredCooldown)
            if not th or th.Health <= 0 then
                kills = kills + 1
                local key = island.mobs[1]
                Quests.killTimes[key] = ema(Quests.killTimes[key], (os.clock() - killStart) / kills, 0.35)
            end
        else
            Util.humanWait(0.3)
        end
        refreshState()
    end
    Quests.turnIn()
    Util.humanWait(0.7)
end

function Leveling.loop(generation)
    Leveling.active = true
    Leveling.startedAt = os.clock()
    while Leveling.active do
        if generation ~= State.generation then break end
        if State.pausedUntil > 0 and os.clock() < State.pausedUntil then
            Util.humanWait(0.5)
            continue
        end
        pcall(Leveling.routeOnce, generation)
        Util.humanWait(0.25)
    end
end

function Leveling.stop() Leveling.active = false end

local Farm = {
    active = false,
    bonesFound = 0,
    chestsFound = 0,
    fruitFound = 0,
}

function Farm.mobLoop(generation)
    while Farm.active and Config.data.farm.mobs do
        if generation ~= State.generation then break end
        if State.pausedUntil > 0 and os.clock() < State.pausedUntil then Util.humanWait(0.4) continue end
        local target = nearestEnemy(320)
        if target then
            State.currentTarget = target.Name
            local tp = target:FindFirstChild("HumanoidRootPart")
            if tp then Movement.stepTo(tp.Position, generation) end
            Combat.ensureMelee()
            Combat.attack(target, generation)
        end
        Util.humanWait(Combat.measuredCooldown)
    end
end

function Farm.bossLoop(generation)
    while Farm.active and Config.data.farm.bosses do
        if generation ~= State.generation then break end
        local found = nil
        local enemies = Discovery.resolveFolder({ "workspace.Enemies", "workspace.Living" })
        if enemies then
            local ok, kids = pcall(function() return enemies:GetChildren() end)
            if ok and kids then
                for i = 1, math.min(#kids, 200) do
                    local m = kids[i]
                    for b = 1, #BOSSES do
                        if string.find(m.Name, BOSSES[b].name, 1, true) then
                            local hum = m:FindFirstChildOfClass("Humanoid")
                            if hum and hum.Health > 0 then found = m break end
                        end
                    end
                    if found then break end
                end
            end
        end
        if found then
            local tp = found:FindFirstChild("HumanoidRootPart")
            if tp then Movement.stepTo(tp.Position, generation) end
            Combat.ensureMelee()
            Combat.attack(found, generation)
            State.currentTarget = found.Name
        elseif Config.data.leveling.hopForBoss and Leveling.canHop() then
            Leveling.recordHop()
            Util.humanWait(Util.jitter(1.4, 0.5))
        end
        Util.humanWait(0.4)
    end
end

function Farm.chestLoop(generation)
    while Farm.active and Config.data.farm.chests do
        if generation ~= State.generation then break end
        local chests = Discovery.resolveFolder({ "workspace.Chests", "workspace.Map.Chests", "workspace.Items" })
        local rp = rootPart()
        if chests and rp then
            local ok, kids = pcall(function() return chests:GetChildren() end)
            if ok and kids then
                local best, bestD = nil, math.huge
                for i = 1, math.min(#kids, 200) do
                    local c = kids[i]
                    local p = nil
                    if c:IsA("BasePart") then
                        p = c.Position
                    else
                        local hrp = c:FindFirstChild("HumanoidRootPart") or c:FindFirstChildWhichIsA("BasePart")
                        if hrp then p = hrp.Position end
                    end
                    if p then
                        local d = (p - rp.Position).Magnitude
                        if d < bestD then bestD, best = d, c end
                    end
                end
                if best and bestD < 400 then
                    local p2 = best:IsA("BasePart") and best.Position or (best:FindFirstChild("HumanoidRootPart") and best.HumanoidRootPart.Position)
                    if p2 then
                        Movement.stepTo(p2, generation)
                        Farm.chestsFound = Farm.chestsFound + 1
                    end
                end
            end
        end
        Util.humanWait(0.8)
    end
end

function Farm.bonesLoop(generation)
    local counted = 0
    while Farm.active and Config.data.farm.bones do
        if generation ~= State.generation then break end
        local enemies = Discovery.resolveFolder({ "workspace.Enemies" })
        if enemies then
            local ok, kids = pcall(function() return enemies:GetChildren() end)
            if ok and kids then
                for i = 1, math.min(#kids, 200) do
                    local m = kids[i]
                    local low = string.lower(m.Name)
                    if string.find(low, "skeleton", 1, true) or string.find(low, "zombie", 1, true) then
                        local hum = m:FindFirstChildOfClass("Humanoid")
                        if hum and hum.Health > 0 then
                            local tp = m:FindFirstChild("HumanoidRootPart")
                            if tp then Movement.stepTo(tp.Position, generation) end
                            Combat.ensureMelee()
                            Combat.attack(m, generation)
                            counted = counted + 1
                            break
                        end
                    end
                end
            end
        end
        Farm.bonesFound = counted
        Util.humanWait(0.5)
    end
end

function Farm.masteryLoop(generation)
    while Farm.active and Config.data.farm.mastery do
        if generation ~= State.generation then break end
        Combat.ensureMelee()
        local target = nearestEnemy(200, function(mob, hum) return hum.MaxHealth > 500 end)
        if target then
            local hum = target:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > hum.MaxHealth * 0.25 then
                Combat.attack(target, generation)
                State.currentTarget = target.Name
            else
                local other = nearestEnemy(250, function(m, h) return h.MaxHealth > 500 and m ~= target end)
                if other then
                    State.currentTarget = other.Name
                    local tp = other:FindFirstChild("HumanoidRootPart")
                    if tp then Movement.stepTo(tp.Position, generation) end
                    Combat.attack(other, generation)
                end
            end
        end
        Util.humanWait(Combat.measuredCooldown)
    end
end

function Farm.fruitLoop(generation)
    while Farm.active and Config.data.farm.fruit do
        if generation ~= State.generation then break end
        local fruits = Discovery.resolveFolder({ "workspace.Fruit", "workspace.Fruits" })
        local rp = rootPart()
        if fruits and rp then
            local ok, kids = pcall(function() return fruits:GetChildren() end)
            if ok and kids then
                for i = 1, math.min(#kids, 60) do
                    local f = kids[i]
                    local part = f:IsA("BasePart") and f or f:FindFirstChildWhichIsA("BasePart")
                    if part then
                        local filt = Config.data.util.fruitFilter
                        if filt == "" or string.find(string.lower(f.Name), string.lower(filt), 1, true) then
                            Movement.stepTo(part.Position, generation)
                            Farm.fruitFound = Farm.fruitFound + 1
                            if Config.data.util.autoStore then
                                Discovery.invoke("StoreFruit", f.Name)
                            end
                            break
                        end
                    end
                end
            end
        end
        Util.humanWait(0.9)
    end
end

function Farm.fishingLoop(generation)
    while Farm.active and Config.data.farm.fishing do
        if generation ~= State.generation then break end
        local c = char()
        local hasRod = false
        if c then
            for _, t in ipairs(c:GetChildren()) do
                if t:IsA("Tool") and string.find(string.lower(t.Name), "rod", 1, true) then hasRod = true break end
            end
            local bp = c:FindFirstChildOfClass("Backpack")
            if bp then
                for _, t in ipairs(bp:GetChildren()) do
                    if t:IsA("Tool") and string.find(string.lower(t.Name), "rod", 1, true) then hasRod = true break end
                end
            end
        end
        if not hasRod then
            State.stateText = "no rod"
            Util.humanWait(2)
            continue
        end
        Discovery.invoke("Fishing", "Cast")
        Util.humanWait(Util.jitter(3.5, 0.4))
        Discovery.invoke("Fishing", "Reel")
        Util.humanWait(Util.jitter(1.2, 0.3))
    end
end

function Farm.seaBeastLoop(generation)
    while Farm.active and Config.data.farm.seaBeast do
        if generation ~= State.generation then break end
        local beasts = Discovery.resolveFolder({ "workspace.SeaBeasts", "workspace.Enemies" })
        if beasts then
            local ok, kids = pcall(function() return beasts:GetChildren() end)
            if ok and kids then
                for i = 1, math.min(#kids, 60) do
                    local b = kids[i]
                    local low = string.lower(b.Name)
                    if string.find(low, "beast", 1, true) or string.find(low, "kraken", 1, true) then
                        local hum = b:FindFirstChildOfClass("Humanoid")
                        if hum and hum.Health > 0 then
                            local myHum = humanoid()
                            if myHum and myHum.Health < myHum.MaxHealth * 0.35 then
                                State.stateText = "beast retreat"
                                break
                            end
                            local tp = b:FindFirstChild("HumanoidRootPart")
                            if tp then Movement.stepTo(tp.Position, generation) end
                            Combat.attack(b, generation)
                        end
                    end
                end
            end
        end
        Util.humanWait(0.5)
    end
end

function Farm.eliteLoop(generation)
    while Farm.active and Config.data.farm.elites do
        if generation ~= State.generation then break end
        local enemies = Discovery.resolveFolder({ "workspace.Enemies" })
        if enemies then
            local ok, kids = pcall(function() return enemies:GetChildren() end)
            if ok and kids then
                for i = 1, math.min(#kids, 200) do
                    local m = kids[i]
                    if string.find(string.lower(m.Name), "elite", 1, true) then
                        local hum = m:FindFirstChildOfClass("Humanoid")
                        if hum and hum.Health > 0 then
                            local tp = m:FindFirstChild("HumanoidRootPart")
                            if tp then Movement.stepTo(tp.Position, generation) end
                            Combat.ensureMelee()
                            Combat.attack(m, generation)
                            State.currentTarget = m.Name
                            break
                        end
                    end
                end
            end
        end
        Util.humanWait(0.4)
    end
end

function Farm.magnetLoop(generation)
    while Farm.active and Config.data.farm.magnet do
        if generation ~= State.generation then break end
        local t = os.date("*t")
        if t.min >= 10 then
            State.stateText = "magnet window closed"
            Util.humanWait(5)
            continue
        end
        State.stateText = "magnet active"
        local enemies = Discovery.resolveFolder({ "workspace.Enemies" })
        if enemies then
            local ok, kids = pcall(function() return enemies:GetChildren() end)
            if ok and kids then
                local best, bestScore = nil, -1
                for i = 1, math.min(#kids, 200) do
                    local m = kids[i]
                    local hum = m:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        local score = 1
                        if string.find(m.Name, "Overcharged", 1, true) then score = 10 end
                        if string.find(string.lower(m.Name), "magnet", 1, true) then score = score + 5 end
                        if score > bestScore then bestScore, best = score, m end
                    end
                end
                if best then
                    local tp = best:FindFirstChild("HumanoidRootPart")
                    if tp then Movement.stepTo(tp.Position, generation) end
                    Combat.ensureMelee()
                    Combat.attack(best, generation)
                    State.currentTarget = best.Name
                end
            end
        end
        Util.humanWait(0.35)
    end
end

local Events = {
    raidActive = false,
}

function Events.startRaid(generation)
    Events.raidActive = true
    local fruit = Config.data.events.raidFruit
    while Events.raidActive do
        if generation ~= State.generation then break end
        Discovery.invoke("BlackbeardReward", "Raid", fruit)
        Util.humanWait(1.2)
        Discovery.invoke("RaiseFist")
        Util.humanWait(0.6)
        local map = Workspace and Workspace:FindFirstChild("Map")
        if map then
            local ok, kids = pcall(function() return map:GetChildren() end)
            if ok and kids then
                for i = 1, math.min(#kids, 60) do
                    local node = kids[i]
                    if string.find(string.lower(node.Name), "chest", 1, true) then
                        local part = node:IsA("BasePart") and node or node:FindFirstChildWhichIsA("BasePart")
                        if part then Movement.stepTo(part.Position, generation) end
                    end
                end
            end
        end
        Util.humanWait(1.0)
    end
end

function Events.factoryLoop(generation)
    while Config.data.events.factory do
        if generation ~= State.generation then break end
        Discovery.invoke("Factory", "Start")
        local target = nearestEnemy(400, function(m)
            return string.find(string.lower(m.Name), "core", 1, true) ~= nil
        end)
        if target then
            local tp = target:FindFirstChild("HumanoidRootPart")
            if tp then Movement.stepTo(tp.Position, generation) end
            Combat.ensureMelee()
            Combat.attack(target, generation)
        end
        Util.humanWait(0.6)
    end
end

function Events.seaEventsLoop(generation)
    while Config.data.events.seaEvents do
        if generation ~= State.generation then break end
        local map = Workspace and Workspace:FindFirstChild("Map")
        if map then
            local ok, kids = pcall(function() return map:GetChildren() end)
            if ok and kids then
                for i = 1, math.min(#kids, 120) do
                    local n = kids[i]
                    local low = string.lower(n.Name)
                    if string.find(low, "shark", 1, true) or string.find(low, "kraken", 1, true)
                        or string.find(low, "pirate", 1, true) or string.find(low, "ship", 1, true) then
                        local part = n:IsA("BasePart") and n or n:FindFirstChildWhichIsA("BasePart")
                        if part then Movement.stepTo(part.Position, generation) end
                    end
                end
            end
        end
        Util.humanWait(1.4)
    end
end

function Events.mirageLoop(generation)
    while Config.data.events.mirage do
        if generation ~= State.generation then break end
        local mirage = Workspace and Workspace:FindFirstChild("MirageIsland")
        if mirage then
            local chests = mirage:FindFirstChild("Chests") or mirage
            local ok, kids = pcall(function() return chests:GetChildren() end)
            if ok and kids then
                for i = 1, math.min(#kids, 60) do
                    local c = kids[i]
                    if string.find(string.lower(c.Name), "chest", 1, true) then
                        local part = c:IsA("BasePart") and c or c:FindFirstChildWhichIsA("BasePart")
                        if part then Movement.stepTo(part.Position, generation) end
                    end
                end
            end
        end
        Util.humanWait(1.0)
    end
end

function Events.kitsuneLoop(generation)
    while Config.data.events.kitsune do
        if generation ~= State.generation then break end
        Discovery.invoke("Kitsune", "Shrine")
        Util.humanWait(1.4)
        local enemies = Discovery.resolveFolder({ "workspace.Enemies" })
        if enemies then
            local ok, kids = pcall(function() return enemies:GetChildren() end)
            if ok and kids then
                for i = 1, math.min(#kids, 200) do
                    local m = kids[i]
                    local hum = m:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 and string.find(string.lower(m.Name), "kitsune", 1, true) then
                        local tp = m:FindFirstChild("HumanoidRootPart")
                        if tp then Movement.stepTo(tp.Position, generation) end
                        Combat.attack(m, generation)
                        break
                    end
                end
            end
        end
        Util.humanWait(0.7)
    end
end

function Events.castleLoop(generation)
    while Config.data.events.haunted or Config.data.events.cursedShip or Config.data.events.castleSea do
        if generation ~= State.generation then break end
        local targets = { "castle", "cursed", "ship", "haunted" }
        local enemies = Discovery.resolveFolder({ "workspace.Enemies" })
        local done = false
        if enemies then
            local ok, kids = pcall(function() return enemies:GetChildren() end)
            if ok and kids then
                for i = 1, math.min(#kids, 200) do
                    local m = kids[i]
                    local low = string.lower(m.Name)
                    for t = 1, #targets do
                        if string.find(low, targets[t], 1, true) then
                            local hum = m:FindFirstChildOfClass("Humanoid")
                            if hum and hum.Health > 0 then
                                local tp = m:FindFirstChild("HumanoidRootPart")
                                if tp then Movement.stepTo(tp.Position, generation) end
                                Combat.ensureMelee()
                                Combat.attack(m, generation)
                                done = true
                                break
                            end
                        end
                    end
                    if done then break end
                end
            end
        end
        Util.humanWait(0.5)
    end
end

function Events.raceTrialLoop(generation)
    while Config.data.events.raceTrial do
        if generation ~= State.generation then break end
        Discovery.invoke("Race", "Trial")
        Util.humanWait(2.0)
        local checkpoints = Workspace and Workspace:FindFirstChild("RaceCheckpoints")
        if checkpoints then
            local ok, kids = pcall(function() return checkpoints:GetChildren() end)
            if ok and kids then
                for i = 1, math.min(#kids, 30) do
                    local cp = kids[i]
                    if cp:IsA("BasePart") then
                        Movement.stepTo(cp.Position, generation)
                        Util.humanWait(0.2)
                    end
                end
            end
        end
        Util.humanWait(0.8)
    end
end

local Progression = {}

local function hasBeli(amount) return State.beli >= amount end

function Progression.buyHaki(kind)
    local key = string.lower(kind) == "buso" and "Buso" or "Ken"
    Discovery.invoke("BuyHaki", key)
    Util.humanWait(0.4)
    Discovery.invoke("RaiseFist")
end

function Progression.trainHaki(generation)
    while Config.data.progression.trainHaki do
        if generation ~= State.generation then break end
        Discovery.invoke("RaiseFist")
        Util.humanWait(Util.jitter(3.2, 0.3))
    end
end

function Progression.buyStyle(style)
    if not style then return false end
    if not hasBeli(style.cost) then
        State.stateText = "beli low: " .. style.name
        return false
    end
    Discovery.invoke("BuyFightingStyle", style.name)
    Util.humanWait(0.8)
    return true
end

function Progression.buyGun(gun)
    if not gun then return false end
    if not hasBeli(gun.cost) then
        State.stateText = "beli low: " .. gun.name
        return false
    end
    Discovery.invoke("BuyWeapon", gun.name)
    Util.humanWait(0.6)
    return true
end

function Progression.buySword(sword)
    if not sword then return false end
    if not hasBeli(sword.cost) then
        State.stateText = "beli low: " .. sword.name
        return false
    end
    Discovery.invoke("BuyWeapon", sword.name)
    Util.humanWait(0.6)
    return true
end

function Progression.legendaryChain(name, generation)
    local chain = LEGENDARY_STEPS[name]
    if not chain then return false end
    for i = 1, #chain do
        if generation ~= State.generation then return false end
        State.stateText = name .. " step " .. i
        Discovery.invoke("Legendary", name, chain[i])
        Util.humanWait(Util.jitter(1.0, 0.25))
    end
    State.stateText = "idle"
    return true
end

function Progression.sanguine(generation)
    while Config.data.progression.sanguine do
        if generation ~= State.generation then break end
        Discovery.invoke("Sanguine", "Start")
        Util.humanWait(1.4)
        local target = nearestEnemy(400, function(m)
            return string.find(string.lower(m.Name), "sanguine", 1, true) ~= nil
        end)
        if target then
            local tp = target:FindFirstChild("HumanoidRootPart")
            if tp then Movement.stepTo(tp.Position, generation) end
            Combat.attack(target, generation)
        end
        Util.humanWait(0.6)
    end
end

function Progression.awaken(generation)
    while Config.data.progression.awaken do
        if generation ~= State.generation then break end
        if State.fragments < 500 then
            State.stateText = "fragments low"
            Util.humanWait(2)
            continue
        end
        Discovery.invoke("AwakenFruit", "NPC")
        Util.humanWait(1.0)
        Discovery.invoke("AwakenMoves", "All")
        Util.humanWait(1.0)
    end
end

function Progression.raceUnlock(race, generation)
    Discovery.invoke("Race", "Buy", race)
    Util.humanWait(1.2)
    for attempt = 1, 3 do
        if generation ~= State.generation then return false end
        Discovery.invoke("Race", "Trial", race)
        Util.humanWait(2.0)
        if Discovery.invoke("Race", "Check") then return true end
        Util.humanWait(attempt * 1.5)
    end
    return false
end

function Progression.valkyrie(generation)
    while Config.data.progression.valkyrie do
        if generation ~= State.generation then break end
        Discovery.invoke("Valkyrie", "Start")
        local target = nearestEnemy(400, function(m)
            return string.find(string.lower(m.Name), "valkyrie", 1, true) ~= nil
        end)
        if target then
            local tp = target:FindFirstChild("HumanoidRootPart")
            if tp then Movement.stepTo(tp.Position, generation) end
            Combat.attack(target, generation)
        end
        Util.humanWait(0.6)
    end
end

function Progression.fragmentLoop(generation)
    while Config.data.progression.fragments do
        if generation ~= State.generation then break end
        Discovery.invoke("Raid", "Fragments")
        Util.humanWait(2.0)
    end
end

local Economy = {}

function Economy.storeFruit(name)
    if not name or name == "" then return false end
    return Discovery.invoke("StoreFruit", name) ~= nil
end

function Economy.sellAll()
    return Discovery.invoke("Sell") ~= nil
end

function Economy.bagFull()
    local bag = Discovery.resolveGuiPath("Main", "Bag")
    if not bag then return false end
    local ok, txt = pcall(function()
        local t = bag:FindFirstChildOfClass("TextLabel")
        return t and t.Text or ""
    end)
    if ok and txt then
        local cur, cap = string.match(txt, "(%d+)%s*/%s*(%d+)")
        if cur and cap then return tonumber(cur) >= tonumber(cap) end
    end
    return false
end

local Teleport = {
    saved = {},
}

function Teleport.toIsland(name)
    for i = 1, #ISLANDS do
        if ISLANDS[i].name == name then
            local pos = Quests.islandPosition(ISLANDS[i])
            if pos then
                Movement.snapTo(pos)
                return true
            end
            return false
        end
    end
    return false
end

function Teleport.toSpawn()
    local spawn = Workspace and Workspace:FindFirstChild("SpawnLocation")
    if spawn then
        Movement.snapTo(spawn.Position)
        return true
    end
    return false
end

function Teleport.saveWaypoint(name)
    local rp = rootPart()
    if not rp then return false end
    Teleport.saved[name] = rp.CFrame
    return true
end

function Teleport.gotoWaypoint(name)
    local cf = Teleport.saved[name]
    local rp = rootPart()
    if not cf or not rp then return false end
    return pcall(function() rp.CFrame = cf end)
end

function Teleport.toNpc(name)
    local npcs = Workspace and (Workspace:FindFirstChild("NPCs") or Workspace:FindFirstChild("NPC"))
    if not npcs then return false end
    local ok, node = pcall(function() return npcs:FindFirstChild(name, true) end)
    if ok and node then
        local part = node:IsA("BasePart") and node or node:FindFirstChildWhichIsA("BasePart")
        if part then
            Movement.snapTo(part.Position)
            return true
        end
    end
    return false
end

local ESP = {
    pool = {},
    drawings = {},
}

function ESP.worldToScreen(worldPos)
    local cam = Workspace and Workspace.CurrentCamera
    if not cam then return nil end
    local ok, sp, onScreen = pcall(function() return cam:WorldToScreenPoint(worldPos) end)
    if not ok or not onScreen then return nil end
    return sp
end

function ESP.refresh()
    local cap = PLATFORM.mobile and 60 or 150
    if Config.data.util.espCap > 0 then cap = math.min(cap, Config.data.util.espCap) end
    local cull = PLATFORM.mobile and 250 or 800
    if Config.data.util.espDistance > 0 then cull = math.min(cull, Config.data.util.espDistance) end
    local rp = rootPart()
    if not rp then return end
    local players = Players:GetPlayers()
    local needed = 0
    for i = 1, #players do
        local plr = players[i]
        if plr ~= LP and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp and (hrp.Position - rp.Position).Magnitude < cull then needed = needed + 1 end
        end
    end
    local want = math.min(needed, cap)
    while #ESP.pool < want do
        local bb = Instance.new("BillboardGui")
        bb.Name = "e" .. tostring(#ESP.pool)
        bb.Size = UDim2.fromScale(5, 1.4)
        bb.AlwaysOnTop = true
        bb.Enabled = false
        bb.Parent = PLATFORM.guiParent
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.fromScale(1, 1)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = Color3.fromRGB(232, 246, 255)
        lbl.TextStrokeTransparency = 0
        lbl.TextScaled = true
        lbl.Font = Enum.Font.Gotham
        lbl.Parent = bb
        table.insert(ESP.pool, { gui = bb, label = lbl })
    end
    local used = 0
    if Config.data.util.espPlayers then
        for i = 1, #players do
            if used >= cap then break end
            local plr = players[i]
            if plr ~= LP and plr.Character then
                local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                local hum = plr.Character:FindFirstChildOfClass("Humanoid")
                if hrp and hum then
                    local dist = (hrp.Position - rp.Position).Magnitude
                    if dist < cull then
                        used = used + 1
                        local slot = ESP.pool[used]
                        if slot then
                            slot.gui.Adornee = hrp
                            slot.gui.Enabled = true
                            slot.label.Text = string.format("%s  %d  %dm", plr.Name, math.floor(hum.Health), math.floor(dist))
                        end
                    end
                end
            end
        end
    end
    for i = used + 1, #ESP.pool do
        ESP.pool[i].gui.Enabled = false
    end
end

function ESP.teardown()
    for i = 1, #ESP.pool do
        pcall(function() ESP.pool[i].gui:Destroy() end)
    end
    ESP.pool = {}
    for i = 1, #ESP.drawings do
        pcall(function() ESP.drawings[i]:Destroy() end)
    end
    ESP.drawings = {}
end

local Aimbot = {}

function Aimbot.findTarget()
    local cam = Workspace and Workspace.CurrentCamera
    local rp = rootPart()
    if not cam or not rp then return nil end
    local fov = Config.data.util.aimFov
    local best, bestScore = nil, math.huge
    local enemies = Discovery.resolveFolder({ "workspace.Enemies" })
    if not enemies then return nil end
    local ok, kids = pcall(function() return enemies:GetChildren() end)
    if not ok or not kids then return nil end
    local centre = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
    for i = 1, math.min(#kids, 200) do
        local m = kids[i]
        local hum = m:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            local part = m:FindFirstChild(Config.data.util.aimPart) or m:FindFirstChild("HumanoidRootPart")
            if part then
                local sp = ESP.worldToScreen(part.Position)
                if sp then
                    local d = (Vector2.new(sp.X, sp.Y) - centre).Magnitude
                    if d < fov and d < bestScore then bestScore, best = d, part end
                end
            end
        end
    end
    return best
end

function Aimbot.tick()
    if not Config.data.util.aimbot then return end
    local cam = Workspace and Workspace.CurrentCamera
    if not cam then return end
    local part = Aimbot.findTarget()
    if not part then return end
    local ok, targetCf = pcall(function() return CFrame.lookAt(cam.CFrame.Position, part.Position) end)
    if not ok then return end
    local ok2, newCf = pcall(function() return cam.CFrame:Lerp(targetCf, Config.data.util.aimSmooth) end)
    if ok2 then pcall(function() cam.CFrame = newCf end) end
end

local ServerHop = {
    hopping = false,
    lastHop = 0,
}

local REEXEC_FETCH = "game:" .. "HttpGet"
local REEXEC_COMPILE = "loadstring"

function ServerHop.reexecLine(url)
    return string.format('%s(%s("%s"))()', REEXEC_COMPILE, REEXEC_FETCH, url)
end

function ServerHop.enqueueReexec()
    local url = ENV["frost_boot_" .. STABLE_TAG]
    if type(url) ~= "string" or url == "" then return false end
    if not CAP.queue_on_teleport then return false end
    return (safeCall(CAP.queue_on_teleport, ServerHop.reexecLine(url)))
end

function ServerHop.hop()
    if ServerHop.hopping then return false end
    if os.clock() - ServerHop.lastHop < 30 then return false end
    ServerHop.hopping = true
    ServerHop.lastHop = os.clock()
    local endpoint = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
    local body = nil
    if CAP.request then
        local okReq, res = safeCall(CAP.request, { Url = endpoint, Method = "GET" })
        if okReq and type(res) == "table" then body = res.Body end
    end
    if type(body) ~= "string" then
        local okFetch, raw = pcall(function() return game:HttpGet(endpoint) end)
        if okFetch then body = raw end
    end
    if type(body) ~= "string" then
        ServerHop.hopping = false
        return false
    end
    local okDec, list = pcall(function() return HttpService:JSONDecode(body) end)
    if not okDec or type(list) ~= "table" or type(list.data) ~= "table" then
        ServerHop.hopping = false
        return false
    end
    local minP = Config.data.util.hopMinPlayers
    local best, bestScore = nil, -1
    for i = 1, #list.data do
        local s = list.data[i]
        if s.id and s.playing and s.maxPlayers and s.playing < s.maxPlayers and s.playing >= minP then
            if s.playing > bestScore then bestScore, best = s.playing, s end
        end
    end
    if best then
        ServerHop.enqueueReexec()
        pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, best.id, LP) end)
        ServerHop.hopping = false
        return true
    end
    ServerHop.hopping = false
    return false
end

function ServerHop.joinPrivate(link)
    if type(link) ~= "string" or link == "" then return false end
    local code = string.match(link, "privateServerLinkCode=([%w%-_]+)")
    if not code then return false end
    ServerHop.enqueueReexec()
    return pcall(function() TeleportService:TeleportToPrivateServer(game.PlaceId, code, { LP }) end)
end

local Watchdog = {
    deaths = {},
    paused = false,
    resumeAt = 0,
}

function Watchdog.recordDeath()
    local now = os.clock()
    table.insert(Watchdog.deaths, now)
    local kept = {}
    for i = 1, #Watchdog.deaths do
        if Watchdog.deaths[i] >= now - 60 then table.insert(kept, Watchdog.deaths[i]) end
    end
    Watchdog.deaths = kept
    if #Watchdog.deaths >= 3 then
        Watchdog.paused = true
        Watchdog.resumeAt = now + 5
        State.pausedUntil = now + 5
        State.stateText = "watchdog pause"
    end
end

function Watchdog.tick()
    if not Watchdog.paused then return end
    if os.clock() < Watchdog.resumeAt then return end
    local hum = humanoid()
    if hum and hum.Health > 0 then
        Watchdog.paused = false
        Watchdog.deaths = {}
        State.pausedUntil = 0
        State.stateText = "resumed"
    end
end

local AntiAfk = { conn = nil }

function AntiAfk.start()
    if AntiAfk.conn then return end
    AntiAfk.conn = RunService.Heartbeat:Connect(function()
        if not Config.data.util.antiAfk then return end
        if not VirtualUser then return end
        pcall(function() VirtualUser:CaptureController() end)
        pcall(function() VirtualUser:Button2Down(Vector2.new(0.5, 0.5)) end)
        task.delay(0.05, function()
            pcall(function() VirtualUser:Button2Up(Vector2.new(0.5, 0.5)) end)
        end)
    end)
    registerTeardown(function()
        if AntiAfk.conn then AntiAfk.conn:Disconnect() end
    end)
end

local PAL = {
    base = Color3.fromRGB(10, 20, 32),
    panel = Color3.fromRGB(15, 30, 46),
    panelDeep = Color3.fromRGB(8, 17, 28),
    accent = Color3.fromRGB(127, 231, 255),
    accentSoft = Color3.fromRGB(184, 241, 255),
    text = Color3.fromRGB(232, 246, 255),
    muted = Color3.fromRGB(110, 143, 166),
    danger = Color3.fromRGB(255, 107, 138),
    success = Color3.fromRGB(124, 255, 178),
}

local DIM = {
    titleBar = 34,
    tabStrip = 132,
    tabRow = 40,
    statusBar = 24,
    pad = 8,
    toggleW = 34,
    toggleH = 18,
    knob = 14,
    sliderKnob = 12,
    trackH = 4,
    corner = 12,
    cornerSm = 8,
}

local function new(class, props, children)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do
        if k ~= "Parent" then
            pcall(function() inst[k] = v end)
        end
    end
    if children then
        for i = 1, #children do children[i].Parent = inst end
    end
    if props and props.Parent then inst.Parent = props.Parent end
    return inst
end

local function corner(inst, px)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, px or DIM.corner)
    c.Parent = inst
    return c
end

local function stroke(inst, color, transparency, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or PAL.accent
    s.Transparency = transparency or 0.78
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = inst
    return s
end

local function gradient(inst, fromColor, fromAlpha, toColor, toAlpha, rotation)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(fromColor, toColor)
    g.Transparency = NumberSequence.new(fromAlpha, toAlpha)
    g.Rotation = rotation or 90
    g.Parent = inst
    return g
end

local function pad(inst, px)
    local p = Instance.new("UIPadding")
    local u = UDim.new(0, px or DIM.pad)
    p.PaddingTop = u
    p.PaddingBottom = u
    p.PaddingLeft = u
    p.PaddingRight = u
    p.Parent = inst
    return p
end

local function listLayout(inst, spacing, dir)
    local l = Instance.new("UIListLayout")
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Padding = UDim.new(0, spacing or 6)
    l.FillDirection = dir or Enum.FillDirection.Vertical
    l.Parent = inst
    return l
end

local function padEach(obj, l, r, t, b)
    local p = Instance.new("UIPadding")
    p.PaddingLeft = UDim.new(0, l or 0)
    p.PaddingRight = UDim.new(0, r or 0)
    p.PaddingTop = UDim.new(0, t or 0)
    p.PaddingBottom = UDim.new(0, b or 0)
    p.Parent = obj
    return p
end

local function tween(obj, props, duration)
    if not TweenService then return end
    local ok = pcall(function()
        local t = TweenService:Create(obj, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
        t:Play()
    end)
    return ok
end

local UI = {
    window = nil,
    titleBar = nil,
    tabStrip = nil,
    content = nil,
    statusBar = nil,
    tabs = {},
    activeTab = nil,
    scale = nil,
    snow = {},
    snowActive = false,
    blur = nil,
    minimized = false,
    open = true,
}

local function snowflakeIcon(parent, size)
    local holder = new("Frame", {
        Size = UDim2.fromOffset(size, size),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    for i = 1, 3 do
        local arm = new("Frame", {
            Size = UDim2.fromOffset(size, 1),
            Position = UDim2.fromScale(0.5, 0.5),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = PAL.accent,
            BorderSizePixel = 0,
            Rotation = (i - 1) * 60,
            Parent = holder,
        })
        arm.BackgroundTransparency = 0.15
    end
    return holder
end

local function chevron(parent, down)
    local holder = new("Frame", {
        Size = UDim2.fromOffset(12, 12),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    local a = new("Frame", {
        Size = UDim2.fromOffset(7, 1),
        Position = UDim2.fromScale(0.34, 0.55),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Rotation = down and 45 or -45,
        BackgroundColor3 = PAL.muted,
        BorderSizePixel = 0,
        Parent = holder,
    })
    local b = new("Frame", {
        Size = UDim2.fromOffset(7, 1),
        Position = UDim2.fromScale(0.66, 0.55),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Rotation = down and -45 or 45,
        BackgroundColor3 = PAL.muted,
        BorderSizePixel = 0,
        Parent = holder,
    })
    return holder, a, b
end

local function sectionCard(parent, height)
    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, height or 40),
        BackgroundColor3 = PAL.panel,
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
        Parent = parent,
    })
    corner(card, DIM.cornerSm)
    local s = stroke(card, PAL.accent, 0.89, 1)
    gradient(card, PAL.accent, 0.95, PAL.accent, 1, 90)
    return card, s
end

local function sectionTitle(parent, text)
    local lbl = new("TextLabel", {
        Size = UDim2.new(1, -16, 0, 22),
        Position = UDim2.fromOffset(8, 4),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium,
        Text = text,
        TextSize = 12,
        TextColor3 = PAL.accent,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = parent,
    })
    return lbl
end

local function makeToggle(parent, labelText, initial, callback)
    local row = new("Frame", {
        Size = UDim2.new(1, -16, 0, 44),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    local lbl = new("TextLabel", {
        Size = UDim2.new(1, -56, 0, 44),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = labelText,
        TextSize = 13,
        TextColor3 = PAL.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })
    local hit = new("TextButton", {
        Size = UDim2.fromOffset(44, 44),
        Position = UDim2.new(1, -44, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        Parent = row,
    })
    local track = new("Frame", {
        Size = UDim2.fromOffset(DIM.toggleW, DIM.toggleH),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = initial and PAL.accent or PAL.muted,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Parent = hit,
    })
    corner(track, 9)
    local ts = stroke(track, PAL.accent, initial and 0.25 or 0.8, 1)
    local knob = new("Frame", {
        Size = UDim2.fromOffset(DIM.knob, DIM.knob),
        Position = UDim2.new(0, initial and 2 or (DIM.toggleW - DIM.knob - 2), 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = PAL.text,
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(knob, 7)
    local state = initial and true or false
    local function apply(on)
        state = on
        tween(track, { BackgroundColor3 = on and PAL.accent or PAL.muted }, 0.15)
        tween(knob, { Position = UDim2.new(0, on and (DIM.toggleW - DIM.knob - 2) or 2, 0.5, 0) }, 0.15)
        ts.Transparency = on and 0.25 or 0.8
    end
    hit.MouseEnter:Connect(function() ts.Transparency = math.max(ts.Transparency - 0.1, 0) end)
    hit.MouseLeave:Connect(function() ts.Transparency = state and 0.25 or 0.8 end)
    hit.MouseButton1Click:Connect(function()
        apply(not state)
        if callback then pcall(callback, state) end
    end)
    apply(initial)
    return row, function(v)
        apply(v)
        if callback then pcall(callback, v) end
    end, function() return state end
end

local function makeSlider(parent, labelText, minV, maxV, initial, callback)
    local row = new("Frame", {
        Size = UDim2.new(1, -16, 0, 46),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    local lbl = new("TextLabel", {
        Size = UDim2.new(1, -70, 0, 18),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = labelText,
        TextSize = 12,
        TextColor3 = PAL.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })
    local val = new("TextLabel", {
        Size = UDim2.fromOffset(60, 18),
        Position = UDim2.new(1, -60, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium,
        Text = tostring(math.floor(initial)),
        TextSize = 12,
        TextColor3 = PAL.accent,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = row,
    })
    local track = new("Frame", {
        Size = UDim2.new(1, 0, 0, DIM.trackH),
        Position = UDim2.new(0, 0, 0, 30),
        BackgroundColor3 = PAL.panelDeep,
        BorderSizePixel = 0,
        Parent = row,
    })
    corner(track, 2)
    stroke(track, PAL.accent, 0.88, 1)
    local fill = new("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = PAL.accent,
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(fill, 2)
    local knob = new("Frame", {
        Size = UDim2.fromOffset(DIM.sliderKnob, DIM.sliderKnob),
        Position = UDim2.new(0, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = PAL.text,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = track,
    })
    corner(knob, 6)
    local hit = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 20),
        Position = UDim2.new(0, 0, 0, 22),
        BackgroundTransparency = 1,
        Text = "",
        Parent = row,
    })
    local value = Util.clamp(initial, minV, maxV)
    local dragging = false
    local function render()
        local t = (maxV > minV) and ((value - minV) / (maxV - minV)) or 0
        fill.Size = UDim2.fromScale(t, 1)
        knob.Position = UDim2.new(t, 0, 0.5, 0)
        val.Text = tostring(math.floor(value))
    end
    local function setFromX(x)
        local absX = hit.AbsolutePosition.X
        local w = hit.AbsoluteSize.X
        if w <= 0 then return end
        local t = Util.clamp((x - absX) / w, 0, 1)
        value = minV + (maxV - minV) * t
        render()
        if callback then pcall(callback, math.floor(value)) end
    end
    hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromX(input.Position.X)
        end
    end)
    hit.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            setFromX(input.Position.X)
        end
    end)
    hit.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    hit.MouseEnter:Connect(function() tween(track, { BackgroundTransparency = 0 }, 0.08) end)
    hit.MouseLeave:Connect(function() tween(track, { BackgroundTransparency = 0 }, 0.08) end)
    render()
    return row, function(v)
        value = Util.clamp(v, minV, maxV)
        render()
        if callback then pcall(callback, math.floor(value)) end
    end
end

local function makeDropdown(parent, labelText, options, initial, callback)
    local holder = new("Frame", {
        Size = UDim2.new(1, -16, 0, 44),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    local lbl = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = labelText,
        TextSize = 12,
        TextColor3 = PAL.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = holder,
    })
    local box = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 24),
        Position = UDim2.new(0, 0, 0, 20),
        BackgroundColor3 = PAL.panelDeep,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Text = "",
        Parent = holder,
    })
    corner(box, 6)
    local bs = stroke(box, PAL.accent, 0.82, 1)
    local shown = new("TextLabel", {
        Size = UDim2.new(1, -28, 1, 0),
        Position = UDim2.fromOffset(8, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = initial or (options[1] or "-"),
        TextSize = 12,
        TextColor3 = PAL.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = box,
    })
    chevron(box, true)
    local menu = new("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.new(0, 0, 1, 4),
        BackgroundColor3 = PAL.panelDeep,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        Visible = false,
        ZIndex = 5,
        Parent = holder,
    })
    corner(menu, 6)
    stroke(menu, PAL.accent, 0.85, 1)
    local ml = listLayout(menu, 0)
    local open = false
    local current = initial or options[1]
    local function rebuild()
        for _, ch in ipairs(menu:GetChildren()) do
            if ch:IsA("TextButton") then ch:Destroy() end
        end
        for i = 1, #options do
            local opt = options[i]
            local btn = new("TextButton", {
                Size = UDim2.new(1, 0, 0, 22),
                BackgroundColor3 = PAL.panel,
                BackgroundTransparency = 0.5,
                BorderSizePixel = 0,
                Text = "",
                LayoutOrder = i,
                ZIndex = 6,
                Parent = menu,
            })
            local ol = new("TextLabel", {
                Size = UDim2.new(1, -12, 1, 0),
                Position = UDim2.fromOffset(6, 0),
                BackgroundTransparency = 1,
                Font = Enum.Font.Gotham,
                Text = opt,
                TextSize = 12,
                TextColor3 = PAL.text,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 7,
                Parent = btn,
            })
            btn.MouseEnter:Connect(function() btn.BackgroundTransparency = 0.2 end)
            btn.MouseLeave:Connect(function() btn.BackgroundTransparency = 0.5 end)
            btn.MouseButton1Click:Connect(function()
                current = opt
                shown.Text = opt
                open = false
                tween(menu, { Size = UDim2.new(1, 0, 0, 0) }, 0.08)
                menu.Visible = false
                if callback then pcall(callback, opt) end
            end)
            local _ = ol
        end
        menu.CanvasSize = UDim2.new(0, 0, 0, #options * 22)
    end
    rebuild()
    box.MouseButton1Click:Connect(function()
        open = not open
        if open then
            local h = math.min(120, #options * 22)
            menu.Visible = true
            tween(menu, { Size = UDim2.new(1, 0, 0, h) }, 0.08)
        else
            tween(menu, { Size = UDim2.new(1, 0, 0, 0) }, 0.08)
            task.delay(0.09, function() menu.Visible = false end)
        end
    end)
    box.MouseEnter:Connect(function() bs.Transparency = 0.72 end)
    box.MouseLeave:Connect(function() bs.Transparency = 0.82 end)
    return holder, function(v)
        current = v
        shown.Text = v
        if callback then pcall(callback, v) end
    end
end

local function makeTextBox(parent, labelText, initial, placeholder, callback)
    local holder = new("Frame", {
        Size = UDim2.new(1, -16, 0, 44),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = labelText,
        TextSize = 12,
        TextColor3 = PAL.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = holder,
    })
    local box = new("TextBox", {
        Size = UDim2.new(1, 0, 0, 24),
        Position = UDim2.new(0, 0, 0, 20),
        BackgroundColor3 = PAL.panelDeep,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Font = Enum.Font.Gotham,
        Text = initial or "",
        PlaceholderText = placeholder or "",
        PlaceholderColor3 = PAL.muted,
        TextColor3 = PAL.text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        Parent = holder,
    })
    corner(box, 6)
    local bs = stroke(box, PAL.accent, 0.82, 1)
    padEach(box, 8, 8, 0, 0)
    box.Focused:Connect(function() bs.Transparency = 0.35 end)
    box.FocusLost:Connect(function()
        bs.Transparency = 0.82
        if callback then pcall(callback, box.Text) end
    end)
    return holder, function(v)
        box.Text = v
        if callback then pcall(callback, v) end
    end
end

local function makeButton(parent, text, callback, danger)
    local btn = new("TextButton", {
        Size = UDim2.new(1, -16, 0, 32),
        BackgroundColor3 = danger and PAL.danger or PAL.panel,
        BackgroundTransparency = 0.25,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamMedium,
        Text = text,
        TextSize = 12,
        TextColor3 = danger and PAL.text or PAL.accent,
        Parent = parent,
    })
    corner(btn, 6)
    local bs = stroke(btn, danger and PAL.danger or PAL.accent, 0.7, 1)
    btn.MouseEnter:Connect(function()
        bs.Transparency = 0.6
        tween(btn, { BackgroundTransparency = 0.1 }, 0.08)
    end)
    btn.MouseLeave:Connect(function()
        bs.Transparency = 0.7
        tween(btn, { BackgroundTransparency = 0.25 }, 0.08)
    end)
    btn.MouseButton1Click:Connect(function()
        if callback then pcall(callback) end
    end)
    return btn
end

local function makeLabel(parent, text, color)
    return new("TextLabel", {
        Size = UDim2.new(1, -16, 0, 20),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = text,
        TextSize = 11,
        TextColor3 = color or PAL.muted,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        Parent = parent,
    })
end

local function makeKeybind(parent, labelText, initial, callback)
    local row = new("Frame", {
        Size = UDim2.new(1, -16, 0, 44),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    new("TextLabel", {
        Size = UDim2.new(1, -80, 0, 44),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = labelText,
        TextSize = 13,
        TextColor3 = PAL.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })
    local btn = new("TextButton", {
        Size = UDim2.fromOffset(76, 26),
        Position = UDim2.new(1, -76, 0.5, -13),
        BackgroundColor3 = PAL.panelDeep,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Font = Enum.Font.Gotham,
        Text = initial or "None",
        TextSize = 11,
        TextColor3 = PAL.accent,
        Parent = row,
    })
    corner(btn, 5)
    local bs = stroke(btn, PAL.accent, 0.82, 1)
    local capturing = false
    local current = initial or "None"
    local conn
    btn.MouseButton1Click:Connect(function()
        if PLATFORM.mobile then
            current = "Touch"
            btn.Text = "Touch"
            if callback then pcall(callback, "Touch") end
            return
        end
        capturing = true
        btn.Text = "Press a key..."
        btn.TextColor3 = PAL.muted
        if conn then conn:Disconnect() end
        conn = UserInputService.InputBegan:Connect(function(input, processed)
            if processed then return end
            if not capturing then return end
            if input.KeyCode == Enum.KeyCode.Escape then
                capturing = false
                btn.Text = current
                btn.TextColor3 = PAL.accent
                if conn then conn:Disconnect() end
                return
            end
            local name = input.KeyCode.Name
            if name == "Unknown" then return end
            current = name
            capturing = false
            btn.Text = name
            btn.TextColor3 = PAL.accent
            if conn then conn:Disconnect() end
            if callback then pcall(callback, name) end
        end)
    end)
    btn.MouseEnter:Connect(function() bs.Transparency = 0.72 end)
    btn.MouseLeave:Connect(function() bs.Transparency = 0.82 end)
    return row, function() return current end
end

local function computeScale()
    local cam = Workspace and Workspace.CurrentCamera
    if not cam then return 1 end
    local vp = cam.ViewportSize
    local maxW = vp.X * 0.92
    local maxH = vp.Y * 0.88
    local sw = maxW / Config.data.ui.width
    local sh = maxH / Config.data.ui.height
    local s = math.min(sw, sh, 1.15)
    if PLATFORM.mobile then s = math.min(s, 1.0) end
    return Util.clamp(s, 0.55, 1.15)
end

local function makeStatusBar(parent)
    local bar = new("Frame", {
        Size = UDim2.new(1, 0, 0, DIM.statusBar),
        Position = UDim2.new(0, 0, 1, -DIM.statusBar),
        BackgroundColor3 = PAL.panelDeep,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Parent = parent,
    })
    local left = new("TextLabel", {
        Size = UDim2.new(1, -110, 1, 0),
        Position = UDim2.fromOffset(8, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = "idle",
        TextSize = 10,
        TextColor3 = PAL.muted,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = bar,
    })
    local right = new("TextLabel", {
        Size = UDim2.fromOffset(100, 1),
        Position = UDim2.new(1, -108, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = VERSION,
        TextSize = 10,
        TextColor3 = PAL.muted,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = bar,
    })
    return bar, left, right
end

local function buildSnow(root)
    for i = 1, #UI.snow do pcall(function() UI.snow[i]:Destroy() end) end
    UI.snow = {}
    if not Config.data.ui.snow then return end
    local count = PLATFORM.mobile and 12 or 24
    for i = 1, count do
        local flake = new("Frame", {
            Size = UDim2.fromOffset(2, 2),
            BackgroundColor3 = PAL.accentSoft,
            BackgroundTransparency = 0.65,
            BorderSizePixel = 0,
            Position = UDim2.fromScale(math.random(), -0.05),
            Parent = root,
        })
        corner(flake, 1)
        table.insert(UI.snow, flake)
    end
    UI.snowActive = true
end

local function snowStep()
    if not UI.snowActive then return end
    local root = UI.window
    if not root then return end
    local h = root.AbsoluteSize.Y
    if h <= 0 then return end
    for i = 1, #UI.snow do
        local flake = UI.snow[i]
        if flake and flake.Parent then
            local pos = flake.Position
            local y = pos.Y.Scale * h + pos.Y.Offset
            y = y + (PLATFORM.mobile and 22 or 34) * TICK
            if y > h then y = -4 end
            local sway = math.sin((os.clock() + i * 0.7) * 1.4) * 0.006
            local x = Util.clamp(pos.X.Scale + sway * TICK, 0, 0.99)
            flake.Position = UDim2.new(x, 0, 0, y)
        end
    end
end

local function applyBlur()
    if UI.blur then pcall(function() UI.blur:Destroy() end) UI.blur = nil end
    if not Config.data.ui.blur then return end
    if PLATFORM.mobile then return end
    if not Lighting then return end
    local b = Instance.new("BlurEffect")
    b.Size = 12
    b.Parent = Lighting
    UI.blur = b
end

local function buildWindow()
    local scale = computeScale()
    local parent = PLATFORM.guiParent
    if not parent then return nil end

    local screen = new("ScreenGui", {
        Name = "s" .. STABLE_TAG,
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 999,
        Parent = parent,
    })
    local uscale = Instance.new("UIScale")
    uscale.Scale = scale
    uscale.Parent = screen
    UI.scale = uscale

    local root = new("Frame", {
        Name = "r",
        Size = UDim2.fromOffset(Config.data.ui.width, Config.data.ui.height),
        Position = UDim2.fromScale(Config.data.ui.x, Config.data.ui.y),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = PAL.panel,
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
        Parent = screen,
    })
    corner(root, DIM.corner)
    local rootStroke = stroke(root, PAL.accent, 0.78, 1)
    gradient(root, PAL.accent, 0.9, PAL.accent, 1, 90)
    UI.window = root
    UI.screen = screen

    local titleBar = new("Frame", {
        Size = UDim2.new(1, 0, 0, DIM.titleBar),
        BackgroundColor3 = PAL.panel,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Parent = root,
    })
    corner(titleBar, DIM.corner)
    UI.titleBar = titleBar
    local divider = new("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, -1),
        BackgroundColor3 = PAL.accent,
        BackgroundTransparency = 0.85,
        BorderSizePixel = 0,
        Parent = titleBar,
    })
    local _ = divider
    snowflakeIcon(titleBar, 14).Position = UDim2.fromOffset(10, 10)
    new("TextLabel", {
        Size = UDim2.new(1, -140, 1, 0),
        Position = UDim2.fromOffset(32, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium,
        Text = VERSION,
        TextSize = 12,
        TextColor3 = PAL.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = titleBar,
    })

    local minBtn = new("TextButton", {
        Size = UDim2.fromOffset(20, 20),
        Position = UDim2.new(1, -56, 0, 7),
        BackgroundColor3 = PAL.panelDeep,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = "_",
        TextSize = 12,
        TextColor3 = PAL.muted,
        Parent = titleBar,
    })
    corner(minBtn, 4)

    local closeBtn = new("TextButton", {
        Size = UDim2.fromOffset(20, 20),
        Position = UDim2.new(1, -32, 0, 7),
        BackgroundColor3 = PAL.panelDeep,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = "x",
        TextSize = 12,
        TextColor3 = PAL.danger,
        Parent = titleBar,
    })
    corner(closeBtn, 4)

    local tabStrip = new("Frame", {
        Size = UDim2.new(0, DIM.tabStrip, 1, -(DIM.titleBar + DIM.statusBar)),
        Position = UDim2.fromOffset(0, DIM.titleBar),
        BackgroundColor3 = PAL.panelDeep,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Parent = root,
    })
    UI.tabStrip = tabStrip
    local tabLayout = listLayout(tabStrip, 2)
    padEach(tabStrip, 6, 6, 6, 6)

    local content = new("ScrollingFrame", {
        Size = UDim2.new(1, -(DIM.tabStrip + 12), 1, -(DIM.titleBar + DIM.statusBar + 12)),
        Position = UDim2.fromOffset(DIM.tabStrip + 8, DIM.titleBar + 6),
        BackgroundColor3 = PAL.panelDeep,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = PAL.accent,
        ScrollBarImageTransparency = 0.4,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = root,
    })
    corner(content, 10)
    stroke(content, PAL.accent, 0.9, 1)
    pad(content, DIM.pad)
    UI.content = content

    local statusBar, statusLeft = makeStatusBar(root)
    UI.statusBar = statusBar
    UI.statusLeft = statusLeft

    local function applyMinimize(on)
        UI.minimized = on
        Config.data.ui.minimized = on
        Config.dirty = true
        tabStrip.Visible = not on
        content.Visible = not on
        statusBar.Visible = not on
        tween(root, { Size = on and UDim2.fromOffset(Config.data.ui.width, DIM.titleBar) or UDim2.fromOffset(Config.data.ui.width, Config.data.ui.height) }, 0.12)
    end

    if Config.data.ui.minimized then applyMinimize(true) end

    minBtn.MouseButton1Click:Connect(function() applyMinimize(not UI.minimized) end)
    closeBtn.MouseButton1Click:Connect(function()
        Config.data.ui.visible = false
        Config.dirty = true
        screen.Enabled = false
    end)

    do
        local dragging = false
        local dragStart, startPos
        titleBar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = root.Position
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch then
                local delta = input.Position - dragStart
                root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                if dragging then
                    dragging = false
                    local cam = Workspace.CurrentCamera
                    local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
                    local abs = root.AbsolutePosition
                    local size = root.AbsoluteSize
                    local cx = Util.clamp((abs.X + size.X / 2) / vp.X, 0.06, 0.94)
                    local cy = Util.clamp((abs.Y + size.Y / 2) / vp.Y, 0.06, 0.94)
                    root.Position = UDim2.fromScale(cx, cy)
                    Config.data.ui.x = cx
                    Config.data.ui.y = cy
                    Config.dirty = true
                end
            end
        end)
    end

    local function makeTab(name)
        local btn = new("TextButton", {
            Size = UDim2.new(1, 0, 0, DIM.tabRow),
            BackgroundColor3 = PAL.panel,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font = Enum.Font.Gotham,
            Text = "",
            Parent = tabStrip,
        })
        corner(btn, DIM.cornerSm)
        local bar = new("Frame", {
            Size = UDim2.new(0, 2, 0, 0),
            Position = UDim2.new(0, 0, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundColor3 = PAL.accent,
            BorderSizePixel = 0,
            Parent = btn,
        })
        local lbl = new("TextLabel", {
            Size = UDim2.new(1, -14, 1, 0),
            Position = UDim2.fromOffset(12, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham,
            Text = name,
            TextSize = 12,
            TextColor3 = PAL.muted,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = btn,
        })
        local page = new("ScrollingFrame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 0,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Visible = false,
            Parent = content,
        })
        local pl = listLayout(page, 8)
        local _ = pl
        local entry = { name = name, button = btn, bar = bar, label = lbl, page = page }
        UI.tabs[name] = entry
        return entry
    end

    local function activate(name)
        for key, tab in pairs(UI.tabs) do
            local on = key == name
            tab.page.Visible = on
            tab.button.BackgroundTransparency = on and 0.88 or 1
            tab.label.TextColor3 = on and PAL.accent or PAL.muted
            tween(tab.bar, { Size = on and UDim2.new(0, 2, 1, -12) or UDim2.new(0, 2, 0, 0) }, 0.08)
        end
        UI.activeTab = name
        Config.data.ui.tab = name
        Config.dirty = true
    end

    UI.activateTab = activate

    for _, name in ipairs({ "Farm", "Level", "Events", "Progression", "Utility", "Settings" }) do
        local entry = makeTab(name)
        entry.button.MouseButton1Click:Connect(function() activate(name) end)
        entry.button.MouseEnter:Connect(function()
            if UI.activeTab ~= name then entry.label.TextColor3 = PAL.accentSoft end
        end)
        entry.button.MouseLeave:Connect(function()
            if UI.activeTab ~= name then entry.label.TextColor3 = PAL.muted end
        end)
    end

    activate(UI.tabs[Config.data.ui.tab] and Config.data.ui.tab or "Farm")

    UI.screen = screen
    UI.tabLayout = tabLayout
    UI.rootStroke = rootStroke
    return screen
end

local function buildFarmTab()
    local page = UI.tabs["Farm"].page
    local card = sectionCard(page, 300)
    card.Size = UDim2.new(1, -8, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    sectionTitle(card, "FARM")
    local inner = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, 26),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = card,
    })
    listLayout(inner, 0)

    makeToggle(inner, "Auto Farm Mobs", Config.data.farm.mobs, function(v)
        configSet({ "farm", "mobs" }, v)
        if v then task.spawn(Farm.mobLoop, State.generation) end
    end)
    makeToggle(inner, "Auto Farm Bosses", Config.data.farm.bosses, function(v)
        configSet({ "farm", "bosses" }, v)
        if v then task.spawn(Farm.bossLoop, State.generation) end
    end)
    makeToggle(inner, "Auto Chests", Config.data.farm.chests, function(v)
        configSet({ "farm", "chests" }, v)
        if v then task.spawn(Farm.chestLoop, State.generation) end
    end)
    makeToggle(inner, "Auto Bones", Config.data.farm.bones, function(v)
        configSet({ "farm", "bones" }, v)
        if v then task.spawn(Farm.bonesLoop, State.generation) end
    end)
    makeToggle(inner, "Auto Mastery", Config.data.farm.mastery, function(v)
        configSet({ "farm", "mastery" }, v)
        if v then task.spawn(Farm.masteryLoop, State.generation) end
    end)
    makeToggle(inner, "Auto Ground Fruit", Config.data.farm.fruit, function(v)
        configSet({ "farm", "fruit" }, v)
        if v then task.spawn(Farm.fruitLoop, State.generation) end
    end)
    makeToggle(inner, "Auto Fishing", Config.data.farm.fishing, function(v)
        configSet({ "farm", "fishing" }, v)
        if v then task.spawn(Farm.fishingLoop, State.generation) end
    end)
    makeToggle(inner, "Auto Sea Beast", Config.data.farm.seaBeast, function(v)
        configSet({ "farm", "seaBeast" }, v)
        if v then task.spawn(Farm.seaBeastLoop, State.generation) end
    end)
    makeToggle(inner, "Auto Elite Pirates", Config.data.farm.elites, function(v)
        configSet({ "farm", "elites" }, v)
        if v then task.spawn(Farm.eliteLoop, State.generation) end
    end)
    makeToggle(inner, "Auto Magnet Tokens", Config.data.farm.magnet, function(v)
        configSet({ "farm", "magnet" }, v)
        if v then task.spawn(Farm.magnetLoop, State.generation) end
    end)
    makeSlider(inner, "Level Floor", 1, 3000, Config.data.farm.levelFloor, function(v)
        configSet({ "farm", "levelFloor" }, v)
    end)
    makeSlider(inner, "Level Ceiling", 1, 3000, Config.data.farm.levelCeil, function(v)
        configSet({ "farm", "levelCeil" }, v)
    end)
    makeSlider(inner, "Mastery Cap", 1, 600, Config.data.farm.masteryCap, function(v)
        configSet({ "farm", "masteryCap" }, v)
    end)
end

local function buildLevelTab()
    local page = UI.tabs["Level"].page
    local card = sectionCard(page, 0)
    card.Size = UDim2.new(1, -8, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    sectionTitle(card, "LEVELING ROUTER")
    local inner = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, 26),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = card,
    })
    listLayout(inner, 0)

    makeToggle(inner, "Auto Farm Level", Config.data.leveling.enabled, function(v)
        configSet({ "leveling", "enabled" }, v)
        if v then
            task.spawn(Leveling.loop, State.generation)
        else
            Leveling.stop()
        end
    end)
    makeSlider(inner, "Target Level", 1, 3000, Config.data.leveling.targetLevel, function(v)
        configSet({ "leveling", "targetLevel" }, v)
    end)
    makeToggle(inner, "Prefer Boss When Faster", Config.data.leveling.preferBoss, function(v)
        configSet({ "leveling", "preferBoss" }, v)
    end)
    makeToggle(inner, "Hop For Boss", Config.data.leveling.hopForBoss, function(v)
        configSet({ "leveling", "hopForBoss" }, v)
    end)
    makeSlider(inner, "Hop Cap / Minute", 1, 10, Config.data.leveling.hopCapPerMinute, function(v)
        configSet({ "leveling", "hopCapPerMinute" }, v)
    end)
    makeTextBox(inner, "Private Server Link", Config.data.leveling.privateServer, "privateServerLinkCode=...", function(v)
        configSet({ "leveling", "privateServer" }, v)
    end)
    makeButton(inner, "Join Private Server", function()
        ServerHop.joinPrivate(Config.data.leveling.privateServer)
    end)
    makeDropdown(inner, "Stat Plan", { "balanced", "melee", "sword", "fruit", "gun", "defense" }, Config.data.leveling.statPlan, function(v)
        configSet({ "leveling", "statPlan" }, v)
    end)
    makeToggle(inner, "Convert Stats At 1900", Config.data.leveling.convertAt1900, function(v)
        configSet({ "leveling", "convertAt1900" }, v)
    end)

    local card2 = sectionCard(page, 0)
    card2.Size = UDim2.new(1, -8, 0, 0)
    card2.AutomaticSize = Enum.AutomaticSize.Y
    sectionTitle(card2, "STATS")
    local inner2 = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, 26),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = card2,
    })
    listLayout(inner2, 0)
    makeSlider(inner2, "Melee", 0, 4000, Config.data.stats.melee, function(v)
        configSet({ "stats", "melee" }, v)
    end)
    makeSlider(inner2, "Defense", 0, 4000, Config.data.stats.defense, function(v)
        configSet({ "stats", "defense" }, v)
    end)
    makeSlider(inner2, "Sword", 0, 4000, Config.data.stats.sword, function(v)
        configSet({ "stats", "sword" }, v)
    end)
    makeSlider(inner2, "Gun", 0, 4000, Config.data.stats.gun, function(v)
        configSet({ "stats", "gun" }, v)
    end)
    makeSlider(inner2, "Blox Fruit", 0, 4000, Config.data.stats.fruit, function(v)
        configSet({ "stats", "fruit" }, v)
    end)
end

local function buildEventsTab()
    local page = UI.tabs["Events"].page
    local card = sectionCard(page, 0)
    card.Size = UDim2.new(1, -8, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    sectionTitle(card, "RAIDS & EVENTS")
    local inner = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, 26),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = card,
    })
    listLayout(inner, 0)
    makeToggle(inner, "Auto Raid", Config.data.events.raid, function(v)
        configSet({ "events", "raid" }, v)
        if v then task.spawn(Events.startRaid, State.generation) else Events.raidActive = false end
    end)
    makeDropdown(inner, "Raid Fruit", { "Dragon", "Dough", "Leopard", "Kitsune", "Venom", "Shadow", "Buddha", "Portal" }, Config.data.events.raidFruit, function(v)
        configSet({ "events", "raidFruit" }, v)
    end)
    makeToggle(inner, "Auto Factory Raid", Config.data.events.factory, function(v)
        configSet({ "events", "factory" }, v)
        if v then task.spawn(Events.factoryLoop, State.generation) end
    end)
    makeToggle(inner, "Auto Sea Events", Config.data.events.seaEvents, function(v)
        configSet({ "events", "seaEvents" }, v)
        if v then task.spawn(Events.seaEventsLoop, State.generation) end
    end)
    makeToggle(inner, "Auto Mirage", Config.data.events.mirage, function(v)
        configSet({ "events", "mirage" }, v)
        if v then task.spawn(Events.mirageLoop, State.generation) end
    end)
    makeToggle(inner, "Auto Kitsune Island", Config.data.events.kitsune, function(v)
        configSet({ "events", "kitsune" }, v)
        if v then task.spawn(Events.kitsuneLoop, State.generation) end
    end)
    makeToggle(inner, "Auto Haunted Castle", Config.data.events.haunted, function(v)
        configSet({ "events", "haunted" }, v)
        if v then task.spawn(Events.castleLoop, State.generation) end
    end)
    makeToggle(inner, "Auto Cursed Ship", Config.data.events.cursedShip, function(v)
        configSet({ "events", "cursedShip" }, v)
        if v then task.spawn(Events.castleLoop, State.generation) end
    end)
    makeToggle(inner, "Auto Castle On The Sea", Config.data.events.castleSea, function(v)
        configSet({ "events", "castleSea" }, v)
        if v then task.spawn(Events.castleLoop, State.generation) end
    end)
    makeToggle(inner, "Auto Race Trial", Config.data.events.raceTrial, function(v)
        configSet({ "events", "raceTrial" }, v)
        if v then task.spawn(Events.raceTrialLoop, State.generation) end
    end)
end

local function buildProgressionTab()
    local page = UI.tabs["Progression"].page
    local card = sectionCard(page, 0)
    card.Size = UDim2.new(1, -8, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    sectionTitle(card, "HAKI & AWAKENING")
    local inner = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, 26),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = card,
    })
    listLayout(inner, 0)
    makeToggle(inner, "Auto Buy Buso", Config.data.progression.buso, function(v)
        configSet({ "progression", "buso" }, v)
        if v then Progression.buyHaki("buso") end
    end)
    makeToggle(inner, "Auto Buy Ken", Config.data.progression.ken, function(v)
        configSet({ "progression", "ken" }, v)
        if v then Progression.buyHaki("ken") end
    end)
    makeToggle(inner, "Auto Train Haki", Config.data.progression.trainHaki, function(v)
        configSet({ "progression", "trainHaki" }, v)
        if v then task.spawn(Progression.trainHaki, State.generation) end
    end)
    makeToggle(inner, "Auto Awaken Fruit", Config.data.progression.awaken, function(v)
        configSet({ "progression", "awaken" }, v)
        if v then task.spawn(Progression.awaken, State.generation) end
    end)
    makeToggle(inner, "Auto Sanguine Art", Config.data.progression.sanguine, function(v)
        configSet({ "progression", "sanguine" }, v)
        if v then task.spawn(Progression.sanguine, State.generation) end
    end)
    makeToggle(inner, "Auto Fragment Farm", Config.data.progression.fragments, function(v)
        configSet({ "progression", "fragments" }, v)
        if v then task.spawn(Progression.fragmentLoop, State.generation) end
    end)
    makeToggle(inner, "Auto Valkyrie Helmet", Config.data.progression.valkyrie, function(v)
        configSet({ "progression", "valkyrie" }, v)
        if v then task.spawn(Progression.valkyrie, State.generation) end
    end)

    local card2 = sectionCard(page, 0)
    card2.Size = UDim2.new(1, -8, 0, 0)
    card2.AutomaticSize = Enum.AutomaticSize.Y
    sectionTitle(card2, "FIGHTING STYLES")
    local inner2 = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, 26),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = card2,
    })
    listLayout(inner2, 0)
    for i = 1, #FIGHTING_STYLES do
        local style = FIGHTING_STYLES[i]
        makeToggle(inner2, style.name, Config.data.progression.styles[style.name] or false, function(v)
            Config.data.progression.styles[style.name] = v
            Config.dirty = true
            if v then Progression.buyStyle(style) end
        end)
    end

    local card3 = sectionCard(page, 0)
    card3.Size = UDim2.new(1, -8, 0, 0)
    card3.AutomaticSize = Enum.AutomaticSize.Y
    sectionTitle(card3, "GUNS")
    local inner3 = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, 26),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = card3,
    })
    listLayout(inner3, 0)
    for i = 1, #GUNS do
        local gun = GUNS[i]
        makeToggle(inner3, gun.name, Config.data.progression.guns[gun.name] or false, function(v)
            Config.data.progression.guns[gun.name] = v
            Config.dirty = true
            if v then Progression.buyGun(gun) end
        end)
    end

    local card4 = sectionCard(page, 0)
    card4.Size = UDim2.new(1, -8, 0, 0)
    card4.AutomaticSize = Enum.AutomaticSize.Y
    sectionTitle(card4, "SWORDS")
    local inner4 = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, 26),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = card4,
    })
    listLayout(inner4, 0)
    for i = 1, #SWORDS do
        local sword = SWORDS[i]
        makeToggle(inner4, sword.name, Config.data.progression.swords[sword.name] or false, function(v)
            Config.data.progression.swords[sword.name] = v
            Config.dirty = true
            if v then Progression.buySword(sword) end
        end)
    end

    local card5 = sectionCard(page, 0)
    card5.Size = UDim2.new(1, -8, 0, 0)
    card5.AutomaticSize = Enum.AutomaticSize.Y
    sectionTitle(card5, "LEGENDARY WEAPONS")
    local inner5 = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, 26),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = card5,
    })
    listLayout(inner5, 0)
    for i = 1, #LEGENDARY do
        local lw = LEGENDARY[i]
        makeToggle(inner5, lw.name, Config.data.progression.legendaries[lw.name] or false, function(v)
            Config.data.progression.legendaries[lw.name] = v
            Config.dirty = true
            if v then task.spawn(Progression.legendaryChain, lw.name, State.generation) end
        end)
    end

    local card6 = sectionCard(page, 0)
    card6.Size = UDim2.new(1, -8, 0, 0)
    card6.AutomaticSize = Enum.AutomaticSize.Y
    sectionTitle(card6, "RACES")
    local inner6 = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, 26),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = card6,
    })
    listLayout(inner6, 0)
    for i = 1, #RACES do
        local race = RACES[i]
        makeToggle(inner6, race, false, function(v)
            if v then task.spawn(Progression.raceUnlock, race, State.generation) end
        end)
    end
end

local function buildUtilityTab()
    local page = UI.tabs["Utility"].page

    local card = sectionCard(page, 0)
    card.Size = UDim2.new(1, -8, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    sectionTitle(card, "ESP")
    local inner = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, 26),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = card,
    })
    listLayout(inner, 0)
    makeToggle(inner, "Players", Config.data.util.espPlayers, function(v) configSet({ "util", "espPlayers" }, v) end)
    makeToggle(inner, "Enemies", Config.data.util.espEnemies, function(v) configSet({ "util", "espEnemies" }, v) end)
    makeToggle(inner, "Fruits", Config.data.util.espFruits, function(v) configSet({ "util", "espFruits" }, v) end)
    makeToggle(inner, "Chests", Config.data.util.espChests, function(v) configSet({ "util", "espChests" }, v) end)
    makeToggle(inner, "NPCs", Config.data.util.espNpcs, function(v) configSet({ "util", "espNpcs" }, v) end)
    makeToggle(inner, "Sea Beasts", Config.data.util.espSeaBeasts, function(v) configSet({ "util", "espSeaBeasts" }, v) end)
    makeSlider(inner, "Distance Cull", 0, 2000, Config.data.util.espDistance, function(v)
        configSet({ "util", "espDistance" }, v)
    end)
    makeSlider(inner, "Draw Cap", 0, 300, Config.data.util.espCap, function(v)
        configSet({ "util", "espCap" }, v)
    end)

    local card2 = sectionCard(page, 0)
    card2.Size = UDim2.new(1, -8, 0, 0)
    card2.AutomaticSize = Enum.AutomaticSize.Y
    sectionTitle(card2, "AIMBOT")
    local inner2 = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, 26),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = card2,
    })
    listLayout(inner2, 0)
    makeToggle(inner2, "Enable Aimbot", Config.data.util.aimbot, function(v) configSet({ "util", "aimbot" }, v) end)
    makeSlider(inner2, "FOV", 10, 400, Config.data.util.aimFov, function(v)
        configSet({ "util", "aimFov" }, v)
    end)
    makeSlider(inner2, "Smoothing x100", 2, 100, math.floor(Config.data.util.aimSmooth * 100), function(v)
        configSet({ "util", "aimSmooth" }, v / 100)
    end)
    makeDropdown(inner2, "Aim Part", { "Head", "HumanoidRootPart", "Torso", "UpperTorso" }, Config.data.util.aimPart, function(v)
        configSet({ "util", "aimPart" }, v)
    end)

    local card3 = sectionCard(page, 0)
    card3.Size = UDim2.new(1, -8, 0, 0)
    card3.AutomaticSize = Enum.AutomaticSize.Y
    sectionTitle(card3, "FRUIT SNIPER")
    local inner3 = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, 26),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = card3,
    })
    listLayout(inner3, 0)
    makeTextBox(inner3, "Name Filter", Config.data.util.fruitFilter, "any", function(v)
        configSet({ "util", "fruitFilter" }, v)
    end)
    makeToggle(inner3, "Auto Store Fruit", Config.data.util.autoStore, function(v) configSet({ "util", "autoStore" }, v) end)
    makeToggle(inner3, "Auto Sell", Config.data.util.autoSell, function(v)
        configSet({ "util", "autoSell" }, v)
        if v then Economy.sellAll() end
    end)
    makeButton(inner3, "Store All Fruit Now", function()
        Discovery.invoke("StoreFruit", "All")
    end)

    local card4 = sectionCard(page, 0)
    card4.Size = UDim2.new(1, -8, 0, 0)
    card4.AutomaticSize = Enum.AutomaticSize.Y
    sectionTitle(card4, "TELEPORT")
    local inner4 = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, 26),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = card4,
    })
    listLayout(inner4, 0)
    local islandNames = {}
    for i = 1, #ISLANDS do table.insert(islandNames, ISLANDS[i].name) end
    makeDropdown(inner4, "Island", islandNames, "Bandits", function(v)
        Config.data._pendingIsland = v
    end)
    makeButton(inner4, "Teleport To Island", function()
        Teleport.toIsland(Config.data._pendingIsland or "Bandits")
    end)
    makeButton(inner4, "Back To Spawn", function() Teleport.toSpawn() end)
    makeTextBox(inner4, "Waypoint Name", "", "name", function(v)
        Config.data._waypointName = v
    end)
    makeButton(inner4, "Save Waypoint", function()
        local n = Config.data._waypointName
        if type(n) == "string" and n ~= "" then Teleport.saveWaypoint(n) end
    end)
    makeButton(inner4, "Go To Waypoint", function()
        local n = Config.data._waypointName
        if type(n) == "string" and n ~= "" then Teleport.gotoWaypoint(n) end
    end)

    local card5 = sectionCard(page, 0)
    card5.Size = UDim2.new(1, -8, 0, 0)
    card5.AutomaticSize = Enum.AutomaticSize.Y
    sectionTitle(card5, "SERVER")
    local inner5 = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, 26),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = card5,
    })
    listLayout(inner5, 0)
    makeSlider(inner5, "Min Players", 0, 50, Config.data.util.hopMinPlayers, function(v)
        configSet({ "util", "hopMinPlayers" }, v)
    end)
    makeButton(inner5, "Server Hop", function() ServerHop.hop() end)
    makeToggle(inner5, "Anti AFK", Config.data.util.antiAfk, function(v) configSet({ "util", "antiAfk" }, v) end)
    makeToggle(inner5, "Auto Rejoin", Config.data.util.autoRejoin, function(v) configSet({ "util", "autoRejoin" }, v) end)
end

local function buildSettingsTab()
    local page = UI.tabs["Settings"].page
    local card = sectionCard(page, 0)
    card.Size = UDim2.new(1, -8, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    sectionTitle(card, "INTERFACE")
    local inner = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, 26),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = card,
    })
    listLayout(inner, 0)
    makeToggle(inner, "Snow", Config.data.ui.snow, function(v)
        configSet({ "ui", "snow" }, v)
        if v then
            buildSnow(UI.window)
        else
            UI.snowActive = false
            for i = 1, #UI.snow do pcall(function() UI.snow[i]:Destroy() end) end
            UI.snow = {}
        end
    end)
    makeToggle(inner, "Blur", Config.data.ui.blur, function(v)
        configSet({ "ui", "blur" }, v)
        applyBlur()
    end)
    makeKeybind(inner, "Toggle UI", Config.data.keys.toggleUi, function(k)
        configSet({ "keys", "toggleUi" }, k)
    end)
    makeKeybind(inner, "Toggle Farm", Config.data.keys.toggleFarm, function(k)
        configSet({ "keys", "toggleFarm" }, k)
    end)
    makeKeybind(inner, "Panic Unload", Config.data.keys.panic, function(k)
        configSet({ "keys", "panic" }, k)
    end)

    local card2 = sectionCard(page, 0)
    card2.Size = UDim2.new(1, -8, 0, 0)
    card2.AutomaticSize = Enum.AutomaticSize.Y
    sectionTitle(card2, "RUNTIME")
    local inner2 = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, 26),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = card2,
    })
    listLayout(inner2, 0)
    makeLabel(inner2, "Platform: " .. PLATFORM.os .. "   Hz: " .. tostring(PLATFORM.hz), PAL.text)
    makeLabel(inner2, "Executor: " .. PLATFORM.executor, PAL.muted)
    makeLabel(inner2, "Drawing: " .. tostring(PLATFORM.drawing) .. "   GUI: " .. tostring(PLATFORM.guiParent ~= nil), PAL.muted)
    makeLabel(inner2, "Filesystem: " .. (PLATFORM.fs and "config saved" or "config not saved (no filesystem)"), PLATFORM.fs and PAL.success or PAL.danger)
    makeButton(inner2, "Save Config", function() configSave() end)
    makeButton(inner2, "Reset Config", function()
        Config.data = Util.deepCopy(DEFAULTS)
        clampAll()
        configSave()
    end)
    makeButton(inner2, "Unload Frost Hub", function()
        runTeardown()
        if UI.screen then pcall(function() UI.screen:Destroy() end) end
        ENV[SENTINEL_KEY] = nil
    end, true)
end

local function buildMobilePad()
    if not PLATFORM.mobile then return end
    local parent = PLATFORM.guiParent
    if not parent then return end
    local padGui = new("ScreenGui", {
        Name = "p" .. STABLE_TAG,
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 998,
        Parent = parent,
    })
    local pad = new("TextButton", {
        Size = UDim2.fromOffset(52, 52),
        Position = UDim2.new(0, 16, 0.5, -26),
        BackgroundColor3 = PAL.panel,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Text = "",
        Parent = padGui,
    })
    corner(pad, 26)
    local ps = stroke(pad, PAL.accent, 0.45, 1)
    snowflakeIcon(pad, 22).Position = UDim2.fromOffset(15, 15)
    pad.MouseEnter:Connect(function() ps.Transparency = 0.3 end)
    pad.MouseLeave:Connect(function() ps.Transparency = 0.45 end)
    pad.MouseButton1Click:Connect(function()
        Config.data.ui.visible = not Config.data.ui.visible
        if UI.screen then UI.screen.Enabled = Config.data.ui.visible end
    end)
    local dragging = false
    local dragStart, startPos
    pad.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = pad.Position
        end
    end)
    pad.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            pad.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    pad.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    registerTeardown(function() pcall(function() padGui:Destroy() end) end)
end

local Loops = {
    running = true,
}

local function managerTick()
    local generation = State.generation
    while Loops.running do
        if generation ~= State.generation then
            generation = State.generation
        end
        pcall(refreshState)
        pcall(Watchdog.tick)
        pcall(Discovery.sweep)
        pcall(Aimbot.tick)
        if Config.data.util.espPlayers then pcall(ESP.refresh) end
        if UI.statusLeft then
            local xp = Leveling.xpPerHour()
            local eta = 0
            if xp > 0 and State.level < Config.data.leveling.targetLevel then
                eta = math.floor((Config.data.leveling.targetLevel - State.level) * 50)
            end
            local parts = {
                State.stateText,
                State.currentTarget,
                tostring(State.ping) .. "ms",
                "Lv" .. tostring(State.level),
                tostring(xp) .. " xp/h",
                eta > 0 and (eta .. "m") or "-",
                "b" .. tostring(State.bones),
                "t" .. tostring(State.tokens),
            }
            UI.statusLeft.Text = table.concat(parts, " | ")
        end
        task.wait(SCAN_TICK * 2)
    end
end

local function mainLoop()
    while Loops.running do
        if UI.snowActive then pcall(snowStep) end
        if Config.dirty and PLATFORM.fs then configSave() end
        task.wait(TICK)
    end
end

local function bindKeys()
    if not UserInputService then return end
    local conn = UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        local key = input.KeyCode.Name
        if key == Config.data.keys.toggleUi and Config.data.keys.toggleUi ~= "Touch" then
            Config.data.ui.visible = not Config.data.ui.visible
            if UI.screen then UI.screen.Enabled = Config.data.ui.visible end
        elseif key == Config.data.keys.toggleFarm and Config.data.keys.toggleFarm ~= "Touch" then
            local on = not Config.data.leveling.enabled
            configSet({ "leveling", "enabled" }, on)
            if on then task.spawn(Leveling.loop, State.generation) else Leveling.stop() end
        elseif key == Config.data.keys.panic and Config.data.keys.panic ~= "Touch" then
            Loops.running = false
            runTeardown()
            if UI.screen then pcall(function() UI.screen:Destroy() end) end
            if UI.blur then pcall(function() UI.blur:Destroy() end) end
            ENV[SENTINEL_KEY] = nil
        end
    end)
    registerTeardown(function() conn:Disconnect() end)
end

local function bindCharacter()
    if not LP then return end
    local conn = LP.CharacterAdded:Connect(function(c)
        State.generation = State.generation + 1
        Movement.gen = State.generation
        Combat.gen = State.generation
        task.wait(1.2)
        local hum = c:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.Died:Connect(function()
                Watchdog.recordDeath()
            end)
        end
        if Config.data.leveling.enabled then
            task.spawn(Leveling.loop, State.generation)
        end
    end)
    registerTeardown(function() conn:Disconnect() end)
    if LP.Character then
        local hum = LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.Died:Connect(function() Watchdog.recordDeath() end)
        end
    end
end

pcall(function()
    buildWindow()
    pcall(buildFarmTab)
    pcall(buildLevelTab)
    pcall(buildEventsTab)
    pcall(buildProgressionTab)
    pcall(buildUtilityTab)
    pcall(buildSettingsTab)
    pcall(buildMobilePad)
    pcall(applyBlur)
    pcall(bindKeys)
    pcall(bindCharacter)
    pcall(AntiAfk.start)
    task.spawn(managerTick)
    task.spawn(mainLoop)
    if Config.data.ui.snow then pcall(buildSnow, UI.window) end
end)

ENV[SENTINEL_KEY] = {
    gui = UI.screen,
    blur = UI.blur,
    teardown = function()
        Loops.running = false
        Leveling.stop()
        Farm.active = false
        Events.raidActive = false
        runTeardown()
        pcall(ESP.teardown)
        if UI.blur then pcall(function() UI.blur:Destroy() end) end
        if UI.screen then pcall(function() UI.screen:Destroy() end) end
        for i = 1, #UI.snow do pcall(function() UI.snow[i]:Destroy() end) end
        UI.snow = {}
        UI.snowActive = false
        Movement.restore()
    end,
}

pcall(function()
    print("[Frost Hub] " .. VERSION .. " ready - " .. PLATFORM.os .. " @ " .. tostring(PLATFORM.hz) .. "hz")
end)
