---------------------------------------------------
-- PetUI.lua - 宠物系统
-- 功能：宠物列表、详情、升级、升星、进阶、品质、装备、出战
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local BigNum = require("Utils.BigNum")
local NumFormat = require("Utils.NumFormat")

local PetUI = {}

local parentRef_ = nil

--- 品质颜色映射
local QUALITY_COLORS = {
    ["白"] = { 200, 200, 200, 255 },
    ["绿"] = { 100, 220, 100, 255 },
    ["蓝"] = { 80, 160, 255, 255 },
    ["紫"] = { 180, 100, 255, 255 },
    ["橙"] = { 255, 165, 0, 255 },
    ["红"] = { 255, 60, 60, 255 },
    ["金"] = { 255, 215, 0, 255 },
    ["圣"] = { 255, 255, 180, 255 },
    ["仙"] = { 180, 255, 255, 255 },
    ["神"] = { 255, 200, 255, 255 },
}

--- 品质升级链映射
local QUALITY_NEXT_MAP = { ["白"] = "绿", ["绿"] = "蓝", ["蓝"] = "紫", ["紫"] = "橙", ["橙"] = "红", ["红"] = "金", ["金"] = "圣", ["圣"] = "仙", ["仙"] = "神" }

--- 品质定义（从品质消耗配置动态获取，保证与后台同步）
local DEFAULT_QUALITY_ORDER = { "白", "绿", "蓝", "紫", "橙", "红", "金", "圣", "仙", "神" }

local function GetQualityList()
    local pc = DataManager.petConfig or {}
    local qCost = pc.quality_cost or {}
    -- 收集配置中存在的品质（key + 目标品质）
    local qualSet = {}
    local qualRaw = {}
    for qName, _ in pairs(qCost) do
        if not qualSet[qName] then
            qualSet[qName] = true
            table.insert(qualRaw, qName)
        end
        local nextQ = QUALITY_NEXT_MAP[qName]
        if nextQ and not qualSet[nextQ] then
            qualSet[nextQ] = true
            table.insert(qualRaw, nextQ)
        end
    end
    if #qualRaw == 0 then
        return DEFAULT_QUALITY_ORDER
    end
    -- 按固定顺序排列
    local sorted = {}
    local sortedSet = {}
    for _, q in ipairs(DEFAULT_QUALITY_ORDER) do
        if qualSet[q] then
            table.insert(sorted, q)
            sortedSet[q] = true
        end
    end
    -- 补充自定义品质（不在固定顺序中的）
    for _, q in ipairs(qualRaw) do
        if not sortedSet[q] then
            table.insert(sorted, q)
        end
    end
    return sorted
end

--- 宠物装备部位
local PET_EQUIP_SLOTS = { "项圈", "护甲", "爪套", "铃铛" }

--- 获取品质索引
local function GetQualityIndex(quality)
    local list = GetQualityList()
    for i, q in ipairs(list) do
        if q == quality then return i end
    end
    return 1
end

--- 获取品质颜色
local function GetQualityColor(quality)
    return QUALITY_COLORS[quality] or QUALITY_COLORS["白"]
end

--- 升级所需经验（等级越高越多）
local function GetLevelUpExp(level)
    local lv = tonumber(level) or 1
    return tostring(math.floor(50 * lv * (1 + lv * 0.2)))
end

--- 升星所需金币（星级越高越贵）
local function GetStarUpCost(star)
    local s = tonumber(star) or 0
    return tostring(math.floor(200 * (s + 1) ^ 2))
end

--- 进阶所需材料数量（公式：base + growth × 当前阶数，无上限）
local function GetAdvanceCost(stage)
    local st = tonumber(stage) or 0
    local config = DataManager.petConfig
    local base = tonumber(config.adv_cost_base) or 30
    local growth = tonumber(config.adv_cost_growth) or 20
    return tostring(math.floor(base + growth * st))
end

--- 品质提升所需金币
local function GetQualityUpCost(quality)
    local idx = GetQualityIndex(quality)
    return tostring(math.floor(500 * idx ^ 2))
end

--- 递增公式（BigNum版）：前N级总加成 = N*base + growth*N*(N-1)/2
--- 返回字符串（BigNum格式）
local function CalcBonusSum(base, growth, n)
    if n <= 0 then return "0" end
    local sn = tostring(n)
    -- N * base
    local part1 = BigNum.mul(sn, tostring(base))
    -- growth * N * (N-1) / 2
    local nm1 = tostring(n - 1)
    local part2 = BigNum.mul(tostring(growth), BigNum.mul(sn, nm1))
    part2 = BigNum.div(part2, "2")
    return BigNum.add(part1, part2)
end

--- 计算第N级的单次加成（供UI显示用）：base + growth × (N-1)
local function CalcBonusAt(base, growth, n)
    if n <= 0 then return tostring(base) end
    return tostring(base + growth * (n - 1))
end

--- 计算宠物战力（BigNum版），返回3个BigNum字符串
local function CalcPetPower(pet)
    local baseAtk = tostring(tonumber(pet.atk) or 10)
    local baseDef = tostring(tonumber(pet.def) or 5)
    local baseHp = tostring(tonumber(pet.max_hp) or 100)
    local level = tonumber(pet.level) or 1
    local star = tonumber(pet.star) or 0
    local stage = tonumber(pet.stage) or 0
    local qualityIdx = GetQualityIndex(pet.quality or "白")

    local config = DataManager.petConfig
    local sb = config.star_bonus or {}
    local ab = config.advance_bonus or {}
    local qb = config.quality_bonus or {}

    -- 递增加成总和（BigNum字符串）
    local starAtk = CalcBonusSum(tonumber(sb.atk) or 10, tonumber(sb.atk_g) or 5, star)
    local starDef = CalcBonusSum(tonumber(sb.def) or 6, tonumber(sb.def_g) or 3, star)
    local starHp = CalcBonusSum(tonumber(sb.hp) or 50, tonumber(sb.hp_g) or 25, star)

    local advAtk = CalcBonusSum(tonumber(ab.atk) or 20, tonumber(ab.atk_g) or 10, stage)
    local advDef = CalcBonusSum(tonumber(ab.def) or 12, tonumber(ab.def_g) or 6, stage)
    local advHp = CalcBonusSum(tonumber(ab.hp) or 100, tonumber(ab.hp_g) or 50, stage)

    local qn = qualityIdx - 1
    local qualAtk = CalcBonusSum(tonumber(qb.atk) or 15, tonumber(qb.atk_g) or 8, qn)
    local qualDef = CalcBonusSum(tonumber(qb.def) or 8, tonumber(qb.def_g) or 4, qn)
    local qualHp = CalcBonusSum(tonumber(qb.hp) or 60, tonumber(qb.hp_g) or 30, qn)

    -- 装备加成
    local equipAtk, equipDef, equipHp = "0", "0", "0"
    if pet.equip then
        for _, slot in ipairs(PET_EQUIP_SLOTS) do
            local itemName = pet.equip[slot]
            if itemName and itemName ~= "" then
                local itemData = DataManager.GetItem(itemName)
                if itemData then
                    equipAtk = BigNum.add(equipAtk, tostring(tonumber(itemData.pet_atk) or 5))
                    equipDef = BigNum.add(equipDef, tostring(tonumber(itemData.pet_def) or 3))
                    equipHp = BigNum.add(equipHp, tostring(tonumber(itemData.pet_hp) or 20))
                end
            end
        end
    end

    -- 等级成长
    local lvlAtk = tostring(level * 3)
    local lvlDef = tostring(level * 2)
    local lvlHp = tostring(level * 15)

    -- 总计：基础 + 等级成长 + 升星 + 进阶 + 品质 + 装备
    local totalAtk = BigNum.add(baseAtk, BigNum.add(lvlAtk, BigNum.add(starAtk, BigNum.add(advAtk, BigNum.add(qualAtk, equipAtk)))))
    local totalDef = BigNum.add(baseDef, BigNum.add(lvlDef, BigNum.add(starDef, BigNum.add(advDef, BigNum.add(qualDef, equipDef)))))
    local totalHp = BigNum.add(baseHp, BigNum.add(lvlHp, BigNum.add(starHp, BigNum.add(advHp, BigNum.add(qualHp, equipHp)))))

    return totalAtk, totalDef, totalHp
end

--- 确保玩家有宠物数据结构
local function EnsurePetData(player)
    if not player.pets then
        player.pets = {}      -- { {name, level, exp, star, stage, quality, deployed, equip={}, atk, def, max_hp}, ... }
    end
    if not player.pet_deployed then
        player.pet_deployed = {} -- 出战宠物索引列表，最多3个
    end
end

--- 渲染宠物面板
---@param parent Widget
function PetUI.Render(parent)
    parentRef_ = parent
    PetUI.ShowList()
end

--- 刷新
function PetUI.Refresh()
    if not parentRef_ then return end
    PetUI.ShowList()
end

--- 宠物列表视图
function PetUI.ShowList()
    if not parentRef_ then return end
    parentRef_:ClearChildren()

    local player = DataManager.playerData
    if not player then return end
    EnsurePetData(player)

    -- 标题
    parentRef_:AddChild(UI.Label {
        text = "— 宠物 —",
        fontSize = 16,
        fontColor = { 200, 170, 100, 255 },
        textAlign = "center",
        marginTop = 8,
    })

    -- 出战信息
    local deployCount = 0
    for _, pet in ipairs(player.pets) do
        if pet.deployed then deployCount = deployCount + 1 end
    end
    parentRef_:AddChild(UI.Label {
        text = "出战: " .. deployCount .. "/3",
        fontSize = 12,
        fontColor = { 180, 220, 255, 255 },
        textAlign = "center",
        marginBottom = 6,
    })

    if #player.pets == 0 then
        parentRef_:AddChild(UI.Label {
            text = "暂无宠物，可通过商城或副本获得",
            fontSize = 13,
            fontColor = { 120, 120, 140, 255 },
            textAlign = "center",
            marginTop = 20,
        })
        return
    end

    -- 宠物列表
    for i, pet in ipairs(player.pets) do
        local qualityColor = GetQualityColor(pet.quality or "白")
        local petAtk, petDef, petHp = CalcPetPower(pet)
        local power = BigNum.add(petAtk, BigNum.add(petDef, BigNum.div(petHp, "5")))

        local stateText = pet.deployed and " [出战中]" or ""
        local starStr = tostring(tonumber(pet.star) or 0) .. "☆"

        parentRef_:AddChild(UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            width = "100%",
            padding = 6,
            gap = 6,
            backgroundColor = pet.deployed and { 30, 50, 40, 220 } or { 25, 20, 45, 200 },
            borderRadius = 4,
            marginBottom = 4,
            children = {
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    flexDirection = "column",
                    children = {
                        UI.Label {
                            text = pet.name .. " Lv." .. (pet.level or "1") .. stateText,
                            fontSize = 14,
                            fontColor = qualityColor,
                        },
                        UI.Label {
                            text = starStr .. " | " .. (pet.quality or "白") .. "品 | 阶:" .. (pet.stage or "0") .. " | 战力:" .. NumFormat.Short(power),
                            fontSize = 11,
                            fontColor = { 160, 160, 180, 255 },
                        },
                    },
                },
                UI.Button {
                    text = "详情",
                    variant = "secondary",
                    height = 28,
                    onClick = function() PetUI.ShowDetail(i) end,
                },
            },
        })
    end
end

--- 宠物详情视图
---@param index number 宠物在列表中的索引
function PetUI.ShowDetail(index)
    if not parentRef_ then return end
    parentRef_:ClearChildren()

    local player = DataManager.playerData
    if not player then return end
    EnsurePetData(player)

    local pet = player.pets[index]
    if not pet then
        PetUI.ShowList()
        return
    end

    local qualityColor = GetQualityColor(pet.quality or "白")
    local petAtk, petDef, petHp = CalcPetPower(pet)

    -- 返回按钮
    parentRef_:AddChild(UI.Button {
        text = "← 返回列表",
        variant = "secondary",
        height = 26,
        marginBottom = 8,
        onClick = function() PetUI.ShowList() end,
    })

    -- 宠物名称与品质
    local starStr = tostring(tonumber(pet.star) or 0) .. "☆"

    parentRef_:AddChild(UI.Label {
        text = pet.name,
        fontSize = 18,
        fontColor = qualityColor,
        textAlign = "center",
    })
    parentRef_:AddChild(UI.Label {
        text = (pet.quality or "白") .. "品 | " .. starStr .. " | 阶:" .. (pet.stage or "0"),
        fontSize = 13,
        fontColor = { 180, 180, 200, 255 },
        textAlign = "center",
        marginBottom = 6,
    })

    -- 属性面板（含递增加成明细）
    local config = DataManager.petConfig
    local sb = config.star_bonus or {}
    local ab = config.advance_bonus or {}
    local qb = config.quality_bonus or {}
    local star = tonumber(pet.star) or 0
    local stage = tonumber(pet.stage) or 0
    local qualityIdx = GetQualityIndex(pet.quality or "白")

    -- 当前各系统总加成
    local curStarAtk = CalcBonusSum(tonumber(sb.atk) or 10, tonumber(sb.atk_g) or 5, star)
    local curStarDef = CalcBonusSum(tonumber(sb.def) or 6, tonumber(sb.def_g) or 3, star)
    local curStarHp = CalcBonusSum(tonumber(sb.hp) or 50, tonumber(sb.hp_g) or 25, star)
    local curAdvAtk = CalcBonusSum(tonumber(ab.atk) or 20, tonumber(ab.atk_g) or 10, stage)
    local curAdvDef = CalcBonusSum(tonumber(ab.def) or 12, tonumber(ab.def_g) or 6, stage)
    local curAdvHp = CalcBonusSum(tonumber(ab.hp) or 100, tonumber(ab.hp_g) or 50, stage)
    local qn = qualityIdx - 1
    local curQualAtk = CalcBonusSum(tonumber(qb.atk) or 15, tonumber(qb.atk_g) or 8, qn)
    local curQualDef = CalcBonusSum(tonumber(qb.def) or 8, tonumber(qb.def_g) or 4, qn)
    local curQualHp = CalcBonusSum(tonumber(qb.hp) or 60, tonumber(qb.hp_g) or 30, qn)

    -- 下次升级的单次加成（递增：第N+1级 = base + growth*N）
    local nextStarAtk = CalcBonusAt(tonumber(sb.atk) or 10, tonumber(sb.atk_g) or 5, star + 1)
    local nextStarDef = CalcBonusAt(tonumber(sb.def) or 6, tonumber(sb.def_g) or 3, star + 1)
    local nextStarHp = CalcBonusAt(tonumber(sb.hp) or 50, tonumber(sb.hp_g) or 25, star + 1)
    local nextAdvAtk = CalcBonusAt(tonumber(ab.atk) or 20, tonumber(ab.atk_g) or 10, stage + 1)
    local nextAdvDef = CalcBonusAt(tonumber(ab.def) or 12, tonumber(ab.def_g) or 6, stage + 1)
    local nextAdvHp = CalcBonusAt(tonumber(ab.hp) or 100, tonumber(ab.hp_g) or 50, stage + 1)
    local nextQualAtk = CalcBonusAt(tonumber(qb.atk) or 15, tonumber(qb.atk_g) or 8, qn + 1)
    local nextQualDef = CalcBonusAt(tonumber(qb.def) or 8, tonumber(qb.def_g) or 4, qn + 1)
    local nextQualHp = CalcBonusAt(tonumber(qb.hp) or 60, tonumber(qb.hp_g) or 30, qn + 1)

    parentRef_:AddChild(UI.Panel {
        width = "100%",
        backgroundColor = { 30, 25, 50, 200 },
        borderRadius = 4,
        padding = 8,
        marginBottom = 6,
        children = {
            UI.Label { text = "等级: " .. (pet.level or "1") .. "  经验: " .. (pet.exp or "0") .. "/" .. GetLevelUpExp(pet.level or "1"), fontSize = 12, fontColor = { 200, 200, 220, 255 } },
            UI.Label { text = "攻击: " .. NumFormat.Short(petAtk) .. "  防御: " .. NumFormat.Short(petDef) .. "  生命: " .. NumFormat.Short(petHp), fontSize = 13, fontColor = { 100, 255, 200, 255 }, marginTop = 4 },
            UI.Label {
                text = "  升星+" .. NumFormat.Short(curStarAtk) .. "/" .. NumFormat.Short(curStarDef) .. "/" .. NumFormat.Short(curStarHp)
                    .. "  进阶+" .. NumFormat.Short(curAdvAtk) .. "/" .. NumFormat.Short(curAdvDef) .. "/" .. NumFormat.Short(curAdvHp)
                    .. "  品质+" .. NumFormat.Short(curQualAtk) .. "/" .. NumFormat.Short(curQualDef) .. "/" .. NumFormat.Short(curQualHp),
                fontSize = 10, fontColor = { 160, 160, 180, 255 }, marginTop = 2,
            },
            UI.Label {
                text = "  下次升星: 攻+" .. nextStarAtk .. " 防+" .. nextStarDef .. " 血+" .. nextStarHp
                    .. " | 下次进阶: 攻+" .. nextAdvAtk .. " 防+" .. nextAdvDef .. " 血+" .. nextAdvHp,
                fontSize = 10, fontColor = { 255, 220, 120, 255 }, marginTop = 2,
            },
        },
    })

    -- 装备栏
    parentRef_:AddChild(UI.Label {
        text = "— 装备 —",
        fontSize = 13,
        fontColor = { 200, 170, 100, 255 },
        textAlign = "center",
        marginTop = 4, marginBottom = 4,
    })
    if not pet.equip then pet.equip = {} end
    for _, slot in ipairs(PET_EQUIP_SLOTS) do
        local equipName = pet.equip[slot] or ""
        local displayName = equipName ~= "" and equipName or "(空)"
        local displayColor = equipName ~= "" and { 180, 220, 255, 255 } or { 100, 100, 120, 255 }

        parentRef_:AddChild(UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            width = "100%",
            padding = 4,
            gap = 4,
            children = {
                UI.Label { text = slot .. ":", fontSize = 12, fontColor = { 160, 160, 180, 255 }, width = 50 },
                UI.Label { text = displayName, fontSize = 12, fontColor = displayColor, flexGrow = 1 },
                UI.Button {
                    text = equipName ~= "" and "卸下" or "穿戴",
                    variant = equipName ~= "" and "danger" or "primary",
                    height = 24,
                    onClick = function()
                        if equipName ~= "" then
                            PetUI.UnequipSlot(index, slot)
                        else
                            PetUI.ShowEquipSelect(index, slot)
                        end
                    end,
                },
            },
        })
    end

    -- 操作按钮
    parentRef_:AddChild(UI.Label {
        text = "— 操作 —",
        fontSize = 13,
        fontColor = { 200, 170, 100, 255 },
        textAlign = "center",
        marginTop = 8, marginBottom = 4,
    })

    -- 升星
    local starMax = tonumber(DataManager.petConfig.star_max_level) or 30
    local curStar = tonumber(pet.star) or 0
    if curStar < starMax then
        local starMatName, starMatCount = PetUI.GetStarCostMaterial(pet.star or "0")
        parentRef_:AddChild(UI.Panel {
            width = "100%", marginBottom = 4,
            children = {
                UI.Panel {
                    flexDirection = "row", width = "100%", gap = 4,
                    children = {
                        UI.Button {
                            text = "升星 (需" .. starMatCount .. "个" .. starMatName .. ")",
                            variant = "secondary",
                            flexGrow = 1, height = 30,
                            onClick = function() PetUI.StarUp(index) end,
                        },
                    },
                },
                UI.Label {
                    text = "  属性增加: 攻+" .. nextStarAtk .. " 防+" .. nextStarDef .. " 血+" .. nextStarHp,
                    fontSize = 10, fontColor = { 120, 200, 120, 255 }, marginTop = 1,
                },
            },
        })
    else
        parentRef_:AddChild(UI.Label {
            text = "升星已满（" .. starMax .. "星）",
            fontSize = 12, fontColor = { 255, 60, 60, 255 }, textAlign = "center", marginBottom = 4,
        })
    end

    -- 进阶
    local advMax = tonumber(DataManager.petConfig.adv_max_level) or 10
    local curStage = tonumber(pet.stage) or 0
    if curStage < advMax then
        local advCost = GetAdvanceCost(pet.stage or "0")
        local advMatName = DataManager.petConfig.adv_cost_material or "进阶丹"
        parentRef_:AddChild(UI.Panel {
            width = "100%", marginBottom = 4,
            children = {
                UI.Panel {
                    flexDirection = "row", width = "100%", gap = 4,
                    children = {
                        UI.Button {
                            text = "进阶 (需" .. advCost .. "个" .. advMatName .. ")",
                            variant = "secondary",
                            flexGrow = 1, height = 30,
                            onClick = function() PetUI.Advance(index) end,
                        },
                    },
                },
                UI.Label {
                    text = "  属性增加: 攻+" .. nextAdvAtk .. " 防+" .. nextAdvDef .. " 血+" .. nextAdvHp,
                    fontSize = 10, fontColor = { 120, 200, 120, 255 }, marginTop = 1,
                },
            },
        })
    else
        parentRef_:AddChild(UI.Label {
            text = "进阶已满（" .. advMax .. "阶）",
            fontSize = 12, fontColor = { 255, 60, 60, 255 }, textAlign = "center", marginBottom = 4,
        })
    end

    -- 提升品质
    local qualList = GetQualityList()
    local qIdx = GetQualityIndex(pet.quality or "白")
    if qIdx < #qualList then
        local qMatName, qMatCount = PetUI.GetQualityCostMaterial(pet.quality or "白")
        local nextQ = qualList[qIdx + 1]
        parentRef_:AddChild(UI.Panel {
            width = "100%", marginBottom = 4,
            children = {
                UI.Panel {
                    flexDirection = "row", width = "100%", gap = 4,
                    children = {
                        UI.Button {
                            text = "提升品质→" .. nextQ .. " (需" .. qMatCount .. "个" .. qMatName .. ")",
                            variant = "secondary",
                            flexGrow = 1, height = 30,
                            onClick = function() PetUI.QualityUp(index) end,
                        },
                    },
                },
                UI.Label {
                    text = "  属性增加: 攻+" .. nextQualAtk .. " 防+" .. nextQualDef .. " 血+" .. nextQualHp,
                    fontSize = 10, fontColor = { 120, 200, 120, 255 }, marginTop = 1,
                },
            },
        })
    else
        parentRef_:AddChild(UI.Label {
            text = "品质已满",
            fontSize = 12, fontColor = { 255, 60, 60, 255 }, textAlign = "center",
        })
    end

    -- 出战/收回
    parentRef_:AddChild(UI.Panel {
        flexDirection = "row", width = "100%", gap = 4, marginTop = 6,
        children = {
            UI.Button {
                text = pet.deployed and "收回" or "出战",
                variant = pet.deployed and "danger" or "success",
                flexGrow = 1, height = 32,
                onClick = function() PetUI.ToggleDeploy(index) end,
            },
        },
    })
end

--- 获取升星消耗材料（从云端配置读取，格式"材料名:数量"）
---@param star string 当前星级
---@return string matName 材料名
---@return string matCount 数量
--- 升星消耗（公式：base + growth × 当前星级，无上限）
function PetUI.GetStarCostMaterial(star)
    local s = tonumber(star) or 0
    local config = DataManager.petConfig
    local matName = config.star_cost_material or "升星石"
    local base = tonumber(config.star_cost_base) or 100
    local growth = tonumber(config.star_cost_growth) or 100
    local count = math.floor(base + growth * s)
    return matName, tostring(count)
end

--- 获取品质提升消耗材料（从云端配置读取，格式"材料名:数量"）
---@param quality string 当前品质
---@return string matName 材料名
---@return string matCount 数量
function PetUI.GetQualityCostMaterial(quality)
    local cfg = DataManager.petConfig.quality_cost or {}
    local qIdx = GetQualityIndex(quality)
    local costStr = cfg[quality] or cfg[tostring(qIdx)]
    if costStr and costStr:find(":") then
        local name, count = costStr:match("^(.+):(%d+)$")
        if name and count then return name, count end
    end
    -- 默认：品质精华，数量=品质序号*2
    return "品质精华", tostring(qIdx * 2)
end

--- 升星
function PetUI.StarUp(index)
    local player = DataManager.playerData
    if not player then return end
    local pet = player.pets[index]
    if not pet then return end

    -- 检查升星上限
    local starMax = tonumber(DataManager.petConfig.star_max_level) or 30
    local curStar = tonumber(pet.star) or 0
    if curStar >= starMax then
        PetUI.ShowTip("已达升星上限（" .. starMax .. "星）")
        return
    end

    local matName, matCount = PetUI.GetStarCostMaterial(pet.star or "0")
    -- 查找背包中的材料
    local matIdx = nil
    for i, item in ipairs(player.bag) do
        if item.name == matName then
            if BigNum.gte(item.count or "0", matCount) then
                matIdx = i
            end
            break
        end
    end

    if not matIdx then
        PetUI.ShowTip(matName .. "不足，需要 " .. matCount .. " 个")
        return
    end

    -- 扣除材料
    local item = player.bag[matIdx]
    item.count = BigNum.sub(item.count, matCount)
    if BigNum.lte(item.count, "0") then
        table.remove(player.bag, matIdx)
    end

    pet.star = tostring((tonumber(pet.star) or 0) + 1)

    print("[PetUI] " .. pet.name .. " 升星到 " .. pet.star .. "星")
    DataManager.SaveToCloud(player)
    PetUI.ShowDetail(index)
    PetUI.ShowTip(pet.name .. " 升星到 " .. pet.star .. "☆！")
end

--- 进阶（最高10阶）
function PetUI.Advance(index)
    local player = DataManager.playerData
    if not player then return end
    local pet = player.pets[index]
    if not pet then return end

    -- 检查进阶上限
    local advMax = tonumber(DataManager.petConfig.adv_max_level) or 10
    local curStage = tonumber(pet.stage) or 0
    if curStage >= advMax then
        PetUI.ShowTip("已达进阶上限（" .. advMax .. "阶）")
        return
    end

    local needCount = GetAdvanceCost(pet.stage or "0")
    local matName = DataManager.petConfig.adv_cost_material or "进阶丹"
    -- 查找背包中的进阶材料
    local matIdx = nil
    for i, item in ipairs(player.bag) do
        if item.name == matName then
            if BigNum.gte(item.count, needCount) then
                matIdx = i
                break
            end
        end
    end

    if not matIdx then
        PetUI.ShowTip(matName .. "不足，需要 " .. needCount .. " 个")
        return
    end

    -- 扣除材料
    local item = player.bag[matIdx]
    item.count = BigNum.sub(item.count, needCount)
    if BigNum.lte(item.count, "0") then
        table.remove(player.bag, matIdx)
    end

    pet.stage = tostring((tonumber(pet.stage) or 0) + 1)

    print("[PetUI] " .. pet.name .. " 进阶到 " .. pet.stage .. " 阶")
    DataManager.SaveToCloud(player)
    PetUI.ShowDetail(index)
    PetUI.ShowTip(pet.name .. " 进阶到 " .. pet.stage .. " 阶！")
end

--- 品质提升
function PetUI.QualityUp(index)
    local player = DataManager.playerData
    if not player then return end
    local pet = player.pets[index]
    if not pet then return end

    local qualList = GetQualityList()
    local qIdx = GetQualityIndex(pet.quality or "白")
    if qIdx >= #qualList then
        PetUI.ShowTip("品质已达上限")
        return
    end

    local matName, matCount = PetUI.GetQualityCostMaterial(pet.quality or "白")
    -- 查找背包中的材料
    local matIdx = nil
    for i, item in ipairs(player.bag) do
        if item.name == matName then
            if BigNum.gte(item.count or "0", matCount) then
                matIdx = i
            end
            break
        end
    end

    if not matIdx then
        PetUI.ShowTip(matName .. "不足，需要 " .. matCount .. " 个")
        return
    end

    -- 扣除材料
    local item = player.bag[matIdx]
    item.count = BigNum.sub(item.count, matCount)
    if BigNum.lte(item.count, "0") then
        table.remove(player.bag, matIdx)
    end

    pet.quality = qualList[qIdx + 1]

    print("[PetUI] " .. pet.name .. " 品质提升到 " .. pet.quality .. "品")
    DataManager.SaveToCloud(player)
    PetUI.ShowDetail(index)
    PetUI.ShowTip(pet.name .. " 品质提升到 " .. pet.quality .. "品！")
end

--- 出战/收回切换
function PetUI.ToggleDeploy(index)
    local player = DataManager.playerData
    if not player then return end
    local pet = player.pets[index]
    if not pet then return end

    if pet.deployed then
        -- 收回
        pet.deployed = false
        print("[PetUI] " .. pet.name .. " 已收回")
        DataManager.SaveToCloud(player)
        PetUI.ShowDetail(index)
        PetUI.ShowTip(pet.name .. " 已收回")
    else
        -- 检查出战数量
        local deployCount = 0
        for _, p in ipairs(player.pets) do
            if p.deployed then deployCount = deployCount + 1 end
        end
        if deployCount >= 3 then
            PetUI.ShowTip("最多出战3只宠物，请先收回一只")
            return
        end

        pet.deployed = true
        print("[PetUI] " .. pet.name .. " 出战")
        DataManager.SaveToCloud(player)
        PetUI.ShowDetail(index)
        PetUI.ShowTip(pet.name .. " 出战！")
    end
end

--- 穿戴装备选择列表
function PetUI.ShowEquipSelect(petIndex, slot)
    if not parentRef_ then return end
    parentRef_:ClearChildren()

    local player = DataManager.playerData
    if not player then return end

    parentRef_:AddChild(UI.Button {
        text = "← 返回详情",
        variant = "secondary",
        height = 26,
        marginBottom = 8,
        onClick = function() PetUI.ShowDetail(petIndex) end,
    })

    parentRef_:AddChild(UI.Label {
        text = "选择" .. slot .. "装备",
        fontSize = 15,
        fontColor = { 200, 170, 100, 255 },
        textAlign = "center",
        marginBottom = 8,
    })

    -- 从背包中筛选可用的宠物装备
    local found = false
    for i, item in ipairs(player.bag) do
        local itemData = DataManager.GetItem(item.name)
        if itemData and itemData.type and itemData.type:find("宠物装备") then
            local itemSlot = itemData.pet_slot or ""
            if itemSlot == slot then
                found = true
                local desc = itemData.desc or ""
                local statsText = ""
                if itemData.pet_atk then statsText = statsText .. "攻+" .. itemData.pet_atk .. " " end
                if itemData.pet_def then statsText = statsText .. "防+" .. itemData.pet_def .. " " end
                if itemData.pet_hp then statsText = statsText .. "血+" .. itemData.pet_hp end

                parentRef_:AddChild(UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    width = "100%",
                    padding = 6,
                    backgroundColor = { 30, 30, 55, 200 },
                    borderRadius = 4,
                    marginBottom = 4,
                    children = {
                        UI.Panel {
                            flexGrow = 1, flexShrink = 1, flexDirection = "column",
                            children = {
                                UI.Label { text = item.name .. " x" .. item.count, fontSize = 13, fontColor = { 220, 220, 240, 255 } },
                                UI.Label { text = statsText, fontSize = 11, fontColor = { 100, 255, 200, 255 } },
                            },
                        },
                        UI.Button {
                            text = "穿戴",
                            variant = "primary",
                            height = 26,
                            onClick = function() PetUI.EquipSlot(petIndex, slot, i, item.name) end,
                        },
                    },
                })
            end
        end
    end

    if not found then
        parentRef_:AddChild(UI.Label {
            text = "背包中没有适合此部位的宠物装备",
            fontSize = 12,
            fontColor = { 150, 150, 150, 255 },
            textAlign = "center",
            marginTop = 12,
        })
    end
end

--- 穿戴装备
function PetUI.EquipSlot(petIndex, slot, bagIndex, itemName)
    local player = DataManager.playerData
    if not player then return end
    local pet = player.pets[petIndex]
    if not pet then return end
    if not pet.equip then pet.equip = {} end

    -- 如果当前槽位已有装备，先归还背包
    local oldEquip = pet.equip[slot] or ""
    if oldEquip ~= "" then
        local found = false
        for _, bagItem in ipairs(player.bag) do
            if bagItem.name == oldEquip then
                bagItem.count = BigNum.add(bagItem.count, "1")
                found = true
                break
            end
        end
        if not found then
            table.insert(player.bag, { name = oldEquip, count = "1" })
        end
    end

    -- 穿戴新装备
    pet.equip[slot] = itemName
    -- 从背包扣除
    local bagItem = player.bag[bagIndex]
    if bagItem then
        bagItem.count = BigNum.sub(bagItem.count, "1")
        if BigNum.lte(bagItem.count, "0") then
            table.remove(player.bag, bagIndex)
        end
    end

    print("[PetUI] " .. pet.name .. " 穿戴 " .. slot .. ": " .. itemName)
    DataManager.SaveToCloud(player)
    PetUI.ShowDetail(petIndex)
    PetUI.ShowTip(pet.name .. " 穿戴了 " .. itemName)
end

--- 卸下装备
function PetUI.UnequipSlot(petIndex, slot)
    local player = DataManager.playerData
    if not player then return end
    local pet = player.pets[petIndex]
    if not pet or not pet.equip then return end

    local equipName = pet.equip[slot] or ""
    if equipName == "" then return end

    -- 归还背包
    local found = false
    for _, bagItem in ipairs(player.bag) do
        if bagItem.name == equipName then
            bagItem.count = BigNum.add(bagItem.count, "1")
            found = true
            break
        end
    end
    if not found then
        table.insert(player.bag, { name = equipName, count = "1" })
    end

    pet.equip[slot] = ""
    print("[PetUI] " .. pet.name .. " 卸下 " .. slot .. ": " .. equipName)
    DataManager.SaveToCloud(player)
    PetUI.ShowDetail(petIndex)
    PetUI.ShowTip("已卸下 " .. equipName)
end

--- 获取出战宠物的总战力加成（供其他系统调用）
---@return string totalAtk, string totalDef, string totalHp
--- 返回出战宠物总战力（BigNum字符串）
function PetUI.GetDeployedPower()
    local player = DataManager.playerData
    if not player or not player.pets then return "0", "0", "0" end

    local totalAtk, totalDef, totalHp = "0", "0", "0"
    for _, pet in ipairs(player.pets) do
        if pet.deployed then
            local atk, def, hp = CalcPetPower(pet)
            totalAtk = BigNum.add(totalAtk, atk)
            totalDef = BigNum.add(totalDef, def)
            totalHp = BigNum.add(totalHp, hp)
        end
    end
    return totalAtk, totalDef, totalHp
end

--- 喂养经验（供外部调用，如使用经验丹）
---@param index number 宠物索引
---@param expAmount string 经验数量
function PetUI.AddExp(index, expAmount)
    local player = DataManager.playerData
    if not player then return end
    EnsurePetData(player)
    local pet = player.pets[index]
    if not pet then return end

    pet.exp = BigNum.add(pet.exp or "0", expAmount)
    DataManager.SaveToCloud(player)
end

--- 提示
function PetUI.ShowTip(msg)
    print("[PetUI] " .. msg)
    if not parentRef_ then return end
    local tip = parentRef_:FindById("petTip")
    if tip then
        tip:SetText("> " .. msg)
    else
        parentRef_:AddChild(UI.Label {
            id = "petTip",
            text = "> " .. msg,
            fontSize = 12,
            fontColor = { 255, 200, 100, 255 },
            textAlign = "center",
            marginTop = 4,
        })
    end
end

-- 公开接口：计算单个宠物的完整属性（含等级、升星、进阶、品质、装备加成）
-- 供战斗系统等外部模块调用
PetUI.CalcPetPower = CalcPetPower

return PetUI
