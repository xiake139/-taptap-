---------------------------------------------------
-- StatusUI.lua - 角色状态面板
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local NumFormat = require("Utils.NumFormat")
local BigNum = require("Utils.BigNum")
local EquipSlots = require("Systems.EquipSlots")

local StatusUI = {}

-- 保留倒计时标签引用，供动态更新
local expPermLabel_ = nil
local expTempLabel_ = nil
local goldPermLabel_ = nil
local goldTempLabel_ = nil

--- 格式化剩余时间
local function formatRemain(seconds)
    if seconds <= 0 then return "" end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    if m > 0 then
        return string.format(" (%d分%02d秒)", m, s)
    else
        return string.format(" (%d秒)", s)
    end
end

--- 计算永久倍率显示文字（含坐骑倍率）
local function calcPermRateStr(player, buffType)
    local BagUI = require("UI.BagUI")
    -- buff系统的永久倍率
    local total = 0
    if player.buffs then
        for _, b in ipairs(player.buffs) do
            if b.type == buffType and BagUI.IsPermanentBuff(b) then
                total = total + (tonumber(b.value) or 0)
            end
        end
    end
    -- 叠加坐骑永久倍率
    if player.mounts then
        if buffType == "经验倍率" then
            total = total + (tonumber(player.mounts.exp_rate) or 0)
        elseif buffType == "货币倍率" then
            total = total + (tonumber(player.mounts.gold_rate) or 0)
        end
    end
    return "x" .. total
end

--- 计算有限倍率显示文字（含倒计时）
local function calcTempRateStr(player, buffType)
    local BagUI = require("UI.BagUI")
    if not player.buffs then return "x0" end
    local now = os.time()
    local total = 0
    local maxRemain = 0
    for _, b in ipairs(player.buffs) do
        if b.type == buffType and not BagUI.IsPermanentBuff(b) and b.expires > now then
            total = total + (tonumber(b.value) or 0)
            maxRemain = math.max(maxRemain, b.expires - now)
        end
    end
    local str = "x" .. total
    if maxRemain > 0 then
        str = str .. formatRemain(maxRemain)
    end
    return str
end

--- 仅更新倒计时文本（不重建面板）
function StatusUI.UpdateTimers()
    local player = DataManager.playerData
    if not player then return end
    if expPermLabel_ then
        expPermLabel_:SetText(calcPermRateStr(player, "经验倍率"))
    end
    if expTempLabel_ then
        expTempLabel_:SetText(calcTempRateStr(player, "经验倍率"))
    end
    if goldPermLabel_ then
        goldPermLabel_:SetText(calcPermRateStr(player, "货币倍率"))
    end
    if goldTempLabel_ then
        goldTempLabel_:SetText(calcTempRateStr(player, "货币倍率"))
    end
end

--- 渲染角色状态面板
---@param parent Widget
function StatusUI.Render(parent)
    local player = DataManager.playerData
    if not player then return end

    local s = player.status
    local level = s.level or "1"
    local needExp = DataManager.GetExpForLevel(tonumber(level) or 1)
    local curExp = BigNum.new(s.exp or "0")

    -- 装备加成
    local equipAtk, equipDef, equipHp = StatusUI.GetEquipBonus()

    -- buff 加成
    local BagUI = require("UI.BagUI")
    local buffAtk = BagUI.GetBuffValue(player, "攻击")
    local buffDef = BagUI.GetBuffValue(player, "防御")
    local buffHp = BagUI.GetBuffValue(player, "生命上限")

    -- 境界加成
    local realmAtk, realmDef, realmHp = DataManager.GetRealmBonus()

    -- 战魂加成
    local soulBonus = DataManager.GetBattleSoulBonus(s.battle_soul_level)

    -- 攻击/防御总加成文字（全部使用BigNum避免精度丢失）
    local atkBonusTotal = BigNum.add(BigNum.add(BigNum.add(tostring(equipAtk), tostring(buffAtk)), realmAtk), soulBonus.atk)
    local atkTotal = BigNum.add(s.atk or "0", atkBonusTotal)
    local atkStr = NumFormat.Short(atkTotal)
    if BigNum.gt(atkBonusTotal, "0") then atkStr = atkStr .. " (+" .. NumFormat.Short(atkBonusTotal) .. ")" end

    local defBonusTotal = BigNum.add(BigNum.add(BigNum.add(tostring(equipDef), tostring(buffDef)), realmDef), soulBonus.def)
    local defTotal = BigNum.add(s.def or "0", defBonusTotal)
    local defStr = NumFormat.Short(defTotal)
    if BigNum.gt(defBonusTotal, "0") then defStr = defStr .. " (+" .. NumFormat.Short(defBonusTotal) .. ")" end

    -- 生命上限总加成
    local hpBonusTotal = BigNum.add(BigNum.add(BigNum.add(tostring(equipHp), tostring(buffHp)), realmHp), soulBonus.max_hp)
    local maxHpTotal = BigNum.add(s.max_hp or "100", hpBonusTotal)
    -- 确保当前hp不超过实际上限（兼容旧存档）
    if BigNum.gt(s.hp or "0", maxHpTotal) then
        s.hp = maxHpTotal
    end

    -- 创建倍率标签（永久/有限分开，保留引用用于动态更新）
    expPermLabel_ = UI.Label { text = calcPermRateStr(player, "经验倍率"), fontSize = 14, fontColor = { 180, 255, 180, 255 } }
    expTempLabel_ = UI.Label { text = calcTempRateStr(player, "经验倍率"), fontSize = 14, fontColor = { 255, 220, 150, 255 } }
    goldPermLabel_ = UI.Label { text = calcPermRateStr(player, "货币倍率"), fontSize = 14, fontColor = { 180, 255, 180, 255 } }
    goldTempLabel_ = UI.Label { text = calcTempRateStr(player, "货币倍率"), fontSize = 14, fontColor = { 255, 220, 150, 255 } }

    -- 构建 children 列表（避免 table.unpack 不在末尾的陷阱）
    local statChildren = {
        UI.Label { text = "— 角色状态 —", fontSize = 16, fontColor = { 200, 170, 100, 255 }, textAlign = "center" },
        UI.Panel { width = "100%", height = 1, backgroundColor = { 50, 40, 70, 255 } },

        StatusUI.StatRow("角色名", s.name or "无名"),
        StatusUI.StatRow("境界", DataManager.GetRealmFullName()),
        StatusUI.StatRow("等级", NumFormat.Short(level)),
        StatusUI.StatRow("经验", NumFormat.Short(curExp) .. " / " .. NumFormat.Short(needExp)),

        UI.Panel { width = "100%", height = 1, backgroundColor = { 50, 40, 70, 255 } },

        StatusUI.StatRow("生命", NumFormat.Short(s.hp or "0") .. " / " .. NumFormat.Short(maxHpTotal)),
        StatusUI.StatRow("灵力", NumFormat.Short(s.mp or "0") .. " / " .. NumFormat.Short(s.max_mp or "50")),
        StatusUI.StatRow("攻击", atkStr),
        StatusUI.StatRow("防御", defStr),

        UI.Panel { width = "100%", height = 1, backgroundColor = { 50, 40, 70, 255 } },

        -- 经验倍率：永久/有限分开显示
        UI.Panel {
            flexDirection = "row", width = "100%", justifyContent = "space-between",
            children = {
                UI.Label { text = "经验倍率(永久)", fontSize = 14, fontColor = { 160, 160, 180, 255 } },
                expPermLabel_,
            },
        },
        UI.Panel {
            flexDirection = "row", width = "100%", justifyContent = "space-between",
            children = {
                UI.Label { text = "经验倍率(有限)", fontSize = 14, fontColor = { 160, 160, 180, 255 } },
                expTempLabel_,
            },
        },
        -- 货币倍率：永久/有限分开显示
        UI.Panel {
            flexDirection = "row", width = "100%", justifyContent = "space-between",
            children = {
                UI.Label { text = "货币倍率(永久)", fontSize = 14, fontColor = { 160, 160, 180, 255 } },
                goldPermLabel_,
            },
        },
        UI.Panel {
            flexDirection = "row", width = "100%", justifyContent = "space-between",
            children = {
                UI.Label { text = "货币倍率(有限)", fontSize = 14, fontColor = { 160, 160, 180, 255 } },
                goldTempLabel_,
            },
        },

        UI.Panel { width = "100%", height = 1, backgroundColor = { 50, 40, 70, 255 } },
    }

    -- 动态添加所有自定义货币行
    local currList = DataManager.GetCurrencyList()
    for _, cname in ipairs(currList) do
        local val = DataManager.GetPlayerCurrency(player, cname)
        table.insert(statChildren, StatusUI.StatRow(cname, NumFormat.Short(val)))
    end

    table.insert(statChildren, StatusUI.StatRow("所在地图", s.current_map or "未知"))

    parent:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "column",
        padding = 12,
        gap = 8,
        children = statChildren,
    })
end

--- 生成属性行
---@param label string
---@param value string
---@return Widget
function StatusUI.StatRow(label, value)
    return UI.Panel {
        flexDirection = "row",
        width = "100%",
        justifyContent = "space-between",
        children = {
            UI.Label { text = label, fontSize = 14, fontColor = { 160, 160, 180, 255 } },
            UI.Label { text = value, fontSize = 14, fontColor = { 220, 220, 240, 255 } },
        },
    }
end

--- 获取装备加成
---@return string atk, string def, string hp
function StatusUI.GetEquipBonus()
    local player = DataManager.playerData
    if not player then return "0", "0", "0" end

    local totalAtk, totalDef, totalHp = "0", "0", "0"
    for _, slot in ipairs(EquipSlots.keys) do
        local equipName = player.equip[slot]
        if equipName and equipName ~= "" then
            local eData = DataManager.GetEquipment(equipName)
            if eData then
                totalAtk = BigNum.add(totalAtk, eData.atk or "0")
                totalDef = BigNum.add(totalDef, eData.def or "0")
                totalHp = BigNum.add(totalHp, eData.hp or "0")
            end
        end
    end

    return totalAtk, totalDef, totalHp
end

return StatusUI
