---------------------------------------------------
-- EquipUI.lua - 装备系统面板
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")

local EquipUI = {}

local parentRef_ = nil

--- 渲染装备面板
---@param parent Widget
function EquipUI.Render(parent)
    parentRef_ = parent
    EquipUI.Refresh()
end

--- 刷新装备显示
function EquipUI.Refresh()
    if not parentRef_ then return end
    parentRef_:ClearChildren()

    local player = DataManager.playerData
    if not player then return end

    parentRef_:AddChild(UI.Label {
        text = "— 装备栏 —",
        fontSize = 16,
        fontColor = { 200, 170, 100, 255 },
        textAlign = "center",
        marginTop = 8,
        marginBottom = 8,
    })

    -- 装备槽
    local slots = {
        { key = "weapon", label = "武器" },
        { key = "armor", label = "防具" },
        { key = "accessory", label = "饰品" },
    }

    for _, slot in ipairs(slots) do
        local equipName = player.equip[slot.key] or ""
        local eData = nil
        local statsText = ""

        if equipName ~= "" then
            eData = DataManager.GetEquipment(equipName)
            if eData then
                local parts = {}
                if (tonumber(eData.atk) or 0) > 0 then table.insert(parts, "攻+" .. eData.atk) end
                if (tonumber(eData.def) or 0) > 0 then table.insert(parts, "防+" .. eData.def) end
                if (tonumber(eData.hp) or 0) > 0 then table.insert(parts, "血+" .. eData.hp) end
                statsText = table.concat(parts, " ")
            end
        end

        local qualityColor = EquipUI.GetQualityColor(eData and eData.quality or "white")

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
                UI.Label { text = "[" .. slot.label .. "]", fontSize = 14, fontColor = { 140, 140, 160, 255 }, width = 50 },
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    flexDirection = "column",
                    children = {
                        UI.Label {
                            text = equipName ~= "" and equipName or "（未装备）",
                            fontSize = 14,
                            fontColor = equipName ~= "" and qualityColor or { 100, 100, 120, 255 },
                        },
                        statsText ~= "" and UI.Label {
                            text = statsText,
                            fontSize = 11,
                            fontColor = { 150, 200, 150, 255 },
                        } or UI.Panel { height = 0 },
                    },
                },
                equipName ~= "" and UI.Button {
                    text = "卸下",
                    variant = "secondary",
                    height = 28,
                    onClick = function() EquipUI.Unequip(slot.key) end,
                } or UI.Panel { width = 0 },
            },
        })
    end

    -- 分隔
    parentRef_:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = { 50, 40, 70, 255 }, marginTop = 8, marginBottom = 8 })

    -- 可装备物品列表
    parentRef_:AddChild(UI.Label {
        text = "背包中可装备的物品",
        fontSize = 14,
        fontColor = { 150, 150, 180, 255 },
        textAlign = "center",
        marginBottom = 6,
    })

    local hasEquippable = false
    for i, item in ipairs(player.bag) do
        local itemData = DataManager.GetEquipment(item.name)
        if itemData and itemData.slot then
            hasEquippable = true
            local qualityColor = EquipUI.GetQualityColor(itemData.quality or "white")
            local parts = {}
            if (tonumber(itemData.atk) or 0) > 0 then table.insert(parts, "攻+" .. itemData.atk) end
            if (tonumber(itemData.def) or 0) > 0 then table.insert(parts, "防+" .. itemData.def) end
            if (tonumber(itemData.hp) or 0) > 0 then table.insert(parts, "血+" .. itemData.hp) end

            parentRef_:AddChild(UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                width = "100%",
                padding = 6,
                backgroundColor = { 20, 15, 35, 200 },
                borderRadius = 4,
                marginBottom = 3,
                gap = 6,
                children = {
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        flexDirection = "column",
                        children = {
                            UI.Label { text = item.name .. " x" .. item.count, fontSize = 13, fontColor = qualityColor },
                            UI.Label { text = table.concat(parts, " "), fontSize = 11, fontColor = { 150, 200, 150, 255 } },
                        },
                    },
                    UI.Button {
                        text = "装备",
                        variant = "primary",
                        height = 26,
                        onClick = function() EquipUI.EquipFromBag(i) end,
                    },
                },
            })
        end
    end

    if not hasEquippable then
        parentRef_:AddChild(UI.Label {
            text = "无可装备物品",
            fontSize = 12,
            fontColor = { 100, 100, 120, 255 },
            textAlign = "center",
        })
    end
end

--- 卸下装备
---@param slot string
function EquipUI.Unequip(slot)
    local player = DataManager.playerData
    if not player then return end

    local equipName = player.equip[slot]
    if not equipName or equipName == "" then return end

    -- 放回背包
    local found = false
    for _, item in ipairs(player.bag) do
        if item.name == equipName then
            item.count = item.count + 1
            found = true
            break
        end
    end
    if not found then
        table.insert(player.bag, { name = equipName, count = 1 })
    end

    player.equip[slot] = ""
    print("[EquipUI] 卸下了 " .. equipName)
    DataManager.SaveToCloud(player)
    EquipUI.Refresh()
end

--- 从背包装备
---@param bagIndex number
function EquipUI.EquipFromBag(bagIndex)
    local player = DataManager.playerData
    if not player then return end

    local item = player.bag[bagIndex]
    if not item then return end

    local itemData = DataManager.GetEquipment(item.name)
    if not itemData or not itemData.slot then return end

    -- 检查等级需求
    local levelReq = tonumber(itemData.level_req) or 0
    local playerLevel = tonumber(player.status.level) or 1
    if playerLevel < levelReq then
        print("[EquipUI] 等级不足，需要等级 " .. levelReq)
        return
    end

    local slot = itemData.slot

    -- 卸下旧装备
    local oldEquip = player.equip[slot]
    if oldEquip and oldEquip ~= "" then
        local found = false
        for _, bagItem in ipairs(player.bag) do
            if bagItem.name == oldEquip then
                bagItem.count = bagItem.count + 1
                found = true
                break
            end
        end
        if not found then
            table.insert(player.bag, { name = oldEquip, count = 1 })
        end
    end

    -- 装备
    player.equip[slot] = item.name
    item.count = item.count - 1
    if item.count <= 0 then
        table.remove(player.bag, bagIndex)
    end

    print("[EquipUI] 装备了 " .. item.name)
    DataManager.SaveToCloud(player)
    EquipUI.Refresh()
end

--- 获取品质颜色
---@param quality string
---@return table color {r,g,b,a}
function EquipUI.GetQualityColor(quality)
    local colors = {
        white = { 200, 200, 200, 255 },
        green = { 100, 220, 100, 255 },
        blue = { 100, 150, 255, 255 },
        purple = { 200, 100, 255, 255 },
        gold = { 255, 200, 50, 255 },
    }
    return colors[quality] or colors.white
end

return EquipUI
