-- 游戏全局配置
return {
    ["game"] = {
        title = "凡人修仙传",
        version = "1.0.0",
        start_map = "新手村",
        start_quest = "main_001",
    },
    ["player_default"] = {
        hp = 100,
        mp = 50,
        atk = 5,
        def = 3,
        level = 1,
        exp = 0,
        gold = 50,
        cultivation = "练气期一层",
    },
    ["level_up"] = {
        base_exp = 20,
        exp_factor = 1.5,
        hp_per_level = 20,
        mp_per_level = 10,
        atk_per_level = 3,
        def_per_level = 2,
    },
    ["cultivation"] = {
        ["1"] = "练气期一层",
        ["3"] = "练气期二层",
        ["5"] = "练气期三层",
        ["7"] = "筑基期一层",
        ["9"] = "筑基期二层",
        ["11"] = "筑基期三层",
        ["13"] = "金丹期一层",
        ["15"] = "金丹期二层",
    },
}
