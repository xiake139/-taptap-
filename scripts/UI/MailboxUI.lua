---------------------------------------------------
-- MailboxUI.lua - 邮箱系统
-- 接收交易所收入通知、管理员发放物品等
-- 数据存储在共享云端: 邮箱/{account}.ini
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local NumFormat = require("Utils.NumFormat")
local BigNum = require("Utils.BigNum")
local IniParser = require("Utils.IniParser")

local MailboxUI = {}

local parentRef_ = nil
local mails_ = {}       -- 当前玩家邮件列表
local isLoading_ = false

-- =============== 数据层 ===============

--- 获取当前玩家邮箱云端 key
---@return string|nil
local function GetMailboxKey()
    local player = DataManager.playerData
    if not player then return nil end
    local account = player.account and player.account.username or ""
    if account == "" then return nil end
    return "邮箱/" .. account .. ".ini"
end

--- 序列化邮件列表
---@param list table
---@return string
local function SerializeMails(list)
    local lines = {}
    for i, mail in ipairs(list) do
        table.insert(lines, "[mail_" .. i .. "]")
        table.insert(lines, "type=" .. (mail.type or "system"))
        table.insert(lines, "title=" .. (mail.title or ""))
        table.insert(lines, "content=" .. (mail.content or ""))
        table.insert(lines, "gold=" .. (mail.gold or "0"))
        -- 多货币：格式 "货币名:数量,货币名2:数量"
        local currStr = ""
        if mail.currencies then
            if type(mail.currencies) == "string" then
                -- 已经是序列化格式，直接使用
                currStr = mail.currencies
            elseif type(mail.currencies) == "table" then
                local parts = {}
                for cname, val in pairs(mail.currencies) do
                    if val ~= "0" and val ~= "" then
                        table.insert(parts, cname .. ":" .. val)
                    end
                end
                currStr = table.concat(parts, ",")
            end
        end
        table.insert(lines, "currencies=" .. currStr)
        table.insert(lines, "items=" .. (mail.items or ""))
        table.insert(lines, "sender=" .. (mail.sender or "系统"))
        table.insert(lines, "claimed=" .. (mail.claimed and "1" or "0"))
        table.insert(lines, "timestamp=" .. tostring(mail.timestamp or 0))
        table.insert(lines, "")
    end
    return table.concat(lines, "\n")
end

--- 反序列化邮件列表
---@param str string
---@return table
local function DeserializeMails(str)
    if not str or str == "" then return {} end
    local sections = IniParser.Parse(str)
    local list = {}
    for sectionName, data in pairs(sections) do
        if sectionName:find("^mail_") then
            -- 解析多货币字段
            local currencies = {}
            local currRaw = data["currencies"] or ""
            if currRaw ~= "" then
                for part in currRaw:gmatch("[^,]+") do
                    local cname, val = part:match("^(.+):(.+)$")
                    if cname and val then
                        currencies[cname] = val
                    end
                end
            end
            table.insert(list, {
                type = data["type"] or "system",
                title = data["title"] or "",
                content = data["content"] or "",
                gold = data["gold"] or "0",
                currencies = currencies,
                items = data["items"] or "",
                sender = data["sender"] or "系统",
                claimed = data["claimed"] == "1",
                timestamp = tonumber(data["timestamp"]) or 0,
                exp = data["exp"] or "0",
                soul = data["soul"] or "0",
            })
        end
    end
    -- 按时间排序（最新在前）
    table.sort(list, function(a, b) return a.timestamp > b.timestamp end)
    return list
end

--- 获取云存储
local function GetCloud()
    return DataManager.GetCloudProvider()
end

--- 加载当前玩家邮箱
---@param callback fun()|nil
local function LoadMails(callback)
    isLoading_ = true
    local key = GetMailboxKey()
    if not key then
        mails_ = {}
        isLoading_ = false
        if callback then callback() end
        return
    end

    local cloud = GetCloud()
    if not cloud then
        mails_ = {}
        isLoading_ = false
        if callback then callback() end
        return
    end

    cloud:Get(key, {
        ok = function(values)
            local raw = values[key]
            if raw and raw ~= "" then
                mails_ = DeserializeMails(raw)
            else
                mails_ = {}
            end
            isLoading_ = false
            print("[Mailbox] 加载邮箱成功，共 " .. #mails_ .. " 封邮件")
            if callback then callback() end
        end,
        error = function(code, reason)
            mails_ = {}
            isLoading_ = false
            print("[Mailbox] 加载邮箱失败: " .. tostring(reason))
            if callback then callback() end
        end,
    })
end

--- 保存当前玩家邮箱
---@param callback fun(boolean)|nil
local function SaveMails(callback)
    local key = GetMailboxKey()
    if not key then
        if callback then callback(false) end
        return
    end

    local cloud = GetCloud()
    if not cloud then
        if callback then callback(false) end
        return
    end

    local content = SerializeMails(mails_)
    cloud:Set(key, content, {
        ok = function()
            print("[Mailbox] 保存邮箱成功")
            if callback then callback(true) end
        end,
        error = function(code, reason)
            print("[Mailbox] 保存邮箱失败: " .. tostring(reason))
            if callback then callback(false) end
        end,
    })
end

--- 向指定玩家发送邮件（外部调用接口）
---@param account string 目标玩家账号
---@param mail table {type, title, content, gold, items, sender}
---@param callback fun(boolean)|nil
function MailboxUI.SendMail(account, mail, callback)
    local key = "邮箱/" .. account .. ".ini"
    local cloud = GetCloud()
    if not cloud then
        if callback then callback(false) end
        return
    end

    -- 先读取目标玩家邮箱，再追加邮件
    cloud:Get(key, {
        ok = function(values)
            local raw = values[key]
            local existingMails = {}
            if raw and raw ~= "" then
                existingMails = DeserializeMails(raw)
            end

            -- 添加新邮件
            mail.timestamp = mail.timestamp or os.time()
            mail.claimed = false
            table.insert(existingMails, 1, mail)  -- 插入到最前面

            -- 限制邮箱最多100封
            while #existingMails > 100 do
                table.remove(existingMails)
            end

            -- 保存
            local content = SerializeMails(existingMails)
            cloud:Set(key, content, {
                ok = function()
                    print("[Mailbox] 发送邮件成功 -> " .. account)
                    if callback then callback(true) end
                end,
                error = function()
                    if callback then callback(false) end
                end,
            })
        end,
        error = function()
            if callback then callback(false) end
        end,
    })
end

--- 批量向多个玩家发送邮件（全服发放用）
---@param accounts table 账号列表
---@param mail table 邮件数据
---@param callback fun(number, number)|nil 成功数, 失败数
function MailboxUI.SendMailBatch(accounts, mail, callback)
    local total = #accounts
    local finished = 0
    local successCount = 0
    local failCount = 0

    for _, acc in ipairs(accounts) do
        MailboxUI.SendMail(acc, {
            type = mail.type or "system",
            title = mail.title or "",
            content = mail.content or "",
            gold = mail.gold or "0",
            currencies = mail.currencies or {},
            items = mail.items or "",
            sender = mail.sender or "系统",
        }, function(ok)
            finished = finished + 1
            if ok then
                successCount = successCount + 1
            else
                failCount = failCount + 1
            end
            if finished >= total then
                if callback then callback(successCount, failCount) end
            end
        end)
    end

    if total == 0 then
        if callback then callback(0, 0) end
    end
end

-- =============== UI 层 ===============

--- 渲染邮箱面板
---@param parent Widget
function MailboxUI.Render(parent)
    parentRef_ = parent
    parentRef_:ClearChildren()
    parentRef_:AddChild(UI.Label {
        text = "— 邮箱 —",
        fontSize = 16,
        fontColor = { 200, 170, 100, 255 },
        textAlign = "center",
        marginTop = 8,
    })
    parentRef_:AddChild(UI.Label {
        text = "正在加载邮件...",
        fontSize = 13,
        fontColor = { 150, 150, 170, 255 },
        textAlign = "center",
        marginTop = 20,
    })

    LoadMails(function()
        MailboxUI.Refresh()
    end)
end

--- 刷新邮箱显示
function MailboxUI.Refresh()
    if not parentRef_ then return end
    parentRef_:ClearChildren()

    -- 标题
    parentRef_:AddChild(UI.Label {
        text = "— 邮箱 —",
        fontSize = 16,
        fontColor = { 200, 170, 100, 255 },
        textAlign = "center",
        marginTop = 8,
        marginBottom = 8,
    })

    -- 一键领取按钮
    local unclaimedCount = 0
    for _, mail in ipairs(mails_) do
        local hasCurr = mail.currencies and next(mail.currencies)
        if not mail.claimed and (mail.gold ~= "0" or hasCurr or mail.items ~= "") then
            unclaimedCount = unclaimedCount + 1
        end
    end

    if unclaimedCount > 0 then
        parentRef_:AddChild(UI.Button {
            text = "一键领取全部 (" .. unclaimedCount .. ")",
            variant = "primary",
            width = "100%",
            height = 36,
            marginBottom = 8,
            onClick = function() MailboxUI.ClaimAll() end,
        })
    end

    -- 邮件列表
    if #mails_ == 0 then
        parentRef_:AddChild(UI.Label {
            text = "暂无邮件",
            fontSize = 13,
            fontColor = { 150, 150, 170, 255 },
            textAlign = "center",
            marginTop = 20,
        })
        return
    end

    for i, mail in ipairs(mails_) do
        local hasCurr = mail.currencies and next(mail.currencies)
        local hasAttachment = (mail.gold ~= "0" or hasCurr or mail.items ~= "")
        local statusText = ""
        local statusColor = { 150, 150, 150, 255 }
        if hasAttachment then
            if mail.claimed then
                statusText = "[已领取]"
                statusColor = { 100, 100, 100, 255 }
            else
                statusText = "[可领取]"
                statusColor = { 100, 255, 100, 255 }
            end
        end

        -- 附件描述
        local attachText = ""
        if hasCurr then
            for cname, val in pairs(mail.currencies) do
                if val ~= "0" and val ~= "" then
                    attachText = attachText .. cname .. ":" .. NumFormat.Short(val) .. " "
                end
            end
        elseif mail.gold ~= "0" then
            attachText = attachText .. "金币:" .. NumFormat.Short(mail.gold) .. " "
        end
        if mail.items ~= "" then
            attachText = attachText .. "物品:" .. mail.items
        end

        local mailPanel = UI.Panel {
            width = "100%",
            backgroundColor = (i % 2 == 0) and { 35, 30, 55, 200 } or { 25, 20, 45, 200 },
            borderRadius = 4,
            padding = 8,
            marginBottom = 4,
            flexDirection = "column",
            gap = 2,
            children = {
                -- 第一行：标题 + 状态
                UI.Panel {
                    flexDirection = "row",
                    width = "100%",
                    justifyContent = "space-between",
                    children = {
                        UI.Label {
                            text = mail.title or "(无标题)",
                            fontSize = 13,
                            fontColor = { 220, 200, 150, 255 },
                            flexGrow = 1,
                        },
                        UI.Label {
                            text = statusText,
                            fontSize = 11,
                            fontColor = statusColor,
                        },
                    },
                },
                -- 第二行：内容
                UI.Label {
                    text = mail.content or "",
                    fontSize = 11,
                    fontColor = { 180, 180, 200, 255 },
                    whiteSpace = "normal",
                },
                -- 第三行：附件
                (attachText ~= "") and UI.Label {
                    text = "附件: " .. attachText,
                    fontSize = 11,
                    fontColor = { 255, 220, 100, 255 },
                } or UI.Panel { height = 0 },
                -- 第四行：发件人 + 领取按钮
                UI.Panel {
                    flexDirection = "row",
                    width = "100%",
                    justifyContent = "space-between",
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = "来自: " .. (mail.sender or "系统"),
                            fontSize = 10,
                            fontColor = { 120, 120, 140, 255 },
                        },
                        (hasAttachment and not mail.claimed) and UI.Button {
                            text = "领取",
                            variant = "success",
                            height = 24,
                            fontSize = 11,
                            onClick = function() MailboxUI.ClaimMail(i) end,
                        } or UI.Panel { width = 0 },
                    },
                },
            },
        }
        parentRef_:AddChild(mailPanel)
    end
end

--- 领取单封邮件附件
---@param index number
function MailboxUI.ClaimMail(index)
    local mail = mails_[index]
    if not mail or mail.claimed then return end

    local player = DataManager.playerData
    if not player then return end

    -- 发放多货币
    if mail.currencies and next(mail.currencies) then
        for cname, val in pairs(mail.currencies) do
            if val ~= "0" and val ~= "" then
                local cur = DataManager.GetPlayerCurrency(player, cname)
                DataManager.SetPlayerCurrency(player, cname, BigNum.add(cur, val))
            end
        end
    elseif mail.gold ~= "0" then
        -- 兼容旧格式（只有gold字段）
        player.status.gold = BigNum.add(player.status.gold or "0", mail.gold)
    end

    -- 发放物品 (格式: "物品名:数量,物品名2:数量")
    if mail.items ~= "" then
        for part in mail.items:gmatch("[^,]+") do
            local itemName, countStr = part:match("^(.+):(%d+)$")
            if itemName then
                local GameUI = require("UI.GameUI")
                GameUI.AddItemToBag(itemName, countStr)
            else
                -- 无数量默认1
                local GameUI = require("UI.GameUI")
                GameUI.AddItemToBag(part, "1")
            end
        end
    end

    -- 发放经验
    if mail.exp and mail.exp ~= "0" and BigNum.gt(mail.exp, "0") then
        player.status.exp = BigNum.add(player.status.exp or "0", mail.exp)
        local GameUI = require("UI.GameUI")
        if GameUI.CheckLevelUp then GameUI.CheckLevelUp() end
    end

    -- 发放战魂经验
    if mail.soul and mail.soul ~= "0" and BigNum.gt(mail.soul, "0") then
        player.status.battle_soul_exp = BigNum.add(player.status.battle_soul_exp or "0", mail.soul)
    end

    -- 标记已领取
    mail.claimed = true
    mails_[index] = mail

    -- 保存
    DataManager.SaveToCloud(player)
    SaveMails(function()
        MailboxUI.Refresh()
    end)
end

--- 一键领取所有未领取邮件
function MailboxUI.ClaimAll()
    local player = DataManager.playerData
    if not player then return end

    local claimedCount = 0
    local hasExpGain = false
    for _, mail in ipairs(mails_) do
        local hasCurr = mail.currencies and next(mail.currencies)
        local hasExp = mail.exp and mail.exp ~= "0" and BigNum.gt(mail.exp, "0")
        local hasSoul = mail.soul and mail.soul ~= "0" and BigNum.gt(mail.soul, "0")
        if not mail.claimed and (mail.gold ~= "0" or hasCurr or mail.items ~= "" or hasExp or hasSoul) then
            -- 发放多货币
            if hasCurr then
                for cname, val in pairs(mail.currencies) do
                    if val ~= "0" and val ~= "" then
                        local cur = DataManager.GetPlayerCurrency(player, cname)
                        DataManager.SetPlayerCurrency(player, cname, BigNum.add(cur, val))
                    end
                end
            elseif mail.gold ~= "0" then
                -- 兼容旧格式
                player.status.gold = BigNum.add(player.status.gold or "0", mail.gold)
            end
            -- 发放物品
            if mail.items ~= "" then
                for part in mail.items:gmatch("[^,]+") do
                    local itemName, countStr = part:match("^(.+):(%d+)$")
                    if itemName then
                        local GameUI = require("UI.GameUI")
                        GameUI.AddItemToBag(itemName, countStr)
                    else
                        local GameUI = require("UI.GameUI")
                        GameUI.AddItemToBag(part, "1")
                    end
                end
            end
            -- 发放经验
            if hasExp then
                player.status.exp = BigNum.add(player.status.exp or "0", mail.exp)
                hasExpGain = true
            end
            -- 发放战魂经验
            if hasSoul then
                player.status.battle_soul_exp = BigNum.add(player.status.battle_soul_exp or "0", mail.soul)
            end
            mail.claimed = true
            claimedCount = claimedCount + 1
        end
    end

    -- 批量领取后统一检查升级
    if hasExpGain then
        local GameUI = require("UI.GameUI")
        if GameUI.CheckLevelUp then GameUI.CheckLevelUp() end
    end

    if claimedCount > 0 then
        DataManager.SaveToCloud(player)
        SaveMails(function()
            MailboxUI.Refresh()
        end)
    end
end

return MailboxUI
