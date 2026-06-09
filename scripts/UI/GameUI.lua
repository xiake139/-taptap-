---------------------------------------------------
-- GameUI.lua - 主游戏界面
-- 地图显示、方位移动、功能按钮
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local IniParser = require("Utils.IniParser")
local NumFormat = require("Utils.NumFormat")
local BigNum = require("Utils.BigNum")

local GameUI = {}

--- 游戏根面板引用（供子模块弹窗使用）
GameUI.rootPanel = nil

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
local logScroll_ = nil
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
local RealmUI = nil
local TradeUI = nil

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

    -- 怪物列表面板（含挑战按钮）
    monstersLabel_ = UI.Panel {
        id = "monstersPanel",
        flexDirection = "row",
        flexWrap = "wrap",
        alignItems = "center",
        gap = 6,
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

            -- 底部：日志区（可滚动）
            (function()
                logScroll_ = UI.ScrollView {
                    id = "logScroll",
                    width = "100%",
                    height = 100,
                    backgroundColor = { 20, 15, 35, 255 },
                    borderRadius = 6,
                    padding = 6,
                    children = { logPanel_ },
                }
                return logScroll_
            end)(),

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
                            UI.Button { text = "境界", variant = "secondary", flexGrow = 1, marginRight = 4, onClick = function() GameUI.ShowPanel("realm") end },
                            UI.Button { text = "副本", variant = "secondary", flexGrow = 1, marginRight = 4, onClick = function() GameUI.ShowPanel("dungeon") end },
                            UI.Button { text = "装备", variant = "secondary", flexGrow = 1, marginRight = 4, onClick = function() GameUI.ShowPanel("equip") end },
                            UI.Button { text = "任务", variant = "secondary", flexGrow = 1, marginRight = 4, onClick = function() GameUI.ShowPanel("quest") end },
                            UI.Button { text = "礼包", variant = "secondary", flexGrow = 1, marginRight = 4, onClick = function() GameUI.ShowPanel("giftpack") end },
                            UI.Button { text = "交易", variant = "secondary", flexGrow = 1, marginRight = 4, onClick = function() GameUI.ShowPanel("trade") end },
                            UI.Button { text = "排行", variant = "secondary", flexGrow = 1, marginRight = 4, onClick = function() GameUI.ShowPanel("leaderboard") end },
                            UI.Button { text = "聊天", variant = "secondary", flexGrow = 1, onClick = function() GameUI.ShowPanel("chat") end },
                        },
                    },
                },
            },
        },
    }

    -- 初始化地图显示
    GameUI.RefreshMap()

    GameUI.rootPanel = root
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

    -- 更新怪物列表（含挑战按钮）
    local monsterList = IniParser.ParseList(mapData.monsters or "")
    monstersLabel_:ClearChildren()
    monstersLabel_:AddChild(UI.Label {
        text = "怪物：",
        fontSize = 14,
        fontColor = { 220, 100, 100, 255 },
    })
    if #monsterList == 0 then
        monstersLabel_:AddChild(UI.Label { text = "无", fontSize = 13, fontColor = { 150, 150, 150, 255 } })
    else
        for _, mName in ipairs(monsterList) do
            monstersLabel_:AddChild(UI.Button {
                text = "【" .. mName .. "】挑战",
                variant = "danger",
                height = 26,
                fontSize = 12,
                onClick = function() GameUI.StartCombat(mName) end,
            })
        end
    end

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

--- 刷新地图后清空主内容区
function GameUI.ShowMonsterButtons(monsterList)
    -- 挑战按钮已整合到地图怪物面板，主内容区清空
    mainContent_:ClearChildren()
    GameUI.currentPanel = nil
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
        local levelReq = targetData.level_req or "0"
        local playerLevel = player.status.level or "1"
        if BigNum.lt(playerLevel, levelReq) then
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

-- 当前打开的面板类型
GameUI.currentPanel = nil

--- 显示功能面板
---@param panelType string
function GameUI.ShowPanel(panelType)
    GameUI.currentPanel = panelType
    mainContent_:ClearChildren()

    -- 聊天面板时隐藏日志区，腾出空间
    if logScroll_ then
        if panelType == "chat" then
            logScroll_:SetVisible(false)
        else
            logScroll_:SetVisible(true)
        end
    end

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
    elseif panelType == "realm" then
        if not RealmUI then RealmUI = require("UI.RealmUI") end
        RealmUI.Render(mainContent_)
    elseif panelType == "trade" then
        if not TradeUI then TradeUI = require("UI.TradeUI") end
        TradeUI.Render(mainContent_)
    elseif panelType == "giftpack" then
        GameUI.RenderGiftPackPanel()
    elseif panelType == "leaderboard" then
        GameUI.RenderLeaderboardPanel()
    elseif panelType == "chat" then
        GameUI.RenderChatPanel()
    end
end

--- 渲染礼包兑换面板
function GameUI.RenderGiftPackPanel()
    mainContent_:ClearChildren()

    local resultLabel = UI.Label {
        text = "",
        fontSize = 12,
        fontColor = { 200, 200, 200, 255 },
        height = 20,
    }

    local codeField = UI.TextField {
        placeholder = "输入兑换码",
        maxLength = 50,
        width = 180,
        height = 32,
    }

    mainContent_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "column",
        padding = 8,
        gap = 8,
        children = {
            UI.Label { text = "礼包兑换", fontSize = 16, fontColor = { 255, 200, 100, 255 } },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    codeField,
                    UI.Button {
                        text = "兑换",
                        variant = "primary",
                        height = 32,
                        onClick = function()
                            local code = codeField:GetValue()
                            if code == "" then
                                resultLabel:SetText("请输入兑换码")
                                resultLabel:SetFontColor({ 255, 100, 100, 255 })
                                return
                            end
                            GameUI.RedeemGiftPack(code, resultLabel)
                        end,
                    },
                },
            },
            resultLabel,
        },
    })
end

--- 兑换礼包逻辑
---@param code string
---@param resultLabel any
function GameUI.RedeemGiftPack(code, resultLabel)
    local player = DataManager.playerData
    if not player then return end

    -- 查找礼包
    local pack = DataManager.giftpacks[code]
    if not pack then
        resultLabel:SetText("兑换码无效")
        resultLabel:SetFontColor({ 255, 100, 100, 255 })
        return
    end

    -- 检查是否已兑换
    player.redeemed_codes = player.redeemed_codes or {}
    for _, c in ipairs(player.redeemed_codes) do
        if c == code then
            resultLabel:SetText("该礼包已兑换过")
            resultLabel:SetFontColor({ 255, 100, 100, 255 })
            return
        end
    end

    -- 检查使用次数上限
    if BigNum.gt(pack.max_uses or "0", "0") and BigNum.gte(pack.used_count or "0", pack.max_uses) then
        resultLabel:SetText("该礼包已被领完")
        resultLabel:SetFontColor({ 255, 100, 100, 255 })
        return
    end

    -- 发放奖励
    local rewards = {}

    -- 金币
    if BigNum.gt(pack.reward_gold or "0", "0") then
        player.status.gold = BigNum.add(player.status.gold or "0", pack.reward_gold)
        table.insert(rewards, "金币+" .. pack.reward_gold)
    end

    -- 经验
    if BigNum.gt(pack.reward_exp or "0", "0") then
        player.status.exp = BigNum.add(player.status.exp or "0", pack.reward_exp)
        table.insert(rewards, "经验+" .. pack.reward_exp)
    end

    -- 物品
    if pack.reward_items and pack.reward_items ~= "" then
        for part in pack.reward_items:gmatch("[^,]+") do
            local itemName, countStr = part:match("^(.+):(%d+)$")
            if itemName then
                local cnt = countStr or "1"
                GameUI.AddItemToBag(itemName, cnt)
                table.insert(rewards, itemName .. "x" .. cnt)
            else
                -- 没有数量，默认1个
                GameUI.AddItemToBag(part, "1")
                table.insert(rewards, part .. "x1")
            end
        end
    end

    -- 记录已兑换
    table.insert(player.redeemed_codes, code)

    -- 增加全局使用次数并保存到云端
    pack.used_count = BigNum.add(pack.used_count or "0", "1")
    DataManager.giftpacks[code] = pack

    -- 保存礼包使用次数到云端（使用共享云存储）
    local cloud = DataManager.GetCloudProvider()
    if cloud then
        local IniParser = require("Utils.IniParser")
        local sections = {}
        for id, data in pairs(DataManager.giftpacks) do
            sections[id] = {
                ["名称"] = data.name or id,
                ["描述"] = data.desc or "",
                ["奖励物品"] = data.reward_items or "",
                ["奖励金币"] = tostring(data.reward_gold or "0"),
                ["奖励经验"] = tostring(data.reward_exp or "0"),
                ["最大使用次数"] = tostring(data.max_uses or "0"),
                ["已使用次数"] = tostring(data.used_count or "0"),
            }
        end
        local content = IniParser.Serialize(sections)
        cloud:Set("系统配置/giftpacks.ini", content, {
            ok = function() print("[GiftPack] 礼包使用次数已同步") end,
            error = function() print("[GiftPack] 礼包同步失败") end,
        })
    end

    -- 保存玩家数据
    DataManager.SaveToCloud(player)

    -- 显示结果
    local rewardText = "兑换成功！获得: " .. table.concat(rewards, ", ")
    resultLabel:SetText(rewardText)
    resultLabel:SetFontColor({ 100, 255, 100, 255 })
    GameUI.AddLog("兑换礼包[" .. (pack.name or code) .. "] " .. table.concat(rewards, ","))

    -- 检查升级
    GameUI.CheckLevelUp()
end

--- 渲染排行榜面板
--- 固定的排行榜配置
local LEADERBOARD_TABS = {
    { name = "等级", source = "等级" },
    { name = "攻击", source = "攻击力" },
    { name = "防御", source = "防御力" },
    { name = "生命", source = "生命上限" },
    { name = "金币", source = "金币" },
}

function GameUI.RenderLeaderboardPanel()
    mainContent_:ClearChildren()

    -- 排行榜标题
    mainContent_:AddChild(UI.Label {
        text = "排行榜",
        fontSize = 16,
        fontColor = { 255, 200, 100, 255 },
        textAlign = "center",
        marginBottom = 8,
        width = "100%",
    })

    -- 标签按钮行
    local tabChildren = {}
    for i, tab in ipairs(LEADERBOARD_TABS) do
        table.insert(tabChildren, UI.Button {
            text = tab.name,
            variant = "secondary",
            flexGrow = 1,
            marginRight = (i < #LEADERBOARD_TABS) and 4 or 0,
            onClick = function()
                GameUI.ShowLeaderboardDetail(tab.source)
            end,
        })
    end

    mainContent_:AddChild(UI.Panel {
        flexDirection = "row",
        width = "100%",
        paddingLeft = 8, paddingRight = 8,
        marginBottom = 8,
        children = tabChildren,
    })

    -- 内容区
    mainContent_:AddChild(UI.Panel {
        id = "lb_content",
        width = "100%",
        padding = 8,
        children = {
            UI.Label { text = "加载中...", fontSize = 12, fontColor = { 180, 180, 180, 255 }, textAlign = "center" },
        },
    })

    -- 先同步当前玩家分数，再显示第一个排行榜（等级）
    DataManager.SyncLeaderboardScores(function()
        GameUI.ShowLeaderboardDetail(LEADERBOARD_TABS[1].source)
    end)
end

--- 显示某个排行榜详情
---@param source string 数据来源字段名（等级/攻击力/防御力/生命上限/金币）
function GameUI.ShowLeaderboardDetail(source)
    local existing = mainContent_:FindById("lb_content")
    if not existing then return end
    existing:ClearChildren()

    -- 从本地排行数据排序（显示前20名）
    local rankedList = DataManager.GetRankedList(source, 20)

    -- 标题行
    existing:AddChild(UI.Panel {
        flexDirection = "row",
        width = "100%",
        paddingLeft = 4, paddingRight = 4,
        marginBottom = 4,
        children = {
            UI.Label { text = "排名", fontSize = 11, fontColor = { 200, 170, 100, 255 }, width = 40 },
            UI.Label { text = "玩家昵称", fontSize = 11, fontColor = { 200, 170, 100, 255 }, flexGrow = 1 },
            UI.Label { text = "数值", fontSize = 11, fontColor = { 200, 170, 100, 255 }, width = 80, textAlign = "right" },
        },
    })

    if #rankedList == 0 then
        existing:AddChild(UI.Label {
            text = "暂无数据",
            fontSize = 12,
            fontColor = { 150, 150, 150, 255 },
            textAlign = "center",
            marginTop = 8,
        })
        return
    end

    -- 显示排行列表
    for i, item in ipairs(rankedList) do
        local rankColor = (i <= 3) and { 255, 215, 0, 255 } or { 200, 200, 220, 255 }
        existing:AddChild(UI.Panel {
            flexDirection = "row",
            width = "100%",
            paddingLeft = 4, paddingRight = 4,
            paddingTop = 3, paddingBottom = 3,
            backgroundColor = (i % 2 == 0) and { 40, 35, 60, 150 } or { 30, 25, 50, 100 },
            children = {
                UI.Label { text = "#" .. i, fontSize = 12, fontColor = rankColor, width = 40 },
                UI.Label { text = item.name, fontSize = 12, fontColor = { 220, 220, 240, 255 }, flexGrow = 1 },
                UI.Label { text = NumFormat.Short(item.value), fontSize = 12, fontColor = { 100, 255, 200, 255 }, width = 80, textAlign = "right" },
            },
        })
    end
end

-- =============== 聊天面板 ===============

local chatListPanel_ = nil
local chatInput_ = nil

function GameUI.RenderChatPanel()
    if not mainContent_ then return end
    mainContent_:RemoveAllChildren()

    -- 先刷新聊天记录
    DataManager.RefreshChatMessages(function()
        GameUI.BuildChatUI()
    end)

    -- 先显示加载中
    mainContent_:AddChild(UI.Label {
        text = "加载聊天记录...",
        fontSize = 13,
        fontColor = { 180, 180, 200, 255 },
        marginTop = 8,
        marginLeft = 8,
    })
end

function GameUI.BuildChatUI()
    if not mainContent_ then return end
    mainContent_:RemoveAllChildren()

    -- 标题
    mainContent_:AddChild(UI.Label {
        text = "世界聊天",
        fontSize = 15,
        fontColor = { 255, 220, 100, 255 },
        marginBottom = 6,
        marginLeft = 4,
    })

    -- 消息列表区域
    chatListPanel_ = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        backgroundColor = { 20, 15, 40, 180 },
        borderRadius = 4,
        paddingLeft = 6, paddingRight = 6,
        paddingTop = 4, paddingBottom = 4,
    }
    mainContent_:AddChild(chatListPanel_)

    -- 填充消息
    GameUI.RefreshChatList()

    -- 输入区域
    local inputRow = UI.Panel {
        flexDirection = "row",
        width = "100%",
        marginTop = 6,
        alignItems = "center",
    }
    mainContent_:AddChild(inputRow)

    chatInput_ = UI.TextField {
        placeholder = "输入消息...",
        flexGrow = 1,
        height = 32,
        marginRight = 6,
        fontSize = 13,
    }
    inputRow:AddChild(chatInput_)

    inputRow:AddChild(UI.Button {
        text = "发送",
        variant = "primary",
        width = 56,
        height = 32,
        onClick = function()
            local text = chatInput_:GetValue()
            if text and text ~= "" then
                chatInput_:SetValue("")
                DataManager.SendChatMessage(text, function(success)
                    if success then
                        GameUI.RefreshChatList()
                    end
                end)
            end
        end,
    })

    -- 刷新按钮
    inputRow:AddChild(UI.Button {
        text = "刷新",
        variant = "secondary",
        width = 56,
        height = 32,
        marginLeft = 4,
        onClick = function()
            DataManager.RefreshChatMessages(function()
                GameUI.RefreshChatList()
            end)
        end,
    })
end

function GameUI.RefreshChatList()
    if not chatListPanel_ then return end
    chatListPanel_:RemoveAllChildren()

    local messages = DataManager.chatMessages
    if not messages or #messages == 0 then
        chatListPanel_:AddChild(UI.Label {
            text = "暂无消息，发一条吧~",
            fontSize = 12,
            fontColor = { 150, 150, 170, 255 },
            marginTop = 8,
        })
        return
    end

    for i, msg in ipairs(messages) do
        chatListPanel_:AddChild(UI.Panel {
            width = "100%",
            paddingTop = 3, paddingBottom = 3,
            paddingLeft = 2, paddingRight = 2,
            backgroundColor = (i % 2 == 0) and { 40, 35, 60, 100 } or { 0, 0, 0, 0 },
            children = {
                UI.Panel {
                    flexDirection = "row",
                    width = "100%",
                    children = {
                        UI.Label {
                            text = msg.sender,
                            fontSize = 11,
                            fontColor = { 100, 200, 255, 255 },
                            marginRight = 8,
                        },
                        UI.Label {
                            text = msg.time or "",
                            fontSize = 10,
                            fontColor = { 120, 120, 140, 255 },
                        },
                    },
                },
                UI.Label {
                    text = msg.content,
                    fontSize = 12,
                    fontColor = { 220, 220, 240, 255 },
                    marginTop = 2,
                    whiteSpace = "normal",
                },
            },
        })
    end
end

--- 添加游戏日志
---@param msg string
function GameUI.AddLog(msg)
    if not logPanel_ then return end

    -- 限制最多20条日志
    local children = logPanel_:GetChildren()
    if children and #children >= 20 then
        logPanel_:RemoveChild(children[1])
    end

    logPanel_:AddChild(UI.Label {
        text = "> " .. msg,
        fontSize = 11,
        fontColor = { 180, 180, 200, 255 },
        whiteSpace = "normal",
    })

    -- 自动滚动到底部
    if logScroll_ and logScroll_.ScrollToBottom then
        logScroll_:ScrollToBottom()
    end

    print("[Log] " .. msg)
end

--- 检查探索类任务完成
---@param mapName string
function GameUI.CheckExploreQuest(mapName)
    local player = DataManager.playerData
    if not player then return end

    for _, quest in ipairs(player.quests.active) do
        local qData = DataManager.GetQuest(quest.id)
        if qData and (qData.target_type == "explore" or qData.target_type == "探索") and qData.target_name == mapName then
            quest.progress = "1"
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

    local targetCount = qData.target_count or "1"
    if BigNum.gte(tostring(quest.progress or "0"), targetCount) then
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
    local expReward = qData.reward_exp or "0"
    local goldReward = qData.reward_gold or "0"
    player.status.exp = BigNum.add(player.status.exp or "0", expReward)
    player.status.gold = BigNum.add(player.status.gold or "0", goldReward)

    GameUI.AddLog("任务完成：" .. (qData.name or quest.id) .. "！获得经验" .. expReward .. " 金币" .. goldReward)

    -- 物品奖励
    local rewardItems = IniParser.ParseList(qData.reward_items or "")
    for _, itemStr in ipairs(rewardItems) do
        local iName, iCount = itemStr:match("^(.+):(%d+)$")
        if iName then
            GameUI.AddItemToBag(iName, iCount or "1")
        end
    end

    -- 检查升级
    GameUI.CheckLevelUp()

    -- 接取下一个任务
    if qData.next_quest and qData.next_quest ~= "" then
        table.insert(player.quests.active, { id = qData.next_quest, progress = "0" })
        local nextData = DataManager.GetQuest(qData.next_quest)
        if nextData then
            GameUI.AddLog("新任务：" .. (nextData.name or qData.next_quest))
        end
    end

    DataManager.SaveToCloud(player)
end

--- 添加物品到背包
---@param itemName string
---@param count string|number
function GameUI.AddItemToBag(itemName, count)
    local player = DataManager.playerData
    if not player then return end
    local countStr = tostring(count)

    -- 检查是否已有该物品
    for _, item in ipairs(player.bag) do
        if item.name == itemName then
            item.count = BigNum.add(item.count or "0", countStr)
            GameUI.AddLog("获得 " .. itemName .. " x" .. countStr)
            return
        end
    end

    -- 新物品
    table.insert(player.bag, { name = itemName, count = countStr })
    GameUI.AddLog("获得 " .. itemName .. " x" .. countStr)
end

--- 检查升级
function GameUI.CheckLevelUp()
    local player = DataManager.playerData
    if not player then return end

    local level = tostring(player.status.level or "1")
    local exp = BigNum.new(player.status.exp or "0")
    local needExp = DataManager.GetExpForLevel(level)
    local maxLevel = DataManager.GetMaxLevel()

    while BigNum.gte(exp, needExp) do
        -- 最高等级限制
        if tonumber(level) >= maxLevel then
            GameUI.AddLog("已达到最高等级 " .. maxLevel .. "，无法继续提升")
            break
        end

        exp = BigNum.sub(exp, needExp)
        level = BigNum.add(level, "1")

        -- 提升属性
        local config = DataManager.gameConfig["level_up"] or {}
        local hpAdd = tostring(config.hp_per_level or "20")
        local mpAdd = tostring(config.mp_per_level or "10")
        local atkAdd = tostring(config.atk_per_level or "3")
        local defAdd = tostring(config.def_per_level or "2")

        player.status.max_hp = BigNum.add(player.status.max_hp or "100", hpAdd)
        player.status.hp = player.status.max_hp
        player.status.max_mp = BigNum.add(player.status.max_mp or "50", mpAdd)
        player.status.mp = player.status.max_mp
        player.status.atk = BigNum.add(player.status.atk or "5", atkAdd)
        player.status.def = BigNum.add(player.status.def or "3", defAdd)

        GameUI.AddLog("恭喜！等级提升至 " .. level)

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
