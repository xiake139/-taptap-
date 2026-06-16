---------------------------------------------------
-- MonsterGuideUI.lua - 怪物分布图鉴
-- 地图列表 → 怪物列表 → 怪物详情
---------------------------------------------------
local UI = require("urhox-libs/UI")
local DataManager = require("Systems.DataManager")
local IniParser = require("Utils.IniParser")
local NumFormat = require("Utils.NumFormat")

local MonsterGuideUI = {}

-- 分页与视图状态
local MAPS_PER_PAGE = 10
local currentPage_ = 1
local currentView_ = "maps"      -- "maps" | "monsters" | "detail" | "search"
local selectedMap_ = nil          -- 当前选中的地图名
local selectedMonster_ = nil      -- 当前选中的怪物名
local parentPanel_ = nil          -- 渲染父容器
local searchKeyword_ = ""         -- 搜索关键字
local searchFrom_ = "maps"       -- 搜索前的来源视图（用于返回）

--- 获取所有地图列表（排序）
---@return table[]
local function GetAllMaps()
    local list = {}
    for name, data in pairs(DataManager.maps) do
        table.insert(list, { name = name, data = data })
    end
    -- 按等级要求排序，等级相同按名称
    table.sort(list, function(a, b)
        local la = tonumber(a.data.level_req) or 0
        local lb = tonumber(b.data.level_req) or 0
        if la ~= lb then return la < lb end
        return a.name < b.name
    end)
    return list
end

--- 渲染入口
---@param container Widget
function MonsterGuideUI.Render(container)
    parentPanel_ = container
    currentView_ = "maps"
    currentPage_ = 1
    selectedMap_ = nil
    selectedMonster_ = nil
    MonsterGuideUI.RenderMaps()
end

--- 渲染地图列表（分页）
function MonsterGuideUI.RenderMaps()
    if not parentPanel_ then return end
    parentPanel_:ClearChildren()
    currentView_ = "maps"

    local allMaps = GetAllMaps()
    local totalMaps = #allMaps
    local totalPages = math.max(1, math.ceil(totalMaps / MAPS_PER_PAGE))

    if currentPage_ > totalPages then currentPage_ = totalPages end
    if currentPage_ < 1 then currentPage_ = 1 end

    local startIdx = (currentPage_ - 1) * MAPS_PER_PAGE + 1
    local endIdx = math.min(startIdx + MAPS_PER_PAGE - 1, totalMaps)

    -- 标题 + 搜索按钮
    parentPanel_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        marginBottom = 6,
        children = {
            UI.Label {
                text = "— 怪物分布图鉴 —",
                fontSize = 16,
                fontColor = { 255, 200, 100, 255 },
                textAlign = "center",
                flexGrow = 1,
            },
            UI.Button {
                text = "搜索",
                variant = "primary",
                width = 56,
                height = 28,
                fontSize = 12,
                onClick = function()
                    searchFrom_ = "maps"
                    MonsterGuideUI.RenderSearchView()
                end,
            },
        },
    })

    -- 分页信息
    parentPanel_:AddChild(UI.Label {
        text = "共 " .. totalMaps .. " 张地图 | 第 " .. currentPage_ .. "/" .. totalPages .. " 页",
        fontSize = 11,
        fontColor = { 160, 160, 180, 255 },
        textAlign = "center",
        width = "100%",
        marginBottom = 6,
    })

    -- 地图列表
    for i = startIdx, endIdx do
        local mapInfo = allMaps[i]
        if mapInfo then
            local mapData = mapInfo.data
            local monsterList = IniParser.ParseList(mapData.monsters or "")
            local monsterCount = #monsterList
            local levelReq = tonumber(mapData.level_req) or 0

            parentPanel_:AddChild(UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                padding = 8,
                marginBottom = 4,
                backgroundColor = { 35, 30, 55, 200 },
                borderRadius = 6,
                children = {
                    -- 地图信息
                    UI.Panel {
                        flexGrow = 1,
                        flexDirection = "column",
                        gap = 2,
                        children = {
                            UI.Label {
                                text = mapInfo.name,
                                fontSize = 14,
                                fontColor = { 220, 200, 255, 255 },
                            },
                            UI.Label {
                                text = "等级要求: " .. (levelReq > 0 and tostring(levelReq) or "无") .. " | 怪物: " .. monsterCount .. "种",
                                fontSize = 11,
                                fontColor = { 140, 140, 160, 255 },
                            },
                        },
                    },
                    -- 查看按钮
                    UI.Button {
                        text = "查看",
                        variant = "secondary",
                        width = 56,
                        height = 28,
                        fontSize = 12,
                        onClick = (function(mName)
                            return function()
                                selectedMap_ = mName
                                MonsterGuideUI.RenderMonsters()
                            end
                        end)(mapInfo.name),
                    },
                },
            })
        end
    end

    -- 空状态
    if totalMaps == 0 then
        parentPanel_:AddChild(UI.Label {
            text = "暂无地图数据",
            fontSize = 13,
            fontColor = { 150, 150, 150, 255 },
            textAlign = "center",
            width = "100%",
            marginTop = 20,
        })
    end

    -- 分页按钮
    local pageChildren = {}
    if currentPage_ > 1 then
        table.insert(pageChildren, UI.Button {
            text = "上一页",
            variant = "secondary",
            flexGrow = 1,
            height = 30,
            onClick = function()
                currentPage_ = currentPage_ - 1
                MonsterGuideUI.RenderMaps()
            end,
        })
    end
    table.insert(pageChildren, UI.Label {
        text = currentPage_ .. "/" .. totalPages,
        fontSize = 12,
        fontColor = { 180, 180, 200, 255 },
        textAlign = "center",
        flexGrow = 1,
    })
    if currentPage_ < totalPages then
        table.insert(pageChildren, UI.Button {
            text = "下一页",
            variant = "secondary",
            flexGrow = 1,
            height = 30,
            onClick = function()
                currentPage_ = currentPage_ + 1
                MonsterGuideUI.RenderMaps()
            end,
        })
    end

    parentPanel_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        marginTop = 8,
        children = pageChildren,
    })
end

--- 渲染某地图的怪物列表
function MonsterGuideUI.RenderMonsters()
    if not parentPanel_ or not selectedMap_ then return end
    parentPanel_:ClearChildren()
    currentView_ = "monsters"

    local mapData = DataManager.GetMap(selectedMap_)
    local monsterNames = IniParser.ParseList(mapData and mapData.monsters or "")

    -- 标题 + 返回
    parentPanel_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        marginBottom = 8,
        children = {
            UI.Button {
                text = "< 返回",
                variant = "outline",
                width = 70,
                height = 28,
                fontSize = 12,
                onClick = function()
                    MonsterGuideUI.RenderMaps()
                end,
            },
            UI.Label {
                text = "【" .. selectedMap_ .. "】怪物",
                fontSize = 15,
                fontColor = { 200, 170, 100, 255 },
                flexGrow = 1,
                textAlign = "center",
            },
        },
    })

    if #monsterNames == 0 then
        parentPanel_:AddChild(UI.Label {
            text = "此地图没有怪物",
            fontSize = 13,
            fontColor = { 150, 150, 150, 255 },
            textAlign = "center",
            width = "100%",
            marginTop = 20,
        })
        return
    end

    -- 怪物卡片列表
    for idx, mName in ipairs(monsterNames) do
        local mData = DataManager.monsters[mName]
        local mType = mData and mData.type or "未知"
        local mHp = mData and mData.hp or "?"

        -- 根据怪物类型设置颜色
        local typeColor = { 180, 180, 200, 255 }
        if mType == "创世级" then typeColor = { 255, 50, 50, 255 }
        elseif mType == "神级" then typeColor = { 255, 150, 0, 255 }
        elseif mType == "仙级" then typeColor = { 200, 100, 255, 255 }
        elseif mType == "帝级" then typeColor = { 255, 215, 0, 255 }
        elseif mType == "BOSS" then typeColor = { 255, 100, 100, 255 }
        elseif mType == "精英怪" then typeColor = { 100, 200, 255, 255 }
        end

        parentPanel_:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            padding = 8,
            marginBottom = 4,
            backgroundColor = (idx % 2 == 0) and { 40, 35, 60, 180 } or { 30, 25, 50, 150 },
            borderRadius = 6,
            children = {
                -- 怪物信息
                UI.Panel {
                    flexGrow = 1,
                    flexDirection = "column",
                    gap = 2,
                    children = {
                        UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            gap = 4,
                            children = {
                                UI.Label {
                                    text = "[" .. mType .. "]",
                                    fontSize = 11,
                                    fontColor = typeColor,
                                },
                                UI.Label {
                                    text = mName,
                                    fontSize = 14,
                                    fontColor = { 220, 220, 240, 255 },
                                },
                            },
                        },
                        UI.Label {
                            text = "HP: " .. NumFormat.Short(mHp),
                            fontSize = 11,
                            fontColor = { 140, 140, 160, 255 },
                        },
                    },
                },
                -- 详情按钮
                UI.Button {
                    text = "详情",
                    variant = "secondary",
                    width = 56,
                    height = 28,
                    fontSize = 12,
                    onClick = (function(name)
                        return function()
                            selectedMonster_ = name
                            MonsterGuideUI.RenderDetail()
                        end
                    end)(mName),
                },
            },
        })
    end
end

--- 渲染怪物详情
function MonsterGuideUI.RenderDetail()
    if not parentPanel_ or not selectedMonster_ then return end
    parentPanel_:ClearChildren()
    currentView_ = "detail"

    local mData = DataManager.monsters[selectedMonster_]
    if not mData then
        parentPanel_:AddChild(UI.Label { text = "怪物数据不存在", fontSize = 14, fontColor = { 255, 100, 100, 255 } })
        return
    end

    -- 记录从哪个视图进入详情（用于返回）
    local prevView = currentView_

    -- 标题 + 返回
    parentPanel_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        marginBottom = 8,
        children = {
            UI.Button {
                text = "< 返回",
                variant = "outline",
                width = 70,
                height = 28,
                fontSize = 12,
                onClick = function()
                    if searchFrom_ == "search" then
                        MonsterGuideUI.RenderSearchView()
                    elseif selectedMap_ then
                        MonsterGuideUI.RenderMonsters()
                    else
                        MonsterGuideUI.RenderMaps()
                    end
                end,
            },
            UI.Label {
                text = selectedMonster_,
                fontSize = 16,
                fontColor = { 220, 180, 100, 255 },
                flexGrow = 1,
                textAlign = "center",
            },
        },
    })

    -- 类型标签
    local mType = mData.type or "普通怪"
    local typeColor = { 180, 180, 200, 255 }
    if mType == "创世级" then typeColor = { 255, 50, 50, 255 }
    elseif mType == "神级" then typeColor = { 255, 150, 0, 255 }
    elseif mType == "仙级" then typeColor = { 200, 100, 255, 255 }
    elseif mType == "帝级" then typeColor = { 255, 215, 0, 255 }
    elseif mType == "BOSS" then typeColor = { 255, 100, 100, 255 }
    elseif mType == "精英怪" then typeColor = { 100, 200, 255, 255 }
    end

    parentPanel_:AddChild(UI.Label {
        text = "类型: " .. mType,
        fontSize = 13,
        fontColor = typeColor,
        textAlign = "center",
        width = "100%",
        marginBottom = 4,
    })

    -- 描述
    local descText = tostring(mData.desc or "")
    if descText ~= "" then
        parentPanel_:AddChild(UI.Label {
            text = descText,
            fontSize = 12,
            fontColor = { 160, 160, 180, 255 },
            textAlign = "center",
            width = "100%",
            marginBottom = 6,
        })
    end

    -- 分隔线
    parentPanel_:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 50, 90, 200 }, marginBottom = 8 })

    -- ===== 基础属性 =====
    parentPanel_:AddChild(UI.Label {
        text = "基础属性",
        fontSize = 13,
        fontColor = { 150, 220, 255, 255 },
        marginBottom = 4,
    })

    local statItems = {
        { label = "生命值", value = NumFormat.Short(mData.hp or "0"), color = { 100, 255, 100, 255 } },
        { label = "攻击力", value = NumFormat.Short(mData.atk or "0"), color = { 255, 150, 150, 255 } },
        { label = "防御力", value = NumFormat.Short(mData.def or "0"), color = { 150, 200, 255, 255 } },
    }

    for _, stat in ipairs(statItems) do
        parentPanel_:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            paddingLeft = 8, paddingRight = 8,
            marginBottom = 2,
            children = {
                UI.Label { text = stat.label, fontSize = 12, fontColor = { 180, 180, 200, 255 } },
                UI.Label { text = stat.value, fontSize = 12, fontColor = stat.color },
            },
        })
    end

    -- 分隔线
    parentPanel_:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 50, 90, 200 }, marginTop = 6, marginBottom = 8 })

    -- ===== 击杀奖励 =====
    parentPanel_:AddChild(UI.Label {
        text = "击杀奖励",
        fontSize = 13,
        fontColor = { 255, 220, 100, 255 },
        marginBottom = 4,
    })

    -- 经验值
    parentPanel_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        paddingLeft = 8, paddingRight = 8,
        marginBottom = 2,
        children = {
            UI.Label { text = "经验值", fontSize = 12, fontColor = { 180, 180, 200, 255 } },
            UI.Label { text = NumFormat.Short(mData.exp or "0"), fontSize = 12, fontColor = { 200, 255, 200, 255 } },
        },
    })

    -- 金币
    parentPanel_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        paddingLeft = 8, paddingRight = 8,
        marginBottom = 2,
        children = {
            UI.Label { text = "金币", fontSize = 12, fontColor = { 180, 180, 200, 255 } },
            UI.Label { text = NumFormat.Short(mData.gold or "0"), fontSize = 12, fontColor = { 255, 215, 0, 255 } },
        },
    })

    -- 货币掉落（多货币系统）
    if mData.currency_drops then
        for currName, currAmount in pairs(mData.currency_drops) do
            parentPanel_:AddChild(UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                paddingLeft = 8, paddingRight = 8,
                marginBottom = 2,
                children = {
                    UI.Label { text = currName, fontSize = 12, fontColor = { 180, 180, 200, 255 } },
                    UI.Label { text = NumFormat.Short(tostring(currAmount)), fontSize = 12, fontColor = { 200, 180, 255, 255 } },
                },
            })
        end
    end

    -- 战魂值
    local soulMin, soulMax = DataManager.GetBattleSoulRange(selectedMonster_)
    parentPanel_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        paddingLeft = 8, paddingRight = 8,
        marginBottom = 2,
        children = {
            UI.Label { text = "战魂经验", fontSize = 12, fontColor = { 180, 180, 200, 255 } },
            UI.Label { text = tostring(soulMin) .. " ~ " .. tostring(soulMax), fontSize = 12, fontColor = { 180, 130, 255, 255 } },
        },
    })

    -- 分隔线
    parentPanel_:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 50, 90, 200 }, marginTop = 6, marginBottom = 8 })

    -- ===== 掉落物品 =====
    parentPanel_:AddChild(UI.Label {
        text = "掉落物品",
        fontSize = 13,
        fontColor = { 100, 255, 200, 255 },
        marginBottom = 4,
    })

    local dropList = IniParser.ParseList(mData.drops or "")
    if #dropList == 0 then
        parentPanel_:AddChild(UI.Label {
            text = "无掉落",
            fontSize = 12,
            fontColor = { 120, 120, 140, 255 },
            paddingLeft = 8,
        })
    else
        for _, dropStr in ipairs(dropList) do
            -- 解析格式: "物品名:数量" 或 "物品名"
            local itemName, itemCount = dropStr:match("^(.+):(%d+)$")
            if not itemName then
                itemName = dropStr
                itemCount = "1"
            end

            parentPanel_:AddChild(UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                paddingLeft = 8, paddingRight = 8,
                marginBottom = 2,
                children = {
                    UI.Label { text = itemName, fontSize = 12, fontColor = { 220, 220, 240, 255 } },
                    UI.Label { text = "x" .. itemCount, fontSize = 12, fontColor = { 180, 180, 200, 255 } },
                },
            })
        end
    end
end

--- 渲染搜索视图
function MonsterGuideUI.RenderSearchView()
    if not parentPanel_ then return end
    parentPanel_:ClearChildren()
    currentView_ = "search"

    -- 标题 + 返回
    parentPanel_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        marginBottom = 8,
        children = {
            UI.Button {
                text = "< 返回",
                variant = "outline",
                width = 70,
                height = 28,
                fontSize = 12,
                onClick = function()
                    MonsterGuideUI.RenderMaps()
                end,
            },
            UI.Label {
                text = "搜索图鉴",
                fontSize = 15,
                fontColor = { 200, 170, 100, 255 },
                flexGrow = 1,
                textAlign = "center",
            },
        },
    })

    -- 搜索输入框 + 搜索按钮
    local searchField = UI.TextField {
        placeholder = "输入怪物名或地图名...",
        flexGrow = 1,
        height = 34,
        fontSize = 13,
        value = searchKeyword_,
    }

    parentPanel_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        marginBottom = 10,
        children = {
            searchField,
            UI.Button {
                text = "搜索",
                variant = "primary",
                width = 60,
                height = 34,
                fontSize = 13,
                onClick = function()
                    searchKeyword_ = searchField:GetValue() or ""
                    MonsterGuideUI.DoSearch(searchKeyword_)
                end,
            },
        },
    })

    -- 搜索提示
    parentPanel_:AddChild(UI.Label {
        id = "searchHint",
        text = "输入关键字后点击搜索，支持怪物名和地图名模糊匹配",
        fontSize = 11,
        fontColor = { 140, 140, 160, 255 },
        textAlign = "center",
        width = "100%",
        marginBottom = 6,
    })

    -- 搜索结果容器
    parentPanel_:AddChild(UI.Panel {
        id = "searchResults",
        width = "100%",
        flexDirection = "column",
    })

    -- 如果已有关键字，自动搜索
    if searchKeyword_ ~= "" then
        MonsterGuideUI.DoSearch(searchKeyword_)
    end
end

--- 执行搜索
---@param keyword string
function MonsterGuideUI.DoSearch(keyword)
    if not parentPanel_ then return end
    local resultsPanel = parentPanel_:FindById("searchResults")
    if not resultsPanel then return end
    resultsPanel:ClearChildren()

    local hint = parentPanel_:FindById("searchHint")

    if keyword == "" then
        if hint then hint:SetText("请输入搜索关键字") end
        return
    end

    local kw = keyword:lower()
    local matchedMaps = {}     -- { { name, data, matchType="map" } }
    local matchedMonsters = {} -- { { monsterName, maps={...} } }

    -- 搜索地图名
    for mapName, mapData in pairs(DataManager.maps) do
        if mapName:lower():find(kw, 1, true) then
            table.insert(matchedMaps, { name = mapName, data = mapData })
        end
    end

    -- 搜索怪物名，并收集其所在地图
    for monsterName, _ in pairs(DataManager.monsters) do
        if monsterName:lower():find(kw, 1, true) then
            local inMaps = {}
            for mapName, mapData in pairs(DataManager.maps) do
                local monsterList = IniParser.ParseList(mapData.monsters or "")
                for _, mName in ipairs(monsterList) do
                    if mName == monsterName then
                        table.insert(inMaps, mapName)
                        break
                    end
                end
            end
            table.insert(matchedMonsters, { name = monsterName, maps = inMaps })
        end
    end

    -- 排序
    table.sort(matchedMaps, function(a, b) return a.name < b.name end)
    table.sort(matchedMonsters, function(a, b) return a.name < b.name end)

    local totalResults = #matchedMaps + #matchedMonsters

    if hint then
        hint:SetText("找到 " .. totalResults .. " 条结果（地图 " .. #matchedMaps .. " / 怪物 " .. #matchedMonsters .. "）")
    end

    if totalResults == 0 then
        resultsPanel:AddChild(UI.Label {
            text = "未找到匹配结果",
            fontSize = 13,
            fontColor = { 200, 100, 100, 255 },
            textAlign = "center",
            width = "100%",
            marginTop = 12,
        })
        return
    end

    -- 显示匹配的地图
    if #matchedMaps > 0 then
        resultsPanel:AddChild(UI.Label {
            text = "匹配地图",
            fontSize = 13,
            fontColor = { 100, 200, 255, 255 },
            marginBottom = 4,
            marginTop = 4,
        })

        for _, mapInfo in ipairs(matchedMaps) do
            local mapData = mapInfo.data
            local monsterList = IniParser.ParseList(mapData.monsters or "")
            local monsterCount = #monsterList

            resultsPanel:AddChild(UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                padding = 8,
                marginBottom = 4,
                backgroundColor = { 35, 30, 55, 200 },
                borderRadius = 6,
                children = {
                    UI.Panel {
                        flexGrow = 1,
                        flexDirection = "column",
                        gap = 2,
                        children = {
                            UI.Label {
                                text = mapInfo.name,
                                fontSize = 14,
                                fontColor = { 220, 200, 255, 255 },
                            },
                            UI.Label {
                                text = "怪物: " .. monsterCount .. "种",
                                fontSize = 11,
                                fontColor = { 140, 140, 160, 255 },
                            },
                        },
                    },
                    UI.Button {
                        text = "查看",
                        variant = "secondary",
                        width = 56,
                        height = 28,
                        fontSize = 12,
                        onClick = (function(mName)
                            return function()
                                selectedMap_ = mName
                                MonsterGuideUI.RenderMonsters()
                            end
                        end)(mapInfo.name),
                    },
                },
            })
        end
    end

    -- 显示匹配的怪物
    if #matchedMonsters > 0 then
        resultsPanel:AddChild(UI.Label {
            text = "匹配怪物",
            fontSize = 13,
            fontColor = { 255, 180, 100, 255 },
            marginBottom = 4,
            marginTop = 8,
        })

        for _, monsterInfo in ipairs(matchedMonsters) do
            local mData = DataManager.monsters[monsterInfo.name]
            local mType = mData and mData.type or "未知"

            -- 根据怪物类型设置颜色
            local typeColor = { 180, 180, 200, 255 }
            if mType == "创世级" then typeColor = { 255, 50, 50, 255 }
            elseif mType == "神级" then typeColor = { 255, 150, 0, 255 }
            elseif mType == "仙级" then typeColor = { 200, 100, 255, 255 }
            elseif mType == "帝级" then typeColor = { 255, 215, 0, 255 }
            elseif mType == "BOSS" then typeColor = { 255, 100, 100, 255 }
            elseif mType == "精英怪" then typeColor = { 100, 200, 255, 255 }
            end

            -- 分布地图分页（每页10个）
            local DIST_PER_PAGE = 10
            local allDistMaps = monsterInfo.maps
            local distTotal = #allDistMaps
            local distPages = math.max(1, math.ceil(distTotal / DIST_PER_PAGE))

            -- 怪物卡片容器
            local monsterCard = UI.Panel {
                id = "monsterCard_" .. monsterInfo.name,
                width = "100%",
                flexDirection = "column",
                padding = 8,
                marginBottom = 4,
                backgroundColor = { 35, 30, 55, 200 },
                borderRadius = 6,
            }
            resultsPanel:AddChild(monsterCard)

            -- 类型 + 怪物名 + 详情按钮
            monsterCard:AddChild(UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                children = {
                    UI.Label {
                        text = "[" .. mType .. "]",
                        fontSize = 11,
                        fontColor = typeColor,
                    },
                    UI.Label {
                        text = monsterInfo.name,
                        fontSize = 14,
                        fontColor = { 220, 220, 240, 255 },
                        flexGrow = 1,
                    },
                    UI.Button {
                        text = "详情",
                        variant = "secondary",
                        width = 56,
                        height = 26,
                        fontSize = 12,
                        onClick = (function(name)
                            return function()
                                searchFrom_ = "search"
                                selectedMonster_ = name
                                MonsterGuideUI.RenderDetail()
                            end
                        end)(monsterInfo.name),
                    },
                },
            })

            -- 分布地图标题
            monsterCard:AddChild(UI.Label {
                text = "分布地图 (共" .. distTotal .. "张):",
                fontSize = 11,
                fontColor = { 140, 180, 140, 255 },
                marginTop = 4,
                marginBottom = 2,
            })

            -- 分布地图分页内容容器
            local distContainer = UI.Panel {
                id = "distContainer_" .. monsterInfo.name,
                width = "100%",
                flexDirection = "column",
            }
            monsterCard:AddChild(distContainer)

            -- 渲染分布地图分页的闭包函数
            local function RenderDistPage(page, maps, container, totalPg)
                container:ClearChildren()
                local s = (page - 1) * DIST_PER_PAGE + 1
                local e = math.min(s + DIST_PER_PAGE - 1, #maps)

                for i = s, e do
                    container:AddChild(UI.Label {
                        text = "  " .. i .. ". " .. maps[i],
                        fontSize = 11,
                        fontColor = { 180, 200, 180, 255 },
                        marginBottom = 1,
                    })
                end

                -- 分页控制（仅多于1页时显示）
                if totalPg > 1 then
                    local pageCtrl = {}
                    if page > 1 then
                        table.insert(pageCtrl, UI.Button {
                            text = "上页",
                            variant = "outline",
                            width = 48,
                            height = 22,
                            fontSize = 10,
                            onClick = function()
                                RenderDistPage(page - 1, maps, container, totalPg)
                            end,
                        })
                    end
                    table.insert(pageCtrl, UI.Label {
                        text = page .. "/" .. totalPg,
                        fontSize = 10,
                        fontColor = { 140, 140, 160, 255 },
                        textAlign = "center",
                        flexGrow = 1,
                    })
                    if page < totalPg then
                        table.insert(pageCtrl, UI.Button {
                            text = "下页",
                            variant = "outline",
                            width = 48,
                            height = 22,
                            fontSize = 10,
                            onClick = function()
                                RenderDistPage(page + 1, maps, container, totalPg)
                            end,
                        })
                    end
                    container:AddChild(UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 4,
                        marginTop = 4,
                        children = pageCtrl,
                    })
                end
            end

            -- 渲染第1页
            if distTotal == 0 then
                distContainer:AddChild(UI.Label {
                    text = "  无分布",
                    fontSize = 11,
                    fontColor = { 120, 120, 140, 255 },
                })
            else
                RenderDistPage(1, allDistMaps, distContainer, distPages)
            end
        end
    end
end

return MonsterGuideUI
