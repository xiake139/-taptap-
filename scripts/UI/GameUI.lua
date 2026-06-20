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

local mainContent_ = nil

-- 日志弹窗（模态，手动关闭）
local logDialog_ = nil      -- 弹窗遮罩层

local logTexts_ = {}        -- 消息文本队列
local LOG_MAX = 30          -- 最多保留条数

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
local MailboxUI = nil
local PetUI = nil
local MonsterGuideUI = nil


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



            -- 底部：可折叠功能按钮
            (function()
                local buttons = {
                    { text = "状态", panel = "status", variant = "primary" },
                    { text = "背包", panel = "bag", variant = "primary" },
                    { text = "商城", panel = "shop", variant = "primary" },
                    { text = "境界", panel = "realm", variant = "secondary" },
                    { text = "副本", panel = "dungeon", variant = "secondary" },
                    { text = "装备", panel = "equip", variant = "secondary" },
                    { text = "任务", panel = "quest", variant = "secondary" },
                    { text = "礼包", panel = "giftpack", variant = "secondary" },
                    { text = "交易", panel = "trade", variant = "secondary" },
                    { text = "宠物", panel = "pet", variant = "secondary" },
                    { text = "战魂", panel = "battle_soul", variant = "secondary" },
                    { text = "传送", panel = "teleport", variant = "secondary" },
                    { text = "坐骑", panel = "mount", variant = "secondary" },
                    { text = "图鉴", panel = "monster_guide", variant = "secondary" },
                    { text = "邮箱", panel = "mailbox", variant = "secondary" },
                    { text = "排行", panel = "leaderboard", variant = "secondary" },
                    { text = "聊天", panel = "chat", variant = "secondary" },
                    { text = "数值:" .. NumFormat.GetModeLabel(), panel = "toggle_numformat", variant = "outline" },
                    { text = "退出", panel = "logout", variant = "danger" },
                }
                -- 每3个一排
                local rows = {}
                for i = 1, #buttons, 3 do
                    local rowChildren = {}
                    for j = i, math.min(i + 2, #buttons) do
                        local btn = buttons[j]
                        table.insert(rowChildren, UI.Button {
                            text = btn.text, variant = btn.variant, flexGrow = 1,
                            onClick = function() GameUI.ShowPanel(btn.panel) end,
                        })
                    end
                    table.insert(rows, UI.Panel {
                        flexDirection = "row",
                        width = "100%",
                        gap = 4,
                        children = rowChildren,
                    })
                end

                -- 按钮内容区（默认折叠隐藏，自动适应高度）
                local btnContent = UI.Panel {
                    width = "100%",
                    flexDirection = "column",
                    gap = 4,
                    children = rows,
                }
                btnContent:SetVisible(false)

                -- 折叠/展开切换按钮
                local expanded = false
                local toggleBtn = UI.Button {
                    text = "展开功能 ▼",
                    variant = "outline",
                    width = "100%",
                    height = 28,
                    onClick = function(self)
                        expanded = not expanded
                        btnContent:SetVisible(expanded)
                        self:SetText(expanded and "收起功能 ▲" or "展开功能 ▼")
                    end,
                }

                return UI.Panel {
                    width = "100%",
                    flexDirection = "column",
                    gap = 4,
                    children = { toggleBtn, btnContent },
                }
            end)(),
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
        -- 自动回退到有效地图
        local fallbackMap = nil
        local deployCfg = (DataManager.gameConfig or {})["deploy"]
        if deployCfg and deployCfg.target_map and deployCfg.target_map ~= "" and DataManager.maps[deployCfg.target_map] then
            fallbackMap = deployCfg.target_map
        end
        if not fallbackMap and DataManager.maps["新手村"] then
            fallbackMap = "新手村"
        end
        if not fallbackMap then
            for name, _ in pairs(DataManager.maps) do
                fallbackMap = name
                break
            end
        end
        if fallbackMap then
            print("[GameUI] 当前地图【" .. tostring(mapName) .. "】不存在，自动回退到【" .. fallbackMap .. "】")
            player.status.current_map = fallbackMap
            DataManager.SaveToCloud(DataManager.playerData)
            mapName = fallbackMap
            mapData = DataManager.GetMap(fallbackMap)
        end
        if not mapData then
            mapNameLabel_:SetText("【未知地图】")
            return
        end
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
            local mData = DataManager.monsters[mName]
            local mType = mData and mData.type or "普通怪"
            monstersLabel_:AddChild(UI.Button {
                text = "【" .. mName .. "】" .. mType,
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
    -- 死亡检测：血量为0时不允许战斗
    local player = DataManager.playerData
    if player and BigNum.lte(player.status.hp or "0", "0") then
        GameUI.ShowDeathDialog()
        return
    end
    if not CombatUI then
        CombatUI = require("UI.CombatUI")
    end
    CombatUI.Start(monsterName, mainContent_, function(result)
        -- 战斗结束回调
        if result == "defeat" then
            GameUI.ShowDeathDialog()
        end
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
    elseif panelType == "pet" then
        if not PetUI then PetUI = require("UI.PetUI") end
        PetUI.Render(mainContent_)
    elseif panelType == "battle_soul" then
        GameUI.RenderBattleSoulPanel()
    elseif panelType == "monster_guide" then
        if not MonsterGuideUI then MonsterGuideUI = require("UI.MonsterGuideUI") end
        MonsterGuideUI.Render(mainContent_)
    elseif panelType == "mailbox" then
        if not MailboxUI then MailboxUI = require("UI.MailboxUI") end
        MailboxUI.Render(mainContent_)
    elseif panelType == "giftpack" then
        GameUI.RenderGiftPackPanel()
    elseif panelType == "leaderboard" then
        GameUI.RenderLeaderboardPanel()
    elseif panelType == "chat" then
        GameUI.RenderChatPanel()
    elseif panelType == "teleport" then
        GameUI.RenderTeleportPanel()
    elseif panelType == "mount" then
        GameUI.RenderMountPanel()
    elseif panelType == "toggle_numformat" then
        NumFormat.ToggleMode()
        -- 持久化到玩家数据并保存云端
        if DataManager.playerData then
            DataManager.playerData.status.num_format_mode = NumFormat.mode
            DataManager.SaveToCloud(DataManager.playerData)
        end
        -- 重建整个GameUI以刷新按钮文字和数值显示
        if ShowGame then
            ShowGame()
        end
        -- 提示当前显示方式
        GameUI.AddLog("【系统】数值显示已切换为: " .. NumFormat.GetModeLabel() .. " 模式")
        return
    elseif panelType == "logout" then
        -- 退出登录：先保存当前数据到云端，再清除并返回登录界面
        local player = DataManager.playerData
        if player then
            DataManager.SaveToCloud(player)
        end
        DataManager.playerData = nil
        DataManager.currentAccount = nil
        DataManager.currentPassword = nil
        SwitchState("login")
        return
    end
end

--- 渲染战魂面板
function GameUI.RenderBattleSoulPanel()
    mainContent_:ClearChildren()

    local player = DataManager.playerData
    if not player then return end
    local s = player.status
    local soulLv = tonumber(s.battle_soul_level) or 0
    local soulExp = s.battle_soul_exp or "0"
    local needExp = DataManager.GetBattleSoulExpNeeded(soulLv)
    local bonus = DataManager.GetBattleSoulBonus(s.battle_soul_level)

    -- 经验进度百分比
    local expNum = tonumber(soulExp) or 0
    local needNum = tonumber(needExp) or 1
    local pct = math.min(100, math.floor(expNum / math.max(needNum, 1) * 100))

    mainContent_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "column",
        padding = 12,
        gap = 8,
        children = {
            UI.Label { text = "— 战魂 —", fontSize = 16, fontColor = { 200, 150, 255, 255 }, textAlign = "center" },
            UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 40, 80, 255 } },

            -- 等级
            UI.Panel {
                flexDirection = "row", width = "100%", justifyContent = "space-between",
                children = {
                    UI.Label { text = "战魂等级", fontSize = 14, fontColor = { 180, 160, 220, 255 } },
                    UI.Label { text = "Lv." .. soulLv, fontSize = 14, fontColor = { 220, 180, 255, 255 } },
                },
            },

            -- 经验进度
            UI.Panel {
                flexDirection = "column", width = "100%", gap = 4,
                children = {
                    UI.Panel {
                        flexDirection = "row", width = "100%", justifyContent = "space-between",
                        children = {
                            UI.Label { text = "战魂经验", fontSize = 13, fontColor = { 160, 160, 180, 255 } },
                            UI.Label { text = NumFormat.Short(soulExp) .. " / " .. NumFormat.Short(needExp) .. "  (" .. pct .. "%)", fontSize = 13, fontColor = { 200, 180, 255, 255 } },
                        },
                    },
                    -- 进度条
                    UI.Panel {
                        width = "100%", height = 8, backgroundColor = { 40, 30, 60, 255 }, borderRadius = 4,
                        children = {
                            UI.Panel {
                                width = pct .. "%", height = "100%",
                                backgroundColor = { 160, 100, 255, 255 }, borderRadius = 4,
                            },
                        },
                    },
                },
            },

            UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 40, 80, 255 } },

            -- 属性加成标题
            UI.Label { text = "战魂属性加成", fontSize = 14, fontColor = { 150, 255, 200, 255 }, textAlign = "center" },

            -- 属性详情
            UI.Panel {
                flexDirection = "column", width = "100%", gap = 4,
                padding = 8, backgroundColor = { 35, 30, 55, 200 }, borderRadius = 6,
                children = {
                    UI.Panel {
                        flexDirection = "row", width = "100%", justifyContent = "space-between",
                        children = {
                            UI.Label { text = "攻击加成", fontSize = 13, fontColor = { 160, 160, 180, 255 } },
                            UI.Label { text = "+" .. NumFormat.Short(bonus.atk), fontSize = 13, fontColor = { 255, 150, 150, 255 } },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row", width = "100%", justifyContent = "space-between",
                        children = {
                            UI.Label { text = "防御加成", fontSize = 13, fontColor = { 160, 160, 180, 255 } },
                            UI.Label { text = "+" .. NumFormat.Short(bonus.def), fontSize = 13, fontColor = { 150, 200, 255, 255 } },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row", width = "100%", justifyContent = "space-between",
                        children = {
                            UI.Label { text = "生命上限加成", fontSize = 13, fontColor = { 160, 160, 180, 255 } },
                            UI.Label { text = "+" .. NumFormat.Short(bonus.max_hp), fontSize = 13, fontColor = { 150, 255, 150, 255 } },
                        },
                    },
                },
            },

            UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 40, 80, 255 } },

            -- 下一级预览
            UI.Label {
                text = "下一级(Lv." .. (soulLv + 1) .. ")属性：攻+" .. tostring((soulLv + 1) * (tonumber(DataManager.battleSoulConfig.level_bonus.atk) or 5)) ..
                    " 防+" .. tostring((soulLv + 1) * (tonumber(DataManager.battleSoulConfig.level_bonus.def) or 3)) ..
                    " 生命上限+" .. tostring((soulLv + 1) * (tonumber(DataManager.battleSoulConfig.level_bonus.max_hp) or 20)),
                fontSize = 11, fontColor = { 180, 180, 200, 255 }, textAlign = "center",
            },
            UI.Label {
                text = "击杀怪物自动获取战魂经验", fontSize = 10, fontColor = { 140, 140, 160, 255 }, textAlign = "center",
            },
        },
    })
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
-- 默认排行榜Tab（当管理后台未配置时使用）
local DEFAULT_LEADERBOARD_TABS = {
    { name = "等级", source = "等级" },
    { name = "攻击", source = "攻击力" },
    { name = "防御", source = "防御力" },
    { name = "生命", source = "生命上限" },
    { name = "金币", source = "金币" },
}

--- 动态获取排行榜Tab列表（优先读取管理后台配置）
local function GetLeaderboardTabs()
    local tabs = {}
    -- 从管理后台配置的排行榜中读取
    if DataManager.leaderboards then
        for _, board in pairs(DataManager.leaderboards) do
            table.insert(tabs, { name = board.name, source = board.source })
        end
    end
    -- 如果管理后台没有配置任何排行榜，使用默认值
    if #tabs == 0 then
        return DEFAULT_LEADERBOARD_TABS
    end
    return tabs
end

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

    -- 重置延迟加载标记，确保每次打开都从云端拉取最新管理员配置
    DataManager.ResetLazyData()
    -- 加载排行榜配置+排名数据，再构建UI
    DataManager.LoadLazyData(function()
        -- 标签按钮行（动态获取）
        local lbTabs = GetLeaderboardTabs()
        local tabChildren = {}
        for i, tab in ipairs(lbTabs) do
            table.insert(tabChildren, UI.Button {
                text = tab.name,
                variant = "secondary",
                flexGrow = 1,
                marginRight = (i < #lbTabs) and 4 or 0,
                onClick = function()
                    -- 每次点击tab都重新同步数据并从云端刷新
                    DataManager.SyncLeaderboardScores(function()
                        GameUI.ShowLeaderboardDetail(tab.source)
                    end)
                end,
            })
        end

        mainContent_:AddChild(UI.Panel {
            flexDirection = "row",
            width = "100%",
            paddingLeft = 8, paddingRight = 8,
            marginBottom = 8,
            flexWrap = "wrap",
            gap = 4,
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

        -- 先同步当前玩家分数，再显示第一个排行榜
        DataManager.SyncLeaderboardScores(function()
            GameUI.ShowLeaderboardDetail(lbTabs[1].source)
        end)
    end)
end

--- 当前排行榜选中的数据源（用于自动刷新）
GameUI.currentLeaderboardSource = nil

--- 显示某个排行榜详情
---@param source string 数据来源字段名（等级/攻击力/防御力/生命上限/金币）
function GameUI.ShowLeaderboardDetail(source)
    GameUI.currentLeaderboardSource = source
    local existing = mainContent_:FindById("lb_content")
    if not existing then return end
    existing:ClearChildren()

    -- 从本地排行数据排序（显示前20名）
    local rankedList = DataManager.GetRankedList(source, 20)

    -- 标题行
    existing:AddChild(UI.Label {
        text = "排名 / 玩家 / 数值",
        fontSize = 11,
        fontColor = { 200, 170, 100, 255 },
        marginBottom = 4,
        paddingLeft = 4,
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

    -- 排行榜最多20条，直接循环渲染，长数值手动拆行
    local LINE_CHARS = 22  -- 每行最多字符数
    for i, data in ipairs(rankedList) do
        local rankColor = (i <= 3) and { 255, 215, 0, 255 } or { 200, 200, 220, 255 }
        local row = UI.Panel {
            width = "100%",
            flexDirection = "column",
            paddingLeft = 6, paddingRight = 6,
            paddingTop = 4, paddingBottom = 4,
            marginBottom = 4,
            borderRadius = 4,
            backgroundColor = (i % 2 == 0) and { 40, 35, 60, 150 } or { 30, 25, 50, 100 },
        }
        row:AddChild(UI.Label { text = "#" .. i .. "  " .. (data.name or ""), fontSize = 12, fontColor = rankColor, width = "100%" })

        -- 将长数值拆成多行
        local valueStr = NumFormat.Short(data.value)
        local pos = 1
        local len = utf8.len(valueStr) or #valueStr
        while pos <= len do
            local endPos = math.min(pos + LINE_CHARS - 1, len)
            local line = string.sub(valueStr, utf8.offset(valueStr, pos), (utf8.offset(valueStr, endPos + 1) or (#valueStr + 1)) - 1)
            row:AddChild(UI.Label { text = line, fontSize = 10, fontColor = { 100, 255, 200, 255 }, width = "100%" })
            pos = endPos + 1
        end

        existing:AddChild(row)
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

    -- 消息列表区域（VirtualList 容器）
    chatListPanel_ = UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        flexBasis = 0,
        overflow = "hidden",
        backgroundColor = { 20, 15, 40, 180 },
        borderRadius = 4,
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

local CHAT_ITEM_HEIGHT = 48
local CHAT_ITEM_GAP = 2

function GameUI.RefreshChatList()
    if not chatListPanel_ then return end
    chatListPanel_:ClearChildren()

    local messages = DataManager.chatMessages
    if not messages or #messages == 0 then
        chatListPanel_:AddChild(UI.Label {
            text = "暂无消息，发一条吧~",
            fontSize = 12,
            fontColor = { 150, 150, 170, 255 },
            marginTop = 8,
            marginLeft = 6,
        })
        return
    end

    local vList = UI.VirtualList {
        width = "100%",
        height = "100%",
        viewportHeight = 300,
        data = messages,
        itemHeight = CHAT_ITEM_HEIGHT,
        itemGap = CHAT_ITEM_GAP,
        poolBuffer = 5,
        createItem = function()
            local row = UI.Panel {
                width = "100%",
                height = CHAT_ITEM_HEIGHT,
                flexDirection = "column",
                justifyContent = "center",
                paddingTop = 3, paddingBottom = 3,
                paddingLeft = 6, paddingRight = 6,
            }
            local headerRow = UI.Panel {
                flexDirection = "row",
                width = "100%",
            }
            local senderLabel = UI.Label {
                id = "sender",
                text = "",
                fontSize = 11,
                fontColor = { 100, 200, 255, 255 },
                marginRight = 8,
            }
            local timeLabel = UI.Label {
                id = "time",
                text = "",
                fontSize = 10,
                fontColor = { 120, 120, 140, 255 },
            }
            headerRow:AddChild(senderLabel)
            headerRow:AddChild(timeLabel)
            row:AddChild(headerRow)

            local contentLabel = UI.Label {
                id = "content",
                text = "",
                fontSize = 12,
                fontColor = { 220, 220, 240, 255 },
                marginTop = 2,
                maxLines = 1,
            }
            row:AddChild(contentLabel)

            row._senderLabel = senderLabel
            row._timeLabel = timeLabel
            row._contentLabel = contentLabel
            return row
        end,
        bindItem = function(widget, data, index)
            widget._senderLabel:SetText(data.sender or "")
            widget._timeLabel:SetText(data.time or "")
            widget._contentLabel:SetText(data.content or "")
            widget.props.backgroundColor = (index % 2 == 0) and { 40, 35, 60, 100 } or { 0, 0, 0, 0 }
        end,
    }
    chatListPanel_:AddChild(vList)
end

local LOG_ITEM_HEIGHT = 40
local LOG_ITEM_GAP = 2
--- 获取某个传送地图需要的物品信息
---@return string itemName, string itemCount, boolean isFree
local function GetTeleportCost(tp)
    local tc = DataManager.teleportMaps
    if tp.free then
        return "", "0", true
    end
    if tp.custom_item and tp.custom_item ~= "" then
        return tp.custom_item, tp.custom_item_count or "1", false
    end
    if tc.default_item and tc.default_item ~= "" then
        return tc.default_item, tc.default_item_count or "1", false
    end
    return "", "0", true  -- 无默认物品 = 免费
end

--- 检查玩家是否有足够物品
---@return boolean hasEnough, string currentCount
local function HasTeleportItem(player, itemName, needCount)
    if itemName == "" then return true, "0" end
    for _, item in ipairs(player.bag or {}) do
        if item.name == itemName then
            return BigNum.gte(item.count or "0", needCount), item.count or "0"
        end
    end
    return false, "0"
end

--- 扣除传送物品
local function ConsumeTeleportItem(player, itemName, needCount)
    if itemName == "" then return end
    for i, item in ipairs(player.bag or {}) do
        if item.name == itemName then
            item.count = BigNum.sub(item.count or "0", needCount)
            if BigNum.lte(item.count, "0") then
                table.remove(player.bag, i)
            end
            return
        end
    end
end

--- 渲染传送面板
function GameUI.RenderTeleportPanel()
    if not mainContent_ then return end

    local player = DataManager.playerData
    if not player then return end

    local tc = DataManager.teleportMaps or { default_item = "", default_item_count = "1", maps = {} }
    local teleportList = tc.maps or {}

    if #teleportList == 0 then
        mainContent_:AddChild(UI.Panel {
            width = "100%", padding = 16, justifyContent = "center", alignItems = "center",
            children = {
                UI.Label { text = "暂无可传送地图", fontSize = 14, fontColor = { 180, 180, 180, 255 } },
            }
        })
        return
    end

    -- 标题
    mainContent_:AddChild(UI.Label {
        text = "— 传送 —",
        fontSize = 16,
        fontColor = { 100, 200, 255, 255 },
        textAlign = "center",
        width = "100%",
        marginBottom = 8,
    })

    local playerLevel = player.status.level or "1"
    local currentMap = player.status.current_map or ""

    -- 传送目的地列表
    for i, tp in ipairs(teleportList) do
        local mapName = tp.name or ""
        local levelReq = tp.level_req or "0"
        local levelReqNum = tonumber(levelReq) or 0
        local isCurrent = (mapName == currentMap)
        local levelOk = BigNum.gte(playerLevel, levelReq)
        local costItem, costCount, isFree = GetTeleportCost(tp)
        local hasItem, ownedCount = HasTeleportItem(player, costItem, costCount)

        -- 行容器
        local rowChildren = {}

        -- 序号 + 地图名
        local nameColor = isCurrent and { 100, 255, 100, 255 } or { 220, 220, 240, 255 }
        table.insert(rowChildren, UI.Label {
            text = i .. ". " .. mapName .. (isCurrent and " (当前)" or ""),
            fontSize = 13,
            fontColor = nameColor,
            flexShrink = 1,
            flexGrow = 1,
        })

        -- 物品消耗提示
        if not isFree and not isCurrent then
            local costColor = hasItem and { 180, 180, 100, 255 } or { 255, 100, 100, 255 }
            table.insert(rowChildren, UI.Label {
                text = costItem .. "x" .. costCount,
                fontSize = 10,
                fontColor = costColor,
                marginRight = 4,
            })
        elseif isFree and not isCurrent then
            table.insert(rowChildren, UI.Label {
                text = "免费",
                fontSize = 10,
                fontColor = { 100, 200, 100, 255 },
                marginRight = 4,
            })
        end

        -- 等级需求提示
        if levelReqNum > 0 then
            table.insert(rowChildren, UI.Label {
                text = "Lv." .. levelReq,
                fontSize = 11,
                fontColor = levelOk and { 150, 150, 150, 255 } or { 255, 100, 100, 255 },
                marginRight = 4,
            })
        end

        -- 传送按钮
        if isCurrent then
            table.insert(rowChildren, UI.Button {
                text = "当前",
                variant = "secondary",
                height = 26,
                disabled = true,
            })
        elseif not levelOk then
            table.insert(rowChildren, UI.Button {
                text = "等级不足",
                variant = "danger",
                height = 26,
                disabled = true,
            })
        elseif not isFree and not hasItem then
            table.insert(rowChildren, UI.Button {
                text = "物品不足",
                variant = "danger",
                height = 26,
                disabled = true,
            })
        else
            local targetName = mapName
            local cItem, cCount, cFree = costItem, costCount, isFree
            table.insert(rowChildren, UI.Button {
                text = "传送",
                variant = "primary",
                height = 26,
                onClick = function()
                    GameUI.DoTeleport(targetName, cItem, cCount, cFree)
                end,
            })
        end

        mainContent_:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = 8, paddingRight = 8,
            paddingTop = 4, paddingBottom = 4,
            backgroundColor = (i % 2 == 0) and { 30, 30, 50, 200 } or { 20, 20, 40, 200 },
            gap = 4,
            children = rowChildren,
        })
    end
end

--- 执行传送
---@param targetMap string
---@param costItem string
---@param costCount string
---@param isFree boolean
function GameUI.DoTeleport(targetMap, costItem, costCount, isFree)
    local player = DataManager.playerData
    if not player then return end

    local currentMap = player.status.current_map or ""
    if targetMap == currentMap then
        GameUI.AddLog("你已在【" .. targetMap .. "】")
        return
    end

    -- 等级二次校验
    local targetData = DataManager.GetMap(targetMap)
    if targetData then
        local levelReq = targetData.level_req or "0"
        if BigNum.lt(player.status.level or "1", levelReq) then
            GameUI.AddLog("等级不足！需要等级 " .. levelReq .. " 才能传送到 " .. targetMap)
            return
        end
    end

    -- 物品校验和扣除
    if not isFree and costItem ~= "" then
        local hasItem = HasTeleportItem(player, costItem, costCount)
        if not hasItem then
            GameUI.AddLog("物品不足！需要 " .. costItem .. " x" .. costCount)
            return
        end
        ConsumeTeleportItem(player, costItem, costCount)
        GameUI.AddLog("消耗 " .. costItem .. " x" .. costCount)
    end

    player.status.current_map = targetMap
    GameUI.AddLog("传送成功！你来到了【" .. targetMap .. "】")
    GameUI.RefreshMap()
    DataManager.SaveToCloud(player)

    -- 刷新传送面板显示当前位置
    GameUI.ShowPanel("teleport")
end

--- 渲染坐骑面板(绑定/解绑单坐骑 + 独立传送)
--- 坐骑绑定时加属性/倍率到玩家
local function ApplyMountBonuses(player, mountData)
    if not mountData then return end
    local BigNum = require("Utils.BigNum")
    local atkAdd = mountData.atk or "0"
    local defAdd = mountData.def or "0"
    local hpAdd  = mountData.hp or "0"
    if atkAdd ~= "0" then
        player.status.atk = BigNum.add(player.status.atk or "5", atkAdd)
    end
    if defAdd ~= "0" then
        player.status.def = BigNum.add(player.status.def or "3", defAdd)
    end
    if hpAdd ~= "0" then
        player.status.max_hp = BigNum.add(player.status.max_hp or "100", hpAdd)
        player.status.hp = BigNum.add(player.status.hp or "100", hpAdd)
    end
    -- 永久倍率存储到 player.mounts 中供战斗系统读取
    local expR = tonumber(mountData.exp_rate) or 0
    local goldR = tonumber(mountData.gold_rate) or 0
    player.mounts.exp_rate = expR
    player.mounts.gold_rate = goldR
end

--- 坐骑解绑时减属性/倍率
local function RemoveMountBonuses(player, mountData)
    if not mountData then return end
    local BigNum = require("Utils.BigNum")
    local atkSub = mountData.atk or "0"
    local defSub = mountData.def or "0"
    local hpSub  = mountData.hp or "0"
    if atkSub ~= "0" then
        player.status.atk = BigNum.max("0", BigNum.sub(player.status.atk or "5", atkSub))
    end
    if defSub ~= "0" then
        player.status.def = BigNum.max("0", BigNum.sub(player.status.def or "3", defSub))
    end
    if hpSub ~= "0" then
        player.status.max_hp = BigNum.max("1", BigNum.sub(player.status.max_hp or "100", hpSub))
        -- 当前HP不超过新上限
        if BigNum.gt(player.status.hp or "0", player.status.max_hp) then
            player.status.hp = player.status.max_hp
        end
    end
    -- 清除坐骑倍率
    player.mounts.exp_rate = 0
    player.mounts.gold_rate = 0
end

--- 显示坐骑提示弹窗
local function ShowMountTip(msg)
    ---@type Widget
    local dialog = nil
    dialog = UI.Panel {
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 140 },
        children = {
            UI.Panel {
                width = "75%", maxWidth = 280, padding = 16,
                backgroundColor = { 30, 25, 50, 245 }, borderRadius = 10,
                borderWidth = 1, borderColor = { 100, 80, 160, 200 },
                flexDirection = "column", alignItems = "center", gap = 12,
                onClick = function() end,
                children = {
                    UI.Label { text = msg, fontSize = 14, fontColor = {255,200,100,255}, textAlign = "center", whiteSpace = "normal" },
                    UI.Button { text = "确 定", variant = "default", onClick = function() dialog:Remove() end },
                },
            },
        },
    }
    if GameUI.rootPanel then
        GameUI.rootPanel:AddChild(dialog)
    end
end

function GameUI.RenderMountPanel()
    if not mainContent_ then return end
    mainContent_:ClearChildren()

    local player = DataManager.playerData
    if not player then return end

    -- 玩家坐骑数据: player.mounts = { bound = "坐骑名" or "", exp_rate = 0, gold_rate = 0 }
    if not player.mounts then player.mounts = { bound = "", exp_rate = 0, gold_rate = 0 } end
    local boundName = player.mounts.bound or ""
    local boundMount = boundName ~= "" and DataManager.mounts[boundName] or nil

    -- 兼容修复：已绑定坐骑但倍率/属性未应用（旧存档升级）
    if boundMount and (tonumber(player.mounts.exp_rate) or 0) == 0 and (tonumber(player.mounts.gold_rate) or 0) == 0 then
        local m = boundMount
        if (m.exp_rate ~= "0" and m.exp_rate ~= "") or (m.gold_rate ~= "0" and m.gold_rate ~= "") then
            -- 自动补全倍率
            player.mounts.exp_rate = tonumber(m.exp_rate) or 0
            player.mounts.gold_rate = tonumber(m.gold_rate) or 0
            DataManager.SaveToCloud(player)
        end
    end

    local children = {}
    children[#children + 1] = UI.Label {
        text = "— 坐骑 —", fontSize = 16, fontColor = {200,170,100,255}, textAlign = "center", marginBottom = 8,
    }

    -- 当前绑定的坐骑
    if boundMount then
        local m = boundMount
        local info = boundName .. " [" .. (m.type or "不可传送") .. "]"
        if m.atk ~= "0" then info = info .. " 攻+" .. m.atk end
        if m.def ~= "0" then info = info .. " 防+" .. m.def end
        if m.hp ~= "0" then info = info .. " 命+" .. m.hp end
        if m.exp_rate ~= "0" then info = info .. " 经验×" .. m.exp_rate end
        if m.gold_rate ~= "0" then info = info .. " 金币×" .. m.gold_rate end
        children[#children + 1] = UI.Panel {
            width = "100%", flexDirection = "column", padding = 8, borderRadius = 6,
            backgroundColor = {30,50,40,200}, marginBottom = 8, gap = 4,
            children = {
                UI.Label { text = "当前坐骑", fontSize = 11, fontColor = {140,140,160,255} },
                UI.Label { text = info, fontSize = 13, fontColor = {100,255,200,255}, whiteSpace = "normal" },
                UI.Panel { flexDirection = "row", gap = 8, marginTop = 4, children = {
                    UI.Button { text = "解绑(回背包)", fontSize = 10, height = 28, variant = "danger",
                        onClick = function()
                            -- 解绑:减去坐骑属性/倍率
                            RemoveMountBonuses(player, boundMount)
                            -- 坐骑回背包
                            local bag = player.bag or {}
                            local found = false
                            for _, item in ipairs(bag) do
                                if item.name == boundName then item.count = (tonumber(item.count) or 0) + 1; found = true; break end
                            end
                            if not found then bag[#bag + 1] = { name = boundName, count = 1 } end
                            player.bag = bag
                            player.mounts.bound = ""
                            DataManager.SaveToCloud(player)
                            GameUI.AddLog("解绑坐骑【" .. boundName .. "】，属性已移除")
                            GameUI.ShowPanel("mount")
                        end },
                }},
            },
        }

        -- 传送功能(按坐骑类型)
        if m.type == "全图传送" or (m.type == "部分传送" and #(m.maps or {}) > 0) then
            children[#children + 1] = UI.Label { text = "— 坐骑传送 —", fontSize = 13, fontColor = {200,170,100,255}, textAlign = "center", marginTop = 4, marginBottom = 4 }
            local curMap = player.status.current_map or ""
            local mapList = {}
            if m.type == "全图传送" then
                for mapName in pairs(DataManager.maps) do
                    if mapName ~= curMap then mapList[#mapList + 1] = mapName end
                end
            else
                for _, mapName in ipairs(m.maps or {}) do
                    if mapName ~= curMap and DataManager.maps[mapName] then mapList[#mapList + 1] = mapName end
                end
            end
            table.sort(mapList)
            if #mapList > 0 then
                local MOUNT_MAP_ITEM_H = 32
                local MOUNT_MAP_ITEM_GAP = 2
                local vList = UI.VirtualList {
                    width = "100%",
                    height = 200,
                    viewportHeight = 200,
                    data = mapList,
                    itemHeight = MOUNT_MAP_ITEM_H,
                    itemGap = MOUNT_MAP_ITEM_GAP,
                    poolBuffer = 4,
                    createItem = function()
                        local row = UI.Panel {
                            width = "100%", height = MOUNT_MAP_ITEM_H,
                            flexDirection = "row", alignItems = "center", gap = 4,
                            paddingLeft = 6, paddingRight = 6,
                        }
                        local nameLabel = UI.Label { id = "mapName", text = "", fontSize = 11, fontColor = {180,180,200,255}, flexGrow = 1 }
                        local tpBtn = UI.Button { id = "tpBtn", text = "传送", fontSize = 9, width = 46, height = 22, variant = "primary" }
                        row:AddChild(nameLabel)
                        row:AddChild(tpBtn)
                        row._nameLabel = nameLabel
                        row._tpBtn = tpBtn
                        return row
                    end,
                    bindItem = function(widget, mapName, index)
                        widget._nameLabel:SetText(mapName)
                        widget._tpBtn.props.onClick = function()
                            player.status.current_map = mapName
                            DataManager.SaveToCloud(player)
                            GameUI.AddLog("坐骑【" .. boundName .. "】传送至【" .. mapName .. "】")
                            if ShowGame then ShowGame() end
                        end
                        widget.props.backgroundColor = (index % 2 == 0) and {30,30,50,120} or {0,0,0,0}
                    end,
                }
                children[#children + 1] = vList
            else
                children[#children + 1] = UI.Label { text = "(当前已在唯一可传送地图)", fontSize = 10, fontColor = {120,120,140,255} }
            end
        elseif m.type == "不可传送" then
            children[#children + 1] = UI.Label { text = "此坐骑不可传送", fontSize = 11, fontColor = {150,150,150,255}, marginTop = 6 }
        end
    else
        children[#children + 1] = UI.Label {
            text = "未绑定坐骑", fontSize = 13, fontColor = {150,150,170,255}, marginBottom = 6,
        }
        children[#children + 1] = UI.Label {
            text = "从背包「坐骑类」中选择坐骑使用即可绑定", fontSize = 11, fontColor = {120,120,140,255},
            whiteSpace = "normal",
        }
    end

    -- 背包中可绑定的坐骑列表(快捷入口)
    local bagMounts = {}
    for _, item in ipairs(player.bag or {}) do
        if DataManager.mounts[item.name] and (tonumber(item.count) or 0) > 0 then
            bagMounts[#bagMounts + 1] = item.name
        end
    end
    if #bagMounts > 0 then
        children[#children + 1] = UI.Label { text = "— 背包中的坐骑 —", fontSize = 12, fontColor = {160,160,180,255}, marginTop = 10, marginBottom = 4 }
        table.sort(bagMounts)
        for _, name in ipairs(bagMounts) do
            local m = DataManager.mounts[name]
            local typeColor = m.type == "全图传送" and {100,255,150,255} or (m.type == "部分传送" and {100,180,255,255} or {150,150,150,255})
            children[#children + 1] = UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center", gap = 4, marginBottom = 2,
                padding = 4, borderRadius = 4, backgroundColor = {30,30,45,180},
                children = {
                    UI.Label { text = name, fontSize = 11, fontColor = {200,200,220,255}, flexGrow = 1 },
                    UI.Label { text = tostring(m.type or ""), fontSize = 9, fontColor = typeColor },
                    UI.Button { text = "绑定", fontSize = 9, width = 42, height = 22, variant = "primary",
                        onClick = function()
                            -- 限制：必须先解绑当前坐骑
                            if boundName ~= "" then
                                ShowMountTip("请先解绑当前坐骑【" .. boundName .. "】后再绑定新坐骑")
                                return
                            end
                            -- 从背包扣除新坐骑
                            for i, item in ipairs(player.bag) do
                                if item.name == name then
                                    item.count = (tonumber(item.count) or 0) - 1
                                    if item.count <= 0 then table.remove(player.bag, i) end
                                    break
                                end
                            end
                            player.mounts.bound = name
                            -- 绑定:加属性/倍率
                            ApplyMountBonuses(player, m)
                            DataManager.SaveToCloud(player)
                            GameUI.AddLog("绑定坐骑【" .. name .. "】，属性已生效")
                            GameUI.ShowPanel("mount")
                        end },
                },
            }
        end
    end

    mainContent_:AddChild(UI.ScrollView {
        width = "100%", height = "100%",
        children = { UI.Panel { width = "100%", flexDirection = "column", padding = 8, children = children } },
    })
end



local logVirtualList_ = nil

--- 添加游戏日志（一体式弹窗显示）
---@param msg string
function GameUI.AddLog(msg)
    -- 追加消息到队列
    table.insert(logTexts_, msg)
    if #logTexts_ > LOG_MAX then
        table.remove(logTexts_, 1)
    end

    -- 如果弹窗已打开，更新 VirtualList 数据
    if logDialog_ and logVirtualList_ then
        logVirtualList_:SetData(logTexts_)
    else
        -- 弹窗未打开，自动弹出
        GameUI.ShowLogDialog()
    end

    print("[Log] " .. msg)
end

--- 显示日志弹窗（模态，手动关闭）
function GameUI.ShowLogDialog()
    -- 如果已打开，不重复创建
    if logDialog_ then return end

    -- VirtualList 容器
    local listContainer = UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        flexBasis = 0,
        overflow = "hidden",
    }

    logVirtualList_ = UI.VirtualList {
        width = "100%",
        height = "100%",
        viewportHeight = 280,
        data = logTexts_,
        itemHeight = LOG_ITEM_HEIGHT,
        itemGap = LOG_ITEM_GAP,
        poolBuffer = 5,
        createItem = function()
            local row = UI.Panel {
                width = "100%",
                height = LOG_ITEM_HEIGHT,
                justifyContent = "center",
                paddingLeft = 4,
            }
            local label = UI.Label {
                id = "msg",
                text = "",
                fontSize = 12,
                fontColor = { 220, 220, 240, 255 },
                maxLines = 2,
                whiteSpace = "normal",
                width = "100%",
            }
            row:AddChild(label)
            row._label = label
            return row
        end,
        bindItem = function(widget, data, index)
            widget._label:SetText("> " .. (data or ""))
        end,
    }
    listContainer:AddChild(logVirtualList_)

    logDialog_ = UI.Panel {
        id = "logDialogOverlay",
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        onClick = function()
            GameUI.HideLogDialog()
        end,
        children = {
            UI.Panel {
                width = "85%",
                maxWidth = 340,
                height = "70%",
                maxHeight = 420,
                padding = 14,
                backgroundColor = { 25, 20, 45, 245 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 100, 80, 160, 200 },
                flexDirection = "column",
                alignItems = "center",
                gap = 8,
                onClick = function() end,  -- 阻止穿透
                children = {
                    -- 标题
                    UI.Label { text = "游戏日志", fontSize = 16, fontColor = { 200, 180, 255, 255 }, textAlign = "center" },
                    -- 分隔线
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 60, 120, 200 } },
                    -- VirtualList 消息区域
                    listContainer,
                    -- 关闭按钮
                    UI.Button {
                        text = "关  闭",
                        variant = "secondary",
                        width = 100,
                        height = 34,
                        marginTop = 6,
                        onClick = function()
                            GameUI.HideLogDialog()
                        end,
                    },
                },
            },
        },
    }

    -- 添加到根面板
    local root = GameUI.rootPanel
    if root then
        local old = root:FindById("logDialogOverlay")
        if old then old:Remove() end
        root:AddChild(logDialog_)
    end
end

--- 关闭日志弹窗（同时清空日志）
function GameUI.HideLogDialog()
    if logDialog_ then
        logDialog_:Remove()
        logDialog_ = nil
        logVirtualList_ = nil
    end
    logTexts_ = {}
end

-- 死亡弹框引用
local deathDialog_ = nil

--- 显示死亡弹框（道具复活 / 回新手村复活）
function GameUI.ShowDeathDialog()
    if deathDialog_ then return end

    local player = DataManager.playerData
    if not player then return end

    -- 检查背包是否有复活类道具
    local reviveItemIndex = nil
    local reviveItemName = ""
    for i, item in ipairs(player.bag or {}) do
        local itemData = DataManager.GetItem(item.name)
        if itemData and itemData.type and itemData.type:find("复活") then
            if BigNum.gt(item.count or "0", "0") then
                reviveItemIndex = i
                reviveItemName = item.name
                break
            end
        end
    end

    -- 道具复活按钮文本
    local reviveBtnText = reviveItemIndex and ("使用道具复活 (" .. reviveItemName .. ")") or "使用道具复活 (无复活道具)"

    deathDialog_ = UI.Panel {
        id = "deathDialogOverlay",
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        children = {
            UI.Panel {
                width = "80%",
                maxWidth = 320,
                padding = 20,
                backgroundColor = { 40, 15, 15, 250 },
                borderRadius = 12,
                borderWidth = 2,
                borderColor = { 180, 50, 50, 220 },
                flexDirection = "column",
                alignItems = "center",
                gap = 14,
                onClick = function() end,  -- 阻止穿透
                children = {
                    -- 标题
                    UI.Label {
                        text = "你已死亡",
                        fontSize = 20,
                        fontColor = { 255, 80, 80, 255 },
                        textAlign = "center",
                    },
                    -- 分隔线
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 150, 50, 50, 180 } },
                    -- 提示
                    UI.Label {
                        text = "请选择复活方式：",
                        fontSize = 14,
                        fontColor = { 220, 200, 200, 255 },
                        textAlign = "center",
                    },
                    -- 道具复活按钮
                    UI.Button {
                        text = reviveBtnText,
                        width = "100%",
                        variant = reviveItemIndex and "primary" or "default",
                        disabled = not reviveItemIndex,
                        onClick = function()
                            GameUI.ReviveWithItem(reviveItemIndex)
                        end,
                    },
                    -- 回新手村复活按钮
                    UI.Button {
                        text = "回新手村复活",
                        width = "100%",
                        variant = "default",
                        onClick = function()
                            GameUI.ReviveAtStartVillage()
                        end,
                    },
                },
            },
        },
    }

    local root = GameUI.rootPanel
    if root then
        root:AddChild(deathDialog_)
    end
end

--- 隐藏死亡弹框
function GameUI.HideDeathDialog()
    if deathDialog_ then
        deathDialog_:Remove()
        deathDialog_ = nil
    end
end

--- 计算当前最大生命值（含装备+buff+境界+战魂加成）
---@return string maxHp 大数字符串
function GameUI.CalcMaxHp()
    local player = DataManager.playerData
    if not player then return "100" end

    if not StatusUI then StatusUI = require("UI.StatusUI") end
    if not BagUI then BagUI = require("UI.BagUI") end

    local _, _, eHp = StatusUI.GetEquipBonus()
    local bHp = BagUI.GetBuffValue(player, "生命上限")
    local _, _, rHp = DataManager.GetRealmBonus()
    local soulBonus = DataManager.GetBattleSoulBonus(player.status.battle_soul_level)
    local maxHp = BigNum.add(BigNum.add(BigNum.add(BigNum.add(player.status.max_hp or "100", tostring(eHp)), tostring(bHp)), rHp), soulBonus.max_hp)
    return maxHp
end

--- 使用道具复活
---@param itemIndex number|nil
function GameUI.ReviveWithItem(itemIndex)
    local player = DataManager.playerData
    if not player then return end

    if not itemIndex then
        GameUI.AddLog("没有复活道具可使用")
        return
    end

    -- 再次确认玩家已死亡
    if not BigNum.lte(player.status.hp or "0", "0") then
        GameUI.AddLog("当前未处于死亡状态")
        GameUI.HideDeathDialog()
        return
    end

    local item = player.bag[itemIndex]
    if not item then
        GameUI.AddLog("道具不存在")
        return
    end

    -- 恢复满血
    local maxHp = GameUI.CalcMaxHp()
    player.status.hp = maxHp

    -- 消耗道具
    item.count = BigNum.sub(item.count or "1", "1")
    if BigNum.lte(item.count, "0") then
        table.remove(player.bag, itemIndex)
    end

    DataManager.SaveToCloud(player)
    GameUI.AddLog("使用 " .. item.name .. " 复活成功，生命恢复满")
    GameUI.HideDeathDialog()
    GameUI.RefreshMap()
end

--- 回新手村复活
function GameUI.ReviveAtStartVillage()
    local player = DataManager.playerData
    if not player then return end

    -- 恢复满血
    local maxHp = GameUI.CalcMaxHp()
    player.status.hp = maxHp

    -- 传送到新手村
    local startMap = DataManager.gameConfig["game"] and DataManager.gameConfig["game"]["start_map"] or "新手村"
    player.status.current_map = startMap

    DataManager.SaveToCloud(player)
    GameUI.AddLog("已传送至【" .. startMap .. "】，生命恢复满")
    GameUI.HideDeathDialog()
    GameUI.RefreshMap()
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

    local level = tonumber(player.status.level) or 1
    local exp = BigNum.new(player.status.exp or "0")
    local maxLevel = DataManager.GetMaxLevel()

    -- 已达到最高等级
    if level >= maxLevel then
        player.status.exp = tostring(exp)
        return
    end

    local needExp = DataManager.GetExpForLevel(tostring(level))

    -- 快速判断：经验不够升级则直接返回
    if BigNum.lt(exp, needExp) then
        player.status.exp = tostring(exp)
        return
    end

    -- === O(log n) 精确升级：闭合求和公式 + 二分搜索 ===
    -- 经验公式: base_exp * level^factor (factor为整数1/2/3)
    -- 闭合求和: GetTotalExpForRange 使用 Faulhaber 公式 O(1) 计算任意区间经验和
    -- 二分搜索: O(log(maxLevel)) 次闭合求和即可精确定位目标等级

    local startLevel = level

    -- 二分搜索：找到最大的 targetLevel 使得 totalExp(startLevel..targetLevel) <= exp
    local lo = startLevel + 1
    local hi = maxLevel

    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        local cost = DataManager.GetTotalExpForRange(startLevel, mid)
        if BigNum.gte(exp, cost) then
            lo = mid
        else
            hi = mid - 1
        end
    end

    -- lo 现在是能升到的最高等级
    local finalLevel = lo
    local totalCost = DataManager.GetTotalExpForRange(startLevel, finalLevel)

    -- 检查是否真的能升级（防御性判断）
    if BigNum.lt(exp, totalCost) then
        -- 回退一级
        finalLevel = finalLevel - 1
        if finalLevel <= startLevel then
            player.status.exp = tostring(exp)
            return
        end
        totalCost = DataManager.GetTotalExpForRange(startLevel, finalLevel)
    end

    -- 扣除经验
    local expRemaining = BigNum.sub(exp, totalCost)

    -- 没有升级
    if finalLevel <= startLevel then
        player.status.exp = tostring(expRemaining)
        return
    end

    if finalLevel > maxLevel then
        finalLevel = maxLevel
    end

    local levelsGained = finalLevel - startLevel
    local config = DataManager.gameConfig["level_up"] or {}

    -- 批量计算属性增量
    local hpPerLv = tonumber(config.hp_per_level) or 20
    local mpPerLv = tonumber(config.mp_per_level) or 10
    local atkPerLv = tonumber(config.atk_per_level) or 3
    local defPerLv = tonumber(config.def_per_level) or 2

    local totalHpAdd = tostring(hpPerLv * levelsGained)
    local totalMpAdd = tostring(mpPerLv * levelsGained)
    local totalAtkAdd = tostring(atkPerLv * levelsGained)
    local totalDefAdd = tostring(defPerLv * levelsGained)

    player.status.max_hp = BigNum.add(player.status.max_hp or "100", totalHpAdd)
    player.status.hp = player.status.max_hp
    player.status.max_mp = BigNum.add(player.status.max_mp or "50", totalMpAdd)
    player.status.mp = player.status.max_mp
    player.status.atk = BigNum.add(player.status.atk or "5", totalAtkAdd)
    player.status.def = BigNum.add(player.status.def or "3", totalDefAdd)

    player.status.level = tostring(finalLevel)
    player.status.exp = tostring(expRemaining)

    GameUI.AddLog("恭喜！等级提升至 " .. finalLevel .. "（连升 " .. levelsGained .. " 级）")
end

--- ESC 键处理
function GameUI.HandleEscape()
    -- 返回地图主界面
    GameUI.RefreshMap()
end

return GameUI
