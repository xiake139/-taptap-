---------------------------------------------------
-- TradeUI.lua - 交易所系统
-- 玩家自由挂售物品，支持金币定价或物品交换
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local NumFormat = require("Utils.NumFormat")
local BigNum = require("Utils.BigNum")

local TradeUI = {}

local parentRef_ = nil
local listings_ = {}        -- 当前交易所列表 [{seller, item_name, item_count, price_type, price_gold, price_item, price_item_count, timestamp}]
local pendingIncome_ = {}   -- 待领取收入 [{recipient, type, gold, item_name, item_count, from_buyer, item_sold, timestamp}]
local isLoading_ = false
local GameUI = nil           -- 延迟引用
local currentDialog_ = nil   -- 当前弹窗引用（用于关闭）

--- 关闭当前弹窗
local function CloseDialog()
    if currentDialog_ then
        if not GameUI then GameUI = require("UI.GameUI") end
        if GameUI.rootPanel then
            GameUI.rootPanel:RemoveChild(currentDialog_)
        end
        currentDialog_ = nil
    end
end

--- 云端存储 key
local TRADE_CLOUD_KEY = "系统配置/trade_market.ini"

-- =============== 数据层 ===============

--- 序列化交易列表为字符串（INI格式，包含挂售列表 + 待领取收入）
local function SerializeListings(list, incomeList)
    local lines = {}
    for i, entry in ipairs(list) do
        table.insert(lines, "[listing_" .. i .. "]")
        table.insert(lines, "seller=" .. (entry.seller or ""))
        table.insert(lines, "item_name=" .. (entry.item_name or ""))
        table.insert(lines, "item_count=" .. tostring(entry.item_count or 1))
        table.insert(lines, "price_type=" .. (entry.price_type or "currency"))  -- "currency" or "item"
        table.insert(lines, "price_gold=" .. (entry.price_gold or "0"))
        table.insert(lines, "price_currency_name=" .. (entry.price_currency_name or "金币"))
        table.insert(lines, "price_item=" .. (entry.price_item or ""))
        table.insert(lines, "price_item_count=" .. tostring(entry.price_item_count or 0))
        table.insert(lines, "timestamp=" .. tostring(entry.timestamp or 0))
        table.insert(lines, "")
    end
    -- 序列化待领取收入
    for i, entry in ipairs(incomeList or {}) do
        table.insert(lines, "[income_" .. i .. "]")
        table.insert(lines, "recipient=" .. (entry.recipient or ""))
        table.insert(lines, "type=" .. (entry.type or "currency"))
        table.insert(lines, "currency_name=" .. (entry.currency_name or "金币"))
        table.insert(lines, "gold=" .. (entry.gold or "0"))
        table.insert(lines, "item_name=" .. (entry.item_name or ""))
        table.insert(lines, "item_count=" .. tostring(entry.item_count or 0))
        table.insert(lines, "from_buyer=" .. (entry.from_buyer or ""))
        table.insert(lines, "item_sold=" .. (entry.item_sold or ""))
        table.insert(lines, "timestamp=" .. tostring(entry.timestamp or 0))
        table.insert(lines, "")
    end
    return table.concat(lines, "\n")
end

--- 反序列化字符串为交易列表 + 待领取收入
local function DeserializeListings(str)
    if not str or str == "" then return {}, {} end
    local IniParser = require("Utils.IniParser")
    local sections = IniParser.Parse(str)
    local list = {}
    local incomeList = {}
    for sectionName, data in pairs(sections) do
        if sectionName:find("^listing_") then
            local ptype = data["price_type"] or "gold"
            -- 兼容旧数据："gold" 视为 "currency" + 金币
            if ptype == "gold" then ptype = "currency" end
            table.insert(list, {
                seller = data["seller"] or "",
                item_name = data["item_name"] or "",
                item_count = tonumber(data["item_count"]) or 1,
                price_type = ptype,
                price_gold = data["price_gold"] or "0",
                price_currency_name = data["price_currency_name"] or "金币",
                price_item = data["price_item"] or "",
                price_item_count = tonumber(data["price_item_count"]) or 0,
                timestamp = tonumber(data["timestamp"]) or 0,
            })
        elseif sectionName:find("^income_") then
            local itype = data["type"] or "gold"
            if itype == "gold" then itype = "currency" end
            table.insert(incomeList, {
                recipient = data["recipient"] or "",
                type = itype,
                currency_name = data["currency_name"] or "金币",
                gold = data["gold"] or "0",
                item_name = data["item_name"] or "",
                item_count = tonumber(data["item_count"]) or 0,
                from_buyer = data["from_buyer"] or "",
                item_sold = data["item_sold"] or "",
                timestamp = tonumber(data["timestamp"]) or 0,
            })
        end
    end
    -- 按时间排序（最新在前）
    table.sort(list, function(a, b) return a.timestamp > b.timestamp end)
    table.sort(incomeList, function(a, b) return a.timestamp > b.timestamp end)
    return list, incomeList
end

--- 获取云存储实例（兼容多人模式的CloudProxy）
local function GetCloud()
    return DataManager.GetCloudProvider()
end

--- 从云端加载交易所数据
local function LoadListings(callback)
    isLoading_ = true
    local cloud = GetCloud()
    if not cloud then
        print("[TradeUI] 云存储不可用，使用空列表")
        listings_ = {}
        pendingIncome_ = {}
        isLoading_ = false
        if callback then callback() end
        return
    end
    cloud:Get(TRADE_CLOUD_KEY, {
        ok = function(values)
            local raw = values[TRADE_CLOUD_KEY]
            if raw and raw ~= "" then
                listings_, pendingIncome_ = DeserializeListings(raw)
            else
                listings_ = {}
                pendingIncome_ = {}
            end
            isLoading_ = false
            print("[TradeUI] 加载交易所数据成功，共 " .. #listings_ .. " 条挂售, " .. #pendingIncome_ .. " 条待领取")
            if callback then callback() end
        end,
        error = function(code, reason)
            isLoading_ = false
            listings_ = {}
            pendingIncome_ = {}
            print("[TradeUI] 加载交易所失败: " .. tostring(reason))
            if callback then callback() end
        end,
    })
end

--- 保存交易所数据到云端
local function SaveListings(callback)
    local cloud = GetCloud()
    if not cloud then
        if callback then callback(false) end
        return
    end
    local content = SerializeListings(listings_, pendingIncome_)
    cloud:Set(TRADE_CLOUD_KEY, content, {
        ok = function()
            print("[TradeUI] 保存交易所数据成功")
            if callback then callback(true) end
        end,
        error = function(code, reason)
            print("[TradeUI] 保存交易所失败: " .. tostring(reason))
            if callback then callback(false) end
        end,
    })
end

--- 领取当前玩家的所有待领取收入
local function CollectPendingIncome()
    local player = DataManager.playerData
    if not player then return end
    local currentUser = player.account and player.account.username or ""
    if currentUser == "" then return end

    local collected = {}
    local remaining = {}

    for _, entry in ipairs(pendingIncome_) do
        if entry.recipient == currentUser then
            table.insert(collected, entry)
        else
            table.insert(remaining, entry)
        end
    end

    if #collected == 0 then return end

    -- 发放收入到玩家数据
    for _, entry in ipairs(collected) do
        if entry.type == "currency" or entry.type == "gold" then
            -- 增加对应货币
            local currName = entry.currency_name or "金币"
            local curBal = DataManager.GetPlayerCurrency(player, currName)
            local newBal = BigNum.add(curBal, entry.gold)
            DataManager.SetPlayerCurrency(player, currName, newBal)
            TradeUI.ShowMsg("收到交易收入：" .. NumFormat.Short(entry.gold) .. " " .. currName .. "（" .. (entry.from_buyer or "?") .. " 购买了你的 " .. (entry.item_sold or "?") .. "）")
        else
            -- 增加物品
            local addedToBag = false
            for _, item in ipairs(player.bag) do
                if item.name == entry.item_name then
                    item.count = tostring((tonumber(item.count) or 0) + entry.item_count)
                    addedToBag = true
                    break
                end
            end
            if not addedToBag then
                table.insert(player.bag, { name = entry.item_name, count = tostring(entry.item_count) })
            end
            TradeUI.ShowMsg("收到交易收入：" .. (entry.item_name or "?") .. " x" .. tostring(entry.item_count) .. "（" .. (entry.from_buyer or "?") .. " 购买了你的 " .. (entry.item_sold or "?") .. "）")
        end
    end

    -- 更新待领取列表（移除已领取的）
    pendingIncome_ = remaining

    -- 保存玩家数据和更新后的交易所数据
    DataManager.SaveToCloud(player)
    SaveListings(function()
        print("[TradeUI] 领取收入完成，共 " .. #collected .. " 条")
    end)
end

-- =============== UI 层 ===============

--- 渲染交易所面板
---@param parent Widget
function TradeUI.Render(parent)
    parentRef_ = parent
    -- 先加载最新数据再渲染，加载完后自动领取待领取收入
    LoadListings(function()
        TradeUI.Refresh()
    end)
    -- 先显示加载中
    parentRef_:ClearChildren()
    parentRef_:AddChild(UI.Label {
        text = "— 交易所 —",
        fontSize = 16,
        fontColor = { 200, 170, 100, 255 },
        textAlign = "center",
        marginTop = 8,
    })
    parentRef_:AddChild(UI.Label {
        text = "正在加载交易数据...",
        fontSize = 13,
        fontColor = { 150, 150, 170, 255 },
        textAlign = "center",
        marginTop = 20,
    })
end

--- 刷新交易所显示
function TradeUI.Refresh()
    if not parentRef_ then return end
    parentRef_:ClearChildren()

    local player = DataManager.playerData
    if not player then return end

    -- 标题
    parentRef_:AddChild(UI.Label {
        text = "— 交易所 —",
        fontSize = 16,
        fontColor = { 200, 170, 100, 255 },
        textAlign = "center",
        marginTop = 8,
    })

    -- 玩家货币余额显示（所有自定义货币）
    local currencies = DataManager.GetCurrencyList()
    local currTexts = {}
    for _, cname in ipairs(currencies) do
        local bal = DataManager.GetPlayerCurrency(player, cname)
        table.insert(currTexts, cname .. "：" .. NumFormat.Short(bal))
    end
    parentRef_:AddChild(UI.Label {
        text = table.concat(currTexts, "  "),
        fontSize = 13,
        fontColor = { 255, 215, 0, 255 },
        textAlign = "center",
        marginBottom = 4,
    })

    -- 操作按钮区
    parentRef_:AddChild(UI.Panel {
        flexDirection = "row",
        width = "100%",
        justifyContent = "center",
        gap = 8,
        marginBottom = 8,
        children = {
            UI.Button {
                text = "挂售物品",
                variant = "primary",
                height = 32,
                onClick = function() TradeUI.ShowSellDialog() end,
            },
            UI.Button {
                text = "我的挂售",
                variant = "secondary",
                height = 32,
                onClick = function() TradeUI.ShowMyListings() end,
            },
            UI.Button {
                text = "刷新",
                variant = "secondary",
                height = 32,
                onClick = function()
                    LoadListings(function()
                        CollectPendingIncome()
                        TradeUI.Refresh()
                    end)
                end,
            },
        },
    })

    -- 分割线
    parentRef_:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 50, 80, 255 }, marginBottom = 6 })

    -- 挂售列表（只显示别人的）
    local currentUser = player.account and player.account.username or ""
    local hasOthers = false

    for i, entry in ipairs(listings_) do
        if entry.seller ~= currentUser then
            TradeUI.RenderListingRow(entry, i, currentUser)
            hasOthers = true
        end
    end

    if not hasOthers then
        parentRef_:AddChild(UI.Label {
            text = "暂无其他玩家挂售物品",
            fontSize = 13,
            fontColor = { 120, 120, 140, 255 },
            textAlign = "center",
            marginTop = 20,
        })
    end
end

--- 显示我的挂售列表
function TradeUI.ShowMyListings()
    if not parentRef_ then return end
    parentRef_:ClearChildren()

    local player = DataManager.playerData
    if not player then return end
    local currentUser = player.account and player.account.username or ""

    -- 标题
    parentRef_:AddChild(UI.Label {
        text = "— 我的挂售 —",
        fontSize = 16,
        fontColor = { 200, 170, 100, 255 },
        textAlign = "center",
        marginTop = 8,
    })

    -- 返回按钮
    parentRef_:AddChild(UI.Panel {
        flexDirection = "row",
        width = "100%",
        justifyContent = "center",
        gap = 8,
        marginBottom = 8,
        marginTop = 6,
        children = {
            UI.Button {
                text = "返回交易所",
                variant = "secondary",
                height = 32,
                onClick = function() TradeUI.Refresh() end,
            },
        },
    })

    -- 分割线
    parentRef_:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 50, 80, 255 }, marginBottom = 6 })

    -- 只显示自己的挂售
    local hasMine = false
    for i, entry in ipairs(listings_) do
        if entry.seller == currentUser then
            TradeUI.RenderListingRow(entry, i, currentUser)
            hasMine = true
        end
    end

    if not hasMine then
        parentRef_:AddChild(UI.Label {
            text = "你还没有挂售任何物品",
            fontSize = 13,
            fontColor = { 120, 120, 140, 255 },
            textAlign = "center",
            marginTop = 20,
        })
    end
end

--- 渲染单条挂售记录
---@param entry table
---@param index number
---@param currentUser string
function TradeUI.RenderListingRow(entry, index, currentUser)
    local isMine = (entry.seller == currentUser)
    local priceText = ""
    if entry.price_type == "currency" or entry.price_type == "gold" then
        local currName = entry.price_currency_name or "金币"
        priceText = NumFormat.Short(entry.price_gold) .. " " .. currName
    else
        priceText = (entry.price_item or "?") .. " x" .. tostring(entry.price_item_count or 1)
    end

    local actionBtn
    if isMine then
        actionBtn = UI.Button {
            text = "下架",
            variant = "danger",
            height = 26,
            onClick = function() TradeUI.CancelListing(index) end,
        }
    else
        actionBtn = UI.Button {
            text = "购买",
            variant = "primary",
            height = 26,
            onClick = function() TradeUI.BuyListing(index) end,
        }
    end

    parentRef_:AddChild(UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        width = "100%",
        padding = 6,
        gap = 4,
        backgroundColor = isMine and { 35, 30, 55, 200 } or { 25, 20, 45, 200 },
        borderRadius = 4,
        marginBottom = 3,
        children = {
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                flexDirection = "column",
                children = {
                    UI.Label {
                        text = (entry.item_name or "?") .. " x" .. tostring(entry.item_count or 1),
                        fontSize = 14,
                        fontColor = { 220, 200, 255, 255 },
                    },
                    UI.Label {
                        text = "价格：" .. priceText,
                        fontSize = 12,
                        fontColor = entry.price_type == "gold" and { 255, 215, 0, 200 } or { 100, 220, 180, 200 },
                    },
                    UI.Label {
                        text = "卖家：" .. (entry.seller or "?"),
                        fontSize = 11,
                        fontColor = { 130, 130, 150, 200 },
                    },
                },
            },
            actionBtn,
        },
    })
end

-- =============== 挂售弹窗 ===============

--- 显示挂售弹窗
function TradeUI.ShowSellDialog()
    if not GameUI then GameUI = require("UI.GameUI") end
    local player = DataManager.playerData
    if not player or #player.bag == 0 then
        TradeUI.ShowMsg("背包为空，无法挂售")
        return
    end

    CloseDialog()  -- 关闭之前的弹窗

    -- 选择物品阶段（VirtualList）
    local TRADE_ITEM_HEIGHT = 36
    local TRADE_ITEM_GAP = 4

    local itemsPanel = UI.Panel {
        width = "100%",
        height = 300,
        overflow = "hidden",
    }

    local vList = UI.VirtualList {
        width = "100%",
        height = "100%",
        viewportHeight = 300,
        data = player.bag,
        itemHeight = TRADE_ITEM_HEIGHT,
        itemGap = TRADE_ITEM_GAP,
        poolBuffer = 5,
        createItem = function()
            local btn = UI.Button {
                text = "",
                variant = "secondary",
                width = "100%",
                height = TRADE_ITEM_HEIGHT,
            }
            return btn
        end,
        bindItem = function(widget, data, index)
            widget:SetText(data.name .. " x" .. tostring(data.count))
            widget.props.onClick = function()
                CloseDialog()
                TradeUI.ShowPriceDialog(data)
            end
        end,
    }
    itemsPanel:AddChild(vList)

    currentDialog_ = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 180 },
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = "90%",
                maxHeight = "80%",
                backgroundColor = { 30, 25, 50, 250 },
                borderRadius = 10,
                padding = 16,
                flexDirection = "column",
                gap = 8,
                children = {
                    UI.Label {
                        text = "选择要挂售的物品",
                        fontSize = 16,
                        fontColor = { 200, 170, 100, 255 },
                        textAlign = "center",
                    },
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 50, 80, 255 } },
                    itemsPanel,
                    UI.Button {
                        text = "取消",
                        variant = "danger",
                        width = "100%",
                        onClick = function()
                            CloseDialog()
                        end,
                    },
                },
            },
        },
    }

    if GameUI.rootPanel then
        GameUI.rootPanel:AddChild(currentDialog_)
    end
end

--- 显示定价弹窗（选择金币或物品定价）
---@param bagItem table {name, count}
function TradeUI.ShowPriceDialog(bagItem)
    if not GameUI then GameUI = require("UI.GameUI") end

    CloseDialog()  -- 关闭之前的弹窗

    local sellCount = 1
    local priceType = "currency"  -- "currency" or "item"
    local currencies = DataManager.GetCurrencyList()
    local selectedCurrency = currencies[1] or "金币"
    local priceGold = "100"
    local priceItemName = ""
    local priceItemCount = 1

    local contentArea = nil

    --- 渲染定价内容
    local function RenderPriceContent()
        if not contentArea then return end
        contentArea:ClearChildren()

        -- 挂售数量
        contentArea:AddChild(UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            width = "100%",
            gap = 6,
            children = {
                UI.Label { text = "挂售数量：", fontSize = 13, fontColor = { 180, 180, 200, 255 } },
                UI.TextField {
                    value = tostring(sellCount),
                    width = 80,
                    fontSize = 13,
                    placeholder = "数量",
                    onChange = function(self, val)
                        local n = tonumber(val)
                        if n and n >= 1 then
                            sellCount = math.min(n, tonumber(bagItem.count) or 1)
                        end
                    end,
                },
                UI.Label { text = "/ " .. tostring(bagItem.count), fontSize = 12, fontColor = { 130, 130, 150, 255 } },
            },
        })

        -- 定价方式选择
        contentArea:AddChild(UI.Panel {
            flexDirection = "row",
            width = "100%",
            gap = 6,
            marginTop = 8,
            children = {
                UI.Button {
                    text = "货币定价",
                    variant = priceType == "currency" and "primary" or "secondary",
                    flexGrow = 1,
                    height = 30,
                    onClick = function()
                        priceType = "currency"
                        RenderPriceContent()
                    end,
                },
                UI.Button {
                    text = "物品交换",
                    variant = priceType == "item" and "primary" or "secondary",
                    flexGrow = 1,
                    height = 30,
                    onClick = function()
                        priceType = "item"
                        RenderPriceContent()
                    end,
                },
            },
        })

        -- 根据定价方式显示不同输入
        if priceType == "currency" then
            -- 货币选择按钮行
            if #currencies > 1 then
                local currBtns = {}
                for _, cname in ipairs(currencies) do
                    table.insert(currBtns, UI.Button {
                        text = cname,
                        variant = selectedCurrency == cname and "primary" or "secondary",
                        height = 26,
                        paddingLeft = 8, paddingRight = 8,
                        onClick = function()
                            selectedCurrency = cname
                            RenderPriceContent()
                        end,
                    })
                end
                contentArea:AddChild(UI.Panel {
                    flexDirection = "row",
                    width = "100%",
                    gap = 4,
                    marginTop = 8,
                    flexWrap = "wrap",
                    children = currBtns,
                })
            end

            contentArea:AddChild(UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                width = "100%",
                gap = 6,
                marginTop = 8,
                children = {
                    UI.Label { text = "售价" .. selectedCurrency .. "：", fontSize = 13, fontColor = { 255, 215, 0, 255 } },
                    UI.TextField {
                        value = priceGold,
                        width = 120,
                        fontSize = 13,
                        placeholder = "输入金额",
                        onChange = function(self, val)
                            priceGold = val or "0"
                        end,
                    },
                },
            })
        else
            contentArea:AddChild(UI.Panel {
                flexDirection = "column",
                width = "100%",
                gap = 6,
                marginTop = 8,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 6,
                        children = {
                            UI.Label { text = "所需物品：", fontSize = 13, fontColor = { 100, 220, 180, 255 } },
                            UI.TextField {
                                value = priceItemName,
                                width = 140,
                                fontSize = 13,
                                placeholder = "物品名称",
                                onChange = function(self, val)
                                    priceItemName = val or ""
                                end,
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 6,
                        children = {
                            UI.Label { text = "所需数量：", fontSize = 13, fontColor = { 100, 220, 180, 255 } },
                            UI.TextField {
                                value = tostring(priceItemCount),
                                width = 80,
                                fontSize = 13,
                                placeholder = "数量",
                                onChange = function(self, val)
                                    local n = tonumber(val)
                                    if n and n >= 1 then priceItemCount = n end
                                end,
                            },
                        },
                    },
                },
            })
        end
    end

    contentArea = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 4,
    }

    currentDialog_ = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 180 },
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = "90%",
                backgroundColor = { 30, 25, 50, 250 },
                borderRadius = 10,
                padding = 16,
                flexDirection = "column",
                gap = 8,
                children = {
                    UI.Label {
                        text = "挂售：" .. bagItem.name,
                        fontSize = 15,
                        fontColor = { 220, 200, 255, 255 },
                        textAlign = "center",
                    },
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 50, 80, 255 } },
                    contentArea,
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 50, 80, 255 }, marginTop = 8 },
                    UI.Panel {
                        flexDirection = "row",
                        width = "100%",
                        gap = 8,
                        children = {
                            UI.Button {
                                text = "确认挂售",
                                variant = "primary",
                                flexGrow = 1,
                                onClick = function()
                                    TradeUI.ConfirmSell(bagItem, sellCount, priceType, priceGold, priceItemName, priceItemCount, selectedCurrency)
                                end,
                            },
                            UI.Button {
                                text = "取消",
                                variant = "danger",
                                flexGrow = 1,
                                onClick = function()
                                    CloseDialog()
                                end,
                            },
                        },
                    },
                },
            },
        },
    }

    RenderPriceContent()

    if GameUI.rootPanel then
        GameUI.rootPanel:AddChild(currentDialog_)
    end
end

-- =============== 交易逻辑 ===============

--- 确认挂售
function TradeUI.ConfirmSell(bagItem, sellCount, priceType, priceGold, priceItemName, priceItemCount, selectedCurrency)
    if not GameUI then GameUI = require("UI.GameUI") end
    local player = DataManager.playerData
    if not player then return end

    -- 校验数量：实时从背包查询当前数量
    local actualBagCount = 0
    for _, item in ipairs(player.bag) do
        if item.name == bagItem.name then
            actualBagCount = tonumber(item.count) or 0
            break
        end
    end

    if sellCount < 1 then
        TradeUI.ShowMsg("挂售数量无效")
        return
    end

    if sellCount > actualBagCount then
        TradeUI.ShowMsg("背包物品数量不足，挂售失败")
        return
    end

    -- 校验定价
    if priceType == "currency" then
        local gold = tonumber(priceGold)
        if not gold or gold <= 0 then
            TradeUI.ShowMsg("请输入有效的" .. (selectedCurrency or "货币") .. "价格")
            return
        end
    else
        if priceItemName == "" then
            TradeUI.ShowMsg("请输入所需物品名称")
            return
        end
        if priceItemCount < 1 then
            TradeUI.ShowMsg("请输入有效的物品数量")
            return
        end
    end

    -- 从背包扣除物品
    local removed = false
    for i, item in ipairs(player.bag) do
        if item.name == bagItem.name then
            local curCount = tonumber(item.count) or 0
            if curCount <= sellCount then
                table.remove(player.bag, i)
            else
                item.count = tostring(curCount - sellCount)
            end
            removed = true
            break
        end
    end

    if not removed then
        TradeUI.ShowMsg("背包中没有该物品")
        return
    end

    -- 添加到交易所列表
    local newListing = {
        seller = player.account and player.account.username or "unknown",
        item_name = bagItem.name,
        item_count = sellCount,
        price_type = priceType,
        price_gold = priceType == "currency" and priceGold or "0",
        price_currency_name = selectedCurrency or "金币",
        price_item = priceType == "item" and priceItemName or "",
        price_item_count = priceType == "item" and priceItemCount or 0,
        timestamp = os.time(),
    }
    table.insert(listings_, 1, newListing)  -- 最新在前

    -- 关闭弹窗
    CloseDialog()

    -- 保存交易数据和玩家数据
    SaveListings(function()
        DataManager.SaveToCloud(player)
        TradeUI.ShowMsg("挂售成功！")
        -- 自动跳转到交易所页面并刷新
        if GameUI.ShowPanel then
            GameUI.ShowPanel("trade")
        else
            TradeUI.Refresh()
        end
    end)
end

--- 购买挂售物品
---@param index number
function TradeUI.BuyListing(index)
    local player = DataManager.playerData
    if not player then return end

    local entry = listings_[index]
    if not entry then
        TradeUI.ShowMsg("该物品已被下架")
        return
    end

    -- 不能购买自己的挂售
    local currentUser = player.account and player.account.username or ""
    if entry.seller == currentUser then
        TradeUI.ShowMsg("不能购买自己的物品")
        return
    end

    -- 检查支付能力
    if entry.price_type == "currency" or entry.price_type == "gold" then
        local currName = entry.price_currency_name or "金币"
        local bal = DataManager.GetPlayerCurrency(player, currName)
        local price = BigNum.new(entry.price_gold)
        if BigNum.lt(bal, price) then
            TradeUI.ShowMsg(currName .. "不足，需要 " .. NumFormat.Short(entry.price_gold) .. " " .. currName)
            return
        end
        -- 扣除对应货币
        DataManager.SetPlayerCurrency(player, currName, BigNum.sub(bal, price))
    else
        -- 检查背包中是否有足够的交换物品
        local found = false
        for _, item in ipairs(player.bag) do
            if item.name == entry.price_item then
                local cnt = tonumber(item.count) or 0
                if cnt >= entry.price_item_count then
                    found = true
                    -- 扣除物品
                    if cnt <= entry.price_item_count then
                        -- 直接移除
                        for j, it in ipairs(player.bag) do
                            if it.name == entry.price_item then
                                table.remove(player.bag, j)
                                break
                            end
                        end
                    else
                        item.count = tostring(cnt - entry.price_item_count)
                    end
                    break
                end
            end
        end
        if not found then
            TradeUI.ShowMsg("物品不足，需要 " .. entry.price_item .. " x" .. tostring(entry.price_item_count))
            return
        end
    end

    -- 将挂售物品添加到买家背包
    local addedToBag = false
    for _, item in ipairs(player.bag) do
        if item.name == entry.item_name then
            item.count = tostring((tonumber(item.count) or 0) + entry.item_count)
            addedToBag = true
            break
        end
    end
    if not addedToBag then
        table.insert(player.bag, { name = entry.item_name, count = tostring(entry.item_count) })
    end

    -- 发送邮件通知卖家
    local MailboxUI = require("UI.MailboxUI")
    local mailData = {
        type = "trade",
        title = "交易成功",
        sender = currentUser,
        timestamp = os.time(),
    }
    if entry.price_type == "currency" or entry.price_type == "gold" then
        local currName = entry.price_currency_name or "金币"
        mailData.content = currentUser .. " 购买了你的 " .. entry.item_name .. " x" .. tostring(entry.item_count)
        -- 使用邮箱的多货币字段
        mailData.gold = "0"
        mailData.currencies = { [currName] = entry.price_gold }
        mailData.items = ""
    else
        mailData.content = currentUser .. " 用 " .. entry.price_item .. " x" .. tostring(entry.price_item_count) .. " 换购了你的 " .. entry.item_name .. " x" .. tostring(entry.item_count)
        mailData.gold = "0"
        mailData.items = entry.price_item .. ":" .. tostring(entry.price_item_count)
    end
    MailboxUI.SendMail(entry.seller, mailData, function(ok)
        if ok then
            print("[TradeUI] 交易邮件已发送给卖家: " .. entry.seller)
        else
            print("[TradeUI] 交易邮件发送失败")
        end
    end)

    -- 从交易列表移除
    table.remove(listings_, index)

    -- 保存
    SaveListings(function()
        DataManager.SaveToCloud(player)
        TradeUI.ShowMsg("购买成功！获得 " .. entry.item_name .. " x" .. tostring(entry.item_count))
        TradeUI.Refresh()
    end)
end

--- 下架自己的挂售物品（退回背包）
---@param index number
function TradeUI.CancelListing(index)
    local player = DataManager.playerData
    if not player then return end

    local entry = listings_[index]
    if not entry then return end

    local currentUser = player.account and player.account.username or ""
    if entry.seller ~= currentUser then
        TradeUI.ShowMsg("只能下架自己的物品")
        return
    end

    -- 退回到背包
    local addedToBag = false
    for _, item in ipairs(player.bag) do
        if item.name == entry.item_name then
            item.count = tostring((tonumber(item.count) or 0) + entry.item_count)
            addedToBag = true
            break
        end
    end
    if not addedToBag then
        table.insert(player.bag, { name = entry.item_name, count = tostring(entry.item_count) })
    end

    -- 从列表移除
    table.remove(listings_, index)

    -- 保存
    SaveListings(function()
        DataManager.SaveToCloud(player)
        TradeUI.ShowMsg("已下架，物品已退回背包")
        TradeUI.Refresh()
    end)
end

--- 显示提示信息（复用 GameUI 的日志）
---@param text string
function TradeUI.ShowMsg(text)
    if not GameUI then GameUI = require("UI.GameUI") end
    if GameUI.AddLog then
        GameUI.AddLog(text)
    else
        print("[TradeUI] " .. text)
    end
end

return TradeUI
