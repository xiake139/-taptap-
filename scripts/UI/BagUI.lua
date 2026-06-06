---------------------------------------------------
-- BagUI.lua - 背包系统
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")

local BagUI = {}

local parentRef_ = nil

--- 渲染背包面板
---@param parent Widget
function BagUI.Render(parent)
    parentRef_ = parent
    BagUI.Refresh()
end

--- 刷新背包显示
function BagUI.Refresh()
    if not parentRef_ then return end
    parentRef_:ClearChildren()

    local player = DataManager.playerData
    if not player then return end

    parentRef_:AddChild(UI.Label {
        text = "— 背包 —",
        fontSize = 16,
        fontColor = { 200, 170, 100, 255 },
        textAlign = "center",
        marginTop = 8,
    })

    if #player.bag == 0 then
        parentRef_:AddChild(UI.Label {
            text = "背包空空如也...",
            fontSize = 13,
            fontColor = { 120, 120, 140, 255 },
            textAlign = "center",
            marginTop = 20,
        })
        return
    end

    for i, item in ipairs(player.bag) do
        local itemData = DataManager.GetItem(item.name)
        local desc = itemData and (itemData.desc or "") or ""
        local sellPrice = itemData and (tonumber(itemData.price_sell) or 0) or 0

        local isConsumable = itemData and itemData.type == "consumable"
        local isEquip = itemData and itemData.slot

        local btnChildren = {}

        if isConsumable then
            table.insert(btnChildren, UI.Button {
                text = "使用",
                variant = "success",
                height = 26,
                onClick = function() BagUI.UseItem(i) end,
            })
        end

        if isEquip then
            table.insert(btnChildren, UI.Button {
                text = "装备",
                variant = "primary",
                height = 26,
                onClick = function() BagUI.EquipItem(i) end,
            })
        end

        if sellPrice > 0 then
            table.insert(btnChildren, UI.Button {
                text = "卖" .. sellPrice,
                variant = "danger",
                height = 26,
                onClick = function() BagUI.SellItem(i) end,
            })
        end

        parentRef_:AddChild(UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            width = "100%",
            padding = 6,
            gap = 6,
            backgroundColor = { 25, 20, 45, 200 },
            borderRadius = 4,
            marginBottom = 4,
            children = {
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    flexDirection = "column",
                    children = {
                        UI.Label { text = item.name .. " x" .. item.count, fontSize = 14, fontColor = { 220, 220, 240, 255 } },
                        UI.Label { text = desc, fontSize = 11, fontColor = { 140, 140, 160, 255 }, whiteSpace = "normal" },
                    },
                },
                UI.Panel { flexDirection = "row", gap = 4, children = btnChildren },
            },
        })
    end
end

--- 使用物品
---@param index number
function BagUI.UseItem(index)
    local player = DataManager.playerData
    if not player then return end

    local item = player.bag[index]
    if not item then return end

    local itemData = DataManager.GetItem(item.name)
    if not itemData then return end

    if itemData.effect == "heal" then
        local healValue = tonumber(itemData.value) or 0
        local maxHp = tonumber(player.status.max_hp) or 100
        player.status.hp = math.min((tonumber(player.status.hp) or 0) + healValue, maxHp)
        print("[BagUI] 使用 " .. item.name .. "，恢复 " .. healValue .. " 生命")
    end

    -- 减少数量
    item.count = item.count - 1
    if item.count <= 0 then
        table.remove(player.bag, index)
    end

    DataManager.SaveToCloud(player)
    BagUI.Refresh()
end

--- 装备物品
---@param index number
function BagUI.EquipItem(index)
    local player = DataManager.playerData
    if not player then return end

    local item = player.bag[index]
    if not item then return end

    local itemData = DataManager.GetItem(item.name)
    if not itemData or not itemData.slot then return end

    local slot = itemData.slot

    -- 卸下旧装备
    local oldEquip = player.equip[slot]
    if oldEquip and oldEquip ~= "" then
        -- 放回背包
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

    -- 装备新物品
    player.equip[slot] = item.name
    item.count = item.count - 1
    if item.count <= 0 then
        table.remove(player.bag, index)
    end

    print("[BagUI] 装备了 " .. item.name)
    DataManager.SaveToCloud(player)
    BagUI.Refresh()
end

--- 出售物品
---@param index number
function BagUI.SellItem(index)
    local player = DataManager.playerData
    if not player then return end

    local item = player.bag[index]
    if not item then return end

    local itemData = DataManager.GetItem(item.name)
    local sellPrice = itemData and (tonumber(itemData.price_sell) or 0) or 0

    if sellPrice <= 0 then return end

    player.status.gold = (tonumber(player.status.gold) or 0) + sellPrice
    item.count = item.count - 1
    if item.count <= 0 then
        table.remove(player.bag, index)
    end

    print("[BagUI] 卖出 " .. item.name .. "，获得 " .. sellPrice .. " 金币")
    DataManager.SaveToCloud(player)
    BagUI.Refresh()
end

return BagUI
