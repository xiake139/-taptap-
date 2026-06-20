---------------------------------------------------
-- EquipSlots.lua - 装备部位统一管理模块
-- 所有文件引用此模块获取部位列表和映射,不再各自硬编码
-- 管理员可通过 game_config [装备部位] 自定义部位列表
---------------------------------------------------

local EquipSlots = {}

-- 默认部位(已移除坐骑):12个
local DEFAULT_SLOTS_STR = "weapon:武器,helmet:头盔,armor:铠甲,bracer:护腕,belt:腰带,boots:战靴,cloak:披风,necklace:项链,ring:戒指,artifact:法宝,wings:灵翼,shield:护盾"

--- 当前生效的部位列表(有序)
---@type {key:string, label:string}[]
EquipSlots.slots = {}

--- 中文名 → 英文key 映射
---@type table<string, string>
EquipSlots.cnToKey = {}

--- 英文key → 中文名 映射
---@type table<string, string>
EquipSlots.keyToLabel = {}

--- 有序的中文名列表(供后台按钮选择器用)
---@type string[]
EquipSlots.labels = {}

--- 有序的英文key列表(供属性计算遍历用)
---@type string[]
EquipSlots.keys = {}

--- 解析 "weapon:武器,helmet:头盔,..." 格式字符串
---@param str string
local function ParseSlotString(str)
    local result = {}
    for item in str:gmatch("[^,]+") do
        local key, label = item:match("^%s*([^:]+):(.+)%s*$")
        if key and label then
            key = key:match("^%s*(.-)%s*$")
            label = label:match("^%s*(.-)%s*$")
            result[#result + 1] = { key = key, label = label }
        end
    end
    return result
end

--- 用解析后的列表刷新所有映射表
---@param list {key:string, label:string}[]
local function RefreshMappings(list)
    EquipSlots.slots = list
    EquipSlots.cnToKey = {}
    EquipSlots.keyToLabel = {}
    EquipSlots.labels = {}
    EquipSlots.keys = {}
    for _, s in ipairs(list) do
        EquipSlots.cnToKey[s.label] = s.key
        EquipSlots.keyToLabel[s.key] = s.label
        EquipSlots.labels[#EquipSlots.labels + 1] = s.label
        EquipSlots.keys[#EquipSlots.keys + 1] = s.key
    end
    -- 兼容性:额外映射
    EquipSlots.cnToKey["防具"] = "armor"
    EquipSlots.cnToKey["饰品"] = "accessory"
end

--- 从 gameConfig 加载自定义部位(由 DataManager.LoadSystemData 调用)
--- gameConfig 是解析后的 table: { ["装备部位"] = { 列表 = "weapon:武器,..." } }
---@param gameConfig table|nil
function EquipSlots.LoadFromConfig(gameConfig)
    local section = gameConfig and gameConfig["装备部位"]
    local str = section and section["列表"]
    if str and str ~= "" then
        local list = ParseSlotString(str)
        if #list > 0 then
            RefreshMappings(list)
            return
        end
    end
    -- 无自定义配置时用默认
    RefreshMappings(ParseSlotString(DEFAULT_SLOTS_STR))
end

--- 序列化当前部位列表为 "weapon:武器,helmet:头盔,..." 格式
---@return string
function EquipSlots.Serialize()
    local parts = {}
    for _, s in ipairs(EquipSlots.slots) do
        parts[#parts + 1] = s.key .. ":" .. s.label
    end
    return table.concat(parts, ",")
end

--- 添加一个部位(末尾追加)
---@param key string 英文key(如 "earring")
---@param label string 中文名(如 "耳环")
---@return boolean success
function EquipSlots.Add(key, label)
    if not key or key == "" or not label or label == "" then return false end
    if EquipSlots.keyToLabel[key] or EquipSlots.cnToKey[label] then return false end -- 已存在
    EquipSlots.slots[#EquipSlots.slots + 1] = { key = key, label = label }
    EquipSlots.cnToKey[label] = key
    EquipSlots.keyToLabel[key] = label
    EquipSlots.labels[#EquipSlots.labels + 1] = label
    EquipSlots.keys[#EquipSlots.keys + 1] = key
    return true
end

--- 删除一个部位(按key)
---@param key string
---@return boolean success
function EquipSlots.Remove(key)
    if not key or not EquipSlots.keyToLabel[key] then return false end
    local label = EquipSlots.keyToLabel[key]
    -- 从有序列表移除
    for i = #EquipSlots.slots, 1, -1 do
        if EquipSlots.slots[i].key == key then
            table.remove(EquipSlots.slots, i)
            break
        end
    end
    EquipSlots.cnToKey[label] = nil
    EquipSlots.keyToLabel[key] = nil
    -- 重建 labels/keys
    EquipSlots.labels = {}
    EquipSlots.keys = {}
    for _, s in ipairs(EquipSlots.slots) do
        EquipSlots.labels[#EquipSlots.labels + 1] = s.label
        EquipSlots.keys[#EquipSlots.keys + 1] = s.key
    end
    return true
end

--- 初始化(无配置时加载默认)
EquipSlots.LoadFromConfig(nil)

return EquipSlots
