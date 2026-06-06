---------------------------------------------------
-- DungeonUI.lua - 副本系统
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local IniParser = require("Utils.IniParser")

local DungeonUI = {}

local parentRef_ = nil

-- 副本战斗状态
local currentDungeon_ = nil
local currentWave_ = 0
local waveMonsters_ = {}
local waveIndex_ = 0

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
    local playerLevel = tonumber(player.status.level) or 1

    parentRef_:AddChild(UI.Label {
        text = "— 副本 —",
        fontSize = 16,
        fontColor = { 200, 170, 100, 255 },
        textAlign = "center",
        marginTop = 8,
        marginBottom = 8,
    })

    for dungeonId, dData in pairs(DataManager.dungeons) do
        local levelReq = tonumber(dData.level_req) or 1
        local canEnter = playerLevel >= levelReq
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
end

--- 进入副本
---@param dungeonId string
function DungeonUI.EnterDungeon(dungeonId)
    local dData = DataManager.GetDungeon(dungeonId)
    if not dData then return end

    currentDungeon_ = dData
    currentDungeon_.id = dungeonId
    currentWave_ = 1
    local totalWaves = tonumber(dData.waves) or 1

    print("[DungeonUI] 进入副本: " .. (dData.name or dungeonId) .. "，共" .. totalWaves .. "波")

    DungeonUI.StartWave()
end

--- 开始一波战斗
function DungeonUI.StartWave()
    if not parentRef_ or not currentDungeon_ then return end

    local waveKey = "wave_" .. currentWave_
    local waveData = currentDungeon_[waveKey]

    if not waveData or waveData == "" then
        -- 所有波次完成，检查Boss
        if currentDungeon_.boss and currentDungeon_.boss ~= "" then
            DungeonUI.FightBoss()
        else
            DungeonUI.DungeonVictory()
        end
        return
    end

    waveMonsters_ = IniParser.ParseList(waveData)
    waveIndex_ = 1

    DungeonUI.FightNextMonster()
end

--- 战斗下一只怪物
function DungeonUI.FightNextMonster()
    if waveIndex_ > #waveMonsters_ then
        -- 本波完成
        currentWave_ = currentWave_ + 1
        local totalWaves = tonumber(currentDungeon_.waves) or 1

        if currentWave_ > totalWaves then
            -- 所有波次完成
            if currentDungeon_.boss and currentDungeon_.boss ~= "" then
                DungeonUI.FightBoss()
            else
                DungeonUI.DungeonVictory()
            end
        else
            -- 下一波
            DungeonUI.ShowWaveTransition()
        end
        return
    end

    local monsterName = waveMonsters_[waveIndex_]
    waveIndex_ = waveIndex_ + 1

    -- 显示副本进度，然后开始自动战斗
    DungeonUI.AutoCombat(monsterName, false)
end

--- 自动战斗（副本中简化）
---@param monsterName string
---@param isBoss boolean
function DungeonUI.AutoCombat(monsterName, isBoss)
    local player = DataManager.playerData
    if not player then return end

    local mData = DataManager.GetMonster(monsterName)
    if not mData then
        DungeonUI.FightNextMonster()
        return
    end

    local StatusUI = require("UI.StatusUI")
    local eAtk, eDef, _ = StatusUI.GetEquipBonus()
    local playerAtk = (tonumber(player.status.atk) or 5) + eAtk
    local playerDef = (tonumber(player.status.def) or 3) + eDef

    local mHp = tonumber(mData.hp) or 50
    local mAtk = tonumber(mData.atk) or 5
    local mDef = tonumber(mData.def) or 3

    -- Boss 属性加成
    if isBoss then
        mHp = math.floor(mHp * 1.5)
        mAtk = math.floor(mAtk * 1.3)
        mDef = math.floor(mDef * 1.2)
    end

    -- 自动战斗循环
    local rounds = 0
    while mHp > 0 and tonumber(player.status.hp) > 0 do
        rounds = rounds + 1

        -- 玩家攻击
        local dmg = math.max(1, playerAtk - mDef + math.random(-2, 3))
        mHp = mHp - dmg

        if mHp <= 0 then break end

        -- 怪物攻击
        local mDmg = math.max(1, mAtk - playerDef + math.random(-2, 3))
        player.status.hp = (tonumber(player.status.hp) or 100) - mDmg

        if rounds > 100 then break end -- 防止死循环
    end

    if tonumber(player.status.hp) <= 0 then
        player.status.hp = 0
        DungeonUI.DungeonDefeat()
        return
    end

    -- 获得战斗奖励（副本中每只怪经验减半）
    local expGain = math.floor((tonumber(mData.exp) or 5) * 0.5)
    player.status.exp = (tonumber(player.status.exp) or 0) + expGain

    -- 检查击杀任务
    local CombatUI = require("UI.CombatUI")
    CombatUI.CheckKillQuest(monsterName)

    -- 继续下一只
    DungeonUI.FightNextMonster()
end

--- Boss 战
function DungeonUI.FightBoss()
    local bossName = currentDungeon_.boss
    print("[DungeonUI] Boss 战: " .. bossName)
    DungeonUI.AutoCombat(bossName, true)

    -- 如果还活着，说明打赢了boss（AutoCombat中失败会调DungeonDefeat）
    if tonumber(DataManager.playerData.status.hp) > 0 then
        DungeonUI.DungeonVictory()
    end
end

--- 波次过渡
function DungeonUI.ShowWaveTransition()
    -- 直接继续下一波
    DungeonUI.StartWave()
end

--- 副本通关
function DungeonUI.DungeonVictory()
    if not parentRef_ then return end
    local player = DataManager.playerData
    if not player then return end

    local dData = currentDungeon_
    local expReward = tonumber(dData.reward_exp) or 0
    local goldReward = tonumber(dData.reward_gold) or 0

    player.status.exp = (tonumber(player.status.exp) or 0) + expReward
    player.status.gold = (tonumber(player.status.gold) or 0) + goldReward

    -- 物品奖励
    local rewardItems = IniParser.ParseList(dData.reward_items or "")
    local gotItems = {}
    for _, itemStr in ipairs(rewardItems) do
        local iName, iCount = itemStr:match("^(.+):(%d+)$")
        if iName then
            local GameUI = require("UI.GameUI")
            GameUI.AddItemToBag(iName, tonumber(iCount) or 1)
            table.insert(gotItems, iName .. "x" .. (iCount or 1))
        end
    end

    -- 检查升级
    local GameUI = require("UI.GameUI")
    GameUI.CheckLevelUp()

    parentRef_:ClearChildren()
    parentRef_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "column",
        alignItems = "center",
        padding = 16,
        gap = 8,
        children = {
            UI.Label { text = "副本通关！", fontSize = 20, fontColor = { 255, 215, 0, 255 }, textAlign = "center" },
            UI.Label { text = "【" .. (dData.name or "副本") .. "】", fontSize = 16, fontColor = { 200, 170, 100, 255 } },
            UI.Label { text = "获得经验：" .. expReward, fontSize = 14, fontColor = { 100, 255, 100, 255 } },
            UI.Label { text = "获得金币：" .. goldReward, fontSize = 14, fontColor = { 255, 215, 0, 255 } },
            #gotItems > 0 and UI.Label {
                text = "获得物品：" .. table.concat(gotItems, "、"),
                fontSize = 13,
                fontColor = { 150, 200, 255, 255 },
                whiteSpace = "normal",
            } or UI.Panel { height = 0 },
            UI.Button {
                text = "返回",
                variant = "primary",
                marginTop = 12,
                onClick = function() DungeonUI.ShowList() end,
            },
        },
    })

    DataManager.SaveToCloud(player)
    currentDungeon_ = nil
end

--- 副本失败
function DungeonUI.DungeonDefeat()
    if not parentRef_ then return end
    local player = DataManager.playerData
    if not player then return end

    -- 恢复满血
    player.status.hp = player.status.max_hp

    parentRef_:ClearChildren()
    parentRef_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "column",
        alignItems = "center",
        padding = 16,
        gap = 8,
        children = {
            UI.Label { text = "副本挑战失败", fontSize = 18, fontColor = { 255, 80, 80, 255 }, textAlign = "center" },
            UI.Label { text = "你的实力还不够，需要继续修炼！", fontSize = 14, fontColor = { 200, 150, 150, 255 } },
            UI.Label { text = "伤口已恢复", fontSize = 12, fontColor = { 150, 200, 150, 255 } },
            UI.Button {
                text = "返回",
                variant = "secondary",
                marginTop = 12,
                onClick = function() DungeonUI.ShowList() end,
            },
        },
    })

    DataManager.SaveToCloud(player)
    currentDungeon_ = nil
end

return DungeonUI
