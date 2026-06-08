--------------------------------------------
-- NumFormat.lua - 数字格式化工具
-- 基于 BigNum 大数库，精确显示任意位数
--------------------------------------------
local BigNum = require("Utils.BigNum")

local NumFormat = {}

--- 将数字格式化为纯整数字符串（无科学计数法）
---@param n number|string|nil
---@return string
function NumFormat.Int(n)
    return BigNum.new(n)
end

--- 将大数格式化为逐级中文单位显示，精确到个位
--- 例如：9999999999999999 → "9999兆9999亿9999万9999"
---@param n number|string|nil
---@return string
function NumFormat.Short(n)
    return BigNum.toShort(n)
end

return NumFormat
