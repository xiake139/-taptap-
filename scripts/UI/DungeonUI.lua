---------------------------------------------------
-- DungeonUI.lua - 副本系统（逐步击杀模式）
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local IniParser = require("Utils.IniParser")
local NumFormat = require("Utils.NumFormat")
local BigNum = require("Utils.BigNum")

local DungeonUI = {}

local parentRef_ = nil

-- 副本战斗状态
local currentDungeon_ = nil   -- 当前副本数据
local currentWave_ = 0        -- 当前波次
local waveMonsters_ = {}      -- 当前波次怪物列表
local waveIndex_ = 0          -- 当前波次第几只怪
local combatLog_ = {}         -- 战斗日志

--- 渲染副本列表
---@param parent Widget
function DungeonUI.Render(parent)
    parentRef_ = parent
    DungeonUI.ShowList()
end

--- 显示副本列表
function DungeonUI.ShowList()
    if not parentRef_ then return end
    parentRef_:ClearChildren()

    local player = DataManager.playerData
    if not player then return end
    local playerLevel = player.status.level or "1"

    parentRef_:AddChild(UI.Label {
        text = "— 副本 —",
        fontSize = 16,
        fontColor = { 200, 170, 100, 255 },
        textAlign = "center",
        marginTop = 8,
        marginBottom = 8,
    })

    local hasDungeon = false
    for dungeonId, dData in pairs(DataManager.dungeons) do
        hasDungeon = true
        local levelReq = dData.level_req or "1"
        local canEnter = not BigNum.lt(playerLevel, levelReq)
        local labelColor = canEnter and { 220, 220, 240, 255 } or { 100, 100, 120, 255 }

        parentRef_:AddChild(UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            width = "100%",
            padding = 8,
            backgroundColor = { 25, 20, 45, 200 },
            borderRadius = 6,
            marginBottom = 6,
            gap = 8,
            children = {
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    flexDirection = "column",
                    children = {
                        UI.Label { text = dData.name or dungeonId, fontSize = 14, fontColor = labelColor },
                        UI.Label { text = (dData.desc or "") .. " (需要等级" .. levelReq .. ")", fontSize = 11, fontColor = { 140, 140, 160, 255 }, whiteSpace = "normal" },
                        UI.Label { text = "波次:" .. (dData.waves or "?") .. "  奖励经验:" .. (dData.reward_exp or "?"), fontSize = 11, fontColor = { 150, 200, 150, 255 } },
                    },
                },
                UI.Button {
                    text = canEnter and "进入" or "锁定",
                    variant = canEnter and "danger" or "secondary",
                    height = 30,
                    onClick = canEnter and function() DungeonUI.EnterDungeon(dungeonId) end or nil,
                },
            },
        })
    end

    if not hasDungeon then
        parentRef_:AddChild(UI.Label {
            text = "暂无可用副本",
            fontSize = 13,
            fontColor = { 120, 120, 140, 255 },
            textAlign = "center",
            marginTop = 20,
        })
    end
end

--- 进入副本
---@param dungeonId string
function DungeonUI.EnterDungeon(dungeonId)
    local dData = DataManager.GetDungeon(dungeonId)
    if not dData then
        print("[DungeonUI] 找不到副本数据: " .. dungeonId)
        return
    end

    currentDungeon_ = {
        id = dungeonId,
        name = dData.name or dungeonId,
        desc = dData.desc or "",
        waves = tonumber(dData.waves) or 1,  -- for-loop 需要 number
        boss = dData.boss or "",
        reward_exp = dData.reward_exp or "0",
        reward_gold = dData.reward_gold or "0",
        reward_items = dData.reward_items or "",
    }
    -- 复制波次数据
    for i = 1, currentDungeon_.waves do
        currentDungeon_["wave_" .. i] = dData["wave_" .. i] or ""
    end

    currentWave_ = 1
    combatLog_ = {}

    local totalWaves = currentDungeon_.waves
    print("[DungeonUI] 进入副本: " .. currentDungeon_.name .. "，共" .. totalWaves .. "波")

    local GameUI = require("UI.GameUI")
    if GameUI.AddLog then
        GameUI.AddLog("进入副本【" .. currentDungeon_.name .. "】")
    end

    DungeonUI.StartWave()
end

--- 开始一波战斗
function DungeonUI.StartWave()
    if not parentRef_ or not currentDungeon_ then return end

    local totalWaves = currentDungeon_.waves

    if currentWave_ > totalWaves then
        -- 所有波次完成，检查 Boss
        if currentDungeon_.boss ~= "" then
            DungeonUI.ShowBossIntro()
        else
            DungeonUI.DungeonVictory()
        end
        return
    end

    local waveKey = "wave_" .. currentWave_
    local waveData = currentDungeon_[waveKey]

    if not waveData or waveData == "" then
        -- 本波无怪物数据，跳到下一波
        currentWave_ = currentWave_ + 1
        DungeonUI.StartWave()
        return
    end

    waveMonsters_ = IniParser.ParseList(waveData)
    waveIndex_ = 1

    -- 显示波次开始提示
    DungeonUI.ShowWaveStart()
end

--- 显示波次开始界面
function DungeonUI.ShowWaveStart()
    if not parentRef_ then return end
    parentRef_:ClearChildren()

    local totalWaves = currentDungeon_.waves

    parentRef_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "column",
        alignItems = "center",
        padding = 12,
        gap = 8,
        children = {
            UI.Label {
                text = "【" .. currentDungeon_.name .. "】",
                fontSize = 16,
                fontColor = { 200, 170, 100, 255 },
                textAlign = "center",
            },
            UI.Label {
                text = "第 " .. currentWave_ .. " / " .. totalWaves .. " 波",
                fontSize = 15,
                fontColor = { 220, 220, 240, 255 },
                textAlign = "center",
            },
            UI.Label {
                text = "怪物数量: " .. #waveMonsters_,
                fontSize = 13,
                fontColor = { 180, 180, 200, 255 },
                textAlign = "center",
            },
            UI.Button {
                text = "开始战斗",
                variant = "danger",
                marginTop = 8,
                onClick = function() DungeonUI.FightCurrentMonster() end,
            },
            UI.Button {
                text = "撤退",
                variant = "secondary",
                onClick = function() DungeonUI.Retreat() end,
            },
        },
    })
end

--- 战斗当前怪物
function DungeonUI.FightCurrentMonster()
    if not currentDungeon_ then return end

    if waveIndex_ > #waveMonsters_ then
        -- 本波完成
        currentWave_ = currentWave_ + 1
        DungeonUI.StartWave()
        return
    end

    local monsterName = waveMonsters_[waveIndex_]
    DungeonUI.DoCombat(monsterName, false)
end

--- 执行一次战斗并显示结果
---@param monsterName string
---@param isBoss boolean
function DungeonUI.DoCombat(monsterName, isBoss)
    local player = DataManager.playerData
    if not player then return end

    local mData = DataManager.GetMonster(monsterName)
    if not mData then
        print("[DungeonUI] 找不到怪物: " .. monsterName)
        -- 跳过该怪物
        waveIndex_ = waveIndex_ + 1
        DungeonUI.ShowCombatResult(monsterName, true, {}, "0", false)
        return
    end

    local StatusUI = require("UI.StatusUI")
    local eAtk, eDef, _ = StatusUI.GetEquipBonus()
    local BagUI = require("UI.BagUI")
    local atkBuff = BagUI.GetBuffValue(player, "攻击")
    local defBuff = BagUI.GetBuffValue(player, "防御")
    local playerAtk = BigNum.add(BigNum.add(player.status.atk or "5", tostring(eAtk)), tostring(atkBuff))
    local playerDef = BigNum.add(BigNum.add(player.status.def or "3", tostring(eDef)), tostring(defBuff))
    local playerHp = BigNum.new(player.status.hp or "100")

    local mHp = BigNum.new(mData.hp or "50")
    local mAtk = BigNum.new(mData.atk or "5")
    local mDef = BigNum.new(mData.def or "3")

    -- Boss 属性加成（1.5x/1.3x/1.2x 用缩放法）
    if isBoss then
        mHp = BigNum.div(BigNum.mul(mHp, "150"), "100")
        mAtk = BigNum.div(BigNum.mul(mAtk, "130"), "100")
        mDef = BigNum.div(BigNum.mul(mDef, "120"), "100")
    end

    -- 战斗日志
    local log = {}
    local rounds = 0
    local won = false

    while BigNum.gt(mHp, "0") and BigNum.gt(playerHp, "0") do
        rounds = rounds + 1

        -- 玩家攻击
        local dmg = BigNum.max("1", BigNum.add(BigNum.sub(playerAtk, mDef), tostring(math.random(-2, 3))))
        mHp = BigNum.sub(mHp, dmg)
        table.insert(log, "你攻击" .. monsterName .. "，造成" .. NumFormat.Short(dmg) .. "点伤害")

        if BigNum.lte(mHp, "0") then
            table.insert(log, monsterName .. "被击败了！")
            won = true
            break
        end

        -- 怪物攻击
        local mDmg = BigNum.max("1", BigNum.add(BigNum.sub(mAtk, playerDef), tostring(math.random(-2, 3))))
        playerHp = BigNum.sub(playerHp, mDmg)
        table.insert(log, monsterName .. "攻击你，造成" .. NumFormat.Short(mDmg) .. "点伤害")

        if BigNum.lte(playerHp, "0") then
            table.insert(log, "你被击败了...")
            break
        end

        if rounds > 100 then
            table.insert(log, "战斗超时")
            break
        end
    end

    -- 更新玩家血量
    player.status.hp = BigNum.max("0", playerHp)

    local expGain = "0"
    if won then
        -- 获得经验（副本内每只怪经验减半）
        local expRate = BagUI.GetBuffValue(player, "经验倍率")
        -- 0.5 * expRate 用缩放法: expRate*50/100
        local rateScaled = math.floor(expRate * 50 + 0.5)
        expGain = BigNum.div(BigNum.mul(BigNum.new(mData.exp or "5"), tostring(rateScaled)), "100")
        player.status.exp = BigNum.add(player.status.exp or "0", expGain)

        -- 检查击杀任务
        local CombatUI = require("UI.CombatUI")
        CombatUI.CheckKillQuest(monsterName)

        waveIndex_ = waveIndex_ + 1
    end

    DungeonUI.ShowCombatResult(monsterName, won, log, expGain, isBoss)
end

--- 显示战斗结果
---@param monsterName string
---@param won boolean
---@param log table
---@param expGain string
---@param isBoss boolean
function DungeonUI.ShowCombatResult(monsterName, won, log, expGain, isBoss)
    if not parentRef_ then return end
    parentRef_:ClearChildren()

    local player = DataManager.playerData
    local totalWaves = currentDungeon_ and currentDungeon_.waves or 1
    local displayName = isBoss and ("BOSS " .. monsterName) or monsterName

    -- 标题
    parentRef_:AddChild(UI.Label {
        text = won and ("击败了【" .. displayName .. "】") or ("被【" .. displayName .. "】击败"),
        fontSize = 15,
        fontColor = won and { 100, 255, 100, 255 } or { 255, 80, 80, 255 },
        textAlign = "center",
        marginTop = 8,
        marginBottom = 4,
    })

    -- 进度信息
    if currentDungeon_ then
        local progressText = "第" .. currentWave_ .. "/" .. totalWaves .. "波"
        if not isBoss then
            progressText = progressText .. "  怪物" .. (waveIndex_ - (won and 1 or 0)) .. "/" .. #waveMonsters_
        end
        parentRef_:AddChild(UI.Label {
            text = progressText,
            fontSize = 12,
            fontColor = { 160, 160, 180, 255 },
            textAlign = "center",
            marginBottom = 4,
        })
    end

    -- 战斗日志（滚动区域）
    local logChildren = {}
    -- 只显示最后 10 条日志避免太长
    local startIdx = math.max(1, #log - 9)
    for i = startIdx, #log do
        table.insert(logChildren, UI.Label {
            text = "> " .. log[i],
            fontSize = 11,
            fontColor = { 180, 180, 200, 255 },
        })
    end

    parentRef_:AddChild(UI.ScrollView {
        width = "100%",
        maxHeight = 150,
        backgroundColor = { 15, 12, 30, 200 },
        borderRadius = 4,
        padding = 6,
        marginBottom = 6,
        children = logChildren,
    })

    -- 经验获取
    if won and not BigNum.isZero(expGain) then
        parentRef_:AddChild(UI.Label {
            text = "获得经验 +" .. NumFormat.Short(expGain),
            fontSize = 13,
            fontColor = { 100, 255, 100, 255 },
            textAlign = "center",
        })
    end

    -- 玩家状态
    if player then
        parentRef_:AddChild(UI.Label {
            text = "剩余生命: " .. NumFormat.Short(player.status.hp) .. "/" .. NumFormat.Short(player.status.max_hp),
            fontSize = 13,
            fontColor = BigNum.gt(player.status.hp or "0", "0") and { 200, 200, 220, 255 } or { 255, 80, 80, 255 },
            textAlign = "center",
            marginTop = 4,
        })
    end

    -- 按钮区域
    if not won then
        -- 战败
        parentRef_:AddChild(UI.Panel {
            flexDirection = "row",
            justifyContent = "center",
            gap = 12,
            marginTop = 10,
            children = {
                UI.Button {
                    text = "返回",
                    variant = "secondary",
                    onClick = function()
                        -- 恢复满血后退出
                        if player then
                            player.status.hp = player.status.max_hp
                            DataManager.SaveToCloud(player)
                        end
                        currentDungeon_ = nil
                        DungeonUI.ShowList()
                    end,
                },
            },
        })
    elseif isBoss then
        -- Boss 击败 → 通关
        parentRef_:AddChild(UI.Button {
            text = "领取通关奖励",
            variant = "primary",
            marginTop = 10,
            onClick = function() DungeonUI.DungeonVictory() end,
        })
    else
        -- 普通怪击败 → 继续
        local isWaveEnd = waveIndex_ > #waveMonsters_
        local isAllWaveEnd = isWaveEnd and (currentWave_ + 1 > totalWaves)
        local hasBoss = currentDungeon_ and currentDungeon_.boss ~= ""

        local nextText = "继续战斗"
        if isWaveEnd and not isAllWaveEnd then
            nextText = "下一波"
        elseif isAllWaveEnd and hasBoss then
            nextText = "挑战Boss"
        elseif isAllWaveEnd and not hasBoss then
            nextText = "领取奖励"
        end

        parentRef_:AddChild(UI.Panel {
            flexDirection = "row",
            justifyContent = "center",
            gap = 12,
            marginTop = 10,
            children = {
                UI.Button {
                    text = nextText,
                    variant = "primary",
                    onClick = function()
                        if isWaveEnd then
                            currentWave_ = currentWave_ + 1
                            DungeonUI.StartWave()
                        else
                            DungeonUI.FightCurrentMonster()
                        end
                    end,
                },
                UI.Button {
                    text = "撤退",
                    variant = "secondary",
                    onClick = function() DungeonUI.Retreat() end,
                },
            },
        })
    end
end

--- Boss 介绍界面
function DungeonUI.ShowBossIntro()
    if not parentRef_ or not currentDungeon_ then return end
    parentRef_:ClearChildren()

    local bossName = currentDungeon_.boss
    local mData = DataManager.GetMonster(bossName)

    parentRef_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "column",
        alignItems = "center",
        padding = 16,
        gap = 8,
        children = {
            UI.Label {
                text = "Boss 出现！",
                fontSize = 18,
                fontColor = { 255, 80, 80, 255 },
                textAlign = "center",
            },
            UI.Label {
                text = "【" .. bossName .. "】",
                fontSize = 16,
                fontColor = { 255, 200, 100, 255 },
                textAlign = "center",
            },
            mData and UI.Label {
                text = "生命:" .. NumFormat.Short(BigNum.div(BigNum.mul(BigNum.new(mData.hp or "50"), "150"), "100")) ..
                    "  攻击:" .. NumFormat.Short(BigNum.div(BigNum.mul(BigNum.new(mData.atk or "5"), "130"), "100")) ..
                    "  防御:" .. NumFormat.Short(BigNum.div(BigNum.mul(BigNum.new(mData.def or "3"), "120"), "100")),
                fontSize = 13,
                fontColor = { 200, 150, 150, 255 },
                textAlign = "center",
            } or UI.Panel { height = 0 },
            UI.Button {
                text = "迎战",
                variant = "danger",
                marginTop = 8,
                onClick = function() DungeonUI.DoCombat(bossName, true) end,
            },
            UI.Button {
                text = "撤退",
                variant = "secondary",
                onClick = function() DungeonUI.Retreat() end,
            },
        },
    })
end

--- 副本通关
function DungeonUI.DungeonVictory()
    if not parentRef_ or not currentDungeon_ then return end
    local player = DataManager.playerData
    if not player then return end

    local dData = currentDungeon_
    local expReward = BigNum.new(dData.reward_exp or "0")
    local goldReward = BigNum.new(dData.reward_gold or "0")

    -- 应用倍率（缩放法）
    local BagUI = require("UI.BagUI")
    local expRate = BagUI.GetBuffValue(player, "经验倍率")
    local goldRate = BagUI.GetBuffValue(player, "货币倍率")
    local expRateScaled = math.floor(expRate * 100 + 0.5)
    local goldRateScaled = math.floor(goldRate * 100 + 0.5)
    expReward = BigNum.div(BigNum.mul(expReward, tostring(expRateScaled)), "100")
    goldReward = BigNum.div(BigNum.mul(goldReward, tostring(goldRateScaled)), "100")

    player.status.exp = BigNum.add(player.status.exp or "0", expReward)
    player.status.gold = BigNum.add(player.status.gold or "0", goldReward)

    -- 物品奖励
    local rewardItems = IniParser.ParseList(dData.reward_items or "")
    local gotItems = {}
    for _, itemStr in ipairs(rewardItems) do
        local iName, iCount = itemStr:match("^(.+):(%d+)$")
        if iName then
            local GameUI = require("UI.GameUI")
            GameUI.AddItemToBag(iName, iCount or "1")
            table.insert(gotItems, iName .. "x" .. (iCount or 1))
        end
    end

    -- 检查升级
    local GameUI = require("UI.GameUI")
    GameUI.CheckLevelUp()

    -- 日志
    if GameUI.AddLog then
        GameUI.AddLog("通关副本【" .. dData.name .. "】")
        local expLog = "获得经验 +" .. NumFormat.Short(expReward)
        if expRate > 1 then expLog = expLog .. " (经验倍率x" .. expRate .. ")" end
        GameUI.AddLog(expLog)
        local goldLog = "获得金币 +" .. NumFormat.Short(goldReward)
        if goldRate > 1 then goldLog = goldLog .. " (货币倍率x" .. goldRate .. ")" end
        GameUI.AddLog(goldLog)
        if #gotItems > 0 then
            GameUI.AddLog("获得物品：" .. table.concat(gotItems, "、"))
        end
    end

    -- 显示通关界面
    parentRef_:ClearChildren()

    local resultChildren = {
        UI.Label { text = "副本通关！", fontSize = 20, fontColor = { 255, 215, 0, 255 }, textAlign = "center" },
        UI.Label { text = "【" .. dData.name .. "】", fontSize = 16, fontColor = { 200, 170, 100, 255 } },
        UI.Label { text = "获得经验：+" .. NumFormat.Short(expReward), fontSize = 14, fontColor = { 100, 255, 100, 255 } },
    }

    if expRate > 1 then
        table.insert(resultChildren, UI.Label { text = "(经验倍率x" .. expRate .. ")", fontSize = 11, fontColor = { 150, 255, 150, 255 } })
    end

    table.insert(resultChildren, UI.Label { text = "获得金币：+" .. NumFormat.Short(goldReward), fontSize = 14, fontColor = { 255, 215, 0, 255 } })

    if goldRate > 1 then
        table.insert(resultChildren, UI.Label { text = "(货币倍率x" .. goldRate .. ")", fontSize = 11, fontColor = { 255, 235, 100, 255 } })
    end

    if #gotItems > 0 then
        table.insert(resultChildren, UI.Label {
            text = "获得物品：" .. table.concat(gotItems, "、"),
            fontSize = 13,
            fontColor = { 150, 200, 255, 255 },
            whiteSpace = "normal",
        })
    end

    table.insert(resultChildren, UI.Button {
        text = "返回",
        variant = "primary",
        marginTop = 12,
        onClick = function() DungeonUI.ShowList() end,
    })

    parentRef_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "column",
        alignItems = "center",
        padding = 16,
        gap = 6,
        children = resultChildren,
    })

    DataManager.SaveToCloud(player)
    currentDungeon_ = nil
end

--- 撤退（中途退出副本）
function DungeonUI.Retreat()
    local player = DataManager.playerData
    if player then
        DataManager.SaveToCloud(player)
    end

    local GameUI = require("UI.GameUI")
    if GameUI.AddLog then
        GameUI.AddLog("从副本中撤退")
    end

    currentDungeon_ = nil
    DungeonUI.ShowList()
end

return DungeonUI
