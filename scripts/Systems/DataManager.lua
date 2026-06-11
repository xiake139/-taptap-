---------------------------------------------------
-- DataManager.lua - 数据管理器
-- 负责加载系统配置和管理玩家数据
---------------------------------------------------
local IniParser = require("Utils.IniParser")
local ConfigData = require("Config.ConfigData")
local NumFormat = require("Utils.NumFormat")
local BigNum = require("Utils.BigNum")

local DataManager = {}

-- 云存储提供者（默认 clientCloud，联网模式下替换为 CloudProxy）
local cloud_ = clientCloud

--- 设置云存储提供者（由 main.lua 在联网模式下调用）
---@param provider table 提供 Get/Set/BatchGet/BatchSet 接口的对象
function DataManager.SetCloudProvider(provider)
    cloud_ = provider
    print("[DataManager] 云存储提供者已切换")
end

--- 获取当前云存储提供者（供其他模块如 AdminUI 使用）
---@return table
function DataManager.GetCloudProvider()
    return cloud_
end

-- 所有系统配置均使用 INI 文件存储（中文键名）
-- IniParser 用于解析系统配置和玩家数据

-- 系统数据（只读）
DataManager.maps = {}
DataManager.monsters = {}
DataManager.npcs = {}
DataManager.items = {}
DataManager.equipment = {}
DataManager.quests = {}
DataManager.shops = {}
DataManager.systemShops = {}  -- 系统商店（功能按键入口，独立于NPC商店）
DataManager.dungeons = {}
DataManager.giftpacks = {}
DataManager.realms = {}       -- 境界配置列表（按阶段排序）
DataManager.realmsByStage = {} -- 按阶段索引 { [阶段数字] = realmData }
DataManager.realmPills = {}   -- 境界经验丹配置 { [名称] = { name, desc, value } }
DataManager.admins = {}  -- 管理员列表 { [username] = true }
DataManager.leaderboards = {}
DataManager.rankingData = {}  -- 所有玩家的排行数据 { [玩家名] = { 名称=xx, 等级=xx, ... } }
DataManager.chatMessages = {} -- 聊天记录列表 { {sender=xx, content=xx, time=xx}, ... }
DataManager.petConfig = {    -- 宠物成长配置（公式化）
    -- 升星消耗公式：数量 = star_cost_base + star_cost_growth × 当前星级
    star_cost_material = "升星石",
    star_cost_base = 100,       -- 0星→1星消耗
    star_cost_growth = 100,     -- 每级递增
    star_max_level = 10,        -- 升星上限（后台可配置）
    -- 进阶消耗公式：数量 = adv_cost_base + adv_cost_growth × 当前阶数（最高10阶）
    adv_cost_material = "进阶丹",
    adv_cost_base = 30,         -- 0阶→1阶消耗
    adv_cost_growth = 20,       -- 每级递增
    adv_max_level = 10,         -- 进阶上限（固定10阶）
    -- 品质消耗（品质有上限：白→绿→...→神，共10级）
    quality_cost = {
        ["白"] = "品质精华:200", ["绿"] = "品质精华:400", ["蓝"] = "品质精华:600",
        ["紫"] = "品质精华:800", ["橙"] = "品质精华:1000", ["红"] = "品质精华:2000",
        ["金"] = "品质精华:2000", ["圣"] = "品质精华:3000", ["仙"] = "品质精华:3000", ["神"] = "品质精华:5000",
    },
    -- 属性加成公式（递增）：第N级加成 = base + growth × (N-1)
    -- 例: base=10, growth=5 → 第1级+10, 第2级+15, 第3级+20 ...
    star_bonus = { atk = 10, def = 6, hp = 50, atk_g = 5, def_g = 3, hp_g = 25 },
    advance_bonus = { atk = 20, def = 12, hp = 100, atk_g = 10, def_g = 6, hp_g = 50 },
    quality_bonus = { atk = 15, def = 8, hp = 60, atk_g = 8, def_g = 4, hp_g = 30 },
}
DataManager.petTypes = {}    -- 宠物种类配置 { [id] = { name, desc, atk, def, max_hp, quality, skill } }
DataManager.battleSoulConfig = {
    -- 怪物类型 → 战魂获取区间 { [怪物类型] = { min, max } }
    monster_soul = {},
    -- 升级公式: need = base + growth * (level - 1) ^ power
    level_formula = { base = "100", growth = "50", power = "1.5" },
    -- 每级属性加成: { atk = "5", def = "3", max_hp = "20" }
    level_bonus = { atk = "5", def = "3", max_hp = "20" },
}
DataManager.gameConfig = {}

-- 当前玩家数据
DataManager.playerData = nil
DataManager.currentAccount = nil
DataManager.currentPassword = nil

--- 读取本地 INI 配置文件内容
---@param path string 资源路径（相对于资源根目录）
---@return string|nil content
local function ReadConfigFile(path)
    local file = cache:GetFile(path)
    if not file then
        print("[DataManager] 无法读取配置: " .. path)
        return nil
    end
    local lines = {}
    while not file.eof do
        lines[#lines + 1] = file:ReadLine()
    end
    file:Close()
    return table.concat(lines, "\n")
end

--- 解析 game_config.ini → gameConfig 表
local function ParseGameConfig(sections)
    local config = {}
    -- 游戏设置
    local gameSec = sections["游戏设置"]
    if gameSec then
        config["game"] = {
            title = gameSec["标题"] or "修仙游戏",
            version = gameSec["版本"] or "1.0.0",
            start_map = gameSec["起始地图"] or "新手村",
            start_quest = gameSec["起始任务"] or "main_001",
        }
    end
    -- 玩家默认属性
    local defSec = sections["玩家默认属性"]
    if defSec then
        config["player_default"] = {
            hp = defSec["生命值"] or "100",
            mp = defSec["法力值"] or "50",
            atk = defSec["攻击力"] or "5",
            def = defSec["防御力"] or "3",
            level = defSec["等级"] or "1",
            exp = defSec["经验"] or "0",
            gold = defSec["金币"] or "50",
        }
    end
    -- 升级配置
    local lvlSec = sections["升级配置"]
    if lvlSec then
        config["level_up"] = {
            base_exp = lvlSec["基础经验"] or "20",
            exp_factor = tonumber(lvlSec["经验系数"]) or 2,
            hp_per_level = lvlSec["每级生命"] or "20",
            mp_per_level = lvlSec["每级法力"] or "10",
            atk_per_level = lvlSec["每级攻击"] or "3",
            def_per_level = lvlSec["每级防御"] or "2",
            max_level = lvlSec["最高等级"] or "100",
        }
    end
    -- 货币配置
    local currSec = sections["货币配置"]
    if currSec then
        local list = {}
        local count = tonumber(currSec["货币数量"]) or 0
        for i = 1, count do
            local name = currSec["货币_" .. i]
            if name and name ~= "" then
                table.insert(list, name)
            end
        end
        if #list == 0 then
            table.insert(list, "金币")
        end
        config["currencies"] = list
    else
        config["currencies"] = { "金币" }
    end
    -- 怪物生成区间配置
    local monGenSec = sections["怪物生成配置"]
    if monGenSec then
        local types = {}
        local count = tonumber(monGenSec["类型数量"]) or 0
        for i = 1, count do
            local name = monGenSec["类型" .. i .. "_名称"]
            if name and name ~= "" then
                -- 兼容旧格式（单一 下限/上限）
                local oldMin = monGenSec["类型" .. i .. "_下限"] or "10"
                local oldMax = monGenSec["类型" .. i .. "_上限"] or "2000"
                -- 新格式：独立 HP/ATK/DEF 区间
                local entry = {
                    name = name,
                    min_hp = monGenSec["类型" .. i .. "_HP下限"] or oldMin,
                    max_hp = monGenSec["类型" .. i .. "_HP上限"] or oldMax,
                    min_atk = monGenSec["类型" .. i .. "_攻击下限"] or oldMin,
                    max_atk = monGenSec["类型" .. i .. "_攻击上限"] or oldMax,
                    min_def = monGenSec["类型" .. i .. "_防御下限"] or oldMin,
                    max_def = monGenSec["类型" .. i .. "_防御上限"] or oldMax,
                    min_exp = monGenSec["类型" .. i .. "_经验下限"] or oldMin,
                    max_exp = monGenSec["类型" .. i .. "_经验上限"] or oldMax,
                    desc = monGenSec["类型" .. i .. "_描述"] or "",
                    -- 保留旧字段供兼容
                    min = oldMin,
                    max = oldMax,
                }
                -- 货币区间（多货币支持）
                local currCount = tonumber(monGenSec["类型" .. i .. "_货币数量"]) or 0
                local currRanges = {}
                for ci = 1, currCount do
                    local cName = monGenSec["类型" .. i .. "_货币" .. ci .. "_名称"]
                    if cName and cName ~= "" then
                        currRanges[cName] = {
                            min = monGenSec["类型" .. i .. "_货币" .. ci .. "_下限"] or "0",
                            max = monGenSec["类型" .. i .. "_货币" .. ci .. "_上限"] or "0",
                        }
                    end
                end
                -- 兼容旧金币字段
                if currCount == 0 then
                    local oldGoldMin = monGenSec["类型" .. i .. "_金币下限"] or oldMin
                    local oldGoldMax = monGenSec["类型" .. i .. "_金币上限"] or oldMax
                    currRanges["金币"] = { min = oldGoldMin, max = oldGoldMax }
                end
                entry.currency_ranges = currRanges
                table.insert(types, entry)
            end
        end
        if #types > 0 then
            config["monster_gen"] = types
        end
    end
    return config
end

--- 解析 maps.ini → maps 表
local function ParseMaps(sections)
    local maps = {}
    for sectionName, data in pairs(sections) do
        local mapEntry = {
            name = data["名称"] or sectionName,
            desc = data["描述"] or "",
            monsters = data["怪物"] or "",
            npcs = data["NPC"] or "",
            front = data["前方"] or "",
            back = data["后方"] or "",
            left = data["左方"] or "",
            right = data["右方"] or "",
            level_req = tonumber(data["等级要求"]) or 0,
        }
        maps[sectionName] = mapEntry
    end
    return maps
end

--- 怪物类型分类阈值（按HP判断，从高到低匹配）
local MONSTER_TYPE_THRESHOLDS = {
    { name = "创世级", min = "60000000000" },
    { name = "神级",   min = "5000000000" },
    { name = "仙级",   min = "600000000" },
    { name = "帝级",   min = "3000000" },
    { name = "BOSS",   min = "500000" },
    { name = "精英怪", min = "3000" },
    { name = "普通怪", min = "0" },
}

--- 根据怪物HP自动判断怪物类型
---@param hp string HP值
---@return string 怪物类型名称
local function ClassifyMonsterType(hp)
    local hpStr = tostring(hp or "0")
    for _, threshold in ipairs(MONSTER_TYPE_THRESHOLDS) do
        if BigNum.gte(hpStr, threshold.min) then
            return threshold.name
        end
    end
    return "普通怪"
end

--- 解析 monsters.ini → monsters 表
local function ParseMonsters(sections)
    local monsters = {}
    for sectionName, data in pairs(sections) do
        local hp = data["生命值"] or "20"
        local entry = {
            name = data["名称"] or sectionName,
            type = ClassifyMonsterType(hp),
            desc = data["描述"] or "",
            hp = hp,
            atk = data["攻击力"] or "3",
            def = data["防御力"] or "1",
            exp = data["经验值"] or "5",
            gold = data["金币"] or "2",
            drops = data["掉落"] or "",
        }
        -- 解析多货币掉落
        local currCount = tonumber(data["货币数量"]) or 0
        if currCount > 0 then
            local currDrops = {}
            for ci = 1, currCount do
                local cName = data["货币" .. ci .. "_名称"]
                local cVal = data["货币" .. ci .. "_数量"] or "0"
                if cName and cName ~= "" then
                    currDrops[cName] = cVal
                end
            end
            entry.currency_drops = currDrops
        else
            -- 向后兼容：只有金币字段时，构建 currency_drops
            entry.currency_drops = { ["金币"] = entry.gold }
        end
        monsters[sectionName] = entry
    end
    return monsters
end

--- 解析 battle_soul.ini → battleSoulConfig
local function ParseBattleSoul(sections)
    local config = {
        monster_soul = {},
        level_formula = { base = "100", growth = "50", power = "1.5" },
        level_bonus = { atk = "5", def = "3", max_hp = "20" },
    }
    -- [升级公式] base=100, growth=50, power=1.5
    local formulaSec = sections["升级公式"]
    if formulaSec then
        config.level_formula.base = formulaSec["基础值"] or "100"
        config.level_formula.growth = formulaSec["成长值"] or "50"
        config.level_formula.power = formulaSec["幂次"] or "1.5"
    end
    -- [每级属性加成] atk=5, def=3, max_hp=20
    local bonusSec = sections["每级属性加成"]
    if bonusSec then
        config.level_bonus.atk = bonusSec["攻击力"] or "5"
        config.level_bonus.def = bonusSec["防御力"] or "3"
        config.level_bonus.max_hp = bonusSec["生命上限"] or "20"
    end
    -- [怪物战魂] 每个怪物类型一个键，格式: 类型名=最小值-最大值
    local monsterSec = sections["怪物战魂"]
    if monsterSec then
        for typeName, rangeStr in pairs(monsterSec) do
            local minVal, maxVal = rangeStr:match("^(%d+)%-(%d+)$")
            if minVal and maxVal then
                config.monster_soul[typeName] = { min = minVal, max = maxVal }
            else
                -- 单值情况
                config.monster_soul[typeName] = { min = rangeStr, max = rangeStr }
            end
        end
    end
    return config
end

--- 解析 items.ini → items 表
local function ParseItems(sections)
    local items = {}
    for sectionName, data in pairs(sections) do
        local durVal = tonumber(data["持续时间"]) or 0
        local entry = {
            name = data["名称"] or sectionName,
            type = data["类型"] or "材料",
            value = data["数值"] or "0",
            duration = durVal > 0 and tostring(durVal) or nil,
            desc = data["描述"] or "",
        }
        -- 宠物装备额外字段
        if data["宠物部位"] then entry.pet_slot = data["宠物部位"] end
        if data["宠物攻击"] then entry.pet_atk = data["宠物攻击"] end
        if data["宠物防御"] then entry.pet_def = data["宠物防御"] end
        if data["宠物生命"] then entry.pet_hp = data["宠物生命"] end
        items[sectionName] = entry
    end
    return items
end

--- 解析 equipment.ini → equipment 表
local function ParseEquipment(sections)
    local equipment = {}
    for sectionName, data in pairs(sections) do
        local entry = {
            name = data["名称"] or sectionName,
            slot = data["部位"] or "武器",
            quality = data["品质"] or "白色",
            desc = data["描述"] or "",
            atk = data["攻击"] or "0",
            def = data["防御"] or "0",
            hp = data["生命"] or "0",
            level_req = data["等级需求"] or "1",
            price_buy = data["购买价"] or "0",
            price_sell = data["出售价"] or "0",
        }
        equipment[sectionName] = entry
    end
    return equipment
end

--- 解析 quests.ini → quests 表
local function ParseQuests(sections)
    local quests = {}
    for sectionName, data in pairs(sections) do
        local entry = {
            name = data["名称"] or sectionName,
            type = data["类型"] or "主线",
            desc = data["描述"] or "",
            target_type = data["目标类型"] or "击杀",
            target_name = data["目标名称"] or "",
            target_count = data["目标数量"] or "1",
            reward_exp = data["奖励经验"] or "0",
            reward_gold = data["奖励金币"] or "0",
            reward_items = data["奖励物品"] or "",
            next_quest = data["后续任务"] or "",
        }
        quests[sectionName] = entry
    end
    return quests
end

--- 解析 shops.ini → shops 表
--- 商品格式: 商品_N = 物品名:购买价格:描述
local function ParseShops(sections)
    local shops = {}
    for sectionName, data in pairs(sections) do
        local entry = {
            name = data["名称"] or sectionName,
            desc = data["描述"] or "",
            items = {},
        }
        local count = tonumber(data["商品数量"]) or 0
        for i = 1, count do
            local raw = data["商品_" .. i]
            if raw then
                local itemName, price, itemDesc = raw:match("^(.+):(%d+):(.*)$")
                if not itemName then
                    -- 兼容旧格式 "物品名:价格"
                    itemName, price = raw:match("^(.+):(%d+)$")
                end
                if itemName then
                    table.insert(entry.items, {
                        name = itemName,
                        price = price or "0",
                        desc = itemDesc or "",
                    })
                end
            end
        end
        -- 兼容旧 "商品列表" 字段（逗号分隔格式）
        if #entry.items == 0 and data["商品列表"] and data["商品列表"] ~= "" then
            for part in data["商品列表"]:gmatch("[^,]+") do
                local n, p = part:match("^(.+):(%d+)$")
                if n then
                    table.insert(entry.items, { name = n, price = p or "0", desc = "" })
                else
                    table.insert(entry.items, { name = part, price = "0", desc = "" })
                end
            end
        end
        shops[sectionName] = entry
    end
    return shops
end

--- 解析 system_shops.ini → systemShops 表
--- 格式: [商店ID]  名称=xxx  货币=xxx  商品数量=N  商品_N=物品名:价格:描述
local function ParseSystemShops(sections)
    local result = {}
    for sectionName, data in pairs(sections) do
        local entry = {
            name = data["名称"] or sectionName,
            currency = data["货币"] or "金币",
            desc = data["描述"] or "",
            items = {},
        }
        local count = tonumber(data["商品数量"]) or 0
        for i = 1, count do
            local raw = data["商品_" .. i]
            if raw then
                local itemName, price, itemDesc = raw:match("^(.+):(%d+):(.*)$")
                if not itemName then
                    itemName, price = raw:match("^(.+):(%d+)$")
                end
                if itemName then
                    table.insert(entry.items, {
                        name = itemName,
                        price = price or "0",
                        desc = itemDesc or "",
                    })
                end
            end
        end
        result[sectionName] = entry
    end
    return result
end

--- 解析 dungeons.ini → dungeons 表
local function ParseDungeons(sections)
    local dungeons = {}
    for sectionName, data in pairs(sections) do
        local entry = {
            name = data["名称"] or sectionName,
            desc = data["描述"] or "",
            level_req = data["等级需求"] or "1",
            waves = data["波数"] or "1",
            boss = data["首领"] or "",
            reward_exp = data["奖励经验"] or "0",
            reward_gold = data["奖励金币"] or "0",
            reward_items = data["奖励物品"] or "",
        }
        -- 解析各波次
        local wavesNum = tonumber(entry.waves) or 1
        for i = 1, wavesNum do
            entry["wave_" .. i] = data["第" .. i .. "波"] or ""
        end
        dungeons[sectionName] = entry
    end
    return dungeons
end

--- 解析 giftpacks.ini → giftpacks 表
local function ParseGiftPacks(sections)
    local packs = {}
    for sectionName, data in pairs(sections) do
        local entry = {
            name = data["名称"] or sectionName,
            desc = data["描述"] or "",
            reward_items = data["奖励物品"] or "",
            reward_gold = data["奖励金币"] or "0",
            reward_exp = data["奖励经验"] or "0",
            max_uses = data["最大使用次数"] or "0",
            used_count = data["已使用次数"] or "0",
        }
        packs[sectionName] = entry
    end
    return packs
end

--- 解析 realms.ini → realms 表（按阶段排序的列表）
local function ParseRealms(sections)
    local realms = {}
    for sectionName, data in pairs(sections) do
        local entry = {
            name = data["名称"] or sectionName,
            stage = tonumber(data["阶段"]) or 1,
            layers = tonumber(data["层数"]) or 9,
            desc = data["描述"] or "",
            breakthrough_material = data["突破材料"] or "",
            breakthrough_count = tonumber(data["突破数量"]) or 0,
            upgrade_material = data["提升材料"] or "",
            upgrade_count = tonumber(data["提升数量"]) or 0,
            layer_exp = data["层经验"] or "100",
            atk_bonus = data["攻击加成"] or "0",
            def_bonus = data["防御加成"] or "0",
            hp_bonus = data["生命加成"] or "0",
        }
        table.insert(realms, entry)
    end
    -- 按阶段排序
    table.sort(realms, function(a, b) return a.stage < b.stage end)
    return realms
end

--- 暴露给外部调用（如 AdminUI 重置境界）
function DataManager.ParseRealms(sections)
    return ParseRealms(sections)
end

--- 解析 realm_pills.ini → realmPills 表
local function ParseRealmPills(sections)
    local pills = {}
    for sectionName, data in pairs(sections) do
        pills[sectionName] = {
            name = data["名称"] or sectionName,
            desc = data["描述"] or "",
            value = data["数值"] or "0",
        }
    end
    return pills
end

--- 将境界经验丹注入 items 表（类型固定为"境界经验"）
local function InjectRealmPillsToItems()
    for id, pill in pairs(DataManager.realmPills) do
        DataManager.items[id] = {
            name = pill.name,
            type = "境界经验",
            value = pill.value,
            desc = pill.desc,
        }
    end
end



--- 解析 pet_types.ini → petTypes 表
local function ParsePetTypes(sections)
    local types = {}
    for id, data in pairs(sections) do
        types[id] = {
            name = data["名称"] or id,
            desc = data["描述"] or "",
            atk = data["攻击"] or "10",
            def = data["防御"] or "5",
            max_hp = data["生命"] or "100",
            quality = data["品质"] or "白",
            skill = data["技能"] or "",
        }
    end
    return types
end

--- 解析 leaderboards.ini → leaderboards 表
local function ParseLeaderboards(sections)
    local boards = {}
    for sectionName, data in pairs(sections) do
        local entry = {
            name = data["名称"] or sectionName,
            key = data["云端键名"] or ("rank_" .. sectionName),
            source = data["数据来源"] or "level",
            order = data["排序"] or "desc",
            top_count = tonumber(data["显示人数"]) or 10,
        }
        boards[sectionName] = entry
    end
    return boards
end

--- 解析 npcs.ini → npcs 表
local function ParseNPCs(sections)
    local npcs = {}
    for sectionName, data in pairs(sections) do
        local entry = {
            name = data["名称"] or sectionName,
            type = data["类型"] or "任务",
            dialog = data["对话"] or "",
            location = data["所在地"] or "",
        }
        -- 根据类型设置关联 ID
        if entry.type == "商人" or entry.type == "merchant" then
            entry.shop_id = data["商店编号"] or ""
        else
            entry.quest_id = data["任务编号"] or ""
        end
        npcs[sectionName] = entry
    end
    return npcs
end

--- 从本地 ConfigData 加载默认系统配置
local function LoadLocalDefaults()
    if ConfigData.game_config then
        DataManager.gameConfig = ParseGameConfig(IniParser.Parse(ConfigData.game_config))
    end
    if ConfigData.maps then
        DataManager.maps = ParseMaps(IniParser.Parse(ConfigData.maps))
    end
    if ConfigData.monsters then
        DataManager.monsters = ParseMonsters(IniParser.Parse(ConfigData.monsters))
    end
    if ConfigData.items then
        DataManager.items = ParseItems(IniParser.Parse(ConfigData.items))
    end
    if ConfigData.equipment then
        DataManager.equipment = ParseEquipment(IniParser.Parse(ConfigData.equipment))
    end
    if ConfigData.quests then
        DataManager.quests = ParseQuests(IniParser.Parse(ConfigData.quests))
    end
    if ConfigData.shops then
        DataManager.shops = ParseShops(IniParser.Parse(ConfigData.shops))
    end
    if ConfigData.system_shops then
        DataManager.systemShops = ParseSystemShops(IniParser.Parse(ConfigData.system_shops))
    end
    if ConfigData.dungeons then
        DataManager.dungeons = ParseDungeons(IniParser.Parse(ConfigData.dungeons))
    end
    if ConfigData.npcs then
        DataManager.npcs = ParseNPCs(IniParser.Parse(ConfigData.npcs))
    end
    if ConfigData.giftpacks then
        DataManager.giftpacks = ParseGiftPacks(IniParser.Parse(ConfigData.giftpacks))
    end
    if ConfigData.realms then
        DataManager.realms = ParseRealms(IniParser.Parse(ConfigData.realms))
        -- 构建阶段索引
        DataManager.realmsByStage = {}
        for _, r in ipairs(DataManager.realms) do
            DataManager.realmsByStage[r.stage] = r
        end
    end
    if ConfigData.realm_pills then
        DataManager.realmPills = ParseRealmPills(IniParser.Parse(ConfigData.realm_pills))
        InjectRealmPillsToItems()
    end
end

--- 打印当前系统数据统计
local function PrintSystemStats()
    print("[DataManager] 地图数量: " .. DataManager.CountTable(DataManager.maps))
    print("[DataManager] 怪物数量: " .. DataManager.CountTable(DataManager.monsters))
    print("[DataManager] NPC数量: " .. DataManager.CountTable(DataManager.npcs))
    print("[DataManager] 物品数量: " .. DataManager.CountTable(DataManager.items))
    print("[DataManager] 装备数量: " .. DataManager.CountTable(DataManager.equipment))
    print("[DataManager] 任务数量: " .. DataManager.CountTable(DataManager.quests))
    print("[DataManager] 商店数量: " .. DataManager.CountTable(DataManager.shops))
    print("[DataManager] 副本数量: " .. DataManager.CountTable(DataManager.dungeons))
    print("[DataManager] 礼包数量: " .. DataManager.CountTable(DataManager.giftpacks))
end

--- 云端系统配置键名映射（核心配置，启动时加载）
local SYSTEM_CLOUD_KEYS = {
    "系统配置/game_config.ini",
    "系统配置/maps.ini",
    "系统配置/monsters.ini",
    "系统配置/items.ini",
    "系统配置/equipment.ini",
    "系统配置/quests.ini",
    "系统配置/shops.ini",
    "系统配置/system_shops.ini",
    "系统配置/dungeons.ini",
    "系统配置/npcs.ini",
    "系统配置/giftpacks.ini",
    "系统配置/realms.ini",
    "系统配置/realm_pills.ini",
    "系统配置/pet_types.ini",
    "系统配置/battle_soul.ini",
}

--- 延迟加载的键（打开对应面板时才拉取，减少启动压力）
local LAZY_CLOUD_KEYS = {
    "系统配置/leaderboards.ini",
    "系统配置/ranking_data.ini",
    "系统配置/chat_messages.ini",
}

--- 延迟数据是否已加载的标记
local lazyDataLoaded_ = {
    leaderboards = false,
    rankingData = false,
    chatMessages = false,
}

--- 加载所有系统配置（优先云端，回退本地 ConfigData）
---@param callback fun()|nil 加载完成回调
function DataManager.LoadSystemData(callback)
    print("[DataManager] 加载系统配置...")

    -- 先加载本地默认值
    LoadLocalDefaults()

    -- 尝试从云端加载覆盖
    if not cloud_ then
        print("[DataManager] 云存储不可用，使用本地默认配置")
        PrintSystemStats()
        print("[DataManager] 系统配置加载完成!")
        if callback then callback() end
        return
    end

    local batch = cloud_:BatchGet()
    for _, key in ipairs(SYSTEM_CLOUD_KEYS) do
        batch:Key(key)
    end
    batch:Fetch({
        ok = function(values, iscores)
            local hasCloud = false
            -- game_config
            local v = values["系统配置/game_config.ini"]
            if v and v ~= "" then
                DataManager.gameConfig = ParseGameConfig(IniParser.Parse(v))
                hasCloud = true
            end
            -- maps
            v = values["系统配置/maps.ini"]
            if v and v ~= "" then
                DataManager.maps = ParseMaps(IniParser.Parse(v))
                hasCloud = true
            end
            -- monsters
            v = values["系统配置/monsters.ini"]
            if v and v ~= "" then
                DataManager.monsters = ParseMonsters(IniParser.Parse(v))
                hasCloud = true
            end
            -- items
            v = values["系统配置/items.ini"]
            if v and v ~= "" then
                DataManager.items = ParseItems(IniParser.Parse(v))
                hasCloud = true
            end
            -- equipment
            v = values["系统配置/equipment.ini"]
            if v and v ~= "" then
                DataManager.equipment = ParseEquipment(IniParser.Parse(v))
                hasCloud = true
            end
            -- quests
            v = values["系统配置/quests.ini"]
            if v and v ~= "" then
                DataManager.quests = ParseQuests(IniParser.Parse(v))
                hasCloud = true
            end
            -- shops
            v = values["系统配置/shops.ini"]
            if v and v ~= "" then
                DataManager.shops = ParseShops(IniParser.Parse(v))
                hasCloud = true
            end
            -- system_shops
            v = values["系统配置/system_shops.ini"]
            if v and v ~= "" then
                DataManager.systemShops = ParseSystemShops(IniParser.Parse(v))
                hasCloud = true
            end
            -- dungeons
            v = values["系统配置/dungeons.ini"]
            if v and v ~= "" then
                DataManager.dungeons = ParseDungeons(IniParser.Parse(v))
                hasCloud = true
            end
            -- npcs
            v = values["系统配置/npcs.ini"]
            if v and v ~= "" then
                DataManager.npcs = ParseNPCs(IniParser.Parse(v))
                hasCloud = true
            end
            -- giftpacks
            v = values["系统配置/giftpacks.ini"]
            if v and v ~= "" then
                DataManager.giftpacks = ParseGiftPacks(IniParser.Parse(v))
                hasCloud = true
            end
            -- realms
            v = values["系统配置/realms.ini"]
            if v and v ~= "" then
                DataManager.realms = ParseRealms(IniParser.Parse(v))
                DataManager.realmsByStage = {}
                for _, r in ipairs(DataManager.realms) do
                    DataManager.realmsByStage[r.stage] = r
                end
                hasCloud = true
            end
            -- realm_pills
            v = values["系统配置/realm_pills.ini"]
            if v and v ~= "" then
                DataManager.realmPills = ParseRealmPills(IniParser.Parse(v))
                InjectRealmPillsToItems()
                hasCloud = true
            end
            -- pet_config: 已固定写死在 DataManager.petConfig，不再从云端加载
            -- pet_types
            v = values["系统配置/pet_types.ini"]
            if v and v ~= "" then
                DataManager.petTypes = ParsePetTypes(IniParser.Parse(v))
                hasCloud = true
            end
            -- battle_soul
            v = values["系统配置/battle_soul.ini"]
            if v and v ~= "" then
                DataManager.battleSoulConfig = ParseBattleSoul(IniParser.Parse(v))
                hasCloud = true
            end
            -- leaderboards/ranking_data/chat_messages 改为按需加载，不在启动时拉取

            if hasCloud then
                print("[DataManager] 已从云端加载系统配置")
            else
                print("[DataManager] 云端无配置，使用本地默认")
            end
            PrintSystemStats()
            print("[DataManager] 系统配置加载完成!")
            if callback then callback() end
        end,
        error = function(code, reason)
            print("[DataManager] 云端加载失败(" .. tostring(reason) .. ")，使用本地默认")
            PrintSystemStats()
            print("[DataManager] 系统配置加载完成!")
            if callback then callback() end
        end,
    })
end

--- 按需加载排行榜/排行数据/聊天记录（首次调用时从云端拉取，之后使用缓存）
---@param callback fun()|nil 加载完成回调
function DataManager.LoadLazyData(callback)
    -- 如果已经加载过，直接回调
    if lazyDataLoaded_.leaderboards and lazyDataLoaded_.rankingData and lazyDataLoaded_.chatMessages then
        if callback then callback() end
        return
    end

    if not cloud_ then
        if callback then callback() end
        return
    end

    print("[DataManager] 按需加载排行榜/聊天数据...")
    local batch = cloud_:BatchGet()
    for _, key in ipairs(LAZY_CLOUD_KEYS) do
        batch:Key(key)
    end
    batch:Fetch({
        ok = function(values)
            local v = values["系统配置/leaderboards.ini"]
            if v and v ~= "" then
                DataManager.leaderboards = ParseLeaderboards(IniParser.Parse(v))
            end
            lazyDataLoaded_.leaderboards = true

            v = values["系统配置/ranking_data.ini"]
            if v and v ~= "" then
                DataManager.rankingData = IniParser.Parse(v)
            end
            lazyDataLoaded_.rankingData = true

            v = values["系统配置/chat_messages.ini"]
            if v and v ~= "" then
                DataManager.chatMessages = DataManager.ParseChatMessages(IniParser.Parse(v))
            end
            lazyDataLoaded_.chatMessages = true

            print("[DataManager] 排行榜/聊天数据加载完成")
            if callback then callback() end
        end,
        error = function(code, reason)
            print("[DataManager] 延迟数据加载失败: " .. tostring(reason))
            -- 标记为已加载，避免重复尝试
            lazyDataLoaded_.leaderboards = true
            lazyDataLoaded_.rankingData = true
            lazyDataLoaded_.chatMessages = true
            if callback then callback() end
        end,
    })
end

--- 重置延迟加载标记（管理员修改数据后需要重新拉取时调用）
function DataManager.ResetLazyData()
    lazyDataLoaded_.leaderboards = false
    lazyDataLoaded_.rankingData = false
    lazyDataLoaded_.chatMessages = false
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
            level = defaults.level or "1",
            exp = defaults.exp or "0",
            hp = defaults.hp or "100",
            max_hp = defaults.hp or "100",
            mp = defaults.mp or "50",
            max_mp = defaults.mp or "50",
            atk = defaults.atk or "5",
            def = defaults.def or "3",
            gold = defaults.gold or "50",
            currencies = {},  -- 自定义货币余额 { ["金币"]="50", ["钻石"]="0", ... }
            current_map = startMap,
            realm = "1",  -- 当前境界阶段（从1开始，独立于等级）
            realm_layer = "1", -- 当前境界层数（小境界，1-9）
            realm_exp = "0",   -- 当前层修炼经验
            battle_soul_level = "0",  -- 战魂等级
            battle_soul_exp = "0",    -- 战魂经验
        },
        bag = {},       -- { {name="物品名", count=数量}, ... }
        equip = {       -- 装备槽（13部位）
            weapon = "",
            helmet = "",
            armor = "",
            bracer = "",
            belt = "",
            boots = "",
            cloak = "",
            necklace = "",
            ring = "",
            artifact = "",
            mount = "",
            wings = "",
            shield = "",
        },
        quests = {
            active = {},     -- { {id="quest_id", progress=0}, ... }
            completed = {},  -- { "quest_id", ... }
        },
        redeemed_codes = {},  -- { "code1", "code2", ... }
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

    -- 账号配置已集中存储，不再写入玩家目录

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
        current_map = "当前地图",
        realm = "境界",
        realm_layer = "境界层",
        realm_exp = "境界经验",
        battle_soul_level = "战魂等级",
        battle_soul_exp = "战魂经验",
    }
    for k, v in pairs(playerData.status) do
        if k == "currencies" then
            -- currencies 是 table，单独序列化为 [自定义货币] section
        elseif type(v) == "table" then
            -- 跳过其他 table 类型字段，避免 tostring 产生垃圾
        else
            local zhKey = statusMap[k] or k
            -- 数值字段用 NumFormat.Int 避免科学计数法
            if type(v) == "number" then
                statusSections["角色属性"][zhKey] = NumFormat.Int(v)
            else
                statusSections["角色属性"][zhKey] = tostring(v)
            end
        end
    end
    -- 自定义货币序列化为独立 section
    local currencies = playerData.status.currencies
    if currencies and type(currencies) == "table" then
        statusSections["自定义货币"] = {}
        for name, amount in pairs(currencies) do
            statusSections["自定义货币"][name] = tostring(amount)
        end
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
    equipSections["装备栏"]["头盔"] = playerData.equip.helmet or ""
    equipSections["装备栏"]["铠甲"] = playerData.equip.armor or ""
    equipSections["装备栏"]["护腕"] = playerData.equip.bracer or ""
    equipSections["装备栏"]["腰带"] = playerData.equip.belt or ""
    equipSections["装备栏"]["战靴"] = playerData.equip.boots or ""
    equipSections["装备栏"]["披风"] = playerData.equip.cloak or ""
    equipSections["装备栏"]["项链"] = playerData.equip.necklace or ""
    equipSections["装备栏"]["戒指"] = playerData.equip.ring or ""
    equipSections["装备栏"]["法宝"] = playerData.equip.artifact or ""
    equipSections["装备栏"]["坐骑"] = playerData.equip.mount or ""
    equipSections["装备栏"]["灵翼"] = playerData.equip.wings or ""
    equipSections["装备栏"]["护盾"] = playerData.equip.shield or ""
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

    -- Buff数据.ini
    local buffSections = {}
    buffSections["增益效果"] = {}
    local buffs = playerData.buffs or {}
    buffSections["增益效果"]["数量"] = tostring(#buffs)
    for i, b in ipairs(buffs) do
        -- 格式: 类型:数值:到期时间戳
        buffSections["增益效果"]["Buff_" .. i] = (b.type or "") .. ":" .. (b.value or 0) .. ":" .. (b.expires or 0)
    end
    files["Buff数据.ini"] = IniParser.Serialize(buffSections)

    -- 礼包兑换记录.ini
    local giftSections = {}
    giftSections["已兑换礼包"] = {}
    local codes = playerData.redeemed_codes or {}
    giftSections["已兑换礼包"]["数量"] = tostring(#codes)
    for i, code in ipairs(codes) do
        giftSections["已兑换礼包"]["礼包_" .. i] = code
    end
    files["礼包兑换记录.ini"] = IniParser.Serialize(giftSections)

    -- 宠物数据.ini
    local petSections = {}
    petSections["宠物列表"] = {}
    local pets = playerData.pets or {}
    petSections["宠物列表"]["数量"] = tostring(#pets)
    for i, pet in ipairs(pets) do
        -- 格式: 名称|等级|经验|星级|阶|品质|出战|基础攻|基础防|基础血
        local deployed = pet.deployed and "1" or "0"
        local base = (pet.name or "") .. "|" .. (pet.level or "1") .. "|" .. (pet.exp or "0") .. "|"
            .. (pet.star or "0") .. "|" .. (pet.stage or "0") .. "|" .. (pet.quality or "白") .. "|"
            .. deployed .. "|" .. (pet.atk or "10") .. "|" .. (pet.def or "5") .. "|" .. (pet.max_hp or "100")
        petSections["宠物列表"]["宠物_" .. i] = base
        -- 宠物装备：宠物_i_装备 = 项圈:装备名,护甲:装备名,...
        local equipParts = {}
        if pet.equip then
            for slot, eName in pairs(pet.equip) do
                if eName and eName ~= "" then
                    table.insert(equipParts, slot .. ":" .. eName)
                end
            end
        end
        if #equipParts > 0 then
            petSections["宠物列表"]["宠物_" .. i .. "_装备"] = table.concat(equipParts, ",")
        end
    end
    files["宠物数据.ini"] = IniParser.Serialize(petSections)

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
        equip = {
            weapon = "", helmet = "", armor = "", bracer = "",
            belt = "", boots = "", cloak = "", necklace = "",
            ring = "", artifact = "", mount = "", wings = "", shield = "",
        },
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
        ["当前地图"] = "current_map",
        ["境界"] = "realm",
        ["境界层"] = "realm_layer",
        ["境界经验"] = "realm_exp",
        ["战魂等级"] = "battle_soul_level",
        ["战魂经验"] = "battle_soul_exp",
    }

    -- 账号配置已集中存储，从 currentAccount/currentPassword 获取
    playerData.account.username = DataManager.currentAccount or ""
    playerData.account.password = DataManager.currentPassword or ""

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
        -- 解析 [自定义货币] section
        local currencySection = sections["自定义货币"]
        if currencySection then
            playerData.status.currencies = {}
            for name, amount in pairs(currencySection) do
                playerData.status.currencies[name] = tostring(amount)
            end
        else
            playerData.status.currencies = playerData.status.currencies or {}
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
                        table.insert(playerData.bag, { name = name, count = cnt or "1" })
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
            playerData.equip.helmet = equipSection["头盔"] or equipSection["helmet"] or ""
            playerData.equip.armor = equipSection["铠甲"] or equipSection["防具"] or equipSection["armor"] or ""
            playerData.equip.bracer = equipSection["护腕"] or equipSection["bracer"] or ""
            playerData.equip.belt = equipSection["腰带"] or equipSection["belt"] or ""
            playerData.equip.boots = equipSection["战靴"] or equipSection["boots"] or ""
            playerData.equip.cloak = equipSection["披风"] or equipSection["cloak"] or ""
            playerData.equip.necklace = equipSection["项链"] or equipSection["necklace"] or ""
            playerData.equip.ring = equipSection["戒指"] or equipSection["ring"] or ""
            playerData.equip.artifact = equipSection["法宝"] or equipSection["artifact"] or ""
            playerData.equip.mount = equipSection["坐骑"] or equipSection["mount"] or ""
            playerData.equip.wings = equipSection["灵翼"] or equipSection["wings"] or ""
            playerData.equip.shield = equipSection["护盾"] or equipSection["shield"] or ""
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
                        table.insert(playerData.quests.active, { id = id, progress = progress or "0" })
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

    -- 解析 Buff数据.ini
    playerData.buffs = {}
    if fileMap["Buff数据.ini"] then
        local sections = IniParser.Parse(fileMap["Buff数据.ini"])
        local buffSection = sections["增益效果"]
        if buffSection then
            local count = tonumber(buffSection["数量"]) or 0
            local now = os.time()
            for i = 1, count do
                local raw = buffSection["Buff_" .. i]
                if raw then
                    -- 格式: 类型:数值:到期时间戳
                    local bType, bValue, bExpires = raw:match("^(.+):([^:]+):(%d+)$")
                    if bType then
                        local expires = tonumber(bExpires) or 0
                        -- 只恢复未过期的 buff
                        if expires > now then
                            table.insert(playerData.buffs, {
                                type = bType,
                                value = tonumber(bValue) or bValue,
                                expires = expires,
                            })
                        end
                    end
                end
            end
        end
    end

    -- 解析 礼包兑换记录.ini
    playerData.redeemed_codes = {}
    if fileMap["礼包兑换记录.ini"] then
        local sections = IniParser.Parse(fileMap["礼包兑换记录.ini"])
        local giftSection = sections["已兑换礼包"]
        if giftSection then
            local count = tonumber(giftSection["数量"]) or 0
            for i = 1, count do
                local code = giftSection["礼包_" .. i]
                if code and code ~= "" then
                    table.insert(playerData.redeemed_codes, code)
                end
            end
        end
    end

    -- 解析 宠物数据.ini
    playerData.pets = {}
    if fileMap["宠物数据.ini"] then
        local sections = IniParser.Parse(fileMap["宠物数据.ini"])
        local petSection = sections["宠物列表"]
        if petSection then
            local count = tonumber(petSection["数量"]) or 0
            for i = 1, count do
                local raw = petSection["宠物_" .. i]
                if raw then
                    -- 格式: 名称|等级|经验|星级|阶|品质|出战|基础攻|基础防|基础血
                    local parts = {}
                    for part in raw:gmatch("[^|]+") do
                        table.insert(parts, part)
                    end
                    if #parts >= 6 then
                        local pet = {
                            name = parts[1],
                            level = parts[2] or "1",
                            exp = parts[3] or "0",
                            star = parts[4] or "0",
                            stage = parts[5] or "0",
                            quality = parts[6] or "白",
                            deployed = (parts[7] == "1"),
                            atk = parts[8] or "10",
                            def = parts[9] or "5",
                            max_hp = parts[10] or "100",
                            equip = {},
                        }
                        -- 解析宠物装备
                        local equipRaw = petSection["宠物_" .. i .. "_装备"]
                        if equipRaw and equipRaw ~= "" then
                            for entry in equipRaw:gmatch("[^,]+") do
                                local slot, eName = entry:match("^(.+):(.+)$")
                                if slot and eName then
                                    pet.equip[slot] = eName
                                end
                            end
                        end
                        table.insert(playerData.pets, pet)
                    end
                end
            end
        end
    end

    return playerData
end

--- 云端文件名列表
--- 玩家游戏数据文件列表（不含账号配置，账号集中存储）
DataManager.CLOUD_FILES = { "状态数据.ini", "背包数据.ini", "装备数据.ini", "任务数据.ini", "Buff数据.ini", "礼包兑换记录.ini", "宠物数据.ini" }

--- 集中式账号配置云端键（所有玩家账号密码存在这一个文件里）
DataManager.ACCOUNT_REGISTRY_KEY = "账号配置.ini"

--- 从云端值中提取字符串（clientCloud:Get 可能返回 table）
---@param value any
---@return string
local function extractString(value)
    if type(value) == "string" then
        return value
    elseif type(value) == "table" then
        return value.value or value[1] or ""
    end
    return ""
end

--- 读取集中式账号配置
---@param callback fun(sections: table|nil)
function DataManager.LoadAccountRegistry(callback)
    if not cloud_ then
        callback(nil)
        return
    end
    cloud_:Get(DataManager.ACCOUNT_REGISTRY_KEY, {
        ok = function(values, iscores)
            local raw = values[DataManager.ACCOUNT_REGISTRY_KEY]
            local content = extractString(raw)
            if content == "" then
                callback({})
                return
            end
            local sections = IniParser.Parse(content)
            callback(sections)
        end,
        error = function(code, reason)
            print("[DataManager] 读取账号配置失败: " .. tostring(reason))
            callback(nil)
        end,
    })
end

local isRegistrySaving_ = false
local registryQueue_ = nil  -- { sections, callback } 排队中的最新数据

--- 保存集中式账号配置
---@param sections table
---@param callback fun(success: boolean)|nil
function DataManager.SaveAccountRegistry(sections, callback)
    if not cloud_ then
        if callback then callback(false) end
        return
    end

    -- 如果正在保存中，排队最新数据
    if isRegistrySaving_ then
        registryQueue_ = { sections = sections, callback = callback }
        return
    end

    isRegistrySaving_ = true
    registryQueue_ = nil

    local content = IniParser.Serialize(sections)
    cloud_:Set(DataManager.ACCOUNT_REGISTRY_KEY, content, {
        ok = function()
            isRegistrySaving_ = false
            print("[DataManager] 账号配置已保存")
            if callback then callback(true) end
            if registryQueue_ then
                local q = registryQueue_
                registryQueue_ = nil
                DataManager.SaveAccountRegistry(q.sections, q.callback)
            end
        end,
        error = function(code, reason)
            isRegistrySaving_ = false
            print("[DataManager] 保存账号配置失败: " .. tostring(reason))
            if callback then callback(false) end
            if registryQueue_ then
                local q = registryQueue_
                registryQueue_ = nil
                DataManager.SaveAccountRegistry(q.sections, q.callback)
            end
        end,
    })
end

--- 注册新账号到集中配置
---@param username string
---@param password string
---@param charName string
---@param callback fun(success: boolean)|nil
function DataManager.RegisterAccount(username, password, charName, callback)
    DataManager.LoadAccountRegistry(function(sections)
        if not sections then
            sections = {}
        end
        -- 检查是否已存在
        if sections[username] then
            print("[DataManager] 账号已存在: " .. username)
            if callback then callback(false) end
            return
        end
        -- 添加新账号
        sections[username] = {
            ["密码"] = password,
            ["角色名"] = charName,
            ["创建时间"] = tostring(os.time and os.time() or 0),
        }
        DataManager.SaveAccountRegistry(sections, callback)
    end)
end

--- 验证登录（从集中配置读取）
---@param username string
---@param password string
---@param callback fun(success: boolean, charName: string|nil, errorMsg: string|nil)
function DataManager.VerifyLogin(username, password, callback)
    DataManager.LoadAccountRegistry(function(sections)
        if not sections or not sections[username] then
            callback(false, nil, "账号不存在，请先注册")
            return
        end
        local accData = sections[username]
        local savedPwd = tostring(accData["密码"] or accData["password"] or "")
        if savedPwd ~= "" and savedPwd ~= tostring(password) then
            callback(false, nil, "密码错误")
            return
        end
        local charName = accData["角色名"] or accData["char_name"] or username
        callback(true, charName, nil)
    end)
end

--- 检查账号是否存在
---@param username string
---@param callback fun(exists: boolean)
function DataManager.CheckAccountExists(username, callback)
    DataManager.LoadAccountRegistry(function(sections)
        if sections and sections[username] then
            callback(true)
        else
            callback(false)
        end
    end)
end

--- 获取所有玩家账号信息（供管理员后台使用）
---@param callback fun(players: table[])
function DataManager.GetAllPlayers(callback)
    DataManager.LoadAccountRegistry(function(sections)
        if not sections then
            callback({})
            return
        end
        -- 自动清理 default 等无效条目（从云端彻底删除）
        local needSave = false
        if sections["default"] then
            sections["default"] = nil
            needSave = true
        end
        if sections[""] then
            sections[""] = nil
            needSave = true
        end
        -- 同时清理排行榜中的 default
        local rankNeedSave = false
        if DataManager.rankingData["default"] then
            DataManager.rankingData["default"] = nil
            rankNeedSave = true
        end
        if DataManager.rankingData[""] then
            DataManager.rankingData[""] = nil
            rankNeedSave = true
        end

        -- 保存清理后的数据到云端
        if needSave then
            DataManager.SaveAccountRegistry(sections, function()
                print("[DataManager] 已从云端删除 default 账号条目")
            end)
        end
        if rankNeedSave and cloud_ then
            local content = IniParser.Serialize(DataManager.rankingData)
            cloud_:Set("系统配置/ranking_data.ini", content, {
                ok = function()
                    print("[DataManager] 已从排行榜删除 default 条目")
                end,
                error = function() end,
            })
        end

        local players = {}
        for username, data in pairs(sections) do
            table.insert(players, {
                username = username,
                password = tostring(data["密码"] or data["password"] or "未设置"),
                charName = data["角色名"] or data["char_name"] or "",
            })
        end
        print("[DataManager] 获取玩家列表: " .. #players .. " 个账号")
        callback(players)
    end)
end

--- 修改玩家密码（集中式）
---@param username string
---@param newPassword string
---@param callback fun(success: boolean)
function DataManager.ChangePlayerPassword(username, newPassword, callback)
    DataManager.LoadAccountRegistry(function(sections)
        if not sections or not sections[username] then
            print("[DataManager] 未找到账号: " .. username)
            if callback then callback(false) end
            return
        end
        sections[username]["密码"] = newPassword
        DataManager.SaveAccountRegistry(sections, callback)
    end)
end

--- 验证玩家密码
---@param username string
---@param password string
---@param callback fun(ok: boolean)
function DataManager.VerifyPlayerPassword(username, password, callback)
    DataManager.LoadAccountRegistry(function(sections)
        if not sections or not sections[username] then
            if callback then callback(false) end
            return
        end
        local storedPwd = tostring(sections[username]["密码"] or sections[username]["password"] or "")
        if callback then callback(storedPwd == password) end
    end)
end

--- 修改玩家账号信息（密码、角色名）
---@param username string
---@param newData table {password, charName}
---@param callback fun(success: boolean)
function DataManager.UpdateAccountInfo(username, newData, callback)
    DataManager.LoadAccountRegistry(function(sections)
        if not sections or not sections[username] then
            print("[DataManager] 未找到账号: " .. username)
            if callback then callback(false) end
            return
        end
        if newData.password then
            sections[username]["密码"] = newData.password
        end
        if newData.charName then
            sections[username]["角色名"] = newData.charName
        end
        DataManager.SaveAccountRegistry(sections, callback)
    end)
end

--- 加载指定玩家的所有游戏数据（供管理员后台使用）
---@param username string
---@param callback fun(playerData: table|nil)
function DataManager.LoadPlayerDataForAdmin(username, callback)
    if not cloud_ then
        print("[DataManager] 云存储不可用")
        callback(nil)
        return
    end

    local path = DataManager.GetCloudPath(username)
    print("[DataManager] 管理员加载玩家数据: " .. path)

    local batch = cloud_:BatchGet()
    for _, fileName in ipairs(DataManager.CLOUD_FILES) do
        batch:Key(path .. fileName)
    end
    batch:Fetch({
        ok = function(values, iscores)
            local firstKey = path .. "状态数据.ini"
            local firstContent = values[firstKey]
            if not firstContent or firstContent == "" then
                print("[DataManager] 玩家无游戏数据: " .. username)
                callback(nil)
                return
            end

            local fileMap = {}
            for _, fileName in ipairs(DataManager.CLOUD_FILES) do
                local key = path .. fileName
                local val = values[key]
                if val and val ~= "" then
                    fileMap[fileName] = extractString(val)
                end
            end

            local playerData = DataManager.FilesToPlayerData(fileMap)
            playerData.account.username = username
            print("[DataManager] 管理员加载成功: " .. username)
            callback(playerData)
        end,
        error = function(code, reason)
            print("[DataManager] 管理员加载失败: " .. tostring(reason))
            callback(nil)
        end,
    })
end

--- 保存指定玩家的游戏数据（供管理员修改后保存）
---@param username string
---@param playerData table
---@param callback fun(success: boolean)
function DataManager.SavePlayerDataForAdmin(username, playerData, callback)
    if not cloud_ then
        print("[DataManager] 云存储不可用")
        if callback then callback(false) end
        return
    end

    local path = DataManager.GetCloudPath(username)
    local files = DataManager.PlayerDataToFiles(playerData)

    print("[DataManager] 管理员保存玩家数据: " .. path)

    local batch = cloud_:BatchSet()
    for fileName, content in pairs(files) do
        batch:Set(path .. fileName, content)
    end
    batch:Save("管理员修改玩家数据", {
        ok = function()
            print("[DataManager] 管理员保存成功: " .. username)
            -- 自动刷新该玩家的排行榜数据
            DataManager.RefreshPlayerRankingForAdmin(username, function(rankOk, rankMsg)
                if rankOk then
                    print("[DataManager] 排行榜已自动刷新: " .. username)
                else
                    print("[DataManager] 排行榜自动刷新失败: " .. tostring(rankMsg))
                end
            end)
            if callback then callback(true) end
        end,
        error = function(code, reason)
            print("[DataManager] 管理员保存失败: " .. tostring(reason))
            if callback then callback(false) end
        end,
    })
end

--- 删除玩家（从账号注册表移除 + 删除云端游戏数据）
---@param username string
---@param callback fun(success: boolean)
function DataManager.DeletePlayer(username, callback)
    -- 第一步：从账号注册表删除
    DataManager.LoadAccountRegistry(function(sections)
        if not sections then
            print("[DataManager] 无法加载账号配置")
            if callback then callback(false) end
            return
        end
        -- 保存角色名用于排行榜移除
        local charName = sections[username] and (sections[username]["角色名"] or sections[username]["char_name"] or "")
        sections[username] = nil
        DataManager.SaveAccountRegistry(sections, function(ok)
            if not ok then
                if callback then callback(false) end
                return
            end
            -- 第二步：清空云端游戏数据（设为空字符串）
            if not cloud_ then
                if callback then callback(true) end
                return
            end
            local path = DataManager.GetCloudPath(username)
            local batch = cloud_:BatchSet()
            for _, fileName in ipairs(DataManager.CLOUD_FILES) do
                batch:Set(path .. fileName, "")
            end
            batch:Save("删除玩家数据", {
                ok = function()
                    print("[DataManager] 玩家已删除: " .. username)
                    -- 同步删除排行榜中该玩家的数据
                    DataManager.RemovePlayerFromRanking(username, charName)
                    if callback then callback(true) end
                end,
                error = function(code, reason)
                    print("[DataManager] 删除玩家数据失败: " .. tostring(reason))
                    -- 账号已移除，游戏数据清理失败但不影响主流程
                    if callback then callback(true) end
                end,
            })
        end)
    end)
end

--- 兼容旧代码：AddToPlayerIndex（现在为空操作）
---@param username string
---@param callback function|nil
function DataManager.AddToPlayerIndex(username, callback)
    -- 集中式账号配置已在注册时自动处理，此函数保留兼容性
    if callback then callback(true) end
end

local isSaving_ = false      -- 是否有保存请求正在飞行中
local isDirty_ = false       -- 保存期间是否有新变更
local saveRetries_ = 0       -- 当前连续重试次数
local SAVE_MAX_RETRIES = 2   -- 最大重试次数

--- 保存玩家数据到云端（拆分为多个文件）
--- 使用队列机制：同一时间只允许一个保存请求 in-flight，
--- 保存期间如有新变更，完成后自动再保存一次最新数据。
--- 保存失败时自动重试（最多2次）。
---@param playerData table
---@param callback function|nil 完成回调
function DataManager.SaveToCloud(playerData, callback)
    if not cloud_ then
        print("[DataManager] 云存储不可用，跳过云端保存")
        if callback then callback(false) end
        return
    end

    -- 如果正在保存中，标记 dirty 等当前保存完成后再存最新数据
    if isSaving_ then
        isDirty_ = true
        return
    end

    isSaving_ = true
    isDirty_ = false

    local username = playerData.account.username or "unknown"
    local path = DataManager.GetCloudPath(username)
    local files = DataManager.PlayerDataToFiles(playerData)

    print("[DataManager] 保存到云端: " .. path)

    local batch = cloud_:BatchSet()
    for fileName, content in pairs(files) do
        batch:Set(path .. fileName, content)
    end
    batch:Save("保存玩家数据", {
        ok = function()
            isSaving_ = false
            saveRetries_ = 0
            print("[DataManager] 云端保存成功 (" .. path .. ")")
            -- 同步排行榜分数
            DataManager.SyncLeaderboardScores()
            if callback then callback(true) end
            -- 保存期间有新变更，立即再存一次最新快照
            if isDirty_ and DataManager.playerData then
                DataManager.SaveToCloud(DataManager.playerData)
            end
        end,
        error = function(code, reason)
            isSaving_ = false
            print("[DataManager] 云端保存失败: " .. tostring(reason))
            -- 自动重试
            if saveRetries_ < SAVE_MAX_RETRIES then
                saveRetries_ = saveRetries_ + 1
                print("[DataManager] 自动重试保存 (" .. saveRetries_ .. "/" .. SAVE_MAX_RETRIES .. ")")
                DataManager.SaveToCloud(playerData, callback)
            else
                saveRetries_ = 0
                print("[DataManager] 保存重试耗尽，等待下次操作触发")
                if callback then callback(false) end
                -- 保留 dirty 状态，下次操作触发时会再次尝试
                isDirty_ = true
            end
        end,
    })
end

--- 从云端加载玩家数据（批量读取多个文件）
---@param callback function(playerData|nil)
---@param username string|nil 指定账号名（可选，默认用 currentAccount）
function DataManager.LoadFromCloud(callback, username)
    if not cloud_ then
        print("[DataManager] 云存储不可用")
        callback(nil)
        return
    end

    local name = username or DataManager.currentAccount
    if not name or name == "" then
        -- 没有指定账号，尝试用通配方式检查是否有存档
        -- 先尝试读取旧格式（兼容）
        cloud_:Get("player_save", {
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

    local batch = cloud_:BatchGet()
    for _, fileName in ipairs(DataManager.CLOUD_FILES) do
        batch:Key(path .. fileName)
    end
    batch:Fetch({
        ok = function(values, iscores)
            -- 检查是否有数据（用状态数据.ini判断）
            local firstKey = path .. "状态数据.ini"
            local firstContent = values[firstKey]
            if not firstContent or firstContent == "" then
                -- 新格式无数据，尝试旧格式兼容
                cloud_:Get("player_save", {
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

--- 获取物品信息（先按 ID/key 查找，再按显示名称回退查找）
---@param itemName string
---@return table|nil
function DataManager.GetItem(itemName)
    -- 先从物品表按 key 找
    if DataManager.items[itemName] then
        return DataManager.items[itemName]
    end
    -- 再从装备表按 key 找
    if DataManager.equipment[itemName] then
        return DataManager.equipment[itemName]
    end
    -- 按显示名称(name字段)回退查找物品表
    for _, data in pairs(DataManager.items) do
        if data.name == itemName then
            return data
        end
    end
    -- 按显示名称回退查找装备表
    for _, data in pairs(DataManager.equipment) do
        if data.name == itemName then
            return data
        end
    end
    return nil
end

--- 获取装备信息（仅按key直接查找）
---@param equipName string
---@return table|nil
function DataManager.GetEquipment(equipName)
    return DataManager.equipment[equipName]
end

--- 获取装备数据（优先equipment表，支持key和name字段回退）
--- 用于装备面板等需要确保返回有slot字段的场景
---@param itemName string
---@return table|nil
function DataManager.GetEquipData(itemName)
    -- 先从装备表按 key 找
    if DataManager.equipment[itemName] then
        return DataManager.equipment[itemName]
    end
    -- 按显示名称回退查找装备表
    for _, data in pairs(DataManager.equipment) do
        if data.name == itemName then
            return data
        end
    end
    return nil
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

--- 获取系统商店信息
---@param shopId string
---@return table|nil
function DataManager.GetSystemShop(shopId)
    return DataManager.systemShops[shopId]
end

--- 获取所有系统商店列表
---@return table
function DataManager.GetAllSystemShops()
    return DataManager.systemShops
end

--- 获取配置的货币列表
---@return table 货币名称数组，如 {"金币", "钻石", "积分"}
function DataManager.GetCurrencyList()
    return DataManager.gameConfig["currencies"] or { "金币" }
end

--- 获取玩家某种货币余额（兼容 gold 字段）
---@param player table
---@param currencyName string
---@return string
function DataManager.GetPlayerCurrency(player, currencyName)
    if not player or not player.status then return "0" end
    -- 金币兼容旧字段
    if currencyName == "金币" then
        return tostring(player.status.gold or "0")
    end
    local currencies = player.status.currencies or {}
    return tostring(currencies[currencyName] or "0")
end

--- 设置玩家某种货币余额
---@param player table
---@param currencyName string
---@param value string
function DataManager.SetPlayerCurrency(player, currencyName, value)
    if not player or not player.status then return end
    if currencyName == "金币" then
        player.status.gold = value
        return
    end
    if not player.status.currencies then
        player.status.currencies = {}
    end
    player.status.currencies[currencyName] = value
end

-- =============== 战魂系统 ===============

--- 获取击杀某怪物应获得的战魂值区间
---@param monsterName string
---@return number min, number max
function DataManager.GetBattleSoulRange(monsterName)
    local mData = DataManager.monsters[monsterName]
    local monsterType = mData and mData.type or "普通怪"
    local soulCfg = DataManager.battleSoulConfig.monster_soul[monsterType]
    if soulCfg then
        return tonumber(soulCfg.min) or 1, tonumber(soulCfg.max) or 5
    end
    -- 未配置的类型默认 1-3
    return 1, 3
end

--- 计算战魂升级到下一级所需经验
--- 公式: need = base + growth * (level)^power
---@param level number|string 当前等级
---@return string 所需经验(BigNum字符串)
function DataManager.GetBattleSoulExpNeeded(level)
    local lv = tonumber(level) or 0
    local formula = DataManager.battleSoulConfig.level_formula
    local base = tonumber(formula.base) or 100
    local growth = tonumber(formula.growth) or 50
    local power = tonumber(formula.power) or 1.5
    local need = math.floor(base + growth * (lv ^ power))
    return tostring(need)
end

--- 获取战魂等级对玩家的总属性加成
---@param level number|string
---@return table { atk=string, def=string, max_hp=string }
function DataManager.GetBattleSoulBonus(level)
    local lv = tonumber(level) or 0
    local bonus = DataManager.battleSoulConfig.level_bonus
    return {
        atk = tostring(math.floor(lv * (tonumber(bonus.atk) or 5))),
        def = tostring(math.floor(lv * (tonumber(bonus.def) or 3))),
        max_hp = tostring(math.floor(lv * (tonumber(bonus.max_hp) or 20))),
    }
end

--- 根据任意 playerData 计算完整战斗属性（基础+装备+buff+境界+战魂）
--- 用于管理后台刷新排行榜，不依赖当前登录玩家
---@param playerData table
---@return string totalAtk, string totalDef, string totalHp
function DataManager.CalcFullStatsFromPlayerData(playerData)
    local st = playerData.status or {}
    local eq = playerData.equip or {}

    -- 基础属性
    local baseAtk = st.atk or "5"
    local baseDef = st.def or "3"
    local baseHp = st.max_hp or "100"

    -- 装备加成
    local equipAtk, equipDef, equipHp = "0", "0", "0"
    for _, slot in ipairs({ "weapon", "helmet", "armor", "bracer", "belt", "boots", "cloak", "necklace", "ring", "artifact", "mount", "wings", "shield" }) do
        local equipName = eq[slot]
        if equipName and equipName ~= "" then
            local eData = DataManager.GetEquipment(equipName)
            if eData then
                equipAtk = BigNum.add(equipAtk, eData.atk or "0")
                equipDef = BigNum.add(equipDef, eData.def or "0")
                equipHp = BigNum.add(equipHp, eData.hp or "0")
            end
        end
    end

    -- Buff 加成（需要检查过期）
    local buffAtk, buffDef, buffHp = "0", "0", "0"
    local now = os.time()
    local buffs = playerData.buffs or {}
    for _, b in ipairs(buffs) do
        if b.expires and b.expires > now then
            if b.type == "攻击" then
                buffAtk = BigNum.add(buffAtk, tostring(b.value or 0))
            elseif b.type == "防御" then
                buffDef = BigNum.add(buffDef, tostring(b.value or 0))
            elseif b.type == "生命上限" then
                buffHp = BigNum.add(buffHp, tostring(b.value or 0))
            end
        end
    end

    -- 境界加成（基于 playerData 中的境界数据）
    local stage = tonumber(st.realm) or 1
    local layer = tonumber(st.realm_layer) or 1
    local realmAtk, realmDef, realmHp = "0", "0", "0"
    for i = 1, stage - 1 do
        local r = DataManager.realmsByStage[i]
        if r then
            local layers = r.layers or 9
            for _ = 1, layers do
                realmAtk = BigNum.add(realmAtk, r.atk_bonus or "0")
                realmDef = BigNum.add(realmDef, r.def_bonus or "0")
                realmHp = BigNum.add(realmHp, r.hp_bonus or "0")
            end
        end
    end
    local curRealm = DataManager.realmsByStage[stage]
    if curRealm then
        for _ = 1, layer do
            realmAtk = BigNum.add(realmAtk, curRealm.atk_bonus or "0")
            realmDef = BigNum.add(realmDef, curRealm.def_bonus or "0")
            realmHp = BigNum.add(realmHp, curRealm.hp_bonus or "0")
        end
    end

    -- 战魂加成
    local soulBonus = DataManager.GetBattleSoulBonus(st.battle_soul_level)

    -- 汇总
    local totalAtk = BigNum.add(BigNum.add(BigNum.add(BigNum.add(baseAtk, equipAtk), buffAtk), realmAtk), soulBonus.atk)
    local totalDef = BigNum.add(BigNum.add(BigNum.add(BigNum.add(baseDef, equipDef), buffDef), realmDef), soulBonus.def)
    local totalHp = BigNum.add(BigNum.add(BigNum.add(BigNum.add(baseHp, equipHp), buffHp), realmHp), soulBonus.max_hp)

    return totalAtk, totalDef, totalHp
end

--- 管理员刷新单个玩家的排行榜数据（加载其完整存档后计算属性并写入排行榜）
---@param username string 玩家账号
---@param callback fun(success: boolean, msg: string)
function DataManager.RefreshPlayerRankingForAdmin(username, callback)
    if not cloud_ then
        callback(false, "云存储不可用")
        return
    end

    DataManager.LoadPlayerDataForAdmin(username, function(playerData)
        if not playerData then
            callback(false, "加载玩家数据失败")
            return
        end

        local st = playerData.status or {}
        local charName = st.name or username

        -- 计算完整属性
        local totalAtk, totalDef, totalHp = DataManager.CalcFullStatsFromPlayerData(playerData)

        -- 读取当前排行榜数据
        cloud_:Get("系统配置/ranking_data.ini", {
            ok = function(values)
                local raw = values["系统配置/ranking_data.ini"]
                if raw and raw ~= "" then
                    DataManager.rankingData = IniParser.Parse(raw)
                end

                -- 更新该玩家的排行榜条目
                DataManager.rankingData[charName] = {
                    ["等级"] = NumFormat.Int(st.level or 1),
                    ["金币"] = NumFormat.Int(st.gold or 0),
                    ["攻击力"] = NumFormat.Int(totalAtk),
                    ["防御力"] = NumFormat.Int(totalDef),
                    ["生命上限"] = NumFormat.Int(totalHp),
                }

                -- 清理无效条目
                if DataManager.rankingData["default"] then DataManager.rankingData["default"] = nil end
                if DataManager.rankingData[""] then DataManager.rankingData[""] = nil end

                local content = IniParser.Serialize(DataManager.rankingData)
                cloud_:Set("系统配置/ranking_data.ini", content, {
                    ok = function()
                        print("[DataManager] 管理员刷新排行榜成功: " .. charName)
                        callback(true, charName .. " 排行榜已刷新")
                    end,
                    error = function(_, r)
                        callback(false, "写入排行榜失败: " .. tostring(r))
                    end,
                })
            end,
            error = function(_, r)
                callback(false, "读取排行榜失败: " .. tostring(r))
            end,
        })
    end)
end

--- 管理员批量刷新所有玩家排行榜
---@param callback fun(success: boolean, msg: string)
function DataManager.RefreshAllPlayersRankingForAdmin(callback)
    if not cloud_ then
        callback(false, "云存储不可用")
        return
    end

    DataManager.GetAllPlayers(function(players)
        if #players == 0 then
            callback(false, "没有玩家数据")
            return
        end

        -- 先读取当前排行榜
        cloud_:Get("系统配置/ranking_data.ini", {
            ok = function(values)
                local raw = values["系统配置/ranking_data.ini"]
                if raw and raw ~= "" then
                    DataManager.rankingData = IniParser.Parse(raw)
                end

                local total = #players
                local done = 0
                local successCount = 0

                local function checkDone()
                    done = done + 1
                    if done >= total then
                        -- 清理无效条目并保存
                        if DataManager.rankingData["default"] then DataManager.rankingData["default"] = nil end
                        if DataManager.rankingData[""] then DataManager.rankingData[""] = nil end

                        local content = IniParser.Serialize(DataManager.rankingData)
                        cloud_:Set("系统配置/ranking_data.ini", content, {
                            ok = function()
                                print("[DataManager] 批量刷新排行榜完成: " .. successCount .. "/" .. total)
                                callback(true, "已刷新 " .. successCount .. "/" .. total .. " 个玩家")
                            end,
                            error = function(_, r)
                                callback(false, "写入排行榜失败: " .. tostring(r))
                            end,
                        })
                    end
                end

                for _, info in ipairs(players) do
                    DataManager.LoadPlayerDataForAdmin(info.username, function(playerData)
                        if playerData then
                            local st = playerData.status or {}
                            local charName = st.name or info.username
                            local totalAtk, totalDef, totalHp = DataManager.CalcFullStatsFromPlayerData(playerData)

                            local rankEntry = {
                                ["等级"] = NumFormat.Int(st.level or 1),
                                ["金币"] = NumFormat.Int(st.gold or 0),
                                ["攻击力"] = NumFormat.Int(totalAtk),
                                ["防御力"] = NumFormat.Int(totalDef),
                                ["生命上限"] = NumFormat.Int(totalHp),
                                ["战魂等级"] = NumFormat.Int(st.battle_soul_level or 0),
                            }
                            -- 自定义货币
                            local currencies = st.currencies or {}
                            for cName, cVal in pairs(currencies) do
                                rankEntry["货币:" .. cName] = NumFormat.Int(cVal or 0)
                                rankEntry[cName] = NumFormat.Int(cVal or 0)
                            end
                            -- 背包道具计数
                            for _, item in ipairs(playerData.bag or {}) do
                                local key = "道具:" .. item.name
                                local prev = tonumber(rankEntry[key]) or 0
                                rankEntry[key] = tostring(prev + (tonumber(item.count) or 1))
                            end
                            -- 装备栏（已穿戴装备计数）
                            local eqSlots = { "weapon", "helmet", "armor", "bracer", "belt", "boots", "cloak", "necklace", "ring", "artifact", "mount", "wings", "shield" }
                            for _, slot in ipairs(eqSlots) do
                                local eName = playerData.equip and playerData.equip[slot]
                                if eName and eName ~= "" then
                                    local key = "装备:" .. eName
                                    local prev = tonumber(rankEntry[key]) or 0
                                    rankEntry[key] = tostring(prev + 1)
                                end
                            end
                            DataManager.rankingData[charName] = rankEntry
                            successCount = successCount + 1
                        end
                        checkDone()
                    end)
                end
            end,
            error = function(_, r)
                callback(false, "读取排行榜失败: " .. tostring(r))
            end,
        })
    end)
end

--- 获取所有怪物类型列表（从怪物配置中提取去重）
---@return table 类型名列表
function DataManager.GetMonsterTypes()
    local typeSet = {}
    local typeList = {}
    for _, mData in pairs(DataManager.monsters) do
        local t = mData.type or "普通怪"
        if not typeSet[t] then
            typeSet[t] = true
            table.insert(typeList, t)
        end
    end
    table.sort(typeList)
    return typeList
end

--- 根据HP值自动判断怪物类型
---@param hp string HP值
---@return string 怪物类型名称
function DataManager.ClassifyMonsterType(hp)
    return ClassifyMonsterType(hp)
end

--- 重新分类所有怪物类型（根据HP值）
function DataManager.ReclassifyAllMonsters()
    for _, mData in pairs(DataManager.monsters) do
        mData.type = ClassifyMonsterType(mData.hp)
    end
end

--- 获取副本信息
---@param dungeonId string
---@return table|nil
function DataManager.GetDungeon(dungeonId)
    return DataManager.dungeons[dungeonId]
end

--- 获取升级所需经验（返回大数字符串）
--- 公式: base_exp * level^exp_factor (exp_factor 必须为整数: 1, 2, 3)
---@param level number|string
---@return string
function DataManager.GetExpForLevel(level)
    local config = DataManager.gameConfig["level_up"] or {}
    local baseExp = tostring(config.base_exp or "20")
    -- 强制取整（兼容旧配置 1.5 → 2），确保闭合求和公式可用
    local factor = math.max(1, math.min(3, math.floor((tonumber(config.exp_factor) or 2) + 0.5)))
    local lvl = tonumber(level) or 1
    local multiplier = tostring(math.floor(lvl ^ factor))
    return BigNum.mul(baseExp, multiplier)
end

--- 闭合公式计算 sum(i^k, i=1..n)，返回 BigNum 字符串
--- 支持 k=1: n(n+1)/2, k=2: n(n+1)(2n+1)/6, k=3: [n(n+1)/2]^2
---@param n number 上界（含）
---@param k number 幂次（1/2/3）
---@return string BigNum 字符串
function DataManager.SumOfPowers(n, k)
    if n <= 0 then return "0" end
    local sn = tostring(n)
    local sn1 = tostring(n + 1)
    if k == 1 then
        -- n*(n+1)/2
        local prod = BigNum.mul(sn, sn1)
        return BigNum.div(prod, "2")
    elseif k == 2 then
        -- n*(n+1)*(2n+1)/6
        local s2n1 = tostring(2 * n + 1)
        local prod = BigNum.mul(BigNum.mul(sn, sn1), s2n1)
        return BigNum.div(prod, "6")
    elseif k == 3 then
        -- [n*(n+1)/2]^2
        local half = BigNum.div(BigNum.mul(sn, sn1), "2")
        return BigNum.mul(half, half)
    else
        -- 降级：逐级累加（不应触发，仅保护）
        local total = "0"
        for i = 1, n do
            total = BigNum.add(total, tostring(math.floor(i ^ k)))
        end
        return total
    end
end

--- 闭合公式计算从 fromLv 升到 toLv 需要的总经验（精确）
--- = base_exp * sum(i^factor, i=fromLv .. toLv-1)
--- = base_exp * (SumOfPowers(toLv-1, factor) - SumOfPowers(fromLv-1, factor))
---@param fromLv number 起始等级
---@param toLv number 目标等级（不含该级消耗）
---@return string BigNum 字符串
function DataManager.GetTotalExpForRange(fromLv, toLv)
    if toLv <= fromLv then return "0" end
    local config = DataManager.gameConfig["level_up"] or {}
    local baseExp = tostring(config.base_exp or "20")
    -- 强制取整，与 GetExpForLevel 一致
    local factor = math.max(1, math.min(3, math.floor((tonumber(config.exp_factor) or 2) + 0.5)))
    local sumHigh = DataManager.SumOfPowers(toLv - 1, factor)
    local sumLow = DataManager.SumOfPowers(fromLv - 1, factor)
    local diff = BigNum.sub(sumHigh, sumLow)
    return BigNum.mul(baseExp, diff)
end

--- 获取最高等级上限
---@return number
function DataManager.GetMaxLevel()
    local lvlConfig = DataManager.gameConfig["level_up"] or {}
    return tonumber(lvlConfig.max_level) or 100
end

--- 从排行榜中移除某玩家（删除时调用）
---@param username string 玩家用户名
---@param charName string|nil 角色名（排行榜中用角色名作为key）
function DataManager.RemovePlayerFromRanking(username, charName)
    if not cloud_ then return end
    -- 先从云端读取最新排行数据，再删除指定玩家
    cloud_:Get("系统配置/ranking_data.ini", {
        ok = function(values)
            local raw = values["系统配置/ranking_data.ini"]
            if raw and raw ~= "" then
                DataManager.rankingData = IniParser.Parse(raw)
            end

            local removed = false
            -- 按角色名删除（排行榜中存的是角色名）
            if charName and charName ~= "" and DataManager.rankingData[charName] then
                DataManager.rankingData[charName] = nil
                removed = true
            end
            -- 也按用户名尝试删除（兼容）
            if DataManager.rankingData[username] then
                DataManager.rankingData[username] = nil
                removed = true
            end
            -- 清理无效条目
            if DataManager.rankingData["default"] then
                DataManager.rankingData["default"] = nil
            end
            if DataManager.rankingData[""] then
                DataManager.rankingData[""] = nil
            end

            if removed then
                local content = IniParser.Serialize(DataManager.rankingData)
                cloud_:Set("系统配置/ranking_data.ini", content, {
                    ok = function()
                        print("[DataManager] 排行榜已移除玩家: " .. (charName or username))
                    end,
                    error = function(_, r)
                        print("[DataManager] 排行榜移除失败: " .. tostring(r))
                    end,
                })
            end
        end,
        error = function(_, r)
            print("[DataManager] 排行榜读取失败，无法移除玩家: " .. tostring(r))
        end,
    })
end

local isRankSyncing_ = false   -- 排行榜是否正在同步中
local rankSyncQueued_ = false  -- 同步期间是否有新请求排队

function DataManager.SyncLeaderboardScores(callback)
    if not cloud_ then
        if callback then callback(false) end
        return
    end
    local pd = DataManager.playerData
    if not pd or not pd.status then
        if callback then callback(false) end
        return
    end

    -- 如果正在同步中，标记排队，完成后自动再同步一次
    if isRankSyncing_ then
        rankSyncQueued_ = true
        return
    end

    isRankSyncing_ = true
    rankSyncQueued_ = false

    -- 用角色名作为 section key
    local charName = (pd.status and pd.status.name) or
                     (pd.account and pd.account.username) or "未知玩家"

    local function finishSync(success)
        isRankSyncing_ = false
        if callback then callback(success) end
        -- 同步期间有新请求，再同步一次最新数据
        if rankSyncQueued_ then
            rankSyncQueued_ = false
            DataManager.SyncLeaderboardScores()
        end
    end

    -- 先从云端读取最新排行数据，再合并写入（避免覆盖其他玩家数据）
    cloud_:Get("系统配置/ranking_data.ini", {
        ok = function(values)
            local raw = values["系统配置/ranking_data.ini"]
            if raw and raw ~= "" then
                DataManager.rankingData = IniParser.Parse(raw)
            end

            -- 合并当前玩家数据（含装备+buff+境界+战魂加成）
            local StatusUI = require("UI.StatusUI")
            local BagUI = require("UI.BagUI")
            local eAtk, eDef, eHp = StatusUI.GetEquipBonus()
            local buffAtk = BagUI.GetBuffValue(pd, "攻击")
            local buffDef = BagUI.GetBuffValue(pd, "防御")
            local buffHp = BagUI.GetBuffValue(pd, "生命上限")
            local rAtk, rDef, rHp = DataManager.GetRealmBonus()
            local soulBonus = DataManager.GetBattleSoulBonus(pd.status.battle_soul_level)
            local totalAtk = BigNum.add(BigNum.add(BigNum.add(BigNum.add(pd.status.atk or "5", tostring(eAtk)), tostring(buffAtk)), rAtk), soulBonus.atk)
            local totalDef = BigNum.add(BigNum.add(BigNum.add(BigNum.add(pd.status.def or "3", tostring(eDef)), tostring(buffDef)), rDef), soulBonus.def)
            local totalHp = BigNum.add(BigNum.add(BigNum.add(BigNum.add(pd.status.max_hp or "100", tostring(eHp)), tostring(buffHp)), rHp), soulBonus.max_hp)

            local rankEntry = {
                ["等级"] = NumFormat.Int(pd.status.level or 1),
                ["金币"] = NumFormat.Int(pd.status.gold or 0),
                ["攻击力"] = NumFormat.Int(totalAtk),
                ["防御力"] = NumFormat.Int(totalDef),
                ["生命上限"] = NumFormat.Int(totalHp),
                ["战魂等级"] = NumFormat.Int(pd.status.battle_soul_level or 0),
            }
            -- 自定义货币
            local currencies = pd.status.currencies or {}
            for cName, cVal in pairs(currencies) do
                rankEntry["货币:" .. cName] = NumFormat.Int(cVal or 0)
                rankEntry[cName] = NumFormat.Int(cVal or 0) -- 兼容直接用货币名
            end
            -- 背包道具计数
            for _, item in ipairs(pd.bag or {}) do
                local key = "道具:" .. item.name
                local prev = tonumber(rankEntry[key]) or 0
                rankEntry[key] = tostring(prev + (tonumber(item.count) or 1))
            end
            -- 装备栏（已穿戴装备计数）
            local equipSlots = { "weapon", "helmet", "armor", "bracer", "belt", "boots", "cloak", "necklace", "ring", "artifact", "mount", "wings", "shield" }
            for _, slot in ipairs(equipSlots) do
                local eName = pd.equip and pd.equip[slot]
                if eName and eName ~= "" then
                    local key = "装备:" .. eName
                    local prev = tonumber(rankEntry[key]) or 0
                    rankEntry[key] = tostring(prev + 1)
                end
            end
            DataManager.rankingData[charName] = rankEntry

            -- 清理无效条目
            if DataManager.rankingData["default"] then
                DataManager.rankingData["default"] = nil
            end
            if DataManager.rankingData[""] then
                DataManager.rankingData[""] = nil
            end

            -- 序列化并保存到云端
            local content = IniParser.Serialize(DataManager.rankingData)
            cloud_:Set("系统配置/ranking_data.ini", content, {
                ok = function()
                    print("[DataManager] 排行榜数据已同步")
                    finishSync(true)
                end,
                error = function(_, r)
                    print("[DataManager] 排行榜同步失败: " .. tostring(r))
                    finishSync(false)
                end,
            })
        end,
        error = function(_, r)
            print("[DataManager] 排行榜读取失败，尝试直接写入: " .. tostring(r))
            -- 读取失败时仍尝试写入本地数据（含装备+buff+境界+战魂加成）
            local StatusUI2 = require("UI.StatusUI")
            local BagUI2 = require("UI.BagUI")
            local eAtk2, eDef2, eHp2 = StatusUI2.GetEquipBonus()
            local buffAtk2 = BagUI2.GetBuffValue(pd, "攻击")
            local buffDef2 = BagUI2.GetBuffValue(pd, "防御")
            local buffHp2 = BagUI2.GetBuffValue(pd, "生命上限")
            local rAtk2, rDef2, rHp2 = DataManager.GetRealmBonus()
            local soulBonus2 = DataManager.GetBattleSoulBonus(pd.status.battle_soul_level)
            local totalAtk2 = BigNum.add(BigNum.add(BigNum.add(BigNum.add(pd.status.atk or "5", tostring(eAtk2)), tostring(buffAtk2)), rAtk2), soulBonus2.atk)
            local totalDef2 = BigNum.add(BigNum.add(BigNum.add(BigNum.add(pd.status.def or "3", tostring(eDef2)), tostring(buffDef2)), rDef2), soulBonus2.def)
            local totalHp2 = BigNum.add(BigNum.add(BigNum.add(BigNum.add(pd.status.max_hp or "100", tostring(eHp2)), tostring(buffHp2)), rHp2), soulBonus2.max_hp)

            local rankEntry2 = {
                ["等级"] = NumFormat.Int(pd.status.level or 1),
                ["金币"] = NumFormat.Int(pd.status.gold or 0),
                ["攻击力"] = NumFormat.Int(totalAtk2),
                ["防御力"] = NumFormat.Int(totalDef2),
                ["生命上限"] = NumFormat.Int(totalHp2),
                ["战魂等级"] = NumFormat.Int(pd.status.battle_soul_level or 0),
            }
            -- 自定义货币
            local currencies2 = pd.status.currencies or {}
            for cName, cVal in pairs(currencies2) do
                rankEntry2["货币:" .. cName] = NumFormat.Int(cVal or 0)
                rankEntry2[cName] = NumFormat.Int(cVal or 0)
            end
            -- 背包道具计数
            for _, item in ipairs(pd.bag or {}) do
                local key = "道具:" .. item.name
                local prev = tonumber(rankEntry2[key]) or 0
                rankEntry2[key] = tostring(prev + (tonumber(item.count) or 1))
            end
            -- 装备栏
            local equipSlots2 = { "weapon", "helmet", "armor", "bracer", "belt", "boots", "cloak", "necklace", "ring", "artifact", "mount", "wings", "shield" }
            for _, slot in ipairs(equipSlots2) do
                local eName = pd.equip and pd.equip[slot]
                if eName and eName ~= "" then
                    local key = "装备:" .. eName
                    local prev = tonumber(rankEntry2[key]) or 0
                    rankEntry2[key] = tostring(prev + 1)
                end
            end
            DataManager.rankingData[charName] = rankEntry2
            local content = IniParser.Serialize(DataManager.rankingData)
            cloud_:Set("系统配置/ranking_data.ini", content, {
                ok = function()
                    finishSync(true)
                end,
                error = function(_, r2)
                    finishSync(false)
                end,
            })
        end,
    })
end

--- 获取排行榜排序结果
---@param source string 数据来源字段（等级/金币/攻击力/货币:xx/道具:xx/装备:xx）
---@param topCount number 显示前几名
---@param order? string "desc"(默认降序) 或 "asc"(升序)
---@return table 排序后的列表 { {name=xx, value=xx}, ... }
function DataManager.GetRankedList(source, topCount, order)
    order = order or "desc"
    local list = {}
    for name, data in pairs(DataManager.rankingData) do
        -- 过滤无效条目
        if name ~= "default" and name ~= "" then
            local rawVal = data[source]
            -- 如果直接匹配不到，可能是用了不带前缀的货币名
            if not rawVal or rawVal == "" then
                rawVal = data["货币:" .. source]
            end
            local val = BigNum.new(rawVal or "0")
            -- 只有值>0的才加入排行（避免所有人都是0的无意义排行）
            if not BigNum.eq(val, BigNum.new("0")) then
                table.insert(list, { name = name, value = val })
            end
        end
    end
    -- 排序
    if order == "asc" then
        table.sort(list, function(a, b) return BigNum.gt(b.value, a.value) end)
    else
        table.sort(list, function(a, b) return BigNum.gt(a.value, b.value) end)
    end
    -- 截取前N名
    local result = {}
    for i = 1, math.min(topCount, #list) do
        result[i] = list[i]
    end
    return result
end

-- =============== 聊天系统 ===============

local CHAT_CLOUD_KEY = "系统配置/chat_messages.ini"
local MAX_CHAT_MESSAGES = 50

--- 解析聊天记录INI为列表
---@param sections table INI解析结果
---@return table 聊天记录列表
function DataManager.ParseChatMessages(sections)
    local list = {}
    for sectionName, data in pairs(sections) do
        if sectionName ~= "default" and sectionName ~= "" then
            table.insert(list, {
                id = sectionName,
                sender = data["发送者"] or "未知",
                content = data["内容"] or "",
                time = data["时间"] or "",
            })
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local isChatSending_ = false   -- 聊天是否正在发送中
local chatSendQueue_ = {}      -- 排队中的聊天消息 { {content, callback}, ... }

--- 发送聊天消息
---@param content string 消息内容
---@param callback fun(boolean)|nil
function DataManager.SendChatMessage(content, callback)
    if not cloud_ then
        if callback then callback(false) end
        return
    end
    if not content or content == "" then
        if callback then callback(false) end
        return
    end

    -- 如果正在发送中，排队等待
    if isChatSending_ then
        table.insert(chatSendQueue_, { content = content, callback = callback })
        return
    end

    isChatSending_ = true

    local pd = DataManager.playerData
    local sender = (pd and pd.status and pd.status.name) or
                   (pd and pd.account and pd.account.username) or "未知玩家"

    local msgId = "msg_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))

    -- 先从云端读取最新聊天记录，再合并新消息写入（避免覆盖其他玩家的消息）
    cloud_:Get(CHAT_CLOUD_KEY, {
        ok = function(values)
            local raw = values[CHAT_CLOUD_KEY]
            if raw and raw ~= "" then
                DataManager.chatMessages = DataManager.ParseChatMessages(IniParser.Parse(raw))
            end

            -- 添加新消息
            table.insert(DataManager.chatMessages, {
                id = msgId,
                sender = sender,
                content = content,
                time = os.date("%m-%d %H:%M"),
            })

            -- 限制消息数量
            while #DataManager.chatMessages > MAX_CHAT_MESSAGES do
                ---@diagnostic disable-next-line: param-type-mismatch
                table.remove(DataManager.chatMessages, 1)
            end

            -- 序列化并写入
            local sections = {}
            for _, msg in ipairs(DataManager.chatMessages) do
                sections[msg.id] = {
                    ["发送者"] = msg.sender,
                    ["内容"] = msg.content,
                    ["时间"] = msg.time,
                }
            end
            local iniContent = IniParser.Serialize(sections)
            cloud_:Set(CHAT_CLOUD_KEY, iniContent, {
                ok = function()
                    print("[DataManager] 聊天消息已发送")
                    isChatSending_ = false
                    if callback then callback(true) end
                    -- 处理排队的消息
                    if #chatSendQueue_ > 0 then
                        local next = table.remove(chatSendQueue_, 1)
                        DataManager.SendChatMessage(next.content, next.callback)
                    end
                end,
                error = function(_, r)
                    print("[DataManager] 聊天消息发送失败: " .. tostring(r))
                    isChatSending_ = false
                    if callback then callback(false) end
                    if #chatSendQueue_ > 0 then
                        local next = table.remove(chatSendQueue_, 1)
                        DataManager.SendChatMessage(next.content, next.callback)
                    end
                end,
            })
        end,
        error = function(_, r)
            print("[DataManager] 聊天记录读取失败，尝试直接写入: " .. tostring(r))
            -- 读取失败时仍尝试写入
            table.insert(DataManager.chatMessages, {
                id = msgId,
                sender = sender,
                content = content,
                time = os.date("%m-%d %H:%M"),
            })
            while #DataManager.chatMessages > MAX_CHAT_MESSAGES do
                ---@diagnostic disable-next-line: param-type-mismatch
                table.remove(DataManager.chatMessages, 1)
            end
            local sections = {}
            for _, msg in ipairs(DataManager.chatMessages) do
                sections[msg.id] = {
                    ["发送者"] = msg.sender,
                    ["内容"] = msg.content,
                    ["时间"] = msg.time,
                }
            end
            local iniContent = IniParser.Serialize(sections)
            cloud_:Set(CHAT_CLOUD_KEY, iniContent, {
                ok = function()
                    isChatSending_ = false
                    if callback then callback(true) end
                    if #chatSendQueue_ > 0 then
                        local next = table.remove(chatSendQueue_, 1)
                        DataManager.SendChatMessage(next.content, next.callback)
                    end
                end,
                error = function(_, r2)
                    isChatSending_ = false
                    if callback then callback(false) end
                    if #chatSendQueue_ > 0 then
                        local next = table.remove(chatSendQueue_, 1)
                        DataManager.SendChatMessage(next.content, next.callback)
                    end
                end,
            })
        end,
    })
end

--- 刷新聊天记录（从云端重新加载）
---@param callback fun()|nil
function DataManager.RefreshChatMessages(callback)
    if not cloud_ then
        if callback then callback() end
        return
    end
    cloud_:Get(CHAT_CLOUD_KEY, {
        ok = function(values)
            local raw = values[CHAT_CLOUD_KEY]
            if raw and raw ~= "" then
                DataManager.chatMessages = DataManager.ParseChatMessages(IniParser.Parse(raw))
            end
            if callback then callback() end
        end,
        error = function()
            if callback then callback() end
        end,
    })
end

--- 获取当前玩家境界数据
---@return table|nil realmData 当前境界配置
function DataManager.GetCurrentRealm()
    local player = DataManager.playerData
    if not player then return nil end
    local stage = tonumber(player.status.realm) or 1
    return DataManager.realmsByStage[stage]
end

--- 获取下一阶段境界数据（用于突破）
---@return table|nil realmData 下一境界配置，已是最高则返回 nil
function DataManager.GetNextRealm()
    local player = DataManager.playerData
    if not player then return nil end
    local stage = tonumber(player.status.realm) or 1
    return DataManager.realmsByStage[stage + 1]
end

--- 获取当前层数
---@return number
function DataManager.GetRealmLayer()
    local player = DataManager.playerData
    if not player then return 1 end
    return tonumber(player.status.realm_layer) or 1
end

--- 获取当前层修炼经验
---@return string
function DataManager.GetRealmExp()
    local player = DataManager.playerData
    if not player then return "0" end
    return player.status.realm_exp or "0"
end

--- 判断当前是否处于大境界的最高层（即需要突破才能进入下一大境界）
---@return boolean
function DataManager.IsAtMaxLayer()
    local realm = DataManager.GetCurrentRealm()
    if not realm then return true end
    local layer = DataManager.GetRealmLayer()
    return layer >= realm.layers
end

--- 获取境界属性加成（基于大境界阶段 + 当前层数的累计加成）
---@return string atk, string def, string hp
function DataManager.GetRealmBonus()
    local player = DataManager.playerData
    if not player then return "0", "0", "0" end
    local stage = tonumber(player.status.realm) or 1
    local layer = tonumber(player.status.realm_layer) or 1
    local totalAtk = "0"
    local totalDef = "0"
    local totalHp = "0"
    -- 累计所有已过境界的全层加成
    for i = 1, stage - 1 do
        local r = DataManager.realmsByStage[i]
        if r then
            local layers = r.layers or 9
            for _ = 1, layers do
                totalAtk = BigNum.add(totalAtk, r.atk_bonus or "0")
                totalDef = BigNum.add(totalDef, r.def_bonus or "0")
                totalHp = BigNum.add(totalHp, r.hp_bonus or "0")
            end
        end
    end
    -- 当前境界已达到的层数加成
    local curRealm = DataManager.realmsByStage[stage]
    if curRealm then
        for _ = 1, layer do
            totalAtk = BigNum.add(totalAtk, curRealm.atk_bonus or "0")
            totalDef = BigNum.add(totalDef, curRealm.def_bonus or "0")
            totalHp = BigNum.add(totalHp, curRealm.hp_bonus or "0")
        end
    end
    return totalAtk, totalDef, totalHp
end

--- 获取指定阶段的境界名称
---@param stage number|string
---@return string
function DataManager.GetRealmName(stage)
    local s = tonumber(stage) or 1
    local realm = DataManager.realmsByStage[s]
    if realm then return realm.name end
    return "未知"
end

--- 获取完整境界显示名（如"练气期三层"）
---@return string
function DataManager.GetRealmFullName()
    local player = DataManager.playerData
    if not player then return "未知" end
    local stage = tonumber(player.status.realm) or 1
    local layer = tonumber(player.status.realm_layer) or 1
    local realm = DataManager.realmsByStage[stage]
    if not realm then return "未知" end
    local layerNames = { "一", "二", "三", "四", "五", "六", "七", "八", "九" }
    local layerStr = layerNames[layer] or tostring(layer)
    return realm.name .. layerStr .. "层"
end

return DataManager
