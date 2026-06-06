---------------------------------------------------
-- CombatUI.lua - 战斗系统
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local IniParser = require("Utils.IniParser")

local CombatUI = {}

local parentRef_ = nil
local callback_ = nil
local combatLog_ = nil

-- 战斗状态
local monsterName_ = ""
local monsterHp_ = 0
local monsterMaxHp_ = 0
local monsterAtk_ = 0
local monsterDef_ = 0
local inCombat_ = false

--- 开始战斗
---@param monsterName string
---@param parent Widget
---@param onFinish function
function CombatUI.Start(monsterName, parent, onFinish)
    parentRef_ = parent
    callback_ = onFinish
    monsterName_ = monsterName
    inCombat_ = true

    local mData = DataManager.GetMonster(monsterName)
    if not mData then
        print("[CombatUI] 找不到怪物数据: " .. monsterName)
        return
    end

    monsterMaxHp_ = tonumber(mData.hp) or 50
    monsterHp_ = monsterMaxHp_
    monsterAtk_ = tonumber(mData.atk) or 5
    monsterDef_ = tonumber(mData.def) or 3

    CombatUI.Render()
end

--- 渲染战斗界面
function CombatUI.Render()
    if not parentRef_ then return end
    parentRef_:ClearChildren()

    local player = DataManager.playerData
    if not player then return end

    -- 计算玩家总属性（含装备加成）
    local StatusUI = require("UI.StatusUI")
    local eAtk, eDef, eHp = StatusUI.GetEquipBonus()
    local playerAtk = (tonumber(player.status.atk) or 5) + eAtk
    local playerDef = (tonumber(player.status.def) or 3) + eDef
    local playerHp = tonumber(player.status.hp) or 100
    local playerMaxHp = (tonumber(player.status.max_hp) or 100) + eHp

    -- 战斗日志
    combatLog_ = UI.Panel {
        id = "combatLog",
        width = "100%",
        flexDirection = "column",
        gap = 2,
        padding = 8,
        backgroundColor = { 20, 15, 35, 200 },
        borderRadius = 6,
        minHeight = 80,
    }

    parentRef_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "column",
        padding = 12,
        gap = 8,
        children = {
            UI.Label { text = "— 战斗 —", fontSize = 16, fontColor = { 255, 100, 100, 255 }, textAlign = "center" },

            -- 怪物信息
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                alignItems = "center",
                backgroundColor = { 40, 20, 20, 200 },
                borderRadius = 6,
                padding = 8,
                children = {
                    UI.Label { text = "【" .. monsterName_ .. "】", fontSize = 16, fontColor = { 255, 150, 150, 255 } },
                    UI.Label {
                        text = "HP: " .. monsterHp_ .. " / " .. monsterMaxHp_,
                        fontSize = 13,
                        fontColor = { 255, 100, 100, 255 },
                    },
                    UI.Label {
                        text = "攻:" .. monsterAtk_ .. "  防:" .. monsterDef_,
                        fontSize = 12,
                        fontColor = { 200, 150, 150, 255 },
                    },
                },
            },

            UI.Label { text = "VS", fontSize = 14, fontColor = { 200, 200, 200, 255 }, textAlign = "center" },

            -- 玩家信息
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                alignItems = "center",
                backgroundColor = { 20, 20, 40, 200 },
                borderRadius = 6,
                padding = 8,
                children = {
                    UI.Label { text = "【" .. (player.status.name or "玩家") .. "】", fontSize = 16, fontColor = { 100, 200, 255, 255 } },
                    UI.Label {
                        text = "HP: " .. playerHp .. " / " .. playerMaxHp,
                        fontSize = 13,
                        fontColor = { 100, 200, 100, 255 },
                    },
                    UI.Label {
                        text = "攻:" .. playerAtk .. "  防:" .. playerDef,
                        fontSize = 12,
                        fontColor = { 150, 150, 200, 255 },
                    },
                },
            },

            -- 操作按钮
            UI.Panel {
                flexDirection = "row",
                justifyContent = "center",
                gap = 12,
                marginTop = 8,
                children = {
                    UI.Button { text = "攻击", variant = "danger", width = 80, onClick = function() CombatUI.DoAttack() end },
                    UI.Button { text = "使用丹药", variant = "success", width = 100, onClick = function() CombatUI.UsePotion() end },
                    UI.Button { text = "逃跑", variant = "secondary", width = 80, onClick = function() CombatUI.Flee() end },
                },
            },

            -- 战斗日志
            combatLog_,
        },
    })
end

--- 执行攻击
function CombatUI.DoAttack()
    if not inCombat_ then return end

    local player = DataManager.playerData
    if not player then return end

    local StatusUI = require("UI.StatusUI")
    local eAtk, eDef, _ = StatusUI.GetEquipBonus()
    local playerAtk = (tonumber(player.status.atk) or 5) + eAtk
    local playerDef = (tonumber(player.status.def) or 3) + eDef

    -- 玩家攻击怪物
    local dmgToMonster = math.max(1, playerAtk - monsterDef_ + math.random(-2, 3))
    monsterHp_ = monsterHp_ - dmgToMonster
    CombatUI.AddCombatLog("你对" .. monsterName_ .. "造成了 " .. dmgToMonster .. " 点伤害")

    -- 检查怪物是否死亡
    if monsterHp_ <= 0 then
        monsterHp_ = 0
        CombatUI.Victory()
        return
    end

    -- 怪物攻击玩家
    local dmgToPlayer = math.max(1, monsterAtk_ - playerDef + math.random(-2, 3))
    player.status.hp = (tonumber(player.status.hp) or 100) - dmgToPlayer
    CombatUI.AddCombatLog(monsterName_ .. "对你造成了 " .. dmgToPlayer .. " 点伤害")

    -- 检查玩家是否死亡
    if tonumber(player.status.hp) <= 0 then
        player.status.hp = 0
        CombatUI.Defeat()
        return
    end

    -- 刷新界面
    CombatUI.Render()
end

--- 使用丹药回血
function CombatUI.UsePotion()
    local player = DataManager.playerData
    if not player then return end

    -- 寻找回血物品
    for i, item in ipairs(player.bag) do
        local itemData = DataManager.GetItem(item.name)
        if itemData and itemData.effect == "heal" then
            local healValue = tonumber(itemData.value) or 0
            local maxHp = tonumber(player.status.max_hp) or 100
            player.status.hp = math.min((tonumber(player.status.hp) or 0) + healValue, maxHp)

            item.count = item.count - 1
            if item.count <= 0 then
                table.remove(player.bag, i)
            end

            CombatUI.AddCombatLog("使用了" .. item.name .. "，恢复" .. healValue .. "生命")

            -- 怪物趁机攻击
            local StatusUI = require("UI.StatusUI")
            local _, eDef, _ = StatusUI.GetEquipBonus()
            local playerDef = (tonumber(player.status.def) or 3) + eDef
            local dmg = math.max(1, monsterAtk_ - playerDef + math.random(-1, 2))
            player.status.hp = (tonumber(player.status.hp) or 100) - dmg
            CombatUI.AddCombatLog(monsterName_ .. "趁机攻击，造成 " .. dmg .. " 伤害")

            if tonumber(player.status.hp) <= 0 then
                player.status.hp = 0
                CombatUI.Defeat()
                return
            end

            CombatUI.Render()
            return
        end
    end

    CombatUI.AddCombatLog("没有可用的回复道具！")
end

--- 逃跑
function CombatUI.Flee()
    inCombat_ = false
    CombatUI.AddCombatLog("你选择了逃跑...")

    if parentRef_ then
        parentRef_:ClearChildren()
        parentRef_:AddChild(UI.Label {
            text = "你逃离了战斗",
            fontSize = 14,
            fontColor = { 180, 180, 200, 255 },
            textAlign = "center",
            marginTop = 20,
        })
    end

    if callback_ then callback_("flee") end
end

--- 战斗胜利
function CombatUI.Victory()
    inCombat_ = false
    local player = DataManager.playerData
    if not player then return end

    local mData = DataManager.GetMonster(monsterName_)
    local expGain = mData and (tonumber(mData.exp) or 10) or 10
    local goldGain = mData and (tonumber(mData.gold) or 5) or 5

    -- 发放奖励
    player.status.exp = (tonumber(player.status.exp) or 0) + expGain
    player.status.gold = (tonumber(player.status.gold) or 0) + goldGain

    -- 掉落物品
    local drops = {}
    if mData and mData.drops then
        local dropList = IniParser.ParseList(mData.drops)
        for _, dropStr in ipairs(dropList) do
            local itemName, chance = dropStr:match("^(.+):(%d+)$")
            if itemName and chance then
                if math.random(100) <= tonumber(chance) then
                    table.insert(drops, itemName)
                    -- 添加到背包
                    local found = false
                    for _, bagItem in ipairs(player.bag) do
                        if bagItem.name == itemName then
                            bagItem.count = bagItem.count + 1
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(player.bag, { name = itemName, count = 1 })
                    end
                end
            end
        end
    end

    -- 检查击杀/收集类任务
    CombatUI.CheckKillQuest(monsterName_)
    CombatUI.CheckCollectQuest(drops)

    -- 检查升级
    local GameUI = require("UI.GameUI")
    GameUI.CheckLevelUp()

    -- 显示胜利界面
    if parentRef_ then
        parentRef_:ClearChildren()
        parentRef_:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "column",
            alignItems = "center",
            padding = 16,
            gap = 8,
            children = {
                UI.Label { text = "战斗胜利！", fontSize = 18, fontColor = { 255, 215, 0, 255 }, textAlign = "center" },
                UI.Label { text = "击败了【" .. monsterName_ .. "】", fontSize = 14, fontColor = { 200, 200, 220, 255 } },
                UI.Label { text = "获得经验：" .. expGain, fontSize = 13, fontColor = { 100, 255, 100, 255 } },
                UI.Label { text = "获得金币：" .. goldGain, fontSize = 13, fontColor = { 255, 215, 0, 255 } },
                #drops > 0 and UI.Label {
                    text = "掉落物品：" .. table.concat(drops, "、"),
                    fontSize = 13,
                    fontColor = { 150, 200, 255, 255 },
                    whiteSpace = "normal",
                } or UI.Panel { height = 0 },
            },
        })
    end

    DataManager.SaveToCloud(player)
    if callback_ then callback_("victory") end
end

--- 战斗失败
function CombatUI.Defeat()
    inCombat_ = false
    local player = DataManager.playerData
    if not player then return end

    -- 死亡惩罚：恢复到满血，扣少量金币
    local goldLoss = math.floor((tonumber(player.status.gold) or 0) * 0.1)
    player.status.gold = (tonumber(player.status.gold) or 0) - goldLoss
    player.status.hp = player.status.max_hp

    if parentRef_ then
        parentRef_:ClearChildren()
        parentRef_:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "column",
            alignItems = "center",
            padding = 16,
            gap = 8,
            children = {
                UI.Label { text = "战斗失败...", fontSize = 18, fontColor = { 255, 80, 80, 255 }, textAlign = "center" },
                UI.Label { text = "你被【" .. monsterName_ .. "】击败了", fontSize = 14, fontColor = { 200, 150, 150, 255 } },
                UI.Label { text = "损失金币：" .. goldLoss, fontSize = 13, fontColor = { 255, 150, 50, 255 } },
                UI.Label { text = "你的伤口已恢复", fontSize = 12, fontColor = { 150, 200, 150, 255 } },
            },
        })
    end

    DataManager.SaveToCloud(player)
    if callback_ then callback_("defeat") end
end

--- 添加战斗日志
---@param msg string
function CombatUI.AddCombatLog(msg)
    if combatLog_ then
        combatLog_:AddChild(UI.Label {
            text = "> " .. msg,
            fontSize = 11,
            fontColor = { 180, 180, 200, 255 },
        })
    end
    print("[Combat] " .. msg)
end

--- 检查击杀类任务
---@param monsterName string
function CombatUI.CheckKillQuest(monsterName)
    local player = DataManager.playerData
    if not player then return end

    for _, quest in ipairs(player.quests.active) do
        local qData = DataManager.GetQuest(quest.id)
        if qData and qData.target_type == "kill" and qData.target_name == monsterName then
            quest.progress = (quest.progress or 0) + 1
            local targetCount = tonumber(qData.target_count) or 1
            print("[CombatUI] 任务进度: " .. quest.id .. " " .. quest.progress .. "/" .. targetCount)

            local GameUI = require("UI.GameUI")
            GameUI.AddLog("任务进度：" .. (qData.name or quest.id) .. " (" .. quest.progress .. "/" .. targetCount .. ")")

            if quest.progress >= targetCount then
                GameUI.CompleteQuest(quest)
            end
        end
    end
end

--- 检查收集类任务
---@param droppedItems table
function CombatUI.CheckCollectQuest(droppedItems)
    local player = DataManager.playerData
    if not player then return end

    for _, quest in ipairs(player.quests.active) do
        local qData = DataManager.GetQuest(quest.id)
        if qData and qData.target_type == "collect" then
            -- 统计背包中目标物品数量
            local count = 0
            for _, bagItem in ipairs(player.bag) do
                if bagItem.name == qData.target_name then
                    count = count + bagItem.count
                    break
                end
            end
            quest.progress = count
            local targetCount = tonumber(qData.target_count) or 1
            if count >= targetCount then
                local GameUI = require("UI.GameUI")
                GameUI.CompleteQuest(quest)
            end
        end
    end
end

return CombatUI
