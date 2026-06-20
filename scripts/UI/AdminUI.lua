---------------------------------------------------
-- AdminUI.lua - 管理员后台界面（完整配置管理版）
-- 支持所有系统配置的读取、修改、添加
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local IniParser = require("Utils.IniParser")
local NumFormat = require("Utils.NumFormat")
local BigNum = require("Utils.BigNum")
local EquipSlots = require("Systems.EquipSlots")

local AdminUI = {}

-- 管理员凭据
local SUPER_ADMIN = "xiake139"
local ADMIN_PASSWORD = "114124"

-- 模块状态
local adminLoggedIn_ = false
local currentAdminUser_ = ""  -- 当前登录的管理员用户名
local rootPanel_ = nil
local contentPanel_ = nil
local msgLabel_ = nil
local currentCategory_ = "players"  -- 当前选中分类
local searchKeyword_ = ""  -- 当前搜索关键词
local editDialog_ = nil
local selectDialog_ = nil

-- 分类定义
local CATEGORIES = {
    { id = "players", name = "玩家管理" },
    { id = "game_config", name = "游戏设置" },
    { id = "maps", name = "地图" },
    { id = "monsters", name = "怪物" },
    { id = "items", name = "物品" },
    { id = "equipment", name = "装备" },
    { id = "quests", name = "任务" },
    { id = "shops", name = "商店" },
    { id = "dungeons", name = "副本" },
    { id = "npcs", name = "NPC" },
    { id = "giftpacks", name = "礼包" },
    { id = "realms", name = "境界管理" },
    { id = "distribute", name = "发放物品" },
    { id = "chests", name = "宝箱管理" },
    { id = "pets", name = "宠物管理" },
    { id = "pet_equip", name = "宠物装备" },
    { id = "pet_bonus", name = "宠物属性加成" },
    { id = "system_shops", name = "系统商店" },
    { id = "battle_soul", name = "战魂管理" },
    { id = "leaderboards", name = "排行榜" },
    { id = "teleport_maps", name = "传送地图" },
    { id = "mounts", name = "坐骑管理" },

    { id = "generator", name = "一键生成" },
}

-- =============== 前向声明 ===============
local CreateButtonSelector  -- 定义在后面，ShowEditDialog 中需要引用

-- =============== 工具函数 ===============

--- 显示提示信息
local function ShowMsg(text)
    if msgLabel_ then
        msgLabel_:SetText(text)
    end
end

--- 关闭弹窗
local function CloseDialog()
    if editDialog_ and rootPanel_ then
        rootPanel_:RemoveChild(editDialog_)
        editDialog_ = nil
    end
end

--- 装备选择弹窗（带搜索，NPC商店和系统商店共用）
---@param editItems table 商品列表引用
---@param rebuildCallback function 重建列表回调
local function ShowEquipSelectDialog(editItems, rebuildCallback)
    -- 收集所有装备
    local allEquips = {}
    for eId, eData in pairs(DataManager.equipment) do
        table.insert(allEquips, { id = eId, name = eData.name or eId, price_sell = eData.price_sell or "0" })
    end
    table.sort(allEquips, function(a, b) return a.name < b.name end)
    if #allEquips == 0 then return end

    local listPanel = UI.Panel { width = "100%", flexDirection = "column" }

    local function RenderEquipList(keyword)
        listPanel:ClearChildren()
        local kw = (keyword or ""):lower()
        local count = 0
        for _, eq in ipairs(allEquips) do
            if kw == "" or eq.name:lower():find(kw, 1, true) or eq.id:lower():find(kw, 1, true) then
                count = count + 1
                local priceText = eq.price_sell ~= "0" and ("出售价: " .. NumFormat.Short(eq.price_sell)) or "无定价"
                listPanel:AddChild(UI.Panel {
                    flexDirection = "column", width = "100%",
                    marginBottom = 3, backgroundColor = { 50, 45, 80, 200 }, borderRadius = 4, padding = 6,
                    children = {
                        UI.Panel {
                            flexDirection = "row", width = "100%", alignItems = "center",
                            children = {
                                UI.Label { text = eq.name, fontSize = 12, fontColor = { 220, 220, 255, 255 }, flex = 1, flexShrink = 1 },
                                UI.Button {
                                    text = "添加", fontSize = 10, width = 42, height = 22, variant = "primary",
                                    onClick = function()
                                        -- 自动使用装备出售价作为商店价格（价格为0时游戏内也会回退到出售价）
                                        local autoPrice = (eq.price_sell ~= "0" and eq.price_sell ~= "") and eq.price_sell or "0"
                                        table.insert(editItems, { name = eq.name, price = autoPrice, desc = "装备" })
                                        rebuildCallback()
                                        if selectDialog_ then selectDialog_:Remove(); selectDialog_ = nil end
                                    end,
                                },
                            },
                        },
                        UI.Label { text = priceText, fontSize = 10, fontColor = { 140, 200, 140, 255 }, marginTop = 2 },
                    },
                })
            end
        end
        if count == 0 then
            listPanel:AddChild(UI.Label { text = "无匹配装备", fontSize = 11, fontColor = { 160, 160, 160, 255 }, textAlign = "center", marginTop = 10 })
        end
    end

    RenderEquipList("")

    local searchField = UI.TextField {
        placeholder = "搜索装备名...", width = "100%", height = 30, fontSize = 11,
        onChange = function(_, text) RenderEquipList(text) end,
    }

    selectDialog_ = UI.Panel {
        width = "100%", height = "100%", position = "absolute",
        justifyContent = "center", alignItems = "center", backgroundColor = { 0, 0, 0, 160 },
        children = {
            UI.Panel {
                width = 300, maxHeight = 450, backgroundColor = { 30, 25, 55, 250 },
                borderRadius = 10, padding = 12, flexDirection = "column",
                children = {
                    UI.Label { text = "选择装备添加到商店", fontSize = 13, fontColor = { 255, 220, 100, 255 }, textAlign = "center", marginBottom = 6 },
                    searchField,
                    UI.ScrollView { width = "100%", maxHeight = 320, marginTop = 6, children = { listPanel } },
                    UI.Button {
                        text = "关闭", variant = "secondary", width = 70, height = 26, marginTop = 8, alignSelf = "center",
                        onClick = function()
                            if selectDialog_ then selectDialog_:Remove(); selectDialog_ = nil end
                        end,
                    },
                },
            },
        },
    }
    if rootPanel_ then rootPanel_:AddChild(selectDialog_) end
end

---@param value string
---@param opts table|nil {width, placeholder, multiline}
---@return Widget panel, Widget field
local function CreateFormField(label, value, opts)
    opts = opts or {}
    local unitLabel = nil
    local field = UI.TextField {
        value = tostring(value or ""),
        placeholder = opts.placeholder or "",
        width = opts.width or 200,
        height = opts.height or 32,
        fontSize = 12,
        onChange = opts.showUnit and function(_, t)
            if unitLabel then
                local v = (t == nil or t == "") and "0" or t
                unitLabel:SetText(NumFormat.Short(v))
            end
        end or nil,
    }
    -- 输入框+单位标签组合（单位在输入框下方换行显示）
    local fieldGroup
    if opts.showUnit then
        local initVal = (value == nil or value == "") and "0" or tostring(value)
        unitLabel = UI.Label { text = NumFormat.Short(initVal), fontSize = 9, fontColor = { 140, 200, 140, 255 }, marginTop = 1 }
        fieldGroup = UI.Panel {
            flexDirection = "column",
            children = { field, unitLabel },
        }
    else
        fieldGroup = field
    end
    local panel = UI.Panel {
        flexDirection = "row",
        alignItems = "flex-start",
        gap = 8,
        marginBottom = 4,
        children = {
            UI.Label {
                text = label,
                fontSize = 12,
                fontColor = { 180, 180, 200, 255 },
                width = opts.labelWidth or 80,
                marginTop = 6,
            },
            fieldGroup,
        },
    }
    return panel, field
end

-- 系统配置保存队列：同一个 key 同时只允许一个请求 in-flight
local configSaving_ = {}     -- configSaving_[key] = true 表示该 key 正在保存
local configDirty_ = {}      -- configDirty_[key] = {content, onDone} 排队中的最新数据
local CONFIG_MAX_RETRIES = 2

--- 保存配置到云端（使用 DataManager 的共享云存储）
---@param configKey string 云端存储 key
---@param content string INI 内容
---@param onDone fun(success: boolean)|nil
local function SaveConfigToCloud(configKey, content, onDone)
    local cloud = DataManager.GetCloudProvider()
    if not cloud then
        print("[Admin] 云存储不可用")
        if onDone then onDone(false) end
        return
    end

    -- 如果该 key 正在保存中，排队最新数据（覆盖旧排队）
    if configSaving_[configKey] then
        configDirty_[configKey] = { content = content, onDone = onDone }
        return
    end

    configSaving_[configKey] = true
    configDirty_[configKey] = nil

    local retries = 0
    local function doSave(c, cb)
        cloud:Set(configKey, c, {
            ok = function()
                configSaving_[configKey] = false
                print("[Admin] 配置已保存: " .. configKey)
                if cb then cb(true) end
                -- 如果保存期间有新数据排队，立即保存最新版
                local queued = configDirty_[configKey]
                if queued then
                    configDirty_[configKey] = nil
                    SaveConfigToCloud(configKey, queued.content, queued.onDone)
                end
            end,
            error = function(code, reason)
                if retries < CONFIG_MAX_RETRIES then
                    retries = retries + 1
                    print("[Admin] 保存失败，重试 (" .. retries .. "): " .. configKey)
                    doSave(c, cb)
                else
                    configSaving_[configKey] = false
                    print("[Admin] 保存失败(已重试): " .. tostring(reason))
                    if cb then cb(false) end
                    -- 有排队数据也尝试
                    local queued = configDirty_[configKey]
                    if queued then
                        configDirty_[configKey] = nil
                        SaveConfigToCloud(configKey, queued.content, queued.onDone)
                    end
                end
            end,
        })
    end
    doSave(content, onDone)
end

-- 怪物类型定义（默认值，运行时从云端配置覆盖）
-- min/max: 战斗属性(HP/ATK/DEF)区间; min_exp/max_exp: 经验区间; min_gold/max_gold: 金币区间
local MONSTER_TYPES_DEFAULTS = {
    { name = "普通怪",  min_hp = "10", max_hp = "2000", min_atk = "5", max_atk = "1000", min_def = "3", max_def = "800", min_exp = "5", max_exp = "500", currency_ranges = { ["金币"] = { min = "1", max = "200" } }, desc = "散发着微弱的妖气" },
    { name = "精英怪",  min_hp = "3000", max_hp = "100000", min_atk = "1500", max_atk = "50000", min_def = "1000", max_def = "40000", min_exp = "1000", max_exp = "30000", currency_ranges = { ["金币"] = { min = "500", max = "10000" } }, desc = "浑身散发着强大气息" },
    { name = "BOSS",    min_hp = "500000", max_hp = "1000000", min_atk = "200000", max_atk = "500000", min_def = "150000", max_def = "400000", min_exp = "100000", max_exp = "500000", currency_ranges = { ["金币"] = { min = "50000", max = "200000" } }, desc = "威压四方，令人胆寒" },
    { name = "帝级",    min_hp = "3000000", max_hp = "500000000", min_atk = "1000000", max_atk = "200000000", min_def = "800000", max_def = "150000000", min_exp = "1000000", max_exp = "100000000", currency_ranges = { ["金币"] = { min = "500000", max = "50000000" } }, desc = "帝威无边，天地变色" },
    { name = "仙级",    min_hp = "600000000", max_hp = "5000000000", min_atk = "300000000", max_atk = "2000000000", min_def = "200000000", max_def = "1500000000", min_exp = "200000000", max_exp = "2000000000", currency_ranges = { ["金币"] = { min = "100000000", max = "1000000000" } }, desc = "仙威浩荡，不可直视" },
    { name = "神级",    min_hp = "5000000000", max_hp = "60000000000", min_atk = "2000000000", max_atk = "30000000000", min_def = "1500000000", max_def = "20000000000", min_exp = "2000000000", max_exp = "30000000000", currency_ranges = { ["金币"] = { min = "1000000000", max = "15000000000" } }, desc = "神威如狱，万物臣服" },
    { name = "创世级",  min_hp = "60000000000", max_hp = "10000000000000000000000000000000000000000", min_atk = "30000000000", max_atk = "5000000000000000000000000000000000000000", min_def = "20000000000", max_def = "3000000000000000000000000000000000000000", min_exp = "30000000000", max_exp = "5000000000000000000000000000000000000000", currency_ranges = { ["金币"] = { min = "10000000000", max = "1000000000000000000000000000000000000000" } }, desc = "创世之力，毁天灭地" },
}

--- 加载怪物类型配置（优先从云端配置读取，否则用默认值）
local function LoadMonsterTypes()
    local saved = DataManager.gameConfig["monster_gen"]
    if saved and #saved > 0 then
        -- 兼容旧配置：如果没有 min_hp 等新字段，从旧 min/max 迁移
        for _, t in ipairs(saved) do
            local oldMin = t.min or "10"
            local oldMax = t.max or "2000"
            if not t.min_hp or t.min_hp == "" then t.min_hp = oldMin end
            if not t.max_hp or t.max_hp == "" then t.max_hp = oldMax end
            if not t.min_atk or t.min_atk == "" then t.min_atk = oldMin end
            if not t.max_atk or t.max_atk == "" then t.max_atk = oldMax end
            if not t.min_def or t.min_def == "" then t.min_def = oldMin end
            if not t.max_def or t.max_def == "" then t.max_def = oldMax end
            if not t.min_exp or t.min_exp == "" then t.min_exp = oldMin end
            if not t.max_exp or t.max_exp == "" then t.max_exp = oldMax end
            -- 兼容旧 min_gold/max_gold → 迁移到 currency_ranges
            if not t.currency_ranges then
                t.currency_ranges = {}
                local oldGoldMin = t.min_gold or oldMin
                local oldGoldMax = t.max_gold or oldMax
                t.currency_ranges["金币"] = { min = oldGoldMin, max = oldGoldMax }
            end
        end
        return saved
    end
    local types = {}
    for _, t in ipairs(MONSTER_TYPES_DEFAULTS) do
        -- 深拷贝 currency_ranges
        local cr = {}
        if t.currency_ranges then
            for k, v in pairs(t.currency_ranges) do
                cr[k] = { min = v.min, max = v.max }
            end
        end
        table.insert(types, {
            name = t.name,
            min_hp = t.min_hp, max_hp = t.max_hp,
            min_atk = t.min_atk, max_atk = t.max_atk,
            min_def = t.min_def, max_def = t.max_def,
            min_exp = t.min_exp, max_exp = t.max_exp,
            currency_ranges = cr,
            desc = t.desc,
        })
    end
    return types
end

local MONSTER_TYPES = LoadMonsterTypes()

--- 将 DataManager 中的数据序列化为 INI 并保存
---@param category string
local function SaveCategoryToCloud(category, onDoneExtra)
    local content = ""
    if category == "maps" then
        local sections = {}
        for id, data in pairs(DataManager.maps) do
            sections[id] = {
                ["名称"] = data.name or id,
                ["描述"] = data.desc or "",
                ["怪物"] = data.monsters or "",
                ["NPC"] = data.npcs or "",
                ["前方"] = data.front or "",
                ["后方"] = data.back or "",
                ["左方"] = data.left or "",
                ["右方"] = data.right or "",
                ["等级要求"] = NumFormat.Int(data.level_req or 0),
            }
        end
        content = IniParser.Serialize(sections)
        SaveConfigToCloud("系统配置/maps.ini", content, function(ok)
            ShowMsg(ok and "地图配置已保存到云端" or "保存失败")
        end)
    elseif category == "monsters" then
        local sections = {}
        for id, data in pairs(DataManager.monsters) do
            local sec = {
                ["名称"] = data.name or id,
                ["类型"] = data.type or "普通怪",
                ["描述"] = data.desc or "",
                ["生命值"] = NumFormat.Int(data.hp or 20),
                ["攻击力"] = NumFormat.Int(data.atk or 3),
                ["防御力"] = NumFormat.Int(data.def or 1),
                ["经验值"] = NumFormat.Int(data.exp or 5),
                ["金币"] = NumFormat.Int(data.gold or 2),
                ["掉落"] = data.drops or "",
            }
            -- 序列化多货币掉落
            if data.currency_drops then
                local cIdx = 0
                for cName, cVal in pairs(data.currency_drops) do
                    cIdx = cIdx + 1
                    sec["货币" .. cIdx .. "_名称"] = cName
                    sec["货币" .. cIdx .. "_数量"] = NumFormat.Int(cVal or 0)
                end
                sec["货币数量"] = tostring(cIdx)
            else
                sec["货币数量"] = "0"
            end
            sections[id] = sec
        end
        content = IniParser.Serialize(sections)
        SaveConfigToCloud("系统配置/monsters.ini", content, function(ok)
            ShowMsg(ok and "怪物配置已保存到云端" or "保存失败")
        end)
    elseif category == "items" then
        local sections = {}
        for id, data in pairs(DataManager.items) do
            local sec = {
                ["名称"] = data.name or id,
                ["类型"] = data.type or "材料",
                ["数值"] = tostring(data.value or "0"),
                ["描述"] = data.desc or "",
            }
            if data.duration and tonumber(data.duration) and tonumber(data.duration) > 0 then
                sec["持续时间"] = tostring(data.duration)
            end
            -- 宠物装备额外字段
            if data.pet_slot and data.pet_slot ~= "" then sec["宠物部位"] = data.pet_slot end
            if data.pet_atk and data.pet_atk ~= "" and data.pet_atk ~= "0" then sec["宠物攻击"] = tostring(data.pet_atk) end
            if data.pet_def and data.pet_def ~= "" and data.pet_def ~= "0" then sec["宠物防御"] = tostring(data.pet_def) end
            if data.pet_hp and data.pet_hp ~= "" and data.pet_hp ~= "0" then sec["宠物生命"] = tostring(data.pet_hp) end
            sections[id] = sec
        end
        content = IniParser.Serialize(sections)
        SaveConfigToCloud("系统配置/items.ini", content, function(ok)
            ShowMsg(ok and "物品配置已保存到云端" or "保存失败")
        end)
    elseif category == "equipment" then
        local sections = {}
        for id, data in pairs(DataManager.equipment) do
            sections[id] = {
                ["名称"] = data.name or id,
                ["部位"] = data.slot or "武器",
                ["品质"] = data.quality or "白色",
                ["描述"] = data.desc or "",
                ["攻击"] = NumFormat.Int(data.atk or 0),
                ["防御"] = NumFormat.Int(data.def or 0),
                ["生命"] = NumFormat.Int(data.hp or 0),
                ["等级需求"] = NumFormat.Int(data.level_req or 1),
                ["出售价"] = NumFormat.Int(data.price_sell or 0),
            }
        end
        content = IniParser.Serialize(sections)
        SaveConfigToCloud("系统配置/equipment.ini", content, function(ok)
            ShowMsg(ok and "装备配置已保存到云端" or "保存失败")
        end)
    elseif category == "quests" then
        local sections = {}
        for id, data in pairs(DataManager.quests) do
            sections[id] = {
                ["名称"] = data.name or id,
                ["类型"] = data.type or "主线",
                ["描述"] = data.desc or "",
                ["目标类型"] = data.target_type or "击杀",
                ["目标名称"] = data.target_name or "",
                ["目标数量"] = NumFormat.Int(data.target_count or 1),
                ["奖励经验"] = NumFormat.Int(data.reward_exp or 0),
                ["奖励金币"] = NumFormat.Int(data.reward_gold or 0),
                ["奖励物品"] = data.reward_items or "",
                ["后续任务"] = data.next_quest or "",
            }
        end
        content = IniParser.Serialize(sections)
        SaveConfigToCloud("系统配置/quests.ini", content, function(ok)
            ShowMsg(ok and "任务配置已保存到云端" or "保存失败")
        end)
    elseif category == "shops" then
        local sections = {}
        for id, data in pairs(DataManager.shops) do
            local sec = {
                ["名称"] = data.name or id,
                ["描述"] = data.desc or "",
                ["商品数量"] = tostring(#(data.items or {})),
            }
            for i, item in ipairs(data.items or {}) do
                local p = item.price or "0"
                if p == "" then p = "0" end
                sec["商品_" .. i] = (item.name or "") .. ":" .. p .. ":" .. (item.desc or "")
            end
            sections[id] = sec
        end
        content = IniParser.Serialize(sections)
        SaveConfigToCloud("系统配置/shops.ini", content, function(ok)
            ShowMsg(ok and "商店配置已保存到云端" or "保存失败")
        end)
    elseif category == "system_shops" then
        local sections = {}
        for id, data in pairs(DataManager.systemShops) do
            local sec = {
                ["名称"] = data.name or id,
                ["货币"] = data.currency or "金币",
                ["描述"] = data.desc or "",
                ["商品数量"] = tostring(#(data.items or {})),
            }
            for i, item in ipairs(data.items or {}) do
                local p = item.price or "0"
                if p == "" then p = "0" end
                sec["商品_" .. i] = (item.name or "") .. ":" .. p .. ":" .. (item.desc or "")
            end
            sections[id] = sec
        end
        content = IniParser.Serialize(sections)
        SaveConfigToCloud("系统配置/system_shops.ini", content, function(ok)
            ShowMsg(ok and "系统商店配置已保存到云端" or "保存失败")
        end)
    elseif category == "dungeons" then
        local sections = {}
        for id, data in pairs(DataManager.dungeons) do
            local sec = {
                ["名称"] = data.name or id,
                ["描述"] = data.desc or "",
                ["等级需求"] = NumFormat.Int(data.level_req or 1),
                ["波数"] = NumFormat.Int(data.waves or 1),
                ["首领"] = data.boss or "",
                ["奖励经验"] = NumFormat.Int(data.reward_exp or 0),
                ["奖励金币"] = NumFormat.Int(data.reward_gold or 0),
                ["奖励物品"] = data.reward_items or "",
            }
            for i = 1, (data.waves or 1) do
                sec["第" .. i .. "波"] = data["wave_" .. i] or ""
            end
            sections[id] = sec
        end
        content = IniParser.Serialize(sections)
        SaveConfigToCloud("系统配置/dungeons.ini", content, function(ok)
            ShowMsg(ok and "副本配置已保存到云端" or "保存失败")
        end)
    elseif category == "npcs" then
        local sections = {}
        for id, data in pairs(DataManager.npcs) do
            local sec = {
                ["名称"] = data.name or id,
                ["类型"] = data.type or "任务",
                ["对话"] = data.dialog or "",
                ["所在地"] = data.location or "",
            }
            if data.type == "商人" or data.type == "merchant" then
                sec["商店编号"] = data.shop_id or ""
            else
                sec["任务编号"] = data.quest_id or ""
            end
            sections[id] = sec
        end
        content = IniParser.Serialize(sections)
        SaveConfigToCloud("系统配置/npcs.ini", content, function(ok)
            ShowMsg(ok and "NPC配置已保存到云端" or "保存失败")
        end)
    elseif category == "giftpacks" then
        local sections = {}
        for id, data in pairs(DataManager.giftpacks) do
            sections[id] = {
                ["名称"] = data.name or id,
                ["描述"] = data.desc or "",
                ["奖励物品"] = data.reward_items or "",
                ["奖励金币"] = NumFormat.Int(data.reward_gold or 0),
                ["奖励经验"] = NumFormat.Int(data.reward_exp or 0),
                ["最大使用次数"] = NumFormat.Int(data.max_uses or 0),
                ["已使用次数"] = NumFormat.Int(data.used_count or 0),
            }
        end
        content = IniParser.Serialize(sections)
        SaveConfigToCloud("系统配置/giftpacks.ini", content, function(ok)
            ShowMsg(ok and "礼包配置已保存到云端" or "保存失败")
        end)
    elseif category == "realms" then
        local sections = {}
        for _, data in ipairs(DataManager.realms) do
            sections[data.name] = {
                ["名称"] = data.name,
                ["阶段"] = tostring(data.stage),
                ["层数"] = tostring(data.layers),
                ["描述"] = data.desc or "",
                ["突破材料"] = data.breakthrough_material or "",
                ["突破数量"] = tostring(data.breakthrough_count or 0),
                ["提升材料"] = data.upgrade_material or "",
                ["提升数量"] = tostring(data.upgrade_count or 0),
                ["层经验"] = tostring(data.layer_exp or "100"),
                ["攻击加成"] = tostring(data.atk_bonus or "0"),
                ["防御加成"] = tostring(data.def_bonus or "0"),
                ["生命加成"] = tostring(data.hp_bonus or "0"),
            }
        end
        content = IniParser.Serialize(sections)
        SaveConfigToCloud("系统配置/realms.ini", content, function(ok)
            ShowMsg(ok and "境界配置已保存到云端" or "保存失败")
        end)
    elseif category == "realm_pills" then
        local sections = {}
        for id, data in pairs(DataManager.realmPills) do
            sections[id] = {
                ["名称"] = data.name or id,
                ["描述"] = data.desc or "",
                ["数值"] = tostring(data.value or "0"),
            }
        end
        content = IniParser.Serialize(sections)
        -- 同步注入 items
        for id, pill in pairs(DataManager.realmPills) do
            DataManager.items[id] = {
                name = pill.name,
                type = "境界经验",
                value = pill.value,
                desc = pill.desc,
            }
        end
        SaveConfigToCloud("系统配置/realm_pills.ini", content, function(ok)
            ShowMsg(ok and "境界经验丹配置已保存到云端" or "保存失败")
        end)
    elseif category == "game_config" then
        local gc = DataManager.gameConfig
        local sections = {}
        local gameSec = gc["game"] or {}
        sections["游戏设置"] = {
            ["标题"] = gameSec.title or "修仙游戏",
            ["版本"] = gameSec.version or "1.0.0",
            ["起始地图"] = gameSec.start_map or "新手村",
            ["起始任务"] = gameSec.start_quest or "main_001",
        }
        local defSec = gc["player_default"] or {}
        sections["玩家默认属性"] = {
            ["生命值"] = NumFormat.Int(defSec.hp or 100),
            ["法力值"] = NumFormat.Int(defSec.mp or 50),
            ["攻击力"] = NumFormat.Int(defSec.atk or 5),
            ["防御力"] = NumFormat.Int(defSec.def or 3),
            ["等级"] = NumFormat.Int(defSec.level or 1),
            ["经验"] = NumFormat.Int(defSec.exp or 0),
            ["金币"] = NumFormat.Int(defSec.gold or 50),
        }
        local lvlSec = gc["level_up"] or {}
        sections["升级配置"] = {
            ["基础经验"] = NumFormat.Int(lvlSec.base_exp or 20),
            ["经验系数"] = tostring(lvlSec.exp_factor or 2),
            ["每级生命"] = NumFormat.Int(lvlSec.hp_per_level or 20),
            ["每级法力"] = NumFormat.Int(lvlSec.mp_per_level or 10),
            ["每级攻击"] = NumFormat.Int(lvlSec.atk_per_level or 3),
            ["每级防御"] = NumFormat.Int(lvlSec.def_per_level or 2),
            ["最高等级"] = NumFormat.Int(lvlSec.max_level or 100),
        }
        -- 货币配置
        local currList = gc["currencies"] or { "金币" }
        local currSec = { ["货币数量"] = tostring(#currList) }
        for i, name in ipairs(currList) do
            currSec["货币_" .. i] = name
        end
        sections["货币配置"] = currSec
        -- 初始货币配置
        local initCurrData = gc["initial_currencies"] or {}
        local initCurrCount = 0
        local initCurrSec = {}
        for name, amount in pairs(initCurrData) do
            initCurrCount = initCurrCount + 1
            initCurrSec["货币_" .. initCurrCount .. "_名称"] = name
            initCurrSec["货币_" .. initCurrCount .. "_数量"] = tostring(amount)
        end
        initCurrSec["数量"] = tostring(initCurrCount)
        sections["初始货币"] = initCurrSec
        -- 初始背包配置
        local initBagData = gc["initial_bag"] or {}
        local initBagSec = { ["物品数量"] = tostring(#initBagData) }
        for i, item in ipairs(initBagData) do
            initBagSec["物品_" .. i .. "_名称"] = item.name or ""
            initBagSec["物品_" .. i .. "_数量"] = tostring(item.count or 1)
        end
        sections["初始背包"] = initBagSec
        -- 怪物生成区间配置
        local monGenSec = { ["类型数量"] = tostring(#MONSTER_TYPES) }
        for i, mt in ipairs(MONSTER_TYPES) do
            monGenSec["类型" .. i .. "_名称"] = mt.name
            monGenSec["类型" .. i .. "_HP下限"] = mt.min_hp or "10"
            monGenSec["类型" .. i .. "_HP上限"] = mt.max_hp or "2000"
            monGenSec["类型" .. i .. "_攻击下限"] = mt.min_atk or "5"
            monGenSec["类型" .. i .. "_攻击上限"] = mt.max_atk or "1000"
            monGenSec["类型" .. i .. "_防御下限"] = mt.min_def or "3"
            monGenSec["类型" .. i .. "_防御上限"] = mt.max_def or "800"
            monGenSec["类型" .. i .. "_经验下限"] = mt.min_exp or "5"
            monGenSec["类型" .. i .. "_经验上限"] = mt.max_exp or "500"
            -- 货币区间（多货币支持）
            if mt.currency_ranges then
                local cIdx = 0
                for cName, cRange in pairs(mt.currency_ranges) do
                    cIdx = cIdx + 1
                    monGenSec["类型" .. i .. "_货币" .. cIdx .. "_名称"] = cName
                    monGenSec["类型" .. i .. "_货币" .. cIdx .. "_下限"] = cRange.min or "0"
                    monGenSec["类型" .. i .. "_货币" .. cIdx .. "_上限"] = cRange.max or "0"
                end
                monGenSec["类型" .. i .. "_货币数量"] = tostring(cIdx)
            else
                monGenSec["类型" .. i .. "_货币数量"] = "0"
            end
            monGenSec["类型" .. i .. "_描述"] = mt.desc or ""
        end
        sections["怪物生成配置"] = monGenSec
        -- 部署版本配置（懒迁移）
        local deployCfg = gc["deploy"] or {}
        sections["部署版本"] = {
            ["版本号"] = tostring(deployCfg.version or 0),
            ["目标地图"] = deployCfg.target_map or "",
        }
        content = IniParser.Serialize(sections)
        SaveConfigToCloud("系统配置/game_config.ini", content, function(ok)
            ShowMsg(ok and "游戏设置已保存到云端" or "保存失败")
            if onDoneExtra then onDoneExtra(ok) end
        end)
        return  -- 提前返回，避免下方重复调用 onDoneExtra
    elseif category == "admins" then
        -- 管理员列表序列化为逗号分隔字符串
        local list = {}
        for username in pairs(DataManager.admins) do
            table.insert(list, username)
        end
        content = table.concat(list, ",")
        SaveConfigToCloud("系统配置/admins.txt", content, function(ok)
            ShowMsg(ok and "管理员列表已保存到云端" or "保存失败")
        end)
    elseif category == "pet_types" then
        local sections = {}
        for id, data in pairs(DataManager.petTypes) do
            sections[id] = {
                ["名称"] = data.name or id,
                ["描述"] = data.desc or "",
                ["攻击"] = tostring(data.atk or "10"),
                ["防御"] = tostring(data.def or "5"),
                ["生命"] = tostring(data.max_hp or "100"),
                ["品质"] = data.quality or "白",
                ["技能"] = data.skill or "",
            }
        end
        content = IniParser.Serialize(sections)
        SaveConfigToCloud("系统配置/pet_types.ini", content, function(ok)
            ShowMsg(ok and "宠物种类配置已保存到云端" or "保存失败")
        end)
    elseif category == "battle_soul" then
        local sections = {}
        -- 升级公式
        local formula = DataManager.battleSoulConfig.level_formula
        sections["升级公式"] = {
            ["基础值"] = formula.base or "100",
            ["成长值"] = formula.growth or "50",
            ["幂次"] = formula.power or "1.5",
        }
        -- 每级属性加成
        local bonus = DataManager.battleSoulConfig.level_bonus
        sections["每级属性加成"] = {
            ["攻击力"] = bonus.atk or "5",
            ["防御力"] = bonus.def or "3",
            ["生命上限"] = bonus.max_hp or "20",
        }
        -- 怪物战魂
        local monsterSoul = {}
        for typeName, range in pairs(DataManager.battleSoulConfig.monster_soul) do
            monsterSoul[typeName] = range.min .. "-" .. range.max
        end
        sections["怪物战魂"] = monsterSoul
        content = IniParser.Serialize(sections)
        SaveConfigToCloud("系统配置/battle_soul.ini", content, function(ok)
            ShowMsg(ok and "战魂配置已保存到云端" or "保存失败")
        end)
    elseif category == "leaderboards" then
        local sections = {}
        for id, data in pairs(DataManager.leaderboards) do
            sections[id] = {
                ["名称"] = data.name or id,
                ["云端键名"] = data.key or ("rank_" .. id),
                ["数据来源"] = data.source or "等级",
                ["排序"] = data.order or "desc",
                ["显示人数"] = tostring(data.top_count or 10),
            }
        end
        content = IniParser.Serialize(sections)
        SaveConfigToCloud("系统配置/leaderboards.ini", content, function(ok)
            ShowMsg(ok and "排行榜配置已保存到云端" or "保存失败")
            if onDoneExtra then onDoneExtra(ok) end
        end)
    elseif category == "teleport_maps" then
        local tc = DataManager.teleportMaps
        local sections = {}
        -- 全局配置
        sections["_config"] = {
            ["默认物品"] = tc.default_item or "",
            ["默认物品数量"] = tc.default_item_count or "1",
        }
        for i, data in ipairs(tc.maps) do
            sections["tp_" .. i] = {
                ["名称"] = data.name or "",
                ["等级要求"] = data.level_req or "0",
                ["自定义物品"] = data.custom_item or "",
                ["自定义物品数量"] = data.custom_item_count or "1",
                ["免费"] = data.free and "true" or "false",
            }
        end
        content = IniParser.Serialize(sections)
        SaveConfigToCloud("系统配置/teleport_maps.ini", content, function(ok)
            ShowMsg(ok and "传送地图配置已保存到云端" or "保存失败")
            if onDoneExtra then onDoneExtra(ok) end
        end)
    end
end

--- 从云端加载管理员列表
local function LoadAdminsFromCloud(onDone)
    local cloud = DataManager.GetCloudProvider()
    if not cloud then
        if onDone then onDone() end
        return
    end
    local adminKey = "系统配置/admins.txt"
    cloud:Get(adminKey, {
        ok = function(values)
            DataManager.admins = {}
            -- CloudProxy 返回 { [key] = value } 表; clientCloud 可能返回 string
            local str = ""
            if type(values) == "string" then
                str = values
            elseif type(values) == "table" then
                str = values[adminKey] or values.value or values[1] or ""
            end
            if type(str) ~= "string" then str = tostring(str or "") end
            if str ~= "" then
                for username in string.gmatch(str, "([^,]+)") do
                    local trimmed = username:match("^%s*(.-)%s*$")
                    if trimmed ~= "" then
                        DataManager.admins[trimmed] = true
                    end
                end
            end
            print("[Admin] 管理员列表已加载: " .. tostring(str))
            if onDone then onDone() end
        end,
        error = function()
            DataManager.admins = {}
            if onDone then onDone() end
        end,
    })
end

--- 判断是否为总管理员
---@param username string
---@return boolean
local function IsSuperAdmin(username)
    return username == SUPER_ADMIN
end

--- 判断是否有管理员权限（总管理员或被授权的管理员）
---@param username string
---@return boolean
local function IsAdmin(username)
    return username == SUPER_ADMIN or DataManager.admins[username] == true
end

-- =============== 分类内容渲染 ===============

--- 清空内容面板
local function ClearContent()
    if not contentPanel_ then return end
    local children = contentPanel_:GetChildren()
    if children then
        for i = #children, 1, -1 do
            contentPanel_:RemoveChild(children[i])
        end
    end
end

--- 创建搜索栏并添加到内容面板
---@param placeholder string 搜索框提示文字
---@param onSearch fun() 搜索触发时回调（重新渲染当前分类）
---@return Widget searchBar
local function CreateSearchBar(placeholder, onSearch)
    local searchField = UI.TextField {
        value = searchKeyword_,
        placeholder = placeholder or "搜索...",
        width = 200, height = 28, fontSize = 12,
    }
    local bar = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12, paddingRight = 12, paddingTop = 6, paddingBottom = 6,
        gap = 8,
        children = {
            UI.Label { text = "搜索:", fontSize = 12, fontColor = { 180, 180, 200, 255 } },
            searchField,
            UI.Button {
                text = "查找", variant = "secondary", width = 50, height = 28, fontSize = 11,
                onClick = function()
                    searchKeyword_ = searchField:GetValue() or ""
                    onSearch()
                end,
            },
            UI.Button {
                text = "清除", variant = "secondary", width = 50, height = 28, fontSize = 11,
                onClick = function()
                    searchKeyword_ = ""
                    onSearch()
                end,
            },
        },
    }
    return bar
end

--- 检查名称是否匹配搜索关键词
---@param name string
---@return boolean
local function MatchSearch(name)
    if searchKeyword_ == "" then return true end
    if not name then return false end
    return string.find(string.lower(name), string.lower(searchKeyword_), 1, true) ~= nil
end

--- 创建列表项行
---@param text string
---@param subtext string
---@param onEdit fun()
---@param index number
local function CreateListRow(text, subtext, onEdit, index, onDelete)
    local bgColor = (index % 2 == 0) and { 25, 20, 45, 200 } or { 20, 15, 35, 200 }
    local buttons = {
        UI.Button {
            text = "编辑",
            fontSize = 11,
            width = 50,
            height = 26,
            variant = "secondary",
            onClick = onEdit,
        },
    }
    if onDelete then
        table.insert(buttons, UI.Button {
            text = "删除",
            fontSize = 11,
            width = 50,
            height = 26,
            variant = "danger",
            onClick = onDelete,
        })
    end
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12,
        paddingRight = 12,
        paddingTop = 6,
        paddingBottom = 6,
        backgroundColor = bgColor,
        children = {
            UI.Panel {
                flexDirection = "column",
                flexGrow = 1,
                flexShrink = 1,
                children = {
                    UI.Label {
                        text = text,
                        fontSize = 13,
                        fontColor = { 220, 220, 240, 255 },
                    },
                    UI.Label {
                        text = subtext,
                        fontSize = 11,
                        fontColor = { 140, 140, 160, 255 },
                    },
                },
            },
            UI.Panel {
                flexDirection = "row",
                gap = 4,
                children = buttons,
            },
        },
    }
end

--- 虚拟列表行高度常量
local VLIST_ITEM_HEIGHT = 52
local VLIST_ITEM_GAP = 2

--- 创建虚拟数据列表（替代逐条 AddChild 的方式，性能恒定）
--- @param dataArray table[] 每项 {text=string, subtext=string, onEdit=fun(), onDelete=fun()|nil}
--- @return Widget virtualListContainer
local function CreateVirtualDataList(dataArray)
    local container = UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        overflow = "hidden",
        marginTop = 4,
    }

    if #dataArray == 0 then
        container:AddChild(UI.Label {
            text = "（无数据）",
            fontSize = 12,
            fontColor = { 140, 140, 160, 255 },
            textAlign = "center",
            marginTop = 20,
        })
        return container
    end

    local vList = UI.VirtualList {
        width = "100%",
        height = "100%",
        viewportHeight = (UI.GetHeight and UI.GetHeight() or 500) - 80,
        data = dataArray,
        itemHeight = VLIST_ITEM_HEIGHT,
        itemGap = VLIST_ITEM_GAP,
        poolBuffer = 5,
        createItem = function()
            local row = UI.Panel {
                width = "100%",
                height = VLIST_ITEM_HEIGHT,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 12,
                paddingRight = 12,
                paddingTop = 4,
                paddingBottom = 4,
                backgroundColor = { 20, 15, 35, 200 },
            }
            local infoCol = UI.Panel {
                flexDirection = "column",
                flexGrow = 1,
                flexShrink = 1,
            }
            local titleLabel = UI.Label {
                id = "title",
                text = "",
                fontSize = 13,
                fontColor = { 220, 220, 240, 255 },
                maxLines = 1,
            }
            local subLabel = UI.Label {
                id = "sub",
                text = "",
                fontSize = 11,
                fontColor = { 140, 140, 160, 255 },
                maxLines = 1,
            }
            infoCol:AddChild(titleLabel)
            infoCol:AddChild(subLabel)
            row:AddChild(infoCol)

            local btnPanel = UI.Panel {
                flexDirection = "row",
                gap = 4,
            }
            local editBtn = UI.Button {
                id = "editBtn",
                text = "编辑",
                fontSize = 11,
                width = 50,
                height = 26,
                variant = "secondary",
            }
            local delBtn = UI.Button {
                id = "delBtn",
                text = "删除",
                fontSize = 11,
                width = 50,
                height = 26,
                variant = "danger",
            }
            btnPanel:AddChild(editBtn)
            btnPanel:AddChild(delBtn)
            row:AddChild(btnPanel)

            row._titleLabel = titleLabel
            row._subLabel = subLabel
            row._editBtn = editBtn
            row._delBtn = delBtn
            row._btnPanel = btnPanel
            return row
        end,
        bindItem = function(widget, data, index)
            widget._titleLabel:SetText(data.text or "")
            widget._subLabel:SetText(data.subtext or "")
            widget.props.backgroundColor = (index % 2 == 0) and { 25, 20, 45, 200 } or { 20, 15, 35, 200 }
            -- 绑定按钮回调
            widget._editBtn.props.onClick = data.onEdit
            if data.onDelete then
                widget._delBtn:SetVisible(true)
                widget._delBtn.props.onClick = data.onDelete
            else
                widget._delBtn:SetVisible(false)
            end
        end,
    }
    container:AddChild(vList)
    return container
end

--- 通用编辑弹窗
---@param title string
---@param fields table[] { {label, key, value, opts} }
---@param onSave fun(values: table)
local function ShowEditDialog(title, fields, onSave)
    CloseDialog()

    local fieldWidgets = {}
    local formChildren = {}

    table.insert(formChildren, UI.Label {
        text = title,
        fontSize = 16,
        fontColor = { 255, 200, 100, 255 },
        textAlign = "center",
        marginBottom = 8,
    })

    for _, f in ipairs(fields) do
        if f.type == "action" then
            -- 动作按钮类型：渲染可点击按钮（不参与表单数据收集）
            table.insert(formChildren, UI.Panel {
                flexDirection = "row",
                gap = 8,
                marginTop = 4,
                marginBottom = 4,
                children = f.buttons or {
                    UI.Button {
                        text = f.label,
                        variant = f.variant or "secondary",
                        width = f.width or 120,
                        onClick = f.onClick,
                    },
                },
            })
        elseif f.type == "selector" and f.opts and f.opts.options then
            -- 选择器类型：使用按钮选择组件
            local selectorPanel, getSelected = CreateButtonSelector(f.opts.options, f.value or f.opts.options[1], f.label, false)
            -- 包装成与 TextField 兼容的接口（有 GetValue 方法）
            fieldWidgets[f.key] = { GetValue = getSelected }
            table.insert(formChildren, selectorPanel)
        else
            local panel, field = CreateFormField(f.label, f.value, f.opts)
            fieldWidgets[f.key] = field
            table.insert(formChildren, panel)
        end
    end

    local dialogMsg = UI.Label {
        text = "",
        fontSize = 11,
        fontColor = { 100, 255, 100, 255 },
        textAlign = "center",
        height = 16,
    }
    table.insert(formChildren, dialogMsg)

    table.insert(formChildren, UI.Panel {
        flexDirection = "row",
        gap = 12,
        marginTop = 8,
        justifyContent = "center",
        children = {
            UI.Button {
                text = "保存",
                variant = "primary",
                width = 80,
                onClick = function()
                    local values = {}
                    for key, widget in pairs(fieldWidgets) do
                        values[key] = widget:GetValue() or ""
                    end
                    onSave(values)
                    dialogMsg:SetText("已保存")
                end,
            },
            UI.Button {
                text = "关闭",
                variant = "secondary",
                width = 80,
                onClick = function()
                    CloseDialog()
                end,
            },
        },
    })

    editDialog_ = UI.Panel {
        width = "100%",
        height = "100%",
        position = "absolute",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        children = {
            UI.ScrollView {
                width = 380,
                maxHeight = 500,
                backgroundColor = { 30, 25, 55, 250 },
                borderRadius = 12,
                padding = 16,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "column",
                        gap = 4,
                        children = formChildren,
                    },
                },
            },
        },
    }

    -- 暴露 fieldWidgets 供动态按钮读取当前值
    editDialog_._fieldWidgets = fieldWidgets

    if rootPanel_ then
        rootPanel_:AddChild(editDialog_)
    end
end

-- =============== 玩家管理 ===============

-- 前向声明
local RenderPlayers
local RenderItems
local RenderShops
local RenderSystemShops

--- 显示玩家详细数据弹窗（查看+修改）
---@param username string
---@param accountInfo table {username, password, charName}
---@param editMode boolean 是否可编辑
local function ShowPlayerDetailDialog(username, accountInfo, editMode)
    CloseDialog()
    ShowMsg("正在加载 " .. username .. " 的数据...")

    DataManager.LoadPlayerDataForAdmin(username, function(playerData)
        if not playerData then
            -- 无游戏数据，只显示账号信息
            playerData = {
                account = { username = username, password = accountInfo.password, char_name = accountInfo.charName },
                status = {},
                bag = {},
                equip = { weapon = "", armor = "", accessory = "" },
                quests = { active = {}, completed = {} },
            }
        end
        playerData.account.username = username
        playerData.account.password = accountInfo.password
        playerData.account.char_name = accountInfo.charName

        ShowMsg("已加载 " .. username .. " 的数据")

        -- 构建表单字段
        local fieldWidgets = {}
        local formChildren = {}

        local title = editMode and ("修改玩家 - " .. username) or ("查看玩家 - " .. username)
        table.insert(formChildren, UI.Label {
            text = title,
            fontSize = 16,
            fontColor = { 255, 200, 100, 255 },
            textAlign = "center",
            marginBottom = 8,
        })

        -- === 账号信息 ===
        table.insert(formChildren, UI.Label {
            text = "【账号信息】",
            fontSize = 13,
            fontColor = { 100, 200, 255, 255 },
            marginTop = 6,
            marginBottom = 2,
        })
        local accFields = {
            { label = "账号", key = "acc_username", value = username },
            { label = "密码", key = "acc_password", value = accountInfo.password },
            { label = "角色名", key = "acc_charName", value = accountInfo.charName },
        }
        for _, f in ipairs(accFields) do
            local panel, field = CreateFormField(f.label, f.value, { width = 180 })
            if not editMode then
                field:SetDisabled(true)
            end
            -- 账号名不可修改
            if f.key == "acc_username" then
                field:SetDisabled(true)
            end
            fieldWidgets[f.key] = field
            table.insert(formChildren, panel)
        end

        -- === 状态数据 ===
        table.insert(formChildren, UI.Label {
            text = "【状态数据】",
            fontSize = 13,
            fontColor = { 100, 200, 255, 255 },
            marginTop = 6,
            marginBottom = 2,
        })
        local st = playerData.status or {}
        local statusFields = {
            { label = "姓名", key = "st_name", value = st.name or "" },
            { label = "等级", key = "st_level", value = st.level or "1", showUnit = true },
            { label = "经验", key = "st_exp", value = st.exp or "0", showUnit = true },
            { label = "生命值", key = "st_hp", value = st.hp or "100", showUnit = true },
            { label = "最大生命", key = "st_max_hp", value = st.max_hp or "100", showUnit = true },
            { label = "法力值", key = "st_mp", value = st.mp or "50", showUnit = true },
            { label = "最大法力", key = "st_max_mp", value = st.max_mp or "50", showUnit = true },
            { label = "攻击力", key = "st_atk", value = st.atk or "5", showUnit = true },
            { label = "防御力", key = "st_def", value = st.def or "3", showUnit = true },
            { label = "金币", key = "st_gold", value = st.gold or "50", showUnit = true },
            { label = "当前地图", key = "st_current_map", value = st.current_map or "新手村" },
            { label = "战魂等级", key = "st_battle_soul_level", value = st.battle_soul_level or "0", showUnit = true },
            { label = "战魂经验", key = "st_battle_soul_exp", value = st.battle_soul_exp or "0", showUnit = true },
        }
        for _, f in ipairs(statusFields) do
            local panel, field = CreateFormField(f.label, f.value, { width = 150, showUnit = f.showUnit })
            if not editMode then field:SetDisabled(true) end
            fieldWidgets[f.key] = field
            table.insert(formChildren, panel)
        end

        -- === 自定义货币 ===
        local currencyList = DataManager.GetCurrencyList()
        local stCurrencies = st.currencies or {}
        -- 过滤掉"金币"（已在基础属性中展示）
        local customCurrencies = {}
        for _, cName in ipairs(currencyList) do
            if cName ~= "金币" then
                table.insert(customCurrencies, cName)
            end
        end
        if #customCurrencies > 0 then
            table.insert(formChildren, UI.Label {
                text = "【自定义货币】",
                fontSize = 13,
                fontColor = { 100, 200, 255, 255 },
                marginTop = 6,
                marginBottom = 2,
            })
            for _, cName in ipairs(customCurrencies) do
                local cValue = tostring(stCurrencies[cName] or "0")
                local panel, field = CreateFormField(cName, cValue, { width = 150, showUnit = true })
                if not editMode then field:SetDisabled(true) end
                fieldWidgets["currency_" .. cName] = field
                table.insert(formChildren, panel)
            end
        end

        -- === 背包数据 ===
        table.insert(formChildren, UI.Label {
            text = "【背包数据】",
            fontSize = 13,
            fontColor = { 100, 200, 255, 255 },
            marginTop = 6,
            marginBottom = 2,
        })
        local bagStr = ""
        for i, item in ipairs(playerData.bag or {}) do
            if i > 1 then bagStr = bagStr .. "," end
            bagStr = bagStr .. item.name .. ":" .. item.count
        end
        if bagStr == "" then bagStr = "(空)" end
        local bagPanel, bagField = CreateFormField("物品", bagStr, { width = 250, placeholder = "物品:数量,物品:数量" })
        if not editMode then bagField:SetDisabled(true) end
        fieldWidgets["bag_items"] = bagField
        table.insert(formChildren, bagPanel)

        -- === 装备数据 ===
        table.insert(formChildren, UI.Label {
            text = "【装备数据】",
            fontSize = 13,
            fontColor = { 100, 200, 255, 255 },
            marginTop = 6,
            marginBottom = 2,
        })
        local eq = playerData.equip or {}
        -- 装备栏字段动态生成(从 EquipSlots 共享模块读取,管理员可自定义部位)
        local equipFields = {}
        for _, slot in ipairs(EquipSlots.slots) do
            equipFields[#equipFields + 1] = { label = slot.label, key = "eq_" .. slot.key, value = eq[slot.key] or "" }
        end
        for _, f in ipairs(equipFields) do
            local panel, field = CreateFormField(f.label, f.value, { width = 150 })
            if not editMode then field:SetDisabled(true) end
            fieldWidgets[f.key] = field
            table.insert(formChildren, panel)
        end

        -- === 任务数据 ===
        table.insert(formChildren, UI.Label {
            text = "【任务数据】",
            fontSize = 13,
            fontColor = { 100, 200, 255, 255 },
            marginTop = 6,
            marginBottom = 2,
        })
        local quests = playerData.quests or { active = {}, completed = {} }
        local activeStr = ""
        for i, q in ipairs(quests.active or {}) do
            if i > 1 then activeStr = activeStr .. "," end
            activeStr = activeStr .. q.id .. ":" .. q.progress
        end
        if activeStr == "" then activeStr = "(无)" end
        local activePanel, activeField = CreateFormField("进行中", activeStr, { width = 250, placeholder = "任务ID:进度,..." })
        if not editMode then activeField:SetDisabled(true) end
        fieldWidgets["quest_active"] = activeField
        table.insert(formChildren, activePanel)

        local completedStr = table.concat(quests.completed or {}, ",")
        if completedStr == "" then completedStr = "(无)" end
        local completedPanel, completedField = CreateFormField("已完成", completedStr, { width = 250, placeholder = "任务ID,任务ID,..." })
        if not editMode then completedField:SetDisabled(true) end
        fieldWidgets["quest_completed"] = completedField
        table.insert(formChildren, completedPanel)

        -- === 礼包使用记录 ===
        table.insert(formChildren, UI.Label {
            text = "【礼包使用记录】",
            fontSize = 13,
            fontColor = { 100, 200, 255, 255 },
            marginTop = 6,
            marginBottom = 2,
        })
        local redeemedCodes = playerData.redeemed_codes or {}
        local redeemedStr = table.concat(redeemedCodes, ",")
        if redeemedStr == "" then redeemedStr = "(无)" end
        local redeemedPanel, redeemedField = CreateFormField("已兑换", redeemedStr, { width = 250, placeholder = "兑换码1,兑换码2,..." })
        if not editMode then redeemedField:SetDisabled(true) end
        fieldWidgets["redeemed_codes"] = redeemedField
        table.insert(formChildren, redeemedPanel)

        -- 弹窗消息
        local dialogMsg = UI.Label {
            text = "",
            fontSize = 11,
            fontColor = { 100, 255, 100, 255 },
            textAlign = "center",
            height = 16,
            marginTop = 4,
        }
        table.insert(formChildren, dialogMsg)

        -- 按钮
        local btnChildren = {}
        if editMode then
            table.insert(btnChildren, UI.Button {
                text = "保存全部",
                variant = "primary",
                width = 90,
                onClick = function()
                    dialogMsg:SetText("保存中...")
                    -- 收集数据
                    local newAccPassword = fieldWidgets["acc_password"]:GetValue() or ""
                    local newAccCharName = fieldWidgets["acc_charName"]:GetValue() or ""

                    -- 构建新的 playerData（基于原始数据合并，避免丢失不在表单中的字段）
                    local newPlayerData = {}
                    for k, v in pairs(playerData) do
                        if type(v) == "table" then
                            -- 浅拷贝一层
                            newPlayerData[k] = {}
                            for kk, vv in pairs(v) do
                                newPlayerData[k][kk] = vv
                            end
                        else
                            newPlayerData[k] = v
                        end
                    end

                    -- 覆盖表单中可编辑的字段
                    newPlayerData.account = {
                        username = username,
                        password = newAccPassword,
                        char_name = newAccCharName,
                    }
                    newPlayerData.status = newPlayerData.status or {}
                    newPlayerData.status.name = fieldWidgets["st_name"]:GetValue() or ""
                    newPlayerData.status.level = fieldWidgets["st_level"]:GetValue() or "1"
                    newPlayerData.status.exp = fieldWidgets["st_exp"]:GetValue() or "0"
                    newPlayerData.status.hp = fieldWidgets["st_hp"]:GetValue() or "100"
                    newPlayerData.status.max_hp = fieldWidgets["st_max_hp"]:GetValue() or "100"
                    newPlayerData.status.mp = fieldWidgets["st_mp"]:GetValue() or "50"
                    newPlayerData.status.max_mp = fieldWidgets["st_max_mp"]:GetValue() or "50"
                    newPlayerData.status.atk = fieldWidgets["st_atk"]:GetValue() or "5"
                    newPlayerData.status.def = fieldWidgets["st_def"]:GetValue() or "3"
                    newPlayerData.status.gold = fieldWidgets["st_gold"]:GetValue() or "50"
                    newPlayerData.status.current_map = fieldWidgets["st_current_map"]:GetValue() or "新手村"
                    newPlayerData.status.battle_soul_level = fieldWidgets["st_battle_soul_level"]:GetValue() or "0"
                    newPlayerData.status.battle_soul_exp = fieldWidgets["st_battle_soul_exp"]:GetValue() or "0"
                    newPlayerData.status.currencies = {}

                    newPlayerData.bag = {}
                    newPlayerData.equip = (function()
                        local eq = {}
                        for _, slot in ipairs(EquipSlots.slots) do
                            local w = fieldWidgets["eq_" .. slot.key]
                            eq[slot.key] = w and w:GetValue() or ""
                        end
                        return eq
                    end)()
                    newPlayerData.quests = { active = {}, completed = {} }
                    newPlayerData.redeemed_codes = {}

                    -- 收集自定义货币数据
                    for _, cName in ipairs(customCurrencies) do
                        local w = fieldWidgets["currency_" .. cName]
                        if w then
                            newPlayerData.status.currencies[cName] = w:GetValue() or "0"
                        end
                    end

                    -- 解析礼包使用记录
                    local redeemedVal = fieldWidgets["redeemed_codes"]:GetValue() or ""
                    if redeemedVal ~= "(无)" and redeemedVal ~= "" then
                        for code in redeemedVal:gmatch("[^,]+") do
                            local trimmed = code:match("^%s*(.-)%s*$")
                            if trimmed and trimmed ~= "" then
                                table.insert(newPlayerData.redeemed_codes, trimmed)
                            end
                        end
                    end

                    -- 解析背包
                    local bagVal = fieldWidgets["bag_items"]:GetValue() or ""
                    if bagVal ~= "(空)" and bagVal ~= "" then
                        for entry in bagVal:gmatch("[^,]+") do
                            local name, cnt = entry:match("^(.+):(%d+)$")
                            if name then
                                table.insert(newPlayerData.bag, { name = name, count = cnt or "1" })
                            end
                        end
                    end

                    -- 解析进行中任务
                    local activeVal = fieldWidgets["quest_active"]:GetValue() or ""
                    if activeVal ~= "(无)" and activeVal ~= "" then
                        for entry in activeVal:gmatch("[^,]+") do
                            local id, progress = entry:match("^(.+):(%d+)$")
                            if id then
                                table.insert(newPlayerData.quests.active, { id = id, progress = progress or "0" })
                            end
                        end
                    end

                    -- 解析已完成任务
                    local completedVal = fieldWidgets["quest_completed"]:GetValue() or ""
                    if completedVal ~= "(无)" and completedVal ~= "" then
                        for qid in completedVal:gmatch("[^,]+") do
                            local trimmed = qid:match("^%s*(.-)%s*$")
                            if trimmed and trimmed ~= "" then
                                table.insert(newPlayerData.quests.completed, trimmed)
                            end
                        end
                    end

                    -- 先保存账号信息
                    DataManager.UpdateAccountInfo(username, {
                        password = newAccPassword,
                        charName = newAccCharName,
                    }, function(accOk)
                        -- 再保存游戏数据
                        DataManager.SavePlayerDataForAdmin(username, newPlayerData, function(dataOk)
                            if accOk and dataOk then
                                dialogMsg:SetText("全部保存成功!")
                            elseif accOk then
                                dialogMsg:SetText("账号已保存，游戏数据保存失败")
                            elseif dataOk then
                                dialogMsg:SetText("游戏数据已保存，账号保存失败")
                            else
                                dialogMsg:SetText("保存失败")
                            end
                        end)
                    end)
                end,
            })
        end
        table.insert(btnChildren, UI.Button {
            text = "刷新排行",
            variant = "secondary",
            width = 80,
            onClick = function()
                dialogMsg:SetText("正在刷新排行榜...")
                DataManager.RefreshPlayerRankingForAdmin(username, function(ok, msg)
                    dialogMsg:SetText(ok and msg or ("失败: " .. msg))
                end)
            end,
        })
        table.insert(btnChildren, UI.Button {
            text = "关闭",
            variant = "secondary",
            width = 80,
            onClick = function()
                CloseDialog()
                RenderPlayers()
            end,
        })

        table.insert(formChildren, UI.Panel {
            flexDirection = "row",
            gap = 12,
            marginTop = 8,
            justifyContent = "center",
            children = btnChildren,
        })

        -- 创建弹窗
        editDialog_ = UI.Panel {
            width = "100%",
            height = "100%",
            position = "absolute",
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = { 0, 0, 0, 180 },
            children = {
                UI.ScrollView {
                    width = 400,
                    maxHeight = 550,
                    backgroundColor = { 30, 25, 55, 250 },
                    borderRadius = 12,
                    padding = 16,
                    children = {
                        UI.Panel {
                            width = "100%",
                            flexDirection = "column",
                            gap = 3,
                            children = formChildren,
                        },
                    },
                },
            },
        }

        if rootPanel_ then
            rootPanel_:AddChild(editDialog_)
        end
    end)
end

--- 显示删除确认弹窗
---@param username string
local function ShowDeleteConfirmDialog(username)
    CloseDialog()

    local dialogMsg = UI.Label {
        text = "",
        fontSize = 11,
        fontColor = { 255, 100, 100, 255 },
        textAlign = "center",
        height = 16,
    }

    editDialog_ = UI.Panel {
        width = "100%",
        height = "100%",
        position = "absolute",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        children = {
            UI.Panel {
                width = 320,
                backgroundColor = { 40, 20, 20, 250 },
                borderRadius = 12,
                padding = 20,
                flexDirection = "column",
                alignItems = "center",
                gap = 12,
                children = {
                    UI.Label {
                        text = "确认删除玩家",
                        fontSize = 16,
                        fontColor = { 255, 100, 100, 255 },
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "即将删除玩家: " .. username,
                        fontSize = 13,
                        fontColor = { 220, 220, 240, 255 },
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "此操作将删除该玩家的账号信息和所有游戏数据，不可恢复！",
                        fontSize = 11,
                        fontColor = { 255, 180, 100, 255 },
                        textAlign = "center",
                    },
                    dialogMsg,
                    UI.Panel {
                        flexDirection = "row",
                        gap = 16,
                        marginTop = 8,
                        children = {
                            UI.Button {
                                text = "确认删除",
                                variant = "primary",
                                width = 100,
                                backgroundColor = { 180, 40, 40, 255 },
                                onClick = function()
                                    dialogMsg:SetText("删除中...")
                                    DataManager.DeletePlayer(username, function(ok)
                                        if ok then
                                            dialogMsg:SetText("已删除!")
                                            CloseDialog()
                                            RenderPlayers()
                                        else
                                            dialogMsg:SetText("删除失败")
                                        end
                                    end)
                                end,
                            },
                            UI.Button {
                                text = "取消",
                                variant = "secondary",
                                width = 80,
                                onClick = function()
                                    CloseDialog()
                                end,
                            },
                        },
                    },
                },
            },
        },
    }

    if rootPanel_ then
        rootPanel_:AddChild(editDialog_)
    end
end

RenderPlayers = function()
    ClearContent()
    contentPanel_:AddChild(CreateSearchBar("搜索玩家名...", function() RenderPlayers() end))
    ShowMsg("正在加载玩家列表...")
    LoadAdminsFromCloud(function()
    DataManager.GetAllPlayers(function(players)
        if #players == 0 then
            ShowMsg("暂无注册玩家")
            return
        end
        local filtered = {}
        for _, info in ipairs(players) do
            if MatchSearch(info.username) or MatchSearch(info.charName) then
                table.insert(filtered, info)
            end
        end
        ShowMsg("共 " .. #players .. " 个玩家" .. (searchKeyword_ ~= "" and ("，匹配 " .. #filtered .. " 个") or ""))

        -- 批量刷新排行榜按钮
        local refreshRankMsg = UI.Label {
            text = "",
            fontSize = 11,
            fontColor = { 100, 255, 100, 255 },
            marginLeft = 8,
        }
        contentPanel_:AddChild(UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            marginBottom = 4,
            paddingLeft = 4,
            children = {
                UI.Button {
                    text = "批量刷新排行榜",
                    fontSize = 10,
                    width = 110,
                    height = 26,
                    variant = "primary",
                    onClick = function()
                        refreshRankMsg:SetText("正在刷新所有玩家排行...")
                        DataManager.RefreshAllPlayersRankingForAdmin(function(ok, msg)
                            refreshRankMsg:SetText(ok and msg or ("失败: " .. msg))
                        end)
                    end,
                },
                refreshRankMsg,
            },
        })

        for i, info in ipairs(filtered) do
            local bgColor = (i % 2 == 0) and { 25, 20, 45, 200 } or { 20, 15, 35, 200 }
            local isPlayerAdmin = IsAdmin(info.username)
            local adminTag = ""
            if info.username == SUPER_ADMIN then
                adminTag = " [总管理员]"
            elseif isPlayerAdmin then
                adminTag = " [管理员]"
            end
            local rowChildren = {
                UI.Panel {
                    flexDirection = "column",
                    flexGrow = 1,
                    flexShrink = 1,
                    children = {
                        UI.Label {
                            text = info.username .. adminTag,
                            fontSize = 13,
                            fontColor = isPlayerAdmin and { 255, 200, 80, 255 } or { 220, 220, 240, 255 },
                        },
                        UI.Label {
                            text = "密码: " .. info.password .. "  角色: " .. (info.charName or ""),
                            fontSize = 11,
                            fontColor = { 140, 140, 160, 255 },
                        },
                    },
                },
                UI.Button {
                    text = "查看",
                    fontSize = 10,
                    width = 42,
                    height = 24,
                    variant = "secondary",
                    onClick = function()
                        ShowPlayerDetailDialog(info.username, info, false)
                    end,
                },
                UI.Button {
                    text = "修改",
                    fontSize = 10,
                    width = 42,
                    height = 24,
                    marginLeft = 4,
                    variant = "secondary",
                    onClick = function()
                        ShowPlayerDetailDialog(info.username, info, true)
                    end,
                },
                UI.Button {
                    text = "删除",
                    fontSize = 10,
                    width = 42,
                    height = 24,
                    marginLeft = 4,
                    variant = "secondary",
                    onClick = function()
                        ShowDeleteConfirmDialog(info.username)
                    end,
                },
            }
            -- 总管理员可以设置/取消其他玩家为管理员（不能操作自己和总管理员）
            if IsSuperAdmin(currentAdminUser_) and info.username ~= SUPER_ADMIN then
                local btnText = isPlayerAdmin and "取消管理员" or "设为管理员"
                local btnVariant = isPlayerAdmin and "secondary" or "primary"
                table.insert(rowChildren, UI.Button {
                    text = btnText,
                    fontSize = 9,
                    width = 62,
                    height = 24,
                    marginLeft = 4,
                    variant = btnVariant,
                    onClick = function()
                        if isPlayerAdmin then
                            DataManager.admins[info.username] = nil
                        else
                            DataManager.admins[info.username] = true
                        end
                        SaveCategoryToCloud("admins")
                        RenderPlayers()
                    end,
                })
            end
            local row = UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 12,
                paddingRight = 12,
                paddingTop = 6,
                paddingBottom = 6,
                backgroundColor = bgColor,
                children = rowChildren,
            }
            contentPanel_:AddChild(row)
        end
    end)
    end) -- LoadAdminsFromCloud
end

-- =============== 游戏设置管理 ===============

local function RenderGameConfig()
    ClearContent()
    ShowMsg("游戏全局设置（含玩家初始属性、升级公式）")

    local gc = DataManager.gameConfig
    local gameSec = gc["game"] or {}
    local defSec = gc["player_default"] or {}
    local lvlSec = gc["level_up"] or {}

    -- 游戏设置行
    contentPanel_:AddChild(CreateListRow("游戏设置",
        "标题:" .. (gameSec.title or "") .. " 起始地图:" .. (gameSec.start_map or ""),
        function()
            ShowEditDialog("游戏设置", {
                { label = "标题", key = "title", value = gameSec.title },
                { label = "版本", key = "version", value = gameSec.version },
                { label = "起始地图", key = "start_map", value = gameSec.start_map },
                { label = "起始任务", key = "start_quest", value = gameSec.start_quest },
            }, function(v)
                gc["game"] = { title = v.title, version = v.version, start_map = v.start_map, start_quest = v.start_quest }
                SaveCategoryToCloud("game_config")
            end)
        end, 1))

    -- 玩家默认属性
    contentPanel_:AddChild(CreateListRow("玩家初始属性",
        "生命:" .. (defSec.hp or 100) .. " 法力:" .. (defSec.mp or 50) .. " 攻击:" .. (defSec.atk or 5) .. " 防御:" .. (defSec.def or 3),
        function()
            ShowEditDialog("玩家初始属性", {
                { label = "生命值", key = "hp", value = defSec.hp },
                { label = "法力值", key = "mp", value = defSec.mp },
                { label = "攻击力", key = "atk", value = defSec.atk },
                { label = "防御力", key = "def", value = defSec.def },
                { label = "等级", key = "level", value = defSec.level },
                { label = "金币", key = "gold", value = defSec.gold },
            }, function(v)
                gc["player_default"] = {
                    hp = v.hp or "100", mp = v.mp or "50",
                    atk = v.atk or "5", def = v.def or "3",
                    level = v.level or "1", exp = "0",
                    gold = v.gold or "50",
                }
                SaveCategoryToCloud("game_config")
            end)
        end, 2))

    -- 升级公式
    contentPanel_:AddChild(CreateListRow("升级公式",
        "最高等级:" .. (lvlSec.max_level or 100) .. " 基础经验:" .. (lvlSec.base_exp or 20) .. " 系数:" .. (lvlSec.exp_factor or 2),
        function()
            ShowEditDialog("升级公式", {
                { label = "最高等级", key = "max_level", value = lvlSec.max_level or "100" },
                { label = "基础经验", key = "base_exp", value = lvlSec.base_exp },
                { label = "经验系数", key = "exp_factor", value = lvlSec.exp_factor },
                { label = "每级生命", key = "hp_per_level", value = lvlSec.hp_per_level },
                { label = "每级法力", key = "mp_per_level", value = lvlSec.mp_per_level },
                { label = "每级攻击", key = "atk_per_level", value = lvlSec.atk_per_level },
                { label = "每级防御", key = "def_per_level", value = lvlSec.def_per_level },
            }, function(v)
                gc["level_up"] = {
                    max_level = v.max_level or "100",
                    base_exp = v.base_exp or "20", exp_factor = tonumber(v.exp_factor) or 2,
                    hp_per_level = v.hp_per_level or "20", mp_per_level = v.mp_per_level or "10",
                    atk_per_level = v.atk_per_level or "3", def_per_level = v.def_per_level or "2",
                }
                SaveCategoryToCloud("game_config")
            end)
        end, 3))

    -- 货币管理
    local currList = gc["currencies"] or { "金币" }
    local currSummary = table.concat(currList, ", ")
    contentPanel_:AddChild(CreateListRow("货币管理",
        "当前货币: " .. currSummary,
        function()
            -- 打开货币编辑对话框
            CloseDialog()
            local formChildren = {}
            table.insert(formChildren, UI.Label {
                text = "货币管理",
                fontSize = 16,
                fontColor = { 200, 170, 100, 255 },
                textAlign = "center",
                marginBottom = 8,
            })
            table.insert(formChildren, UI.Label {
                text = "添加或删除游戏中使用的货币类型",
                fontSize = 11,
                fontColor = { 140, 140, 160, 255 },
                textAlign = "center",
                marginBottom = 8,
            })

            local editCurrencies = {}
            for _, c in ipairs(currList) do
                table.insert(editCurrencies, c)
            end

            local listPanel = UI.Panel { width = "100%", flexDirection = "column", gap = 4 }

            local function RebuildCurrencyList()
                listPanel:ClearChildren()
                for i, name in ipairs(editCurrencies) do
                    listPanel:AddChild(UI.Panel {
                        flexDirection = "row",
                        width = "100%",
                        gap = 6,
                        alignItems = "center",
                        children = {
                            UI.Label { text = i .. ".", fontSize = 12, fontColor = { 160, 160, 180, 255 }, width = 20 },
                            UI.Label { text = name, fontSize = 14, fontColor = { 220, 220, 240, 255 }, flexGrow = 1 },
                            UI.Button {
                                text = "×",
                                variant = "danger",
                                width = 24, height = 24, fontSize = 12,
                                onClick = function()
                                    if #editCurrencies <= 1 then return end  -- 至少保留一个
                                    table.remove(editCurrencies, i)
                                    RebuildCurrencyList()
                                end,
                            },
                        },
                    })
                end
            end
            RebuildCurrencyList()
            table.insert(formChildren, listPanel)

            -- 添加新货币
            local newCurrField = UI.TextField { placeholder = "输入新货币名称", width = "60%", height = 30 }
            table.insert(formChildren, UI.Panel {
                flexDirection = "row",
                width = "100%",
                gap = 6,
                marginTop = 8,
                alignItems = "center",
                children = {
                    newCurrField,
                    UI.Button {
                        text = "+ 添加",
                        variant = "outline",
                        height = 28,
                        onClick = function()
                            local val = newCurrField:GetValue() or ""
                            if val ~= "" then
                                -- 检查重复
                                for _, c in ipairs(editCurrencies) do
                                    if c == val then return end
                                end
                                table.insert(editCurrencies, val)
                                newCurrField:SetText("")
                                RebuildCurrencyList()
                            end
                        end,
                    },
                },
            })

            local dialogMsg = UI.Label { text = "", fontSize = 11, fontColor = { 100, 255, 100, 255 }, textAlign = "center", height = 16 }
            table.insert(formChildren, dialogMsg)

            -- 保存/关闭按钮
            table.insert(formChildren, UI.Panel {
                flexDirection = "row", gap = 12, marginTop = 8, justifyContent = "center",
                children = {
                    UI.Button {
                        text = "保存", variant = "primary", width = 80,
                        onClick = function()
                            if #editCurrencies == 0 then
                                table.insert(editCurrencies, "金币")
                            end
                            gc["currencies"] = editCurrencies
                            SaveCategoryToCloud("game_config")
                            dialogMsg:SetText("已保存")
                            CloseDialog()
                            RenderGameConfig()
                        end,
                    },
                    UI.Button {
                        text = "关闭", variant = "secondary", width = 80,
                        onClick = function() CloseDialog() end,
                    },
                },
            })

            editDialog_ = UI.Panel {
                width = "100%", height = "100%", position = "absolute",
                justifyContent = "center", alignItems = "center",
                backgroundColor = { 0, 0, 0, 180 },
                children = {
                    UI.Panel {
                        width = 340,
                        backgroundColor = { 30, 25, 55, 250 },
                        borderRadius = 12, padding = 16,
                        flexDirection = "column", gap = 4,
                        children = formChildren,
                    },
                },
            }
            if rootPanel_ then rootPanel_:AddChild(editDialog_) end
        end, 4))

    -- 初始货币配置
    local initCurrData = gc["initial_currencies"] or {}
    local initCurrSummary = ""
    for name, amount in pairs(initCurrData) do
        if initCurrSummary ~= "" then initCurrSummary = initCurrSummary .. ", " end
        initCurrSummary = initCurrSummary .. name .. ":" .. amount
    end
    if initCurrSummary == "" then initCurrSummary = "未配置" end
    contentPanel_:AddChild(CreateListRow("初始货币",
        initCurrSummary,
        function()
            CloseDialog()
            local formChildren = {}
            table.insert(formChildren, UI.Label {
                text = "初始货币配置",
                fontSize = 16,
                fontColor = { 200, 170, 100, 255 },
                textAlign = "center",
                marginBottom = 8,
            })
            table.insert(formChildren, UI.Label {
                text = "新玩家注册时每种货币的初始数量",
                fontSize = 11,
                fontColor = { 140, 140, 160, 255 },
                textAlign = "center",
                marginBottom = 8,
            })

            -- 从已配置的货币列表读取
            local currencyNames = gc["currencies"] or { "金币" }
            local editInitCurr = {}
            for _, name in ipairs(currencyNames) do
                editInitCurr[name] = initCurrData[name] or "0"
            end

            local listPanel = UI.Panel { width = "100%", flexDirection = "column", gap = 6 }

            local currFields = {}
            local function RebuildInitCurrList()
                listPanel:ClearChildren()
                currFields = {}
                for _, name in ipairs(currencyNames) do
                    local field = UI.TextField {
                        text = editInitCurr[name] or "0",
                        width = 100, height = 28,
                        placeholder = "0",
                    }
                    currFields[name] = field
                    listPanel:AddChild(UI.Panel {
                        flexDirection = "row",
                        width = "100%",
                        gap = 8,
                        alignItems = "center",
                        children = {
                            UI.Label { text = name, fontSize = 13, fontColor = { 220, 220, 240, 255 }, width = 80 },
                            field,
                            UI.Label { text = "个", fontSize = 11, fontColor = { 140, 140, 160, 255 } },
                        },
                    })
                end
            end
            RebuildInitCurrList()
            table.insert(formChildren, listPanel)

            local dialogMsg = UI.Label { text = "", fontSize = 11, fontColor = { 100, 255, 100, 255 }, textAlign = "center", height = 16 }
            table.insert(formChildren, dialogMsg)

            table.insert(formChildren, UI.Panel {
                flexDirection = "row", gap = 12, marginTop = 8, justifyContent = "center",
                children = {
                    UI.Button {
                        text = "保存", variant = "primary", width = 80,
                        onClick = function()
                            local result = {}
                            for name, field in pairs(currFields) do
                                local val = tonumber(field:GetValue()) or 0
                                if val > 0 then
                                    result[name] = tostring(val)
                                end
                            end
                            gc["initial_currencies"] = result
                            SaveCategoryToCloud("game_config")
                            dialogMsg:SetText("已保存")
                            CloseDialog()
                            RenderGameConfig()
                        end,
                    },
                    UI.Button {
                        text = "关闭", variant = "secondary", width = 80,
                        onClick = function() CloseDialog() end,
                    },
                },
            })

            editDialog_ = UI.Panel {
                width = "100%", height = "100%", position = "absolute",
                justifyContent = "center", alignItems = "center",
                backgroundColor = { 0, 0, 0, 180 },
                children = {
                    UI.Panel {
                        width = 360,
                        backgroundColor = { 30, 25, 55, 250 },
                        borderRadius = 12, padding = 16,
                        flexDirection = "column", gap = 4,
                        children = formChildren,
                    },
                },
            }
            if rootPanel_ then rootPanel_:AddChild(editDialog_) end
        end, 5))

    -- 初始背包配置
    local initBagData = gc["initial_bag"] or {}
    local initBagSummary = ""
    for i, item in ipairs(initBagData) do
        if i > 1 then initBagSummary = initBagSummary .. ", " end
        initBagSummary = initBagSummary .. item.name .. "x" .. item.count
    end
    if initBagSummary == "" then initBagSummary = "未配置" end
    contentPanel_:AddChild(CreateListRow("初始背包",
        initBagSummary,
        function()
            CloseDialog()
            local formChildren = {}
            table.insert(formChildren, UI.Label {
                text = "初始背包配置",
                fontSize = 16,
                fontColor = { 200, 170, 100, 255 },
                textAlign = "center",
                marginBottom = 8,
            })
            table.insert(formChildren, UI.Label {
                text = "新玩家注册时背包中默认携带的物品",
                fontSize = 11,
                fontColor = { 140, 140, 160, 255 },
                textAlign = "center",
                marginBottom = 8,
            })

            local editBag = {}
            for _, item in ipairs(initBagData) do
                table.insert(editBag, { name = item.name, count = item.count })
            end

            local listPanel = UI.Panel { width = "100%", flexDirection = "column", gap = 4 }

            local function RebuildInitBagList()
                listPanel:ClearChildren()
                for i, item in ipairs(editBag) do
                    listPanel:AddChild(UI.Panel {
                        flexDirection = "row",
                        width = "100%",
                        gap = 6,
                        alignItems = "center",
                        children = {
                            UI.Label { text = i .. ".", fontSize = 12, fontColor = { 160, 160, 180, 255 }, width = 20 },
                            UI.Label { text = item.name, fontSize = 13, fontColor = { 220, 220, 240, 255 }, flexGrow = 1 },
                            UI.Label { text = "x" .. item.count, fontSize = 12, fontColor = { 180, 180, 200, 255 }, width = 40 },
                            UI.Button {
                                text = "×",
                                variant = "danger",
                                width = 24, height = 24, fontSize = 12,
                                onClick = function()
                                    table.remove(editBag, i)
                                    RebuildInitBagList()
                                end,
                            },
                        },
                    })
                end
            end
            RebuildInitBagList()
            table.insert(formChildren, listPanel)

            -- 添加新物品行
            local newItemField = UI.TextField { placeholder = "物品名称", width = "50%", height = 28 }
            local newCountField = UI.TextField { placeholder = "数量", text = "1", width = 60, height = 28 }
            table.insert(formChildren, UI.Panel {
                flexDirection = "row",
                width = "100%",
                gap = 6,
                marginTop = 8,
                alignItems = "center",
                children = {
                    newItemField,
                    newCountField,
                    UI.Button {
                        text = "+ 添加",
                        variant = "outline",
                        height = 28,
                        onClick = function()
                            local itemName = newItemField:GetValue() or ""
                            local itemCount = tonumber(newCountField:GetValue()) or 1
                            if itemName ~= "" and itemCount > 0 then
                                table.insert(editBag, { name = itemName, count = itemCount })
                                newItemField:SetText("")
                                newCountField:SetText("1")
                                RebuildInitBagList()
                            end
                        end,
                    },
                },
            })

            local dialogMsg = UI.Label { text = "", fontSize = 11, fontColor = { 100, 255, 100, 255 }, textAlign = "center", height = 16 }
            table.insert(formChildren, dialogMsg)

            table.insert(formChildren, UI.Panel {
                flexDirection = "row", gap = 12, marginTop = 8, justifyContent = "center",
                children = {
                    UI.Button {
                        text = "保存", variant = "primary", width = 80,
                        onClick = function()
                            gc["initial_bag"] = editBag
                            SaveCategoryToCloud("game_config")
                            dialogMsg:SetText("已保存")
                            CloseDialog()
                            RenderGameConfig()
                        end,
                    },
                    UI.Button {
                        text = "关闭", variant = "secondary", width = 80,
                        onClick = function() CloseDialog() end,
                    },
                },
            })

            editDialog_ = UI.Panel {
                width = "100%", height = "100%", position = "absolute",
                justifyContent = "center", alignItems = "center",
                backgroundColor = { 0, 0, 0, 180 },
                children = {
                    UI.Panel {
                        width = 380,
                        backgroundColor = { 30, 25, 55, 250 },
                        borderRadius = 12, padding = 16,
                        flexDirection = "column", gap = 4,
                        children = formChildren,
                    },
                },
            }
            if rootPanel_ then rootPanel_:AddChild(editDialog_) end
        end, 6))

    -- ===== 装备部位管理 =====
    contentPanel_:AddChild(UI.Label {
        text = "— 装备部位管理 —", fontSize = 14, fontColor = {200,170,100,255},
        textAlign = "center", marginTop = 16, marginBottom = 6,
    })
    contentPanel_:AddChild(UI.Label {
        text = "当前部位列表(可增删,保存后全局生效):", fontSize = 11, fontColor = {150,150,170,255},
        marginBottom = 4,
    })
    -- 当前部位列表
    for _, slot in ipairs(EquipSlots.slots) do
        contentPanel_:AddChild(UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center", gap = 6, marginBottom = 2,
            children = {
                UI.Label { text = slot.label .. " (" .. slot.key .. ")", fontSize = 11, fontColor = {180,180,200,255}, flexGrow = 1 },
                UI.Button { text = "删除", fontSize = 9, width = 42, height = 22, variant = "danger",
                    onClick = function()
                        EquipSlots.Remove(slot.key)
                        -- 保存到 game_config
                        local gc = DataManager.gameConfig
                        if not gc["装备部位"] then gc["装备部位"] = {} end
                        gc["装备部位"]["列表"] = EquipSlots.Serialize()
                        SaveCategoryToCloud("game_config")
                        RenderGameConfig()
                    end },
            },
        })
    end
    -- 添加新部位
    local newSlotKey = UI.TextField { placeholder = "英文key(如earring)", width = 100, height = 26, fontSize = 10 }
    local newSlotLabel = UI.TextField { placeholder = "中文名(如耳环)", width = 100, height = 26, fontSize = 10 }
    contentPanel_:AddChild(UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center", gap = 4, marginTop = 6,
        flexWrap = "wrap",
        children = {
            newSlotKey,
            newSlotLabel,
            UI.Button { text = "+ 添加", fontSize = 10, height = 26, variant = "primary",
                onClick = function()
                    local k = newSlotKey:GetValue() or ""
                    local l = newSlotLabel:GetValue() or ""
                    if k == "" or l == "" then ShowMsg("请输入英文key和中文名"); return end
                    if not EquipSlots.Add(k, l) then ShowMsg("部位已存在"); return end
                    local gc = DataManager.gameConfig
                    if not gc["装备部位"] then gc["装备部位"] = {} end
                    gc["装备部位"]["列表"] = EquipSlots.Serialize()
                    SaveCategoryToCloud("game_config")
                    ShowMsg("已添加部位「" .. l .. "」")
                    RenderGameConfig()
                end },
        },
    })

end

-- =============== 通用列表配置管理 ===============

--- 渲染地图列表
local function RenderMaps()
    ClearContent()
    contentPanel_:AddChild(CreateSearchBar("搜索地图名...", function() RenderMaps() end))
    local count = 0
    for _ in pairs(DataManager.maps) do count = count + 1 end
    ShowMsg("共 " .. count .. " 张地图")

    local dataArray = {}
    for id, data in pairs(DataManager.maps) do
        if not MatchSearch(data.name or id) then goto continue_maps end
        table.insert(dataArray, {
            text = data.name or id,
            subtext = "等级需求:" .. (data.level_req or 0) .. " 怪物:" .. (data.monsters or ""),
            onEdit = function()
                ShowEditDialog("编辑地图 - " .. id, {
                    { label = "名称", key = "name", value = data.name },
                    { label = "描述", key = "desc", value = data.desc, opts = { width = 220 } },
                    { label = "怪物", key = "monsters", value = data.monsters, opts = { width = 220, placeholder = "逗号分隔" } },
                    { label = "NPC", key = "npcs", value = data.npcs, opts = { width = 220, placeholder = "逗号分隔" } },
                    { label = "前方", key = "front", value = data.front },
                    { label = "后方", key = "back", value = data.back },
                    { label = "左方", key = "left", value = data.left },
                    { label = "右方", key = "right", value = data.right },
                    { label = "等级要求", key = "level_req", value = data.level_req },
                }, function(v)
                    DataManager.maps[id] = {
                        name = v.name, desc = v.desc, monsters = v.monsters, npcs = v.npcs,
                        front = v.front, back = v.back, left = v.left, right = v.right,
                        level_req = v.level_req or "0",
                    }
                    SaveCategoryToCloud("maps")
                    CloseDialog()
                    RenderMaps()
                end)
            end,
            onDelete = function()
                DataManager.maps[id] = nil
                SaveCategoryToCloud("maps")
                RenderMaps()
            end,
        })
        ::continue_maps::
    end
    contentPanel_:AddChild(CreateVirtualDataList(dataArray))

    -- 添加按钮
    contentPanel_:AddChild(UI.Button {
        text = "+ 添加地图",
        variant = "primary",
        width = 120,
        marginTop = 8,
        marginLeft = 12,
        onClick = function()
            ShowEditDialog("添加地图", {
                { label = "ID", key = "id", value = "", opts = { placeholder = "如：新地图" } },
                { label = "名称", key = "name", value = "" },
                { label = "描述", key = "desc", value = "", opts = { width = 220 } },
                { label = "怪物", key = "monsters", value = "", opts = { width = 220, placeholder = "逗号分隔" } },
                { label = "NPC", key = "npcs", value = "", opts = { width = 220, placeholder = "逗号分隔" } },
                { label = "前方", key = "front", value = "" },
                { label = "后方", key = "back", value = "" },
                { label = "左方", key = "left", value = "" },
                { label = "右方", key = "right", value = "" },
                { label = "等级要求", key = "level_req", value = "0" },
            }, function(v)
                if v.id == "" then return end
                DataManager.maps[v.id] = {
                    name = v.name ~= "" and v.name or v.id, desc = v.desc,
                    monsters = v.monsters, npcs = v.npcs,
                    front = v.front, back = v.back, left = v.left, right = v.right,
                    level_req = v.level_req or "0",
                }
                SaveCategoryToCloud("maps")
                CloseDialog()
                RenderMaps()
            end)
        end,
    })
end

--- 渲染怪物列表
local function RenderMonsters()
    ClearContent()
    contentPanel_:AddChild(CreateSearchBar("搜索怪物名...", function() RenderMonsters() end))
    local count = 0
    for _ in pairs(DataManager.monsters) do count = count + 1 end
    ShowMsg("共 " .. count .. " 种怪物")

    local dataArray = {}
    for id, data in pairs(DataManager.monsters) do
        if not MatchSearch(data.name or id) then goto continue_monsters end
        local typeTag = data.type and ("[" .. data.type .. "] ") or ""
        -- 动态构建编辑字段（含多货币）
        local editFields = {
            { label = "名称", key = "name", value = data.name },
            { label = "描述", key = "desc", value = data.desc, opts = { width = 220 } },
            { label = "生命值", key = "hp", value = data.hp },
            { label = "攻击力", key = "atk", value = data.atk },
            { label = "防御力", key = "def", value = data.def },
            { label = "经验值", key = "exp", value = data.exp },
        }
        local currencies = DataManager.gameConfig["currencies"] or { "金币" }
        for _, cName in ipairs(currencies) do
            local cVal = (data.currency_drops and data.currency_drops[cName]) or (cName == "金币" and data.gold) or "0"
            table.insert(editFields, { label = cName, key = "curr_" .. cName, value = cVal })
        end
        table.insert(editFields, { label = "掉落", key = "drops", value = data.drops, opts = { width = 220, placeholder = "物品:概率,..." } })

        table.insert(dataArray, {
            text = typeTag .. (data.name or id),
            subtext = "血量:" .. (data.hp or 0) .. " 攻击:" .. (data.atk or 0) .. " 经验:" .. (data.exp or 0),
            onEdit = function()
                ShowEditDialog("编辑怪物 - " .. id, editFields, function(v)
                    local currDrops = {}
                    local cs = DataManager.gameConfig["currencies"] or { "金币" }
                    for _, cn in ipairs(cs) do
                        currDrops[cn] = v["curr_" .. cn] or "0"
                    end
                    DataManager.monsters[id] = {
                        name = v.name, type = DataManager.ClassifyMonsterType(v.hp or "20"), desc = v.desc,
                        hp = v.hp or "20", atk = v.atk or "3",
                        def = v.def or "1", exp = v.exp or "5",
                        gold = currDrops["金币"] or v["curr_金币"] or "2",
                        currency_drops = currDrops, drops = v.drops,
                    }
                    SaveCategoryToCloud("monsters")
                    CloseDialog()
                    RenderMonsters()
                end)
            end,
            onDelete = function()
                DataManager.monsters[id] = nil
                SaveCategoryToCloud("monsters")
                RenderMonsters()
            end,
        })
        ::continue_monsters::
    end
    contentPanel_:AddChild(CreateVirtualDataList(dataArray))

    contentPanel_:AddChild(UI.Button {
        text = "+ 添加怪物",
        variant = "primary", width = 120, marginTop = 8, marginLeft = 12,
        onClick = function()
            local addFields = {
                { label = "ID(名称)", key = "id", value = "", opts = { placeholder = "如：火焰鸟" } },
                { label = "描述", key = "desc", value = "", opts = { width = 220 } },
                { label = "生命值", key = "hp", value = "50" },
                { label = "攻击力", key = "atk", value = "10" },
                { label = "防御力", key = "def", value = "5" },
                { label = "经验值", key = "exp", value = "15" },
            }
            local addCurrencies = DataManager.gameConfig["currencies"] or { "金币" }
            for _, cName in ipairs(addCurrencies) do
                table.insert(addFields, { label = cName, key = "curr_" .. cName, value = "8" })
            end
            table.insert(addFields, { label = "掉落", key = "drops", value = "", opts = { width = 220, placeholder = "物品:概率,..." } })

            ShowEditDialog("添加怪物", addFields, function(v)
                if v.id == "" then return end
                local currDrops = {}
                for _, cn in ipairs(addCurrencies) do
                    currDrops[cn] = v["curr_" .. cn] or "0"
                end
                DataManager.monsters[v.id] = {
                    name = v.id, type = DataManager.ClassifyMonsterType(v.hp or "50"), desc = v.desc,
                    hp = v.hp or "50", atk = v.atk or "10",
                    def = v.def or "5", exp = v.exp or "15",
                    gold = currDrops["金币"] or "8",
                    currency_drops = currDrops, drops = v.drops,
                }
                SaveCategoryToCloud("monsters")
                CloseDialog()
                RenderMonsters()
            end)
        end,
    })
end

--- 渲染物品列表
-- 道具类型选项
local ITEM_TYPES = { "攻击", "防御", "生命上限", "恢复血量", "恢复灵力", "经验倍率", "货币倍率", "复活", "材料" }

--- 物品类型英文→中文（兼容旧数据）
local ITEM_TYPE_EN_TO_CN = {
    material = "材料", consumable = "恢复血量", attack = "攻击",
    defense = "防御", hp = "生命上限", mp = "恢复灵力",
    exp = "经验倍率", gold = "货币倍率", recover_hp = "恢复血量",
    recover_mp = "恢复灵力", exp_boost = "经验倍率", gold_boost = "货币倍率",
    currency_boost = "货币倍率", max_hp = "生命上限", revive = "复活",
}

--- 创建道具类型选择器
---@param currentType string
---@param disabled boolean
---@return Widget panel, fun():string getSelected
local function CreateTypeSelector(currentType, disabled)
    -- 支持多选，currentType 可能是 "攻击|防御" 格式
    local selectedSet = {}
    if currentType and currentType ~= "" then
        for t in currentType:gmatch("[^|]+") do
            local trimmed = t:match("^%s*(.-)%s*$")
            if trimmed ~= "" then
                -- 英文类型自动转中文
                trimmed = ITEM_TYPE_EN_TO_CN[trimmed] or trimmed
                selectedSet[trimmed] = true
            end
        end
    end
    if next(selectedSet) == nil then
        selectedSet["材料"] = true
    end

    local btnList = {}
    local selectorPanel

    local function refreshButtons()
        for i, btn in ipairs(btnList) do
            local typeName = ITEM_TYPES[i]
            if selectedSet[typeName] then
                btn:SetVariant("primary")
            else
                btn:SetVariant("secondary")
            end
        end
    end

    local btnChildren = {}
    for i, typeName in ipairs(ITEM_TYPES) do
        local btn = UI.Button {
            text = typeName,
            fontSize = 10,
            width = 56,
            height = 22,
            variant = selectedSet[typeName] and "primary" or "secondary",
            onClick = function()
                if disabled then return end
                if selectedSet[typeName] then
                    -- 取消选中（但至少保留一个）
                    local count = 0
                    for _ in pairs(selectedSet) do count = count + 1 end
                    if count > 1 then
                        selectedSet[typeName] = nil
                    end
                else
                    selectedSet[typeName] = true
                end
                refreshButtons()
            end,
        }
        if disabled then btn:SetDisabled(true) end
        btnList[i] = btn
        table.insert(btnChildren, btn)
    end

    selectorPanel = UI.Panel {
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 3,
        marginBottom = 4,
        children = btnChildren,
    }

    local wrapper = UI.Panel {
        flexDirection = "column",
        gap = 2,
        marginBottom = 4,
        children = {
            UI.Label {
                text = "类型（可多选）",
                fontSize = 12,
                fontColor = { 180, 180, 200, 255 },
            },
            selectorPanel,
        },
    }

    local function getSelected()
        -- 按 ITEM_TYPES 顺序拼接，用 | 分隔
        local result = {}
        for _, typeName in ipairs(ITEM_TYPES) do
            if selectedSet[typeName] then
                table.insert(result, typeName)
            end
        end
        return table.concat(result, "|")
    end

    return wrapper, getSelected
end

--- 显示物品编辑弹窗（含类型选择器）
---@param title string
---@param itemData table|nil 编辑时有数据，新增时为nil
---@param itemId string|nil 编辑时有ID
---@param isNew boolean
local function ShowItemEditDialog(title, itemData, itemId, isNew)
    CloseDialog()

    local data = itemData or {}
    local fieldWidgets = {}
    local formChildren = {}

    table.insert(formChildren, UI.Label {
        text = title,
        fontSize = 16,
        fontColor = { 255, 200, 100, 255 },
        textAlign = "center",
        marginBottom = 8,
    })

    -- ID 字段（仅新增时可编辑）
    if isNew then
        local idPanel, idField = CreateFormField("物品名称", "", { width = 180, placeholder = "输入物品名称" })
        fieldWidgets["id"] = idField
        table.insert(formChildren, idPanel)
    else
        table.insert(formChildren, UI.Label {
            text = "物品: " .. (itemId or ""),
            fontSize = 13,
            fontColor = { 200, 200, 220, 255 },
            marginBottom = 4,
        })
    end

    -- 名称
    local namePanel, nameField = CreateFormField("显示名称", data.name or "", { width = 180 })
    fieldWidgets["name"] = nameField
    table.insert(formChildren, namePanel)

    -- 类型选择器
    local typePanel, getType = CreateTypeSelector(data.type or "材料", false)
    table.insert(formChildren, typePanel)

    -- 描述
    local descPanel, descField = CreateFormField("描述", data.desc or "", { width = 220 })
    fieldWidgets["desc"] = descField
    table.insert(formChildren, descPanel)

    -- 数值
    local valuePanel, valueField = CreateFormField("数值", tostring(data.value or "0"), { width = 120, showUnit = true })
    fieldWidgets["value"] = valueField
    table.insert(formChildren, valuePanel)

    -- 持续时间（分钟），0或空=永久
    local durPanel, durField = CreateFormField("持续时间(分钟)", tostring(data.duration or ""), { width = 120, placeholder = "0=永久" })
    fieldWidgets["duration"] = durField
    table.insert(formChildren, durPanel)

    -- 消息
    local dialogMsg = UI.Label {
        text = "",
        fontSize = 11,
        fontColor = { 100, 255, 100, 255 },
        textAlign = "center",
        height = 16,
    }
    table.insert(formChildren, dialogMsg)

    -- 按钮
    table.insert(formChildren, UI.Panel {
        flexDirection = "row",
        gap = 12,
        marginTop = 8,
        justifyContent = "center",
        children = {
            UI.Button {
                text = "保存",
                variant = "primary",
                width = 80,
                onClick = function()
                    local selectedType = getType()
                    local name = fieldWidgets["name"]:GetValue() or ""
                    local id = isNew and (fieldWidgets["id"]:GetValue() or "") or itemId
                    if isNew and id == "" then
                        dialogMsg:SetText("请输入物品名称")
                        return
                    end
                    if isNew and name == "" then
                        name = id
                    end

                    local durStr = fieldWidgets["duration"]:GetValue() or ""
                    local durVal = tonumber(durStr) or 0
                    DataManager.items[id] = {
                        name = name,
                        type = selectedType,
                        value = fieldWidgets["value"]:GetValue() or "0",
                        duration = durVal > 0 and tostring(durVal) or nil,
                        desc = fieldWidgets["desc"]:GetValue() or "",
                    }
                    SaveCategoryToCloud("items")
                    dialogMsg:SetText("已保存")
                    CloseDialog()
                    RenderItems()
                end,
            },
            UI.Button {
                text = "关闭",
                variant = "secondary",
                width = 80,
                onClick = function() CloseDialog() end,
            },
        },
    })

    editDialog_ = UI.Panel {
        width = "100%",
        height = "100%",
        position = "absolute",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        children = {
            UI.ScrollView {
                width = 380,
                maxHeight = 500,
                backgroundColor = { 30, 25, 55, 250 },
                borderRadius = 12,
                padding = 16,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "column",
                        gap = 4,
                        children = formChildren,
                    },
                },
            },
        },
    }
    if rootPanel_ then
        rootPanel_:AddChild(editDialog_)
    end
end

RenderItems = function()
    ClearContent()
    contentPanel_:AddChild(CreateSearchBar("搜索物品名/类型...", function() RenderItems() end))
    local count = 0
    for _ in pairs(DataManager.items) do count = count + 1 end
    ShowMsg("共 " .. count .. " 种物品")

    local dataArray = {}
    for id, data in pairs(DataManager.items) do
        local typeCN = ITEM_TYPE_EN_TO_CN[data.type] or data.type
        if not MatchSearch(data.name or id) and not MatchSearch(data.type) and not MatchSearch(typeCN) then goto continue_items end
        local typeStr = data.type or "材料"
        typeStr = ITEM_TYPE_EN_TO_CN[typeStr] or typeStr
        table.insert(dataArray, {
            text = (data.name or id) .. "  [" .. typeStr .. "]",
            subtext = "数值:" .. tostring(data.value or 0),
            onEdit = function()
                ShowItemEditDialog("编辑物品 - " .. (data.name or id), data, id, false)
            end,
            onDelete = function()
                DataManager.items[id] = nil
                SaveCategoryToCloud("items")
                RenderItems()
            end,
        })
        ::continue_items::
    end
    contentPanel_:AddChild(CreateVirtualDataList(dataArray))

    contentPanel_:AddChild(UI.Button {
        text = "+ 添加物品",
        variant = "primary", width = 120, marginTop = 8, marginLeft = 12,
        onClick = function()
            ShowItemEditDialog("添加新物品", nil, nil, true)
        end,
    })
end

--- 装备部位选项（从共享模块动态获取,管理员可后台增删）
local function GetEquipSlotLabels() return EquipSlots.labels end
--- 装备品质选项
local EQUIP_QUALITIES = { "白色", "绿色", "橙色", "红色", "彩色", "地级", "天级", "帝级", "仙级", "神级", "创世级" }

--- 英文→中文翻译映射（引用共享模块）
local SLOT_EN_TO_CN = EquipSlots.keyToLabel
local QUALITY_EN_TO_CN = {
    white = "白色", green = "绿色", blue = "蓝色", purple = "紫色",
    orange = "橙色", gold = "金色", red = "红色",
}

--- NPC类型英文→中文
local NPC_TYPE_EN_TO_CN = {
    quest = "任务", merchant = "商人", master = "师傅",
    teacher = "师傅", blacksmith = "铁匠", elder = "长老",
}
--- 任务目标类型英文→中文
local TARGET_TYPE_EN_TO_CN = {
    kill = "击杀", collect = "收集", explore = "探索",
    talk = "对话", level = "等级", escort = "护送",
}
--- 任务类型英文→中文
local QUEST_TYPE_EN_TO_CN = {
    main = "主线", side = "支线", daily = "日常",
}

--- 将可能的英文部位/品质转换为中文显示
local function SlotToCN(slot)
    if not slot or slot == "" then return "武器" end
    return SLOT_EN_TO_CN[slot] or slot
end
local function QualityToCN(quality)
    if not quality or quality == "" then return "白色" end
    return QUALITY_EN_TO_CN[quality] or quality
end
local function NpcTypeToCN(t)
    if not t or t == "" then return "任务" end
    return NPC_TYPE_EN_TO_CN[t] or t
end
local function TargetTypeToCN(t)
    if not t or t == "" then return "击杀" end
    return TARGET_TYPE_EN_TO_CN[t] or t
end
local function QuestTypeToCN(t)
    if not t or t == "" then return "支线" end
    return QUEST_TYPE_EN_TO_CN[t] or t
end

--- 创建按钮组选择器（通用）
---@param options string[] 选项列表
---@param currentValue string 当前选中值
---@param label string 标签文字
---@param disabled boolean
---@return Widget panel, fun():string getSelected
CreateButtonSelector = function(options, currentValue, label, disabled)
    local selected = currentValue or options[1]
    local btnList = {}

    local function refreshButtons()
        for i, btn in ipairs(btnList) do
            if options[i] == selected then
                btn:SetVariant("primary")
            else
                btn:SetVariant("secondary")
            end
        end
    end

    local btnChildren = {}
    for i, optName in ipairs(options) do
        local btn = UI.Button {
            text = optName,
            fontSize = 10,
            width = 48,
            height = 22,
            variant = (optName == selected) and "primary" or "secondary",
            onClick = function()
                if disabled then return end
                selected = optName
                refreshButtons()
            end,
        }
        if disabled then btn:SetDisabled(true) end
        btnList[i] = btn
        table.insert(btnChildren, btn)
    end

    local wrapper = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 4,
        marginBottom = 4,
        children = {
            UI.Label {
                text = label,
                fontSize = 12,
                fontColor = { 180, 180, 200, 255 },
                width = 80,
            },
            UI.Panel {
                flexDirection = "row",
                flexWrap = "wrap",
                gap = 3,
                children = btnChildren,
            },
        },
    }

    return wrapper, function() return selected end
end

--- 渲染装备列表
local function RenderEquipment()
    ClearContent()
    contentPanel_:AddChild(CreateSearchBar("搜索装备名...", function() RenderEquipment() end))
    local count = 0
    for _ in pairs(DataManager.equipment) do count = count + 1 end
    ShowMsg("共 " .. count .. " 件装备")

    local dataArray = {}
    for id, data in pairs(DataManager.equipment) do
        if not MatchSearch(data.name or id) then goto continue_equip end
        table.insert(dataArray, {
            text = (data.name or id) .. "  [" .. SlotToCN(data.slot or "武器") .. "]",
            subtext = "品质:" .. QualityToCN(data.quality or "白色") .. " 攻击:" .. (data.atk or 0) .. " 防御:" .. (data.def or 0) .. " 生命:" .. (data.hp or 0),
            onEdit = function()
                -- 使用自定义弹窗（含选择器）
                CloseDialog()
                local fieldWidgets = {}
                local formChildren = {}

                table.insert(formChildren, UI.Label {
                    text = "编辑装备 - " .. (data.name or id),
                    fontSize = 16,
                    fontColor = { 255, 200, 100, 255 },
                    textAlign = "center",
                    marginBottom = 8,
                })

                -- 名称
                local namePanel, nameField = CreateFormField("名称", data.name or id, { width = 180 })
                fieldWidgets["name"] = nameField
                table.insert(formChildren, namePanel)

                -- 部位选择器
                local slotPanel, getSlot = CreateButtonSelector(GetEquipSlotLabels(), SlotToCN(data.slot or "武器"), "部位", false)
                table.insert(formChildren, slotPanel)

                -- 品质选择器
                local qualityPanel, getQuality = CreateButtonSelector(EQUIP_QUALITIES, QualityToCN(data.quality or "白色"), "品质", false)
                table.insert(formChildren, qualityPanel)

                -- 其他字段
                local descPanel, descField = CreateFormField("描述", data.desc or "", { width = 220 })
                fieldWidgets["desc"] = descField
                table.insert(formChildren, descPanel)

                local atkPanel, atkField = CreateFormField("攻击", tostring(data.atk or 0), { width = 120, showUnit = true })
                fieldWidgets["atk"] = atkField
                table.insert(formChildren, atkPanel)

                local defPanel, defField = CreateFormField("防御", tostring(data.def or 0), { width = 120, showUnit = true })
                fieldWidgets["def"] = defField
                table.insert(formChildren, defPanel)

                local hpPanel, hpField = CreateFormField("生命", tostring(data.hp or 0), { width = 120, showUnit = true })
                fieldWidgets["hp"] = hpField
                table.insert(formChildren, hpPanel)

                local lvlPanel, lvlField = CreateFormField("等级需求", tostring(data.level_req or 1), { width = 120 })
                fieldWidgets["level_req"] = lvlField
                table.insert(formChildren, lvlPanel)

                local sellPanel, sellField = CreateFormField("出售价", tostring(data.price_sell or 0), { width = 120, showUnit = true })
                fieldWidgets["price_sell"] = sellField
                table.insert(formChildren, sellPanel)

                local dialogMsg = UI.Label { text = "", fontSize = 11, fontColor = { 100, 255, 100, 255 }, textAlign = "center", height = 16 }
                table.insert(formChildren, dialogMsg)

                table.insert(formChildren, UI.Panel {
                    flexDirection = "row", gap = 12, marginTop = 8, justifyContent = "center",
                    children = {
                        UI.Button {
                            text = "保存", variant = "primary", width = 80,
                            onClick = function()
                                DataManager.equipment[id] = {
                                    name = fieldWidgets["name"]:GetValue() or id,
                                    slot = getSlot(),
                                    quality = getQuality(),
                                    desc = fieldWidgets["desc"]:GetValue() or "",
                                    atk = fieldWidgets["atk"]:GetValue() or "0",
                                    def = fieldWidgets["def"]:GetValue() or "0",
                                    hp = fieldWidgets["hp"]:GetValue() or "0",
                                    level_req = fieldWidgets["level_req"]:GetValue() or "1",
                                    price_sell = fieldWidgets["price_sell"]:GetValue() or "0",
                                }
                                SaveCategoryToCloud("equipment")
                                dialogMsg:SetText("已保存")
                                CloseDialog()
                                RenderEquipment()
                            end,
                        },
                        UI.Button { text = "关闭", variant = "secondary", width = 80, onClick = function() CloseDialog() end },
                    },
                })

                editDialog_ = UI.Panel {
                    width = "100%", height = "100%", position = "absolute",
                    justifyContent = "center", alignItems = "center", backgroundColor = { 0, 0, 0, 180 },
                    children = {
                        UI.ScrollView {
                            width = 380, maxHeight = 500, backgroundColor = { 30, 25, 55, 250 },
                            borderRadius = 12, padding = 16,
                            children = { UI.Panel { width = "100%", flexDirection = "column", gap = 4, children = formChildren } },
                        },
                    },
                }
                if rootPanel_ then rootPanel_:AddChild(editDialog_) end
            end,
            onDelete = function()
                DataManager.equipment[id] = nil
                SaveCategoryToCloud("equipment")
                RenderEquipment()
            end,
        })
        ::continue_equip::
    end
    contentPanel_:AddChild(CreateVirtualDataList(dataArray))

    contentPanel_:AddChild(UI.Button {
        text = "+ 添加装备",
        variant = "primary", width = 120, marginTop = 8, marginLeft = 12,
        onClick = function()
            CloseDialog()
            local fieldWidgets = {}
            local formChildren = {}

            table.insert(formChildren, UI.Label {
                text = "添加装备", fontSize = 16, fontColor = { 255, 200, 100, 255 }, textAlign = "center", marginBottom = 8,
            })

            local idPanel, idField = CreateFormField("装备名称", "", { width = 180, placeholder = "输入装备名称" })
            fieldWidgets["id"] = idField
            table.insert(formChildren, idPanel)

            local slotPanel, getSlot = CreateButtonSelector(GetEquipSlotLabels(), "武器", "部位", false)
            table.insert(formChildren, slotPanel)

            local qualityPanel, getQuality = CreateButtonSelector(EQUIP_QUALITIES, "白色", "品质", false)
            table.insert(formChildren, qualityPanel)

            local descPanel, descField = CreateFormField("描述", "", { width = 220 })
            fieldWidgets["desc"] = descField
            table.insert(formChildren, descPanel)

            local atkPanel, atkField = CreateFormField("攻击", "5", { width = 120, showUnit = true })
            fieldWidgets["atk"] = atkField
            table.insert(formChildren, atkPanel)

            local defPanel, defField = CreateFormField("防御", "0", { width = 120, showUnit = true })
            fieldWidgets["def"] = defField
            table.insert(formChildren, defPanel)

            local hpPanel, hpField = CreateFormField("生命", "0", { width = 120, showUnit = true })
            fieldWidgets["hp"] = hpField
            table.insert(formChildren, hpPanel)

            local lvlPanel, lvlField = CreateFormField("等级需求", "1", { width = 120 })
            fieldWidgets["level_req"] = lvlField
            table.insert(formChildren, lvlPanel)

            local sellPanel, sellField = CreateFormField("出售价", "20", { width = 120, showUnit = true })
            fieldWidgets["price_sell"] = sellField
            table.insert(formChildren, sellPanel)

            local dialogMsg = UI.Label { text = "", fontSize = 11, fontColor = { 100, 255, 100, 255 }, textAlign = "center", height = 16 }
            table.insert(formChildren, dialogMsg)

            table.insert(formChildren, UI.Panel {
                flexDirection = "row", gap = 12, marginTop = 8, justifyContent = "center",
                children = {
                    UI.Button {
                        text = "保存", variant = "primary", width = 80,
                        onClick = function()
                            local newId = fieldWidgets["id"]:GetValue() or ""
                            if newId == "" then
                                dialogMsg:SetText("请输入装备名称")
                                return
                            end
                            DataManager.equipment[newId] = {
                                name = newId,
                                slot = getSlot(),
                                quality = getQuality(),
                                desc = fieldWidgets["desc"]:GetValue() or "",
                                atk = fieldWidgets["atk"]:GetValue() or "0",
                                def = fieldWidgets["def"]:GetValue() or "0",
                                hp = fieldWidgets["hp"]:GetValue() or "0",
                                level_req = fieldWidgets["level_req"]:GetValue() or "1",
                                price_sell = fieldWidgets["price_sell"]:GetValue() or "0",
                            }
                            SaveCategoryToCloud("equipment")
                            dialogMsg:SetText("已保存")
                            CloseDialog()
                            RenderEquipment()
                        end,
                    },
                    UI.Button { text = "关闭", variant = "secondary", width = 80, onClick = function() CloseDialog() end },
                },
            })

            editDialog_ = UI.Panel {
                width = "100%", height = "100%", position = "absolute",
                justifyContent = "center", alignItems = "center", backgroundColor = { 0, 0, 0, 180 },
                children = {
                    UI.ScrollView {
                        width = 380, maxHeight = 500, backgroundColor = { 30, 25, 55, 250 },
                        borderRadius = 12, padding = 16,
                        children = { UI.Panel { width = "100%", flexDirection = "column", gap = 4, children = formChildren } },
                    },
                },
            }
            if rootPanel_ then rootPanel_:AddChild(editDialog_) end
        end,
    })
end

--- 任务类型选项
local QUEST_TYPES = { "主线", "支线" }
--- 任务目标类型选项
local QUEST_TARGET_TYPES = { "击杀", "收集", "对话", "探索" }

--- 渲染任务列表
local function RenderQuests()
    ClearContent()
    contentPanel_:AddChild(CreateSearchBar("搜索任务名...", function() RenderQuests() end))
    local count = 0
    for _ in pairs(DataManager.quests) do count = count + 1 end
    ShowMsg("共 " .. count .. " 个任务")

    local dataArray = {}
    for id, data in pairs(DataManager.quests) do
        if not MatchSearch(data.name or id) then goto continue_quests end
        table.insert(dataArray, {
            text = "[" .. QuestTypeToCN(data.type or "支线") .. "] " .. (data.name or id),
            subtext = "目标:" .. TargetTypeToCN(data.target_type or "击杀") .. " " .. (data.target_name or "") .. "x" .. (data.target_count or 1) .. " 经验:" .. (data.reward_exp or 0),
            onEdit = function()
                ShowEditDialog("编辑任务 - " .. id, {
                    { label = "名称", key = "name", value = data.name },
                    { label = "类型", key = "type", value = data.type, opts = { placeholder = "主线/支线" } },
                    { label = "描述", key = "desc", value = data.desc, opts = { width = 220 } },
                    { label = "目标类型", key = "target_type", value = data.target_type, opts = { placeholder = "击杀/收集/对话/探索" } },
                    { label = "目标名称", key = "target_name", value = data.target_name },
                    { label = "目标数量", key = "target_count", value = data.target_count },
                    { label = "奖励经验", key = "reward_exp", value = data.reward_exp },
                    { label = "奖励金币", key = "reward_gold", value = data.reward_gold },
                    { label = "奖励物品", key = "reward_items", value = data.reward_items, opts = { width = 220, placeholder = "物品:数量,..." } },
                    { label = "后续任务", key = "next_quest", value = data.next_quest },
                }, function(v)
                    DataManager.quests[id] = {
                        name = v.name, type = v.type, desc = v.desc,
                        target_type = v.target_type, target_name = v.target_name,
                        target_count = v.target_count or "1",
                        reward_exp = v.reward_exp or "0", reward_gold = v.reward_gold or "0",
                        reward_items = v.reward_items, next_quest = v.next_quest,
                    }
                    SaveCategoryToCloud("quests")
                    CloseDialog()
                    RenderQuests()
                end)
            end,
            onDelete = function()
                DataManager.quests[id] = nil
                SaveCategoryToCloud("quests")
                RenderQuests()
            end,
        })
        ::continue_quests::
    end
    contentPanel_:AddChild(CreateVirtualDataList(dataArray))

    contentPanel_:AddChild(UI.Button {
        text = "+ 添加任务",
        variant = "primary", width = 120, marginTop = 8, marginLeft = 12,
        onClick = function()
            ShowEditDialog("添加任务", {
                { label = "任务ID", key = "id", value = "", opts = { placeholder = "如: 支线_007" } },
                { label = "名称", key = "name", value = "" },
                { label = "类型", key = "type", value = "支线", opts = { placeholder = "主线/支线" } },
                { label = "描述", key = "desc", value = "", opts = { width = 220 } },
                { label = "目标类型", key = "target_type", value = "击杀", opts = { placeholder = "击杀/收集/对话/探索" } },
                { label = "目标名称", key = "target_name", value = "" },
                { label = "目标数量", key = "target_count", value = "3" },
                { label = "奖励经验", key = "reward_exp", value = "30" },
                { label = "奖励金币", key = "reward_gold", value = "50" },
                { label = "奖励物品", key = "reward_items", value = "", opts = { width = 220, placeholder = "物品:数量,..." } },
                { label = "后续任务", key = "next_quest", value = "" },
            }, function(v)
                if v.id == "" then return end
                DataManager.quests[v.id] = {
                    name = v.name, type = v.type, desc = v.desc,
                    target_type = v.target_type, target_name = v.target_name,
                    target_count = v.target_count or "1",
                    reward_exp = v.reward_exp or "0", reward_gold = v.reward_gold or "0",
                    reward_items = v.reward_items, next_quest = v.next_quest,
                }
                SaveCategoryToCloud("quests")
                CloseDialog()
                RenderQuests()
            end)
        end,
    })
end

--- 获取已有物品名称列表
local function GetItemNameList()
    local names = {}
    for id, data in pairs(DataManager.items) do
        table.insert(names, data.name or id)
    end
    table.sort(names)
    return names
end

--- 显示商店编辑弹窗（支持多商品行）
---@param title string
---@param shopData table|nil
---@param shopId string|nil
---@param isNew boolean
local function ShowShopEditDialog(title, shopData, shopId, isNew)
    CloseDialog()

    local data = shopData or { name = "", desc = "", items = {} }
    -- 深拷贝商品列表用于编辑
    local editItems = {}
    for _, item in ipairs(data.items or {}) do
        table.insert(editItems, { name = item.name or "", price = item.price or "0", desc = item.desc or "" })
    end

    local fieldWidgets = {}
    local itemsContainer
    local formChildren = {}

    -- 标题
    table.insert(formChildren, UI.Label {
        text = title,
        fontSize = 14,
        fontColor = { 255, 220, 100, 255 },
        textAlign = "center",
        marginBottom = 8,
    })

    -- 商店ID（新增时）
    if isNew then
        local idPanel, idField = CreateFormField("商店ID", "", { placeholder = "如: shop_xxx" })
        fieldWidgets["id"] = idField
        table.insert(formChildren, idPanel)
    else
        table.insert(formChildren, UI.Label {
            text = "商店: " .. (shopId or ""),
            fontSize = 13,
            fontColor = { 200, 200, 220, 255 },
            marginBottom = 4,
        })
    end

    -- 名称
    local namePanel, nameField = CreateFormField("名称", data.name or "", { width = 180 })
    fieldWidgets["name"] = nameField
    table.insert(formChildren, namePanel)

    -- 描述
    local descPanel, descField = CreateFormField("描述", data.desc or "", { width = 220 })
    fieldWidgets["desc"] = descField
    table.insert(formChildren, descPanel)

    -- 商品列表标题
    table.insert(formChildren, UI.Label {
        text = "── 商品列表 ──",
        fontSize = 12,
        fontColor = { 150, 200, 255, 255 },
        textAlign = "center",
        marginTop = 8,
        marginBottom = 4,
    })

    -- 已有物品名称（用于提示）
    local existingItems = GetItemNameList()

    -- 商品行容器
    itemsContainer = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 6,
    }
    table.insert(formChildren, itemsContainer)

    -- 渲染商品行
    local function RebuildItemRows()
        itemsContainer:RemoveAllChildren()
        for i, item in ipairs(editItems) do
            -- 价格单位标签（显示在价格输入框下方）
            local initPrice = (item.price == nil or item.price == "") and "0" or tostring(item.price)
            local priceUnitLabel = UI.Label { text = NumFormat.Short(initPrice), fontSize = 9, fontColor = { 140, 200, 140, 255 }, marginTop = 1 }

            local rowNameField = UI.TextField { value = item.name or "", placeholder = "物品名", width = 100, height = 28, fontSize = 11 }
            local rowPriceField = UI.TextField {
                value = tostring(item.price or "0"), placeholder = "0", width = 70, height = 28, fontSize = 11,
                onChange = function(_, t)
                    local v = (t == nil or t == "") and "0" or t
                    priceUnitLabel:SetText(NumFormat.Short(v))
                end,
            }
            local rowDescField = UI.TextField { value = item.desc or "", placeholder = "描述", width = 90, height = 28, fontSize = 11 }

            local row = UI.Panel {
                flexDirection = "row",
                alignItems = "flex-start",
                gap = 4,
                width = "100%",
                children = {
                    UI.Panel { flexDirection = "column", gap = 1, children = {
                        UI.Label { text = "物品" .. i, fontSize = 9, fontColor = { 150, 150, 170, 255 } },
                        rowNameField,
                    }},
                    UI.Panel { flexDirection = "column", gap = 1, children = {
                        UI.Label { text = "价格", fontSize = 9, fontColor = { 150, 150, 170, 255 } },
                        rowPriceField,
                        priceUnitLabel,
                    }},
                    UI.Panel { flexDirection = "column", gap = 1, children = {
                        UI.Label { text = "描述", fontSize = 9, fontColor = { 150, 150, 170, 255 } },
                        rowDescField,
                    }},
                    UI.Button {
                        text = "×",
                        fontSize = 12,
                        width = 24,
                        height = 24,
                        variant = "secondary",
                        marginTop = 12,
                        onClick = function()
                            table.remove(editItems, i)
                            RebuildItemRows()
                        end,
                    },
                },
            }

            -- 保存引用以便读取值
            item._nameField = rowNameField
            item._priceField = rowPriceField
            item._descField = rowDescField

            itemsContainer:AddChild(row)
        end
    end

    RebuildItemRows()

    -- 收集当前行值的辅助函数
    local function CollectCurrentRows()
        for _, item in ipairs(editItems) do
            if item._nameField then
                item.name = item._nameField:GetValue() or ""
                local p = item._priceField:GetValue() or "0"
                if p == "" then p = "0" end
                item.price = p
                item.desc = item._descField:GetValue() or ""
            end
        end
    end

    -- 添加商品/装备按钮
    local addBtnPanel = UI.Panel {
        flexDirection = "row", gap = 6, marginTop = 4,
        children = {
            UI.Button {
                text = "+ 添加商品",
                fontSize = 11,
                width = 90,
                height = 26,
                variant = "secondary",
                onClick = function()
                    CollectCurrentRows()
                    table.insert(editItems, { name = "", price = "0", desc = "" })
                    RebuildItemRows()
                end,
            },
            UI.Button {
                text = "+ 添加装备",
                fontSize = 11,
                width = 90,
                height = 26,
                variant = "primary",
                onClick = function()
                    CollectCurrentRows()
                    ShowEquipSelectDialog(editItems, RebuildItemRows)
                end,
            },
        },
    }
    table.insert(formChildren, addBtnPanel)

    -- 已有物品提示
    if #existingItems > 0 then
        local hint = "可用物品: " .. table.concat(existingItems, ", ")
        if #hint > 60 then hint = hint:sub(1, 60) .. "..." end
        table.insert(formChildren, UI.Label {
            text = hint,
            fontSize = 9,
            fontColor = { 120, 120, 150, 255 },
            marginTop = 2,
        })
    end

    -- 消息
    local dialogMsg = UI.Label {
        text = "",
        fontSize = 11,
        fontColor = { 100, 255, 100, 255 },
        textAlign = "center",
        height = 16,
    }
    table.insert(formChildren, dialogMsg)

    -- 按钮
    table.insert(formChildren, UI.Panel {
        flexDirection = "row",
        gap = 12,
        marginTop = 8,
        justifyContent = "center",
        children = {
            UI.Button {
                text = "保存",
                variant = "primary",
                width = 80,
                onClick = function()
                    local id = isNew and (fieldWidgets["id"]:GetValue() or "") or shopId
                    if isNew and id == "" then
                        dialogMsg:SetText("请输入商店ID")
                        return
                    end
                    local name = fieldWidgets["name"]:GetValue() or ""
                    if name == "" then name = id end

                    -- 收集商品行数据
                    local finalItems = {}
                    for _, item in ipairs(editItems) do
                        local n = item._nameField and item._nameField:GetValue() or item.name or ""
                        local p = item._priceField and item._priceField:GetValue() or item.price or "0"
                        if p == "" then p = "0" end
                        local d = item._descField and item._descField:GetValue() or item.desc or ""
                        if n ~= "" then
                            table.insert(finalItems, { name = n, price = p, desc = d })
                        end
                    end

                    DataManager.shops[id] = {
                        name = name,
                        desc = fieldWidgets["desc"]:GetValue() or "",
                        items = finalItems,
                    }
                    SaveCategoryToCloud("shops")
                    dialogMsg:SetText("已保存")
                    CloseDialog()
                    RenderShops()
                end,
            },
            UI.Button {
                text = "关闭",
                variant = "secondary",
                width = 80,
                onClick = function() CloseDialog() end,
            },
        },
    })

    editDialog_ = UI.Panel {
        width = "100%",
        height = "100%",
        position = "absolute",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        children = {
            UI.ScrollView {
                width = 400,
                maxHeight = 520,
                backgroundColor = { 30, 25, 55, 250 },
                borderRadius = 12,
                padding = 16,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "column",
                        gap = 4,
                        children = formChildren,
                    },
                },
            },
        },
    }
    if rootPanel_ then
        rootPanel_:AddChild(editDialog_)
    end
end

--- 渲染商店列表
RenderShops = function()
    ClearContent()
    contentPanel_:AddChild(CreateSearchBar("搜索商店名...", function() RenderShops() end))
    local count = 0
    for _ in pairs(DataManager.shops) do count = count + 1 end
    ShowMsg("共 " .. count .. " 家商店")

    local dataArray = {}
    for id, data in pairs(DataManager.shops) do
        if not MatchSearch(data.name or id) then goto continue_shops end
        local itemCount = #(data.items or {})
        local itemSummary = ""
        for i, item in ipairs(data.items or {}) do
            if i > 3 then itemSummary = itemSummary .. "..."; break end
            if i > 1 then itemSummary = itemSummary .. ", " end
            itemSummary = itemSummary .. item.name .. "(" .. item.price .. "金)"
        end
        if itemSummary == "" then itemSummary = "无商品" end

        table.insert(dataArray, {
            text = (data.name or id) .. "  [" .. itemCount .. "种商品]",
            subtext = itemSummary,
            onEdit = function()
                ShowShopEditDialog("编辑商店 - " .. (data.name or id), data, id, false)
            end,
            onDelete = function()
                DataManager.shops[id] = nil
                SaveCategoryToCloud("shops")
                RenderShops()
            end,
        })
        ::continue_shops::
    end
    contentPanel_:AddChild(CreateVirtualDataList(dataArray))

    contentPanel_:AddChild(UI.Panel {
        flexDirection = "row", gap = 8, marginTop = 8, marginLeft = 12,
        children = {
            UI.Button {
                text = "+ 添加商店",
                variant = "primary", width = 120,
                onClick = function()
                    ShowShopEditDialog("添加新商店", nil, nil, true)
                end,
            },
            UI.Button {
                text = "一键更新装备价格",
                variant = "secondary", width = 140,
                onClick = function()
                    local updatedCount = 0
                    for id, shopData in pairs(DataManager.shops) do
                        for _, item in ipairs(shopData.items or {}) do
                            local equipData = DataManager.GetEquipData(item.name)
                            if equipData and equipData.price_sell and equipData.price_sell ~= "" and equipData.price_sell ~= "0" then
                                if item.price ~= equipData.price_sell then
                                    item.price = equipData.price_sell
                                    updatedCount = updatedCount + 1
                                end
                            end
                        end
                    end
                    if updatedCount > 0 then
                        SaveCategoryToCloud("shops")
                        ShowMsg("已更新 " .. updatedCount .. " 件装备价格")
                    else
                        ShowMsg("所有装备价格已是最新")
                    end
                    RenderShops()
                end,
            },
        },
    })
end

-- =============== 系统商店管理 ===============

--- 显示系统商店编辑对话框
---@param title string
---@param data table|nil
---@param shopId string|nil
---@param isNew boolean
local function ShowSystemShopEditDialog(title, data, shopId, isNew)
    CloseDialog()
    data = data or { name = "", currency = "金币", desc = "", items = {} }

    local formChildren = {}
    local fieldWidgets = {}

    -- 标题
    table.insert(formChildren, UI.Label {
        text = title,
        fontSize = 16,
        fontColor = { 200, 170, 100, 255 },
        textAlign = "center",
        marginBottom = 8,
    })

    -- ID字段（仅新建时可编辑）
    if isNew then
        table.insert(formChildren, UI.Label { text = "商店ID:", fontSize = 12, fontColor = { 160, 160, 180, 255 } })
        fieldWidgets["id"] = UI.TextField { placeholder = "唯一ID，如 shop_gem", width = "100%", height = 32 }
        table.insert(formChildren, fieldWidgets["id"])
    end

    -- 名称
    table.insert(formChildren, UI.Label { text = "商店名称:", fontSize = 12, fontColor = { 160, 160, 180, 255 } })
    fieldWidgets["name"] = UI.TextField { value = data.name or "", placeholder = "商店名称", width = "100%", height = 32 }
    table.insert(formChildren, fieldWidgets["name"])

    -- 货币
    table.insert(formChildren, UI.Label { text = "使用货币:", fontSize = 12, fontColor = { 160, 160, 180, 255 } })
    fieldWidgets["currency"] = UI.TextField { value = data.currency or "金币", placeholder = "如：金币、钻石、积分", width = "100%", height = 32 }
    table.insert(formChildren, fieldWidgets["currency"])

    -- 描述
    table.insert(formChildren, UI.Label { text = "描述:", fontSize = 12, fontColor = { 160, 160, 180, 255 } })
    fieldWidgets["desc"] = UI.TextField { value = data.desc or "", placeholder = "商店描述(可选)", width = "100%", height = 32 }
    table.insert(formChildren, fieldWidgets["desc"])

    -- 商品列表
    table.insert(formChildren, UI.Label { text = "— 商品列表 —", fontSize = 13, fontColor = { 180, 150, 100, 255 }, textAlign = "center", marginTop = 8 })

    local editItems = {}
    for _, item in ipairs(data.items or {}) do
        table.insert(editItems, { name = item.name, price = item.price, desc = item.desc })
    end

    local itemListPanel = UI.Panel { width = "100%", flexDirection = "column", gap = 4 }

    local function RebuildItemList()
        itemListPanel:ClearChildren()
        for i, item in ipairs(editItems) do
            -- 价格单位标签（显示在价格输入框下方）
            local initP = (item.price == nil or item.price == "") and "0" or tostring(item.price)
            local pUnitLabel = UI.Label { text = NumFormat.Short(initP), fontSize = 9, fontColor = { 140, 200, 140, 255 }, marginTop = 1 }

            local nameField = UI.TextField { value = item.name or "", placeholder = "物品名", width = "40%", height = 28, fontSize = 11 }
            local priceField = UI.TextField {
                value = tostring(item.price or "0"), placeholder = "价格", width = "100%", height = 28, fontSize = 11,
                onChange = function(_, t)
                    local v = (t == nil or t == "") and "0" or t
                    pUnitLabel:SetText(NumFormat.Short(v))
                end,
            }
            local descField = UI.TextField { value = item.desc or "", placeholder = "描述", width = "25%", height = 28, fontSize = 11 }
            item._nameField = nameField
            item._priceField = priceField
            item._descField = descField

            itemListPanel:AddChild(UI.Panel {
                flexDirection = "row",
                width = "100%",
                gap = 3,
                alignItems = "flex-start",
                children = {
                    nameField,
                    UI.Panel { flexDirection = "column", width = "25%", children = { priceField, pUnitLabel } },
                    descField,
                    UI.Button {
                        text = "×", variant = "danger", width = 24, height = 24, fontSize = 12, marginTop = 3,
                        onClick = function()
                            table.remove(editItems, i)
                            RebuildItemList()
                        end,
                    },
                },
            })
        end
    end

    RebuildItemList()
    table.insert(formChildren, itemListPanel)

    -- 收集当前行值
    local function CollectSysRows()
        for _, item in ipairs(editItems) do
            if item._nameField then
                item.name = item._nameField:GetValue() or ""
                local p = item._priceField:GetValue() or "0"
                if p == "" then p = "0" end
                item.price = p
                item.desc = item._descField:GetValue() or ""
            end
        end
    end

    table.insert(formChildren, UI.Panel {
        flexDirection = "row", gap = 6, marginTop = 4,
        children = {
            UI.Button {
                text = "+ 添加商品", variant = "outline", width = 90, height = 26, fontSize = 11,
                onClick = function()
                    CollectSysRows()
                    table.insert(editItems, { name = "", price = "0", desc = "" })
                    RebuildItemList()
                end,
            },
            UI.Button {
                text = "+ 添加装备", variant = "primary", width = 90, height = 26, fontSize = 11,
                onClick = function()
                    CollectSysRows()
                    ShowEquipSelectDialog(editItems, RebuildItemList)
                end,
            },
        },
    })

    -- 状态消息
    local dialogMsg = UI.Label {
        text = "",
        fontSize = 11,
        fontColor = { 100, 255, 100, 255 },
        textAlign = "center",
        height = 16,
    }
    table.insert(formChildren, dialogMsg)

    -- 按钮
    table.insert(formChildren, UI.Panel {
        flexDirection = "row",
        gap = 12,
        marginTop = 8,
        justifyContent = "center",
        children = {
            UI.Button {
                text = "保存",
                variant = "primary",
                width = 80,
                onClick = function()
                    local id = isNew and (fieldWidgets["id"]:GetValue() or "") or shopId
                    if isNew and id == "" then
                        dialogMsg:SetText("请输入商店ID")
                        return
                    end
                    local name = fieldWidgets["name"]:GetValue() or ""
                    if name == "" then name = id end
                    local currency = fieldWidgets["currency"]:GetValue() or "金币"
                    if currency == "" then currency = "金币" end

                    -- 收集商品行数据
                    local finalItems = {}
                    for _, item in ipairs(editItems) do
                        local n = item._nameField and item._nameField:GetValue() or item.name or ""
                        local p = item._priceField and item._priceField:GetValue() or item.price or "0"
                        if p == "" then p = "0" end
                        local d = item._descField and item._descField:GetValue() or item.desc or ""
                        if n ~= "" then
                            table.insert(finalItems, { name = n, price = p, desc = d })
                        end
                    end

                    DataManager.systemShops[id] = {
                        name = name,
                        currency = currency,
                        desc = fieldWidgets["desc"]:GetValue() or "",
                        items = finalItems,
                    }
                    SaveCategoryToCloud("system_shops")
                    dialogMsg:SetText("已保存")
                    CloseDialog()
                    RenderSystemShops()
                end,
            },
            UI.Button {
                text = "关闭",
                variant = "secondary",
                width = 80,
                onClick = function() CloseDialog() end,
            },
        },
    })

    editDialog_ = UI.Panel {
        width = "100%",
        height = "100%",
        position = "absolute",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        children = {
            UI.ScrollView {
                width = 400,
                maxHeight = 520,
                backgroundColor = { 30, 25, 55, 250 },
                borderRadius = 12,
                padding = 16,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "column",
                        gap = 4,
                        children = formChildren,
                    },
                },
            },
        },
    }
    if rootPanel_ then
        rootPanel_:AddChild(editDialog_)
    end
end

--- 渲染系统商店列表
RenderSystemShops = function()
    ClearContent()
    contentPanel_:AddChild(CreateSearchBar("搜索系统商店名...", function() RenderSystemShops() end))
    local count = 0
    for _ in pairs(DataManager.systemShops) do count = count + 1 end
    ShowMsg("共 " .. count .. " 家系统商店")

    local dataArray = {}
    for id, data in pairs(DataManager.systemShops) do
        if not MatchSearch(data.name or id) then goto continue_sys_shops end
        local itemCount = #(data.items or {})
        local currency = data.currency or "金币"
        local itemSummary = "货币:" .. currency .. " | "
        for i, item in ipairs(data.items or {}) do
            if i > 3 then itemSummary = itemSummary .. "..."; break end
            if i > 1 then itemSummary = itemSummary .. ", " end
            itemSummary = itemSummary .. item.name .. "(" .. item.price .. currency .. ")"
        end
        if itemCount == 0 then itemSummary = "货币:" .. currency .. " | 无商品" end

        table.insert(dataArray, {
            text = (data.name or id) .. "  [" .. itemCount .. "种商品]",
            subtext = itemSummary,
            onEdit = function()
                ShowSystemShopEditDialog("编辑系统商店 - " .. (data.name or id), data, id, false)
            end,
            onDelete = function()
                DataManager.systemShops[id] = nil
                SaveCategoryToCloud("system_shops")
                RenderSystemShops()
            end,
        })
        ::continue_sys_shops::
    end
    contentPanel_:AddChild(CreateVirtualDataList(dataArray))

    contentPanel_:AddChild(UI.Button {
        text = "+ 添加系统商店",
        variant = "primary", width = 140, marginTop = 8, marginLeft = 12,
        onClick = function()
            ShowSystemShopEditDialog("添加新系统商店", nil, nil, true)
        end,
    })
end

--- 渲染副本列表
local function RenderDungeons()
    ClearContent()
    contentPanel_:AddChild(CreateSearchBar("搜索副本名...", function() RenderDungeons() end))
    local count = 0
    for _ in pairs(DataManager.dungeons) do count = count + 1 end
    ShowMsg("共 " .. count .. " 个副本")

    local dataArray = {}
    for id, data in pairs(DataManager.dungeons) do
        if not MatchSearch(data.name or id) then goto continue_dungeons end
        table.insert(dataArray, {
            text = data.name or id,
            subtext = "等级:" .. (data.level_req or 0) .. " 波数:" .. (data.waves or 0) .. " 首领:" .. (data.boss or "无"),
            onEdit = function()
                local waveCount = tonumber(data.waves) or 1
                local function openDungeonEdit(editData, numWaves)
                    local fields = {
                        { label = "名称", key = "name", value = editData.name },
                        { label = "描述", key = "desc", value = editData.desc, opts = { width = 220 } },
                        { label = "等级需求", key = "level_req", value = editData.level_req },
                        { label = "首领", key = "boss", value = editData.boss },
                        { label = "奖励经验", key = "reward_exp", value = editData.reward_exp },
                        { label = "奖励金币", key = "reward_gold", value = editData.reward_gold },
                        { label = "奖励物品", key = "reward_items", value = editData.reward_items, opts = { width = 220 } },
                    }
                    -- 动态波次字段
                    for i = 1, numWaves do
                        table.insert(fields, { label = "第" .. i .. "波", key = "wave_" .. i, value = editData["wave_" .. i] or "", opts = { width = 220, placeholder = "怪物,怪物,..." } })
                    end
                    -- 添加/删除波次按钮
                    table.insert(fields, {
                        type = "action",
                        buttons = {
                            UI.Button {
                                text = "+ 添加波次",
                                variant = "primary",
                                width = 100,
                                onClick = function()
                                    -- 收集当前输入值后重新打开
                                    local cur = {}
                                    for k, w in pairs(editDialog_ and editDialog_._fieldWidgets or {}) do
                                        cur[k] = w:GetValue() or ""
                                    end
                                    -- 合并到 editData
                                    for k, v in pairs(cur) do editData[k] = v end
                                    openDungeonEdit(editData, numWaves + 1)
                                end,
                            },
                            UI.Button {
                                text = "- 删除最后波",
                                variant = "danger",
                                width = 100,
                                disabled = numWaves <= 1,
                                onClick = function()
                                    local cur = {}
                                    for k, w in pairs(editDialog_ and editDialog_._fieldWidgets or {}) do
                                        cur[k] = w:GetValue() or ""
                                    end
                                    for k, v in pairs(cur) do editData[k] = v end
                                    editData["wave_" .. numWaves] = nil
                                    openDungeonEdit(editData, numWaves - 1)
                                end,
                            },
                        },
                    })
                    ShowEditDialog("编辑副本 - " .. id .. " (波数:" .. numWaves .. ")", fields, function(v)
                        local entry = {
                            name = v.name, desc = v.desc,
                            level_req = v.level_req or "1", waves = tostring(numWaves),
                            boss = v.boss,
                            reward_exp = v.reward_exp or "0", reward_gold = v.reward_gold or "0",
                            reward_items = v.reward_items,
                        }
                        for i = 1, numWaves do
                            entry["wave_" .. i] = v["wave_" .. i] or ""
                        end
                        DataManager.dungeons[id] = entry
                        SaveCategoryToCloud("dungeons")
                        CloseDialog()
                        RenderDungeons()
                    end)
                end
                openDungeonEdit(data, waveCount)
            end,
            onDelete = function()
                DataManager.dungeons[id] = nil
                SaveCategoryToCloud("dungeons")
                RenderDungeons()
            end,
        })
        ::continue_dungeons::
    end
    contentPanel_:AddChild(CreateVirtualDataList(dataArray))

    contentPanel_:AddChild(UI.Button {
        text = "+ 添加副本",
        variant = "primary", width = 120, marginTop = 8, marginLeft = 12,
        onClick = function()
            local function openDungeonAdd(addData, numWaves)
                local fields = {
                    { label = "副本ID", key = "id", value = addData.id or "", opts = { placeholder = "如: dungeon_006" } },
                    { label = "名称", key = "name", value = addData.name or "" },
                    { label = "描述", key = "desc", value = addData.desc or "", opts = { width = 220 } },
                    { label = "等级需求", key = "level_req", value = addData.level_req or "5" },
                    { label = "首领", key = "boss", value = addData.boss or "" },
                    { label = "奖励经验", key = "reward_exp", value = addData.reward_exp or "50" },
                    { label = "奖励金币", key = "reward_gold", value = addData.reward_gold or "80" },
                    { label = "奖励物品", key = "reward_items", value = addData.reward_items or "", opts = { width = 220 } },
                }
                for i = 1, numWaves do
                    table.insert(fields, { label = "第" .. i .. "波", key = "wave_" .. i, value = addData["wave_" .. i] or "", opts = { width = 220, placeholder = "怪物,怪物,..." } })
                end
                table.insert(fields, {
                    type = "action",
                    buttons = {
                        UI.Button {
                            text = "+ 添加波次",
                            variant = "primary",
                            width = 100,
                            onClick = function()
                                local cur = {}
                                for k, w in pairs(editDialog_ and editDialog_._fieldWidgets or {}) do
                                    cur[k] = w:GetValue() or ""
                                end
                                for k, v in pairs(cur) do addData[k] = v end
                                openDungeonAdd(addData, numWaves + 1)
                            end,
                        },
                        UI.Button {
                            text = "- 删除最后波",
                            variant = "danger",
                            width = 100,
                            disabled = numWaves <= 1,
                            onClick = function()
                                local cur = {}
                                for k, w in pairs(editDialog_ and editDialog_._fieldWidgets or {}) do
                                    cur[k] = w:GetValue() or ""
                                end
                                for k, v in pairs(cur) do addData[k] = v end
                                addData["wave_" .. numWaves] = nil
                                openDungeonAdd(addData, numWaves - 1)
                            end,
                        },
                    },
                })
                ShowEditDialog("添加副本 (波数:" .. numWaves .. ")", fields, function(v)
                    if v.id == "" then return end
                    local entry = {
                        name = v.name, desc = v.desc,
                        level_req = v.level_req or "1", waves = tostring(numWaves),
                        boss = v.boss,
                        reward_exp = v.reward_exp or "0", reward_gold = v.reward_gold or "0",
                        reward_items = v.reward_items,
                    }
                    for i = 1, numWaves do
                        entry["wave_" .. i] = v["wave_" .. i] or ""
                    end
                    DataManager.dungeons[v.id] = entry
                    SaveCategoryToCloud("dungeons")
                    CloseDialog()
                    RenderDungeons()
                end)
            end
            openDungeonAdd({}, 3)
        end,
    })
end

--- 渲染NPC列表
local function RenderNPCs()
    ClearContent()
    contentPanel_:AddChild(CreateSearchBar("搜索NPC名...", function() RenderNPCs() end))
    local count = 0
    for _ in pairs(DataManager.npcs) do count = count + 1 end
    ShowMsg("共 " .. count .. " 个NPC")

    local dataArray = {}
    for id, data in pairs(DataManager.npcs) do
        if not MatchSearch(data.name or id) then goto continue_npcs end
        table.insert(dataArray, {
            text = data.name or id,
            subtext = "类型:" .. NpcTypeToCN(data.type or "任务") .. " 地点:" .. (data.location or ""),
            onEdit = function()
                local fields = {
                    { label = "名称", key = "name", value = data.name },
                    { label = "类型", key = "type", value = data.type, opts = { placeholder = "任务/商人/师傅" } },
                    { label = "对话", key = "dialog", value = data.dialog, opts = { width = 250 } },
                    { label = "所在地", key = "location", value = data.location },
                }
                if data.type == "商人" or data.type == "merchant" then
                    table.insert(fields, { label = "商店编号", key = "shop_id", value = data.shop_id or "" })
                else
                    table.insert(fields, { label = "任务编号", key = "quest_id", value = data.quest_id or "" })
                end
                ShowEditDialog("编辑NPC - " .. id, fields, function(v)
                    local entry = {
                        name = v.name, type = v.type, dialog = v.dialog, location = v.location,
                    }
                    if v.type == "商人" or v.type == "merchant" then
                        entry.shop_id = v.shop_id or ""
                    else
                        entry.quest_id = v.quest_id or ""
                    end
                    DataManager.npcs[id] = entry
                    SaveCategoryToCloud("npcs")
                    CloseDialog()
                    RenderNPCs()
                end)
            end,
            onDelete = function()
                DataManager.npcs[id] = nil
                SaveCategoryToCloud("npcs")
                RenderNPCs()
            end,
        })
        ::continue_npcs::
    end
    contentPanel_:AddChild(CreateVirtualDataList(dataArray))

    contentPanel_:AddChild(UI.Button {
        text = "+ 添加NPC",
        variant = "primary", width = 120, marginTop = 8, marginLeft = 12,
        onClick = function()
            ShowEditDialog("添加NPC", {
                { label = "NPC名称", key = "id", value = "" },
                { label = "类型", key = "type", value = "任务", opts = { placeholder = "任务/商人/师傅" } },
                { label = "对话", key = "dialog", value = "", opts = { width = 250 } },
                { label = "所在地", key = "location", value = "" },
                { label = "任务编号", key = "quest_id", value = "", opts = { placeholder = "如: 支线_001" } },
                { label = "商店编号", key = "shop_id", value = "", opts = { placeholder = "如: 杂货铺" } },
            }, function(v)
                if v.id == "" then return end
                local entry = {
                    name = v.id, type = v.type, dialog = v.dialog, location = v.location,
                }
                if v.type == "商人" or v.type == "merchant" then
                    entry.shop_id = v.shop_id or ""
                else
                    entry.quest_id = v.quest_id or ""
                end
                DataManager.npcs[v.id] = entry
                SaveCategoryToCloud("npcs")
                CloseDialog()
                RenderNPCs()
            end)
        end,
    })
end

-- =============== 礼包管理 ===============

local function RenderGiftPacks()
    ClearContent()
    contentPanel_:AddChild(CreateSearchBar("搜索礼包名/兑换码...", function() RenderGiftPacks() end))
    local count = 0
    for _ in pairs(DataManager.giftpacks) do count = count + 1 end
    ShowMsg("共 " .. count .. " 个礼包（兑换码即为礼包ID）")

    local dataArray = {}
    for id, data in pairs(DataManager.giftpacks) do
        if not MatchSearch(data.name or id) and not MatchSearch(id) then goto continue_giftpacks end
        local usesText = BigNum.gt(data.max_uses or "0", "0")
            and ("已用" .. (data.used_count or "0") .. "/" .. data.max_uses)
            or ("已用" .. (data.used_count or "0") .. "/无限")
        table.insert(dataArray, {
            text = data.name or id,
            subtext = "兑换码:" .. id .. " " .. usesText,
            onEdit = function()
                ShowEditDialog("编辑礼包 - " .. id, {
                    { label = "名称", key = "name", value = data.name },
                    { label = "描述", key = "desc", value = data.desc, opts = { width = 220 } },
                    { label = "奖励物品", key = "reward_items", value = data.reward_items, opts = { width = 220, placeholder = "物品名:数量,物品名:数量" } },
                    { label = "奖励金币", key = "reward_gold", value = data.reward_gold },
                    { label = "奖励经验", key = "reward_exp", value = data.reward_exp },
                    { label = "最大使用次数", key = "max_uses", value = data.max_uses, opts = { placeholder = "0=无限" } },
                    { label = "已使用次数", key = "used_count", value = data.used_count },
                }, function(v)
                    DataManager.giftpacks[id] = {
                        name = v.name, desc = v.desc,
                        reward_items = v.reward_items,
                        reward_gold = v.reward_gold or "0",
                        reward_exp = v.reward_exp or "0",
                        max_uses = v.max_uses or "0",
                        used_count = v.used_count or "0",
                    }
                    SaveCategoryToCloud("giftpacks")
                    CloseDialog()
                    RenderGiftPacks()
                end)
            end,
            onDelete = function()
                DataManager.giftpacks[id] = nil
                SaveCategoryToCloud("giftpacks")
                RenderGiftPacks()
            end,
        })
        ::continue_giftpacks::
    end
    contentPanel_:AddChild(CreateVirtualDataList(dataArray))

    contentPanel_:AddChild(UI.Button {
        text = "+ 添加礼包",
        variant = "primary", width = 120, marginTop = 8, marginLeft = 12,
        onClick = function()
            ShowEditDialog("添加礼包", {
                { label = "兑换码", key = "id", value = "", opts = { placeholder = "玩家输入此码兑换" } },
                { label = "名称", key = "name", value = "" },
                { label = "描述", key = "desc", value = "", opts = { width = 220 } },
                { label = "奖励物品", key = "reward_items", value = "", opts = { width = 220, placeholder = "物品名:数量,物品名:数量" } },
                { label = "奖励金币", key = "reward_gold", value = "100" },
                { label = "奖励经验", key = "reward_exp", value = "50" },
                { label = "最大使用次数", key = "max_uses", value = "0", opts = { placeholder = "0=无限" } },
            }, function(v)
                if v.id == "" then return end
                DataManager.giftpacks[v.id] = {
                    name = v.name ~= "" and v.name or v.id,
                    desc = v.desc,
                    reward_items = v.reward_items,
                    reward_gold = v.reward_gold or "0",
                    reward_exp = v.reward_exp or "0",
                    max_uses = v.max_uses or "0",
                    used_count = "0",
                }
                SaveCategoryToCloud("giftpacks")
                CloseDialog()
                RenderGiftPacks()
            end)
        end,
    })
end



-- =============== 坐骑管理 ===============

local editingMount_ = nil  -- 当前正在编辑的坐骑名(nil=列表模式)
local RenderMountEdit      -- 前向声明(RenderMounts 内部调用)

--- 保存坐骑配置到云端
local function SaveMountsToCloud(onDone)
    local sections = {}
    for name, m in pairs(DataManager.mounts) do
        sections[name] = {
            ["名称"] = m.name or name,
            ["类型"] = m.type or "不可传送",
            ["可传送地图"] = table.concat(m.maps or {}, ","),
            ["攻击"] = m.atk or "0",
            ["防御"] = m.def or "0",
            ["生命上限"] = m.hp or "0",
            ["经验倍率"] = m.exp_rate or "0",
            ["货币倍率"] = m.gold_rate or "0",
        }
    end
    local content = IniParser.Serialize(sections)
    SaveConfigToCloud("系统配置/mounts.ini", content, onDone)
end

--- 渲染坐骑管理主界面
local function RenderMounts()
    ClearContent()
    if not contentPanel_ then return end

    -- 编辑模式
    if editingMount_ then
        RenderMountEdit(editingMount_)
        return
    end

    -- 列表模式
    local children = {}
    children[#children + 1] = UI.Label {
        text = "— 坐骑管理 —", fontSize = 16, fontColor = { 200, 170, 100, 255 },
        textAlign = "center", marginTop = 8, marginBottom = 8,
    }
    children[#children + 1] = UI.Button {
        text = "+ 添加坐骑", variant = "primary", width = "100%", height = 34, marginBottom = 8,
        onClick = function()
            ShowEditDialog("新增坐骑", {
                { key = "name", label = "坐骑名称", default = "" },
            }, function(values)
                local n = values["name"] or ""
                if n == "" then ShowMsg("请输入坐骑名称"); return end
                if DataManager.mounts[n] then ShowMsg("坐骑「" .. n .. "」已存在"); return end
                DataManager.mounts[n] = { name = n, type = "不可传送", maps = {}, atk = "0", def = "0", hp = "0", exp_rate = "0", gold_rate = "0" }
                SaveMountsToCloud(function() ShowMsg("已添加坐骑「" .. n .. "」"); RenderMounts() end)
            end)
        end,
    }

    -- 坐骑列表
    local typeColors = { ["不可传送"] = {150,150,150,255}, ["部分传送"] = {100,180,255,255}, ["全图传送"] = {100,255,150,255} }
    local sortedNames = {}
    for name in pairs(DataManager.mounts) do sortedNames[#sortedNames + 1] = name end
    table.sort(sortedNames)

    for _, name in ipairs(sortedNames) do
        local m = DataManager.mounts[name]
        local tc = typeColors[m.type] or {180,180,180,255}
        children[#children + 1] = UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            gap = 6, marginBottom = 4, padding = 4, borderRadius = 4,
            backgroundColor = { 35, 30, 50, 200 },
            children = {
                UI.Label { text = name, fontSize = 12, fontColor = {220,210,170,255}, flexGrow = 1 },
                UI.Label { text = tostring(m.type or "不可传送"), fontSize = 10, fontColor = tc },
                UI.Button { text = "编辑", fontSize = 10, width = 50, height = 26, variant = "primary",
                    onClick = function() editingMount_ = name; RenderMounts() end },
                UI.Button { text = "删除", fontSize = 10, width = 50, height = 26, variant = "danger",
                    onClick = function()
                        DataManager.mounts[name] = nil
                        SaveMountsToCloud(function() ShowMsg("已删除坐骑「" .. name .. "」"); RenderMounts() end)
                    end },
            },
        }
    end

    if #sortedNames == 0 then
        children[#children + 1] = UI.Label { text = "暂无坐骑配置", fontSize = 12, fontColor = {120,120,140,255}, textAlign = "center", marginTop = 20 }
    end

    contentPanel_:AddChild(UI.ScrollView {
        width = "100%", height = "100%",
        children = { UI.Panel { width = "100%", flexDirection = "column", padding = 12, children = children } },
    })
end

--- 渲染坐骑编辑界面
---@param mountName string
function RenderMountEdit(mountName)
    ClearContent()
    if not contentPanel_ then return end

    local m = DataManager.mounts[mountName]
    if not m then editingMount_ = nil; RenderMounts(); return end

    local MOUNT_TYPES = { "不可传送", "部分传送", "全图传送" }
    local children = {}

    -- 标题 + 返回
    children[#children + 1] = UI.Panel { width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 8, children = {
        UI.Button { text = "← 返回", variant = "secondary", height = 28, onClick = function() editingMount_ = nil; RenderMounts() end },
        UI.Label { text = "  编辑坐骑：" .. mountName, fontSize = 14, fontColor = {200,170,100,255}, flexGrow = 1 },
    }}

    -- 类型选择器
    local typePanel, getType = CreateButtonSelector(MOUNT_TYPES, m.type or "不可传送", "类型", false)
    children[#children + 1] = typePanel

    -- 属性区(flexWrap 自动换行,每个属性 = 标签+输入框+单位)
    local attrDefs = {
        { key = "atk",       label = "攻击",     unit = "点",  value = m.atk },
        { key = "def",       label = "防御",     unit = "点",  value = m.def },
        { key = "hp",        label = "生命上限", unit = "点",  value = m.hp },
        { key = "exp_rate",  label = "经验倍率", unit = "倍",  value = m.exp_rate },
        { key = "gold_rate", label = "货币倍率", unit = "倍",  value = m.gold_rate },
    }
    local attrFields = {}
    local attrChildren = {}
    for _, a in ipairs(attrDefs) do
        local field = UI.TextField { value = a.value or "0", width = 70, height = 28, fontSize = 11 }
        attrFields[a.key] = field
        attrChildren[#attrChildren + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 2, marginRight = 8, marginBottom = 4,
            children = {
                UI.Label { text = a.label, fontSize = 11, fontColor = {180,180,200,255} },
                field,
                UI.Label { text = a.unit, fontSize = 10, fontColor = {140,140,160,255} },
            },
        }
    end
    children[#children + 1] = UI.Label { text = "属性加成:", fontSize = 12, fontColor = {160,160,180,255}, marginTop = 6, marginBottom = 2 }
    children[#children + 1] = UI.Panel {
        width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 4,
        children = attrChildren,
    }

    -- 部分传送地图管理(仅 type="部分传送" 时相关,但始终显示方便切换)
    children[#children + 1] = UI.Label { text = "可传送地图(部分传送生效):", fontSize = 12, fontColor = {160,160,180,255}, marginTop = 10, marginBottom = 2 }

    -- 搜索框
    local searchField = UI.TextField { placeholder = "搜索地图名...", width = "100%", height = 30, fontSize = 11 }
    children[#children + 1] = searchField

    -- 已选地图列表(每个有删除按钮)
    local selectedMaps = m.maps or {}
    local selectedChildren = {}
    for i, mapName in ipairs(selectedMaps) do
        selectedChildren[#selectedChildren + 1] = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4, marginBottom = 2,
            children = {
                UI.Label { text = "✓ " .. mapName, fontSize = 11, fontColor = {100,255,150,255}, flexGrow = 1 },
                UI.Button { text = "移除", fontSize = 9, width = 42, height = 22, variant = "danger",
                    onClick = function()
                        table.remove(selectedMaps, i)
                        m.maps = selectedMaps
                        RenderMountEdit(mountName)
                    end },
            },
        }
    end
    if #selectedChildren > 0 then
        children[#children + 1] = UI.Panel {
            width = "100%", flexDirection = "column",
            borderRadius = 4, padding = 4, marginTop = 4, backgroundColor = {25,35,25,180},
            children = selectedChildren,
        }
    end

    -- 可添加地图列表(虚拟列表:从 DataManager.maps 获取所有地图,排除已选,支持搜索)
    local allMapNames = {}
    for mapName in pairs(DataManager.maps) do
        -- 排除已选
        local already = false
        for _, s in ipairs(selectedMaps) do if s == mapName then already = true; break end end
        if not already then allMapNames[#allMapNames + 1] = mapName end
    end
    table.sort(allMapNames)

    -- 搜索过滤逻辑:onChange 时重渲染(简化:保存搜索词到 upvalue,用 ScrollView + 只渲染匹配项)
    -- 由于需动态过滤,用 VirtualList 组件 或 普通列表(地图数通常<100,普通列表可接受)
    local mapListPanel = UI.Panel { width = "100%", flexDirection = "column", marginTop = 4 }
    local function RefreshMapList(keyword)
        mapListPanel:ClearChildren()
        local kw = (keyword or ""):lower()
        local count = 0
        for _, mapName in ipairs(allMapNames) do
            if kw == "" or mapName:lower():find(kw, 1, true) then
                count = count + 1
                if count > 50 then break end -- 限制显示数量避免卡顿
                mapListPanel:AddChild(UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4, marginBottom = 2,
                    children = {
                        UI.Label { text = mapName, fontSize = 11, fontColor = {180,180,200,255}, flexGrow = 1 },
                        UI.Button { text = "选择", fontSize = 9, width = 42, height = 22, variant = "primary",
                            onClick = function()
                                selectedMaps[#selectedMaps + 1] = mapName
                                m.maps = selectedMaps
                                RenderMountEdit(mountName)
                            end },
                    },
                })
            end
        end
        if count == 0 then
            mapListPanel:AddChild(UI.Label { text = "(无匹配地图)", fontSize = 11, fontColor = {120,120,140,255} })
        end
    end
    RefreshMapList("")
    searchField.props.onChange = function(self, value) RefreshMapList(value) end
    children[#children + 1] = mapListPanel

    -- 保存按钮
    children[#children + 1] = UI.Panel { width = "100%", flexDirection = "row", gap = 8, marginTop = 12, children = {
        UI.Button { text = "保存", variant = "primary", height = 34, flexGrow = 1,
            onClick = function()
                m.type = getType()
                m.atk = attrFields["atk"]:GetValue() or "0"
                m.def = attrFields["def"]:GetValue() or "0"
                m.hp = attrFields["hp"]:GetValue() or "0"
                m.exp_rate = attrFields["exp_rate"]:GetValue() or "0"
                m.gold_rate = attrFields["gold_rate"]:GetValue() or "0"
                m.maps = selectedMaps
                DataManager.mounts[mountName] = m
                SaveMountsToCloud(function()
                    ShowMsg("坐骑「" .. mountName .. "」已保存")
                    editingMount_ = nil
                    RenderMounts()
                end)
            end },
        UI.Button { text = "取消", variant = "secondary", height = 34, width = 70,
            onClick = function() editingMount_ = nil; RenderMounts() end },
    }}

    contentPanel_:AddChild(UI.ScrollView {
        width = "100%", height = "100%",
        children = { UI.Panel { width = "100%", flexDirection = "column", padding = 12, children = children } },
    })
end

-- =============== 一键生成 ===============

-- 修仙主题名称库
local GEN_NAMES = {
    map_prefix = { "灵", "玄", "幽", "天", "冥", "紫", "苍", "碧", "赤", "金", "翠", "墨", "银", "血", "星" },
    map_suffix = { "峰", "谷", "渊", "林", "泽", "洞", "原", "崖", "岛", "海", "域", "殿", "塔", "城", "池" },
    map_desc_prefix = { "灵气充沛的", "危机四伏的", "云雾缭绕的", "充满神秘气息的", "传说中的", "被遗忘的", "古老的", "荒芜的" },
    monster_prefix = { "炎", "冰", "雷", "风", "毒", "暗", "光", "石", "铁", "血", "骨", "魂", "幽", "狂", "妖" },
    monster_suffix = { "蛟", "蟒", "狼", "熊", "鹰", "蝎", "蜂", "猿", "虎", "豹", "蛛", "龟", "鹤", "凤", "龙" },
    equip_prefix = { "烈焰", "寒冰", "紫电", "玄铁", "碧玉", "金刚", "幽冥", "天蚕", "赤霄", "青莲", "星辰", "混沌" },
    equip_weapon = { "剑", "刀", "枪", "戟", "斧", "锤", "鞭", "杖", "扇", "琴" },
    equip_helmet = { "冠", "盔", "面具", "兜", "发簪", "额饰" },
    equip_armor = { "甲", "袍", "衣", "铠", "战袍", "天衣" },
    equip_bracer = { "护腕", "臂环", "腕甲", "护手", "灵袖", "缚灵带" },
    equip_belt = { "腰带", "玉带", "锁链", "束腰", "灵绳", "仙带" },
    equip_boots = { "战靴", "云履", "踏风靴", "灵步鞋", "天行靴", "飞羽靴" },
    equip_cloak = { "披风", "斗篷", "羽衣", "灵袍", "仙衣", "天幕" },
    equip_necklace = { "链", "坠", "珠串", "灵珠", "仙坠", "神链" },
    equip_ring = { "戒", "环", "指轮", "灵戒", "天环", "命戒" },
    equip_artifact = { "塔", "印", "镜", "铃", "葫芦", "玉如意" },
    equip_wings = { "灵翼", "羽翅", "龙翼", "凤翅", "光翼", "魔翼" },
    equip_shield = { "盾", "壁", "龟甲", "灵壁", "天盾", "圣壁" },
    item_prefix = { "灵", "仙", "妖", "魔", "圣", "玄", "冰", "火", "雷", "风" },
    item_consumable = { "丹", "散", "露", "液", "果", "膏" },
    item_material = { "石", "晶", "粉", "精", "髓", "核", "翎", "鳞", "角", "牙" },
    dungeon_prefix = { "远古", "蛮荒", "上古", "太虚", "九幽", "混沌", "万妖", "天魔", "神秘", "禁忌" },
    dungeon_suffix = { "秘境", "遗迹", "禁地", "魔窟", "试炼场", "战场", "深渊", "迷宫", "圣地", "仙府" },
    shop_prefix = { "百宝", "万灵", "天机", "玄妙", "灵宝", "仙缘", "宝源", "聚仙", "星辰", "紫霄" },
    shop_suffix = { "阁", "坊", "铺", "堂", "轩", "庄", "楼", "斋", "馆", "居" },
}

--- 从表中随机取一个元素
local function RandPick(tbl)
    return tbl[math.random(1, #tbl)]
end

--- 名字拓展字池（修仙风格单字，用于名池用尽后自动拼接拓展）
local NAME_EXTEND_CHARS = {
    "玄", "幽", "灵", "魂", "星", "月", "风", "雷",
    "冰", "炎", "天", "地", "云", "霜", "岚", "渊",
    "紫", "碧", "苍", "翠", "金", "银", "墨", "丹",
    "隐", "虚", "真", "妙", "古", "寒", "烈", "圣",
}

--- 重试取名（无限模式）：
--- Phase1: 用 nameFn 生成随机名，重试 maxRetry 次
--- Phase2: 若仍冲突，对最后一次生成的基础名追加拓展字，逐级加长直到唯一
--- 理论上不会返回 nil（拓展字池^10 级 = 万亿级组合）
local function TryUniqueName(nameFn, existingTable, maxRetry)
    maxRetry = maxRetry or 50
    local baseName
    -- Phase1: 纯随机重试
    for _ = 1, maxRetry do
        baseName = nameFn()
        if not existingTable[baseName] then return baseName end
    end
    -- Phase2: 基础名池用尽，追加拓展字
    local extPool = NAME_EXTEND_CHARS
    local extLen = #extPool
    -- 逐级增加拓展字数（1字、2字、3字...最多10级）
    for level = 1, 10 do
        -- 每级尝试 maxRetry 次随机组合
        for _ = 1, maxRetry do
            local ext = ""
            for _ = 1, level do
                ext = ext .. extPool[math.random(1, extLen)]
            end
            local candidate = baseName .. ext
            if not existingTable[candidate] then return candidate end
        end
    end
    -- 理论不可达（32^10 > 1万亿种组合），兜底返回时间戳名
    return baseName .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(10000, 99999))
end



--- 生成地图数据
---@param count number
---@return number generated, number skipped
local function GenerateMaps(count)
    local existingMaps = {}
    for id in pairs(DataManager.maps) do
        table.insert(existingMaps, id)
    end
    local generated = 0
    local skipped = 0
    for i = 1, count do
        local name = TryUniqueName(function()
            return RandPick(GEN_NAMES.map_prefix) .. RandPick(GEN_NAMES.map_suffix)
        end, DataManager.maps)
        if not name then skipped = skipped + 1; goto map_continue end
        local desc = RandPick(GEN_NAMES.map_desc_prefix) .. name .. "，修仙者的历练之地"
        local lvReq = tostring(math.random(1, 15))
        DataManager.maps[name] = {
            name = name,
            desc = desc,
            monsters = "",
            npcs = "",
            front = "",
            back = "",
            left = "",
            right = "",
            level_req = lvReq,
        }
        table.insert(existingMaps, name)
        generated = generated + 1
        ::map_continue::
    end
    SaveCategoryToCloud("maps")
    return generated, skipped
end

--- 在BigNum区间 [minStr, maxStr] 内生成随机数
---@param minStr string
---@param maxStr string
---@return string
local function BigNumRandRange(minStr, maxStr)
    -- 保护：如果 min >= max，直接返回 min
    if minStr == maxStr then return minStr end
    if BigNum.gt(minStr, maxStr) then return minStr end
    -- 如果数字足够小，用 math.random
    local minN = tonumber(minStr)
    local maxN = tonumber(maxStr)
    if minN and maxN and maxN <= 2000000000 then
        local lo = math.floor(minN)
        local hi = math.floor(maxN)
        if lo > hi then return tostring(lo) end
        return tostring(math.random(lo, hi))
    end
    -- 大数：用 BigNum 做区间内随机
    -- 计算 range = max - min
    local range = BigNum.sub(maxStr, minStr)
    -- 取 range 的位数，然后生成随机系数 0.0~1.0 映射
    local digits = #range
    -- 生成一个 digits 位的随机数
    local result = ""
    for d = 1, digits do
        result = result .. tostring(math.random(0, 9))
    end
    -- 去掉前导零
    result = result:gsub("^0+", "")
    if result == "" then result = "0" end
    -- 如果随机数 > range，取模
    if BigNum.gt(result, range) then
        -- 简单处理：随机系数按比例缩放
        local halfRange = BigNum.div(range, "2")
        result = BigNum.add(halfRange, BigNum.div(result, tostring(digits)))
        if BigNum.gt(result, range) then
            result = range
        end
    end
    return BigNum.add(minStr, result)
end

---@param count number
---@param monsterType number 怪物类型索引（1~7）
local function GenerateMonsters(count, monsterType)
    local typeIdx = monsterType or 1
    if typeIdx < 1 then typeIdx = 1 end
    if typeIdx > #MONSTER_TYPES then typeIdx = #MONSTER_TYPES end
    local mtype = MONSTER_TYPES[typeIdx]

    local generated = 0
    local skipped = 0
    for i = 1, count do
        local name = TryUniqueName(function()
            return RandPick(GEN_NAMES.monster_prefix) .. RandPick(GEN_NAMES.monster_suffix)
        end, DataManager.monsters)
        if not name then skipped = skipped + 1; goto monster_continue end
        local hp = BigNumRandRange(mtype.min_hp or "10", mtype.max_hp or "2000")
        local atk = BigNumRandRange(mtype.min_atk or "5", mtype.max_atk or "1000")
        local def = BigNumRandRange(mtype.min_def or "3", mtype.max_def or "800")
        local exp = BigNumRandRange(mtype.min_exp or "5", mtype.max_exp or "500")
        -- 货币：取第一种货币的区间作为 gold（向后兼容），同时存储所有货币掉落
        local gold = "0"
        local currDrops = {}
        if mtype.currency_ranges then
            for cName, cRange in pairs(mtype.currency_ranges) do
                local val = BigNumRandRange(cRange.min or "0", cRange.max or "0")
                currDrops[cName] = val
                if gold == "0" then gold = val end -- 兼容 gold 字段
            end
        end
        DataManager.monsters[name] = {
            name = name,
            type = mtype.name,
            desc = "一只" .. mtype.name .. "级的" .. name .. "，" .. mtype.desc,
            hp = hp,
            atk = atk,
            def = def,
            exp = exp,
            gold = gold,
            currency_drops = currDrops,
            drops = "",
        }
        generated = generated + 1
        ::monster_continue::
    end
    SaveCategoryToCloud("monsters")
    return generated, skipped
end

--- 装备部位映射(引用共享模块,管理员自定义同步)
local EQUIP_SLOT_MAP = EquipSlots.cnToKey

--- 装备品质属性区间定义（min~max）
local EQUIP_QUALITY_RANGES = {
    ["白色"]   = { min = "100",               max = "3000" },
    ["绿色"]   = { min = "10000",             max = "60000" },
    ["橙色"]   = { min = "700000",            max = "1000000" },
    ["红色"]   = { min = "5000000",           max = "100000000" },
    ["彩色"]   = { min = "500000000",         max = "1000000000000" },
    ["地级"]   = { min = "2000000000000",     max = "5000000000000" },
    ["天级"]   = { min = "6000000000000",     max = "50000000000000" },
    ["帝级"]   = { min = "100000000000000",   max = "2000000000000000" },
    ["仙级"]   = { min = "5000000000000000",  max = "70000000000000000" },
    ["神级"]   = { min = "100000000000000000", max = "5000000000000000000" },
    ["创世级"] = { min = "7000000000000000000", max = "90000000000000000000" },
}

--- 生成装备数据（支持部位和品质过滤）
---@param count number
---@param filterSlots string[]|nil 选中的部位中文列表
---@param filterQualities string[]|nil 选中的品质中文列表
local function GenerateEquipment(count, filterSlots, filterQualities)
    -- 构建实际使用的部位列表（中文）
    local slots = {}
    if filterSlots and #filterSlots > 0 then
        for _, s in ipairs(filterSlots) do
            if EQUIP_SLOT_MAP[s] then table.insert(slots, s) end
        end
    end
    if #slots == 0 then for _, s in ipairs(GetEquipSlotLabels()) do table.insert(slots, s) end end

    -- 构建品质列表（中文）
    local qualities = {}
    if filterQualities and #filterQualities > 0 then
        for _, q in ipairs(filterQualities) do
            if EQUIP_QUALITY_RANGES[q] then table.insert(qualities, q) end
        end
    end
    if #qualities == 0 then for _, q in ipairs(EQUIP_QUALITIES) do table.insert(qualities, q) end end

    local generated = 0
    local skipped = 0
    for i = 1, count do
        local slotCN = slots[math.random(1, #slots)]
        local slot = EQUIP_SLOT_MAP[slotCN] or "weapon"
        local quality = qualities[math.random(1, #qualities)]
        local range = EQUIP_QUALITY_RANGES[quality]
        local suffixTable = GEN_NAMES["equip_" .. slot] or GEN_NAMES.equip_weapon
        local name = TryUniqueName(function()
            return RandPick(GEN_NAMES.equip_prefix) .. RandPick(suffixTable)
        end, DataManager.equipment)
        if not name then skipped = skipped + 1; goto equip_continue end
        -- 根据部位决定属性偏向：攻击型/防御型/生命型
        local baseVal = BigNumRandRange(range.min, range.max)
        local subMax = BigNum.div(BigNum.add(range.min, range.max), "3")
        if BigNum.gt(range.min, subMax) then subMax = range.min end
        local subVal = BigNumRandRange(range.min, subMax)
        local atkVal, defVal, hpVal
        -- 攻击型部位：武器、法宝、戒指
        if slot == "weapon" or slot == "artifact" or slot == "ring" then
            atkVal = baseVal
            defVal = subVal
            hpVal = BigNumRandRange(range.min, subMax)
        -- 防御型部位：铠甲、头盔、护腕、护盾
        elseif slot == "armor" or slot == "helmet" or slot == "bracer" or slot == "shield" then
            defVal = baseVal
            atkVal = subVal
            hpVal = BigNumRandRange(range.min, subMax)
        -- 生命/辅助型部位：腰带、战靴、披风、项链、灵翼等
        else
            hpVal = baseVal
            atkVal = subVal
            defVal = BigNumRandRange(range.min, subMax)
        end
        local lvReq = tostring(math.random(1, 100))
        local price = BigNum.mul(baseVal, tostring(math.random(2, 5)))
        local sell = BigNum.div(price, "3")
        DataManager.equipment[name] = {
            name = name,
            slot = slotCN,
            quality = quality,
            desc = "一件" .. quality .. "品质的" .. name,
            atk = atkVal,
            def = defVal,
            hp = hpVal,
            level_req = lvReq,
            price_sell = sell,
        }
        generated = generated + 1
        ::equip_continue::
    end
    SaveCategoryToCloud("equipment")
    return generated, skipped
end

--- 道具类型到效果的映射
local ITEM_TYPE_EFFECTS = {
    ["攻击"] = { effect = "buff_atk", descFmt = "使用后攻击力提升%d点" },
    ["防御"] = { effect = "buff_def", descFmt = "使用后防御力提升%d点" },
    ["生命上限"] = { effect = "buff_hp", descFmt = "使用后生命上限提升%d点" },
    ["恢复血量"] = { effect = "heal", descFmt = "服用后可恢复%d点生命" },
    ["恢复灵力"] = { effect = "heal_mp", descFmt = "服用后可恢复%d点灵力" },
    ["经验倍率"] = { effect = "exp_mult", descFmt = "使用后经验获取提升%d倍持续一段时间" },
    ["货币倍率"] = { effect = "gold_mult", descFmt = "使用后金币获取提升%d倍持续一段时间" },
    ["复活"] = { effect = "revive", descFmt = "死亡后使用可满血复活" },
    ["材料"] = { effect = "none", descFmt = "修炼用的珍贵材料" },
}

--- 生成道具数据（支持类型过滤和限时设置）
---@param count number
---@param selectedTypes string[]|nil 选中的类型列表
---@param duration number|nil 限时时间（秒），0或nil表示不限时
local function GenerateItems(count, selectedTypes, duration)
    local typeList = selectedTypes or { "恢复血量", "材料" }
    local generated = 0
    local skipped = 0
    for i = 1, count do
        local typeName = typeList[math.random(1, #typeList)]
        local info = ITEM_TYPE_EFFECTS[typeName] or ITEM_TYPE_EFFECTS["材料"]
        local name
        local value = "0"
        local itemDuration = nil
        if typeName == "经验倍率" then
            value = tostring(math.random(2, 100))
            if duration and duration == 0 then
                itemDuration = nil
                name = value .. "倍经验卡[永久]"
            else
                local durMin = (duration and duration > 0) and duration or math.random(5, 60)
                itemDuration = durMin
                name = value .. "倍经验卡[" .. durMin .. "分钟]"
            end
        elseif typeName == "货币倍率" then
            value = tostring(math.random(2, 100))
            if duration and duration == 0 then
                itemDuration = nil
                name = value .. "倍货币卡[永久]"
            else
                local durMin = (duration and duration > 0) and duration or math.random(5, 60)
                itemDuration = durMin
                name = value .. "倍货币卡[" .. durMin .. "分钟]"
            end
        else
            local suffix_src = (typeName == "材料") and GEN_NAMES.item_material or GEN_NAMES.item_consumable
            name = TryUniqueName(function()
                return RandPick(GEN_NAMES.item_prefix) .. RandPick(suffix_src)
            end, DataManager.items)
            if not name then skipped = skipped + 1; goto item_continue end
            if typeName ~= "材料" then
                value = tostring(math.random(10, 200))
            end
        end
        -- 倍率卡名称固定，已存在则跳过
        if DataManager.items[name] then skipped = skipped + 1; goto item_continue end
        local desc = (typeName == "材料") and info.descFmt or string.format(info.descFmt, tonumber(value) or 0)
        local itemData = {
            name = name,
            type = typeName,
            desc = desc,
            effect = info.effect,
            value = value,
        }
        local finalDur = itemDuration or ((duration and duration > 0) and duration or nil)
        if finalDur and finalDur > 0 then
            itemData.duration = tostring(finalDur)
        end
        DataManager.items[name] = itemData
        generated = generated + 1
        ::item_continue::
    end
    SaveCategoryToCloud("items")
    return generated, skipped
end

--- 生成副本数据
---@param count number
local function GenerateDungeons(count)
    local generated = 0
    local skipped = 0
    for i = 1, count do
        local name = TryUniqueName(function()
            return RandPick(GEN_NAMES.dungeon_prefix) .. RandPick(GEN_NAMES.dungeon_suffix)
        end, DataManager.dungeons)
        if not name then skipped = skipped + 1; goto dungeon_continue end
        local lvReq = tostring(math.random(1, 12))
        local waves = math.random(3, 5)
        -- 获取已有怪物名列表作为波次内容
        local monsterNames = {}
        for mId in pairs(DataManager.monsters) do
            table.insert(monsterNames, mId)
        end
        local dungeonData = {
            name = name,
            desc = "危险的" .. name .. "，只有勇者才能挑战",
            level_req = lvReq,
            waves = tostring(waves),
            boss = (#monsterNames > 0) and monsterNames[math.random(1, #monsterNames)] or "",
            reward_exp = tostring(math.random(30, 200)),
            reward_gold = tostring(math.random(50, 300)),
            reward_items = "",
        }
        for w = 1, waves do
            local waveMonsters = {}
            local waveSize = math.random(2, 4)
            for _ = 1, waveSize do
                if #monsterNames > 0 then
                    table.insert(waveMonsters, monsterNames[math.random(1, #monsterNames)])
                end
            end
            dungeonData["wave_" .. w] = table.concat(waveMonsters, ",")
        end
        DataManager.dungeons[name] = dungeonData
        generated = generated + 1
        ::dungeon_continue::
    end
    SaveCategoryToCloud("dungeons")
    return generated, skipped
end

--- 生成商店数据
---@param count number
local function GenerateShops(count)
    -- 收集已有道具和装备名作为商品来源
    local allItems = {}
    for id in pairs(DataManager.items) do table.insert(allItems, id) end
    for id in pairs(DataManager.equipment) do table.insert(allItems, id) end

    local generated = 0
    for i = 1, count do
        local name = RandPick(GEN_NAMES.shop_prefix) .. RandPick(GEN_NAMES.shop_suffix)
        local shopId = "shop_gen_" .. tostring(i) .. "_" .. tostring(math.random(100, 999))
        if DataManager.shops[shopId] then
            shopId = shopId .. "_" .. tostring(math.random(1000, 9999))
        end
        -- 随机 3~6 个商品
        local shopItems = {}
        local itemCount = math.random(3, 6)
        if #allItems > 0 then
            local used = {}
            for _ = 1, itemCount do
                local itemName = allItems[math.random(1, #allItems)]
                if not used[itemName] then
                    used[itemName] = true
                    table.insert(shopItems, {
                        name = itemName,
                        price = tostring(math.random(50, 1000)),
                        desc = "",
                    })
                end
            end
        else
            -- 没有已有道具时生成默认商品
            local defaultItems = { "回血丹", "回灵丹", "强化石", "经验丹", "护身符" }
            for j = 1, math.min(itemCount, #defaultItems) do
                table.insert(shopItems, {
                    name = defaultItems[j],
                    price = tostring(math.random(50, 500)),
                    desc = "",
                })
            end
        end
        DataManager.shops[shopId] = {
            name = name,
            desc = name .. "，修仙界闻名的交易之所",
            items = shopItems,
        }
        generated = generated + 1
    end
    SaveCategoryToCloud("shops")
    return generated, 0
end

--- 生成NPC数据
---@param count number
local function GenerateNPCs(count)
    local npcTypes = { "任务", "商人" }
    local surnames = { "李", "王", "张", "陈", "赵", "刘", "杨", "孙", "周", "吴", "林", "徐", "黄", "马", "高" }
    local titles = { "长老", "掌柜", "师傅", "道人", "仙子", "前辈", "散人", "居士", "真人", "隐士" }
    local dialogs_quest = {
        "年轻人，你来得正好，我这有一事相求。",
        "修仙之路漫漫，若你愿意助我一臂之力，必有重谢。",
        "听闻你实力不俗，可否帮我解决一个麻烦？",
        "施主有缘，贫道有一事相托。",
        "少侠请留步，老夫有要事相商。",
    }
    local dialogs_merchant = {
        "客官请看，都是好东西，童叟无欺！",
        "本店货真价实，绝无虚言。",
        "仙友可有需要？本摊修仙好物应有尽有。",
        "买卖不成仁义在，看看总不收钱。",
        "难得来客，给你便宜些。",
    }
    local generated = 0
    local skipped = 0
    for i = 1, count do
        local nType = npcTypes[math.random(1, #npcTypes)]
        local name = TryUniqueName(function()
            return surnames[math.random(1, #surnames)] .. titles[math.random(1, #titles)]
        end, DataManager.npcs)
        if not name then skipped = skipped + 1; goto npc_continue end
        local dialog
        if nType == "任务" then
            dialog = dialogs_quest[math.random(1, #dialogs_quest)]
        else
            dialog = dialogs_merchant[math.random(1, #dialogs_merchant)]
        end
        DataManager.npcs[name] = {
            name = name,
            type = nType,
            dialog = dialog,
            location = "",
            quest_id = "",
            shop_id = "",
        }
        generated = generated + 1
        ::npc_continue::
    end
    SaveCategoryToCloud("npcs")
    return generated, skipped
end

--- 生成任务数据
---@param count number
local function GenerateQuests(count)
    local questTypes = { "主线", "支线", "支线", "支线" } -- 支线更多
    local targetTypes = { "击杀", "收集", "探索" }
    local verbs_kill = { "消灭", "击败", "讨伐", "清除", "歼灭" }
    local verbs_collect = { "收集", "采集", "寻找", "获取", "搜寻" }
    local verbs_explore = { "前往", "探索", "到达", "寻访", "探查" }
    local generated = 0
    -- 收集已有怪物和地图名
    local monsterNames = {}
    for id in pairs(DataManager.monsters) do table.insert(monsterNames, id) end
    local mapNames = {}
    for id in pairs(DataManager.maps) do table.insert(mapNames, id) end
    local itemNames = {}
    for id in pairs(DataManager.items) do table.insert(itemNames, id) end
    local equipNames = {}
    for id in pairs(DataManager.equipment) do table.insert(equipNames, id) end

    for i = 1, count do
        local qType = questTypes[math.random(1, #questTypes)]
        local tType = targetTypes[math.random(1, #targetTypes)]
        local targetName = ""
        local desc = ""
        local targetCount = math.random(1, 5)

        if tType == "击杀" and #monsterNames > 0 then
            targetName = monsterNames[math.random(1, #monsterNames)]
            desc = RandPick(verbs_kill) .. targetCount .. "只" .. targetName
        elseif tType == "收集" and #itemNames > 0 then
            targetName = itemNames[math.random(1, #itemNames)]
            desc = RandPick(verbs_collect) .. targetCount .. "个" .. targetName
        elseif tType == "探索" and #mapNames > 0 then
            targetName = mapNames[math.random(1, #mapNames)]
            targetCount = 1
            desc = RandPick(verbs_explore) .. targetName
        else
            tType = "击杀"
            targetName = "未知妖兽"
            desc = "消灭" .. targetCount .. "只未知妖兽"
        end

        local questId = "gen_" .. string.format("%03d", i) .. "_" .. tostring(math.random(100, 999))
        if DataManager.quests[questId] then
            questId = questId .. "x"
        end

        -- 随机奖励
        local rewardItems = ""
        local allRewardPool = {}
        for _, n in ipairs(itemNames) do table.insert(allRewardPool, n) end
        for _, n in ipairs(equipNames) do table.insert(allRewardPool, n) end
        if #allRewardPool > 0 then
            local rNum = math.random(1, 2)
            local parts = {}
            for _ = 1, rNum do
                table.insert(parts, allRewardPool[math.random(1, #allRewardPool)] .. ":1")
            end
            rewardItems = table.concat(parts, ",")
        end

        DataManager.quests[questId] = {
            name = desc,
            type = qType,
            desc = "有人委托你：" .. desc .. "，完成后可获得丰厚奖励。",
            target_type = tType,
            target_name = targetName,
            target_count = tostring(targetCount),
            reward_exp = tostring(math.random(20, 150)),
            reward_gold = tostring(math.random(30, 200)),
            reward_items = rewardItems,
            next_quest = "",
        }
        generated = generated + 1
    end
    SaveCategoryToCloud("quests")
    return generated, 0
end

--- 一键部署：将地图、怪物、NPC、商店等数据关联在一起
local function DeployAll()
    local changes = 0

    -- 0a. 如果地图数据中没有"新手村"，自动添加
    if not DataManager.maps["新手村"] then
        DataManager.maps["新手村"] = {
            name = "新手村",
            desc = "修仙者初入仙途的起始之地，灵气稀薄但安全祥和。",
            monsters = "",
            npcs = "",
            front = "",
            back = "",
            left = "",
            right = "",
            level_req = "0",
        }
        changes = changes + 1
    end

    -- 0b. 如果没有主线任务，自动生成新手主线任务链
    local hasMainQuest = false
    for _, q in pairs(DataManager.quests) do
        if q.type == "主线" then
            hasMainQuest = true
            break
        end
    end
    if not hasMainQuest then
        -- 生成一组适合新手的主线任务
        local mainQuests = {
            { id = "main_01", name = "初入仙途", desc = "与村长对话，了解修仙世界的基本知识。", target_type = "对话", target_name = "村长", target_count = "1", reward_exp = "50", reward_gold = "100", next_quest = "main_02" },
            { id = "main_02", name = "初试身手", desc = "击败新手村附近的野兽，证明你的实力。", target_type = "击杀", target_name = "", target_count = "3", reward_exp = "100", reward_gold = "150", next_quest = "main_03" },
            { id = "main_03", name = "采集灵草", desc = "为村中药师采集灵草，学习基础炼丹知识。", target_type = "收集", target_name = "灵草", target_count = "5", reward_exp = "150", reward_gold = "200", next_quest = "main_04" },
            { id = "main_04", name = "修炼入门", desc = "通过冥想提升修为，突破练气期一层。", target_type = "等级", target_name = "", target_count = "2", reward_exp = "200", reward_gold = "300", next_quest = "main_05" },
            { id = "main_05", name = "踏上征途", desc = "告别新手村，前往更广阔的修仙世界探索。", target_type = "探索", target_name = "", target_count = "1", reward_exp = "300", reward_gold = "500", next_quest = "" },
        }
        -- 如果有怪物数据，给第二个任务设置具体击杀目标
        for id in pairs(DataManager.monsters) do
            mainQuests[2].target_name = id
            break
        end
        for _, q in ipairs(mainQuests) do
            DataManager.quests[q.id] = {
                name = q.name,
                type = "主线",
                desc = q.desc,
                target_type = q.target_type,
                target_name = q.target_name,
                target_count = q.target_count,
                reward_exp = q.reward_exp,
                reward_gold = q.reward_gold,
                reward_items = "",
                next_quest = q.next_quest,
            }
        end
        changes = changes + 5
    end

    -- 收集所有已有数据名
    local mapNames = {}
    for id in pairs(DataManager.maps) do table.insert(mapNames, id) end
    local monsterNames = {}
    for id in pairs(DataManager.monsters) do table.insert(monsterNames, id) end
    local itemNames = {}
    for id in pairs(DataManager.items) do table.insert(itemNames, id) end
    local equipNames = {}
    for id in pairs(DataManager.equipment) do table.insert(equipNames, id) end
    local npcNames = {}
    for id in pairs(DataManager.npcs) do table.insert(npcNames, id) end
    local shopIds = {}
    for id in pairs(DataManager.shops) do table.insert(shopIds, id) end

    if #mapNames == 0 then return 0 end

    -- 1. 给每个地图分配怪物（如果没有怪物）
    if #monsterNames > 0 then
        for id, data in pairs(DataManager.maps) do
            if not data.monsters or data.monsters == "" then
                local assigned = {}
                local num = math.random(2, math.min(4, #monsterNames))
                for _ = 1, num do
                    local m = monsterNames[math.random(1, #monsterNames)]
                    assigned[m] = true
                end
                local list = {}
                for m in pairs(assigned) do table.insert(list, m) end
                data.monsters = table.concat(list, ",")
                changes = changes + 1
            end
        end
    end

    -- 2. 给每个地图分配NPC（如果没有NPC）
    if #npcNames > 0 then
        for id, data in pairs(DataManager.maps) do
            if not data.npcs or data.npcs == "" then
                local num = math.random(1, math.min(3, #npcNames))
                local assigned = {}
                for _ = 1, num do
                    local n = npcNames[math.random(1, #npcNames)]
                    assigned[n] = true
                end
                local list = {}
                for n in pairs(assigned) do table.insert(list, n) end
                data.npcs = table.concat(list, ",")
                changes = changes + 1
            end
        end
    end

    -- 3. 地图之间相互连接（前后左右，双向对应）
    -- 按等级排序
    table.sort(mapNames, function(a, b)
        local lvA = tonumber(DataManager.maps[a].level_req) or 0
        local lvB = tonumber(DataManager.maps[b].level_req) or 0
        if lvA ~= lvB then return lvA < lvB end
        return a < b
    end)
    -- 清除所有旧连接
    for _, id in ipairs(mapNames) do
        DataManager.maps[id].front = ""
        DataManager.maps[id].back = ""
        DataManager.maps[id].left = ""
        DataManager.maps[id].right = ""
    end
    -- 方向对：A用dir1连B，B用dir2连回A
    local dirPairs = { { "front", "back" }, { "left", "right" } }
    -- 辅助：给两张地图建立双向连接（随机选方向对）
    local function linkMaps(idA, idB)
        local mapA = DataManager.maps[idA]
        local mapB = DataManager.maps[idB]
        -- 收集A的空方向
        local freeA = {}
        if mapA.front == "" then table.insert(freeA, "front") end
        if mapA.back == "" then table.insert(freeA, "back") end
        if mapA.left == "" then table.insert(freeA, "left") end
        if mapA.right == "" then table.insert(freeA, "right") end
        if #freeA == 0 then return false end
        -- 随机打乱A的空方向
        for i = #freeA, 2, -1 do
            local j = math.random(1, i)
            freeA[i], freeA[j] = freeA[j], freeA[i]
        end
        -- 尝试找到一个方向对，使得A的方向和B的对应反方向都空闲
        local opposite = { front = "back", back = "front", left = "right", right = "left" }
        for _, dirA in ipairs(freeA) do
            local dirB = opposite[dirA]
            if mapB[dirB] == "" then
                mapA[dirA] = idB
                mapB[dirB] = idA
                changes = changes + 2
                return true
            end
        end
        return false
    end
    -- 确保所有地图连通：按顺序链接相邻地图
    for i = 1, #mapNames - 1 do
        linkMaps(mapNames[i], mapNames[i + 1])
    end
    -- 额外随机连接：增加一些岔路和环路，让地图网络更丰富
    local extraLinks = math.max(1, math.floor(#mapNames * 0.3))
    for _ = 1, extraLinks do
        local a = math.random(1, #mapNames)
        local b = math.random(1, #mapNames)
        if a ~= b then
            linkMaps(mapNames[a], mapNames[b])
        end
    end

    -- 4. 给怪物分配掉落（关联道具/装备）
    local allDropItems = {}
    for _, n in ipairs(itemNames) do table.insert(allDropItems, n) end
    for _, n in ipairs(equipNames) do table.insert(allDropItems, n) end
    if #allDropItems > 0 then
        for id, data in pairs(DataManager.monsters) do
            if not data.drops or data.drops == "" then
                local num = math.random(1, 3)
                local drops = {}
                for _ = 1, num do
                    local item = allDropItems[math.random(1, #allDropItems)]
                    local rate = math.random(10, 80)
                    table.insert(drops, item .. ":" .. rate)
                end
                data.drops = table.concat(drops, ",")
                changes = changes + 1
            end
        end
    end

    -- 5. 给商店分配商品（如果商品为空）
    if #allDropItems > 0 then
        for id, data in pairs(DataManager.shops) do
            if not data.items or #data.items == 0 then
                local shopItems = {}
                local num = math.random(3, 6)
                for _ = 1, num do
                    local itemName = allDropItems[math.random(1, #allDropItems)]
                    table.insert(shopItems, { name = itemName, price = tostring(math.random(10, 500)), desc = "" })
                end
                data.items = shopItems
                changes = changes + 1
            end
        end
    end

    -- 6. 给副本分配奖励物品（如果为空）
    if #allDropItems > 0 then
        for id, data in pairs(DataManager.dungeons) do
            if not data.reward_items or data.reward_items == "" then
                local num = math.random(1, 3)
                local rewards = {}
                for _ = 1, num do
                    local item = allDropItems[math.random(1, #allDropItems)]
                    table.insert(rewards, item .. ":1")
                end
                data.reward_items = table.concat(rewards, ",")
                changes = changes + 1
            end
        end
    end

    -- 7. 给NPC分配所在地（如果为空）
    if #mapNames > 0 then
        for id, data in pairs(DataManager.npcs) do
            if not data.location or data.location == "" then
                data.location = mapNames[math.random(1, #mapNames)]
                changes = changes + 1
            end
        end
    end

    -- 8. 给任务型NPC分配任务（如果没有绑定）
    local questIds = {}
    for id in pairs(DataManager.quests) do table.insert(questIds, id) end
    local usedQuests = {}
    -- 先记录已被绑定的任务
    for _, data in pairs(DataManager.npcs) do
        if data.quest_id and data.quest_id ~= "" then
            usedQuests[data.quest_id] = true
        end
    end
    if #questIds > 0 then
        for id, data in pairs(DataManager.npcs) do
            if (data.type == "quest" or data.type == "任务") and (not data.quest_id or data.quest_id == "") then
                -- 尝试分配一个未使用的任务
                for _, qId in ipairs(questIds) do
                    if not usedQuests[qId] then
                        data.quest_id = qId
                        usedQuests[qId] = true
                        changes = changes + 1
                        break
                    end
                end
                -- 没有空闲任务就随机分配一个
                if not data.quest_id or data.quest_id == "" then
                    data.quest_id = questIds[math.random(1, #questIds)]
                    changes = changes + 1
                end
            end
        end
    end

    -- 9. 给商人NPC分配商店（如果没有绑定）
    if #shopIds > 0 then
        for id, data in pairs(DataManager.npcs) do
            if (data.type == "merchant" or data.type == "商人") and (not data.shop_id or data.shop_id == "") then
                data.shop_id = shopIds[math.random(1, #shopIds)]
                changes = changes + 1
            end
        end
    end

    -- 10. 将NPC名添加到对应地图的NPC列表中
    for id, data in pairs(DataManager.npcs) do
        if data.location and data.location ~= "" then
            local mapData = DataManager.maps[data.location]
            if mapData then
                local existingNpcs = mapData.npcs or ""
                if not string.find(existingNpcs, id, 1, true) then
                    if existingNpcs == "" then
                        mapData.npcs = id
                    else
                        mapData.npcs = existingNpcs .. "," .. id
                    end
                    changes = changes + 1
                end
            end
        end
    end

    -- 11. 检查玩家起始地是否有效，如果不存在于地图数据中则设为新手村
    local gc = DataManager.gameConfig or {}
    local gameSec = gc["game"] or {}
    local startMap = gameSec.start_map or ""
    if startMap == "" or not DataManager.maps[startMap] then
        -- 优先设为"新手村"，否则使用第一个地图
        local newStart = DataManager.maps["新手村"] and "新手村" or (mapNames[1] or "")
        if newStart ~= "" then
            if not gc["game"] then gc["game"] = {} end
            gc["game"].start_map = newStart
            DataManager.gameConfig = gc
            local gameConfigMod = require("Config.game_config")
            if gameConfigMod.game then
                gameConfigMod.game.start_map = newStart
            end
            changes = changes + 1
        end
    end

    -- 注意：不在此处保存，由调用方统一 BatchSet 批量保存（1次网络请求代替7次）
    return changes
end

--- 序列化指定分类为云端 key + INI content（不执行保存）
---@param category string
---@return string|nil cloudKey
---@return string|nil content
local function SerializeCategoryForCloud(category)
    if category == "maps" then
        local sections = {}
        for id, data in pairs(DataManager.maps) do
            sections[id] = {
                ["名称"] = data.name or id,
                ["描述"] = data.desc or "",
                ["怪物"] = data.monsters or "",
                ["NPC"] = data.npcs or "",
                ["前方"] = data.front or "",
                ["后方"] = data.back or "",
                ["左方"] = data.left or "",
                ["右方"] = data.right or "",
                ["等级要求"] = NumFormat.Int(data.level_req or 0),
            }
        end
        return "系统配置/maps.ini", IniParser.Serialize(sections)
    elseif category == "monsters" then
        local sections = {}
        for id, data in pairs(DataManager.monsters) do
            local sec = {
                ["名称"] = data.name or id,
                ["类型"] = data.type or "普通怪",
                ["描述"] = data.desc or "",
                ["生命值"] = NumFormat.Int(data.hp or 20),
                ["攻击力"] = NumFormat.Int(data.atk or 3),
                ["防御力"] = NumFormat.Int(data.def or 1),
                ["经验值"] = NumFormat.Int(data.exp or 5),
                ["金币"] = NumFormat.Int(data.gold or 2),
                ["掉落"] = data.drops or "",
            }
            if data.currency_drops then
                local cIdx = 0
                for cName, cVal in pairs(data.currency_drops) do
                    cIdx = cIdx + 1
                    sec["货币" .. cIdx .. "_名称"] = cName
                    sec["货币" .. cIdx .. "_数量"] = NumFormat.Int(cVal or 0)
                end
                sec["货币数量"] = tostring(cIdx)
            else
                sec["货币数量"] = "0"
            end
            sections[id] = sec
        end
        return "系统配置/monsters.ini", IniParser.Serialize(sections)
    elseif category == "shops" then
        local sections = {}
        for id, data in pairs(DataManager.shops) do
            local sec = {
                ["名称"] = data.name or id,
                ["描述"] = data.desc or "",
                ["商品数量"] = tostring(#(data.items or {})),
            }
            for i, item in ipairs(data.items or {}) do
                local p = item.price or "0"
                if p == "" then p = "0" end
                sec["商品_" .. i] = (item.name or "") .. ":" .. p .. ":" .. (item.desc or "")
            end
            sections[id] = sec
        end
        return "系统配置/shops.ini", IniParser.Serialize(sections)
    elseif category == "dungeons" then
        local sections = {}
        for id, data in pairs(DataManager.dungeons) do
            local sec = {
                ["名称"] = data.name or id,
                ["描述"] = data.desc or "",
                ["等级需求"] = NumFormat.Int(data.level_req or 1),
                ["波数"] = NumFormat.Int(data.waves or 1),
                ["首领"] = data.boss or "",
                ["奖励经验"] = NumFormat.Int(data.reward_exp or 0),
                ["奖励金币"] = NumFormat.Int(data.reward_gold or 0),
                ["奖励物品"] = data.reward_items or "",
            }
            for i = 1, (data.waves or 1) do
                sec["第" .. i .. "波"] = data["wave_" .. i] or ""
            end
            sections[id] = sec
        end
        return "系统配置/dungeons.ini", IniParser.Serialize(sections)
    elseif category == "npcs" then
        local sections = {}
        for id, data in pairs(DataManager.npcs) do
            local sec = {
                ["名称"] = data.name or id,
                ["类型"] = data.type or "任务",
                ["对话"] = data.dialog or "",
                ["所在地"] = data.location or "",
            }
            if data.type == "商人" or data.type == "merchant" then
                sec["商店编号"] = data.shop_id or ""
            else
                sec["任务编号"] = data.quest_id or ""
            end
            sections[id] = sec
        end
        return "系统配置/npcs.ini", IniParser.Serialize(sections)
    elseif category == "quests" then
        local sections = {}
        for id, data in pairs(DataManager.quests) do
            sections[id] = {
                ["名称"] = data.name or id,
                ["类型"] = data.type or "主线",
                ["描述"] = data.desc or "",
                ["目标类型"] = data.target_type or "击杀",
                ["目标名称"] = data.target_name or "",
                ["目标数量"] = NumFormat.Int(data.target_count or 1),
                ["奖励经验"] = NumFormat.Int(data.reward_exp or 0),
                ["奖励金币"] = NumFormat.Int(data.reward_gold or 0),
                ["奖励物品"] = data.reward_items or "",
                ["后续任务"] = data.next_quest or "",
            }
        end
        return "系统配置/quests.ini", IniParser.Serialize(sections)
    elseif category == "game_config" then
        local gc = DataManager.gameConfig
        local sections = {}
        local gameSec = gc["game"] or {}
        sections["游戏设置"] = {
            ["标题"] = gameSec.title or "修仙游戏",
            ["版本"] = gameSec.version or "1.0.0",
            ["起始地图"] = gameSec.start_map or "新手村",
            ["起始任务"] = gameSec.start_quest or "main_001",
        }
        local defSec = gc["player_default"] or {}
        sections["玩家默认属性"] = {
            ["生命值"] = NumFormat.Int(defSec.hp or 100),
            ["法力值"] = NumFormat.Int(defSec.mp or 50),
            ["攻击力"] = NumFormat.Int(defSec.atk or 5),
            ["防御力"] = NumFormat.Int(defSec.def or 3),
            ["等级"] = NumFormat.Int(defSec.level or 1),
            ["经验"] = NumFormat.Int(defSec.exp or 0),
            ["金币"] = NumFormat.Int(defSec.gold or 50),
        }
        local lvlSec = gc["level_up"] or {}
        sections["升级配置"] = {
            ["基础经验"] = NumFormat.Int(lvlSec.base_exp or 20),
            ["经验系数"] = tostring(lvlSec.exp_factor or 2),
            ["每级生命"] = NumFormat.Int(lvlSec.hp_per_level or 20),
            ["每级法力"] = NumFormat.Int(lvlSec.mp_per_level or 10),
            ["每级攻击"] = NumFormat.Int(lvlSec.atk_per_level or 3),
            ["每级防御"] = NumFormat.Int(lvlSec.def_per_level or 2),
            ["最高等级"] = NumFormat.Int(lvlSec.max_level or 100),
        }
        local currList = gc["currencies"] or { "金币" }
        local currSec = { ["货币数量"] = tostring(#currList) }
        for i, name in ipairs(currList) do
            currSec["货币_" .. i] = name
        end
        sections["货币配置"] = currSec
        local monGenSec = { ["类型数量"] = tostring(#MONSTER_TYPES) }
        for i, mt in ipairs(MONSTER_TYPES) do
            monGenSec["类型" .. i .. "_名称"] = mt.name
            monGenSec["类型" .. i .. "_HP下限"] = mt.min_hp or "10"
            monGenSec["类型" .. i .. "_HP上限"] = mt.max_hp or "2000"
            monGenSec["类型" .. i .. "_攻击下限"] = mt.min_atk or "5"
            monGenSec["类型" .. i .. "_攻击上限"] = mt.max_atk or "1000"
            monGenSec["类型" .. i .. "_防御下限"] = mt.min_def or "3"
            monGenSec["类型" .. i .. "_防御上限"] = mt.max_def or "800"
            monGenSec["类型" .. i .. "_经验下限"] = mt.min_exp or "5"
            monGenSec["类型" .. i .. "_经验上限"] = mt.max_exp or "500"
            if mt.currency_ranges then
                local cIdx = 0
                for cName, cRange in pairs(mt.currency_ranges) do
                    cIdx = cIdx + 1
                    monGenSec["类型" .. i .. "_货币" .. cIdx .. "_名称"] = cName
                    monGenSec["类型" .. i .. "_货币" .. cIdx .. "_下限"] = cRange.min or "0"
                    monGenSec["类型" .. i .. "_货币" .. cIdx .. "_上限"] = cRange.max or "0"
                end
                monGenSec["类型" .. i .. "_货币数量"] = tostring(cIdx)
            else
                monGenSec["类型" .. i .. "_货币数量"] = "0"
            end
            monGenSec["类型" .. i .. "_描述"] = mt.desc or ""
        end
        sections["怪物生成配置"] = monGenSec
        local deployCfg = gc["deploy"] or {}
        sections["部署版本"] = {
            ["版本号"] = tostring(deployCfg.version or 0),
            ["目标地图"] = deployCfg.target_map or "",
        }
        return "系统配置/game_config.ini", IniParser.Serialize(sections)
    end
    return nil, nil
end

--- 渲染境界管理面板
local function RenderRealms()
    ClearContent()
    contentPanel_:AddChild(CreateSearchBar("搜索境界名...", function() RenderRealms() end))
    local count = #DataManager.realms
    ShowMsg("共 " .. count .. " 个境界")

    local dataArray = {}
    for _, data in ipairs(DataManager.realms) do
        if not MatchSearch(data.name) then goto continue_realms end
        local subtext = "阶段:" .. data.stage .. " 层数:" .. data.layers
            .. " 层经验:" .. (data.layer_exp or "100")
            .. " 攻:" .. (data.atk_bonus or "0")
            .. " 防:" .. (data.def_bonus or "0")
            .. " 血:" .. (data.hp_bonus or "0")
        table.insert(dataArray, {
            text = "[" .. data.stage .. "] " .. data.name,
            subtext = subtext,
            onEdit = function()
                ShowEditDialog("编辑境界 - " .. data.name, {
                    { label = "名称", key = "name", value = data.name },
                    { label = "阶段(排序)", key = "stage", value = tostring(data.stage) },
                    { label = "层数", key = "layers", value = tostring(data.layers) },
                    { label = "描述", key = "desc", value = data.desc or "", opts = { width = 220 } },
                    { label = "每层经验", key = "layer_exp", value = tostring(data.layer_exp or "100") },
                    { label = "攻击加成(每层)", key = "atk_bonus", value = tostring(data.atk_bonus or "0") },
                    { label = "防御加成(每层)", key = "def_bonus", value = tostring(data.def_bonus or "0") },
                    { label = "生命加成(每层)", key = "hp_bonus", value = tostring(data.hp_bonus or "0") },
                    { label = "提升材料", key = "upgrade_material", value = data.upgrade_material or "" },
                    { label = "提升数量(每层)", key = "upgrade_count", value = tostring(data.upgrade_count or 0) },
                    { label = "突破材料", key = "breakthrough_material", value = data.breakthrough_material or "" },
                    { label = "突破数量", key = "breakthrough_count", value = tostring(data.breakthrough_count or 0) },
                }, function(v)
                    data.name = v.name or data.name
                    data.stage = tonumber(v.stage) or data.stage
                    data.layers = tonumber(v.layers) or data.layers
                    data.desc = v.desc or ""
                    data.layer_exp = v.layer_exp or "100"
                    data.atk_bonus = v.atk_bonus or "0"
                    data.def_bonus = v.def_bonus or "0"
                    data.hp_bonus = v.hp_bonus or "0"
                    data.upgrade_material = v.upgrade_material or ""
                    data.upgrade_count = tonumber(v.upgrade_count) or 0
                    data.breakthrough_material = v.breakthrough_material or ""
                    data.breakthrough_count = tonumber(v.breakthrough_count) or 0
                    -- 重建索引
                    table.sort(DataManager.realms, function(a, b) return a.stage < b.stage end)
                    DataManager.realmsByStage = {}
                    for _, r in ipairs(DataManager.realms) do
                        DataManager.realmsByStage[r.stage] = r
                    end
                    SaveCategoryToCloud("realms")
                    CloseDialog()
                    RenderRealms()
                end)
            end,
            onDelete = function()
                -- 删除境界
                for i, r in ipairs(DataManager.realms) do
                    if r == data then
                        table.remove(DataManager.realms, i)
                        break
                    end
                end
                DataManager.realmsByStage = {}
                for _, r in ipairs(DataManager.realms) do
                    DataManager.realmsByStage[r.stage] = r
                end
                SaveCategoryToCloud("realms")
                RenderRealms()
            end,
        })
        ::continue_realms::
    end
    contentPanel_:AddChild(CreateVirtualDataList(dataArray))

    contentPanel_:AddChild(UI.Panel {
        flexDirection = "row", width = "100%", gap = 8, marginTop = 8, marginLeft = 12,
        children = {
            UI.Button {
                text = "+ 添加境界",
                variant = "primary", width = 120,
                onClick = function()
                    local nextStage = #DataManager.realms + 1
                    ShowEditDialog("添加境界", {
                { label = "名称", key = "name", value = "", opts = { placeholder = "如：渡劫期" } },
                { label = "阶段(排序)", key = "stage", value = tostring(nextStage) },
                { label = "层数", key = "layers", value = "9" },
                { label = "描述", key = "desc", value = "", opts = { width = 220 } },
                { label = "每层经验", key = "layer_exp", value = "100" },
                { label = "攻击加成(每层)", key = "atk_bonus", value = "10" },
                { label = "防御加成(每层)", key = "def_bonus", value = "5" },
                { label = "生命加成(每层)", key = "hp_bonus", value = "100" },
                { label = "提升材料", key = "upgrade_material", value = "灵石碎片" },
                { label = "提升数量(每层)", key = "upgrade_count", value = "10" },
                { label = "突破材料", key = "breakthrough_material", value = "灵石" },
                { label = "突破数量", key = "breakthrough_count", value = "100" },
            }, function(v)
                if not v.name or v.name == "" then return end
                local newRealm = {
                    name = v.name,
                    stage = tonumber(v.stage) or nextStage,
                    layers = tonumber(v.layers) or 9,
                    desc = v.desc or "",
                    layer_exp = v.layer_exp or "100",
                    atk_bonus = v.atk_bonus or "0",
                    def_bonus = v.def_bonus or "0",
                    hp_bonus = v.hp_bonus or "0",
                    upgrade_material = v.upgrade_material or "",
                    upgrade_count = tonumber(v.upgrade_count) or 0,
                    breakthrough_material = v.breakthrough_material or "",
                    breakthrough_count = tonumber(v.breakthrough_count) or 0,
                }
                table.insert(DataManager.realms, newRealm)
                table.sort(DataManager.realms, function(a, b) return a.stage < b.stage end)
                DataManager.realmsByStage = {}
                for _, r in ipairs(DataManager.realms) do
                    DataManager.realmsByStage[r.stage] = r
                end
                SaveCategoryToCloud("realms")
                CloseDialog()
                RenderRealms()
            end)
                end,
            },
            UI.Button {
                text = "重置为默认(62阶)",
                variant = "secondary", width = 160,
                onClick = function()
                    local IniParser = require("Utils.IniParser")
                    local ConfigData = require("Config.ConfigData")
                    DataManager.realms = DataManager.ParseRealms(IniParser.Parse(ConfigData.realms))
                    DataManager.realmsByStage = {}
                    for _, r in ipairs(DataManager.realms) do
                        DataManager.realmsByStage[r.stage] = r
                    end
                    SaveCategoryToCloud("realms")
                    ShowMsg("已重置为默认62阶境界并保存到云端")
                    RenderRealms()
                end,
            },
        },
    })

    -- =============== 境界经验丹管理区域 ===============
    contentPanel_:AddChild(UI.Panel {
        width = "100%", height = 1, backgroundColor = { 80, 70, 120, 200 }, marginTop = 12, marginBottom = 4,
    })
    contentPanel_:AddChild(UI.Label {
        text = "境界经验丹配置",
        fontSize = 14, fontColor = { 200, 180, 255, 255 },
        marginLeft = 12, marginBottom = 4,
    })

    local pillDataArray = {}
    for id, pill in pairs(DataManager.realmPills) do
        table.insert(pillDataArray, {
            text = pill.name,
            subtext = "经验值:" .. (pill.value or "0") .. "  " .. (pill.desc or ""),
            onEdit = function()
                ShowEditDialog("编辑经验丹 - " .. id, {
                    { label = "名称", key = "name", value = pill.name },
                    { label = "描述", key = "desc", value = pill.desc or "", opts = { width = 220 } },
                    { label = "经验数值", key = "value", value = tostring(pill.value or "0") },
                }, function(v)
                    pill.name = v.name or pill.name
                    pill.desc = v.desc or ""
                    pill.value = v.value or "0"
                    SaveCategoryToCloud("realm_pills")
                    CloseDialog()
                    RenderRealms()
                end)
            end,
            onDelete = function()
                DataManager.realmPills[id] = nil
                DataManager.items[id] = nil
                SaveCategoryToCloud("realm_pills")
                RenderRealms()
            end,
        })
    end
    if #pillDataArray > 0 then
        contentPanel_:AddChild(CreateVirtualDataList(pillDataArray))
    end

    contentPanel_:AddChild(UI.Button {
        text = "+ 添加经验丹",
        variant = "primary", width = 130, marginTop = 8, marginLeft = 12,
        onClick = function()
            ShowEditDialog("添加境界经验丹", {
                { label = "名称(ID)", key = "id", value = "", opts = { placeholder = "如：极品经验丹" } },
                { label = "描述", key = "desc", value = "", opts = { width = 220 } },
                { label = "经验数值", key = "value", value = "500" },
            }, function(v)
                if not v.id or v.id == "" then return end
                DataManager.realmPills[v.id] = {
                    name = v.id,
                    desc = v.desc or "",
                    value = v.value or "0",
                }
                SaveCategoryToCloud("realm_pills")
                CloseDialog()
                RenderRealms()
            end)
        end,
    })
end

--- 前向声明：宝箱管理相关函数（存在循环引用）
local SaveChestsToCloud
local RenderChestsList
local ShowChestEditDialog

--- 渲染发放物品货币面板
local function RenderDistribute()
    ClearContent()

    -- 发放模式选择
    local modeLabel = UI.Label {
        text = "当前模式：全服发放",
        fontSize = 13,
        fontColor = { 100, 200, 255, 255 },
        marginBottom = 4,
    }
    local isGlobal = true

    -- 目标玩家输入
    local targetPanel, targetField = CreateFormField("目标玩家", "", { placeholder = "输入玩家账号", width = 160 })
    targetPanel:SetVisible(false)

    -- 发放内容表单 - 自定义货币字段
    local currList = DataManager.GetCurrencyList()
    local currFields = {}  -- { name = field } 映射
    local currPanels = {}  -- 面板列表用于 children
    for _, cname in ipairs(currList) do
        local p, f = CreateFormField(cname .. "数量", "0", { placeholder = "0", width = 120, showUnit = true })
        currFields[cname] = f
        table.insert(currPanels, p)
    end
    local itemsPanel, itemsField = CreateFormField("物品列表", "", { placeholder = "物品:数量,物品2:数量", width = 220 })
    local titlePanel, titleField = CreateFormField("邮件标题", "系统发放", { placeholder = "邮件标题", width = 180 })
    local contentPanel, contentField = CreateFormField("邮件内容", "管理员发放奖励", { placeholder = "邮件内容", width = 220 })

    local resultLabel = UI.Label {
        text = "",
        fontSize = 12,
        fontColor = { 200, 200, 200, 255 },
        marginTop = 8,
        whiteSpace = "normal",
    }

    -- 构建 children（避免 table.unpack 不在末尾的陷阱）
    local distChildren = {
        UI.Label { text = "发放物品/货币", fontSize = 16, fontColor = { 255, 200, 100, 255 }, marginBottom = 8 },
        -- 模式切换
        UI.Panel {
            flexDirection = "row",
            gap = 8,
            marginBottom = 4,
            children = {
                UI.Button {
                    text = "全服发放",
                    variant = "primary",
                    height = 30,
                    onClick = function()
                        isGlobal = true
                        modeLabel:SetText("当前模式：全服发放")
                        targetPanel:SetVisible(false)
                    end,
                },
                UI.Button {
                    text = "指定玩家",
                    variant = "secondary",
                    height = 30,
                    onClick = function()
                        isGlobal = false
                        modeLabel:SetText("当前模式：指定玩家发放")
                        targetPanel:SetVisible(true)
                    end,
                },
            },
        },
        modeLabel,
        targetPanel,
        UI.Panel { width = "100%", height = 1, backgroundColor = { 50, 40, 70, 255 }, marginTop = 4, marginBottom = 4 },
    }
    -- 插入每种货币的输入面板
    for _, p in ipairs(currPanels) do
        table.insert(distChildren, p)
    end
    table.insert(distChildren, itemsPanel)
    table.insert(distChildren, titlePanel)
    table.insert(distChildren, contentPanel)
    table.insert(distChildren, UI.Button {
        text = "确认发放",
        variant = "danger",
        width = "100%",
        height = 36,
        marginTop = 8,
        onClick = function()
            -- 收集所有货币数值
            local currencies = {}
            local hasCurrency = false
            for _, cname in ipairs(currList) do
                local val = currFields[cname]:GetValue() or "0"
                if val ~= "" and val ~= "0" then
                    currencies[cname] = val
                    hasCurrency = true
                end
            end
            local items = itemsField:GetValue() or ""
            local title = titleField:GetValue() or "系统发放"
            local mailContent = contentField:GetValue() or ""

            if not hasCurrency and items == "" then
                resultLabel:SetText("请填写货币或物品")
                resultLabel:SetFontColor({ 255, 100, 100, 255 })
                return
            end

            local MailboxUI = require("UI.MailboxUI")
            local mailData = {
                type = "admin",
                title = title,
                content = mailContent,
                gold = currencies["金币"] or "0",
                currencies = currencies,
                items = items,
                sender = "管理员",
            }

            if isGlobal then
                -- 全服发放
                resultLabel:SetText("正在发放中...")
                resultLabel:SetFontColor({ 255, 200, 100, 255 })
                DataManager.GetAllPlayers(function(players)
                    local accounts = {}
                    for _, p in ipairs(players) do
                        table.insert(accounts, p.username)
                    end
                    MailboxUI.SendMailBatch(accounts, mailData, function(okCount, failCount)
                        resultLabel:SetText("全服发放完成！成功 " .. okCount .. " 人，失败 " .. failCount .. " 人")
                        resultLabel:SetFontColor({ 100, 255, 100, 255 })
                    end)
                end)
            else
                -- 指定玩家
                local target = targetField:GetValue() or ""
                if target == "" then
                    resultLabel:SetText("请输入目标玩家账号")
                    resultLabel:SetFontColor({ 255, 100, 100, 255 })
                    return
                end
                resultLabel:SetText("正在发放...")
                resultLabel:SetFontColor({ 255, 200, 100, 255 })
                MailboxUI.SendMail(target, mailData, function(ok)
                    if ok then
                        resultLabel:SetText("发放成功！已发送邮件给 " .. target)
                        resultLabel:SetFontColor({ 100, 255, 100, 255 })
                    else
                        resultLabel:SetText("发放失败，请检查玩家账号")
                        resultLabel:SetFontColor({ 255, 100, 100, 255 })
                    end
                end)
            end
        end,
    })
    table.insert(distChildren, resultLabel)

    contentPanel_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "column",
        padding = 8,
        gap = 6,
        children = distChildren,
    })
end

--- 保存宝箱配置到云端
---@param chests table
---@param callback fun(boolean)
SaveChestsToCloud = function(chests, callback)
    local sections = {}
    for _, chest in ipairs(chests) do
        sections[chest.name] = {
            ["类型"] = chest.type or "固定",
            ["物品"] = chest.items or "",
        }
    end
    local content = IniParser.Serialize(sections)
    SaveConfigToCloud("系统配置/chests.ini", content, callback)
end

--- 显示宝箱编辑弹窗
---@param chest table|nil 为 nil 则新建
---@param chests table 完整宝箱列表引用
ShowChestEditDialog = function(chest, chests)
    CloseDialog()

    local isNew = (chest == nil)
    local origName = chest and chest.name or ""

    local namePanel, nameField = CreateFormField("宝箱名称", origName, { placeholder = "输入宝箱名称", width = 160 })
    local typePanel, typeField = CreateFormField("宝箱类型", chest and chest.type or "固定", { placeholder = "固定 或 随机", width = 120 })
    local itemsPanel, itemsField = CreateFormField("物品列表", chest and chest.items or "", { placeholder = "物品:数量,物品2:数量", width = 220 })

    local dialogPanel = UI.Panel {
        position = "absolute",
        width = "90%",
        left = "5%",
        top = 60,
        backgroundColor = { 30, 25, 50, 250 },
        borderRadius = 8,
        padding = 12,
        flexDirection = "column",
        gap = 8,
        children = {
            UI.Label {
                text = isNew and "添加宝箱" or ("编辑: " .. origName),
                fontSize = 14,
                fontColor = { 255, 220, 100, 255 },
            },
            namePanel,
            typePanel,
            itemsPanel,
            UI.Panel {
                flexDirection = "row",
                gap = 8,
                marginTop = 8,
                children = {
                    UI.Button {
                        text = "保存",
                        variant = "primary",
                        height = 30,
                        onClick = function()
                            local newName = nameField:GetValue() or ""
                            local newType = typeField:GetValue() or "固定"
                            local newItems = itemsField:GetValue() or ""

                            if newName == "" then
                                ShowMsg("宝箱名称不能为空")
                                return
                            end

                            -- 类型校验
                            if newType ~= "固定" and newType ~= "随机" then
                                newType = "固定"
                            end

                            if isNew then
                                table.insert(chests, { name = newName, type = newType, items = newItems })
                            else
                                -- 更新
                                for _, c in ipairs(chests) do
                                    if c.name == origName then
                                        c.name = newName
                                        c.type = newType
                                        c.items = newItems
                                        break
                                    end
                                end
                            end

                            SaveChestsToCloud(chests, function(ok)
                                ShowMsg(ok and "宝箱保存成功" or "保存失败")
                                CloseDialog()
                                RenderChestsList(chests)
                            end)
                        end,
                    },
                    UI.Button {
                        text = "取消",
                        variant = "secondary",
                        height = 30,
                        onClick = function() CloseDialog() end,
                    },
                },
            },
        },
    }

    editDialog_ = dialogPanel
    if rootPanel_ then
        rootPanel_:AddChild(dialogPanel)
    end
end

--- 渲染宝箱列表
---@param chests table
RenderChestsList = function(chests)
    if not contentPanel_ then return end
    contentPanel_:ClearChildren()

    contentPanel_:AddChild(UI.Label {
        text = "宝箱管理",
        fontSize = 16,
        fontColor = { 255, 200, 100, 255 },
        marginBottom = 8,
    })

    -- 添加宝箱按钮
    contentPanel_:AddChild(UI.Button {
        text = "+ 添加宝箱",
        variant = "primary",
        height = 32,
        marginBottom = 8,
        onClick = function()
            ShowChestEditDialog(nil, chests)
        end,
    })

    if #chests == 0 then
        contentPanel_:AddChild(UI.Label {
            text = "暂无宝箱配置",
            fontSize = 13,
            fontColor = { 150, 150, 170, 255 },
            marginTop = 12,
        })
        return
    end

    -- 列表
    for i, chest in ipairs(chests) do
        local typeColor = (chest.type == "随机") and { 200, 100, 255, 255 } or { 100, 200, 255, 255 }
        contentPanel_:AddChild(UI.Panel {
            width = "100%",
            backgroundColor = (i % 2 == 0) and { 35, 30, 55, 200 } or { 25, 20, 45, 200 },
            borderRadius = 4,
            padding = 8,
            marginBottom = 4,
            flexDirection = "column",
            gap = 2,
            children = {
                UI.Panel {
                    flexDirection = "row",
                    width = "100%",
                    justifyContent = "space-between",
                    alignItems = "center",
                    children = {
                        UI.Panel {
                            flexDirection = "row",
                            gap = 8,
                            alignItems = "center",
                            children = {
                                UI.Label { text = chest.name, fontSize = 13, fontColor = { 220, 200, 150, 255 } },
                                UI.Label { text = "[" .. chest.type .. "]", fontSize = 11, fontColor = typeColor },
                            },
                        },
                        UI.Panel {
                            flexDirection = "row",
                            gap = 4,
                            children = {
                                UI.Button {
                                    text = "编辑",
                                    variant = "secondary",
                                    height = 24,
                                    fontSize = 11,
                                    onClick = function() ShowChestEditDialog(chest, chests) end,
                                },
                                UI.Button {
                                    text = "删除",
                                    variant = "danger",
                                    height = 24,
                                    fontSize = 11,
                                    onClick = function()
                                        for j, c in ipairs(chests) do
                                            if c.name == chest.name then
                                                table.remove(chests, j)
                                                break
                                            end
                                        end
                                        SaveChestsToCloud(chests, function(ok)
                                            ShowMsg(ok and "删除成功" or "删除失败")
                                            RenderChestsList(chests)
                                        end)
                                    end,
                                },
                            },
                        },
                    },
                },
                UI.Label {
                    text = "物品: " .. chest.items,
                    fontSize = 11,
                    fontColor = { 180, 180, 200, 255 },
                    whiteSpace = "normal",
                },
            },
        })
    end
end

--- 渲染宝箱管理面板
local function RenderChests()
    ClearContent()
    ShowMsg("正在加载宝箱配置...")

    -- 从云端加载宝箱配置
    local cloud = DataManager.GetCloudProvider()
    if not cloud then
        ShowMsg("云存储不可用")
        return
    end

    local CHESTS_KEY = "系统配置/chests.ini"
    cloud:Get(CHESTS_KEY, {
        ok = function(values)
            local raw = values[CHESTS_KEY]
            local chests = {}
            if raw and raw ~= "" then
                local sections = IniParser.Parse(raw)
                for name, data in pairs(sections) do
                    table.insert(chests, {
                        name = name,
                        type = data["类型"] or "固定",
                        items = data["物品"] or "",
                    })
                end
            end
            table.sort(chests, function(a, b) return a.name < b.name end)
            RenderChestsList(chests)
        end,
        error = function(code, reason)
            ShowMsg("加载宝箱配置失败: " .. tostring(reason))
        end,
    })
end

--- 宠物品质选项（从品质消耗配置动态获取）
local function GetPetQualityOptions()
    local pc = DataManager.petConfig or {}
    local qCost = pc.quality_cost or {}
    -- 品质升级链：key=源品质，value 的下一级也需要加入可选列表
    local qualNextMap = { ["白"] = "绿", ["绿"] = "蓝", ["蓝"] = "紫", ["紫"] = "橙", ["橙"] = "红", ["红"] = "金", ["金"] = "圣", ["圣"] = "仙", ["仙"] = "神" }
    -- 收集所有品质（key + 每个 key 的下一级目标）
    local qualSet = {}
    local qualList = {}
    for qName, _ in pairs(qCost) do
        if not qualSet[qName] then
            qualSet[qName] = true
            table.insert(qualList, qName)
        end
        -- 把目标品质也加入
        local nextQ = qualNextMap[qName]
        if nextQ and not qualSet[nextQ] then
            qualSet[nextQ] = true
            table.insert(qualList, nextQ)
        end
    end
    -- 如果配置为空，使用默认
    if #qualList == 0 then
        return { "白", "绿", "蓝", "紫", "橙", "红", "金" }
    end
    -- 从固定顺序中筛选存在的品质
    local ORDER = { "白", "绿", "蓝", "紫", "橙", "红", "金", "圣", "仙", "神" }
    local sorted = {}
    local sortedSet = {}
    for _, q in ipairs(ORDER) do
        if qualSet[q] then
            table.insert(sorted, q)
            sortedSet[q] = true
        end
    end
    -- 补充配置中有但不在 ORDER 里的自定义品质
    for _, q in ipairs(qualList) do
        if not sortedSet[q] then
            table.insert(sorted, q)
        end
    end
    return sorted
end

--- 渲染宠物管理面板（宠物种类CRUD）
local function RenderPets()
    ClearContent()
    contentPanel_:AddChild(CreateSearchBar("搜索宠物名...", function() RenderPets() end))
    local count = 0
    for _ in pairs(DataManager.petTypes) do count = count + 1 end
    ShowMsg("共 " .. count .. " 种宠物")

    local dataArray = {}
    for id, data in pairs(DataManager.petTypes) do
        if not MatchSearch(data.name or id) then goto continue_pets end
        local qualTag = data.quality and ("[" .. data.quality .. "] ") or ""
        table.insert(dataArray, {
            text = qualTag .. (data.name or id),
            subtext = "攻:" .. (data.atk or 0) .. " 防:" .. (data.def or 0) .. " 血:" .. (data.max_hp or 0) .. (data.skill ~= "" and (" 技能:" .. data.skill) or ""),
            onEdit = function()
                ShowEditDialog("编辑宠物 - " .. (data.name or id), {
                    { label = "名称", key = "name", value = data.name or id },
                    { label = "品质", key = "quality", value = data.quality or "白", type = "selector", opts = { options = GetPetQualityOptions() } },
                    { label = "描述", key = "desc", value = data.desc or "", opts = { width = 220 } },
                    { label = "基础攻击", key = "atk", value = data.atk or "10" },
                    { label = "基础防御", key = "def", value = data.def or "5" },
                    { label = "基础生命", key = "max_hp", value = data.max_hp or "100" },
                    { label = "技能", key = "skill", value = data.skill or "", opts = { width = 220, placeholder = "技能名称（可空）" } },
                }, function(v)
                    DataManager.petTypes[id] = {
                        name = v.name or id,
                        desc = v.desc or "",
                        atk = v.atk or "10",
                        def = v.def or "5",
                        max_hp = v.max_hp or "100",
                        quality = v.quality or "白",
                        skill = v.skill or "",
                    }
                    SaveCategoryToCloud("pet_types")
                    CloseDialog()
                    RenderPets()
                end)
            end,
            onDelete = function()
                DataManager.petTypes[id] = nil
                SaveCategoryToCloud("pet_types")
                RenderPets()
            end,
        })
        ::continue_pets::
    end
    contentPanel_:AddChild(CreateVirtualDataList(dataArray))

    contentPanel_:AddChild(UI.Button {
        text = "+ 添加宠物",
        variant = "primary", width = 120, marginTop = 8, marginLeft = 12,
        onClick = function()
            ShowEditDialog("添加新宠物", {
                { label = "ID(唯一标识)", key = "id", value = "", opts = { placeholder = "如：小火龙" } },
                { label = "名称", key = "name", value = "" },
                { label = "品质", key = "quality", value = "白", type = "selector", opts = { options = GetPetQualityOptions() } },
                { label = "描述", key = "desc", value = "", opts = { width = 220 } },
                { label = "基础攻击", key = "atk", value = "10" },
                { label = "基础防御", key = "def", value = "5" },
                { label = "基础生命", key = "max_hp", value = "100" },
                { label = "技能", key = "skill", value = "", opts = { width = 220, placeholder = "技能名称（可空）" } },
            }, function(v)
                if not v.id or v.id == "" then return end
                DataManager.petTypes[v.id] = {
                    name = v.name ~= "" and v.name or v.id,
                    desc = v.desc or "",
                    atk = v.atk or "10",
                    def = v.def or "5",
                    max_hp = v.max_hp or "100",
                    quality = v.quality or "白",
                    skill = v.skill or "",
                }
                SaveCategoryToCloud("pet_types")
                CloseDialog()
                RenderPets()
            end)
        end,
    })
end

--- 宠物装备部位选项
local PET_EQUIP_SLOT_OPTIONS = { "项圈", "护甲", "爪套", "铃铛" }

--- 渲染宠物装备管理面板
local function RenderPetEquip()
    ClearContent()
    contentPanel_:AddChild(CreateSearchBar("搜索宠物装备...", function() RenderPetEquip() end))

    -- 从物品表中筛选出宠物装备
    local petEquips = {}
    for id, data in pairs(DataManager.items) do
        if data.type and data.type:find("宠物装备") then
            table.insert(petEquips, { id = id, data = data })
        end
    end
    table.sort(petEquips, function(a, b) return a.id < b.id end)

    ShowMsg("共 " .. #petEquips .. " 件宠物装备")

    local dataArray = {}
    for _, item in ipairs(petEquips) do
        local id = item.id
        local data = item.data
        if not MatchSearch(data.name or id) then goto continue_pe end
        local statsStr = "部位:" .. (data.pet_slot or "未设") .. " 攻+" .. (data.pet_atk or 0) .. " 防+" .. (data.pet_def or 0) .. " 血+" .. (data.pet_hp or 0)
        table.insert(dataArray, {
            text = (data.name or id),
            subtext = statsStr,
            onEdit = function()
                -- 编辑宠物装备弹窗
                CloseDialog()
                local fieldWidgets = {}
                local formChildren = {}

                table.insert(formChildren, UI.Label {
                    text = "编辑宠物装备 - " .. (data.name or id),
                    fontSize = 16, fontColor = { 255, 200, 100, 255 },
                    textAlign = "center", marginBottom = 8,
                })

                local namePanel, nameField = CreateFormField("名称", data.name or id, { width = 180 })
                fieldWidgets["name"] = nameField
                table.insert(formChildren, namePanel)

                local slotPanel, getSlot = CreateButtonSelector(PET_EQUIP_SLOT_OPTIONS, data.pet_slot or "项圈", "部位", false)
                table.insert(formChildren, slotPanel)

                local descPanel, descField = CreateFormField("描述", data.desc or "", { width = 220 })
                fieldWidgets["desc"] = descField
                table.insert(formChildren, descPanel)

                local atkPanel, atkField = CreateFormField("宠物攻击", tostring(data.pet_atk or "10"), { width = 120, showUnit = true })
                fieldWidgets["pet_atk"] = atkField
                table.insert(formChildren, atkPanel)

                local defPanel, defField = CreateFormField("宠物防御", tostring(data.pet_def or "5"), { width = 120, showUnit = true })
                fieldWidgets["pet_def"] = defField
                table.insert(formChildren, defPanel)

                local hpPanel, hpField = CreateFormField("宠物生命", tostring(data.pet_hp or "20"), { width = 120, showUnit = true })
                fieldWidgets["pet_hp"] = hpField
                table.insert(formChildren, hpPanel)

                local dialogMsg = UI.Label { text = "", fontSize = 11, fontColor = { 100, 255, 100, 255 }, textAlign = "center", height = 16 }
                table.insert(formChildren, dialogMsg)

                table.insert(formChildren, UI.Panel {
                    flexDirection = "row", gap = 12, marginTop = 8, justifyContent = "center",
                    children = {
                        UI.Button {
                            text = "保存", variant = "primary", width = 80,
                            onClick = function()
                                DataManager.items[id] = {
                                    name = fieldWidgets["name"]:GetValue() or id,
                                    type = "宠物装备",
                                    value = "0",
                                    desc = fieldWidgets["desc"]:GetValue() or "",
                                    pet_slot = getSlot(),
                                    pet_atk = fieldWidgets["pet_atk"]:GetValue() or "10",
                                    pet_def = fieldWidgets["pet_def"]:GetValue() or "5",
                                    pet_hp = fieldWidgets["pet_hp"]:GetValue() or "20",
                                }
                                SaveCategoryToCloud("items")
                                dialogMsg:SetText("已保存")
                                CloseDialog()
                                RenderPetEquip()
                            end,
                        },
                        UI.Button { text = "关闭", variant = "secondary", width = 80, onClick = function() CloseDialog() end },
                    },
                })

                editDialog_ = UI.Panel {
                    width = "100%", height = "100%", position = "absolute",
                    justifyContent = "center", alignItems = "center", backgroundColor = { 0, 0, 0, 180 },
                    children = {
                        UI.ScrollView {
                            width = 380, maxHeight = 500, backgroundColor = { 30, 25, 55, 250 },
                            borderRadius = 12, padding = 16,
                            children = { UI.Panel { width = "100%", flexDirection = "column", gap = 4, children = formChildren } },
                        },
                    },
                }
                if rootPanel_ then rootPanel_:AddChild(editDialog_) end
            end,
            onDelete = function()
                DataManager.items[id] = nil
                SaveCategoryToCloud("items")
                RenderPetEquip()
            end,
        })
        ::continue_pe::
    end
    contentPanel_:AddChild(CreateVirtualDataList(dataArray))

    -- 添加新宠物装备
    contentPanel_:AddChild(UI.Button {
        text = "+ 添加宠物装备",
        variant = "primary", width = 140, marginTop = 8, marginLeft = 12,
        onClick = function()
            CloseDialog()
            local fieldWidgets = {}
            local formChildren = {}

            table.insert(formChildren, UI.Label {
                text = "添加新宠物装备",
                fontSize = 16, fontColor = { 255, 200, 100, 255 },
                textAlign = "center", marginBottom = 8,
            })

            local idPanel, idField = CreateFormField("装备ID", "", { width = 180, placeholder = "唯一标识" })
            fieldWidgets["id"] = idField
            table.insert(formChildren, idPanel)

            local namePanel, nameField = CreateFormField("名称", "", { width = 180 })
            fieldWidgets["name"] = nameField
            table.insert(formChildren, namePanel)

            local slotPanel, getSlot = CreateButtonSelector(PET_EQUIP_SLOT_OPTIONS, "项圈", "部位", false)
            table.insert(formChildren, slotPanel)

            local descPanel, descField = CreateFormField("描述", "", { width = 220 })
            fieldWidgets["desc"] = descField
            table.insert(formChildren, descPanel)

            local atkPanel, atkField = CreateFormField("宠物攻击", "10", { width = 120, showUnit = true })
            fieldWidgets["pet_atk"] = atkField
            table.insert(formChildren, atkPanel)

            local defPanel, defField = CreateFormField("宠物防御", "5", { width = 120, showUnit = true })
            fieldWidgets["pet_def"] = defField
            table.insert(formChildren, defPanel)

            local hpPanel, hpField = CreateFormField("宠物生命", "20", { width = 120, showUnit = true })
            fieldWidgets["pet_hp"] = hpField
            table.insert(formChildren, hpPanel)

            local dialogMsg = UI.Label { text = "", fontSize = 11, fontColor = { 100, 255, 100, 255 }, textAlign = "center", height = 16 }
            table.insert(formChildren, dialogMsg)

            table.insert(formChildren, UI.Panel {
                flexDirection = "row", gap = 12, marginTop = 8, justifyContent = "center",
                children = {
                    UI.Button {
                        text = "保存", variant = "primary", width = 80,
                        onClick = function()
                            local newId = fieldWidgets["id"]:GetValue() or ""
                            if newId == "" then
                                dialogMsg:SetText("请输入装备ID")
                                return
                            end
                            local name = fieldWidgets["name"]:GetValue() or ""
                            if name == "" then name = newId end
                            DataManager.items[newId] = {
                                name = name,
                                type = "宠物装备",
                                value = "0",
                                desc = fieldWidgets["desc"]:GetValue() or "",
                                pet_slot = getSlot(),
                                pet_atk = fieldWidgets["pet_atk"]:GetValue() or "10",
                                pet_def = fieldWidgets["pet_def"]:GetValue() or "5",
                                pet_hp = fieldWidgets["pet_hp"]:GetValue() or "20",
                            }
                            SaveCategoryToCloud("items")
                            dialogMsg:SetText("已保存")
                            CloseDialog()
                            RenderPetEquip()
                        end,
                    },
                    UI.Button { text = "关闭", variant = "secondary", width = 80, onClick = function() CloseDialog() end },
                },
            })

            editDialog_ = UI.Panel {
                width = "100%", height = "100%", position = "absolute",
                justifyContent = "center", alignItems = "center", backgroundColor = { 0, 0, 0, 180 },
                children = {
                    UI.ScrollView {
                        width = 380, maxHeight = 500, backgroundColor = { 30, 25, 55, 250 },
                        borderRadius = 12, padding = 16,
                        children = { UI.Panel { width = "100%", flexDirection = "column", gap = 4, children = formChildren } },
                    },
                },
            }
            if rootPanel_ then rootPanel_:AddChild(editDialog_) end
        end,
    })
end
--- 渲染宠物属性加成设置面板（公式模式）
local function RenderPetBonus()
    ClearContent()
    ShowMsg("宠物属性加成 - 递增公式")

    local config = DataManager.petConfig
    local formChildren = {}

    -- 标题
    table.insert(formChildren, UI.Label {
        text = "宠物属性加成公式设置", fontSize = 16, fontColor = { 255, 200, 100, 255 },
        textAlign = "center", marginBottom = 4,
    })
    table.insert(formChildren, UI.Label {
        text = "公式：第N级加成 = 基础值 + 递增 × (N-1)", fontSize = 11, fontColor = { 180, 180, 180, 255 },
        textAlign = "center", marginBottom = 4,
    })
    table.insert(formChildren, UI.Label {
        text = "例: 基础=10, 递增=5 → 1星+10, 2星+15, 3星+20 ...", fontSize = 10, fontColor = { 140, 140, 160, 255 },
        textAlign = "center", marginBottom = 12,
    })

    --- 创建一组配置（标题 + 基础值 + 递增值 输入框）
    local function CreateBonusGroup(title, titleColor, bonus)
        local fields = {}
        local _, atkF = CreateFormField("攻基础", tostring(bonus.atk or 0), { width = 55, height = 28 })
        local _, atkGF = CreateFormField("攻递增", tostring(bonus.atk_g or 0), { width = 55, height = 28 })
        local _, defF = CreateFormField("防基础", tostring(bonus.def or 0), { width = 55, height = 28 })
        local _, defGF = CreateFormField("防递增", tostring(bonus.def_g or 0), { width = 55, height = 28 })
        local _, hpF = CreateFormField("血基础", tostring(bonus.hp or 0), { width = 55, height = 28 })
        local _, hpGF = CreateFormField("血递增", tostring(bonus.hp_g or 0), { width = 55, height = 28 })
        fields.atk = atkF; fields.atk_g = atkGF
        fields.def = defF; fields.def_g = defGF
        fields.hp = hpF; fields.hp_g = hpGF

        local row = UI.Panel {
            flexDirection = "column", marginBottom = 10, padding = 8,
            backgroundColor = { 40, 35, 60, 200 }, borderRadius = 6,
            children = {
                UI.Label { text = title, fontSize = 13, fontColor = titleColor, marginBottom = 6 },
                UI.Panel {
                    flexDirection = "row", gap = 4, alignItems = "center", flexWrap = "wrap",
                    children = {
                        UI.Label { text = "攻:", fontSize = 11, width = 22 }, atkF,
                        UI.Label { text = "+", fontSize = 11, width = 12 }, atkGF,
                        UI.Label { text = "防:", fontSize = 11, width = 22 }, defF,
                        UI.Label { text = "+", fontSize = 11, width = 12 }, defGF,
                        UI.Label { text = "血:", fontSize = 11, width = 22 }, hpF,
                        UI.Label { text = "+", fontSize = 11, width = 12 }, hpGF,
                    },
                },
            },
        }
        return row, fields
    end

    -- 升星
    local sb = config.star_bonus or { atk = 10, def = 6, hp = 50, atk_g = 5, def_g = 3, hp_g = 25 }
    local starRow, starFields = CreateBonusGroup(
        "▶ 升星属性（基础 + 每级递增）", { 150, 220, 255, 255 }, sb
    )
    table.insert(formChildren, starRow)

    -- 进阶
    local ab = config.advance_bonus or { atk = 20, def = 12, hp = 100, atk_g = 10, def_g = 6, hp_g = 50 }
    local advRow, advFields = CreateBonusGroup(
        "▶ 进阶属性（基础 + 每级递增）", { 150, 255, 180, 255 }, ab
    )
    table.insert(formChildren, advRow)

    -- 品质
    local qb = config.quality_bonus or { atk = 15, def = 8, hp = 60, atk_g = 8, def_g = 4, hp_g = 30 }
    local qualRow, qualFields = CreateBonusGroup(
        "▶ 品质属性（基础 + 每级递增）", { 255, 200, 150, 255 }, qb
    )
    table.insert(formChildren, qualRow)

    -- 预览示例（用递增公式计算）
    local function previewSum(base, growth, n)
        if n <= 0 then return 0 end
        return math.floor(n * base + growth * n * (n - 1) / 2)
    end
    table.insert(formChildren, UI.Panel {
        padding = 6, backgroundColor = { 25, 30, 50, 200 }, borderRadius = 4, marginTop = 4,
        children = {
            UI.Label {
                text = "预览：3星攻+" .. previewSum(sb.atk, sb.atk_g or 0, 3) .. " 5阶攻+" .. previewSum(ab.atk, ab.atk_g or 0, 5) .. " 橙品(4级)攻+" .. previewSum(qb.atk, qb.atk_g or 0, 4),
                fontSize = 10, fontColor = { 180, 220, 255, 255 },
            },
            UI.Label {
                text = "（总加成 = 1级+2级+...+N级 的累加）",
                fontSize = 9, fontColor = { 130, 130, 150, 255 }, marginTop = 2,
            },
        },
    })

    -- ========== 消耗公式配置区域 ==========
    table.insert(formChildren, UI.Label {
        text = "── 升级消耗公式 ──", fontSize = 14, fontColor = { 255, 180, 100, 255 },
        textAlign = "center", marginTop = 12, marginBottom = 4,
    })
    table.insert(formChildren, UI.Label {
        text = "消耗公式：数量 = 基础 + 递增 × 当前等级（无上限）", fontSize = 10, fontColor = { 160, 160, 180, 255 },
        textAlign = "center", marginBottom = 8,
    })

    -- 升星消耗
    local _, starMatField = CreateFormField("升星材料名", config.star_cost_material or "升星石", { width = 80, height = 28 })
    local _, starCostBaseField = CreateFormField("基础消耗", tostring(config.star_cost_base or 100), { width = 60, height = 28 })
    local _, starCostGrowthField = CreateFormField("每级递增", tostring(config.star_cost_growth or 100), { width = 60, height = 28 })
    local _, starMaxLevelField = CreateFormField("升星上限", tostring(config.star_max_level or 30), { width = 50, height = 28 })
    table.insert(formChildren, UI.Panel {
        flexDirection = "column", marginBottom = 8, padding = 8,
        backgroundColor = { 40, 35, 60, 200 }, borderRadius = 6,
        children = {
            UI.Label { text = "▶ 升星消耗", fontSize = 13, fontColor = { 150, 220, 255, 255 }, marginBottom = 6 },
            UI.Panel {
                flexDirection = "row", gap = 4, alignItems = "center", flexWrap = "wrap",
                children = {
                    UI.Label { text = "材料:", fontSize = 11, width = 32 }, starMatField,
                    UI.Label { text = "基础:", fontSize = 11, width = 32 }, starCostBaseField,
                    UI.Label { text = "递增:", fontSize = 11, width = 32 }, starCostGrowthField,
                    UI.Label { text = "上限:", fontSize = 11, width = 32 }, starMaxLevelField,
                },
            },
            UI.Label {
                text = "例: 基础100,递增100 → 0→1星需100, 5→6星需600; 上限=30则最高30星",
                fontSize = 9, fontColor = { 130, 130, 150, 255 }, marginTop = 4,
            },
        },
    })

    -- 进阶消耗
    local _, advMatField = CreateFormField("进阶材料名", config.adv_cost_material or "进阶丹", { width = 80, height = 28 })
    local _, advCostBaseField = CreateFormField("基础消耗", tostring(config.adv_cost_base or 30), { width = 60, height = 28 })
    local _, advCostGrowthField = CreateFormField("每级递增", tostring(config.adv_cost_growth or 20), { width = 60, height = 28 })
    local _, advMaxLevelField = CreateFormField("进阶上限", tostring(config.adv_max_level or 10), { width = 50, height = 28 })
    table.insert(formChildren, UI.Panel {
        flexDirection = "column", marginBottom = 8, padding = 8,
        backgroundColor = { 40, 35, 60, 200 }, borderRadius = 6,
        children = {
            UI.Label { text = "▶ 进阶消耗", fontSize = 13, fontColor = { 150, 255, 180, 255 }, marginBottom = 6 },
            UI.Panel {
                flexDirection = "row", gap = 4, alignItems = "center", flexWrap = "wrap",
                children = {
                    UI.Label { text = "材料:", fontSize = 11, width = 32 }, advMatField,
                    UI.Label { text = "基础:", fontSize = 11, width = 32 }, advCostBaseField,
                    UI.Label { text = "递增:", fontSize = 11, width = 32 }, advCostGrowthField,
                    UI.Label { text = "上限:", fontSize = 11, width = 32 }, advMaxLevelField,
                },
            },
            UI.Label {
                text = "例: 基础30,递增20 → 0→1阶需30, 5→6阶需130; 上限=10则最高10阶",
                fontSize = 9, fontColor = { 130, 130, 150, 255 }, marginTop = 4,
            },
        },
    })

    -- 保存按钮
    local saveMsg = UI.Label { text = "", fontSize = 11, fontColor = { 100, 255, 100, 255 }, textAlign = "center", height = 18, marginTop = 10 }
    table.insert(formChildren, saveMsg)

    table.insert(formChildren, UI.Panel {
        flexDirection = "row", justifyContent = "center", gap = 12, marginTop = 4,
        children = {
            UI.Button {
                text = "保存", variant = "primary", width = 100,
                onClick = function()
                    -- 属性加成
                    config.star_bonus = {
                        atk = tonumber(starFields.atk:GetValue()) or 10,
                        def = tonumber(starFields.def:GetValue()) or 6,
                        hp = tonumber(starFields.hp:GetValue()) or 50,
                        atk_g = tonumber(starFields.atk_g:GetValue()) or 5,
                        def_g = tonumber(starFields.def_g:GetValue()) or 3,
                        hp_g = tonumber(starFields.hp_g:GetValue()) or 25,
                    }
                    config.advance_bonus = {
                        atk = tonumber(advFields.atk:GetValue()) or 20,
                        def = tonumber(advFields.def:GetValue()) or 12,
                        hp = tonumber(advFields.hp:GetValue()) or 100,
                        atk_g = tonumber(advFields.atk_g:GetValue()) or 10,
                        def_g = tonumber(advFields.def_g:GetValue()) or 6,
                        hp_g = tonumber(advFields.hp_g:GetValue()) or 50,
                    }
                    config.quality_bonus = {
                        atk = tonumber(qualFields.atk:GetValue()) or 15,
                        def = tonumber(qualFields.def:GetValue()) or 8,
                        hp = tonumber(qualFields.hp:GetValue()) or 60,
                        atk_g = tonumber(qualFields.atk_g:GetValue()) or 8,
                        def_g = tonumber(qualFields.def_g:GetValue()) or 4,
                        hp_g = tonumber(qualFields.hp_g:GetValue()) or 30,
                    }
                    -- 消耗公式
                    config.star_cost_material = starMatField:GetValue() or "升星石"
                    config.star_cost_base = tonumber(starCostBaseField:GetValue()) or 100
                    config.star_cost_growth = tonumber(starCostGrowthField:GetValue()) or 100
                    config.star_max_level = tonumber(starMaxLevelField:GetValue()) or 30
                    config.adv_cost_material = advMatField:GetValue() or "进阶丹"
                    config.adv_cost_base = tonumber(advCostBaseField:GetValue()) or 30
                    config.adv_cost_growth = tonumber(advCostGrowthField:GetValue()) or 20
                    config.adv_max_level = tonumber(advMaxLevelField:GetValue()) or 10
                    saveMsg:SetText("已保存（运行时生效）")
                end,
            },
        },
    })

    contentPanel_:AddChild(UI.ScrollView {
        width = "100%", height = "100%",
        children = { UI.Panel { width = "100%", flexDirection = "column", gap = 2, padding = 12, children = formChildren } },
    })
end

--- 渲染战魂管理面板
local function RenderBattleSoul()
    ClearContent()
    ShowMsg("战魂管理 - 配置战魂获取与升级")

    local config = DataManager.battleSoulConfig
    local formChildren = {}

    -- ====== 标题 ======
    table.insert(formChildren, UI.Label {
        text = "战魂系统配置", fontSize = 16, fontColor = { 200, 150, 255, 255 },
        textAlign = "center", marginBottom = 4,
    })
    table.insert(formChildren, UI.Label {
        text = "击杀怪物获得战魂经验，积累升级可增加属性", fontSize = 11, fontColor = { 180, 180, 180, 255 },
        textAlign = "center", marginBottom = 12,
    })

    -- ====== 升级公式区 ======
    table.insert(formChildren, UI.Label {
        text = "── 升级公式 ──", fontSize = 14, fontColor = { 255, 200, 100, 255 },
        textAlign = "center", marginBottom = 4,
    })
    table.insert(formChildren, UI.Label {
        text = "所需经验 = 基础值 + 成长值 × (等级 ^ 幂次)", fontSize = 10, fontColor = { 160, 160, 180, 255 },
        textAlign = "center", marginBottom = 8,
    })

    local formula = config.level_formula
    local _, baseField = CreateFormField("基础值", formula.base or "100", { width = 70, height = 28 })
    local _, growthField = CreateFormField("成长值", formula.growth or "50", { width = 70, height = 28 })
    local _, powerField = CreateFormField("幂次", formula.power or "1.5", { width = 70, height = 28 })

    table.insert(formChildren, UI.Panel {
        flexDirection = "column", padding = 8, marginBottom = 10,
        backgroundColor = { 40, 35, 60, 200 }, borderRadius = 6,
        children = {
            UI.Label { text = "▶ 升级公式参数", fontSize = 13, fontColor = { 150, 220, 255, 255 }, marginBottom = 6 },
            UI.Panel {
                flexDirection = "row", gap = 6, alignItems = "center", flexWrap = "wrap",
                children = {
                    UI.Label { text = "基础:", fontSize = 11, width = 32 }, baseField,
                    UI.Label { text = "成长:", fontSize = 11, width = 32 }, growthField,
                    UI.Label { text = "幂次:", fontSize = 11, width = 32 }, powerField,
                },
            },
            UI.Label {
                text = "预览：Lv1需" .. DataManager.GetBattleSoulExpNeeded(0) .. " Lv5需" .. DataManager.GetBattleSoulExpNeeded(4) .. " Lv10需" .. DataManager.GetBattleSoulExpNeeded(9),
                fontSize = 10, fontColor = { 180, 220, 255, 255 }, marginTop = 4,
            },
        },
    })

    -- ====== 每级属性加成区 ======
    table.insert(formChildren, UI.Label {
        text = "── 每级属性加成 ──", fontSize = 14, fontColor = { 100, 255, 180, 255 },
        textAlign = "center", marginTop = 8, marginBottom = 4,
    })
    table.insert(formChildren, UI.Label {
        text = "每升一级战魂增加的属性值", fontSize = 10, fontColor = { 160, 160, 180, 255 },
        textAlign = "center", marginBottom = 8,
    })

    local bonus = config.level_bonus
    local _, atkField = CreateFormField("攻击/级", bonus.atk or "5", { width = 60, height = 28 })
    local _, defField = CreateFormField("防御/级", bonus.def or "3", { width = 60, height = 28 })
    local _, maxHpField = CreateFormField("生命上限/级", bonus.max_hp or "20", { width = 60, height = 28 })

    table.insert(formChildren, UI.Panel {
        flexDirection = "column", padding = 8, marginBottom = 10,
        backgroundColor = { 40, 35, 60, 200 }, borderRadius = 6,
        children = {
            UI.Label { text = "▶ 每级加成数值", fontSize = 13, fontColor = { 150, 255, 180, 255 }, marginBottom = 6 },
            UI.Panel {
                flexDirection = "row", gap = 4, alignItems = "center", flexWrap = "wrap",
                children = {
                    UI.Label { text = "攻:", fontSize = 11, width = 22 }, atkField,
                    UI.Label { text = "防:", fontSize = 11, width = 22 }, defField,
                    UI.Label { text = "生命上限:", fontSize = 11, width = 55 }, maxHpField,
                },
            },
            UI.Label {
                text = "预览Lv10：攻+" .. tostring(10 * (tonumber(bonus.atk) or 5)) .. " 防+" .. tostring(10 * (tonumber(bonus.def) or 3)) .. " 生命上限+" .. tostring(10 * (tonumber(bonus.max_hp) or 20)),
                fontSize = 10, fontColor = { 180, 255, 200, 255 }, marginTop = 4,
            },
        },
    })

    -- ====== 怪物战魂获取区间 ======
    table.insert(formChildren, UI.Label {
        text = "── 怪物战魂获取区间 ──", fontSize = 14, fontColor = { 255, 150, 200, 255 },
        textAlign = "center", marginTop = 8, marginBottom = 4,
    })
    table.insert(formChildren, UI.Label {
        text = "根据怪物类型设定击杀获得的战魂经验范围", fontSize = 10, fontColor = { 160, 160, 180, 255 },
        textAlign = "center", marginBottom = 8,
    })

    -- 获取所有怪物类型
    local monsterTypes = DataManager.GetMonsterTypes()
    local monsterSoulFields = {}

    for _, typeName in ipairs(monsterTypes) do
        local soulCfg = config.monster_soul[typeName]
        local minVal = soulCfg and soulCfg.min or "1"
        local maxVal = soulCfg and soulCfg.max or "5"

        local _, minF = CreateFormField("最小", minVal, { width = 55, height = 28, labelWidth = 32 })
        local _, maxF = CreateFormField("最大", maxVal, { width = 55, height = 28, labelWidth = 32 })
        monsterSoulFields[typeName] = { minF = minF, maxF = maxF }

        table.insert(formChildren, UI.Panel {
            flexDirection = "row", padding = 6, marginBottom = 4, gap = 6,
            backgroundColor = { 45, 40, 65, 200 }, borderRadius = 4, alignItems = "center",
            children = {
                UI.Label { text = typeName, fontSize = 12, fontColor = { 220, 180, 255, 255 }, width = 70 },
                UI.Label { text = "最小:", fontSize = 10, width = 32 }, minF,
                UI.Label { text = "最大:", fontSize = 10, width = 32 }, maxF,
            },
        })
    end

    -- 如果没有怪物类型，显示提示
    if #monsterTypes == 0 then
        table.insert(formChildren, UI.Label {
            text = "暂无怪物类型，请先在怪物管理中添加怪物", fontSize = 12,
            fontColor = { 255, 150, 100, 255 }, textAlign = "center", marginTop = 8,
        })
    end

    -- ====== 保存按钮 ======
    table.insert(formChildren, UI.Button {
        text = "保存战魂配置", variant = "primary", marginTop = 16,
        onClick = function()
            -- 收集公式参数
            config.level_formula.base = baseField:GetText() ~= "" and baseField:GetText() or "100"
            config.level_formula.growth = growthField:GetText() ~= "" and growthField:GetText() or "50"
            config.level_formula.power = powerField:GetText() ~= "" and powerField:GetText() or "1.5"
            -- 收集每级加成
            config.level_bonus.atk = atkField:GetText() ~= "" and atkField:GetText() or "5"
            config.level_bonus.def = defField:GetText() ~= "" and defField:GetText() or "3"
            config.level_bonus.max_hp = maxHpField:GetText() ~= "" and maxHpField:GetText() or "20"
            -- 收集怪物战魂区间
            for typeName, fields in pairs(monsterSoulFields) do
                local minStr = fields.minF:GetText()
                local maxStr = fields.maxF:GetText()
                if minStr ~= "" and maxStr ~= "" then
                    config.monster_soul[typeName] = { min = minStr, max = maxStr }
                end
            end
            DataManager.battleSoulConfig = config
            SaveCategoryToCloud("battle_soul")
        end,
    })

    contentPanel_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "column",
        padding = 12,
        children = formChildren,
    })
end

--- 渲染一键生成面板
local function RenderGenerator()
    ClearContent()
    ShowMsg("一键生成 - 快速生成游戏数据")

    -- 生成数量输入引用
    local genFields = {}

    --- 创建一个生成区块
    ---@param title string 区块标题
    ---@param key string 类型 key
    ---@param defaultNum string 默认数量
    ---@param onGenerate fun(count: number): number 生成回调，返回生成数量
    local function CreateGenSection(title, key, defaultNum, onGenerate)
        local numField = UI.TextField {
            value = defaultNum,
            placeholder = "数量",
            width = 60,
            height = 30,
            fontSize = 13,
        }
        genFields[key] = numField

        local resultLabel = UI.Label {
            text = "",
            fontSize = 11,
            fontColor = { 100, 255, 150, 255 },
            height = 16,
        }

        return UI.Panel {
            width = "100%",
            flexDirection = "column",
            backgroundColor = { 25, 20, 45, 200 },
            borderRadius = 8,
            padding = 12,
            marginBottom = 8,
            children = {
                UI.Label {
                    text = title,
                    fontSize = 14,
                    fontColor = { 255, 200, 100, 255 },
                    marginBottom = 6,
                },
                UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 8,
                    children = {
                        UI.Label {
                            text = "一键生成",
                            fontSize = 12,
                            fontColor = { 200, 200, 220, 255 },
                        },
                        numField,
                        UI.Label {
                            text = "个" .. title,
                            fontSize = 12,
                            fontColor = { 200, 200, 220, 255 },
                        },
                        UI.Button {
                            text = "生成",
                            variant = "primary",
                            width = 60,
                            height = 28,
                            fontSize = 12,
                            onClick = function()
                                local n = tonumber(numField:GetValue()) or 0
                                if n <= 0 then
                                    resultLabel:SetText("请输入有效数量")
                                    return
                                end
                                if n > 100 then n = 100 end -- 上限保护
                                local generated, skipped = onGenerate(n)
                                skipped = skipped or 0
                                if skipped > 0 and generated == 0 then
                                    resultLabel:SetText("已有" .. skipped .. "条数据存在，无需生成")
                                elseif skipped > 0 then
                                    resultLabel:SetText("生成" .. generated .. "个，跳过" .. skipped .. "个(已存在)")
                                else
                                    resultLabel:SetText("成功生成 " .. generated .. " 个" .. title)
                                end
                                ShowMsg(title .. ": 生成" .. generated .. "个, 跳过" .. skipped .. "个")
                            end,
                        },
                    },
                },
                resultLabel,
            },
        }
    end

    -- 各类型生成区块
    local mapSection = CreateGenSection("地图", "maps", "5", GenerateMaps)

    -- === 怪物生成（含类型选择 + 自定义区间） ===
    local monsterNumField = UI.TextField { value = "10", placeholder = "数量", width = 60, height = 30, fontSize = 13 }
    genFields["monsters"] = monsterNumField
    local monsterResultLabel = UI.Label { text = "", fontSize = 11, fontColor = { 100, 255, 150, 255 }, height = 16 }
    local selectedMonsterType = 1  -- 默认普通怪

    -- 三组区间输入框：战斗属性 / 经验 / 金币
    -- 计数单位标签辅助函数
    local function makeUnitLabel(val)
        return UI.Label { text = NumFormat.Short(val), fontSize = 9, fontColor = { 140, 200, 140, 255 }, marginLeft = 2, width = 55 }
    end
    local function updateUnitLabel(label, text)
        local v = text or "0"
        if v == "" then v = "0" end
        label:SetText(NumFormat.Short(v))
    end
    -- HP/ATK/DEF/EXP 独立区间输入框 + 单位标签
    local monsterMinHpUnit = makeUnitLabel(MONSTER_TYPES[1].min_hp)
    local monsterMaxHpUnit = makeUnitLabel(MONSTER_TYPES[1].max_hp)
    local monsterMinAtkUnit = makeUnitLabel(MONSTER_TYPES[1].min_atk)
    local monsterMaxAtkUnit = makeUnitLabel(MONSTER_TYPES[1].max_atk)
    local monsterMinDefUnit = makeUnitLabel(MONSTER_TYPES[1].min_def)
    local monsterMaxDefUnit = makeUnitLabel(MONSTER_TYPES[1].max_def)
    local monsterMinExpUnit = makeUnitLabel(MONSTER_TYPES[1].min_exp)
    local monsterMaxExpUnit = makeUnitLabel(MONSTER_TYPES[1].max_exp)
    local monsterMinHpField = UI.TextField { value = MONSTER_TYPES[1].min_hp, placeholder = "HP下限", width = 90, height = 24, fontSize = 10, onChange = function(_, t) updateUnitLabel(monsterMinHpUnit, t) end }
    local monsterMaxHpField = UI.TextField { value = MONSTER_TYPES[1].max_hp, placeholder = "HP上限", width = 90, height = 24, fontSize = 10, onChange = function(_, t) updateUnitLabel(monsterMaxHpUnit, t) end }
    local monsterMinAtkField = UI.TextField { value = MONSTER_TYPES[1].min_atk, placeholder = "攻击下限", width = 90, height = 24, fontSize = 10, onChange = function(_, t) updateUnitLabel(monsterMinAtkUnit, t) end }
    local monsterMaxAtkField = UI.TextField { value = MONSTER_TYPES[1].max_atk, placeholder = "攻击上限", width = 90, height = 24, fontSize = 10, onChange = function(_, t) updateUnitLabel(monsterMaxAtkUnit, t) end }
    local monsterMinDefField = UI.TextField { value = MONSTER_TYPES[1].min_def, placeholder = "防御下限", width = 90, height = 24, fontSize = 10, onChange = function(_, t) updateUnitLabel(monsterMinDefUnit, t) end }
    local monsterMaxDefField = UI.TextField { value = MONSTER_TYPES[1].max_def, placeholder = "防御上限", width = 90, height = 24, fontSize = 10, onChange = function(_, t) updateUnitLabel(monsterMaxDefUnit, t) end }
    local monsterMinExpField = UI.TextField { value = MONSTER_TYPES[1].min_exp, placeholder = "经验下限", width = 90, height = 24, fontSize = 10, onChange = function(_, t) updateUnitLabel(monsterMinExpUnit, t) end }
    local monsterMaxExpField = UI.TextField { value = MONSTER_TYPES[1].max_exp, placeholder = "经验上限", width = 90, height = 24, fontSize = 10, onChange = function(_, t) updateUnitLabel(monsterMaxExpUnit, t) end }
    local monsterRangeLabel = UI.Label { text = "当前类型: " .. MONSTER_TYPES[1].name, fontSize = 11, fontColor = { 180, 180, 255, 255 } }

    -- 货币区间输入框（动态，按 currencies 列表生成）
    local currencyFields = {} -- { [货币名] = { minField, maxField } }
    local currencyFieldPanels = {} -- UI panels for each currency row
    local currencies = DataManager.gameConfig["currencies"] or { "金币" }

    local function buildCurrencyFields(mtype)
        currencyFields = {}
        currencyFieldPanels = {}
        for _, cName in ipairs(currencies) do
            local cRange = (mtype.currency_ranges and mtype.currency_ranges[cName]) or { min = "0", max = "0" }
            local minUnit = makeUnitLabel(cRange.min)
            local maxUnit = makeUnitLabel(cRange.max)
            local minF = UI.TextField { value = cRange.min, placeholder = cName .. "下限", width = 90, height = 24, fontSize = 10, onChange = function(_, t) updateUnitLabel(minUnit, t) end }
            local maxF = UI.TextField { value = cRange.max, placeholder = cName .. "上限", width = 90, height = 24, fontSize = 10, onChange = function(_, t) updateUnitLabel(maxUnit, t) end }
            currencyFields[cName] = { minField = minF, maxField = maxF, minUnit = minUnit, maxUnit = maxUnit }
            table.insert(currencyFieldPanels, UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4, marginTop = 3,
                flexWrap = "wrap",
                children = {
                    UI.Label { text = cName .. ":", fontSize = 10, fontColor = { 200, 200, 220, 255 }, width = 40 },
                    minF, minUnit,
                    UI.Label { text = "~", fontSize = 10, fontColor = { 200, 200, 220, 255 } },
                    maxF, maxUnit,
                },
            })
        end
    end
    buildCurrencyFields(MONSTER_TYPES[1])

    -- 刷新区间显示
    local function refreshMonsterRangeFields()
        local mtype = MONSTER_TYPES[selectedMonsterType]
        monsterMinHpField:SetValue(mtype.min_hp or "10")
        monsterMaxHpField:SetValue(mtype.max_hp or "2000")
        monsterMinAtkField:SetValue(mtype.min_atk or "5")
        monsterMaxAtkField:SetValue(mtype.max_atk or "1000")
        monsterMinDefField:SetValue(mtype.min_def or "3")
        monsterMaxDefField:SetValue(mtype.max_def or "800")
        monsterMinExpField:SetValue(mtype.min_exp or "5")
        monsterMaxExpField:SetValue(mtype.max_exp or "500")
        -- 刷新单位标签
        updateUnitLabel(monsterMinHpUnit, mtype.min_hp or "10")
        updateUnitLabel(monsterMaxHpUnit, mtype.max_hp or "2000")
        updateUnitLabel(monsterMinAtkUnit, mtype.min_atk or "5")
        updateUnitLabel(monsterMaxAtkUnit, mtype.max_atk or "1000")
        updateUnitLabel(monsterMinDefUnit, mtype.min_def or "3")
        updateUnitLabel(monsterMaxDefUnit, mtype.max_def or "800")
        updateUnitLabel(monsterMinExpUnit, mtype.min_exp or "5")
        updateUnitLabel(monsterMaxExpUnit, mtype.max_exp or "500")
        -- 刷新货币字段
        for _, cName in ipairs(currencies) do
            local cRange = (mtype.currency_ranges and mtype.currency_ranges[cName]) or { min = "0", max = "0" }
            if currencyFields[cName] then
                currencyFields[cName].minField:SetValue(cRange.min)
                currencyFields[cName].maxField:SetValue(cRange.max)
                updateUnitLabel(currencyFields[cName].minUnit, cRange.min)
                updateUnitLabel(currencyFields[cName].maxUnit, cRange.max)
            end
        end
        monsterRangeLabel:SetText("当前类型: " .. mtype.name)
    end

    local monsterTypeBtns = {}
    local function refreshMonsterTypeBtns()
        for idx, btn in ipairs(monsterTypeBtns) do
            btn:SetVariant(idx == selectedMonsterType and "primary" or "secondary")
        end
    end
    local monsterTypeBtnChildren = {}
    for idx, mtype in ipairs(MONSTER_TYPES) do
        local btn = UI.Button {
            text = mtype.name, fontSize = 10, width = 52, height = 22,
            variant = idx == 1 and "primary" or "secondary",
            onClick = function()
                selectedMonsterType = idx
                refreshMonsterTypeBtns()
                refreshMonsterRangeFields()
            end,
        }
        monsterTypeBtns[idx] = btn
        table.insert(monsterTypeBtnChildren, btn)
    end

    --- 验证并保存怪物区间
    local function saveMonsterRanges()
        local function trimVal(field)
            return ((field:GetValue() or ""):match("^%s*(.-)%s*$")) or ""
        end
        local newMinHp = trimVal(monsterMinHpField)
        local newMaxHp = trimVal(monsterMaxHpField)
        local newMinAtk = trimVal(monsterMinAtkField)
        local newMaxAtk = trimVal(monsterMaxAtkField)
        local newMinDef = trimVal(monsterMinDefField)
        local newMaxDef = trimVal(monsterMaxDefField)
        local newMinExp = trimVal(monsterMinExpField)
        local newMaxExp = trimVal(monsterMaxExpField)
        -- 验证基础字段
        local baseFields = { newMinHp, newMaxHp, newMinAtk, newMaxAtk, newMinDef, newMaxDef, newMinExp, newMaxExp }
        for _, v in ipairs(baseFields) do
            if v == "" then
                monsterResultLabel:SetText("所有区间字段不能为空")
                return
            end
            if not v:match("^%d+$") then
                monsterResultLabel:SetText("区间必须为正整数")
                return
            end
        end
        -- 验证下限<=上限
        if BigNum.gt(newMinHp, newMaxHp) then
            monsterResultLabel:SetText("生命: 下限不能大于上限")
            return
        end
        if BigNum.gt(newMinAtk, newMaxAtk) then
            monsterResultLabel:SetText("攻击: 下限不能大于上限")
            return
        end
        if BigNum.gt(newMinDef, newMaxDef) then
            monsterResultLabel:SetText("防御: 下限不能大于上限")
            return
        end
        if BigNum.gt(newMinExp, newMaxExp) then
            monsterResultLabel:SetText("经验: 下限不能大于上限")
            return
        end
        -- 验证货币字段
        local newCurrRanges = {}
        for _, cName in ipairs(currencies) do
            local cf = currencyFields[cName]
            if cf then
                local cMin = trimVal(cf.minField)
                local cMax = trimVal(cf.maxField)
                if cMin == "" or cMax == "" then
                    monsterResultLabel:SetText(cName .. ": 区间不能为空")
                    return
                end
                if not cMin:match("^%d+$") or not cMax:match("^%d+$") then
                    monsterResultLabel:SetText(cName .. ": 区间必须为正整数")
                    return
                end
                if BigNum.gt(cMin, cMax) then
                    monsterResultLabel:SetText(cName .. ": 下限不能大于上限")
                    return
                end
                newCurrRanges[cName] = { min = cMin, max = cMax }
            end
        end
        local mt = MONSTER_TYPES[selectedMonsterType]
        mt.min_hp = newMinHp
        mt.max_hp = newMaxHp
        mt.min_atk = newMinAtk
        mt.max_atk = newMaxAtk
        mt.min_def = newMinDef
        mt.max_def = newMaxDef
        mt.min_exp = newMinExp
        mt.max_exp = newMaxExp
        mt.currency_ranges = newCurrRanges
        DataManager.gameConfig["monster_gen"] = MONSTER_TYPES
        SaveCategoryToCloud("game_config")
        monsterResultLabel:SetText(mt.name .. " 所有区间已保存")
    end

    local monsterSection = UI.Panel {
        width = "100%",
        flexDirection = "column",
        backgroundColor = { 25, 20, 45, 200 },
        borderRadius = 8,
        padding = 12,
        marginBottom = 8,
        children = {
            UI.Label {
                text = "怪物",
                fontSize = 14,
                fontColor = { 255, 200, 100, 255 },
                marginBottom = 6,
            },
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4, marginBottom = 6,
                flexWrap = "wrap",
                children = (function()
                    local c = { UI.Label { text = "类型:", fontSize = 11, fontColor = { 200, 200, 220, 255 } } }
                    for _, btn in ipairs(monsterTypeBtnChildren) do table.insert(c, btn) end
                    return c
                end)(),
            },
            -- 自定义区间编辑
            monsterRangeLabel,
            -- 生命区间
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4, marginTop = 4,
                flexWrap = "wrap",
                children = {
                    UI.Label { text = "生命:", fontSize = 10, fontColor = { 200, 200, 220, 255 }, width = 40 },
                    monsterMinHpField, monsterMinHpUnit,
                    UI.Label { text = "~", fontSize = 10, fontColor = { 200, 200, 220, 255 } },
                    monsterMaxHpField, monsterMaxHpUnit,
                },
            },
            -- 攻击区间
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4, marginTop = 3,
                flexWrap = "wrap",
                children = {
                    UI.Label { text = "攻击:", fontSize = 10, fontColor = { 200, 200, 220, 255 }, width = 40 },
                    monsterMinAtkField, monsterMinAtkUnit,
                    UI.Label { text = "~", fontSize = 10, fontColor = { 200, 200, 220, 255 } },
                    monsterMaxAtkField, monsterMaxAtkUnit,
                },
            },
            -- 防御区间
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4, marginTop = 3,
                flexWrap = "wrap",
                children = {
                    UI.Label { text = "防御:", fontSize = 10, fontColor = { 200, 200, 220, 255 }, width = 40 },
                    monsterMinDefField, monsterMinDefUnit,
                    UI.Label { text = "~", fontSize = 10, fontColor = { 200, 200, 220, 255 } },
                    monsterMaxDefField, monsterMaxDefUnit,
                },
            },
            -- 经验区间
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4, marginTop = 3,
                flexWrap = "wrap",
                children = {
                    UI.Label { text = "经验:", fontSize = 10, fontColor = { 200, 200, 220, 255 }, width = 40 },
                    monsterMinExpField, monsterMinExpUnit,
                    UI.Label { text = "~", fontSize = 10, fontColor = { 200, 200, 220, 255 } },
                    monsterMaxExpField, monsterMaxExpUnit,
                },
            },
            -- 货币区间（动态，按配置的货币列表生成）
            UI.Panel {
                flexDirection = "column", marginTop = 3, marginBottom = 4, width = "100%",
                children = currencyFieldPanels,
            },
            UI.Button {
                text = "保存区间", variant = "secondary", width = 80, height = 26, fontSize = 11, marginBottom = 6,
                onClick = saveMonsterRanges,
            },
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 8,
                children = {
                    UI.Label { text = "一键生成", fontSize = 12, fontColor = { 200, 200, 220, 255 } },
                    monsterNumField,
                    UI.Label { text = "个怪物", fontSize = 12, fontColor = { 200, 200, 220, 255 } },
                    UI.Button {
                        text = "生成", variant = "primary", width = 60, height = 28, fontSize = 12,
                        onClick = function()
                            local n = tonumber(monsterNumField:GetValue()) or 0
                            if n <= 0 then
                                monsterResultLabel:SetText("请输入有效数量")
                                return
                            end
                            if n > 100 then n = 100 end
                            local generated, skipped = GenerateMonsters(n, selectedMonsterType)
                            skipped = skipped or 0
                            local typeName = MONSTER_TYPES[selectedMonsterType].name
                            if skipped > 0 and generated == 0 then
                                monsterResultLabel:SetText("已有" .. skipped .. "条" .. typeName .. "数据存在，无需生成")
                            elseif skipped > 0 then
                                monsterResultLabel:SetText("生成" .. generated .. "个，跳过" .. skipped .. "个(已存在)")
                            else
                                monsterResultLabel:SetText("成功生成 " .. generated .. " 个" .. typeName)
                            end
                            ShowMsg(typeName .. ": 生成" .. generated .. "个, 跳过" .. skipped .. "个")
                        end,
                    },
                },
            },
            monsterResultLabel,
        },
    }
    -- === 装备生成（含部位+品质选择） ===
    local equipNumField = UI.TextField { value = "10", placeholder = "数量", width = 60, height = 30, fontSize = 13 }
    genFields["equipment"] = equipNumField
    local equipResultLabel = UI.Label { text = "", fontSize = 11, fontColor = { 100, 255, 150, 255 }, height = 16 }

    -- 部位多选
    local equipSlotBtns = {}
    local equipSlotSelected = {}
    for _, s in ipairs(GetEquipSlotLabels()) do equipSlotSelected[s] = true end
    local function refreshEquipSlotBtns()
        for name, btn in pairs(equipSlotBtns) do
            btn:SetVariant(equipSlotSelected[name] and "primary" or "secondary")
        end
    end
    local equipSlotChildren = {}
    for _, slotName in ipairs(GetEquipSlotLabels()) do
        local btn = UI.Button {
            text = slotName, fontSize = 9, width = 42, height = 20,
            variant = "primary",
            onClick = function()
                if equipSlotSelected[slotName] then
                    local cnt = 0; for _ in pairs(equipSlotSelected) do cnt = cnt + 1 end
                    if cnt > 1 then equipSlotSelected[slotName] = nil end
                else
                    equipSlotSelected[slotName] = true
                end
                refreshEquipSlotBtns()
            end,
        }
        equipSlotBtns[slotName] = btn
        table.insert(equipSlotChildren, btn)
    end

    -- 品质多选
    local equipQualBtns = {}
    local equipQualSelected = { ["白色"] = true, ["绿色"] = true, ["橙色"] = true, ["红色"] = true, ["彩色"] = true, ["地级"] = true, ["天级"] = true, ["帝级"] = true, ["仙级"] = true, ["神级"] = true, ["创世级"] = true }
    local function refreshEquipQualBtns()
        for name, btn in pairs(equipQualBtns) do
            btn:SetVariant(equipQualSelected[name] and "primary" or "secondary")
        end
    end
    local equipQualChildren = {}
    for _, qName in ipairs(EQUIP_QUALITIES) do
        local btn = UI.Button {
            text = qName, fontSize = 9, width = 42, height = 20,
            variant = "primary",
            onClick = function()
                if equipQualSelected[qName] then
                    local cnt = 0; for _ in pairs(equipQualSelected) do cnt = cnt + 1 end
                    if cnt > 1 then equipQualSelected[qName] = nil end
                else
                    equipQualSelected[qName] = true
                end
                refreshEquipQualBtns()
            end,
        }
        equipQualBtns[qName] = btn
        table.insert(equipQualChildren, btn)
    end

    -- 自定义套装输入
    local setNameField = UI.TextField { value = "", placeholder = "套装前缀名", width = 100, height = 28, fontSize = 12 }
    local setResultLabel = UI.Label { text = "", fontSize = 11, fontColor = { 100, 255, 150, 255 }, height = 16 }

    local equipSection = UI.Panel {
        width = "100%", flexDirection = "column",
        backgroundColor = { 25, 20, 45, 200 }, borderRadius = 8, padding = 12, marginBottom = 8,
        children = {
            UI.Label { text = "装备", fontSize = 14, fontColor = { 255, 200, 100, 255 }, marginBottom = 6 },
            UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, marginBottom = 4, children = {
                UI.Label { text = "部位", fontSize = 12, fontColor = { 180, 180, 200, 255 }, width = 40 },
                UI.Panel { flexDirection = "row", flexWrap = "wrap", gap = 3, children = equipSlotChildren },
            }},
            UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, marginBottom = 6, children = {
                UI.Label { text = "品质", fontSize = 12, fontColor = { 180, 180, 200, 255 }, width = 40 },
                UI.Panel { flexDirection = "row", flexWrap = "wrap", gap = 3, children = equipQualChildren },
            }},
            UI.Panel { flexDirection = "row", alignItems = "center", gap = 8, marginBottom = 6, children = {
                UI.Label { text = "一键生成", fontSize = 12, fontColor = { 200, 200, 220, 255 } },
                equipNumField,
                UI.Label { text = "个装备", fontSize = 12, fontColor = { 200, 200, 220, 255 } },
                UI.Button { text = "生成", variant = "primary", width = 60, height = 28, fontSize = 12,
                    onClick = function()
                        local n = tonumber(equipNumField:GetValue()) or 0
                        if n <= 0 then equipResultLabel:SetText("请输入有效数量"); return end
                        if n > 100 then n = 100 end
                        local selSlots = {}
                        for _, s in ipairs(GetEquipSlotLabels()) do
                            if equipSlotSelected[s] then table.insert(selSlots, s) end
                        end
                        local selQuals = {}
                        for _, q in ipairs(EQUIP_QUALITIES) do
                            if equipQualSelected[q] then table.insert(selQuals, q) end
                        end
                        local generated, skipped = GenerateEquipment(n, selSlots, selQuals)
                        skipped = skipped or 0
                        if skipped > 0 and generated == 0 then
                            equipResultLabel:SetText("已有" .. skipped .. "条装备数据存在，无需生成")
                        elseif skipped > 0 then
                            equipResultLabel:SetText("生成" .. generated .. "个，跳过" .. skipped .. "个(已存在)")
                        else
                            equipResultLabel:SetText("成功生成 " .. generated .. " 个装备")
                        end
                        ShowMsg("装备: 生成" .. generated .. "个, 跳过" .. skipped .. "个")
                    end,
                },
            }},
            equipResultLabel,
            -- 自定义套装区域
            UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, marginTop = 6, children = {
                UI.Label { text = "套装前缀", fontSize = 12, fontColor = { 180, 180, 200, 255 } },
                setNameField,
                UI.Button { text = "生成套装", variant = "primary", width = 80, height = 28, fontSize = 11,
                    onClick = function()
                        local prefix = setNameField:GetValue() or ""
                        if prefix == "" then setResultLabel:SetText("请输入套装前缀名"); return end
                        -- 从选中的品质中随机取一个作为套装品质
                        local selQuals = {}
                        for _, q in ipairs(EQUIP_QUALITIES) do
                            if equipQualSelected[q] then table.insert(selQuals, q) end
                        end
                        if #selQuals == 0 then selQuals = { "橙色" } end
                        local quality = selQuals[math.random(1, #selQuals)]
                        local range = EQUIP_QUALITY_RANGES[quality]
                        local generated = 0
                        local skipped = 0
                        -- 为每个选中的部位生成一件装备
                        local selSlots = {}
                        for _, s in ipairs(GetEquipSlotLabels()) do
                            if equipSlotSelected[s] then table.insert(selSlots, s) end
                        end
                        if #selSlots == 0 then for _, s in ipairs(GetEquipSlotLabels()) do table.insert(selSlots, s) end end
                        for _, slotCN in ipairs(selSlots) do
                            local slot = EQUIP_SLOT_MAP[slotCN] or "weapon"
                            local suffixTable = GEN_NAMES["equip_" .. slot] or GEN_NAMES.equip_weapon
                            local name = TryUniqueName(function()
                                return prefix .. RandPick(suffixTable)
                            end, DataManager.equipment)
                            if not name then skipped = skipped + 1; goto set_continue end
                            local baseVal = BigNumRandRange(range.min, range.max)
                            local subMax = BigNum.div(BigNum.add(range.min, range.max), "3")
                            if BigNum.gt(range.min, subMax) then subMax = range.min end
                            local subVal = BigNumRandRange(range.min, subMax)
                            local atkVal, defVal, hpVal
                            if slot == "weapon" or slot == "artifact" or slot == "ring" then
                                atkVal = baseVal; defVal = subVal; hpVal = BigNumRandRange(range.min, subMax)
                            elseif slot == "armor" or slot == "helmet" or slot == "bracer" or slot == "shield" then
                                defVal = baseVal; atkVal = subVal; hpVal = BigNumRandRange(range.min, subMax)
                            else
                                hpVal = baseVal; atkVal = subVal; defVal = BigNumRandRange(range.min, subMax)
                            end
                            local lvReq = tostring(math.random(1, 100))
                            local price = BigNum.mul(baseVal, tostring(math.random(2, 5)))
                            local sell = BigNum.div(price, "3")
                            DataManager.equipment[name] = {
                                name = name, slot = slotCN, quality = quality,
                                desc = prefix .. "套装之" .. name .. "，" .. quality .. "品质",
                                atk = atkVal, def = defVal, hp = hpVal,
                                level_req = lvReq, price_sell = sell,
                            }
                            generated = generated + 1
                            ::set_continue::
                        end
                        if generated > 0 then SaveCategoryToCloud("equipment") end
                        if skipped > 0 and generated == 0 then
                            setResultLabel:SetText("[" .. prefix .. "]套装已存在，无需重复生成")
                        elseif skipped > 0 then
                            setResultLabel:SetText("生成" .. generated .. "件，跳过" .. skipped .. "件(已存在)")
                        else
                            setResultLabel:SetText("已生成[" .. prefix .. "]套装 " .. generated .. " 件")
                        end
                        ShowMsg("套装: 生成" .. generated .. "件, 跳过" .. skipped .. "件")
                    end,
                },
            }},
            setResultLabel,
        },
    }

    -- === 道具生成（含类型多选+限时输入） ===
    local itemNumField = UI.TextField { value = "10", placeholder = "数量", width = 60, height = 30, fontSize = 13 }
    genFields["items"] = itemNumField
    local itemResultLabel = UI.Label { text = "", fontSize = 11, fontColor = { 100, 255, 150, 255 }, height = 16 }

    -- 道具类型多选
    local itemTypeBtns = {}
    local itemTypeSelected = { ["恢复血量"] = true, ["材料"] = true }
    local function refreshItemTypeBtns()
        for name, btn in pairs(itemTypeBtns) do
            btn:SetVariant(itemTypeSelected[name] and "primary" or "secondary")
        end
    end
    local itemTypeBtnChildren = {}
    for _, typeName in ipairs(ITEM_TYPES) do
        local btn = UI.Button {
            text = typeName, fontSize = 10, width = 56, height = 22,
            variant = itemTypeSelected[typeName] and "primary" or "secondary",
            onClick = function()
                if itemTypeSelected[typeName] then
                    local cnt = 0; for _ in pairs(itemTypeSelected) do cnt = cnt + 1 end
                    if cnt > 1 then itemTypeSelected[typeName] = nil end
                else
                    itemTypeSelected[typeName] = true
                end
                refreshItemTypeBtns()
            end,
        }
        itemTypeBtns[typeName] = btn
        table.insert(itemTypeBtnChildren, btn)
    end

    -- 限时输入框（选中限时类相关类型时可用）
    local itemDurationField = UI.TextField { value = "0", placeholder = "分(0=永久)", width = 80, height = 28, fontSize = 12 }

    -- 自定义倍率输入框
    local customMultField = UI.TextField { value = "10", placeholder = "倍率", width = 60, height = 28, fontSize = 12 }
    local customMultResultLabel = UI.Label { text = "", fontSize = 11, fontColor = { 100, 255, 150, 255 }, height = 16 }

    local itemSection = UI.Panel {
        width = "100%", flexDirection = "column",
        backgroundColor = { 25, 20, 45, 200 }, borderRadius = 8, padding = 12, marginBottom = 8,
        children = {
            UI.Label { text = "道具", fontSize = 14, fontColor = { 255, 200, 100, 255 }, marginBottom = 6 },
            UI.Panel { flexDirection = "column", gap = 2, marginBottom = 4, children = {
                UI.Label { text = "类型（可多选）", fontSize = 12, fontColor = { 180, 180, 200, 255 } },
                UI.Panel { flexDirection = "row", flexWrap = "wrap", gap = 3, children = itemTypeBtnChildren },
            }},
            UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, marginBottom = 6, children = {
                UI.Label { text = "限时", fontSize = 12, fontColor = { 180, 180, 200, 255 } },
                itemDurationField,
                UI.Label { text = "分钟 (0=永久)", fontSize = 10, fontColor = { 140, 140, 160, 255 } },
            }},
            UI.Panel { flexDirection = "row", alignItems = "center", gap = 8, marginBottom = 6, children = {
                UI.Label { text = "一键生成", fontSize = 12, fontColor = { 200, 200, 220, 255 } },
                itemNumField,
                UI.Label { text = "个道具", fontSize = 12, fontColor = { 200, 200, 220, 255 } },
                UI.Button { text = "生成", variant = "primary", width = 60, height = 28, fontSize = 12,
                    onClick = function()
                        local n = tonumber(itemNumField:GetValue()) or 0
                        if n <= 0 then itemResultLabel:SetText("请输入有效数量"); return end
                        if n > 100 then n = 100 end
                        local selTypes = {}
                        for _, t in ipairs(ITEM_TYPES) do
                            if itemTypeSelected[t] then table.insert(selTypes, t) end
                        end
                        local dur = tonumber(itemDurationField:GetValue()) or 0
                        local generated, skipped = GenerateItems(n, selTypes, dur)
                        skipped = skipped or 0
                        if skipped > 0 and generated == 0 then
                            itemResultLabel:SetText("已有" .. skipped .. "条道具数据存在，无需生成")
                        elseif skipped > 0 then
                            itemResultLabel:SetText("生成" .. generated .. "个，跳过" .. skipped .. "个(已存在)")
                        else
                            itemResultLabel:SetText("成功生成 " .. generated .. " 个道具")
                        end
                        ShowMsg("道具: 生成" .. generated .. "个, 跳过" .. skipped .. "个")
                    end,
                },
            }},
            itemResultLabel,
            -- 自定义倍率区域
            UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, marginTop = 6, children = {
                UI.Label { text = "自定义倍率", fontSize = 12, fontColor = { 180, 180, 200, 255 } },
                customMultField,
                UI.Label { text = "倍", fontSize = 10, fontColor = { 140, 140, 160, 255 } },
                UI.Button { text = "生成倍率卡", variant = "primary", width = 80, height = 28, fontSize = 11,
                    onClick = function()
                        local mult = tonumber(customMultField:GetValue()) or 0
                        if mult <= 0 then customMultResultLabel:SetText("请输入有效倍率"); return end
                        local dur = tonumber(itemDurationField:GetValue()) or 0
                        local multStr = tostring(math.floor(mult))
                        local generated = 0
                        local skipped = 0
                        -- 生成经验倍率卡
                        local expName
                        if dur == 0 then
                            expName = multStr .. "倍经验卡[永久]"
                        else
                            expName = multStr .. "倍经验卡[" .. dur .. "分钟]"
                        end
                        if DataManager.items[expName] then
                            skipped = skipped + 1
                        else
                            DataManager.items[expName] = {
                                name = expName, type = "经验倍率",
                                desc = string.format("使用后经验获取提升%d倍持续一段时间", mult),
                                effect = "exp_mult", value = multStr,
                                duration = (dur > 0) and tostring(dur) or nil,
                            }
                            generated = generated + 1
                        end
                        -- 生成货币倍率卡
                        local goldName
                        if dur == 0 then
                            goldName = multStr .. "倍货币卡[永久]"
                        else
                            goldName = multStr .. "倍货币卡[" .. dur .. "分钟]"
                        end
                        if DataManager.items[goldName] then
                            skipped = skipped + 1
                        else
                            DataManager.items[goldName] = {
                                name = goldName, type = "货币倍率",
                                desc = string.format("使用后金币获取提升%d倍持续一段时间", mult),
                                effect = "gold_mult", value = multStr,
                                duration = (dur > 0) and tostring(dur) or nil,
                            }
                            generated = generated + 1
                        end
                        if generated > 0 then SaveCategoryToCloud("items") end
                        if skipped > 0 and generated == 0 then
                            customMultResultLabel:SetText(multStr .. "倍卡已存在，无需重复生成")
                        elseif skipped > 0 then
                            customMultResultLabel:SetText("生成" .. generated .. "个，跳过" .. skipped .. "个(已存在)")
                        else
                            customMultResultLabel:SetText("已生成" .. multStr .. "倍经验卡+" .. multStr .. "倍货币卡")
                        end
                        ShowMsg("倍率卡: 生成" .. generated .. "个, 跳过" .. skipped .. "个")
                    end,
                },
            }},
            customMultResultLabel,
        },
    }
    local dungeonSection = CreateGenSection("副本", "dungeons", "5", GenerateDungeons)
    local shopSection = CreateGenSection("商店", "shops", "3", GenerateShops)
    local npcSection = CreateGenSection("NPC", "npcs", "5", GenerateNPCs)
    local questSection = CreateGenSection("任务", "quests", "10", GenerateQuests)

    -- 一键部署区块
    local deployResult = UI.Label {
        text = "",
        fontSize = 12,
        fontColor = { 100, 255, 200, 255 },
        height = 18,
    }

    local deploySection = UI.Panel {
        width = "100%",
        flexDirection = "column",
        backgroundColor = { 35, 20, 50, 220 },
        borderRadius = 8,
        padding = 12,
        marginTop = 12,
        borderColor = { 255, 180, 80, 100 },
        borderWidth = 1,
        children = {
            UI.Label {
                text = "一键部署",
                fontSize = 16,
                fontColor = { 255, 150, 50, 255 },
                marginBottom = 4,
            },
            UI.Label {
                text = "将地图、怪物、NPC、商店、副本等数据关联在一起",
                fontSize = 11,
                fontColor = { 160, 160, 180, 255 },
                marginBottom = 8,
            },
            UI.Label {
                text = "• 为空白地图分配怪物和NPC",
                fontSize = 11,
                fontColor = { 140, 140, 160, 255 },
            },
            UI.Label {
                text = "• 将地图前后左右连通",
                fontSize = 11,
                fontColor = { 140, 140, 160, 255 },
            },
            UI.Label {
                text = "• 为怪物分配掉落物品/装备",
                fontSize = 11,
                fontColor = { 140, 140, 160, 255 },
            },
            UI.Label {
                text = "• 为商店填充商品",
                fontSize = 11,
                fontColor = { 140, 140, 160, 255 },
            },
            UI.Label {
                text = "• 为副本分配奖励物品",
                fontSize = 11,
                fontColor = { 140, 140, 160, 255 },
                marginBottom = 10,
            },
            UI.Button {
                id = "deploy_btn",
                text = "一键部署",
                variant = "primary",
                width = 120,
                height = 36,
                fontSize = 14,
                disabled = (DataManager.gameConfig and DataManager.gameConfig["deploy"] and DataManager.gameConfig["deploy"].version or 0) > 0,
                onClick = function(self)
                    -- 防止重复点击
                    self:SetDisabled(true)
                    self:SetText("部署中...")

                    local changes = DeployAll()

                    -- 确定目标地图
                    local targetMap = "新手村"
                    if not DataManager.maps[targetMap] then
                        local gc = DataManager.gameConfig or {}
                        local gameSec = gc["game"] or {}
                        targetMap = gameSec.start_map or ""
                        if targetMap == "" or not DataManager.maps[targetMap] then
                            for name, _ in pairs(DataManager.maps) do
                                targetMap = name
                                break
                            end
                        end
                    end

                    -- 懒迁移：递增部署版本号+记录目标地图
                    local gc = DataManager.gameConfig
                    if not gc["deploy"] then gc["deploy"] = { version = 0, target_map = "" } end
                    gc["deploy"].version = (gc["deploy"].version or 0) + 1
                    gc["deploy"].target_map = targetMap

                    -- 批量保存：7个分类合并为1次网络请求（原来7次独立请求）
                    local cloud = DataManager.GetCloudProvider()
                    if not cloud then
                        self:SetText("一键部署")
                        self:SetDisabled(false)
                        ShowMsg("云存储不可用，部署失败")
                        return
                    end
                    local batch = cloud:BatchSet()
                    local categories = { "maps", "monsters", "shops", "dungeons", "npcs", "quests", "game_config" }
                    for _, cat in ipairs(categories) do
                        local key, content = SerializeCategoryForCloud(cat)
                        if key and content then
                            batch:Set(key, content)
                        end
                    end
                    batch:Save("一键部署批量保存", {
                        ok = function()
                            deployResult:SetText("部署完成！关联 " .. changes .. " 处，玩家登录时自动传送至【" .. targetMap .. "】(v" .. gc["deploy"].version .. ")")
                            self:SetText("已部署 ✓")
                            print("[Deploy] BatchSet 成功，7个分类1次写入")
                        end,
                        error = function(code, reason)
                            deployResult:SetText("部署关联 " .. changes .. " 处，但保存失败: " .. tostring(reason))
                            self:SetText("部署失败")
                            self:SetDisabled(false)
                            print("[Deploy] BatchSet 失败: " .. tostring(reason))
                        end,
                    })
                    ShowMsg("一键部署完成: " .. changes .. " 处关联，正在保存...")
                end,
            },
            deployResult,
        },
    }



    -- 一键删除所有系统数据
    local deleteResult = UI.Label { text = "", fontSize = 12, fontColor = { 255, 100, 100, 255 }, marginTop = 6 }
    local deleteSection = UI.Panel {
        width = "100%",
        flexDirection = "column",
        backgroundColor = { 50, 20, 20, 220 },
        borderRadius = 8,
        padding = 12,
        marginTop = 12,
        borderColor = { 255, 80, 80, 100 },
        borderWidth = 1,
        children = {
            UI.Label {
                text = "一键删除",
                fontSize = 16,
                fontColor = { 255, 80, 80, 255 },
                marginBottom = 4,
            },
            UI.Label {
                text = "删除所有系统数据（地图、怪物、物品、装备、任务、商店、副本、NPC、礼包）",
                fontSize = 11,
                fontColor = { 200, 140, 140, 255 },
                marginBottom = 10,
            },
            UI.Button {
                text = "一键删除所有数据",
                variant = "danger",
                width = 160,
                height = 36,
                fontSize = 14,
                onClick = function()
                    -- 清空所有系统数据
                    DataManager.maps = {}
                    DataManager.monsters = {}
                    DataManager.items = {}
                    DataManager.equipment = {}
                    DataManager.quests = {}
                    DataManager.shops = {}
                    DataManager.dungeons = {}
                    DataManager.npcs = {}
                    DataManager.giftpacks = {}
                    -- 重置部署版本号（允许重新部署）
                    local gc = DataManager.gameConfig
                    if gc and gc["deploy"] then
                        gc["deploy"].version = 0
                        gc["deploy"].target_map = ""
                    end
                    -- 保存到云端
                    SaveCategoryToCloud("maps")
                    SaveCategoryToCloud("monsters")
                    SaveCategoryToCloud("items")
                    SaveCategoryToCloud("equipment")
                    SaveCategoryToCloud("quests")
                    SaveCategoryToCloud("shops")
                    SaveCategoryToCloud("dungeons")
                    SaveCategoryToCloud("npcs")
                    SaveCategoryToCloud("giftpacks")
                    SaveCategoryToCloud("game_config")
                    deleteResult:SetText("已删除所有系统数据！可重新部署")
                    ShowMsg("已删除所有系统数据")
                    -- 解锁部署按钮
                    local deployBtn = deploySection:FindById("deploy_btn")
                    if deployBtn then
                        deployBtn:SetDisabled(false)
                        deployBtn:SetText("一键部署")
                    end
                end,
            },
            deleteResult,
        },
    }

    -- 将所有区块添加到内容面板
    contentPanel_:AddChild(UI.Panel {
        width = "100%",
        padding = 10,
        flexDirection = "column",
        children = {
            mapSection,
            monsterSection,
            equipSection,
            itemSection,
            dungeonSection,
            shopSection,
            npcSection,
            questSection,
            deploySection,
            deleteSection,
        },
    })
end

-- =============== 排行榜管理 ===============

--- 可用的排行数据来源（玩家属性字段）
-- 排行榜来源分类
-- 玩家类来源（固定字段 + 动态货币 + 战魂等级）
local LEADERBOARD_PLAYER_SOURCES = { "等级", "攻击力", "防御力", "生命上限", "战魂等级" }
-- 物品类来源前缀
local LEADERBOARD_ITEM_PREFIXES = { "道具:", "装备:" }

--- 检查来源是否合法
---@param source string
---@return boolean
local function IsValidLeaderboardSource(source)
    if not source or source == "" then return false end
    -- 固定玩家属性
    for _, s in ipairs(LEADERBOARD_PLAYER_SOURCES) do
        if s == source then return true end
    end
    -- 自定义货币（直接写货币名，如"金币""钻石"）
    local currencyList = DataManager.GetCurrencyList()
    for _, c in ipairs(currencyList) do
        if source == "货币:" .. c or source == c then return true end
    end
    -- 物品类前缀（道具:物品名 / 装备:装备名）
    for _, prefix in ipairs(LEADERBOARD_ITEM_PREFIXES) do
        if source:sub(1, #prefix) == prefix and #source > #prefix then
            return true
        end
    end
    return false
end

--- 渲染排行榜管理面板
local function RenderLeaderboards()
    ClearContent()

    -- 确保排行榜数据已加载
    DataManager.LoadLazyData(function()
        ClearContent()

        local boardCount = 0
        for _ in pairs(DataManager.leaderboards) do boardCount = boardCount + 1 end
        ShowMsg("共 " .. boardCount .. " 个排行榜")

        -- 操作按钮区
        contentPanel_:AddChild(UI.Panel {
            flexDirection = "row", width = "100%", gap = 8, marginBottom = 8, marginLeft = 12,
            flexWrap = "wrap",
            children = {
                UI.Button {
                    text = "+ 添加排行榜",
                    variant = "primary", width = 130,
                    onClick = function()
                        ShowEditDialog("添加排行榜", {
                            { label = "排行榜ID(唯一)", key = "id", value = "", opts = { placeholder = "如：rank_level" } },
                            { label = "显示名称", key = "name", value = "", opts = { placeholder = "如：等级排行" } },
                            { label = "数据来源", key = "source", value = "等级", opts = { placeholder = "如: 等级/攻击力/金币/道具:回血丹" } },
                            { label = "排序方式", key = "order", value = "desc", opts = { placeholder = "desc=降序, asc=升序" } },
                            { label = "显示人数", key = "top_count", value = "10" },
                        }, function(v)
                            if not v.id or v.id == "" then
                                ShowMsg("排行榜ID不能为空")
                                return
                            end
                            if not v.name or v.name == "" then
                                ShowMsg("显示名称不能为空")
                                return
                            end
                            if DataManager.leaderboards[v.id] then
                                ShowMsg("该ID已存在，请换一个")
                                return
                            end
                            -- 验证数据来源是否合法
                            if not IsValidLeaderboardSource(v.source) then
                                ShowMsg("数据来源无效，请参考下方\"可用数据来源\"")
                                return
                            end
                            DataManager.leaderboards[v.id] = {
                                name = v.name,
                                key = "rank_" .. v.id,
                                source = v.source,
                                order = v.order or "desc",
                                top_count = tonumber(v.top_count) or 10,
                            }
                            SaveCategoryToCloud("leaderboards")
                            CloseDialog()
                            RenderLeaderboards()
                        end)
                    end,
                },
                UI.Button {
                    text = "刷新所有玩家排行",
                    variant = "secondary", width = 160,
                    onClick = function()
                        ShowMsg("正在刷新所有玩家排行数据...")
                        DataManager.RefreshAllPlayersRankingForAdmin(function(ok, msg)
                            ShowMsg(ok and ("刷新完成: " .. msg) or ("刷新失败: " .. msg))
                            RenderLeaderboards()
                        end)
                    end,
                },
            },
        })

        -- 排行榜列表
        local dataArray = {}
        for id, board in pairs(DataManager.leaderboards) do
            local subtext = "来源:" .. (board.source or "?") .. "  排序:" .. (board.order or "desc") .. "  显示:" .. (board.top_count or 10) .. "人"
            table.insert(dataArray, {
                text = board.name .. " [" .. id .. "]",
                subtext = subtext,
                onEdit = function()
                    ShowEditDialog("编辑排行榜 - " .. board.name, {
                        { label = "显示名称", key = "name", value = board.name or "" },
                        { label = "数据来源", key = "source", value = board.source or "等级", opts = { placeholder = "如: 等级/攻击力/金币/道具:回血丹" } },
                        { label = "排序方式", key = "order", value = board.order or "desc", opts = { placeholder = "desc=降序, asc=升序" } },
                        { label = "显示人数", key = "top_count", value = tostring(board.top_count or 10) },
                    }, function(v)
                        -- 验证数据来源
                        if not IsValidLeaderboardSource(v.source or "") then
                            ShowMsg("数据来源无效，请参考下方\"可用数据来源\"")
                            return
                        end
                        board.name = v.name or board.name
                        board.source = v.source or board.source
                        board.order = v.order or "desc"
                        board.top_count = tonumber(v.top_count) or 10
                        SaveCategoryToCloud("leaderboards")
                        CloseDialog()
                        RenderLeaderboards()
                    end)
                end,
                onDelete = function()
                    DataManager.leaderboards[id] = nil
                    SaveCategoryToCloud("leaderboards")
                    RenderLeaderboards()
                end,
            })
        end
        if #dataArray > 0 then
            contentPanel_:AddChild(CreateVirtualDataList(dataArray))
        else
            contentPanel_:AddChild(UI.Label {
                text = "暂无排行榜，点击上方按钮添加",
                fontSize = 13, fontColor = { 180, 180, 180, 200 },
                marginLeft = 12, marginTop = 8,
            })
        end

        -- 分隔线 —— 排行榜数据预览
        contentPanel_:AddChild(UI.Panel {
            width = "100%", height = 1, backgroundColor = { 80, 70, 120, 200 }, marginTop = 12, marginBottom = 4,
        })
        contentPanel_:AddChild(UI.Label {
            text = "排行榜数据预览（点击可查看排名详情）",
            fontSize = 14, fontColor = { 200, 180, 255, 255 },
            marginLeft = 12, marginBottom = 4,
        })

        -- 为每个排行榜显示一个预览按钮
        local previewBtns = {}
        for id, board in pairs(DataManager.leaderboards) do
            table.insert(previewBtns, UI.Button {
                text = board.name,
                variant = "outline", width = 120,
                onClick = function()
                    -- 显示该排行榜的具体排名数据
                    local rankedList = DataManager.GetRankedList(board.source, board.top_count, board.order or "desc")
                    local lines = { board.name .. " (来源: " .. board.source .. ", 前" .. board.top_count .. "名)\n" }
                    if #rankedList == 0 then
                        table.insert(lines, "暂无数据，请先点击[刷新所有玩家排行]")
                    else
                        for i, entry in ipairs(rankedList) do
                            local valStr = NumFormat.Short(entry.value)
                            table.insert(lines, "#" .. i .. "  " .. entry.name .. "  —  " .. valStr)
                        end
                    end
                    ShowEditDialog("排行详情 - " .. board.name, {
                        { label = "排行数据", key = "_info", value = table.concat(lines, "\n"), opts = { width = 280 } },
                    }, function()
                        CloseDialog()
                    end)
                end,
            })
        end
        if #previewBtns > 0 then
            contentPanel_:AddChild(UI.Panel {
                flexDirection = "row", width = "100%", gap = 8,
                flexWrap = "wrap", marginLeft = 12, marginTop = 4,
                children = previewBtns,
            })
        end

        -- 可用数据来源提示（分类显示）
        contentPanel_:AddChild(UI.Panel {
            width = "100%", height = 1, backgroundColor = { 80, 70, 120, 200 }, marginTop = 12, marginBottom = 4,
        })
        contentPanel_:AddChild(UI.Label {
            text = "可用数据来源（填写\"数据来源\"字段时使用）",
            fontSize = 14, fontColor = { 200, 180, 255, 255 },
            marginLeft = 12, marginBottom = 4,
        })

        -- ===== 玩家类 =====
        contentPanel_:AddChild(UI.Label {
            text = "【玩家类】读取玩家属性，按数值高到低排序",
            fontSize = 12, fontColor = { 255, 220, 100, 255 },
            marginLeft = 12, marginTop = 4, marginBottom = 2,
        })
        local playerSourceDescs = {
            { source = "等级",     desc = "玩家当前等级" },
            { source = "攻击力",   desc = "总攻击力（基础+装备+buff+境界+战魂）" },
            { source = "防御力",   desc = "总防御力（基础+装备+buff+境界+战魂）" },
            { source = "生命上限", desc = "总生命上限（基础+装备+buff+境界+战魂）" },
            { source = "战魂等级", desc = "战魂培养等级" },
        }
        for _, item in ipairs(playerSourceDescs) do
            contentPanel_:AddChild(UI.Panel {
                flexDirection = "row", width = "100%", marginLeft = 20, marginBottom = 2,
                children = {
                    UI.Label {
                        text = item.source,
                        fontSize = 12, fontColor = { 100, 255, 200, 255 },
                        width = 80,
                    },
                    UI.Label {
                        text = "— " .. item.desc,
                        fontSize = 11, fontColor = { 160, 160, 180, 255 },
                    },
                },
            })
        end

        -- 自定义货币（动态列出）
        local currencyList = DataManager.GetCurrencyList()
        contentPanel_:AddChild(UI.Label {
            text = "  同步自定义货币（直接写货币名或加\"货币:\"前缀）：",
            fontSize = 11, fontColor = { 180, 200, 255, 255 },
            marginLeft = 20, marginTop = 2,
        })
        for _, cName in ipairs(currencyList) do
            contentPanel_:AddChild(UI.Panel {
                flexDirection = "row", width = "100%", marginLeft = 28, marginBottom = 1,
                children = {
                    UI.Label {
                        text = cName,
                        fontSize = 12, fontColor = { 100, 255, 200, 255 },
                        width = 80,
                    },
                    UI.Label {
                        text = "— 或写 货币:" .. cName,
                        fontSize = 11, fontColor = { 160, 160, 180, 255 },
                    },
                },
            })
        end

        -- ===== 物品类 =====
        contentPanel_:AddChild(UI.Label {
            text = "【物品类】手动输入名称查看排行，按持有数量多到少排序",
            fontSize = 12, fontColor = { 255, 220, 100, 255 },
            marginLeft = 12, marginTop = 8, marginBottom = 2,
        })
        local itemSourceDescs = {
            { source = "道具:物品名", desc = "背包中该道具的持有数量（如 道具:回血丹）" },
            { source = "装备:装备名", desc = "背包中该装备的持有数量（如 装备:青锋剑）" },
        }
        for _, item in ipairs(itemSourceDescs) do
            contentPanel_:AddChild(UI.Panel {
                flexDirection = "row", width = "100%", marginLeft = 20, marginBottom = 2,
                children = {
                    UI.Label {
                        text = item.source,
                        fontSize = 12, fontColor = { 100, 255, 200, 255 },
                        width = 100,
                    },
                    UI.Label {
                        text = "— " .. item.desc,
                        fontSize = 11, fontColor = { 160, 160, 180, 255 },
                    },
                },
            })
        end

        -- 使用说明
        contentPanel_:AddChild(UI.Panel {
            width = "100%", height = 1, backgroundColor = { 80, 70, 120, 200 }, marginTop = 12, marginBottom = 4,
        })
        contentPanel_:AddChild(UI.Label {
            text = "使用说明",
            fontSize = 14, fontColor = { 200, 180, 255, 255 },
            marginLeft = 12, marginBottom = 2,
        })
        contentPanel_:AddChild(UI.Label {
            text = "1. 点击[+添加排行榜]创建新排行榜",
            fontSize = 11, fontColor = { 160, 160, 180, 255 },
            marginLeft = 16,
        })
        contentPanel_:AddChild(UI.Label {
            text = "2. 玩家类直接填字段名，物品类填\"道具:名称\"或\"装备:名称\"",
            fontSize = 11, fontColor = { 160, 160, 180, 255 },
            marginLeft = 16,
        })
        contentPanel_:AddChild(UI.Label {
            text = "3. 点击[刷新所有玩家排行]手动更新排名数据",
            fontSize = 11, fontColor = { 160, 160, 180, 255 },
            marginLeft = 16,
        })
        contentPanel_:AddChild(UI.Label {
            text = "4. 添加后玩家界面会自动显示对应排行榜Tab",
            fontSize = 11, fontColor = { 160, 160, 180, 255 },
            marginLeft = 16,
        })
        contentPanel_:AddChild(UI.Label {
            text = "示例: 来源=等级 / 来源=金币 / 来源=道具:回血丹",
            fontSize = 11, fontColor = { 100, 255, 200, 255 },
            marginLeft = 16, marginTop = 4,
        })
    end)
end

-- =============== 传送地图管理 ===============
local RenderTeleportMapItemEdit  -- forward declaration

--- 渲染传送地图管理面板（虚拟列表显示所有现有地图 + 添加按钮）
local function RenderTeleportMaps()
    ClearContent()

    local tc = DataManager.teleportMaps

    -- 标题
    contentPanel_:AddChild(UI.Label {
        text = "传送地图管理",
        fontSize = 16,
        fontColor = { 200, 170, 100, 255 },
        marginBottom = 4,
        marginLeft = 12,
    })

    -- ========== 默认传送物品配置 ==========
    contentPanel_:AddChild(UI.Label {
        text = "— 默认传送物品 —",
        fontSize = 13,
        fontColor = { 200, 180, 100, 255 },
        marginLeft = 12,
        marginTop = 4,
    })
    contentPanel_:AddChild(UI.Label {
        text = "留空则所有地图默认免费传送(除非单独设置)",
        fontSize = 11,
        fontColor = { 140, 140, 160, 255 },
        marginLeft = 12,
        marginBottom = 4,
    })

    local defItemInput = UI.TextField {
        placeholder = "物品名称(留空=免费)",
        text = tc.default_item or "",
        width = "100%",
        height = 32,
        marginLeft = 12, marginRight = 12,
    }
    contentPanel_:AddChild(defItemInput)

    local defCountInput = UI.TextField {
        placeholder = "消耗数量",
        text = tc.default_item_count or "1",
        width = 100,
        height = 32,
        marginLeft = 12, marginTop = 4,
    }
    contentPanel_:AddChild(defCountInput)

    contentPanel_:AddChild(UI.Button {
        text = "保存默认物品设置",
        variant = "primary",
        height = 30,
        marginLeft = 12, marginTop = 6, marginBottom = 8,
        onClick = function()
            tc.default_item = defItemInput:GetText() or ""
            tc.default_item_count = defCountInput:GetText() or "1"
            SaveCategoryToCloud("teleport_maps")
        end,
    })

    -- 分隔线
    contentPanel_:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 50, 80, 200 }, marginTop = 4, marginBottom = 8 })

    -- ========== 已添加的传送地图列表 ==========
    local teleportCount = #tc.maps
    ShowMsg("已配置 " .. teleportCount .. " 个传送点")

    if teleportCount > 0 then
        contentPanel_:AddChild(UI.Label {
            text = "— 已添加的传送地图 —",
            fontSize = 13,
            fontColor = { 150, 200, 150, 255 },
            marginLeft = 12,
            marginTop = 4, marginBottom = 4,
        })

        for i, data in ipairs(tc.maps) do
            -- 每个地图一行：序号+名称+物品信息+免费切换+删除
            local itemInfo = ""
            if data.free then
                itemInfo = "[免费]"
            elseif data.custom_item and data.custom_item ~= "" then
                itemInfo = "[" .. data.custom_item .. " x" .. (data.custom_item_count or "1") .. "]"
            elseif tc.default_item ~= "" then
                itemInfo = "(默认物品)"
            else
                itemInfo = "[免费]"
            end

            local row = UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 12, paddingRight = 8,
                paddingTop = 3, paddingBottom = 3,
                backgroundColor = (i % 2 == 0) and { 30, 25, 50, 200 } or { 20, 15, 40, 200 },
                gap = 4,
            }
            row:AddChild(UI.Label {
                text = i .. ". " .. data.name,
                fontSize = 12,
                fontColor = { 220, 220, 240, 255 },
                flexGrow = 1, flexShrink = 1,
            })
            row:AddChild(UI.Label {
                text = itemInfo,
                fontSize = 11,
                fontColor = data.free and { 100, 220, 100, 255 } or { 180, 160, 100, 255 },
            })
            -- 免费切换按钮
            local idx = i
            row:AddChild(UI.Button {
                text = data.free and "取消免费" or "设为免费",
                fontSize = 10,
                height = 24,
                variant = data.free and "secondary" or "success",
                onClick = function()
                    tc.maps[idx].free = not tc.maps[idx].free
                    if tc.maps[idx].free then
                        tc.maps[idx].custom_item = ""
                        tc.maps[idx].custom_item_count = "1"
                    end
                    SaveCategoryToCloud("teleport_maps")
                    RenderTeleportMaps()
                end,
            })
            -- 自定义物品按钮
            if not data.free then
                row:AddChild(UI.Button {
                    text = "物品",
                    fontSize = 10,
                    height = 24,
                    variant = "warning",
                    onClick = function()
                        RenderTeleportMapItemEdit(idx)
                    end,
                })
            end
            -- 删除按钮
            row:AddChild(UI.Button {
                text = "删除",
                fontSize = 10,
                height = 24,
                variant = "danger",
                onClick = function()
                    table.remove(tc.maps, idx)
                    SaveCategoryToCloud("teleport_maps")
                    RenderTeleportMaps()
                end,
            })
            contentPanel_:AddChild(row)
        end
    end

    -- 分隔线
    contentPanel_:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 50, 80, 200 }, marginTop = 8, marginBottom = 8 })

    -- ========== 从现有地图列表添加 ==========
    contentPanel_:AddChild(UI.Label {
        text = "— 从现有地图中添加传送点 —",
        fontSize = 13,
        fontColor = { 150, 150, 200, 255 },
        marginLeft = 12,
        marginBottom = 4,
    })

    contentPanel_:AddChild(CreateSearchBar("搜索地图名...", function() RenderTeleportMaps() end))

    -- 构建现有地图列表，标记已添加的
    local existingTpNames = {}
    for _, tp in ipairs(tc.maps) do
        existingTpNames[tp.name] = true
    end

    local mapArray = {}
    local mapIdx = 0
    for id, data in pairs(DataManager.maps) do
        local mapName = data.name or id
        if not MatchSearch(mapName) then goto continue_tp_maps end
        mapIdx = mapIdx + 1
        local alreadyAdded = existingTpNames[mapName]
        table.insert(mapArray, {
            text = mapIdx .. ". " .. mapName,
            subtext = alreadyAdded and "已添加" or ("等级需求:" .. (data.level_req or "0")),
            onEdit = (not alreadyAdded) and function()
                table.insert(tc.maps, {
                    name = mapName,
                    level_req = data.level_req or "0",
                    custom_item = "",
                    custom_item_count = "1",
                    free = false,
                })
                SaveCategoryToCloud("teleport_maps")
                RenderTeleportMaps()
            end or nil,
            _isAdded = alreadyAdded,
        })
        ::continue_tp_maps::
    end

    if #mapArray > 0 then
        local container = UI.Panel {
            width = "100%",
            flexGrow = 1,
            flexBasis = 0,
            overflow = "hidden",
            marginTop = 4,
        }
        local vList = UI.VirtualList {
            width = "100%",
            height = "100%",
            viewportHeight = (UI.GetHeight and UI.GetHeight() or 500) - 200,
            data = mapArray,
            itemHeight = VLIST_ITEM_HEIGHT,
            itemGap = VLIST_ITEM_GAP,
            poolBuffer = 5,
            createItem = function()
                local row = UI.Panel {
                    width = "100%",
                    height = VLIST_ITEM_HEIGHT,
                    flexDirection = "row",
                    alignItems = "center",
                    paddingLeft = 12, paddingRight = 12,
                    paddingTop = 4, paddingBottom = 4,
                    backgroundColor = { 20, 15, 35, 200 },
                }
                local infoCol = UI.Panel {
                    flexDirection = "column",
                    flexGrow = 1, flexShrink = 1,
                }
                local titleLabel = UI.Label { text = "", fontSize = 13, fontColor = { 220, 220, 240, 255 }, maxLines = 1 }
                local subLabel = UI.Label { text = "", fontSize = 11, fontColor = { 140, 140, 160, 255 }, maxLines = 1 }
                infoCol:AddChild(titleLabel)
                infoCol:AddChild(subLabel)
                row:AddChild(infoCol)
                local addBtn = UI.Button { text = "添加", fontSize = 11, width = 55, height = 26, variant = "success" }
                row:AddChild(addBtn)
                row._titleLabel = titleLabel
                row._subLabel = subLabel
                row._addBtn = addBtn
                return row
            end,
            bindItem = function(widget, data, index)
                widget._titleLabel:SetText(data.text or "")
                widget._subLabel:SetText(data.subtext or "")
                widget.props.backgroundColor = (index % 2 == 0) and { 25, 20, 45, 200 } or { 20, 15, 35, 200 }
                if data._isAdded then
                    widget._addBtn:SetText("已添加")
                    widget._addBtn:SetDisabled(true)
                    widget._subLabel:SetFontColor({ 100, 200, 100, 255 })
                else
                    widget._addBtn:SetText("添加")
                    widget._addBtn:SetDisabled(false)
                    widget._addBtn.props.onClick = data.onEdit
                    widget._subLabel:SetFontColor({ 140, 140, 160, 255 })
                end
            end,
        }
        container:AddChild(vList)
        contentPanel_:AddChild(container)
    else
        contentPanel_:AddChild(UI.Label {
            text = "（无地图数据，请先在[地图]分类中添加地图）",
            fontSize = 12,
            fontColor = { 140, 140, 160, 255 },
            textAlign = "center",
            marginTop = 20,
        })
    end
end

--- 传送地图单独物品编辑子页面
function RenderTeleportMapItemEdit(mapIndex)
    ClearContent()
    local tc = DataManager.teleportMaps
    local data = tc.maps[mapIndex]
    if not data then RenderTeleportMaps() return end

    contentPanel_:AddChild(UI.Label {
        text = "设置传送物品: " .. data.name,
        fontSize = 15,
        fontColor = { 200, 170, 100, 255 },
        marginLeft = 12, marginBottom = 8,
    })

    contentPanel_:AddChild(UI.Label {
        text = "留空则使用默认传送物品（当前默认: " .. (tc.default_item ~= "" and tc.default_item or "无/免费") .. "）",
        fontSize = 11,
        fontColor = { 140, 140, 160, 255 },
        marginLeft = 12, marginBottom = 6,
    })

    local itemInput = UI.TextField {
        placeholder = "自定义物品名(留空=用默认)",
        text = data.custom_item or "",
        width = "100%",
        height = 32,
        marginLeft = 12, marginRight = 12,
    }
    contentPanel_:AddChild(itemInput)

    local countInput = UI.TextField {
        placeholder = "数量",
        text = data.custom_item_count or "1",
        width = 100,
        height = 32,
        marginLeft = 12, marginTop = 4,
    }
    contentPanel_:AddChild(countInput)

    contentPanel_:AddChild(UI.Panel {
        width = "100%", flexDirection = "row", gap = 8,
        marginLeft = 12, marginTop = 10,
        children = {
            UI.Button {
                text = "保存",
                variant = "primary",
                height = 32,
                onClick = function()
                    tc.maps[mapIndex].custom_item = itemInput:GetText() or ""
                    tc.maps[mapIndex].custom_item_count = countInput:GetText() or "1"
                    tc.maps[mapIndex].free = false
                    SaveCategoryToCloud("teleport_maps")
                    RenderTeleportMaps()
                end,
            },
            UI.Button {
                text = "返回",
                variant = "secondary",
                height = 32,
                onClick = function() RenderTeleportMaps() end,
            },
        }
    })
end

-- =============== 分类切换 ===============

--- 根据分类渲染内容
local function RenderCategory(catId)
    if currentCategory_ ~= catId then
        searchKeyword_ = ""
    end
    currentCategory_ = catId
    if catId == "players" then RenderPlayers()
    elseif catId == "game_config" then RenderGameConfig()
    elseif catId == "maps" then RenderMaps()
    elseif catId == "monsters" then RenderMonsters()
    elseif catId == "items" then RenderItems()
    elseif catId == "equipment" then RenderEquipment()
    elseif catId == "quests" then RenderQuests()
    elseif catId == "shops" then RenderShops()
    elseif catId == "dungeons" then RenderDungeons()
    elseif catId == "npcs" then RenderNPCs()
    elseif catId == "giftpacks" then RenderGiftPacks()
    elseif catId == "realms" then RenderRealms()
    elseif catId == "distribute" then RenderDistribute()
    elseif catId == "chests" then RenderChests()
    elseif catId == "pets" then RenderPets()
    elseif catId == "pet_equip" then RenderPetEquip()
    elseif catId == "pet_bonus" then RenderPetBonus()
    elseif catId == "system_shops" then RenderSystemShops()
    elseif catId == "battle_soul" then RenderBattleSoul()
    elseif catId == "leaderboards" then RenderLeaderboards()
    elseif catId == "teleport_maps" then RenderTeleportMaps()
    elseif catId == "mounts" then RenderMounts()
    elseif catId == "generator" then RenderGenerator()
    else RenderPlayers()  -- 兜底：未知分类默认显示玩家管理
    end
end

-- =============== 主界面 ===============

--- 创建管理员登录界面
---@return Widget
function AdminUI.CreateLogin()
    adminLoggedIn_ = false
    currentAdminUser_ = ""

    local usernameField = UI.TextField {
        placeholder = "管理员账号",
        maxLength = 20, width = 250, height = 40,
    }
    local passwordField = UI.TextField {
        placeholder = "管理员密码",
        maxLength = 20, width = 250, height = 40,
    }
    local loginMsg = UI.Label {
        text = "", fontSize = 13, fontColor = { 255, 100, 100, 255 },
        textAlign = "center", height = 20,
    }

    local root = UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "column", justifyContent = "center", alignItems = "center",
        backgroundColor = { 10, 10, 20, 255 },
        children = {
            UI.Label {
                text = "管理员登录", fontSize = 28,
                fontColor = { 255, 180, 80, 255 }, textAlign = "center", marginBottom = 30,
            },
            UI.Panel {
                width = 320, flexDirection = "column", alignItems = "center",
                backgroundColor = { 25, 20, 45, 220 }, borderRadius = 12, padding = 24, gap = 12,
                children = {
                    usernameField, passwordField, loginMsg,
                    UI.Panel {
                        flexDirection = "row", gap = 16, marginTop = 8,
                        children = {
                            UI.Button {
                                text = "登 录", variant = "primary", width = 100,
                                onClick = function()
                                    local u = usernameField:GetValue()
                                    local p = passwordField:GetValue()
                                    -- 总管理员用固定密码登录
                                    if u == SUPER_ADMIN and p == ADMIN_PASSWORD then
                                        adminLoggedIn_ = true
                                        currentAdminUser_ = u
                                        loginMsg:SetText("")
                                        AdminUI.ShowDashboard()
                                        return
                                    end
                                    -- 被授权的管理员：先加载管理员列表再验证
                                    loginMsg:SetText("验证中...")
                                    LoadAdminsFromCloud(function()
                                        if not IsAdmin(u) then
                                            loginMsg:SetText("无管理员权限")
                                            return
                                        end
                                        -- 验证玩家账号密码
                                        DataManager.VerifyPlayerPassword(u, p, function(ok)
                                            if ok then
                                                adminLoggedIn_ = true
                                                currentAdminUser_ = u
                                                loginMsg:SetText("")
                                                AdminUI.ShowDashboard()
                                            else
                                                loginMsg:SetText("账号或密码错误")
                                            end
                                        end)
                                    end)
                                end,
                            },
                            UI.Button {
                                text = "返 回", variant = "secondary", width = 100,
                                onClick = function() SwitchState("login") end,
                            },
                        },
                    },
                },
            },
        },
    }
    return root
end

--- 显示管理员后台主界面
function AdminUI.ShowDashboard()
    msgLabel_ = UI.Label {
        text = "选择左侧分类进行管理",
        fontSize = 12, fontColor = { 180, 180, 200, 255 },
        textAlign = "center", height = 18,
    }

    contentPanel_ = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        gap = 2,
    }

    -- 创建侧边导航按钮
    local navButtons = {}
    for _, cat in ipairs(CATEGORIES) do
        table.insert(navButtons, UI.Button {
            text = cat.name,
            fontSize = 11,
            width = "100%",
            height = 30,
            variant = "secondary",
            onClick = function()
                RenderCategory(cat.id)
            end,
        })
    end

    rootPanel_ = UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "column",
        backgroundColor = { 10, 10, 20, 255 },
        children = {
            -- 顶部栏
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                padding = 8, backgroundColor = { 20, 15, 40, 255 },
                children = {
                    UI.Label {
                        text = "管理员后台",
                        fontSize = 18, fontColor = { 255, 180, 80, 255 },
                    },
                    UI.Button {
                        text = "退出", variant = "secondary", fontSize = 11,
                        onClick = function()
                            adminLoggedIn_ = false
                            currentAdminUser_ = ""
                            SwitchState("login")
                        end,
                    },
                },
            },
            -- 消息栏
            msgLabel_,
            -- 主体：左导航 + 右内容
            UI.Panel {
                width = "100%", flexGrow = 1, flexShrink = 1,
                flexDirection = "row",
                children = {
                    -- 左侧导航
                    UI.ScrollView {
                        width = 80,
                        height = "100%",
                        backgroundColor = { 18, 14, 35, 255 },
                        children = {
                            UI.Panel {
                                width = "100%",
                                flexDirection = "column",
                                gap = 2,
                                padding = 4,
                                children = navButtons,
                            },
                        },
                    },
                    -- 右侧内容
                    UI.ScrollView {
                        flexGrow = 1, flexShrink = 1,
                        height = "100%",
                        children = { contentPanel_ },
                    },
                },
            },
        },
    }

    UI.SetRoot(rootPanel_)

    -- 默认显示玩家管理
    RenderCategory("players")
end

return AdminUI
