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
                text = "凡 人 修 仙 传",
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

    -- 从云端验证账号（传入用户名构建路径 player/用户名/）
    DataManager.currentAccount = username
    DataManager.LoadFromCloud(function(playerData)
        if playerData and playerData.account and playerData.account.username == username then
            -- 登录成功，加载玩家数据
            DataManager.playerData = playerData
            print("[LoginUI] 登录成功!")
            msgLabel_:SetText("")
            SwitchState("game")
        else
            -- 云端无此账号数据，提示注册
            DataManager.currentAccount = nil
            msgLabel_:SetText("账号不存在或密码错误，请注册")
        end
    end, username)
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

    -- 先检查云端该账号是否已有存档
    DataManager.LoadFromCloud(function(playerData)
        if playerData and playerData.account and playerData.account.username then
            -- 云端已有此账号，不允许重复注册
            print("[LoginUI] 云端已有账号: " .. playerData.account.username)
            msgLabel_:SetText("账号「" .. playerData.account.username .. "」已存在，请直接登录")
        else
            -- 云端无存档，可以注册
            DataManager.currentAccount = username
            msgLabel_:SetText("")
            SwitchState("create_char")
        end
    end, username)
end

return LoginUI
