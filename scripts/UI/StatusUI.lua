---------------------------------------------------
-- StatusUI.lua - 角色状态面板
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local NumFormat = require("Utils.NumFormat")
local BigNum = require("Utils.BigNum")

local StatusUI = {}

-- 保留倒计时标签引用，供动态更新
local expRateLabel_ = nil
local goldRateLabel_ = nil

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

--- 计算倍率显示文字
local function calcRateStr(player, buffType)
    local BagUI = require("UI.BagUI")
    local rate = BagUI.GetBuffValue(player, buffType)
    local str = "x" .. rate
    if player.buffs then
        local now = os.time()
        local remain = 0
        for _, b in ipairs(player.buffs) do
            if b.type == buffType and b.expires > now then
                remain = math.max(remain, b.expires - now)
            end
        end
        if remain > 0 then
            str = str .. formatRemain(remain)
        end
    end
    return str
end

--- 仅更新倒计时文本（不重建面板）
function StatusUI.UpdateTimers()
    local player = DataManager.playerData
    if not player then return end
    if expRateLabel_ then
        expRateLabel_:SetText(calcRateStr(player, "经验倍率"))
    end
    if goldRateLabel_ then
        goldRateLabel_:SetText(calcRateStr(player, "货币倍率"))
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

    -- 攻击/防御总加成文字（装备和buff加成是小数值，用普通number）
    local atkBonus = equipAtk + buffAtk
    local defBonus = equipDef + buffDef
    local atkTotal = BigNum.add(s.atk or "0", tostring(atkBonus))
    local atkStr = NumFormat.Short(atkTotal)
    if atkBonus > 0 then atkStr = atkStr .. " (+" .. NumFormat.Short(tostring(atkBonus)) .. ")" end
    local defTotal = BigNum.add(s.def or "0", tostring(defBonus))
    local defStr = NumFormat.Short(defTotal)
    if defBonus > 0 then defStr = defStr .. " (+" .. NumFormat.Short(tostring(defBonus)) .. ")" end

    -- 创建倍率标签（保留引用用于动态更新）
    expRateLabel_ = UI.Label { text = calcRateStr(player, "经验倍率"), fontSize = 14, fontColor = { 220, 220, 240, 255 } }
    goldRateLabel_ = UI.Label { text = calcRateStr(player, "货币倍率"), fontSize = 14, fontColor = { 220, 220, 240, 255 } }

    parent:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "column",
        padding = 12,
        gap = 8,
        children = {
            UI.Label { text = "— 角色状态 —", fontSize = 16, fontColor = { 200, 170, 100, 255 }, textAlign = "center" },
            UI.Panel { width = "100%", height = 1, backgroundColor = { 50, 40, 70, 255 } },

            StatusUI.StatRow("角色名", s.name or "无名"),
            StatusUI.StatRow("等级", NumFormat.Short(level)),
            StatusUI.StatRow("经验", NumFormat.Short(curExp) .. " / " .. NumFormat.Short(needExp)),

            UI.Panel { width = "100%", height = 1, backgroundColor = { 50, 40, 70, 255 } },

            StatusUI.StatRow("生命", NumFormat.Short(s.hp or "0") .. " / " .. NumFormat.Short(s.max_hp or "100")),
            StatusUI.StatRow("灵力", NumFormat.Short(s.mp or "0") .. " / " .. NumFormat.Short(s.max_mp or "50")),
            StatusUI.StatRow("攻击", atkStr),
            StatusUI.StatRow("防御", defStr),

            UI.Panel { width = "100%", height = 1, backgroundColor = { 50, 40, 70, 255 } },

            -- 倍率行用预创建的标签
            UI.Panel {
                flexDirection = "row", width = "100%", justifyContent = "space-between",
                children = {
                    UI.Label { text = "经验倍率", fontSize = 14, fontColor = { 160, 160, 180, 255 } },
                    expRateLabel_,
                },
            },
            UI.Panel {
                flexDirection = "row", width = "100%", justifyContent = "space-between",
                children = {
                    UI.Label { text = "货币倍率", fontSize = 14, fontColor = { 160, 160, 180, 255 } },
                    goldRateLabel_,
                },
            },

            UI.Panel { width = "100%", height = 1, backgroundColor = { 50, 40, 70, 255 } },

            StatusUI.StatRow("金币", NumFormat.Short(s.gold)),
            StatusUI.StatRow("所在地图", s.current_map or "未知"),
        },
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
    for _, slot in ipairs({ "weapon", "helmet", "armor", "bracer", "belt", "boots", "cloak", "necklace", "ring", "artifact", "mount", "wings", "shield" }) do
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
