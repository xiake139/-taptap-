---------------------------------------------------
-- DataManager.lua - 数据管理器
-- 负责加载系统配置和管理玩家数据
---------------------------------------------------
local IniParser = require("Utils.IniParser")

local DataManager = {}

-- 系统数据（只读）
DataManager.maps = {}
DataManager.monsters = {}
DataManager.npcs = {}
DataManager.items = {}
DataManager.equipment = {}
DataManager.quests = {}
DataManager.shops = {}
DataManager.dungeons = {}
DataManager.gameConfig = {}

-- 当前玩家数据
DataManager.playerData = nil
DataManager.currentAccount = nil

--- 加载所有系统配置
function DataManager.LoadSystemData()
    print("[DataManager] 加载系统配置...")

    DataManager.gameConfig = IniParser.LoadFile("Config/System/game_config.ini") or {}
    DataManager.maps = IniParser.LoadFile("Config/System/maps.ini") or {}
    DataManager.monsters = IniParser.LoadFile("Config/System/monsters.ini") or {}
    DataManager.npcs = IniParser.LoadFile("Config/System/npcs.ini") or {}
    DataManager.items = IniParser.LoadFile("Config/System/items.ini") or {}
    DataManager.equipment = IniParser.LoadFile("Config/System/equipment.ini") or {}
    DataManager.quests = IniParser.LoadFile("Config/System/quests.ini") or {}
    DataManager.shops = IniParser.LoadFile("Config/System/shops.ini") or {}
    DataManager.dungeons = IniParser.LoadFile("Config/System/dungeons.ini") or {}

    print("[DataManager] 地图数量: " .. DataManager.CountTable(DataManager.maps))
    print("[DataManager] 怪物数量: " .. DataManager.CountTable(DataManager.monsters))
    print("[DataManager] NPC数量: " .. DataManager.CountTable(DataManager.npcs))
    print("[DataManager] 物品数量: " .. DataManager.CountTable(DataManager.items))
    print("[DataManager] 装备数量: " .. DataManager.CountTable(DataManager.equipment))
    print("[DataManager] 任务数量: " .. DataManager.CountTable(DataManager.quests))
    print("[DataManager] 商店数量: " .. DataManager.CountTable(DataManager.shops))
    print("[DataManager] 副本数量: " .. DataManager.CountTable(DataManager.dungeons))
    print("[DataManager] 系统配置加载完成!")
end

--- 计算 table 中的键数量
function DataManager.CountTable(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

--- 创建新玩家数据
---@param username string 账号名
---@param charName string 角色名
---@return table playerData
function DataManager.CreateNewPlayer(username, charName)
    local defaults = DataManager.gameConfig["player_default"] or {}
    local startMap = DataManager.gameConfig["game"] and DataManager.gameConfig["game"]["start_map"] or "新手村"

    local playerData = {
        account = {
            username = username,
            char_name = charName,
            created_time = os.time and os.time() or 0,
        },
        status = {
            name = charName,
            level = defaults.level or 1,
            exp = defaults.exp or 0,
            hp = defaults.hp or 100,
            max_hp = defaults.hp or 100,
            mp = defaults.mp or 50,
            max_mp = defaults.mp or 50,
            atk = defaults.atk or 5,
            def = defaults.def or 3,
            gold = defaults.gold or 50,
            cultivation = defaults.cultivation or "练气期一层",
            current_map = startMap,
        },
        bag = {},       -- { {name="物品名", count=数量}, ... }
        equip = {       -- 装备槽
            weapon = "",
            armor = "",
            accessory = "",
        },
        quests = {
            active = {},     -- { {id="quest_id", progress=0}, ... }
            completed = {},  -- { "quest_id", ... }
        },
    }

    return playerData
end

--- 将玩家数据序列化为 INI sections
---@param playerData table
---@return table sections
function DataManager.PlayerDataToIni(playerData)
    local sections = {}

    -- account section
    sections["account"] = {}
    for k, v in pairs(playerData.account) do
        sections["account"][k] = tostring(v)
    end

    -- status section
    sections["status"] = {}
    for k, v in pairs(playerData.status) do
        sections["status"][k] = tostring(v)
    end

    -- bag section (item_1=物品名:数量)
    sections["bag"] = {}
    sections["bag"]["count"] = #playerData.bag
    for i, item in ipairs(playerData.bag) do
        sections["bag"]["item_" .. i] = item.name .. ":" .. item.count
    end

    -- equip section
    sections["equip"] = {}
    sections["equip"]["weapon"] = playerData.equip.weapon or ""
    sections["equip"]["armor"] = playerData.equip.armor or ""
    sections["equip"]["accessory"] = playerData.equip.accessory or ""

    -- quests section
    sections["quests_active"] = {}
    sections["quests_active"]["count"] = #playerData.quests.active
    for i, q in ipairs(playerData.quests.active) do
        sections["quests_active"]["quest_" .. i] = q.id .. ":" .. q.progress
    end

    sections["quests_completed"] = {}
    sections["quests_completed"]["count"] = #playerData.quests.completed
    for i, qid in ipairs(playerData.quests.completed) do
        sections["quests_completed"]["quest_" .. i] = qid
    end

    return sections
end

--- 从 INI sections 反序列化为玩家数据
---@param sections table
---@return table playerData
function DataManager.IniToPlayerData(sections)
    local playerData = {
        account = {},
        status = {},
        bag = {},
        equip = { weapon = "", armor = "", accessory = "" },
        quests = { active = {}, completed = {} },
    }

    -- account
    if sections["account"] then
        playerData.account = sections["account"]
    end

    -- status (convert numbers)
    if sections["status"] then
        for k, v in pairs(sections["status"]) do
            playerData.status[k] = v
        end
    end

    -- bag
    if sections["bag"] then
        local count = tonumber(sections["bag"]["count"]) or 0
        for i = 1, count do
            local raw = sections["bag"]["item_" .. i]
            if raw then
                local name, cnt = raw:match("^(.+):(%d+)$")
                if name then
                    table.insert(playerData.bag, { name = name, count = tonumber(cnt) or 1 })
                end
            end
        end
    end

    -- equip
    if sections["equip"] then
        playerData.equip.weapon = sections["equip"]["weapon"] or ""
        playerData.equip.armor = sections["equip"]["armor"] or ""
        playerData.equip.accessory = sections["equip"]["accessory"] or ""
    end

    -- quests active
    if sections["quests_active"] then
        local count = tonumber(sections["quests_active"]["count"]) or 0
        for i = 1, count do
            local raw = sections["quests_active"]["quest_" .. i]
            if raw then
                local id, progress = raw:match("^(.+):(%d+)$")
                if id then
                    table.insert(playerData.quests.active, { id = id, progress = tonumber(progress) or 0 })
                end
            end
        end
    end

    -- quests completed
    if sections["quests_completed"] then
        local count = tonumber(sections["quests_completed"]["count"]) or 0
        for i = 1, count do
            local qid = sections["quests_completed"]["quest_" .. i]
            if qid then
                table.insert(playerData.quests.completed, qid)
            end
        end
    end

    return playerData
end

--- 保存玩家数据到云端
---@param playerData table
---@param callback function|nil 完成回调
function DataManager.SaveToCloud(playerData, callback)
    if not clientCloud then
        print("[DataManager] clientCloud 不可用，跳过云端保存")
        if callback then callback(false) end
        return
    end

    local sections = DataManager.PlayerDataToIni(playerData)
    local iniContent = IniParser.Serialize(sections)

    clientCloud:Set("player_save", iniContent, {
        ok = function()
            print("[DataManager] 云端保存成功")
            if callback then callback(true) end
        end,
        error = function(code, reason)
            print("[DataManager] 云端保存失败: " .. tostring(reason))
            if callback then callback(false) end
        end,
    })
end

--- 从云端加载玩家数据
---@param callback function(playerData|nil)
function DataManager.LoadFromCloud(callback)
    if not clientCloud then
        print("[DataManager] clientCloud 不可用")
        callback(nil)
        return
    end

    clientCloud:Get("player_save", {
        ok = function(values, iscores)
            local iniContent = values.player_save
            if iniContent and type(iniContent) == "string" and iniContent ~= "" then
                local sections = IniParser.Parse(iniContent)
                local playerData = DataManager.IniToPlayerData(sections)
                print("[DataManager] 云端加载成功")
                callback(playerData)
            else
                print("[DataManager] 云端无存档")
                callback(nil)
            end
        end,
        error = function(code, reason)
            print("[DataManager] 云端加载失败: " .. tostring(reason))
            callback(nil)
        end,
    })
end

--- 获取地图信息
---@param mapName string
---@return table|nil
function DataManager.GetMap(mapName)
    return DataManager.maps[mapName]
end

--- 获取怪物信息
---@param monsterName string
---@return table|nil
function DataManager.GetMonster(monsterName)
    return DataManager.monsters[monsterName]
end

--- 获取NPC信息
---@param npcName string
---@return table|nil
function DataManager.GetNPC(npcName)
    return DataManager.npcs[npcName]
end

--- 获取物品信息
---@param itemName string
---@return table|nil
function DataManager.GetItem(itemName)
    -- 先从物品表找，再从装备表找
    if DataManager.items[itemName] then
        return DataManager.items[itemName]
    end
    if DataManager.equipment[itemName] then
        return DataManager.equipment[itemName]
    end
    return nil
end

--- 获取装备信息
---@param equipName string
---@return table|nil
function DataManager.GetEquipment(equipName)
    return DataManager.equipment[equipName]
end

--- 获取任务信息
---@param questId string
---@return table|nil
function DataManager.GetQuest(questId)
    return DataManager.quests[questId]
end

--- 获取商店信息
---@param shopId string
---@return table|nil
function DataManager.GetShop(shopId)
    return DataManager.shops[shopId]
end

--- 获取副本信息
---@param dungeonId string
---@return table|nil
function DataManager.GetDungeon(dungeonId)
    return DataManager.dungeons[dungeonId]
end

--- 获取升级所需经验
---@param level number
---@return number
function DataManager.GetExpForLevel(level)
    local config = DataManager.gameConfig["level_up"] or {}
    local baseExp = config.base_exp or 20
    local factor = config.exp_factor or 1.5
    return math.floor(baseExp * (level ^ factor))
end

--- 获取境界名称
---@param level number
---@return string
function DataManager.GetCultivation(level)
    local cultConfig = DataManager.gameConfig["cultivation"] or {}
    local result = "练气期一层"
    for lvlStr, name in pairs(cultConfig) do
        local lvl = tonumber(lvlStr)
        if lvl and level >= lvl then
            result = name
        end
    end
    return result
end

return DataManager
