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

-- 战斗状态
local monsterName_ = ""
local monsterHp_ = "0"
local monsterMaxHp_ = "0"
local monsterAtk_ = "0"
local monsterDef_ = "0"
local inCombat_ = false

-- 出战宠物战斗状态
local combatPets_ = {}  -- { {name, atk, def, hp, maxHp, alive} }

--- 计算玩家实际生命上限（含装备+buff+境界+战魂加成）
---@return string 完整的max_hp值
local function CalcPlayerMaxHp()
    local player = DataManager.playerData
    if not player then return "100" end
    local StatusUI = require("UI.StatusUI")
    local BagUI = require("UI.BagUI")
    local _, _, eHp = StatusUI.GetEquipBonus()
    local buffHp = BagUI.GetBuffValue(player, "生命上限")
    local _, _, rHp = DataManager.GetRealmBonus()
    local soulBonus = DataManager.GetBattleSoulBonus(player.status.battle_soul_level)
    return BigNum.add(BigNum.add(BigNum.add(BigNum.add(player.status.max_hp or "100", tostring(eHp)), tostring(buffHp)), rHp), soulBonus.max_hp)
end

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

    -- 初始化出战宠物战斗数据（使用完整属性计算，含等级/升星/进阶/品质/装备加成）
    combatPets_ = {}
    local PetUI = require("UI.PetUI")
    local player = DataManager.playerData
    if player and player.pets then
        for _, pet in ipairs(player.pets) do
            if pet.deployed then
                local petAtk, petDef, petHp = PetUI.CalcPetPower(pet)
                table.insert(combatPets_, {
                    name = pet.name or "宠物",
                    atk = petAtk,
                    def = petDef,
                    hp = petHp,
                    maxHp = petHp,
                    alive = true,
                })
                print("[CombatUI] 出战宠物: " .. (pet.name or "?") .. " ATK=" .. petAtk .. " DEF=" .. petDef .. " HP=" .. petHp)
            end
        end
    end

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
    local eAtk, eDef, _ = StatusUI.GetEquipBonus()
    local buffAtk = BagUI.GetBuffValue(player, "攻击")
    local buffDef = BagUI.GetBuffValue(player, "防御")
    local rAtk, rDef, _ = DataManager.GetRealmBonus()
    local soulBonus = DataManager.GetBattleSoulBonus(player.status.battle_soul_level)
    local playerAtk = BigNum.add(BigNum.add(BigNum.add(BigNum.add(player.status.atk or "5", tostring(eAtk)), tostring(buffAtk)), rAtk), soulBonus.atk)
    local playerDef = BigNum.add(BigNum.add(BigNum.add(BigNum.add(player.status.def or "3", tostring(eDef)), tostring(buffDef)), rDef), soulBonus.def)
    local playerHp = BigNum.new(player.status.hp or "100")
    local playerMaxHp = CalcPlayerMaxHp()



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

            -- 出战宠物信息
            CombatUI.RenderPetPanel(),

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


        },
    })
end

--- 渲染出战宠物面板
function CombatUI.RenderPetPanel()
    if #combatPets_ == 0 then
        return UI.Panel { height = 0 }
    end

    local petChildren = {}
    for _, pet in ipairs(combatPets_) do
        local nameColor = pet.alive and { 180, 255, 180, 255 } or { 120, 120, 120, 255 }
        local hpColor = pet.alive and { 100, 220, 100, 255 } or { 120, 120, 120, 255 }
        local statusText = pet.alive
            and ("HP:" .. NumFormat.Short(pet.hp) .. "/" .. NumFormat.Short(pet.maxHp) .. "  攻:" .. NumFormat.Short(pet.atk))
            or "已阵亡"
        table.insert(petChildren, UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Label { text = "🐾 " .. pet.name, fontSize = 12, fontColor = nameColor },
                UI.Label { text = statusText, fontSize = 11, fontColor = hpColor },
            },
        })
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        backgroundColor = { 20, 40, 20, 200 },
        borderRadius = 6,
        padding = 6,
        gap = 3,
        children = {
            UI.Label { text = "出战宠物", fontSize = 12, fontColor = { 150, 255, 150, 255 }, textAlign = "center" },
            table.unpack(petChildren),
        },
    }
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
    local soulBonus2 = DataManager.GetBattleSoulBonus(player.status.battle_soul_level)
    local playerAtk = BigNum.add(BigNum.add(BigNum.add(BigNum.add(player.status.atk or "5", tostring(eAtk)), tostring(buffAtk)), rAtk2), soulBonus2.atk)
    local playerDef = BigNum.add(BigNum.add(BigNum.add(BigNum.add(player.status.def or "3", tostring(eDef)), tostring(buffDef)), rDef2), soulBonus2.def)

    -- 玩家攻击怪物
    local dmgToMonster = BigNum.max("1", BigNum.add(BigNum.sub(playerAtk, monsterDef_), tostring(math.random(-2, 3))))
    monsterHp_ = BigNum.sub(monsterHp_, dmgToMonster)
    CombatUI.AddCombatLog("你对" .. monsterName_ .. "造成了 " .. NumFormat.Short(dmgToMonster) .. " 点伤害")

    -- 出战宠物攻击怪物
    for _, pet in ipairs(combatPets_) do
        if pet.alive then
            local petDmg = BigNum.max("1", BigNum.add(BigNum.sub(pet.atk, monsterDef_), tostring(math.random(-1, 2))))
            monsterHp_ = BigNum.sub(monsterHp_, petDmg)
            CombatUI.AddCombatLog("宠物【" .. pet.name .. "】攻击，造成 " .. NumFormat.Short(petDmg) .. " 点伤害")
        end
    end

    -- 检查怪物是否死亡
    if BigNum.lte(monsterHp_, "0") then
        monsterHp_ = "0"
        CombatUI.Victory()
        return
    end

    -- 怪物攻击：优先攻击存活的宠物，宠物全部阵亡后攻击玩家
    local targetPet = nil
    for _, pet in ipairs(combatPets_) do
        if pet.alive then
            targetPet = pet
            break
        end
    end

    if targetPet then
        -- 怪物攻击宠物
        local dmgToPet = BigNum.max("1", BigNum.add(BigNum.sub(monsterAtk_, targetPet.def), tostring(math.random(-2, 3))))
        targetPet.hp = BigNum.sub(targetPet.hp, dmgToPet)
        CombatUI.AddCombatLog(monsterName_ .. "攻击宠物【" .. targetPet.name .. "】，造成 " .. NumFormat.Short(dmgToPet) .. " 点伤害")

        if BigNum.lte(targetPet.hp, "0") then
            targetPet.hp = "0"
            targetPet.alive = false
            CombatUI.AddCombatLog("宠物【" .. targetPet.name .. "】已阵亡！")
        end
    else
        -- 无存活宠物，怪物攻击玩家
        local dmgToPlayer = BigNum.max("1", BigNum.add(BigNum.sub(monsterAtk_, playerDef), tostring(math.random(-2, 3))))
        player.status.hp = BigNum.sub(BigNum.new(player.status.hp or "100"), dmgToPlayer)
        CombatUI.AddCombatLog(monsterName_ .. "对你造成了 " .. NumFormat.Short(dmgToPlayer) .. " 点伤害")

        -- 检查玩家是否死亡
        if BigNum.lte(player.status.hp, "0") then
            player.status.hp = "0"
            CombatUI.Defeat()
            return
        end
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
            local maxHp = CalcPlayerMaxHp()
            player.status.hp = BigNum.min(BigNum.add(player.status.hp or "0", healValue), maxHp)

            item.count = BigNum.sub(item.count or "1", "1")
            if BigNum.lte(item.count, "0") then
                table.remove(player.bag, i)
            end

            CombatUI.AddCombatLog("使用了" .. item.name .. "，恢复" .. NumFormat.Short(healValue) .. "生命")

            -- 怪物趁机攻击：优先攻击宠物
            local potionTargetPet = nil
            for _, pet in ipairs(combatPets_) do
                if pet.alive then
                    potionTargetPet = pet
                    break
                end
            end

            if potionTargetPet then
                local dmg = BigNum.max("1", BigNum.add(BigNum.sub(monsterAtk_, potionTargetPet.def), tostring(math.random(-1, 2))))
                potionTargetPet.hp = BigNum.sub(potionTargetPet.hp, dmg)
                CombatUI.AddCombatLog(monsterName_ .. "趁机攻击宠物【" .. potionTargetPet.name .. "】，造成 " .. NumFormat.Short(dmg) .. " 伤害")
                if BigNum.lte(potionTargetPet.hp, "0") then
                    potionTargetPet.hp = "0"
                    potionTargetPet.alive = false
                    CombatUI.AddCombatLog("宠物【" .. potionTargetPet.name .. "】已阵亡！")
                end
            else
                local StatusUI = require("UI.StatusUI")
                local BagUI = require("UI.BagUI")
                local _, eDef, _ = StatusUI.GetEquipBonus()
                local buffDef = BagUI.GetBuffValue(player, "防御")
                local _, rDef3, _ = DataManager.GetRealmBonus()
                local soulBonus3 = DataManager.GetBattleSoulBonus(player.status.battle_soul_level)
                local playerDef = BigNum.add(BigNum.add(BigNum.add(BigNum.add(player.status.def or "3", tostring(eDef)), tostring(buffDef)), rDef3), soulBonus3.def)
                local dmg = BigNum.max("1", BigNum.add(BigNum.sub(monsterAtk_, playerDef), tostring(math.random(-1, 2))))
                player.status.hp = BigNum.sub(BigNum.new(player.status.hp or "100"), dmg)
                CombatUI.AddCombatLog(monsterName_ .. "趁机攻击，造成 " .. NumFormat.Short(dmg) .. " 伤害")

                if BigNum.lte(player.status.hp, "0") then
                    player.status.hp = "0"
                    CombatUI.Defeat()
                    return
                end
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

    -- 战魂奖励
    local soulMin, soulMax = DataManager.GetBattleSoulRange(monsterName_)
    local soulGain = tostring(math.random(soulMin, math.max(soulMin, soulMax)))
    player.status.battle_soul_exp = BigNum.add(player.status.battle_soul_exp or "0", soulGain)
    -- 战魂自动升级检测（限制单次最多升1000级防卡）
    local soulLeveledUp = false
    local curSoulLv = tonumber(player.status.battle_soul_level) or 0
    local soulUpCount = 0
    local needSoulExp = DataManager.GetBattleSoulExpNeeded(curSoulLv)
    while BigNum.gte(player.status.battle_soul_exp, needSoulExp) and soulUpCount < 1000 do
        player.status.battle_soul_exp = BigNum.sub(player.status.battle_soul_exp, needSoulExp)
        curSoulLv = curSoulLv + 1
        player.status.battle_soul_level = tostring(curSoulLv)
        soulLeveledUp = true
        soulUpCount = soulUpCount + 1
        needSoulExp = DataManager.GetBattleSoulExpNeeded(curSoulLv)
    end
    -- 战魂升级后回满生命（使用完整计算的生命上限）
    if soulLeveledUp then
        player.status.hp = CalcPlayerMaxHp()
    end

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

    -- 出战宠物获得经验（与玩家相同的基础经验）
    local petExpGainList = {}
    if player.pets then
        for _, pet in ipairs(player.pets) do
            if pet.deployed then
                local petExpGain = expGain
                pet.exp = BigNum.add(pet.exp or "0", petExpGain)
                table.insert(petExpGainList, pet.name)
                -- 宠物升级：二分搜索 + 闭合求和（O(log n)，不会卡）
                -- 宠物经验公式: 50*lv*(1+lv*0.2) = 10*lv² + 50*lv
                -- 闭合求和: sum(10*i²+50*i, i=a..b) = 10*SumOfPowers(b,2) + 50*SumOfPowers(b,1) - 同(a-1)
                local petLv = tonumber(pet.level) or 1
                local petNeedExp = tostring(math.floor(50 * petLv * (1 + petLv * 0.2)))
                if BigNum.gte(pet.exp, petNeedExp) then
                    -- 闭合求和: 从 petLv 升到 targetLv 需要的总经验
                    local function petTotalExp(fromLv, toLv)
                        if toLv <= fromLv then return "0" end
                        -- sum(10*i²+50*i, i=fromLv..toLv-1)
                        local s2High = DataManager.SumOfPowers(toLv - 1, 2)
                        local s2Low = DataManager.SumOfPowers(fromLv - 1, 2)
                        local s1High = DataManager.SumOfPowers(toLv - 1, 1)
                        local s1Low = DataManager.SumOfPowers(fromLv - 1, 1)
                        local sum2 = BigNum.mul("10", BigNum.sub(s2High, s2Low))
                        local sum1 = BigNum.mul("50", BigNum.sub(s1High, s1Low))
                        return BigNum.add(sum2, sum1)
                    end
                    -- 二分搜索目标等级（单次最多升10000级，防属性计算过慢）
                    local lo = petLv + 1
                    local hi = petLv + 10000
                    while lo < hi do
                        local mid = math.floor((lo + hi + 1) / 2)
                        local cost = petTotalExp(petLv, mid)
                        if BigNum.gte(pet.exp, cost) then
                            lo = mid
                        else
                            hi = mid - 1
                        end
                    end
                    local targetPetLv = lo
                    if targetPetLv > petLv then
                        local totalCost = petTotalExp(petLv, targetPetLv)
                        pet.exp = BigNum.sub(pet.exp, totalCost)
                        local levelsGained = targetPetLv - petLv
                        -- 批量计算属性增量: atk += sum(floor(2+i*0.5)), def += sum(floor(1+i*0.3)), hp += sum(floor(10+i*2))
                        local totalAtkAdd = 0
                        local totalDefAdd = 0
                        local totalHpAdd = 0
                        for i = petLv, targetPetLv - 1 do
                            totalAtkAdd = totalAtkAdd + math.floor(2 + i * 0.5)
                            totalDefAdd = totalDefAdd + math.floor(1 + i * 0.3)
                            totalHpAdd = totalHpAdd + math.floor(10 + i * 2)
                        end
                        pet.atk = BigNum.add(pet.atk or "10", tostring(totalAtkAdd))
                        pet.def = BigNum.add(pet.def or "5", tostring(totalDefAdd))
                        pet.max_hp = BigNum.add(pet.max_hp or "100", tostring(totalHpAdd))
                        pet.level = tostring(targetPetLv)
                        print("[Combat] 宠物 " .. pet.name .. " 升级到 Lv." .. targetPetLv .. "（连升" .. levelsGained .. "级）")
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
    -- 战魂日志
    GameUI.AddLog("获得战魂 +" .. NumFormat.Short(soulGain))
    if soulLeveledUp then
        GameUI.AddLog("战魂升级！当前等级：" .. player.status.battle_soul_level)
    end
    -- 宠物经验日志
    if #petExpGainList > 0 then
        GameUI.AddLog("宠物获得经验 +" .. NumFormat.Short(expGain) .. "：" .. table.concat(petExpGainList, "、"))
    end
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
                UI.Label { text = "获得战魂：+" .. NumFormat.Short(soulGain) .. (soulLeveledUp and "  (战魂升级！Lv." .. player.status.battle_soul_level .. ")" or ""), fontSize = 13, fontColor = { 200, 150, 255, 255 } },
                #petExpGainList > 0 and UI.Label {
                    text = "宠物经验：+" .. NumFormat.Short(expGain) .. "（" .. table.concat(petExpGainList, "、") .. "）",
                    fontSize = 13,
                    fontColor = { 180, 255, 180, 255 },
                } or UI.Panel { height = 0 },
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
    player.status.hp = CalcPlayerMaxHp()

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

--- 添加战斗日志（以弹窗形式显示）
---@param msg string
function CombatUI.AddCombatLog(msg)
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
