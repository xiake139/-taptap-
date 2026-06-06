---------------------------------------------------
-- StatusUI.lua - 角色状态面板
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")

local StatusUI = {}

--- 渲染角色状态面板
---@param parent Widget
function StatusUI.Render(parent)
    local player = DataManager.playerData
    if not player then return end

    local s = player.status
    local level = tonumber(s.level) or 1
    local needExp = DataManager.GetExpForLevel(level)
    local curExp = tonumber(s.exp) or 0

    -- 装备加成
    local equipAtk, equipDef, equipHp = StatusUI.GetEquipBonus()

    parent:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "column",
        padding = 12,
        gap = 8,
        children = {
            UI.Label { text = "— 角色状态 —", fontSize = 16, fontColor = { 200, 170, 100, 255 }, textAlign = "center" },
            UI.Panel { width = "100%", height = 1, backgroundColor = { 50, 40, 70, 255 } },

            StatusUI.StatRow("角色名", s.name or "无名"),
            StatusUI.StatRow("境界", s.cultivation or "练气期一层"),
            StatusUI.StatRow("等级", tostring(level)),
            StatusUI.StatRow("经验", curExp .. " / " .. needExp),

            UI.Panel { width = "100%", height = 1, backgroundColor = { 50, 40, 70, 255 } },

            StatusUI.StatRow("生命", s.hp .. " / " .. s.max_hp),
            StatusUI.StatRow("灵力", s.mp .. " / " .. s.max_mp),
            StatusUI.StatRow("攻击", tostring((tonumber(s.atk) or 0) + equipAtk) .. (equipAtk > 0 and (" (+" .. equipAtk .. ")") or "")),
            StatusUI.StatRow("防御", tostring((tonumber(s.def) or 0) + equipDef) .. (equipDef > 0 and (" (+" .. equipDef .. ")") or "")),

            UI.Panel { width = "100%", height = 1, backgroundColor = { 50, 40, 70, 255 } },

            StatusUI.StatRow("金币", tostring(s.gold or 0)),
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
---@return number atk, number def, number hp
function StatusUI.GetEquipBonus()
    local player = DataManager.playerData
    if not player then return 0, 0, 0 end

    local totalAtk, totalDef, totalHp = 0, 0, 0
    for _, slot in ipairs({ "weapon", "armor", "accessory" }) do
        local equipName = player.equip[slot]
        if equipName and equipName ~= "" then
            local eData = DataManager.GetEquipment(equipName)
            if eData then
                totalAtk = totalAtk + (tonumber(eData.atk) or 0)
                totalDef = totalDef + (tonumber(eData.def) or 0)
                totalHp = totalHp + (tonumber(eData.hp) or 0)
            end
        end
    end

    return totalAtk, totalDef, totalHp
end

return StatusUI
