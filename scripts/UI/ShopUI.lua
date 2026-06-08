---------------------------------------------------
-- ShopUI.lua - 商城系统
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local NumFormat = require("Utils.NumFormat")
local BigNum = require("Utils.BigNum")

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
        text = "金币：" .. NumFormat.Short(player.status.gold),
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

            local items = shopData.items or {}
            for _, shopItem in ipairs(items) do
                ShopUI.RenderShopItem(shopItem)
            end
        end
    end
end

--- 渲染单个商品
---@param shopItem table {name, price, desc}
function ShopUI.RenderShopItem(shopItem)
    local itemName = shopItem.name or ""
    local price = shopItem.price or "0"
    local desc = shopItem.desc or ""

    if itemName == "" then return end

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
                    desc ~= "" and UI.Label { text = desc, fontSize = 11, fontColor = { 140, 140, 160, 255 }, whiteSpace = "normal" } or nil,
                },
            },
            UI.Label { text = NumFormat.Short(price) .. "金", fontSize = 13, fontColor = { 255, 215, 0, 255 } },
            UI.Button {
                text = "购买",
                variant = "primary",
                height = 28,
                onClick = function() ShopUI.BuyItem(itemName, price) end,
            },
        },
    })
end

--- 购买物品
---@param itemName string
---@param price string|number
function ShopUI.BuyItem(itemName, price)
    local player = DataManager.playerData
    if not player then return end

    local priceStr = BigNum.new(price)
    local gold = BigNum.new(player.status.gold)

    if BigNum.lt(gold, priceStr) then
        print("[ShopUI] 金币不足")
        return
    end

    -- 扣除金币
    player.status.gold = BigNum.sub(gold, priceStr)

    -- 添加到背包
    local found = false
    for _, item in ipairs(player.bag) do
        if item.name == itemName then
            item.count = BigNum.add(item.count or "0", "1")
            found = true
            break
        end
    end
    if not found then
        table.insert(player.bag, { name = itemName, count = "1" })
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
