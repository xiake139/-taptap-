---------------------------------------------------
-- GameUI.lua - 主游戏界面
-- 地图显示、方位移动、功能按钮
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local IniParser = require("Utils.IniParser")

local GameUI = {}

-- UI 引用
local mapNameLabel_ = nil
local mapDescLabel_ = nil
local monstersLabel_ = nil
local npcsPanel_ = nil
local dirBtnFront_ = nil
local dirBtnBack_ = nil
local dirBtnLeft_ = nil
local dirBtnRight_ = nil
local logPanel_ = nil
local mainContent_ = nil

-- 子面板模块（延迟加载）
local StatusUI = nil
local BagUI = nil
local ShopUI = nil
local DungeonUI = nil
local EquipUI = nil
local QuestUI = nil
local CombatUI = nil
local DialogUI = nil

--- 创建主游戏界面
---@return Widget
function GameUI.Create()
    -- 地图名称
    mapNameLabel_ = UI.Label {
        id = "mapName",
        text = "加载中...",
        fontSize = 22,
        fontColor = { 200, 170, 100, 255 },
        textAlign = "center",
    }

    -- 地图描述
    mapDescLabel_ = UI.Label {
        id = "mapDesc",
        text = "",
        fontSize = 13,
        fontColor = { 160, 160, 180, 255 },
        textAlign = "center",
        whiteSpace = "normal",
    }

    -- 怪物列表
    monstersLabel_ = UI.Label {
        id = "monsters",
        text = "怪物：",
        fontSize = 14,
        fontColor = { 220, 100, 100, 255 },
        whiteSpace = "normal",
    }

    -- NPC 面板（动态生成按钮）
    npcsPanel_ = UI.Panel {
        id = "npcsPanel",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 6,
    }

    -- 方向按钮
    dirBtnFront_ = UI.Button { text = "前：---", variant = "secondary", width = "48%", onClick = function() GameUI.Move("front") end }
    dirBtnBack_ = UI.Button { text = "后：---", variant = "secondary", width = "48%", onClick = function() GameUI.Move("back") end }
    dirBtnLeft_ = UI.Button { text = "左：---", variant = "secondary", width = "48%", onClick = function() GameUI.Move("left") end }
    dirBtnRight_ = UI.Button { text = "右：---", variant = "secondary", width = "48%", onClick = function() GameUI.Move("right") end }

    -- 游戏日志面板
    logPanel_ = UI.Panel {
        id = "logPanel",
        flexDirection = "column",
        gap = 2,
        width = "100%",
    }

    -- 主内容区域
    mainContent_ = UI.Panel {
        id = "mainContent",
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        flexDirection = "column",
    }

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        backgroundColor = { 15, 10, 30, 255 },
        padding = 12,
        gap = 6,
        children = {
            -- 顶部：地图信息
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                backgroundColor = { 25, 20, 45, 255 },
                borderRadius = 8,
                padding = 12,
                gap = 4,
                children = {
                    mapNameLabel_,
                    mapDescLabel_,
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 50, 40, 70, 255 }, marginTop = 4, marginBottom = 4 },
                    monstersLabel_,
                    UI.Label { text = "NPC：", fontSize = 14, fontColor = { 100, 200, 100, 255 } },
                    npcsPanel_,
                },
            },

            -- 中间：方向按钮
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                alignItems = "center",
                gap = 4,
                children = {
                    UI.Panel { flexDirection = "row", gap = 6, width = "100%", justifyContent = "center", children = { dirBtnFront_, dirBtnBack_ } },
                    UI.Panel { flexDirection = "row", gap = 6, width = "100%", justifyContent = "center", children = { dirBtnLeft_, dirBtnRight_ } },
                },
            },

            -- 中间：主内容区域（用于切换面板）
            UI.ScrollView {
                width = "100%",
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                children = {
                    mainContent_,
                },
            },

            -- 底部：日志区
            UI.Panel {
                width = "100%",
                height = 60,
                backgroundColor = { 20, 15, 35, 255 },
                borderRadius = 6,
                padding = 6,
                overflow = "hidden",
                children = { logPanel_ },
            },

            -- 底部：功能按钮
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 4,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-around",
                        width = "100%",
                        children = {
                            UI.Button { text = "状态", variant = "primary", flexGrow = 1, marginRight = 4, onClick = function() GameUI.ShowPanel("status") end },
                            UI.Button { text = "背包", variant = "primary", flexGrow = 1, marginRight = 4, onClick = function() GameUI.ShowPanel("bag") end },
                            UI.Button { text = "商城", variant = "primary", flexGrow = 1, onClick = function() GameUI.ShowPanel("shop") end },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-around",
                        width = "100%",
                        children = {
                            UI.Button { text = "副本", variant = "secondary", flexGrow = 1, marginRight = 4, onClick = function() GameUI.ShowPanel("dungeon") end },
                            UI.Button { text = "装备", variant = "secondary", flexGrow = 1, marginRight = 4, onClick = function() GameUI.ShowPanel("equip") end },
                            UI.Button { text = "任务", variant = "secondary", flexGrow = 1, onClick = function() GameUI.ShowPanel("quest") end },
                        },
                    },
                },
            },
        },
    }

    -- 初始化地图显示
    GameUI.RefreshMap()

    return root
end

--- 刷新地图显示
function GameUI.RefreshMap()
    local player = DataManager.playerData
    if not player then return end

    local mapName = player.status.current_map
    local mapData = DataManager.GetMap(mapName)

    if not mapData then
        mapNameLabel_:SetText("【未知地图】")
        return
    end

    -- 更新地图名和描述
    mapNameLabel_:SetText("【" .. (mapData.name or mapName) .. "】")
    mapDescLabel_:SetText(mapData.desc or "")

    -- 更新怪物列表
    local monsterList = IniParser.ParseList(mapData.monsters or "")
    local monsterStr = "怪物："
    for i, m in ipairs(monsterList) do
        monsterStr = monsterStr .. "【" .. m .. "】"
    end
    if #monsterList == 0 then monsterStr = monsterStr .. "无" end
    monstersLabel_:SetText(monsterStr)

    -- 更新NPC按钮
    npcsPanel_:ClearChildren()
    local npcList = IniParser.ParseList(mapData.npcs or "")
    for _, npcName in ipairs(npcList) do
        npcsPanel_:AddChild(UI.Button {
            text = "【" .. npcName .. "】",
            variant = "success",
            height = 28,
            onClick = function() GameUI.TalkToNPC(npcName) end,
        })
    end
    if #npcList == 0 then
        npcsPanel_:AddChild(UI.Label { text = "无", fontSize = 13, fontColor = { 100, 200, 100, 255 } })
    end

    -- 更新方向按钮
    local function updateDirBtn(btn, dir, target)
        local dirLabel = ({ front = "前", back = "后", left = "左", right = "右" })[dir]
        if target and target ~= "" then
            btn:SetText(dirLabel .. "：" .. target)
            btn:SetDisabled(false)
        else
            btn:SetText(dirLabel .. "：---")
            btn:SetDisabled(true)
        end
    end

    updateDirBtn(dirBtnFront_, "front", mapData.front)
    updateDirBtn(dirBtnBack_, "back", mapData.back)
    updateDirBtn(dirBtnLeft_, "left", mapData.left)
    updateDirBtn(dirBtnRight_, "right", mapData.right)

    -- 检查打怪按钮
    GameUI.ShowMonsterButtons(monsterList)
end

--- 显示怪物战斗按钮
function GameUI.ShowMonsterButtons(monsterList)
    mainContent_:ClearChildren()
    if #monsterList > 0 then
        mainContent_:AddChild(UI.Label {
            text = "— 可挑战的怪物 —",
            fontSize = 14,
            fontColor = { 220, 180, 100, 255 },
            textAlign = "center",
            marginTop = 8,
            marginBottom = 4,
        })
        for _, mName in ipairs(monsterList) do
            local mData = DataManager.GetMonster(mName)
            local desc = mData and string.format("Lv? HP:%s ATK:%s", tostring(mData.hp), tostring(mData.atk)) or ""
            mainContent_:AddChild(UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                width = "100%",
                padding = 4,
                children = {
                    UI.Label { text = "【" .. mName .. "】", fontSize = 14, fontColor = { 255, 150, 150, 255 }, flexGrow = 1 },
                    UI.Label { text = desc, fontSize = 11, fontColor = { 150, 150, 150, 255 } },
                    UI.Button {
                        text = "挑战",
                        variant = "danger",
                        height = 28,
                        onClick = function() GameUI.StartCombat(mName) end,
                    },
                },
            })
        end
    end
end

--- 移动到新地图
---@param direction string "front"|"back"|"left"|"right"
function GameUI.Move(direction)
    local player = DataManager.playerData
    if not player then return end

    local currentMap = DataManager.GetMap(player.status.current_map)
    if not currentMap then return end

    local targetMap = currentMap[direction]
    if not targetMap or targetMap == "" then
        GameUI.AddLog("此方向无法前进")
        return
    end

    -- 检查等级需求
    local targetData = DataManager.GetMap(targetMap)
    if targetData then
        local levelReq = tonumber(targetData.level_req) or 0
        local playerLevel = tonumber(player.status.level) or 1
        if playerLevel < levelReq then
            GameUI.AddLog("等级不足！需要等级 " .. levelReq .. " 才能前往 " .. targetMap)
            return
        end
    end

    -- 移动
    player.status.current_map = targetMap
    GameUI.AddLog("你来到了【" .. targetMap .. "】")
    GameUI.RefreshMap()

    -- 检查探索类任务
    GameUI.CheckExploreQuest(targetMap)

    -- 自动保存
    DataManager.SaveToCloud(player)
end

--- 与NPC对话
---@param npcName string
function GameUI.TalkToNPC(npcName)
    if not DialogUI then
        DialogUI = require("UI.DialogUI")
    end
    DialogUI.Show(npcName, mainContent_)
end

--- 开始战斗
---@param monsterName string
function GameUI.StartCombat(monsterName)
    if not CombatUI then
        CombatUI = require("UI.CombatUI")
    end
    CombatUI.Start(monsterName, mainContent_, function(result)
        -- 战斗结束回调
        GameUI.RefreshMap()
    end)
end

--- 显示功能面板
---@param panelType string
function GameUI.ShowPanel(panelType)
    mainContent_:ClearChildren()

    if panelType == "status" then
        if not StatusUI then StatusUI = require("UI.StatusUI") end
        StatusUI.Render(mainContent_)
    elseif panelType == "bag" then
        if not BagUI then BagUI = require("UI.BagUI") end
        BagUI.Render(mainContent_)
    elseif panelType == "shop" then
        if not ShopUI then ShopUI = require("UI.ShopUI") end
        ShopUI.Render(mainContent_)
    elseif panelType == "dungeon" then
        if not DungeonUI then DungeonUI = require("UI.DungeonUI") end
        DungeonUI.Render(mainContent_)
    elseif panelType == "equip" then
        if not EquipUI then EquipUI = require("UI.EquipUI") end
        EquipUI.Render(mainContent_)
    elseif panelType == "quest" then
        if not QuestUI then QuestUI = require("UI.QuestUI") end
        QuestUI.Render(mainContent_)
    end
end

--- 添加游戏日志
---@param msg string
function GameUI.AddLog(msg)
    if not logPanel_ then return end

    -- 限制最多5条日志
    local children = logPanel_:GetChildren()
    if children and #children >= 5 then
        logPanel_:RemoveChild(children[1])
    end

    logPanel_:AddChild(UI.Label {
        text = "> " .. msg,
        fontSize = 11,
        fontColor = { 180, 180, 200, 255 },
        whiteSpace = "normal",
    })

    print("[Log] " .. msg)
end

--- 检查探索类任务完成
---@param mapName string
function GameUI.CheckExploreQuest(mapName)
    local player = DataManager.playerData
    if not player then return end

    for _, quest in ipairs(player.quests.active) do
        local qData = DataManager.GetQuest(quest.id)
        if qData and qData.target_type == "explore" and qData.target_name == mapName then
            quest.progress = 1
            GameUI.AddLog("任务进度更新：" .. (qData.name or quest.id))
            GameUI.CheckQuestComplete(quest)
        end
    end
end

--- 检查任务是否完成
---@param quest table {id, progress}
function GameUI.CheckQuestComplete(quest)
    local qData = DataManager.GetQuest(quest.id)
    if not qData then return end

    local targetCount = tonumber(qData.target_count) or 1
    if quest.progress >= targetCount then
        GameUI.CompleteQuest(quest)
    end
end

--- 完成任务
---@param quest table
function GameUI.CompleteQuest(quest)
    local player = DataManager.playerData
    if not player then return end
    local qData = DataManager.GetQuest(quest.id)
    if not qData then return end

    -- 移除激活任务
    for i, q in ipairs(player.quests.active) do
        if q.id == quest.id then
            table.remove(player.quests.active, i)
            break
        end
    end

    -- 添加到已完成
    table.insert(player.quests.completed, quest.id)

    -- 发放奖励
    local expReward = tonumber(qData.reward_exp) or 0
    local goldReward = tonumber(qData.reward_gold) or 0
    player.status.exp = (tonumber(player.status.exp) or 0) + expReward
    player.status.gold = (tonumber(player.status.gold) or 0) + goldReward

    GameUI.AddLog("任务完成：" .. (qData.name or quest.id) .. "！获得经验" .. expReward .. " 金币" .. goldReward)

    -- 物品奖励
    local rewardItems = IniParser.ParseList(qData.reward_items or "")
    for _, itemStr in ipairs(rewardItems) do
        local iName, iCount = itemStr:match("^(.+):(%d+)$")
        if iName then
            GameUI.AddItemToBag(iName, tonumber(iCount) or 1)
        end
    end

    -- 检查升级
    GameUI.CheckLevelUp()

    -- 接取下一个任务
    if qData.next_quest and qData.next_quest ~= "" then
        table.insert(player.quests.active, { id = qData.next_quest, progress = 0 })
        local nextData = DataManager.GetQuest(qData.next_quest)
        if nextData then
            GameUI.AddLog("新任务：" .. (nextData.name or qData.next_quest))
        end
    end

    DataManager.SaveToCloud(player)
end

--- 添加物品到背包
---@param itemName string
---@param count number
function GameUI.AddItemToBag(itemName, count)
    local player = DataManager.playerData
    if not player then return end

    -- 检查是否已有该物品
    for _, item in ipairs(player.bag) do
        if item.name == itemName then
            item.count = item.count + count
            GameUI.AddLog("获得 " .. itemName .. " x" .. count)
            return
        end
    end

    -- 新物品
    table.insert(player.bag, { name = itemName, count = count })
    GameUI.AddLog("获得 " .. itemName .. " x" .. count)
end

--- 检查升级
function GameUI.CheckLevelUp()
    local player = DataManager.playerData
    if not player then return end

    local level = tonumber(player.status.level) or 1
    local exp = tonumber(player.status.exp) or 0
    local needExp = DataManager.GetExpForLevel(level)

    while exp >= needExp do
        exp = exp - needExp
        level = level + 1

        -- 提升属性
        local config = DataManager.gameConfig["level_up"] or {}
        player.status.max_hp = (tonumber(player.status.max_hp) or 100) + (config.hp_per_level or 20)
        player.status.hp = player.status.max_hp
        player.status.max_mp = (tonumber(player.status.max_mp) or 50) + (config.mp_per_level or 10)
        player.status.mp = player.status.max_mp
        player.status.atk = (tonumber(player.status.atk) or 5) + (config.atk_per_level or 3)
        player.status.def = (tonumber(player.status.def) or 3) + (config.def_per_level or 2)

        -- 更新境界
        player.status.cultivation = DataManager.GetCultivation(level)

        GameUI.AddLog("恭喜突破！等级提升至 " .. level .. "，境界：" .. player.status.cultivation)

        needExp = DataManager.GetExpForLevel(level)
    end

    player.status.level = level
    player.status.exp = exp
end

--- ESC 键处理
function GameUI.HandleEscape()
    -- 返回地图主界面
    GameUI.RefreshMap()
end

return GameUI
