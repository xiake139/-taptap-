-- 游戏全局配置
return {
    ["game"] = {
        title = "创世修仙",
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
    },
    ["level_up"] = {
        base_exp = 20,
        exp_factor = 1.5,
        hp_per_level = 20,
        mp_per_level = 10,
        atk_per_level = 3,
        def_per_level = 2,
        max_level = 100,
    },
}
