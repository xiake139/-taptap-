---------------------------------------------------
-- ShopUI.lua - 商城系统
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local IniParser = require("Utils.IniParser")

local ShopUI = {}

local parentRef_ = nil

--- 渲染商城面板
---@param parent Widget
function ShopUI.Render(parent)
    parentRef_ = parent
    ShopUI.Refresh()
end

--- 刷新商城显示
function ShopUI.Refresh()
    if not parentRef_ then return end
    parentRef_:ClearChildren()

    local player = DataManager.playerData
    if not player then return end

    -- 找到当前地图的NPC商店
    local currentMap = player.status.current_map
    local shopIds = ShopUI.GetShopsInMap(currentMap)

    parentRef_:AddChild(UI.Label {
        text = "— 商城 —",
        fontSize = 16,
        fontColor = { 200, 170, 100, 255 },
        textAlign = "center",
        marginTop = 8,
    })

    parentRef_:AddChild(UI.Label {
        text = "金币：" .. tostring(player.status.gold or 0),
        fontSize = 14,
        fontColor = { 255, 215, 0, 255 },
        textAlign = "center",
        marginBottom = 8,
    })

    if #shopIds == 0 then
        parentRef_:AddChild(UI.Label {
            text = "当前地图没有商店",
            fontSize = 13,
            fontColor = { 120, 120, 140, 255 },
            textAlign = "center",
            marginTop = 10,
        })
        return
    end

    for _, shopId in ipairs(shopIds) do
        local shopData = DataManager.GetShop(shopId)
        if shopData then
            parentRef_:AddChild(UI.Label {
                text = "[ " .. (shopData.name or shopId) .. " ]",
                fontSize = 15,
                fontColor = { 150, 200, 150, 255 },
                textAlign = "center",
                marginTop = 8,
                marginBottom = 4,
            })

            local itemList = IniParser.ParseList(shopData.items or "")
            for _, itemEntry in ipairs(itemList) do
                local itemName, _ = itemEntry:match("^(.+):(%d+)$")
                if itemName then
                    ShopUI.RenderShopItem(itemName)
                end
            end
        end
    end
end

--- 渲染单个商品
---@param itemName string
function ShopUI.RenderShopItem(itemName)
    local itemData = DataManager.GetItem(itemName)
    if not itemData then return end

    local price = tonumber(itemData.price_buy) or 0
    if price <= 0 then return end -- 不可购买

    local desc = itemData.desc or ""

    parentRef_:AddChild(UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        width = "100%",
        padding = 6,
        gap = 6,
        backgroundColor = { 25, 20, 45, 200 },
        borderRadius = 4,
        marginBottom = 3,
        children = {
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                flexDirection = "column",
                children = {
                    UI.Label { text = itemName, fontSize = 14, fontColor = { 220, 220, 240, 255 } },
                    UI.Label { text = desc, fontSize = 11, fontColor = { 140, 140, 160, 255 }, whiteSpace = "normal" },
                },
            },
            UI.Label { text = price .. "金", fontSize = 13, fontColor = { 255, 215, 0, 255 } },
            UI.Button {
                text = "购买",
                variant = "primary",
                height = 28,
                onClick = function() ShopUI.BuyItem(itemName) end,
            },
        },
    })
end

--- 购买物品
---@param itemName string
function ShopUI.BuyItem(itemName)
    local player = DataManager.playerData
    if not player then return end

    local itemData = DataManager.GetItem(itemName)
    if not itemData then return end

    local price = tonumber(itemData.price_buy) or 0
    local gold = tonumber(player.status.gold) or 0

    if gold < price then
        print("[ShopUI] 金币不足")
        return
    end

    -- 扣除金币
    player.status.gold = gold - price

    -- 添加到背包
    local found = false
    for _, item in ipairs(player.bag) do
        if item.name == itemName then
            item.count = item.count + 1
            found = true
            break
        end
    end
    if not found then
        table.insert(player.bag, { name = itemName, count = 1 })
    end

    print("[ShopUI] 购买了 " .. itemName)
    DataManager.SaveToCloud(player)
    ShopUI.Refresh()
end

--- 获取当前地图的商店列表
---@param mapName string
---@return table shopIds
function ShopUI.GetShopsInMap(mapName)
    local shopIds = {}
    for npcId, npcData in pairs(DataManager.npcs) do
        if npcData.location == mapName and npcData.shop_id and npcData.shop_id ~= "" then
            table.insert(shopIds, npcData.shop_id)
        end
    end
    return shopIds
end

return ShopUI
