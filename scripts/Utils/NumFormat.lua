--------------------------------------------
-- NumFormat.lua - 数字格式化工具
-- 基于 BigNum 大数库，精确显示任意位数
-- 支持两种显示模式切换:
--   "unit" - 计数单位模式（万、亿、兆...）
--   "raw"  - 纯数字模式（完整数字显示）
--------------------------------------------
local BigNum = require("Utils.BigNum")

local NumFormat = {}

--- 当前显示模式: "unit" | "raw"
NumFormat.mode = "unit"

--- 切换显示模式
function NumFormat.ToggleMode()
    if NumFormat.mode == "unit" then
        NumFormat.mode = "raw"
    else
        NumFormat.mode = "unit"
    end
    return NumFormat.mode
end

--- 设置显示模式
---@param mode string "unit" | "raw"
function NumFormat.SetMode(mode)
    if mode == "unit" or mode == "raw" then
        NumFormat.mode = mode
    end
end

--- 获取当前模式的中文描述
---@return string
function NumFormat.GetModeLabel()
    if NumFormat.mode == "unit" then
        return "计数单位"
    else
        return "纯数字"
    end
end

--- 将数字格式化为纯整数字符串（无科学计数法）
---@param n number|string|nil
---@return string
function NumFormat.Int(n)
    return BigNum.new(n)
end

--- 将大数格式化显示，根据当前模式选择格式
--- unit模式：9999999999999999 → "9999兆9999亿9999万9999"
--- raw模式：9999999999999999 → "9999999999999999"
---@param n number|string|nil
---@return string
function NumFormat.Short(n)
    if NumFormat.mode == "raw" then
        return BigNum.new(n)
    end
    return BigNum.toShort(n)
end

return NumFormat
