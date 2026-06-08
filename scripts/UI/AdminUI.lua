---------------------------------------------------
-- AdminUI.lua - 管理员后台界面（完整配置管理版）
-- 支持所有系统配置的读取、修改、添加
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local IniParser = require("Utils.IniParser")
local NumFormat = require("Utils.NumFormat")
local BigNum = require("Utils.BigNum")

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
    { id = "generator", name = "一键生成" },
}

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

--- 创建表单字段（标签 + 输入框）
---@param label string
---@param value string
---@param opts table|nil {width, placeholder, multiline}
---@return Widget panel, Widget field
local function CreateFormField(label, value, opts)
    opts = opts or {}
    local field = UI.TextField {
        value = tostring(value or ""),
        placeholder = opts.placeholder or "",
        width = opts.width or 200,
        height = opts.height or 32,
        fontSize = 12,
    }
    local panel = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        marginBottom = 4,
        children = {
            UI.Label {
                text = label,
                fontSize = 12,
                fontColor = { 180, 180, 200, 255 },
                width = opts.labelWidth or 80,
            },
            field,
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

--- 将 DataManager 中的数据序列化为 INI 并保存
---@param category string
local function SaveCategoryToCloud(category)
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
            sections[id] = {
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
                ["购买价"] = NumFormat.Int(data.price_buy or 0),
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
                sec["商品_" .. i] = (item.name or "") .. ":" .. tostring(item.price or 0) .. ":" .. (item.desc or "")
            end
            sections[id] = sec
        end
        content = IniParser.Serialize(sections)
        SaveConfigToCloud("系统配置/shops.ini", content, function(ok)
            ShowMsg(ok and "商店配置已保存到云端" or "保存失败")
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
            ["境界"] = defSec.cultivation or "练气期一层",
        }
        local lvlSec = gc["level_up"] or {}
        sections["升级配置"] = {
            ["基础经验"] = NumFormat.Int(lvlSec.base_exp or 20),
            ["经验系数"] = tostring(lvlSec.exp_factor or 1.5),
            ["每级生命"] = NumFormat.Int(lvlSec.hp_per_level or 20),
            ["每级法力"] = NumFormat.Int(lvlSec.mp_per_level or 10),
            ["每级攻击"] = NumFormat.Int(lvlSec.atk_per_level or 3),
            ["每级防御"] = NumFormat.Int(lvlSec.def_per_level or 2),
        }
        local cultSec = gc["cultivation"] or {}
        sections["境界配置"] = {}
        for k, v in pairs(cultSec) do
            sections["境界配置"][tostring(k)] = tostring(v)
        end
        content = IniParser.Serialize(sections)
        SaveConfigToCloud("系统配置/game_config.ini", content, function(ok)
            ShowMsg(ok and "游戏设置已保存到云端" or "保存失败")
        end)
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
        local panel, field = CreateFormField(f.label, f.value, f.opts)
        fieldWidgets[f.key] = field
        table.insert(formChildren, panel)
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

    if rootPanel_ then
        rootPanel_:AddChild(editDialog_)
    end
end

-- =============== 玩家管理 ===============

-- 前向声明
local RenderPlayers
local RenderItems
local RenderShops

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
            { label = "等级", key = "st_level", value = st.level or "1" },
            { label = "经验", key = "st_exp", value = st.exp or "0" },
            { label = "生命值", key = "st_hp", value = st.hp or "100" },
            { label = "最大生命", key = "st_max_hp", value = st.max_hp or "100" },
            { label = "法力值", key = "st_mp", value = st.mp or "50" },
            { label = "最大法力", key = "st_max_mp", value = st.max_mp or "50" },
            { label = "攻击力", key = "st_atk", value = st.atk or "5" },
            { label = "防御力", key = "st_def", value = st.def or "3" },
            { label = "金币", key = "st_gold", value = st.gold or "50" },
            { label = "境界", key = "st_cultivation", value = st.cultivation or "练气期一层" },
            { label = "当前地图", key = "st_current_map", value = st.current_map or "新手村" },
        }
        for _, f in ipairs(statusFields) do
            local panel, field = CreateFormField(f.label, f.value, { width = 150 })
            if not editMode then field:SetDisabled(true) end
            fieldWidgets[f.key] = field
            table.insert(formChildren, panel)
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
        local equipFields = {
            { label = "武器", key = "eq_weapon", value = eq.weapon or "" },
            { label = "防具", key = "eq_armor", value = eq.armor or "" },
            { label = "饰品", key = "eq_accessory", value = eq.accessory or "" },
        }
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

                    -- 构建新的 playerData
                    local newPlayerData = {
                        account = {
                            username = username,
                            password = newAccPassword,
                            char_name = newAccCharName,
                        },
                        status = {
                            name = fieldWidgets["st_name"]:GetValue() or "",
                            level = fieldWidgets["st_level"]:GetValue() or "1",
                            exp = fieldWidgets["st_exp"]:GetValue() or "0",
                            hp = fieldWidgets["st_hp"]:GetValue() or "100",
                            max_hp = fieldWidgets["st_max_hp"]:GetValue() or "100",
                            mp = fieldWidgets["st_mp"]:GetValue() or "50",
                            max_mp = fieldWidgets["st_max_mp"]:GetValue() or "50",
                            atk = fieldWidgets["st_atk"]:GetValue() or "5",
                            def = fieldWidgets["st_def"]:GetValue() or "3",
                            gold = fieldWidgets["st_gold"]:GetValue() or "50",
                            cultivation = fieldWidgets["st_cultivation"]:GetValue() or "练气期一层",
                            current_map = fieldWidgets["st_current_map"]:GetValue() or "新手村",
                        },
                        bag = {},
                        equip = {
                            weapon = fieldWidgets["eq_weapon"]:GetValue() or "",
                            armor = fieldWidgets["eq_armor"]:GetValue() or "",
                            accessory = fieldWidgets["eq_accessory"]:GetValue() or "",
                        },
                        quests = { active = {}, completed = {} },
                        redeemed_codes = {},
                    }

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
    ShowMsg("游戏全局设置（含玩家初始属性、升级公式、境界表）")

    local gc = DataManager.gameConfig
    local gameSec = gc["game"] or {}
    local defSec = gc["player_default"] or {}
    local lvlSec = gc["level_up"] or {}
    local cultSec = gc["cultivation"] or {}

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
        "HP:" .. (defSec.hp or 100) .. " MP:" .. (defSec.mp or 50) .. " ATK:" .. (defSec.atk or 5) .. " DEF:" .. (defSec.def or 3),
        function()
            ShowEditDialog("玩家初始属性", {
                { label = "生命值", key = "hp", value = defSec.hp },
                { label = "法力值", key = "mp", value = defSec.mp },
                { label = "攻击力", key = "atk", value = defSec.atk },
                { label = "防御力", key = "def", value = defSec.def },
                { label = "等级", key = "level", value = defSec.level },
                { label = "金币", key = "gold", value = defSec.gold },
                { label = "境界", key = "cultivation", value = defSec.cultivation },
            }, function(v)
                gc["player_default"] = {
                    hp = v.hp or "100", mp = v.mp or "50",
                    atk = v.atk or "5", def = v.def or "3",
                    level = v.level or "1", exp = "0",
                    gold = v.gold or "50", cultivation = v.cultivation,
                }
                SaveCategoryToCloud("game_config")
            end)
        end, 2))

    -- 升级公式
    contentPanel_:AddChild(CreateListRow("升级公式",
        "基础经验:" .. (lvlSec.base_exp or 20) .. " 系数:" .. (lvlSec.exp_factor or 1.5),
        function()
            ShowEditDialog("升级公式", {
                { label = "基础经验", key = "base_exp", value = lvlSec.base_exp },
                { label = "经验系数", key = "exp_factor", value = lvlSec.exp_factor },
                { label = "每级生命", key = "hp_per_level", value = lvlSec.hp_per_level },
                { label = "每级法力", key = "mp_per_level", value = lvlSec.mp_per_level },
                { label = "每级攻击", key = "atk_per_level", value = lvlSec.atk_per_level },
                { label = "每级防御", key = "def_per_level", value = lvlSec.def_per_level },
            }, function(v)
                gc["level_up"] = {
                    base_exp = v.base_exp or "20", exp_factor = tonumber(v.exp_factor) or 1.5,
                    hp_per_level = v.hp_per_level or "20", mp_per_level = v.mp_per_level or "10",
                    atk_per_level = v.atk_per_level or "3", def_per_level = v.def_per_level or "2",
                }
                SaveCategoryToCloud("game_config")
            end)
        end, 3))

    -- 境界表
    local cultText = ""
    for k, v in pairs(cultSec) do
        cultText = cultText .. "Lv" .. tostring(k) .. "=" .. tostring(v) .. " "
    end
    contentPanel_:AddChild(CreateListRow("境界表", cultText,
        function()
            -- 动态生成境界字段
            local cultFields = {}
            local sortedKeys = {}
            for k, _ in pairs(cultSec) do
                table.insert(sortedKeys, tonumber(k) or 0)
            end
            table.sort(sortedKeys)
            for _, lvl in ipairs(sortedKeys) do
                table.insert(cultFields, { label = "等级" .. lvl, key = tostring(lvl), value = cultSec[tostring(lvl)] or cultSec[lvl] })
            end
            -- 额外空槽用于添加
            table.insert(cultFields, { label = "新等级", key = "new_level", value = "", opts = { placeholder = "数字" } })
            table.insert(cultFields, { label = "新境界", key = "new_name", value = "", opts = { placeholder = "境界名" } })
            ShowEditDialog("境界配置", cultFields, function(v)
                local newCult = {}
                for _, lvl in ipairs(sortedKeys) do
                    local key = tostring(lvl)
                    if v[key] and v[key] ~= "" then
                        newCult[key] = v[key]
                    end
                end
                -- 添加新境界
                if v.new_level and v.new_level ~= "" and v.new_name and v.new_name ~= "" then
                    newCult[v.new_level] = v.new_name
                end
                gc["cultivation"] = newCult
                SaveCategoryToCloud("game_config")
                CloseDialog()
                RenderGameConfig()
            end)
        end, 4))
end

-- =============== 通用列表配置管理 ===============

--- 渲染地图列表
local function RenderMaps()
    ClearContent()
    contentPanel_:AddChild(CreateSearchBar("搜索地图名...", function() RenderMaps() end))
    local count = 0
    local idx = 0
    for _ in pairs(DataManager.maps) do count = count + 1 end
    ShowMsg("共 " .. count .. " 张地图")

    for id, data in pairs(DataManager.maps) do
        if not MatchSearch(data.name or id) then goto continue_maps end
        idx = idx + 1
        local row = CreateListRow(
            data.name or id,
            "等级需求:" .. (data.level_req or 0) .. " 怪物:" .. (data.monsters or ""),
            function()
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
            end, idx, function()
                DataManager.maps[id] = nil
                SaveCategoryToCloud("maps")
                RenderMaps()
            end)
        contentPanel_:AddChild(row)
        ::continue_maps::
    end

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
    local idx = 0
    for _ in pairs(DataManager.monsters) do count = count + 1 end
    ShowMsg("共 " .. count .. " 种怪物")

    for id, data in pairs(DataManager.monsters) do
        if not MatchSearch(data.name or id) then goto continue_monsters end
        idx = idx + 1
        local typeTag = data.type and ("[" .. data.type .. "] ") or ""
        local row = CreateListRow(
            typeTag .. (data.name or id),
            "HP:" .. (data.hp or 0) .. " ATK:" .. (data.atk or 0) .. " EXP:" .. (data.exp or 0),
            function()
                ShowEditDialog("编辑怪物 - " .. id, {
                    { label = "名称", key = "name", value = data.name },
                    { label = "类型", key = "type", value = data.type or "普通怪", opts = { placeholder = "普通怪/精英怪/BOSS/帝级/仙级/神级/创世级" } },
                    { label = "描述", key = "desc", value = data.desc, opts = { width = 220 } },
                    { label = "生命值", key = "hp", value = data.hp },
                    { label = "攻击力", key = "atk", value = data.atk },
                    { label = "防御力", key = "def", value = data.def },
                    { label = "经验值", key = "exp", value = data.exp },
                    { label = "金币", key = "gold", value = data.gold },
                    { label = "掉落", key = "drops", value = data.drops, opts = { width = 220, placeholder = "物品:概率,..." } },
                }, function(v)
                    DataManager.monsters[id] = {
                        name = v.name, type = v.type or "普通怪", desc = v.desc,
                        hp = v.hp or "20", atk = v.atk or "3",
                        def = v.def or "1", exp = v.exp or "5",
                        gold = v.gold or "2", drops = v.drops,
                    }
                    SaveCategoryToCloud("monsters")
                    CloseDialog()
                    RenderMonsters()
                end)
            end, idx, function()
                DataManager.monsters[id] = nil
                SaveCategoryToCloud("monsters")
                RenderMonsters()
            end)
        contentPanel_:AddChild(row)
        ::continue_monsters::
    end

    contentPanel_:AddChild(UI.Button {
        text = "+ 添加怪物",
        variant = "primary", width = 120, marginTop = 8, marginLeft = 12,
        onClick = function()
            ShowEditDialog("添加怪物", {
                { label = "ID(名称)", key = "id", value = "", opts = { placeholder = "如：火焰鸟" } },
                { label = "类型", key = "type", value = "普通怪", opts = { placeholder = "普通怪/精英怪/BOSS/帝级/仙级/神级/创世级" } },
                { label = "描述", key = "desc", value = "", opts = { width = 220 } },
                { label = "生命值", key = "hp", value = "50" },
                { label = "攻击力", key = "atk", value = "10" },
                { label = "防御力", key = "def", value = "5" },
                { label = "经验值", key = "exp", value = "15" },
                { label = "金币", key = "gold", value = "8" },
                { label = "掉落", key = "drops", value = "", opts = { width = 220, placeholder = "物品:概率,..." } },
            }, function(v)
                if v.id == "" then return end
                DataManager.monsters[v.id] = {
                    name = v.id, type = v.type or "普通怪", desc = v.desc,
                    hp = v.hp or "50", atk = v.atk or "10",
                    def = v.def or "5", exp = v.exp or "15",
                    gold = v.gold or "8", drops = v.drops,
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
local ITEM_TYPES = { "攻击", "防御", "生命上限", "恢复血量", "恢复灵力", "经验倍率", "货币倍率", "材料" }

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
    local valuePanel, valueField = CreateFormField("数值", tostring(data.value or "0"), { width = 120 })
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
    local idx = 0
    for _ in pairs(DataManager.items) do count = count + 1 end
    ShowMsg("共 " .. count .. " 种物品")

    for id, data in pairs(DataManager.items) do
        if not MatchSearch(data.name or id) and not MatchSearch(data.type) then goto continue_items end
        idx = idx + 1
        local typeStr = data.type or "材料"
        local row = CreateListRow(
            (data.name or id) .. "  [" .. typeStr .. "]",
            "数值:" .. tostring(data.value or 0),
            function()
                ShowItemEditDialog("编辑物品 - " .. (data.name or id), data, id, false)
            end, idx, function()
                DataManager.items[id] = nil
                SaveCategoryToCloud("items")
                RenderItems()
            end)
        contentPanel_:AddChild(row)
        ::continue_items::
    end

    contentPanel_:AddChild(UI.Button {
        text = "+ 添加物品",
        variant = "primary", width = 120, marginTop = 8, marginLeft = 12,
        onClick = function()
            ShowItemEditDialog("添加新物品", nil, nil, true)
        end,
    })
end

--- 装备部位选项
local EQUIP_SLOTS = { "武器", "防具", "饰品" }
--- 装备品质选项
local EQUIP_QUALITIES = { "白色", "绿色", "橙色", "红色", "彩色", "地级", "天级", "帝级", "仙级", "神级", "创世级" }

--- 创建按钮组选择器（通用）
---@param options string[] 选项列表
---@param currentValue string 当前选中值
---@param label string 标签文字
---@param disabled boolean
---@return Widget panel, fun():string getSelected
local function CreateButtonSelector(options, currentValue, label, disabled)
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
    local idx = 0
    for _ in pairs(DataManager.equipment) do count = count + 1 end
    ShowMsg("共 " .. count .. " 件装备")

    for id, data in pairs(DataManager.equipment) do
        if not MatchSearch(data.name or id) then goto continue_equip end
        idx = idx + 1
        local row = CreateListRow(
            (data.name or id) .. "  [" .. (data.slot or "武器") .. "]",
            "品质:" .. (data.quality or "白色") .. " 攻击:" .. (data.atk or 0) .. " 防御:" .. (data.def or 0) .. " 生命:" .. (data.hp or 0),
            function()
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
                local slotPanel, getSlot = CreateButtonSelector(EQUIP_SLOTS, data.slot or "武器", "部位", false)
                table.insert(formChildren, slotPanel)

                -- 品质选择器
                local qualityPanel, getQuality = CreateButtonSelector(EQUIP_QUALITIES, data.quality or "白色", "品质", false)
                table.insert(formChildren, qualityPanel)

                -- 其他字段
                local descPanel, descField = CreateFormField("描述", data.desc or "", { width = 220 })
                fieldWidgets["desc"] = descField
                table.insert(formChildren, descPanel)

                local atkPanel, atkField = CreateFormField("攻击", tostring(data.atk or 0), { width = 120 })
                fieldWidgets["atk"] = atkField
                table.insert(formChildren, atkPanel)

                local defPanel, defField = CreateFormField("防御", tostring(data.def or 0), { width = 120 })
                fieldWidgets["def"] = defField
                table.insert(formChildren, defPanel)

                local hpPanel, hpField = CreateFormField("生命", tostring(data.hp or 0), { width = 120 })
                fieldWidgets["hp"] = hpField
                table.insert(formChildren, hpPanel)

                local lvlPanel, lvlField = CreateFormField("等级需求", tostring(data.level_req or 1), { width = 120 })
                fieldWidgets["level_req"] = lvlField
                table.insert(formChildren, lvlPanel)

                local buyPanel, buyField = CreateFormField("购买价", tostring(data.price_buy or 0), { width = 120 })
                fieldWidgets["price_buy"] = buyField
                table.insert(formChildren, buyPanel)

                local sellPanel, sellField = CreateFormField("出售价", tostring(data.price_sell or 0), { width = 120 })
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
                                    price_buy = fieldWidgets["price_buy"]:GetValue() or "0",
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
            end, idx, function()
                DataManager.equipment[id] = nil
                SaveCategoryToCloud("equipment")
                RenderEquipment()
            end)
        contentPanel_:AddChild(row)
        ::continue_equip::
    end

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

            local slotPanel, getSlot = CreateButtonSelector(EQUIP_SLOTS, "武器", "部位", false)
            table.insert(formChildren, slotPanel)

            local qualityPanel, getQuality = CreateButtonSelector(EQUIP_QUALITIES, "白色", "品质", false)
            table.insert(formChildren, qualityPanel)

            local descPanel, descField = CreateFormField("描述", "", { width = 220 })
            fieldWidgets["desc"] = descField
            table.insert(formChildren, descPanel)

            local atkPanel, atkField = CreateFormField("攻击", "5", { width = 120 })
            fieldWidgets["atk"] = atkField
            table.insert(formChildren, atkPanel)

            local defPanel, defField = CreateFormField("防御", "0", { width = 120 })
            fieldWidgets["def"] = defField
            table.insert(formChildren, defPanel)

            local hpPanel, hpField = CreateFormField("生命", "0", { width = 120 })
            fieldWidgets["hp"] = hpField
            table.insert(formChildren, hpPanel)

            local lvlPanel, lvlField = CreateFormField("等级需求", "1", { width = 120 })
            fieldWidgets["level_req"] = lvlField
            table.insert(formChildren, lvlPanel)

            local buyPanel, buyField = CreateFormField("购买价", "50", { width = 120 })
            fieldWidgets["price_buy"] = buyField
            table.insert(formChildren, buyPanel)

            local sellPanel, sellField = CreateFormField("出售价", "20", { width = 120 })
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
                                price_buy = fieldWidgets["price_buy"]:GetValue() or "0",
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
    local idx = 0
    for _ in pairs(DataManager.quests) do count = count + 1 end
    ShowMsg("共 " .. count .. " 个任务")

    for id, data in pairs(DataManager.quests) do
        if not MatchSearch(data.name or id) then goto continue_quests end
        idx = idx + 1
        local row = CreateListRow(
            "[" .. (data.type or "支线") .. "] " .. (data.name or id),
            "目标:" .. (data.target_type or "击杀") .. " " .. (data.target_name or "") .. "x" .. (data.target_count or 1) .. " 经验:" .. (data.reward_exp or 0),
            function()
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
            end, idx, function()
                DataManager.quests[id] = nil
                SaveCategoryToCloud("quests")
                RenderQuests()
            end)
        contentPanel_:AddChild(row)
        ::continue_quests::
    end

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
            local rowNameField, rowPriceField, rowDescField

            -- 物品名
            local _, nf = CreateFormField("物品" .. i, item.name, { width = 100, placeholder = "物品名" })
            rowNameField = nf

            -- 价格
            local _, pf = CreateFormField("价格", tostring(item.price), { width = 60, placeholder = "0" })
            rowPriceField = pf

            -- 描述
            local _, df = CreateFormField("描述", item.desc, { width = 100, placeholder = "描述" })
            rowDescField = df

            local row = UI.Panel {
                flexDirection = "row",
                alignItems = "center",
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
                        onClick = function()
                            -- 先保存当前所有行的值
                            local rows = itemsContainer:GetChildren()
                            for ri = 1, #editItems do
                                if ri ~= i and rows[ri] then
                                    -- 只更新没被删的行
                                end
                            end
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

    -- 添加商品按钮
    local addItemBtn = UI.Button {
        text = "+ 添加商品",
        fontSize = 11,
        width = 100,
        height = 26,
        variant = "secondary",
        marginTop = 4,
        onClick = function()
            -- 先收集当前行的值
            for _, item in ipairs(editItems) do
                if item._nameField then
                    item.name = item._nameField:GetValue() or ""
                    item.price = item._priceField:GetValue() or "0"
                    item.desc = item._descField:GetValue() or ""
                end
            end
            table.insert(editItems, { name = "", price = "0", desc = "" })
            RebuildItemRows()
        end,
    }
    table.insert(formChildren, addItemBtn)

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
    local idx = 0
    for _ in pairs(DataManager.shops) do count = count + 1 end
    ShowMsg("共 " .. count .. " 家商店")

    for id, data in pairs(DataManager.shops) do
        if not MatchSearch(data.name or id) then goto continue_shops end
        idx = idx + 1
        local itemCount = #(data.items or {})
        local itemSummary = ""
        for i, item in ipairs(data.items or {}) do
            if i > 3 then itemSummary = itemSummary .. "..."; break end
            if i > 1 then itemSummary = itemSummary .. ", " end
            itemSummary = itemSummary .. item.name .. "(" .. item.price .. "金)"
        end
        if itemSummary == "" then itemSummary = "无商品" end

        local row = CreateListRow(
            (data.name or id) .. "  [" .. itemCount .. "种商品]",
            itemSummary,
            function()
                ShowShopEditDialog("编辑商店 - " .. (data.name or id), data, id, false)
            end, idx, function()
                DataManager.shops[id] = nil
                SaveCategoryToCloud("shops")
                RenderShops()
            end)
        contentPanel_:AddChild(row)
        ::continue_shops::
    end

    contentPanel_:AddChild(UI.Button {
        text = "+ 添加商店",
        variant = "primary", width = 120, marginTop = 8, marginLeft = 12,
        onClick = function()
            ShowShopEditDialog("添加新商店", nil, nil, true)
        end,
    })
end

--- 渲染副本列表
local function RenderDungeons()
    ClearContent()
    contentPanel_:AddChild(CreateSearchBar("搜索副本名...", function() RenderDungeons() end))
    local count = 0
    local idx = 0
    for _ in pairs(DataManager.dungeons) do count = count + 1 end
    ShowMsg("共 " .. count .. " 个副本")

    for id, data in pairs(DataManager.dungeons) do
        if not MatchSearch(data.name or id) then goto continue_dungeons end
        idx = idx + 1
        local row = CreateListRow(
            data.name or id,
            "等级:" .. (data.level_req or 0) .. " 波数:" .. (data.waves or 0) .. " 首领:" .. (data.boss or "无"),
            function()
                local fields = {
                    { label = "名称", key = "name", value = data.name },
                    { label = "描述", key = "desc", value = data.desc, opts = { width = 220 } },
                    { label = "等级需求", key = "level_req", value = data.level_req },
                    { label = "波数", key = "waves", value = data.waves },
                    { label = "首领", key = "boss", value = data.boss },
                    { label = "奖励经验", key = "reward_exp", value = data.reward_exp },
                    { label = "奖励金币", key = "reward_gold", value = data.reward_gold },
                    { label = "奖励物品", key = "reward_items", value = data.reward_items, opts = { width = 220 } },
                }
                for i = 1, tonumber(data.waves) or 1 do
                    table.insert(fields, { label = "第" .. i .. "波", key = "wave_" .. i, value = data["wave_" .. i] or "", opts = { width = 220, placeholder = "怪物,怪物,..." } })
                end
                ShowEditDialog("编辑副本 - " .. id, fields, function(v)
                    local entry = {
                        name = v.name, desc = v.desc,
                        level_req = v.level_req or "1", waves = v.waves or "1",
                        boss = v.boss,
                        reward_exp = v.reward_exp or "0", reward_gold = v.reward_gold or "0",
                        reward_items = v.reward_items,
                    }
                    for i = 1, tonumber(entry.waves) or 1 do  -- for-loop 需要 number
                        entry["wave_" .. i] = v["wave_" .. i] or ""
                    end
                    DataManager.dungeons[id] = entry
                    SaveCategoryToCloud("dungeons")
                    CloseDialog()
                    RenderDungeons()
                end)
            end, idx, function()
                DataManager.dungeons[id] = nil
                SaveCategoryToCloud("dungeons")
                RenderDungeons()
            end)
        contentPanel_:AddChild(row)
        ::continue_dungeons::
    end

    contentPanel_:AddChild(UI.Button {
        text = "+ 添加副本",
        variant = "primary", width = 120, marginTop = 8, marginLeft = 12,
        onClick = function()
            ShowEditDialog("添加副本", {
                { label = "副本ID", key = "id", value = "", opts = { placeholder = "如: dungeon_006" } },
                { label = "名称", key = "name", value = "" },
                { label = "描述", key = "desc", value = "", opts = { width = 220 } },
                { label = "等级需求", key = "level_req", value = "5" },
                { label = "波数", key = "waves", value = "3" },
                { label = "第1波", key = "wave_1", value = "", opts = { width = 220, placeholder = "怪物,怪物" } },
                { label = "第2波", key = "wave_2", value = "", opts = { width = 220 } },
                { label = "第3波", key = "wave_3", value = "", opts = { width = 220 } },
                { label = "首领", key = "boss", value = "" },
                { label = "奖励经验", key = "reward_exp", value = "50" },
                { label = "奖励金币", key = "reward_gold", value = "80" },
                { label = "奖励物品", key = "reward_items", value = "", opts = { width = 220 } },
            }, function(v)
                if v.id == "" then return end
                local entry = {
                    name = v.name, desc = v.desc,
                    level_req = v.level_req or "1", waves = v.waves or "3",
                    boss = v.boss,
                    reward_exp = v.reward_exp or "0", reward_gold = v.reward_gold or "0",
                    reward_items = v.reward_items,
                }
                for i = 1, tonumber(entry.waves) or 3 do  -- for-loop 需要 number
                    entry["wave_" .. i] = v["wave_" .. i] or ""
                end
                DataManager.dungeons[v.id] = entry
                SaveCategoryToCloud("dungeons")
                CloseDialog()
                RenderDungeons()
            end)
        end,
    })
end

--- 渲染NPC列表
local function RenderNPCs()
    ClearContent()
    contentPanel_:AddChild(CreateSearchBar("搜索NPC名...", function() RenderNPCs() end))
    local count = 0
    local idx = 0
    for _ in pairs(DataManager.npcs) do count = count + 1 end
    ShowMsg("共 " .. count .. " 个NPC")

    for id, data in pairs(DataManager.npcs) do
        if not MatchSearch(data.name or id) then goto continue_npcs end
        idx = idx + 1
        local row = CreateListRow(
            data.name or id,
            "类型:" .. (data.type or "任务") .. " 地点:" .. (data.location or ""),
            function()
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
            end, idx, function()
                DataManager.npcs[id] = nil
                SaveCategoryToCloud("npcs")
                RenderNPCs()
            end)
        contentPanel_:AddChild(row)
        ::continue_npcs::
    end

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
    local idx = 0
    for _ in pairs(DataManager.giftpacks) do count = count + 1 end
    ShowMsg("共 " .. count .. " 个礼包（兑换码即为礼包ID）")

    for id, data in pairs(DataManager.giftpacks) do
        if not MatchSearch(data.name or id) and not MatchSearch(id) then goto continue_giftpacks end
        idx = idx + 1
        local usesText = BigNum.gt(data.max_uses or "0", "0")
            and ("已用" .. (data.used_count or "0") .. "/" .. data.max_uses)
            or ("已用" .. (data.used_count or "0") .. "/无限")
        local row = CreateListRow(
            data.name or id,
            "兑换码:" .. id .. " " .. usesText,
            function()
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
            end, idx, function()
                DataManager.giftpacks[id] = nil
                SaveCategoryToCloud("giftpacks")
                RenderGiftPacks()
            end)
        contentPanel_:AddChild(row)
        ::continue_giftpacks::
    end

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
    equip_armor = { "甲", "袍", "衣", "铠", "裙", "衫" },
    equip_accessory = { "戒", "佩", "链", "珠", "冠", "环" },
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

--- 生成地图数据
---@param count number
local function GenerateMaps(count)
    local existingMaps = {}
    for id in pairs(DataManager.maps) do
        table.insert(existingMaps, id)
    end
    local generated = 0
    for i = 1, count do
        local name = RandPick(GEN_NAMES.map_prefix) .. RandPick(GEN_NAMES.map_suffix)
        -- 避免重复名
        if DataManager.maps[name] then
            name = name .. tostring(i)
        end
        local desc = RandPick(GEN_NAMES.map_desc_prefix) .. name .. "，修仙者的历练之地"
        local lvReq = tostring(math.random(1, 15))
        -- 随机连接已有地图
        local front, back = "", ""
        if #existingMaps > 0 then
            back = existingMaps[math.random(1, #existingMaps)]
        end
        DataManager.maps[name] = {
            name = name,
            desc = desc,
            monsters = "",
            npcs = "",
            front = front,
            back = back,
            left = "",
            right = "",
            level_req = lvReq,
        }
        table.insert(existingMaps, name)
        generated = generated + 1
    end
    SaveCategoryToCloud("maps")
    return generated
end

-- 怪物类型定义：{ 名称, 属性下限, 属性上限, 描述后缀 }
local MONSTER_TYPES = {
    { name = "普通怪",  min = "10",            max = "2000",           desc = "散发着微弱的妖气" },
    { name = "精英怪",  min = "3000",          max = "100000",         desc = "浑身散发着强大气息" },
    { name = "BOSS",    min = "500000",        max = "1000000",        desc = "威压四方，令人胆寒" },
    { name = "帝级",    min = "3000000",       max = "500000000",      desc = "帝威无边，天地变色" },
    { name = "仙级",    min = "600000000",     max = "5000000000",     desc = "仙威浩荡，不可直视" },
    { name = "神级",    min = "5000000000",    max = "60000000000",    desc = "神威如狱，万物臣服" },
    { name = "创世级",  min = "60000000000",   max = "10000000000000000000000000000000000000000", desc = "创世之力，毁天灭地" },
}

--- 在BigNum区间 [minStr, maxStr] 内生成随机数
---@param minStr string
---@param maxStr string
---@return string
local function BigNumRandRange(minStr, maxStr)
    -- 如果数字足够小，用 math.random
    local minN = tonumber(minStr)
    local maxN = tonumber(maxStr)
    if minN and maxN and maxN <= 2000000000 then
        return tostring(math.random(math.floor(minN), math.floor(maxN)))
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
    for i = 1, count do
        local name = RandPick(GEN_NAMES.monster_prefix) .. RandPick(GEN_NAMES.monster_suffix)
        if DataManager.monsters[name] then
            name = name .. tostring(i)
        end
        local hp = BigNumRandRange(mtype.min, mtype.max)
        local atk = BigNumRandRange(mtype.min, mtype.max)
        local def = BigNumRandRange(mtype.min, mtype.max)
        local exp = BigNumRandRange(mtype.min, mtype.max)
        local gold = BigNumRandRange(mtype.min, mtype.max)
        DataManager.monsters[name] = {
            name = name,
            type = mtype.name,
            desc = "一只" .. mtype.name .. "级的" .. name .. "，" .. mtype.desc,
            hp = hp,
            atk = atk,
            def = def,
            exp = exp,
            gold = gold,
            drops = "",
        }
        generated = generated + 1
    end
    SaveCategoryToCloud("monsters")
    return generated
end

--- 装备部位映射
local EQUIP_SLOT_MAP = { ["武器"] = "weapon", ["防具"] = "armor", ["饰品"] = "accessory" }

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
    -- 构建实际使用的部位列表
    local slots = {}
    if filterSlots and #filterSlots > 0 then
        for _, s in ipairs(filterSlots) do
            local en = EQUIP_SLOT_MAP[s]
            if en then table.insert(slots, en) end
        end
    end
    if #slots == 0 then slots = { "weapon", "armor", "accessory" } end

    -- 构建品质列表（直接使用中文名）
    local qualities = {}
    if filterQualities and #filterQualities > 0 then
        for _, q in ipairs(filterQualities) do
            if EQUIP_QUALITY_RANGES[q] then table.insert(qualities, q) end
        end
    end
    if #qualities == 0 then qualities = { "白色", "绿色", "橙色", "红色", "彩色", "地级", "天级", "帝级", "仙级", "神级", "创世级" } end

    local generated = 0
    for i = 1, count do
        local slot = slots[math.random(1, #slots)]
        local quality = qualities[math.random(1, #qualities)]
        local range = EQUIP_QUALITY_RANGES[quality]
        local prefix = RandPick(GEN_NAMES.equip_prefix)
        local suffix
        if slot == "weapon" then suffix = RandPick(GEN_NAMES.equip_weapon)
        elseif slot == "armor" then suffix = RandPick(GEN_NAMES.equip_armor)
        else suffix = RandPick(GEN_NAMES.equip_accessory)
        end
        local name = prefix .. suffix
        if DataManager.equipment[name] then
            name = name .. tostring(i)
        end
        -- 根据品质区间生成属性（武器偏攻击，防具偏防御，饰品偏生命）
        local baseVal = BigNumRandRange(range.min, range.max)
        local atkVal, defVal, hpVal
        if slot == "weapon" then
            atkVal = baseVal
            defVal = BigNumRandRange(range.min, BigNum.div(BigNum.add(range.min, range.max), "4"))
            hpVal = BigNumRandRange(range.min, BigNum.div(BigNum.add(range.min, range.max), "3"))
        elseif slot == "armor" then
            defVal = baseVal
            atkVal = BigNumRandRange(range.min, BigNum.div(BigNum.add(range.min, range.max), "4"))
            hpVal = BigNumRandRange(range.min, BigNum.div(BigNum.add(range.min, range.max), "2"))
        else
            hpVal = baseVal
            atkVal = BigNumRandRange(range.min, BigNum.div(BigNum.add(range.min, range.max), "3"))
            defVal = BigNumRandRange(range.min, BigNum.div(BigNum.add(range.min, range.max), "3"))
        end
        local lvReq = tostring(math.random(1, 100))
        local price = BigNum.mul(baseVal, tostring(math.random(2, 5)))
        local sell = BigNum.div(price, "3")
        DataManager.equipment[name] = {
            name = name,
            slot = slot,
            quality = quality,
            desc = "一件" .. quality .. "品质的" .. name,
            atk = atkVal,
            def = defVal,
            hp = hpVal,
            level_req = lvReq,
            price_buy = price,
            price_sell = sell,
        }
        generated = generated + 1
    end
    SaveCategoryToCloud("equipment")
    return generated
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
    ["材料"] = { effect = "none", descFmt = "修炼用的珍贵材料" },
}

--- 生成道具数据（支持类型过滤和限时设置）
---@param count number
---@param selectedTypes string[]|nil 选中的类型列表
---@param duration number|nil 限时时间（秒），0或nil表示不限时
local function GenerateItems(count, selectedTypes, duration)
    local typeList = selectedTypes or { "恢复血量", "材料" }
    local generated = 0
    for i = 1, count do
        local typeName = typeList[math.random(1, #typeList)]
        local info = ITEM_TYPE_EFFECTS[typeName] or ITEM_TYPE_EFFECTS["材料"]
        local name
        local value = "0"
        local itemDuration = nil
        if typeName == "经验倍率" then
            value = tostring(math.random(2, 100))
            local durMin = (duration and duration > 0) and duration or math.random(5, 60)
            itemDuration = durMin
            name = value .. "倍经验卡[" .. durMin .. "分钟]"
        elseif typeName == "货币倍率" then
            value = tostring(math.random(2, 100))
            local durMin = (duration and duration > 0) and duration or math.random(5, 60)
            itemDuration = durMin
            name = value .. "倍货币卡[" .. durMin .. "分钟]"
        else
            local prefix = RandPick(GEN_NAMES.item_prefix)
            local suffix
            if typeName == "材料" then
                suffix = RandPick(GEN_NAMES.item_material)
            else
                suffix = RandPick(GEN_NAMES.item_consumable)
            end
            name = prefix .. suffix
            if typeName ~= "材料" then
                value = tostring(math.random(10, 200))
            end
        end
        if DataManager.items[name] then
            name = name .. tostring(i)
        end
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
    end
    SaveCategoryToCloud("items")
    return generated
end

--- 生成副本数据
---@param count number
local function GenerateDungeons(count)
    local generated = 0
    for i = 1, count do
        local name = RandPick(GEN_NAMES.dungeon_prefix) .. RandPick(GEN_NAMES.dungeon_suffix)
        if DataManager.dungeons[name] then
            name = name .. tostring(i)
        end
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
    end
    SaveCategoryToCloud("dungeons")
    return generated
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
    return generated
end

--- 生成NPC数据
---@param count number
local function GenerateNPCs(count)
    local npcTypes = { "quest", "merchant" }
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
    for i = 1, count do
        local nType = npcTypes[math.random(1, #npcTypes)]
        local name = surnames[math.random(1, #surnames)] .. titles[math.random(1, #titles)]
        if DataManager.npcs[name] then
            name = name .. tostring(i)
        end
        local dialog
        if nType == "quest" then
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
    end
    SaveCategoryToCloud("npcs")
    return generated
end

--- 生成任务数据
---@param count number
local function GenerateQuests(count)
    local questTypes = { "main", "side", "side", "side" } -- side 更多
    local targetTypes = { "kill", "collect", "explore" }
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

        if tType == "kill" and #monsterNames > 0 then
            targetName = monsterNames[math.random(1, #monsterNames)]
            desc = RandPick(verbs_kill) .. targetCount .. "只" .. targetName
        elseif tType == "collect" and #itemNames > 0 then
            targetName = itemNames[math.random(1, #itemNames)]
            desc = RandPick(verbs_collect) .. targetCount .. "个" .. targetName
        elseif tType == "explore" and #mapNames > 0 then
            targetName = mapNames[math.random(1, #mapNames)]
            targetCount = 1
            desc = RandPick(verbs_explore) .. targetName
        else
            tType = "kill"
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
    return generated
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
            { id = "main_01", name = "初入仙途", desc = "与村长对话，了解修仙世界的基本知识。", target_type = "talk", target_name = "村长", target_count = "1", reward_exp = "50", reward_gold = "100", next_quest = "main_02" },
            { id = "main_02", name = "初试身手", desc = "击败新手村附近的野兽，证明你的实力。", target_type = "kill", target_name = "", target_count = "3", reward_exp = "100", reward_gold = "150", next_quest = "main_03" },
            { id = "main_03", name = "采集灵草", desc = "为村中药师采集灵草，学习基础炼丹知识。", target_type = "collect", target_name = "灵草", target_count = "5", reward_exp = "150", reward_gold = "200", next_quest = "main_04" },
            { id = "main_04", name = "修炼入门", desc = "通过冥想提升修为，突破练气期一层。", target_type = "level", target_name = "", target_count = "2", reward_exp = "200", reward_gold = "300", next_quest = "main_05" },
            { id = "main_05", name = "踏上征途", desc = "告别新手村，前往更广阔的修仙世界探索。", target_type = "explore", target_name = "", target_count = "1", reward_exp = "300", reward_gold = "500", next_quest = "" },
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

    -- 3. 地图之间相互连接（前后左右）
    for i, id in ipairs(mapNames) do
        local data = DataManager.maps[id]
        if (not data.front or data.front == "") and i < #mapNames then
            data.front = mapNames[i + 1]
            changes = changes + 1
        end
        if (not data.back or data.back == "") and i > 1 then
            data.back = mapNames[i - 1]
            changes = changes + 1
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
            if data.type == "quest" and (not data.quest_id or data.quest_id == "") then
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
            if data.type == "merchant" and (not data.shop_id or data.shop_id == "") then
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
            SaveCategoryToCloud("game_config")
            changes = changes + 1
        end
    end

    -- 保存所有改动
    SaveCategoryToCloud("maps")
    SaveCategoryToCloud("monsters")
    SaveCategoryToCloud("shops")
    SaveCategoryToCloud("dungeons")
    SaveCategoryToCloud("npcs")
    SaveCategoryToCloud("quests")

    return changes
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
                                local generated = onGenerate(n)
                                resultLabel:SetText("成功生成 " .. generated .. " 个" .. title)
                                ShowMsg(title .. "生成完成: " .. generated .. " 个")
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

    -- === 怪物生成（含类型选择） ===
    local monsterNumField = UI.TextField { value = "10", placeholder = "数量", width = 60, height = 30, fontSize = 13 }
    genFields["monsters"] = monsterNumField
    local monsterResultLabel = UI.Label { text = "", fontSize = 11, fontColor = { 100, 255, 150, 255 }, height = 16 }
    local selectedMonsterType = 1  -- 默认普通怪
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
            end,
        }
        monsterTypeBtns[idx] = btn
        table.insert(monsterTypeBtnChildren, btn)
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
                            local generated = GenerateMonsters(n, selectedMonsterType)
                            local typeName = MONSTER_TYPES[selectedMonsterType].name
                            monsterResultLabel:SetText("成功生成 " .. generated .. " 个" .. typeName)
                            ShowMsg("怪物生成完成: " .. generated .. " 个" .. typeName)
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
    local equipSlotSelected = { ["武器"] = true, ["防具"] = true, ["饰品"] = true }
    local function refreshEquipSlotBtns()
        for name, btn in pairs(equipSlotBtns) do
            btn:SetVariant(equipSlotSelected[name] and "primary" or "secondary")
        end
    end
    local equipSlotChildren = {}
    for _, slotName in ipairs(EQUIP_SLOTS) do
        local btn = UI.Button {
            text = slotName, fontSize = 10, width = 50, height = 22,
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
            UI.Panel { flexDirection = "row", alignItems = "center", gap = 8, children = {
                UI.Label { text = "一键生成", fontSize = 12, fontColor = { 200, 200, 220, 255 } },
                equipNumField,
                UI.Label { text = "个装备", fontSize = 12, fontColor = { 200, 200, 220, 255 } },
                UI.Button { text = "生成", variant = "primary", width = 60, height = 28, fontSize = 12,
                    onClick = function()
                        local n = tonumber(equipNumField:GetValue()) or 0
                        if n <= 0 then equipResultLabel:SetText("请输入有效数量"); return end
                        if n > 100 then n = 100 end
                        local selSlots = {}
                        for _, s in ipairs(EQUIP_SLOTS) do
                            if equipSlotSelected[s] then table.insert(selSlots, s) end
                        end
                        local selQuals = {}
                        for _, q in ipairs(EQUIP_QUALITIES) do
                            if equipQualSelected[q] then table.insert(selQuals, q) end
                        end
                        local generated = GenerateEquipment(n, selSlots, selQuals)
                        equipResultLabel:SetText("成功生成 " .. generated .. " 个装备")
                        ShowMsg("装备生成完成: " .. generated .. " 个")
                    end,
                },
            }},
            equipResultLabel,
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
            UI.Panel { flexDirection = "row", alignItems = "center", gap = 8, children = {
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
                        local generated = GenerateItems(n, selTypes, dur)
                        itemResultLabel:SetText("成功生成 " .. generated .. " 个道具")
                        ShowMsg("道具生成完成: " .. generated .. " 个")
                    end,
                },
            }},
            itemResultLabel,
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
                text = "一键部署",
                variant = "primary",
                width = 120,
                height = 36,
                fontSize = 14,
                onClick = function()
                    local changes = DeployAll()
                    deployResult:SetText("部署完成！共关联 " .. changes .. " 处数据")
                    ShowMsg("一键部署完成: " .. changes .. " 处关联")
                end,
            },
            deployResult,
        },
    }

    -- 一键生成境界
    local ALL_REALMS = { "练气期", "筑基期", "金丹期", "元婴期", "化神期", "渡劫期", "大乘期", "仙人境", "真仙境", "金仙境" }
    local cultCountInput = UI.TextField { width = 60, height = 30, fontSize = 13, value = "7", placeholder = "数量" }
    local cultResult = UI.Label { text = "", fontSize = 12, fontColor = { 100, 255, 180, 255 }, marginTop = 6 }
    local cultSection = UI.Panel {
        width = "100%",
        flexDirection = "column",
        backgroundColor = { 25, 35, 50, 220 },
        borderRadius = 8,
        padding = 12,
        marginTop = 12,
        borderColor = { 100, 200, 255, 80 },
        borderWidth = 1,
        children = {
            UI.Label {
                text = "一键生成境界",
                fontSize = 16,
                fontColor = { 100, 200, 255, 255 },
                marginBottom = 4,
            },
            UI.Label {
                text = "自动生成修仙境界体系，每个境界九层",
                fontSize = 11,
                fontColor = { 160, 160, 180, 255 },
                marginBottom = 10,
            },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                marginBottom = 10,
                children = {
                    UI.Label { text = "生成大境界数量:", fontSize = 12, fontColor = { 180, 180, 200, 255 }, marginRight = 8 },
                    cultCountInput,
                },
            },
            UI.Button {
                text = "生成境界",
                variant = "primary",
                width = 120,
                height = 36,
                fontSize = 14,
                onClick = function()
                    local realmCount = tonumber(cultCountInput:GetValue()) or 7
                    if realmCount < 1 then realmCount = 1 end
                    local layers = { "一层", "二层", "三层", "四层", "五层", "六层", "七层", "八层", "九层" }
                    local newCult = {}
                    local lvl = 1
                    for i = 1, realmCount do
                        local realmName
                        if i <= #ALL_REALMS then
                            realmName = ALL_REALMS[i]
                        else
                            realmName = "第" .. (i - #ALL_REALMS) .. "重天"
                        end
                        for _, layer in ipairs(layers) do
                            newCult[tostring(lvl)] = realmName .. layer
                            lvl = lvl + 1
                        end
                    end
                    -- 写入 gameConfig
                    local gc = DataManager.gameConfig or {}
                    gc["cultivation"] = newCult
                    DataManager.gameConfig = gc
                    SaveCategoryToCloud("game_config")
                    cultResult:SetText("已生成 " .. (lvl - 1) .. " 个境界等级（" .. realmCount .. " 大境界 × 9 层）")
                    ShowMsg("境界生成完成: " .. realmCount .. " 大境界 × 9 层 = " .. (lvl - 1) .. " 级")
                end,
            },
            cultResult,
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
                    deleteResult:SetText("已删除所有系统数据！")
                    ShowMsg("已删除所有系统数据")
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
            cultSection,
            deleteSection,
        },
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
    elseif catId == "generator" then RenderGenerator()
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
