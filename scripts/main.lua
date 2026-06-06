---------------------------------------------------
-- main.lua - 凡人修仙传 主入口
-- 文字修仙游戏，基于 UrhoX UI 系统
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")

-- 全局变量
---@type Widget
local uiRoot_ = nil

-- 游戏状态枚举
local GameState = {
    LOGIN = "login",
    CREATE_CHAR = "create_char",
    GAME = "game",
}
local currentState_ = GameState.LOGIN

-- UI 模块（延迟加载）
local LoginUI = nil
local CreateCharUI = nil
local GameUI = nil

function Start()
    graphics.windowTitle = "凡人修仙传"
    print("[Main] 游戏启动...")

    -- 加载系统数据
    DataManager.LoadSystemData()

    -- 初始化 UI
    InitUI()

    -- 显示登录界面
    ShowLogin()

    SubscribeToEvent("KeyDown", "HandleKeyDown")
end

function Stop()
    UI.Shutdown()
end

function InitUI()
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })
end

--- 切换游戏状态
---@param state string
function SwitchState(state)
    currentState_ = state
    if state == GameState.LOGIN then
        ShowLogin()
    elseif state == GameState.CREATE_CHAR then
        ShowCreateChar()
    elseif state == GameState.GAME then
        ShowGame()
    end
end

--- 显示登录界面
function ShowLogin()
    if not LoginUI then
        LoginUI = require("UI.LoginUI")
    end
    local root = LoginUI.Create()
    UI.SetRoot(root)
    uiRoot_ = root
end

--- 显示角色创建界面
function ShowCreateChar()
    if not CreateCharUI then
        CreateCharUI = require("UI.CreateCharUI")
    end
    local root = CreateCharUI.Create()
    UI.SetRoot(root)
    uiRoot_ = root
end

--- 显示主游戏界面
function ShowGame()
    if not GameUI then
        GameUI = require("UI.GameUI")
    end
    local root = GameUI.Create()
    UI.SetRoot(root)
    uiRoot_ = root
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if key == KEY_ESCAPE then
        -- ESC 键处理
        if currentState_ == GameState.GAME and GameUI and GameUI.HandleEscape then
            GameUI.HandleEscape()
        end
    end
end
