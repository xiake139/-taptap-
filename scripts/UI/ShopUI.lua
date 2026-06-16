---------------------------------------------------
-- ShopUI.lua - 商城系统（系统商店 + NPC商店）
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local NumFormat = require("Utils.NumFormat")
local BigNum = require("Utils.BigNum")

local ShopUI = {}

local parentRef_ = nil
local currentShopId_ = nil  -- 当前进入的系统商店ID（nil表示在列表页）

--- 渲染商城面板（功能按键入口 → 系统商店列表）
---@param parent Widget
function ShopUI.Render(parent)
    parentRef_ = parent
    currentShopId_ = nil
    ShopUI.RefreshSystemShopList()
end

--- 刷新系统商店列表（首页）
function ShopUI.RefreshSystemShopList()
    if not parentRef_ then return end
    parentRef_:ClearChildren()

    parentRef_:AddChild(UI.Label {
        text = "— 商城 —",
        fontSize = 16,
        fontColor = { 200, 170, 100, 255 },
        textAlign = "center",
        marginTop = 8,
        marginBottom = 8,
    })

    local shops = DataManager.GetAllSystemShops()
    local count = 0
    for _ in pairs(shops) do count = count + 1 end

    if count == 0 then
        parentRef_:AddChild(UI.Label {
            text = "暂无系统商店",
            fontSize = 13,
            fontColor = { 120, 120, 140, 255 },
            textAlign = "center",
            marginTop = 10,
        })
        return
    end

    for id, data in pairs(shops) do
        local shopName = data.name or id
        local currency = data.currency or "金币"
        local desc = data.desc or ""
        local itemCount = #(data.items or {})

        parentRef_:AddChild(UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            width = "100%",
            padding = 8,
            gap = 8,
            backgroundColor = { 30, 25, 55, 200 },
            borderRadius = 6,
            marginBottom = 4,
            children = {
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    flexDirection = "column",
                    children = {
                        UI.Label { text = shopName, fontSize = 15, fontColor = { 200, 200, 240, 255 } },
                        UI.Label {
                            text = "货币: " .. currency .. " | 商品: " .. itemCount .. "种" .. (desc ~= "" and (" | " .. desc) or ""),
                            fontSize = 11,
                            fontColor = { 140, 140, 160, 255 },
                        },
                    },
                },
                UI.Button {
                    text = "进入",
                    variant = "primary",
                    height = 30,
                    onClick = function()
                        currentShopId_ = id
                        ShopUI.RefreshSystemShopDetail(id)
                    end,
                },
            },
        })
    end
end

--- 刷新系统商店详情（进入具体商店后）
---@param shopId string
function ShopUI.RefreshSystemShopDetail(shopId)
    if not parentRef_ then return end
    parentRef_:ClearChildren()

    local shopData = DataManager.GetSystemShop(shopId)
    if not shopData then
        parentRef_:AddChild(UI.Label { text = "商店数据不存在", fontSize = 13, fontColor = { 255, 100, 100, 255 }, textAlign = "center" })
        return
    end

    local player = DataManager.playerData
    if not player then return end

    local shopName = shopData.name or shopId
    local currency = shopData.currency or "金币"

    -- 返回按钮 + 标题行
    parentRef_:AddChild(UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        width = "100%",
        marginTop = 4,
        marginBottom = 4,
        children = {
            UI.Button {
                text = "← 返回",
                variant = "outline",
                height = 26,
                fontSize = 11,
                onClick = function()
                    currentShopId_ = nil
                    ShopUI.RefreshSystemShopList()
                end,
            },
            UI.Label {
                text = "  " .. shopName,
                fontSize = 15,
                fontColor = { 200, 170, 100, 255 },
                flexGrow = 1,
            },
        },
    })

    -- 显示玩家当前货币
    local currencyValue = ShopUI.GetPlayerCurrency(player, currency)
    parentRef_:AddChild(UI.Label {
        text = currency .. "：" .. NumFormat.Short(currencyValue),
        fontSize = 14,
        fontColor = { 255, 215, 0, 255 },
        textAlign = "center",
        marginBottom = 6,
    })

    -- 商品列表
    local items = shopData.items or {}
    if #items == 0 then
        parentRef_:AddChild(UI.Label {
            text = "该商店暂无商品",
            fontSize = 13,
            fontColor = { 120, 120, 140, 255 },
            textAlign = "center",
            marginTop = 10,
        })
        return
    end

    for _, shopItem in ipairs(items) do
        local itemName = shopItem.name or ""
        local desc = shopItem.desc or ""
        if itemName == "" then goto continue_item end

        -- 定价逻辑：单价不为0用输入价格，为0则采用装备数据的出售价
        local itemData = DataManager.GetItem(itemName)
        local shopPrice = shopItem.price or "0"
        local price
        if shopPrice ~= "" and shopPrice ~= "0" then
            price = shopPrice
        else
            -- 回退：尝试从装备数据获取出售价
            local priceSell = nil
            if itemData and itemData.price_sell and itemData.price_sell ~= "" and itemData.price_sell ~= "0" then
                priceSell = itemData.price_sell
            else
                local equipData = DataManager.GetEquipData(itemName)
                if equipData and equipData.price_sell and equipData.price_sell ~= "" and equipData.price_sell ~= "0" then
                    priceSell = equipData.price_sell
                end
            end
            if priceSell then
                price = priceSell
            else
                price = "0"
                print("[ShopUI] 警告: 系统商品'" .. itemName .. "'价格为0且无法回退到出售价 (itemData=" .. tostring(itemData ~= nil) .. ", price_sell=" .. tostring(itemData and itemData.price_sell or "nil") .. ")")
            end
        end

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
                UI.Label { text = NumFormat.Short(price) .. currency, fontSize = 13, fontColor = { 255, 215, 0, 255 } },
                UI.Button {
                    text = "购买",
                    variant = "primary",
                    height = 28,
                    onClick = function()
                        ShopUI.BuySystemItem(shopId, itemName, price, currency)
                    end,
                },
            },
        })
        ::continue_item::
    end
end

--- 获取玩家指定货币的数量
---@param player table
---@param currency string
---@return string
function ShopUI.GetPlayerCurrency(player, currency)
    return DataManager.GetPlayerCurrency(player, currency)
end

--- 扣除玩家指定货币
---@param player table
---@param currency string
---@param amount string
---@return boolean
function ShopUI.DeductPlayerCurrency(player, currency, amount)
    local have = BigNum.new(DataManager.GetPlayerCurrency(player, currency))
    local cost = BigNum.new(amount)
    if BigNum.lt(have, cost) then return false end
    local newVal = BigNum.sub(have, cost)
    DataManager.SetPlayerCurrency(player, currency, newVal)
    return true
end

--- 购买系统商店物品
---@param shopId string
---@param itemName string
---@param price string|number
---@param currency string
function ShopUI.BuySystemItem(shopId, itemName, price, currency)
    local player = DataManager.playerData
    if not player then return end

    local priceStr = tostring(price)

    -- 扣除货币
    if not ShopUI.DeductPlayerCurrency(player, currency, priceStr) then
        print("[ShopUI] " .. currency .. "不足")
        return
    end

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

    print("[ShopUI] 购买了 " .. itemName .. "（花费 " .. priceStr .. currency .. "）")
    DataManager.SaveToCloud(player)
    ShopUI.RefreshSystemShopDetail(shopId)
end

-- ============ NPC商店部分（保留，供NPC交互调用）============

--- 渲染NPC商店（由NPC交互触发时使用）
---@param parent Widget
---@param mapName string
function ShopUI.RenderNpcShops(parent, mapName)
    parentRef_ = parent
    parentRef_:ClearChildren()

    local player = DataManager.playerData
    if not player then return end

    local shopIds = ShopUI.GetShopsInMap(mapName)

    parentRef_:AddChild(UI.Label {
        text = "— NPC商店 —",
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
            text = "当前地图没有NPC商店",
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
                ShopUI.RenderNpcShopItem(shopItem)
            end
        end
    end
end

--- 渲染NPC商店单个商品
---@param shopItem table {name, price, desc}
function ShopUI.RenderNpcShopItem(shopItem)
    local itemName = shopItem.name or ""
    local desc = shopItem.desc or ""

    if itemName == "" then return end

    -- 定价逻辑：单价不为0用输入价格，为0则采用装备数据的出售价
    local itemData = DataManager.GetItem(itemName)
    local shopPrice = shopItem.price or "0"
    local price
    if shopPrice ~= "" and shopPrice ~= "0" then
        price = shopPrice
    else
        -- 回退：尝试从装备数据获取出售价
        local priceSell = nil
        if itemData and itemData.price_sell and itemData.price_sell ~= "" and itemData.price_sell ~= "0" then
            priceSell = itemData.price_sell
        else
            -- 再尝试专门从装备表查找
            local equipData = DataManager.GetEquipData(itemName)
            if equipData and equipData.price_sell and equipData.price_sell ~= "" and equipData.price_sell ~= "0" then
                priceSell = equipData.price_sell
            end
        end
        if priceSell then
            price = priceSell
        else
            price = "0"
            print("[ShopUI] 警告: 商品'" .. itemName .. "'价格为0且无法回退到出售价 (itemData=" .. tostring(itemData ~= nil) .. ", price_sell=" .. tostring(itemData and itemData.price_sell or "nil") .. ")")
        end
    end

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
                onClick = function() ShopUI.BuyNpcItem(itemName, price) end,
            },
        },
    })
end

--- 购买NPC商店物品（金币结算）
---@param itemName string
---@param price string|number
function ShopUI.BuyNpcItem(itemName, price)
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
    -- 刷新NPC商店显示
    local currentMap = player.status.current_map
    ShopUI.RenderNpcShops(parentRef_, currentMap)
end

--- 获取当前地图的NPC商店列表
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
