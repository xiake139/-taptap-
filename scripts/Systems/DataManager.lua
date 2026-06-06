---------------------------------------------------
-- DataManager.lua - 数据管理器
-- 负责加载系统配置和管理玩家数据
---------------------------------------------------
local IniParser = require("Utils.IniParser")

local DataManager = {}

-- 注意：IniParser 仅用于玩家数据的云端序列化/反序列化
-- 系统配置使用 require 加载 Lua 数据模块（确保构建系统正确打包）

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
DataManager.currentPassword = nil

--- 加载所有系统配置
function DataManager.LoadSystemData()
    print("[DataManager] 加载系统配置...")

    DataManager.gameConfig = require("Config.game_config")
    DataManager.maps = require("Config.maps")
    DataManager.monsters = require("Config.monsters")
    DataManager.npcs = require("Config.npcs")
    DataManager.items = require("Config.items")
    DataManager.equipment = require("Config.equipment")
    DataManager.quests = require("Config.quests")
    DataManager.shops = require("Config.shops")
    DataManager.dungeons = require("Config.dungeons")

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
            password = DataManager.currentPassword or "",
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

--- 获取玩家云端存储路径前缀
---@param username string
---@return string
function DataManager.GetCloudPath(username)
    return "player/" .. username .. "/"
end

--- 将玩家数据序列化为多个 INI 文件内容
--- 每个文件对应一个云端 key: player/账号/文件名.ini
---@param playerData table
---@return table<string, string> fileMap {文件名 = INI内容}
function DataManager.PlayerDataToFiles(playerData)
    local files = {}

    -- 账号配置.ini
    local accountSections = {}
    accountSections["账号配置"] = {}
    local accountMap = {
        username = "用户名",
        password = "密码",
        char_name = "角色名",
        created_time = "创建时间",
    }
    for k, v in pairs(playerData.account) do
        local zhKey = accountMap[k] or k
        accountSections["账号配置"][zhKey] = tostring(v)
    end
    files["账号配置.ini"] = IniParser.Serialize(accountSections)

    -- 状态数据.ini
    local statusSections = {}
    statusSections["角色属性"] = {}
    local statusMap = {
        name = "姓名",
        level = "等级",
        exp = "经验",
        hp = "生命值",
        max_hp = "最大生命",
        mp = "法力值",
        max_mp = "最大法力",
        atk = "攻击力",
        def = "防御力",
        gold = "金币",
        cultivation = "境界",
        current_map = "当前地图",
    }
    for k, v in pairs(playerData.status) do
        local zhKey = statusMap[k] or k
        statusSections["角色属性"][zhKey] = tostring(v)
    end
    files["状态数据.ini"] = IniParser.Serialize(statusSections)

    -- 背包数据.ini
    local bagSections = {}
    bagSections["背包物品"] = {}
    bagSections["背包物品"]["数量"] = tostring(#playerData.bag)
    for i, item in ipairs(playerData.bag) do
        bagSections["背包物品"]["物品_" .. i] = item.name .. ":" .. item.count
    end
    files["背包数据.ini"] = IniParser.Serialize(bagSections)

    -- 装备数据.ini
    local equipSections = {}
    equipSections["装备栏"] = {}
    equipSections["装备栏"]["武器"] = playerData.equip.weapon or ""
    equipSections["装备栏"]["防具"] = playerData.equip.armor or ""
    equipSections["装备栏"]["饰品"] = playerData.equip.accessory or ""
    files["装备数据.ini"] = IniParser.Serialize(equipSections)

    -- 任务数据.ini
    local questSections = {}
    questSections["进行中任务"] = {}
    questSections["进行中任务"]["数量"] = tostring(#playerData.quests.active)
    for i, q in ipairs(playerData.quests.active) do
        questSections["进行中任务"]["任务_" .. i] = q.id .. ":" .. q.progress
    end
    questSections["已完成任务"] = {}
    questSections["已完成任务"]["数量"] = tostring(#playerData.quests.completed)
    for i, qid in ipairs(playerData.quests.completed) do
        questSections["已完成任务"]["任务_" .. i] = qid
    end
    files["任务数据.ini"] = IniParser.Serialize(questSections)

    return files
end

--- 从多个 INI 文件内容反序列化为玩家数据
---@param fileMap table<string, string> {文件名 = INI内容}
---@return table playerData
function DataManager.FilesToPlayerData(fileMap)
    local playerData = {
        account = {},
        status = {},
        bag = {},
        equip = { weapon = "", armor = "", accessory = "" },
        quests = { active = {}, completed = {} },
    }

    -- 中文键名 → 内部键名映射
    local accountReverseMap = {
        ["用户名"] = "username",
        ["密码"] = "password",
        ["角色名"] = "char_name",
        ["创建时间"] = "created_time",
    }
    local statusReverseMap = {
        ["姓名"] = "name",
        ["等级"] = "level",
        ["经验"] = "exp",
        ["生命值"] = "hp",
        ["最大生命"] = "max_hp",
        ["法力值"] = "mp",
        ["最大法力"] = "max_mp",
        ["攻击力"] = "atk",
        ["防御力"] = "def",
        ["金币"] = "gold",
        ["境界"] = "cultivation",
        ["当前地图"] = "current_map",
    }

    -- 解析 账号配置.ini
    if fileMap["账号配置.ini"] then
        local sections = IniParser.Parse(fileMap["账号配置.ini"])
        local accSection = sections["账号配置"] or sections["account"]
        if accSection then
            for k, v in pairs(accSection) do
                local internalKey = accountReverseMap[k] or k
                playerData.account[internalKey] = v
            end
        end
    end

    -- 解析 状态数据.ini
    if fileMap["状态数据.ini"] then
        local sections = IniParser.Parse(fileMap["状态数据.ini"])
        local statusSection = sections["角色属性"] or sections["status"]
        if statusSection then
            for k, v in pairs(statusSection) do
                local internalKey = statusReverseMap[k] or k
                playerData.status[internalKey] = v
            end
        end
    end

    -- 解析 背包数据.ini
    if fileMap["背包数据.ini"] then
        local sections = IniParser.Parse(fileMap["背包数据.ini"])
        local bagSection = sections["背包物品"] or sections["bag"]
        if bagSection then
            local count = tonumber(bagSection["数量"] or bagSection["count"]) or 0
            for i = 1, count do
                local raw = bagSection["物品_" .. i] or bagSection["item_" .. i]
                if raw then
                    local name, cnt = raw:match("^(.+):(%d+)$")
                    if name then
                        table.insert(playerData.bag, { name = name, count = tonumber(cnt) or 1 })
                    end
                end
            end
        end
    end

    -- 解析 装备数据.ini
    if fileMap["装备数据.ini"] then
        local sections = IniParser.Parse(fileMap["装备数据.ini"])
        local equipSection = sections["装备栏"] or sections["equip"]
        if equipSection then
            playerData.equip.weapon = equipSection["武器"] or equipSection["weapon"] or ""
            playerData.equip.armor = equipSection["防具"] or equipSection["armor"] or ""
            playerData.equip.accessory = equipSection["饰品"] or equipSection["accessory"] or ""
        end
    end

    -- 解析 任务数据.ini
    if fileMap["任务数据.ini"] then
        local sections = IniParser.Parse(fileMap["任务数据.ini"])
        local activeSection = sections["进行中任务"] or sections["quests_active"]
        if activeSection then
            local count = tonumber(activeSection["数量"] or activeSection["count"]) or 0
            for i = 1, count do
                local raw = activeSection["任务_" .. i] or activeSection["quest_" .. i]
                if raw then
                    local id, progress = raw:match("^(.+):(%d+)$")
                    if id then
                        table.insert(playerData.quests.active, { id = id, progress = tonumber(progress) or 0 })
                    end
                end
            end
        end

        local completedSection = sections["已完成任务"] or sections["quests_completed"]
        if completedSection then
            local count = tonumber(completedSection["数量"] or completedSection["count"]) or 0
            for i = 1, count do
                local qid = completedSection["任务_" .. i] or completedSection["quest_" .. i]
                if qid then
                    table.insert(playerData.quests.completed, qid)
                end
            end
        end
    end

    return playerData
end

--- 云端文件名列表
DataManager.CLOUD_FILES = { "账号配置.ini", "状态数据.ini", "背包数据.ini", "装备数据.ini", "任务数据.ini" }

--- 保存玩家数据到云端（拆分为多个文件）
--- 存储结构: player/账号名/账号配置.ini, player/账号名/状态数据.ini, ...
---@param playerData table
---@param callback function|nil 完成回调
function DataManager.SaveToCloud(playerData, callback)
    if not clientCloud then
        print("[DataManager] clientCloud 不可用，跳过云端保存")
        if callback then callback(false) end
        return
    end

    local username = playerData.account.username or "unknown"
    local path = DataManager.GetCloudPath(username)
    local files = DataManager.PlayerDataToFiles(playerData)

    print("[DataManager] 保存到云端: " .. path)

    local batch = clientCloud:BatchSet()
    for fileName, content in pairs(files) do
        batch:Set(path .. fileName, content)
    end
    batch:Save("保存玩家数据", {
        ok = function()
            print("[DataManager] 云端保存成功 (" .. path .. ")")
            if callback then callback(true) end
        end,
        error = function(code, reason)
            print("[DataManager] 云端保存失败: " .. tostring(reason))
            if callback then callback(false) end
        end,
    })
end

--- 从云端加载玩家数据（批量读取多个文件）
---@param callback function(playerData|nil)
---@param username string|nil 指定账号名（可选，默认用 currentAccount）
function DataManager.LoadFromCloud(callback, username)
    if not clientCloud then
        print("[DataManager] clientCloud 不可用")
        callback(nil)
        return
    end

    local name = username or DataManager.currentAccount
    if not name or name == "" then
        -- 没有指定账号，尝试用通配方式检查是否有存档
        -- 先尝试读取旧格式（兼容）
        clientCloud:Get("player_save", {
            ok = function(values, iscores)
                local iniContent = values.player_save
                if iniContent and type(iniContent) == "string" and iniContent ~= "" then
                    -- 旧格式存档，迁移解析
                    print("[DataManager] 检测到旧格式存档，进行兼容加载")
                    local sections = IniParser.Parse(iniContent)
                    local accSection = sections["账号配置"] or sections["account"]
                    if accSection then
                        local oldName = accSection["用户名"] or accSection["username"]
                        if oldName then
                            -- 用旧存档的账号名加载新格式
                            DataManager.LoadFromCloud(callback, oldName)
                            return
                        end
                    end
                    -- 直接用旧格式解析
                    local content = tostring(iniContent)
                    local fileMap = { ["账号配置.ini"] = content, ["状态数据.ini"] = content,
                        ["背包数据.ini"] = content, ["装备数据.ini"] = content, ["任务数据.ini"] = content }
                    local playerData = DataManager.FilesToPlayerData(fileMap)
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
        return
    end

    local path = DataManager.GetCloudPath(name)
    print("[DataManager] 从云端加载: " .. path)

    local batch = clientCloud:BatchGet()
    for _, fileName in ipairs(DataManager.CLOUD_FILES) do
        batch:Key(path .. fileName)
    end
    batch:Fetch({
        ok = function(values, iscores)
            -- 检查是否有数据
            local firstKey = path .. "账号配置.ini"
            local accountContent = values[firstKey]
            if not accountContent or accountContent == "" then
                -- 新格式无数据，尝试旧格式兼容
                clientCloud:Get("player_save", {
                    ok = function(oldValues, _)
                        local iniContent = oldValues.player_save
                        if iniContent and type(iniContent) == "string" and iniContent ~= "" then
                            -- 旧格式存档：必须验证用户名一致才返回
                            local sections = IniParser.Parse(iniContent)
                            local accSection = sections["账号配置"] or sections["account"]
                            local oldUsername = accSection and (accSection["用户名"] or accSection["username"])
                            if oldUsername and oldUsername == name then
                                print("[DataManager] 兼容加载旧格式存档: " .. name)
                                local fileMap = { ["账号配置.ini"] = iniContent, ["状态数据.ini"] = iniContent,
                                    ["背包数据.ini"] = iniContent, ["装备数据.ini"] = iniContent, ["任务数据.ini"] = iniContent }
                                local playerData = DataManager.FilesToPlayerData(fileMap)
                                callback(playerData)
                            else
                                -- 旧格式用户名不匹配，视为无此账号
                                print("[DataManager] 旧格式用户名不匹配 (需要:" .. name .. " 实际:" .. tostring(oldUsername) .. ")")
                                callback(nil)
                            end
                        else
                            print("[DataManager] 云端无存档")
                            callback(nil)
                        end
                    end,
                    error = function()
                        callback(nil)
                    end,
                })
                return
            end

            -- 新格式：组装文件映射
            local fileMap = {}
            for _, fileName in ipairs(DataManager.CLOUD_FILES) do
                local key = path .. fileName
                if values[key] and values[key] ~= "" then
                    fileMap[fileName] = values[key]
                end
            end

            local playerData = DataManager.FilesToPlayerData(fileMap)
            print("[DataManager] 云端加载成功 (" .. path .. ")")
            callback(playerData)
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
