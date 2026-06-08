--------------------------------------------
-- BigNum.lua - 大数运算库
-- 用字符串存储整数，支持任意位数精确计算
-- 所有函数接受 number 或 string，返回 string
--------------------------------------------
local BigNum = {}

--------------------------------------------
-- 内部工具
--------------------------------------------

--- 规范化：去除前导零，处理负号，空/nil 变 "0"
---@param s string|number|nil
---@return string
local function normalize(s)
    if s == nil then return "0" end
    s = tostring(s)
    -- 去除空白
    s = s:match("^%s*(.-)%s*$") or "0"
    if s == "" then return "0" end

    -- 处理科学计数法（如 "2.35e+22"）
    local num = tonumber(s)
    if num and (s:find("[eE]") or s:find("%.")) then
        -- 有科学计数法或小数点，用 %.0f 转换再规范化
        if num >= 0 then
            s = string.format("%.0f", math.floor(num))
        else
            s = "-" .. string.format("%.0f", math.floor(-num))
        end
    end

    local neg = false
    if s:sub(1, 1) == "-" then
        neg = true
        s = s:sub(2)
    end
    -- 去除前导零
    s = s:match("^0*(%d+)$") or "0"
    if s == "" then s = "0" end
    if s == "0" then return "0" end
    if neg then return "-" .. s end
    return s
end

--- 判断是否为负数
local function isNeg(s)
    return s:sub(1, 1) == "-"
end

--- 取绝对值字符串
local function absStr(s)
    if isNeg(s) then return s:sub(2) end
    return s
end

--- 比较两个正数字符串大小，返回 1, 0, -1
local function comparePositive(a, b)
    if #a ~= #b then
        return #a > #b and 1 or -1
    end
    -- 同长度，逐位比较
    if a > b then return 1
    elseif a < b then return -1
    else return 0
    end
end

--- 正数加法（a, b 都是正数字符串）
local function addPositive(a, b)
    -- 补齐长度
    local len = math.max(#a, #b)
    a = string.rep("0", len - #a) .. a
    b = string.rep("0", len - #b) .. b

    local result = {}
    local carry = 0
    for i = len, 1, -1 do
        local sum = tonumber(a:sub(i, i)) + tonumber(b:sub(i, i)) + carry
        carry = math.floor(sum / 10)
        result[len - i + 1] = sum % 10
    end
    if carry > 0 then
        result[#result + 1] = carry
    end

    -- 反转拼接
    local s = ""
    for i = #result, 1, -1 do
        s = s .. tostring(result[i])
    end
    return s
end

--- 正数减法（a >= b，都是正数字符串）
local function subPositive(a, b)
    local len = math.max(#a, #b)
    a = string.rep("0", len - #a) .. a
    b = string.rep("0", len - #b) .. b

    local result = {}
    local borrow = 0
    for i = len, 1, -1 do
        local diff = tonumber(a:sub(i, i)) - tonumber(b:sub(i, i)) - borrow
        if diff < 0 then
            diff = diff + 10
            borrow = 1
        else
            borrow = 0
        end
        result[len - i + 1] = diff
    end

    -- 反转拼接，去前导零
    local s = ""
    local started = false
    for i = #result, 1, -1 do
        if result[i] ~= 0 then started = true end
        if started then
            s = s .. tostring(result[i])
        end
    end
    return s == "" and "0" or s
end

--- 正数乘法（竖式乘法）
local function mulPositive(a, b)
    -- 短的放后面提高效率
    if #a < #b then a, b = b, a end
    local lenA, lenB = #a, #b
    local result = {}
    for i = 1, lenA + lenB do result[i] = 0 end

    for i = lenA, 1, -1 do
        local da = tonumber(a:sub(i, i))
        for j = lenB, 1, -1 do
            local db = tonumber(b:sub(j, j))
            local pos = (lenA - i) + (lenB - j) + 1
            result[pos] = result[pos] + da * db
        end
    end

    -- 进位
    for i = 1, #result - 1 do
        if result[i] >= 10 then
            result[i + 1] = result[i + 1] + math.floor(result[i] / 10)
            result[i] = result[i] % 10
        end
    end

    -- 反转拼接，去前导零
    local s = ""
    local started = false
    for i = #result, 1, -1 do
        if result[i] ~= 0 then started = true end
        if started then
            s = s .. tostring(result[i])
        end
    end
    return s == "" and "0" or s
end

--- 正数除法（长除法），返回商和余数
local function divPositive(a, b)
    if b == "0" then return "0", "0" end -- 除以0返回0
    local cmp = comparePositive(a, b)
    if cmp < 0 then return "0", a end
    if cmp == 0 then return "1", "0" end

    local quotient = ""
    local current = ""
    for i = 1, #a do
        current = current .. a:sub(i, i)
        -- 去前导零
        current = current:match("^0*(%d+)$") or "0"

        -- 用减法模拟除法（优化：二分查找商的每一位）
        local digit = 0
        local lo, hi = 0, 9
        while lo <= hi do
            local mid = math.floor((lo + hi) / 2)
            local product = mulPositive(b, tostring(mid))
            if comparePositive(product, current) <= 0 then
                digit = mid
                lo = mid + 1
            else
                hi = mid - 1
            end
        end

        quotient = quotient .. tostring(digit)
        if digit > 0 then
            local product = mulPositive(b, tostring(digit))
            current = subPositive(current, product)
        end
    end

    -- 去前导零
    quotient = quotient:match("^0*(%d+)$") or "0"
    return quotient, current
end

--------------------------------------------
-- 公开 API
--------------------------------------------

--- 创建/规范化大数（接受 number, string, nil）
---@param n number|string|nil
---@return string
function BigNum.new(n)
    return normalize(n)
end

--- 加法
---@param a string|number|nil
---@param b string|number|nil
---@return string
function BigNum.add(a, b)
    a = normalize(a)
    b = normalize(b)

    local aNeg = isNeg(a)
    local bNeg = isNeg(b)
    local aAbs = absStr(a)
    local bAbs = absStr(b)

    if not aNeg and not bNeg then
        -- 两正
        return addPositive(aAbs, bAbs)
    elseif aNeg and bNeg then
        -- 两负
        local r = addPositive(aAbs, bAbs)
        return r == "0" and "0" or ("-" .. r)
    elseif aNeg then
        -- a负b正 = b - |a|
        local cmp = comparePositive(bAbs, aAbs)
        if cmp >= 0 then
            return subPositive(bAbs, aAbs)
        else
            return "-" .. subPositive(aAbs, bAbs)
        end
    else
        -- a正b负 = a - |b|
        local cmp = comparePositive(aAbs, bAbs)
        if cmp >= 0 then
            return subPositive(aAbs, bAbs)
        else
            return "-" .. subPositive(bAbs, aAbs)
        end
    end
end

--- 减法
---@param a string|number|nil
---@param b string|number|nil
---@return string
function BigNum.sub(a, b)
    b = normalize(b)
    -- a - b = a + (-b)
    if isNeg(b) then
        return BigNum.add(a, b:sub(2))
    elseif b == "0" then
        return normalize(a)
    else
        return BigNum.add(a, "-" .. b)
    end
end

--- 乘法
---@param a string|number|nil
---@param b string|number|nil
---@return string
function BigNum.mul(a, b)
    a = normalize(a)
    b = normalize(b)
    if a == "0" or b == "0" then return "0" end

    local neg = isNeg(a) ~= isNeg(b)
    local result = mulPositive(absStr(a), absStr(b))
    if result == "0" then return "0" end
    return neg and ("-" .. result) or result
end

--- 整数除法（向下取整）
---@param a string|number|nil
---@param b string|number|nil
---@return string 商
function BigNum.div(a, b)
    a = normalize(a)
    b = normalize(b)
    if b == "0" then return "0" end
    if a == "0" then return "0" end

    local neg = isNeg(a) ~= isNeg(b)
    local quotient, _ = divPositive(absStr(a), absStr(b))
    if quotient == "0" then return "0" end
    return neg and ("-" .. quotient) or quotient
end

--- 取模
---@param a string|number|nil
---@param b string|number|nil
---@return string 余数
function BigNum.mod(a, b)
    a = normalize(a)
    b = normalize(b)
    if b == "0" then return "0" end
    if a == "0" then return "0" end
    local _, remainder = divPositive(absStr(a), absStr(b))
    return remainder
end

--- 比较：返回 -1, 0, 1
---@param a string|number|nil
---@param b string|number|nil
---@return integer
function BigNum.compare(a, b)
    a = normalize(a)
    b = normalize(b)

    local aNeg = isNeg(a)
    local bNeg = isNeg(b)

    if aNeg and not bNeg then return -1 end
    if not aNeg and bNeg then return 1 end

    local aAbs = absStr(a)
    local bAbs = absStr(b)
    local cmp = comparePositive(aAbs, bAbs)

    if aNeg then return -cmp end -- 都是负数，绝对值大的反而小
    return cmp
end

--- a > b
function BigNum.gt(a, b) return BigNum.compare(a, b) > 0 end
--- a >= b
function BigNum.gte(a, b) return BigNum.compare(a, b) >= 0 end
--- a < b
function BigNum.lt(a, b) return BigNum.compare(a, b) < 0 end
--- a <= b
function BigNum.lte(a, b) return BigNum.compare(a, b) <= 0 end
--- a == b
function BigNum.eq(a, b) return BigNum.compare(a, b) == 0 end

--- 取最大值
function BigNum.max(a, b)
    a = normalize(a)
    b = normalize(b)
    return BigNum.gte(a, b) and a or b
end

--- 取最小值
function BigNum.min(a, b)
    a = normalize(a)
    b = normalize(b)
    return BigNum.lte(a, b) and a or b
end

--- 是否为零
function BigNum.isZero(a)
    return normalize(a) == "0"
end

--- 是否为正数（> 0）
function BigNum.isPositive(a)
    a = normalize(a)
    return a ~= "0" and not isNeg(a)
end

--- 是否为负数（< 0）
function BigNum.isNegative(a)
    return isNeg(normalize(a))
end

--- 取绝对值
function BigNum.abs(a)
    return absStr(normalize(a))
end

--- 转为显示字符串（纯数字）
---@param a string|number|nil
---@return string
function BigNum.tostring(a)
    return normalize(a)
end

--- 带中文单位的显示（精确到个位）
---@param a string|number|nil
---@return string
function BigNum.toShort(a)
    a = normalize(a)
    if a == "0" then return "0" end

    local sign = ""
    if isNeg(a) then
        sign = "-"
        a = a:sub(2)
    end

    -- 单位表：从大到小（位数对应）
    local units = {
        { digits = 61, name = "那由他" },
        { digits = 57, name = "阿僧祇" },
        { digits = 53, name = "恒河沙" },
        { digits = 49, name = "极" },
        { digits = 45, name = "载" },
        { digits = 41, name = "正" },
        { digits = 37, name = "涧" },
        { digits = 33, name = "沟" },
        { digits = 29, name = "穣" },
        { digits = 25, name = "秭" },
        { digits = 21, name = "垓" },
        { digits = 17, name = "京" },
        { digits = 13, name = "兆" },
        { digits = 9,  name = "亿" },
        { digits = 5,  name = "万" },
    }

    local result = ""
    local remaining = a

    for _, u in ipairs(units) do
        if #remaining >= u.digits then
            -- 取出高位部分
            local highLen = #remaining - u.digits + 1
            local high = remaining:sub(1, highLen)
            remaining = remaining:sub(highLen + 1)
            -- 去前导零
            remaining = remaining:match("^0*(%d+)$") or ""
            result = result .. high .. u.name
        end
    end

    -- 剩余个位部分
    if remaining ~= "" and remaining ~= "0" then
        result = result .. remaining
    end

    if result == "" then return "0" end
    return sign .. result
end

return BigNum
