---------------------------------------------------
-- LoginUI.lua - 登录/注册界面
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")

local LoginUI = {}

local usernameField_ = nil
local passwordField_ = nil
local msgLabel_ = nil

--- 创建登录界面
---@return Widget
function LoginUI.Create()
    usernameField_ = UI.TextField {
        placeholder = "请输入账号",
        maxLength = 20,
        width = 250,
        height = 40,
    }

    passwordField_ = UI.TextField {
        placeholder = "请输入密码",
        maxLength = 20,
        width = 250,
        height = 40,
    }

    msgLabel_ = UI.Label {
        id = "loginMsg",
        text = "",
        fontSize = 13,
        fontColor = { 255, 100, 100, 255 },
        textAlign = "center",
        height = 20,
    }

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 15, 10, 30, 255 },
        children = {
            -- 标题
            UI.Label {
                text = "创 世 修 仙",
                fontSize = 36,
                fontColor = { 200, 170, 100, 255 },
                textAlign = "center",
                marginBottom = 8,
            },
            UI.Label {
                text = "踏入修仙界，逆天改命",
                fontSize = 14,
                fontColor = { 150, 150, 180, 255 },
                textAlign = "center",
                marginBottom = 40,
            },

            -- 登录面板
            UI.Panel {
                width = 320,
                flexDirection = "column",
                alignItems = "center",
                backgroundColor = { 30, 25, 50, 220 },
                borderRadius = 12,
                padding = 24,
                gap = 12,
                children = {
                    UI.Label {
                        text = "账号登录",
                        fontSize = 18,
                        fontColor = { 220, 200, 150, 255 },
                        textAlign = "center",
                        marginBottom = 8,
                    },
                    usernameField_,
                    passwordField_,
                    msgLabel_,
                    -- 按钮行
                    UI.Panel {
                        flexDirection = "row",
                        gap = 16,
                        marginTop = 8,
                        children = {
                            UI.Button {
                                text = "登 录",
                                variant = "primary",
                                width = 100,
                                onClick = function() LoginUI.DoLogin() end,
                            },
                            UI.Button {
                                text = "注 册",
                                variant = "secondary",
                                width = 100,
                                onClick = function() LoginUI.DoRegister() end,
                            },
                        },
                    },
                },
            },

            -- 底部提示
            UI.Label {
                text = "首次游玩请先注册账号",
                fontSize = 12,
                fontColor = { 100, 100, 130, 255 },
                textAlign = "center",
                marginTop = 20,
            },

            -- 管理员入口
            UI.Button {
                text = "管理员登录",
                variant = "text",
                fontSize = 11,
                fontColor = { 80, 80, 110, 255 },
                marginTop = 12,
                onClick = function() SwitchState("admin_login") end,
            },
        },
    }

    return root
end

--- 执行登录
function LoginUI.DoLogin()
    local username = usernameField_:GetValue()
    local password = passwordField_:GetValue()

    if not username or username == "" then
        msgLabel_:SetText("请输入账号")
        return
    end
    if not password or password == "" then
        msgLabel_:SetText("请输入密码")
        return
    end

    print("[LoginUI] 尝试登录: " .. username)
    msgLabel_:SetText("正在登录...")

    -- 从集中式账号配置验证
    DataManager.VerifyLogin(username, password, function(success, charName, errorMsg)
        if not success then
            DataManager.currentAccount = nil
            msgLabel_:SetText(errorMsg or "登录失败")
            return
        end

        -- 验证通过，加载游戏数据
        DataManager.currentAccount = username
        DataManager.currentPassword = password
        DataManager.LoadFromCloud(function(playerData)
            if not playerData then
                -- 账号存在但无游戏数据，可能是旧账号，创建默认数据
                playerData = DataManager.CreateNewPlayer(username, charName or username)
                DataManager.SaveToCloud(playerData)
            end
            DataManager.playerData = playerData
            -- 确保 account 字段正确
            playerData.account.username = username
            playerData.account.password = password
            playerData.account.char_name = charName or playerData.status.name or username
            print("[LoginUI] 登录成功!")
            msgLabel_:SetText("")
            SwitchState("game")
        end, username)
    end)
end

--- 执行注册
function LoginUI.DoRegister()
    local username = usernameField_:GetValue()
    local password = passwordField_:GetValue()

    if not username or username == "" then
        msgLabel_:SetText("请输入账号")
        return
    end
    if not password or password == "" then
        msgLabel_:SetText("请输入密码")
        return
    end
    if #username < 2 then
        msgLabel_:SetText("账号至少2个字符")
        return
    end
    if #password < 3 then
        msgLabel_:SetText("密码至少3个字符")
        return
    end

    print("[LoginUI] 注册新账号: " .. username)
    msgLabel_:SetText("正在检查...")

    -- 从集中式账号配置检查是否已存在
    DataManager.CheckAccountExists(username, function(exists)
        if exists then
            msgLabel_:SetText("账号「" .. username .. "」已存在，请直接登录")
        else
            -- 可以注册，进入角色创建
            DataManager.currentAccount = username
            DataManager.currentPassword = password
            msgLabel_:SetText("")
            SwitchState("create_char")
        end
    end)
end

return LoginUI
