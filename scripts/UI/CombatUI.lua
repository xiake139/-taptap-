---------------------------------------------------
-- CombatUI.lua - 战斗系统
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local IniParser = require("Utils.IniParser")
local NumFormat = require("Utils.NumFormat")
local BigNum = require("Utils.BigNum")

local CombatUI = {}

local parentRef_ = nil
local callback_ = nil
local combatLog_ = nil

-- 战斗状态
local monsterName_ = ""
local monsterHp_ = "0"
local monsterMaxHp_ = "0"
local monsterAtk_ = "0"
local monsterDef_ = "0"
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

    monsterMaxHp_ = BigNum.new(mData.hp or "50")
    monsterHp_ = monsterMaxHp_
    monsterAtk_ = BigNum.new(mData.atk or "5")
    monsterDef_ = BigNum.new(mData.def or "3")

    CombatUI.Render()
end

--- 渲染战斗界面
function CombatUI.Render()
    if not parentRef_ then return end
    parentRef_:ClearChildren()

    local player = DataManager.playerData
    if not player then return end

    -- 计算玩家总属性（含装备加成 + buff加成 + 境界加成）
    local StatusUI = require("UI.StatusUI")
    local BagUI = require("UI.BagUI")
    local eAtk, eDef, eHp = StatusUI.GetEquipBonus()
    local buffAtk = BagUI.GetBuffValue(player, "攻击")
    local buffDef = BagUI.GetBuffValue(player, "防御")
    local buffHp = BagUI.GetBuffValue(player, "生命上限")
    local rAtk, rDef, rHp = DataManager.GetRealmBonus()
    local playerAtk = BigNum.add(BigNum.add(BigNum.add(player.status.atk or "5", tostring(eAtk)), tostring(buffAtk)), rAtk)
    local playerDef = BigNum.add(BigNum.add(BigNum.add(player.status.def or "3", tostring(eDef)), tostring(buffDef)), rDef)
    local playerHp = BigNum.new(player.status.hp or "100")
    local playerMaxHp = BigNum.add(BigNum.add(BigNum.add(player.status.max_hp or "100", tostring(eHp)), tostring(buffHp)), rHp)

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
                        text = "生命: " .. NumFormat.Short(monsterHp_) .. " / " .. NumFormat.Short(monsterMaxHp_),
                        fontSize = 13,
                        fontColor = { 255, 100, 100, 255 },
                    },
                    UI.Label {
                        text = "攻:" .. NumFormat.Short(monsterAtk_) .. "  防:" .. NumFormat.Short(monsterDef_),
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
                        text = "生命: " .. NumFormat.Short(playerHp) .. " / " .. NumFormat.Short(playerMaxHp),
                        fontSize = 13,
                        fontColor = { 100, 200, 100, 255 },
                    },
                    UI.Label {
                        text = "攻:" .. NumFormat.Short(playerAtk) .. "  防:" .. NumFormat.Short(playerDef),
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
    local BagUI = require("UI.BagUI")
    local eAtk, eDef, _ = StatusUI.GetEquipBonus()
    local buffAtk = BagUI.GetBuffValue(player, "攻击")
    local buffDef = BagUI.GetBuffValue(player, "防御")
    local rAtk2, rDef2, _ = DataManager.GetRealmBonus()
    local playerAtk = BigNum.add(BigNum.add(BigNum.add(player.status.atk or "5", tostring(eAtk)), tostring(buffAtk)), rAtk2)
    local playerDef = BigNum.add(BigNum.add(BigNum.add(player.status.def or "3", tostring(eDef)), tostring(buffDef)), rDef2)

    -- 玩家攻击怪物
    local dmgToMonster = BigNum.max("1", BigNum.add(BigNum.sub(playerAtk, monsterDef_), tostring(math.random(-2, 3))))
    monsterHp_ = BigNum.sub(monsterHp_, dmgToMonster)
    CombatUI.AddCombatLog("你对" .. monsterName_ .. "造成了 " .. NumFormat.Short(dmgToMonster) .. " 点伤害")

    -- 检查怪物是否死亡
    if BigNum.lte(monsterHp_, "0") then
        monsterHp_ = "0"
        CombatUI.Victory()
        return
    end

    -- 怪物攻击玩家
    local dmgToPlayer = BigNum.max("1", BigNum.add(BigNum.sub(monsterAtk_, playerDef), tostring(math.random(-2, 3))))
    player.status.hp = BigNum.sub(BigNum.new(player.status.hp or "100"), dmgToPlayer)
    CombatUI.AddCombatLog(monsterName_ .. "对你造成了 " .. NumFormat.Short(dmgToPlayer) .. " 点伤害")

    -- 检查玩家是否死亡
    if BigNum.lte(player.status.hp, "0") then
        player.status.hp = "0"
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
            local healValue = BigNum.new(itemData.value or "0")
            local maxHp = BigNum.new(player.status.max_hp or "100")
            player.status.hp = BigNum.min(BigNum.add(player.status.hp or "0", healValue), maxHp)

            item.count = BigNum.sub(item.count or "1", "1")
            if BigNum.lte(item.count, "0") then
                table.remove(player.bag, i)
            end

            CombatUI.AddCombatLog("使用了" .. item.name .. "，恢复" .. NumFormat.Short(healValue) .. "生命")

            -- 怪物趁机攻击
            local StatusUI = require("UI.StatusUI")
            local BagUI = require("UI.BagUI")
            local _, eDef, _ = StatusUI.GetEquipBonus()
            local buffDef = BagUI.GetBuffValue(player, "防御")
            local _, rDef3, _ = DataManager.GetRealmBonus()
            local playerDef = BigNum.add(BigNum.add(BigNum.add(player.status.def or "3", tostring(eDef)), tostring(buffDef)), rDef3)
            local dmg = BigNum.max("1", BigNum.add(BigNum.sub(monsterAtk_, playerDef), tostring(math.random(-1, 2))))
            player.status.hp = BigNum.sub(BigNum.new(player.status.hp or "100"), dmg)
            CombatUI.AddCombatLog(monsterName_ .. "趁机攻击，造成 " .. NumFormat.Short(dmg) .. " 伤害")

            if BigNum.lte(player.status.hp, "0") then
                player.status.hp = "0"
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
    local baseExp = mData and (mData.exp or "5") or "5"
    local baseGold = mData and (mData.gold or "2") or "2"

    -- 清理旧版残留字段（已迁移到 buff 系统）
    player.status.exp_rate = nil
    player.status.gold_rate = nil

    -- 从 buff 系统获取倍率加成
    local BagUI = require("UI.BagUI")
    local expRate = BagUI.GetBuffValue(player, "经验倍率")
    local goldRate = BagUI.GetBuffValue(player, "货币倍率")
    -- 使用缩放法处理小数倍率：乘以100再除以100
    local expRateScaled = math.floor(expRate * 100 + 0.5)
    local goldRateScaled = math.floor(goldRate * 100 + 0.5)
    local expGain = BigNum.div(BigNum.mul(BigNum.new(baseExp), tostring(expRateScaled)), "100")
    local goldGain = BigNum.div(BigNum.mul(BigNum.new(baseGold), tostring(goldRateScaled)), "100")

    print("[Combat] 经验计算: " .. baseExp .. " * " .. expRate .. " = " .. expGain)
    print("[Combat] 金币计算: " .. baseGold .. " * " .. goldRate .. " = " .. goldGain)

    -- 发放奖励
    player.status.exp = BigNum.add(player.status.exp or "0", expGain)
    player.status.gold = BigNum.add(player.status.gold or "0", goldGain)

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
                            bagItem.count = BigNum.add(bagItem.count or "0", "1")
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(player.bag, { name = itemName, count = "1" })
                    end
                end
            end
        end
    end

    -- 额外灵石掉落（境界突破材料，所有怪物通用）
    local realmStoneChance = 15  -- 基础15%概率掉落灵石
    if mData and tonumber(mData.level or "1") >= 5 then
        realmStoneChance = 25  -- 5级以上怪物25%概率
    end
    if math.random(100) <= realmStoneChance then
        local stoneName = "灵石"
        table.insert(drops, stoneName)
        local found = false
        for _, bagItem in ipairs(player.bag) do
            if bagItem.name == stoneName then
                bagItem.count = BigNum.add(bagItem.count or "0", "1")
                found = true
                break
            end
        end
        if not found then
            table.insert(player.bag, { name = stoneName, count = "1" })
        end
    end

    -- 检查击杀/收集类任务
    CombatUI.CheckKillQuest(monsterName_)
    CombatUI.CheckCollectQuest(drops)

    -- 检查升级
    local GameUI = require("UI.GameUI")
    GameUI.CheckLevelUp()

    -- 写入游戏日志栏：击杀信息
    GameUI.AddLog("击败了【" .. monsterName_ .. "】")
    -- 经验日志（含buff倍率标注）
    local expLogStr = "获得经验 +" .. NumFormat.Short(expGain)
    if expRate > 1 then
        expLogStr = expLogStr .. " (经验倍率×" .. expRate .. ")"
    end
    GameUI.AddLog(expLogStr)
    -- 金币日志（含buff倍率标注）
    local goldLogStr = "获得金币 +" .. NumFormat.Short(goldGain)
    if goldRate > 1 then
        goldLogStr = goldLogStr .. " (货币倍率×" .. goldRate .. ")"
    end
    GameUI.AddLog(goldLogStr)
    -- 掉落物品日志
    if #drops > 0 then
        GameUI.AddLog("掉落物品：" .. table.concat(drops, "、"))
    end

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
                UI.Label { text = "获得经验：" .. NumFormat.Short(expGain), fontSize = 13, fontColor = { 100, 255, 100, 255 } },
                UI.Label { text = "获得金币：" .. NumFormat.Short(goldGain), fontSize = 13, fontColor = { 255, 215, 0, 255 } },
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

    -- 死亡惩罚：恢复到满血，扣少量金币（10%）
    local goldLoss = BigNum.div(BigNum.new(player.status.gold or "0"), "10")
    player.status.gold = BigNum.sub(BigNum.new(player.status.gold or "0"), goldLoss)
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
                UI.Label { text = "损失金币：" .. NumFormat.Short(goldLoss), fontSize = 13, fontColor = { 255, 150, 50, 255 } },
                UI.Label { text = "你的伤口已恢复", fontSize = 12, fontColor = { 150, 200, 150, 255 } },
            },
        })
    end

    DataManager.SaveToCloud(player)
    if callback_ then callback_("defeat") end
end

--- 添加战斗日志（同时写入底部游戏日志栏）
---@param msg string
function CombatUI.AddCombatLog(msg)
    if combatLog_ then
        combatLog_:AddChild(UI.Label {
            text = "> " .. msg,
            fontSize = 11,
            fontColor = { 180, 180, 200, 255 },
        })
    end
    local GameUI = require("UI.GameUI")
    if GameUI.AddLog then GameUI.AddLog(msg) end
    print("[Combat] " .. msg)
end

--- 检查击杀类任务
---@param monsterName string
function CombatUI.CheckKillQuest(monsterName)
    local player = DataManager.playerData
    if not player then return end

    for _, quest in ipairs(player.quests.active) do
        local qData = DataManager.GetQuest(quest.id)
        if qData and (qData.target_type == "kill" or qData.target_type == "击杀") and qData.target_name == monsterName then
            quest.progress = BigNum.add(tostring(quest.progress or "0"), "1")
            local targetCount = qData.target_count or "1"
            print("[CombatUI] 任务进度: " .. quest.id .. " " .. quest.progress .. "/" .. targetCount)

            local GameUI = require("UI.GameUI")
            GameUI.AddLog("任务进度：" .. (qData.name or quest.id) .. " (" .. quest.progress .. "/" .. targetCount .. ")")

            if BigNum.gte(quest.progress, targetCount) then
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
        if qData and (qData.target_type == "collect" or qData.target_type == "收集") then
            -- 统计背包中目标物品数量
            local count = "0"
            for _, bagItem in ipairs(player.bag) do
                if bagItem.name == qData.target_name then
                    count = BigNum.add(count, tostring(bagItem.count or "0"))
                    break
                end
            end
            quest.progress = count
            local targetCount = qData.target_count or "1"
            if BigNum.gte(count, targetCount) then
                local GameUI = require("UI.GameUI")
                GameUI.CompleteQuest(quest)
            end
        end
    end
end

return CombatUI
