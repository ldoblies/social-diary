-- Copy to config.lua (not committed) and point it at this machine's game.
return {
    -- The account-wide SavedVariables file the addon writes at logout.
    savedVariables = "F:/BattleNet/World of Warcraft/_forever_/WTF/Account/ACCOUNT/SavedVariables/social_diary.lua",
    -- Where SocialDiary_Curated is written.
    addons = "F:/BattleNet/World of Warcraft/_forever_/Interface/AddOns",
    -- feed.json, stories.json and curated_state.json: private, so outside this repository.
    out = "C:/Users/Luchin/workspace/hordcore/source-material/ingame",
    interface = "16001",
    maxLevel = 60,
    -- Stories written per run at most, the newest first.
    maxPerRun = 30,
}
