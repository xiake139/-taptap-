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
local isLoading_ = false
local GameUI = nil           -- 延迟引用

--- 云端存储 key
local TRADE_CLOUD_KEY = "系统配置/trade_market.ini"

-- =============== 数据层 ===============

--- 序列化交易列表为字符串（INI格式）
local function SerializeListings(list)
    local lines = {}
    for i, entry in ipairs(list) do
        table.insert(lines, "[listing_" .. i .. "]")
        table.insert(lines, "seller=" .. (entry.seller or ""))
        table.insert(lines, "item_name=" .. (entry.item_name or ""))
        table.insert(lines, "item_count=" .. tostring(entry.item_count or 1))
        table.insert(lines, "price_type=" .. (entry.price_type or "gold"))  -- "gold" or "item"
        table.insert(lines, "price_gold=" .. (entry.price_gold or "0"))
        table.insert(lines, "price_item=" .. (entry.price_item or ""))
        table.insert(lines, "price_item_count=" .. tostring(entry.price_item_count or 0))
        table.insert(lines, "timestamp=" .. tostring(entry.timestamp or 0))
        table.insert(lines, "")
    end
    return table.concat(lines, "\n")
end

--- 反序列化字符串为交易列表
local function DeserializeListings(str)
    if not str or str == "" then return {} end
    local IniParser = require("Utils.IniParser")
    local sections = IniParser.Parse(str)
    local list = {}
    for sectionName, data in pairs(sections) do
        table.insert(list, {
            seller = data["seller"] or "",
            item_name = data["item_name"] or "",
            item_count = tonumber(data["item_count"]) or 1,
            price_type = data["price_type"] or "gold",
            price_gold = data["price_gold"] or "0",
            price_item = data["price_item"] or "",
            price_item_count = tonumber(data["price_item_count"]) or 0,
            timestamp = tonumber(data["timestamp"]) or 0,
        })
    end
    -- 按时间排序（最新在前）
    table.sort(list, function(a, b) return a.timestamp > b.timestamp end)
    return list
end

--- 从云端加载交易所数据
local function LoadListings(callback)
    isLoading_ = true
    if not clientCloud then
        isLoading_ = false
        if callback then callback() end
        return
    end
    clientCloud:Get(TRADE_CLOUD_KEY, {
        ok = function(values)
            local raw = values[TRADE_CLOUD_KEY]
            if raw and raw ~= "" then
                listings_ = DeserializeListings(raw)
            else
                listings_ = {}
            end
            isLoading_ = false
            print("[TradeUI] 加载交易所数据成功，共 " .. #listings_ .. " 条挂售")
            if callback then callback() end
        end,
        error = function(code, reason)
            isLoading_ = false
            print("[TradeUI] 加载交易所失败: " .. tostring(reason))
            if callback then callback() end
        end,
    })
end

--- 保存交易所数据到云端
local function SaveListings(callback)
    if not clientCloud then
        if callback then callback(false) end
        return
    end
    local content = SerializeListings(listings_)
    clientCloud:Set(TRADE_CLOUD_KEY, content, {
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

-- =============== UI 层 ===============

--- 渲染交易所面板
---@param parent Widget
function TradeUI.Render(parent)
    parentRef_ = parent
    -- 先加载最新数据再渲染
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

    -- 玩家金币显示
    parentRef_:AddChild(UI.Label {
        text = "金币：" .. NumFormat.Short(player.status.gold),
        fontSize = 14,
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
                text = "刷新",
                variant = "secondary",
                height = 32,
                onClick = function()
                    LoadListings(function() TradeUI.Refresh() end)
                end,
            },
        },
    })

    -- 分割线
    parentRef_:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 50, 80, 255 }, marginBottom = 6 })

    -- 挂售列表
    if #listings_ == 0 then
        parentRef_:AddChild(UI.Label {
            text = "暂无挂售物品",
            fontSize = 13,
            fontColor = { 120, 120, 140, 255 },
            textAlign = "center",
            marginTop = 20,
        })
        return
    end

    local currentUser = player.account and player.account.username or ""

    for i, entry in ipairs(listings_) do
        TradeUI.RenderListingRow(entry, i, currentUser)
    end
end

--- 渲染单条挂售记录
---@param entry table
---@param index number
---@param currentUser string
function TradeUI.RenderListingRow(entry, index, currentUser)
    local isMine = (entry.seller == currentUser)
    local priceText = ""
    if entry.price_type == "gold" then
        priceText = NumFormat.Short(entry.price_gold) .. " 金币"
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

    -- 选择物品阶段
    local dialogPanel = UI.Panel {
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
                    (function()
                        local itemsPanel = UI.ScrollView {
                            width = "100%",
                            maxHeight = 300,
                            scrollY = true,
                            flexDirection = "column",
                            gap = 4,
                        }
                        for i, item in ipairs(player.bag) do
                            itemsPanel:AddChild(UI.Button {
                                text = item.name .. " x" .. tostring(item.count),
                                variant = "secondary",
                                width = "100%",
                                onClick = function()
                                    -- 关闭选择弹窗，打开定价弹窗
                                    if GameUI.rootPanel then
                                        GameUI.rootPanel:RemoveChild(dialogPanel)
                                    end
                                    TradeUI.ShowPriceDialog(item)
                                end,
                            })
                        end
                        return itemsPanel
                    end)(),
                    UI.Button {
                        text = "取消",
                        variant = "danger",
                        width = "100%",
                        onClick = function()
                            if GameUI.rootPanel then
                                GameUI.rootPanel:RemoveChild(dialogPanel)
                            end
                        end,
                    },
                },
            },
        },
    }

    if GameUI.rootPanel then
        GameUI.rootPanel:AddChild(dialogPanel)
    end
end

--- 显示定价弹窗（选择金币或物品定价）
---@param bagItem table {name, count}
function TradeUI.ShowPriceDialog(bagItem)
    if not GameUI then GameUI = require("UI.GameUI") end

    local sellCount = 1
    local priceType = "gold"  -- "gold" or "item"
    local priceGold = "100"
    local priceItemName = ""
    local priceItemCount = 1

    ---@type Widget
    local dialogPanel = nil
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
                UI.Input {
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
                    text = "金币定价",
                    variant = priceType == "gold" and "primary" or "secondary",
                    flexGrow = 1,
                    height = 30,
                    onClick = function()
                        priceType = "gold"
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
        if priceType == "gold" then
            contentArea:AddChild(UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                width = "100%",
                gap = 6,
                marginTop = 8,
                children = {
                    UI.Label { text = "售价金币：", fontSize = 13, fontColor = { 255, 215, 0, 255 } },
                    UI.Input {
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
                            UI.Input {
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
                            UI.Input {
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

    dialogPanel = UI.Panel {
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
                                    TradeUI.ConfirmSell(bagItem, sellCount, priceType, priceGold, priceItemName, priceItemCount, dialogPanel)
                                end,
                            },
                            UI.Button {
                                text = "取消",
                                variant = "danger",
                                flexGrow = 1,
                                onClick = function()
                                    if GameUI.rootPanel then
                                        GameUI.rootPanel:RemoveChild(dialogPanel)
                                    end
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
        GameUI.rootPanel:AddChild(dialogPanel)
    end
end

-- =============== 交易逻辑 ===============

--- 确认挂售
function TradeUI.ConfirmSell(bagItem, sellCount, priceType, priceGold, priceItemName, priceItemCount, dialogPanel)
    if not GameUI then GameUI = require("UI.GameUI") end
    local player = DataManager.playerData
    if not player then return end

    -- 校验数量
    local bagCount = tonumber(bagItem.count) or 0
    if sellCount < 1 or sellCount > bagCount then
        TradeUI.ShowMsg("挂售数量无效")
        return
    end

    -- 校验定价
    if priceType == "gold" then
        local gold = tonumber(priceGold)
        if not gold or gold <= 0 then
            TradeUI.ShowMsg("请输入有效的金币价格")
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
        price_gold = priceType == "gold" and priceGold or "0",
        price_item = priceType == "item" and priceItemName or "",
        price_item_count = priceType == "item" and priceItemCount or 0,
        timestamp = os.time(),
    }
    table.insert(listings_, 1, newListing)  -- 最新在前

    -- 关闭弹窗
    if GameUI.rootPanel and dialogPanel then
        GameUI.rootPanel:RemoveChild(dialogPanel)
    end

    -- 保存交易数据和玩家数据
    SaveListings(function()
        DataManager.SaveToCloud(player)
        TradeUI.ShowMsg("挂售成功！")
        TradeUI.Refresh()
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
    if entry.price_type == "gold" then
        local gold = BigNum.new(player.status.gold)
        local price = BigNum.new(entry.price_gold)
        if BigNum.lt(gold, price) then
            TradeUI.ShowMsg("金币不足，需要 " .. NumFormat.Short(entry.price_gold) .. " 金币")
            return
        end
        -- 扣除金币
        player.status.gold = BigNum.sub(gold, price)
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
