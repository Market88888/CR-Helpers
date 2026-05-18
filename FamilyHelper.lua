script_name("Family Helper")
script_description('Helper for Family management in Arizona RP')
script_author("Shinik_Pupckin")
script_version("3.0")

require('lib.moonloader')
require('encoding').default = 'CP1251'
local _u8 = require('encoding').UTF8
local ffi = require('ffi')
local sampev = require('samp.events')

local u8 = setmetatable({}, {
    __call = function(_, s)
        if s == nil then return '' end
        if type(s) ~= 'string' then s = tostring(s) end
        local ok, result = pcall(_u8, s)
        return ok and result or s
    end,
    __index = _u8,
})

local function safe_u8(v) return u8(tostring(v or '')) end
-- fh_num_fmt: формат числа с точками (1519220 -> 1.519.220)
local function fh_num_fmt(n)
    if n == nil then return '-' end
    local num = tonumber(n)
    if not num then return tostring(n) end
    local s = tostring(math.floor(num))
    return s:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
end

local function fh_num_short(n)
    if n == nil then return '-' end
    local num = tonumber(n)
    if not num then return '-' end
    if num >= 1000000000 then return string.format('%.1fB', num/1000000000)
    elseif num >= 1000000 then return string.format('%.1fM', num/1000000)
    elseif num >= 1000 then return string.format('%.1fK', num/1000)
    else return tostring(math.floor(num)) end
end


-------------------------------------------- SETTINGS ---------------------------------------------
-- ===== Авто РП-оружие =====
local fh_sex = 'Мужчина'  -- 'Мужчина' ИЛИ 'Женщина'
local fh_gun_names = {
    [0]='кулаки',[1]='кастеты',[2]='клюшку для гольфа',[3]='дубинку',
    [4]='острый нож',[5]='биту',[6]='лопату',[7]='кий',[8]='катану',[9]='бензопилу',
    [16]='осколочную гранату',[17]='дымовую гранату',[18]='коктейль Молотова',
    [22]='пистолет Colt45',[23]='электрошокер Taser',[24]='пистолет Desert Eagle',
    [25]='дробовик',[26]='обрез',[27]='улучшенный обрез',
    [28]='пист-пулёмёт Micro Uzi',[29]='пист-пулёмёт MP5',
    [30]='автомат AK-47',[31]='автомат M4',[32]='пист-пулёмёт Tec-9',
    [33]='винтовку Rifle',[34]='снайп винтовку Rifle',
    [35]='ркс прот ракету',[37]='огнемёт',[38]='миниган',
    [39]='динамит',[41]='перцовый баллончик',[42]='огнетушитель',
    [71]='пистолет Desert Eagle Steel',[72]='пистолет Desert Eagle Gold',
    [73]='пистолет Glock',[74]='пистолет Desert Eagle Flame',
    [75]='пистолет Colt Python',[76]='пистолет Colt Python Silver',
    [77]='автомат AK-47 Roses',[78]='автомат AK-47 Gold',
    [79]='пулемёт M249 Graffiti',[80]='золотую Сайгу',
    [81]='пист-пулёмёт PPSH',[82]='пулемёт M249',[83]='пист-пулёмёт Skorp',
    [84]='автомат AKS-74 камуф',[85]='автомат AK-47 камуф',
    [86]='дробовик Rebecca',[88]='ледяной меч',[89]='портальную пушку',[92]='снайп винт McMillian TAC-50',
}
local fh_take_from = {'из-за спины','из кобуры','из кармана','набросил'}
local fh_take_to   = {'за спину','в кобуру','в карман','на пояс'}
local fh_rp_take_slot = {
    [1]=2,[2]=1,[3]=2,[4]=2,[5]=1,[6]=1,[7]=1,[8]=1,[9]=1,
    [16]=3,[17]=3,[18]=3,[22]=2,[23]=2,[24]=2,[25]=1,[26]=1,[27]=1,
    [28]=1,[29]=1,[30]=1,[31]=1,[32]=1,[33]=1,[34]=1,[35]=1,[37]=1,[38]=1,
    [39]=3,[41]=3,[42]=1,[71]=2,[72]=2,[73]=2,[74]=2,[75]=2,[76]=2,
    [77]=1,[78]=1,[79]=1,[80]=1,[81]=1,[82]=1,[83]=1,[84]=1,[85]=1,[86]=1,
    [88]=1,[89]=2,[92]=1,
}
local fh_gun_now = 0
local fh_gun_old = 0

local settings = {}
local default_settings = {
    
      blacklist = {},
      quests_stats = {},
      auto_tags = {
          { rank = "1", tag = "\xcd\xee\xe2\xe8\xf7\xee\xea" },
          { rank = "2", tag = "\xd3\xf7\xe0\xf1\xf2\xed\xe8\xea" },
          { rank = "3", tag = "\xd1\xf2\xe0\xf0\xf8\xe8\xe9" },
          { rank = "4", tag = "\xc2\xe5\xf2\xe5\xf0\xe0\xed" },
          { rank = "5", tag = "\xce\xf4\xe8\xf6\xe5\xf0" },
          { rank = "6", tag = "\xd1\xf2\xe0\xf0\xf8\xe8\xe9 \xee\xf4\xe8\xf6\xe5\xf0" },
          { rank = "7", tag = "\xca\xe0\xef\xe8\xf2\xe0\xed" },
          { rank = "8", tag = "\xc7\xe0\xec\xe5\xf1\xf2\xe8\xf2\xe5\xeb\xfc" },
          { rank = "9", tag = "\xd1\xee-\xeb\xe8\xe4\xe5\xf0" },
          { rank = "10", tag = "\xcb\xe8\xe4\xe5\xf0" },
      },
      offline_kick_days = 7,
      quest_reward_amount = 1000000,
  general = {
        version = thisScript().version,
        rp_chat = true,
        auto_invite = false,
        auto_invite_radius = 5,
        auto_invite_delay = 3.0,
        auto_welcome = true,
        auto_congrats = true,
        custom_dpi = 1.0,
        autofind_dpi = false,
        float_btn_x = 40,
        float_btn_y = 300,
        float_btn_radius = 15,
        float_btn_size = 1.0,
        float_btn_enable = true,
        auto_vr_confirm = true,
        auto_ad_confirm = false,      -- авто-подтверждение /ad диалогов
        auto_storage_collect = false,   -- авто-сбор /storage
        auto_rp_guns = false,            -- Авто РП-оружие
        auto_ad_station_idx = 2,       -- 0=Los Santos, 1=Las Venturas, 2=San Fierro
        auto_ad_type = 0,              -- 0=Обычное, 1=VIP
                auto_mute_insults = false,
        auto_mute_insults_time = 60, -- minutes
        auto_mute_spam = false,
        auto_mute_spam_time = 30,
        auto_mute_flood = false,

        auto_mute_flood_time = 30,

        auto_keyword_invite = true,
        auto_quest_congrats = true,
        famspawn_delay = 30,
        invite_total = 0,
        invite_price_normal = 2000000,
        invite_price_bonus = 4000000,
        invite_bonus_threshold = 50,
        keyword_invite_list = {'\xe8\xed\xe2', '\xe8\xed\xe2\xe0\xe9\xf2', '\xe8\xed\xe2\xe0\xe9\xf2 \xef\xe6', '\xec\xee\xe6\xed\xee \xe2 \xf4\xe0\xec', '\xef\xf0\xe8\xec\xe8', '\xe8\xed\xe2 \xe2 \xf4\xe0\xec\xf3', '\xef\xf0\xe8\xec\xe8 \xe2 \xf1\xe5\xec\xfc\xfe', '\xf5\xee\xf7\xf3 \xe2 \xf4\xe0\xec', '\xe2\xee\xe7\xfc\xec\xe8 \xe2 \xf1\xe5\xec\xfc\xfe'},
    },
    reward = {
        use_fam = true,
        items = {
            { text = '\xc4\xee\xe1\xf0\xee \xef\xee\xe6\xe0\xeb\xee\xe2\xe0\xf2\xfc, {player_name}! \xd1\xef\xe0\xf1\xe8\xe1\xee \xe7\xe0 \xea\xe2\xe5\xf1\xf2!', waiting = 1.5 },
        }
    },
    interface = {
        accent_r = 1.0,
        accent_g = 0.65,
        accent_b = 0.0,
        window_alpha = 0.97,
        bg_brightness = 0.13,
    },
    family_info = {
        family_name = 'Grozzy',
        family_tag = '[Grozzy]',
        leader_name = '',
        my_name = '',
        my_rank = '',
        my_rank_number = 1,
    },
    reconnect = {
        enabled       = false,
        auto_login    = false,
        on_kicked     = true,
        on_banned     = false,
        on_rejected   = true,
        on_password   = false,
        delay         = 5.0,
        login         = '',
        password      = '',
    },
    tg = {
        enabled = false,
        token = '',
        channel_id = '',
        chat_id = '',
        bot_username = '',
        my_chat_id = '',
        last_update_offset = 0,
        pending = {},
        relay_ids = {},
        ev_invite = true,
        ev_join = true,
        ev_leave = true,
        ev_level = true,
        ev_quest = true,
        ev_mute = true,
        ev_coins = true,
        ev_bank = true,
        auto_role = false,
        auto_inv_report = false,
    },
    rp_invite = {
        text = '/me \xe4\xee\xf1\xf2\xe0\xb8\xf2 \xe8\xe7 \xea\xe0\xf0\xec\xe0\xed\xe0 \xf2\xe5\xeb\xe5\xf4\xee\xed \xe8 \xee\xf2\xea\xf0\xfb\xe2\xe0\xe5\xf2 \xe1\xe0\xe7\xf3 \xe4\xe0\xed\xed\xfb\xf5 \xf1\xe5\xec\xfc\xe8&/me \xef\xf0\xee\xe2\xe5\xf0\xff\xe5\xf2 \xe8\xed\xf4\xee\xf0\xec\xe0\xf6\xe8\xfe \xee \xf7\xe5\xeb\xee\xe2\xe5\xea\xe5 \xed\xe0\xef\xf0\xee\xf2\xe8\xe2&/do \xc8\xed\xf4\xee\xf0\xec\xe0\xf6\xe8\xff \xef\xf0\xee\xe2\xe5\xf0\xe5\xed\xe0.&/todo \xc4\xee\xe1\xf0\xee \xef\xee\xe6\xe0\xeb\xee\xe2\xe0\xf2\xfc \xe2 \xed\xe0\xf8\xf3 \xf1\xe5\xec\xfc\xfe!*\xf3\xeb\xfb\xe1\xe0\xff\xf1\xfc&/faminvite {arg_id}',
        waiting = 1.5,
    },
    welcome = {
        use_fam = true,
        items = {
            { text = '\xc4\xee\xe1\xf0\xee \xef\xee\xe6\xe0\xeb\xee\xe2\xe0\xf2\xfc \xe2 \xf1\xe5\xec\xfc\xfe {family_name}, {player_name}!', waiting = 1.5 },
            { text = '\xce\xe7\xed\xe0\xea\xee\xec\xfc\xf1\xff \xf1 \xef\xf0\xe0\xe2\xe8\xeb\xe0\xec\xe8 \xe8 \xf7\xf3\xe2\xf1\xf2\xe2\xf3\xe9 \xf1\xe5\xe1\xff \xea\xe0\xea \xe4\xee\xec\xe0.', waiting = 1.5 },
            { text = '\xcf\xee \xe2\xee\xef\xf0\xee\xf1\xe0\xec \xef\xe8\xf8\xe8 \xe2 /fam, \xef\xee\xec\xee\xe6\xe5\xec!', waiting = 1.5 },
        }
    },
    congrats = {
        use_fam = true,
        items = {
            { text = '\xcf\xee\xe7\xe4\xf0\xe0\xe2\xeb\xff\xfe \xf1 \xed\xee\xe2\xfb\xec \xf3\xf0\xee\xe2\xed\xe5\xec, {player_name}!', waiting = 2.0 },
            { text = '\xd2\xe0\xea \xe4\xe5\xf0\xe6\xe0\xf2\xfc!', waiting = 1.5 },
        }
    },
    interactions = {
        { name = '1. \xcf\xf0\xe8\xe2\xe5\xf2\xf1\xf2\xe2\xe8\xe5', lines = {
            '/me \xef\xee\xe4\xf5\xee\xe4\xe8\xf2 \xea {get_ru_nick} \xe8 \xef\xf0\xee\xf2\xff\xe3\xe8\xe2\xe0\xe5\xf2 \xf0\xf3\xea\xf3',
            '\xcf\xf0\xe8\xe2\xe5\xf2, {get_ru_nick}! \xc5\xf1\xf2\xfc \xec\xe8\xed\xf3\xf2\xea\xe0 \xef\xee\xe3\xee\xe2\xee\xf0\xe8\xf2\xfc?',
        }, waiting = 2.5 },
        { name = '2. \xcf\xf0\xe5\xe4\xeb\xee\xe6\xe5\xed\xe8\xe5', lines = {
            '\xdf \xef\xf0\xe5\xe4\xf1\xf2\xe0\xe2\xeb\xff\xfe \xf1\xe5\xec\xfc\xfe {family_name}, \xec\xfb \xf1\xe5\xe9\xf7\xe0\xf1 \xed\xe0\xe1\xe8\xf0\xe0\xe5\xec \xeb\xfe\xe4\xe5\xe9.',
            '\xd5\xee\xf2\xe5\xeb \xe1\xfb \xef\xf0\xe5\xe4\xeb\xee\xe6\xe8\xf2\xfc \xf2\xe5\xe1\xe5 \xea \xed\xe0\xec \xe2\xf1\xf2\xf3\xef\xe8\xf2\xfc.',
        }, waiting = 2.5 },
        { name = '3. \xce \xf1\xe5\xec\xfc\xe5', lines = {
            '\xd1\xe5\xec\xfc\xff {family_name} \x97 \xe0\xea\xf2\xe8\xe2\xed\xfb\xe9 \xea\xee\xeb\xeb\xe5\xea\xf2\xe8\xe2, \xe4\xe0\xe2\xed\xee \xed\xe0 \xf1\xe5\xf0\xe2\xe5\xf0\xe5.',
            '\xc5\xf1\xf2\xfc \xf1\xe2\xee\xff \xea\xe2\xe0\xf0\xf2\xe8\xf0\xe0, \xf2\xf0\xe0\xed\xf1\xef\xee\xf0\xf2, \xef\xf0\xee\xea\xe0\xf7\xe0\xed\xed\xfb\xe5 \xf3\xeb\xf3\xf7\xf8\xe5\xed\xe8\xff.',
        }, waiting = 2.5 },
        { name = '4. \xcf\xeb\xfe\xf1\xfb', lines = {
            '\xc8\xe7 \xef\xeb\xfe\xf1\xee\xe2: \xef\xee\xe2\xfb\xf8\xe5\xed\xed\xe0\xff \xe7\xe0\xf0\xef\xeb\xe0\xf2\xe0 \xed\xe0 \xf0\xe0\xe1\xee\xf2\xe0\xf5 \xee\xf2 \xf3\xeb\xf3\xf7\xf8\xe5\xed\xe8\xe9 \xf1\xe5\xec\xfc\xe8,',
            '\xe4\xee\xf1\xf2\xf3\xef \xea \xf1\xe5\xec\xe5\xe9\xed\xee\xe9 \xea\xe2\xe0\xf0\xf2\xe8\xf0\xe5, \xf1\xee\xe2\xec\xe5\xf1\xf2\xed\xfb\xe5 \xea\xe2\xe5\xf1\xf2\xfb \xe8 \xed\xe0\xe3\xf0\xe0\xe4\xfb.',
        }, waiting = 2.5 },
        { name = '5. \xd3\xf1\xeb\xee\xe2\xe8\xff', lines = {
            '\xd3\xf1\xeb\xee\xe2\xe8\xff \xef\xf0\xee\xf1\xf2\xfb\xe5 \x97 \xe0\xea\xf2\xe8\xe2\xed\xee\xf1\xf2\xfc \xe8 \xf1\xee\xe1\xeb\xfe\xe4\xe5\xed\xe8\xe5 \xef\xf0\xe0\xe2\xe8\xeb \xf1\xe5\xec\xfc\xe8.',
            '\xcb\xe8\xe4\xe5\xf0 \x97 {my_name}, \xe2\xf1\xe5\xe3\xe4\xe0 \xed\xe0 \xf1\xe2\xff\xe7\xe8, \xef\xee\xec\xee\xe6\xe5\xec \xee\xf1\xe2\xee\xe8\xf2\xfc\xf1\xff.',
        }, waiting = 2.5 },
        { name = '6. \xc8\xed\xe2\xe0\xe9\xf2 (\xd0\xcf)', lines = {
            '/me \xe4\xee\xf1\xf2\xe0\xb8\xf2 \xf2\xe5\xeb\xe5\xf4\xee\xed \xe8 \xee\xf2\xea\xf0\xfb\xe2\xe0\xe5\xf2 \xef\xf0\xe8\xeb\xee\xe6\xe5\xed\xe8\xe5 \xf1\xe5\xec\xfc\xe8',
            '/do \xcd\xe0 \xfd\xea\xf0\xe0\xed\xe5 \xef\xee\xff\xe2\xeb\xff\xe5\xf2\xf1\xff \xf4\xee\xf0\xec\xe0 \xef\xf0\xe8\xe3\xeb\xe0\xf8\xe5\xed\xe8\xff.',
            '\xce\xf2\xef\xf0\xe0\xe2\xeb\xff\xfe \xf2\xe5\xe1\xe5 \xef\xf0\xe8\xe3\xeb\xe0\xf8\xe5\xed\xe8\xe5 \x97 \xed\xe0\xef\xe8\xf8\xe8 /offer \xf7\xf2\xee\xe1\xfb \xe2\xf1\xf2\xf3\xef\xe8\xf2\xfc.',
            '/faminvite {arg_id}',
        }, waiting = 2.0 },
        { name = '7. \xcd\xe0\xef\xee\xec\xed\xe8\xf2\xfc /offer', lines = {
            '\xcf\xee\xeb\xf3\xf7\xe8\xeb \xef\xf0\xe8\xe3\xeb\xe0\xf8\xe5\xed\xe8\xe5? \xcd\xe0\xef\xe8\xf8\xe8 \xe2 \xf7\xe0\xf2 /offer \xf7\xf2\xee\xe1\xfb \xe2\xf1\xf2\xf3\xef\xe8\xf2\xfc!',
        }, waiting = 2.0 },
        { name = '8. \xce\xf2\xea\xe0\xe7', lines = {
            '/me \xef\xee\xed\xe8\xec\xe0\xfe\xf9\xe5 \xea\xe8\xe2\xe0\xe5\xf2',
            '\xc1\xe5\xe7 \xef\xf0\xee\xe1\xeb\xe5\xec, \xe5\xf1\xeb\xe8 \xef\xe5\xf0\xe5\xe4\xf3\xec\xe0\xe5\xf8\xfc \x97 \xef\xe8\xf8\xe8 \xe2 \xeb\xfe\xe1\xee\xe5 \xe2\xf0\xe5\xec\xff. \xd3\xe4\xe0\xf7\xe8!',
        }, waiting = 2.5 },
    },
    piar_templates = {
        { name = '\xcf\xe8\xe0\xf0 /s', enable = true, auto = false, auto_interval = 300, auto_interval_max = 0, waiting = 1.5, lines = {
            '/s \xc2\xed\xe8\xec\xe0\xed\xe8\xe5! \xcd\xe0\xe1\xee\xf0 \xe2 \xf1\xe5\xec\xfc\xfe {family_name}!',
            '/s \xcf\xee\xeb\xed\xe0\xff \xef\xf0\xee\xea\xe0\xf7\xea\xe0, \xea\xe2\xe0\xf0\xf2\xe8\xf0\xe0, \xf2\xee\xef \xe0\xe2\xf2\xee\xef\xe0\xf0\xea!',
            '/s \xcf\xee\xe4\xee\xe9\xe4\xe8\xf2\xe5 \xea\xee \xec\xed\xe5 \xe8\xeb\xe8 \xed\xe0\xef\xe8\xf8\xe8\xf2\xe5 \xe2 \xeb\xf1!',
        }, last_time = 0, },
        { name = '\xcf\xe8\xe0\xf0 /vr', enable = true, auto = false, auto_interval = 600, auto_interval_max = 0, waiting = 1.5, lines = {
            '/vr \xd1\xe5\xec\xfc\xff {family_name} \xef\xf0\xe8\xe3\xeb\xe0\xf8\xe0\xe5\xf2 \xe0\xea\xf2\xe8\xe2\xed\xfb\xf5 \xe8\xe3\xf0\xee\xea\xee\xe2!',
            '/vr \xd4\xf3\xeb \xef\xf0\xee\xea\xe0\xf7\xea\xe0, \xe4\xf0\xf3\xe6\xed\xfb\xe9 \xea\xee\xeb\xeb\xe5\xea\xf2\xe8\xe2! \xcf\xee\xe4\xf5\xee\xe4\xe8\xf2\xe5!',
        }, last_time = 0, },
        { name = '\xc0\xed\xee\xed\xf1 \xe2 /fam', enable = true, auto = false, auto_interval = 0, auto_interval_max = 0, waiting = 2.5, lines = {
            '/fam \x95 ================================ \x95',
            '/fam        \xcf\xf0\xe8\xe2\xe5\xf2\xf1\xf2\xe2\xf3\xfe \xf1\xe5\xec\xfc\xfe Grozzy!',
            '/fam \x95 ================================ \x95',
            '/fam  \xa7 \xc1\xee\xed\xf3\xf1\xfb \xe7\xe0 \xe0\xea\xf2\xe8\xe2\xed\xee\xf1\xf2\xfc:',
            '/fam  --------------------------------',
            '/fam  \x95 Telegram: t.me/FamaGrozzy',
            '/fam    \xc2\xf1\xf2\xf3\xef\xe8 \xe2 \xe3\xf0\xf3\xef\xef\xf3 = +1 \xf0\xe0\xed\xe3',
            '/fam  --------------------------------',
            '/fam  \x95 \xd1\xec\xe5\xed\xe8 \xf4\xe0\xec\xe8\xeb\xe8\xfe \xed\xe0 _Grozzy',
            '/fam    \xcf\xf0\xe8\xec\xe5\xf0: Vasya_Grozzy = +1 \xf0\xe0\xed\xe3',
            '/fam  --------------------------------',
            '/fam  \x95 \xca\xf3\xef\xe8 +1 \xf0\xe0\xed\xe3: \xe2\xe7\xed\xee\xf1 5kk \xed\xe0 \xf1\xea\xeb\xe0\xe4',
            '/fam \x95 ================================ \x95',
            '/fam    \xc2\xee\xef\xf0\xee\xf1\xfb >> {my_name}',
        }, last_time = 0, },
    },
    commands = {
        { cmd = 'fzd', description = '\xcf\xf0\xe8\xe2\xe5\xf2\xf1\xf2\xe2\xe8\xe5', text = '\xc7\xe4\xf0\xe0\xe2\xf1\xf2\xe2\xf3\xe9\xf2\xe5, {get_ru_nick}!&\xdf {my_name} \xe8\xe7 \xf1\xe5\xec\xfc\xe8 {family_name}.&\xd7\xe5\xec \xec\xee\xe3\xf3 \xef\xee\xec\xee\xf7\xfc?', arg = '{arg_id}', enable = true, waiting = '1.500', deleted = false },
        { cmd = 'finv', description = '\xc8\xed\xe2\xe0\xe9\xf2 (\xd0\xcf)', text = '/me \xe4\xee\xf1\xf2\xe0\xb8\xf2 \xe8\xe7 \xea\xe0\xf0\xec\xe0\xed\xe0 \xf2\xe5\xeb\xe5\xf4\xee\xed \xe8 \xee\xf2\xea\xf0\xfb\xe2\xe0\xe5\xf2 \xe1\xe0\xe7\xf3 \xe4\xe0\xed\xed\xfb\xf5 \xf1\xe5\xec\xfc\xe8&/me \xef\xf0\xee\xe2\xe5\xf0\xff\xe5\xf2 \xe8\xed\xf4\xee\xf0\xec\xe0\xf6\xe8\xfe \xee \xf7\xe5\xeb\xee\xe2\xe5\xea\xe5 \xed\xe0\xef\xf0\xee\xf2\xe8\xe2&/do \xc8\xed\xf4\xee\xf0\xec\xe0\xf6\xe8\xff \xef\xf0\xee\xe2\xe5\xf0\xe5\xed\xe0.&/todo \xc4\xee\xe1\xf0\xee \xef\xee\xe6\xe0\xeb\xee\xe2\xe0\xf2\xfc \xe2 \xed\xe0\xf8\xf3 \xf1\xe5\xec\xfc\xfe!*\xf3\xeb\xfb\xe1\xe0\xff\xf1\xfc&/faminvite {arg_id}', arg = '{arg_id}', enable = true, waiting = '1.500', deleted = false },
        { cmd = 'fkik', description = '\xca\xe8\xea\xed\xf3\xf2\xfc (\xd0\xcf)', text = '/me \xe4\xee\xf1\xf2\xe0\xb8\xf2 \xf2\xe5\xeb\xe5\xf4\xee\xed \xe8 \xee\xf2\xea\xf0\xfb\xe2\xe0\xe5\xf2 \xe1\xe0\xe7\xf3 \xe4\xe0\xed\xed\xfb\xf5 \xf1\xe5\xec\xfc\xe8&/me \xf3\xe4\xe0\xeb\xff\xe5\xf2 \xe8\xed\xf4\xee\xf0\xec\xe0\xf6\xe8\xfe \xee \xf7\xeb\xe5\xed\xe5 \xf1\xe5\xec\xfc\xe8&/famuninvite {arg_id}', arg = '{arg_id}', enable = true, waiting = '1.500', deleted = false },
        { cmd = 'fpr', description = '\xd0\xf3\xf7\xed\xee\xe9 \xef\xe8\xe0\xf0', text = '/s \xc2\xed\xe8\xec\xe0\xed\xe8\xe5! \xcd\xe0\xe1\xee\xf0 \xe2 \xf1\xe5\xec\xfc\xfe {family_name}!&/s \xc4\xeb\xff \xe2\xf1\xf2\xf3\xef\xeb\xe5\xed\xe8\xff \xef\xee\xe4\xee\xe9\xe4\xe8\xf2\xe5 \xea\xee \xec\xed\xe5!&/s \xd4\xf3\xeb \xef\xf0\xee\xea\xe0\xf7\xea\xe0, \xe4\xf0\xf3\xe6\xed\xfb\xe9 \xea\xee\xeb\xeb\xe5\xea\xf2\xe8\xe2!', arg = '', enable = true, waiting = '1.500', deleted = false },
        { cmd = 'frul', description = '\xcf\xf0\xe0\xe2\xe8\xeb\xe0', text = '/fam === \xcf\xd0\xc0\xc2\xc8\xcb\xc0 \xd1\xc5\xcc\xdc\xc8 ===&/fam 1. \xd3\xe2\xe0\xe6\xe0\xe9\xf2\xe5 \xe4\xf0\xf3\xe3 \xe4\xf0\xf3\xe3\xe0&/fam 2. \xcd\xe5 \xed\xe0\xf0\xf3\xf8\xe0\xe9\xf2\xe5 \xef\xf0\xe0\xe2\xe8\xeb\xe0 \xf1\xe5\xf0\xe2\xe5\xf0\xe0&/fam 3. \xc1\xf3\xe4\xfc\xf2\xe5 \xe0\xea\xf2\xe8\xe2\xed\xfb&/fam 4. \xcf\xee\xec\xee\xe3\xe0\xe9\xf2\xe5 \xed\xee\xe2\xe8\xf7\xea\xe0\xec&/fam =====================', arg = '', enable = true, waiting = '1.300', deleted = false },
        { cmd = 'fsob', description = '\xd1\xee\xe1\xe5\xf1\xe5\xe4\xee\xe2\xe0\xed\xe8\xe5', text = '\xc7\xe4\xf0\xe0\xe2\xf1\xf2\xe2\xf3\xe9\xf2\xe5, {get_ru_nick}!&\xdf {my_name} - {my_rank} \xf1\xe5\xec\xfc\xe8 {family_name}.&\xc2\xfb \xf5\xee\xf2\xe8\xf2\xe5 \xe2\xf1\xf2\xf3\xef\xe8\xf2\xfc \xe2 \xed\xe0\xf8\xf3 \xf1\xe5\xec\xfc\xfe?&\xd0\xe0\xf1\xf1\xea\xe0\xe6\xe8\xf2\xe5 \xed\xe5\xec\xed\xee\xe3\xee \xee \xf1\xe5\xe1\xe5.', arg = '{arg_id}', enable = true, waiting = '1.500', deleted = false },
        { cmd = 'fwel', description = '\xc2\xe5\xeb\xea\xee\xec \xe2 /fam', text = '/fam \xc4\xee\xe1\xf0\xee \xef\xee\xe6\xe0\xeb\xee\xe2\xe0\xf2\xfc, {get_ru_nick}!&/fam \xce\xe7\xed\xe0\xea\xee\xec\xfc\xf1\xff \xf1 \xef\xf0\xe0\xe2\xe8\xeb\xe0\xec\xe8, \xf7\xf3\xe2\xf1\xf2\xe2\xf3\xe9 \xf1\xe5\xe1\xff \xea\xe0\xea \xe4\xee\xec\xe0!&/fam \xcf\xee \xe2\xee\xef\xf0\xee\xf1\xe0\xec - \xea \xf1\xf2\xe0\xf0\xf8\xe8\xec.', arg = '{arg_id}', enable = true, waiting = '1.500', deleted = false },
        { cmd = 'fcong', description = '\xcf\xee\xe7\xe4\xf0\xe0\xe2\xe8\xf2\xfc', text = '/fam \xcf\xee\xe7\xe4\xf0\xe0\xe2\xeb\xff\xfe {get_ru_nick} \xf1 \xe4\xee\xf1\xf2\xe8\xe6\xe5\xed\xe8\xe5\xec!&/fam \xd2\xe0\xea \xe4\xe5\xf0\xe6\xe0\xf2\xfc!', arg = '{arg_id}', enable = true, waiting = '1.500', deleted = false },
        { cmd = 'fobj', description = '\xce\xe1\xf9\xe8\xe9 \xf1\xe1\xee\xf0', text = '/fam \xc2\xcd\xc8\xcc\xc0\xcd\xc8\xc5! \xce\xc1\xd9\xc8\xc9 \xd1\xc1\xce\xd0!&/fam \xc2\xf1\xe5 \xf3\xf7\xe0\xf1\xf2\xed\xe8\xea\xe8, \xef\xee\xe4\xee\xe9\xe4\xe8\xf2\xe5 \xea\xee \xec\xed\xe5!', arg = '', enable = true, waiting = '1.300', deleted = false },
        { cmd = 'fon', description = '\xce\xed\xeb\xe0\xe9\xed', text = '/fam \xca\xf2\xee \xee\xed\xeb\xe0\xe9\xed? \xce\xf2\xef\xe8\xf8\xe8\xf2\xe5\xf1\xfc +', arg = '', enable = true, waiting = '1.500', deleted = false },
        { cmd = 'frank', description = '\xcf\xee\xe2\xfb\xf1\xe8\xf2\xfc (\xd0\xcf)', text = '/me \xee\xf2\xea\xf0\xfb\xe2\xe0\xe5\xf2 \xe1\xe0\xe7\xf3 \xe4\xe0\xed\xed\xfb\xf5 \xf1\xe5\xec\xfc\xe8&/me \xe2\xed\xee\xf1\xe8\xf2 \xe8\xe7\xec\xe5\xed\xe5\xed\xe8\xff \xe2 \xe4\xe0\xed\xed\xfb\xe5&/do \xc8\xe7\xec\xe5\xed\xe5\xed\xe8\xff \xf1\xee\xf5\xf0\xe0\xed\xe5\xed\xfb.&/famrankedit {arg_id}', arg = '{arg_id}', enable = true, waiting = '1.500', deleted = false },
        { cmd = 'fwarn', description = '\xc2\xfb\xe3\xee\xe2\xee\xf0', text = '/fam \xd3\xf7\xe0\xf1\xf2\xed\xe8\xea\xf3 {get_ru_nick} \xe2\xfb\xed\xee\xf1\xe8\xf2\xf1\xff \xef\xf0\xe5\xe4\xf3\xef\xf0\xe5\xe6\xe4\xe5\xed\xe8\xe5.&/fam \xcf\xf0\xe8 \xef\xee\xe2\xf2\xee\xf0\xed\xee\xec \xed\xe0\xf0\xf3\xf8\xe5\xed\xe8\xe8 - \xe8\xf1\xea\xeb\xfe\xf7\xe5\xed\xe8\xe5.', arg = '{arg_id}', enable = true, waiting = '1.500', deleted = false },
        { cmd = 'foffer', description = '\xcd\xe0\xef\xee\xec\xed\xe8\xf2\xfc /offer', text = '\xcd\xe0\xef\xe8\xf8\xe8 /offer \xe2 \xf7\xe0\xf2 \xf7\xf2\xee\xe1\xfb \xef\xf0\xe8\xed\xff\xf2\xfc \xef\xf0\xe8\xe3\xeb\xe0\xf8\xe5\xed\xe8\xe5 \xe2 \xf1\xe5\xec\xfc\xfe!', arg = '{arg_id}', enable = true, waiting = '1.000', deleted = false },
    },
    note = {
        { note_name = '\xcf\xf0\xe0\xe2\xe8\xeb\xe0 \xf1\xe5\xec\xfc\xe8', note_text = '1. \xd3\xe2\xe0\xe6\xe0\xe9 \xe4\xf0\xf3\xe3 \xe4\xf0\xf3\xe3\xe0&2. \xcd\xe5 \xed\xe0\xf0\xf3\xf8\xe0\xe9 \xef\xf0\xe0\xe2\xe8\xeb\xe0 \xf1\xe5\xf0\xe2\xe5\xf0\xe0&3. \xc1\xf3\xe4\xfc \xe0\xea\xf2\xe8\xe2\xe5\xed&4. \xcf\xee\xec\xee\xe3\xe0\xe9 \xed\xee\xe2\xe8\xf7\xea\xe0\xec&5. \xd1\xeb\xf3\xf8\xe0\xe9 \xf1\xf2\xe0\xf0\xf8\xe8\xf5 \xef\xee \xf0\xe0\xed\xe3\xf3&6. \xd3\xf7\xe0\xf1\xf2\xe2\xf3\xe9 \xe2 \xec\xe5\xf0\xee\xef\xf0\xe8\xff\xf2\xe8\xff\xf5', deleted = false },
        { note_name = '\xd0\xe0\xed\xe3\xe8', note_text = '1. \xcd\xee\xe2\xe8\xf7\xee\xea&2. \xd3\xf7\xe0\xf1\xf2\xed\xe8\xea&3. \xd1\xf2\xe0\xf0\xf8\xe8\xe9&4. \xc2\xe5\xf2\xe5\xf0\xe0\xed&5. \xce\xf4\xe8\xf6\xe5\xf0&6. \xd1\xf2\xe0\xf0\xf8\xe8\xe9 \xee\xf4\xe8\xf6\xe5\xf0&7. \xca\xe0\xef\xe8\xf2\xe0\xed&8. \xc7\xe0\xec\xe5\xf1\xf2\xe8\xf2\xe5\xeb\xfc&9. \xd1\xee-\xeb\xe8\xe4\xe5\xf0&10. \xcb\xe8\xe4\xe5\xf0', deleted = false },
    },
}

local configDirectory = getWorkingDirectory():gsub('\\','/') .. "/Family Helper"
local path     = configDirectory .. "/Settings.json"
local log_path = configDirectory .. "/FamilyLog.json"

-- \xcb\xee\xe3 \xf1\xee\xe1\xfb\xf2\xe8\xe9 \xf1\xe5\xec\xfc\xe8 (\xe2 \xef\xe0\xec\xff\xf2\xe8, \xec\xe0\xea\xf1 200 \xe7\xe0\xef\xe8\xf1\xe5\xe9)
local famlog = {
    news    = {},   -- \xf1\xe8\xf1\xf2\xe5\xec\xed\xfb\xe5 \xf1\xee\xe1\xfb\xf2\xe8\xff [\xd1\xe5\xec\xfc\xff (\xcd\xee\xe2\xee\xf1\xf2\xe8)]
    chat    = {},   -- \xee\xe1\xfb\xf7\xed\xfb\xe9 \xf7\xe0\xf2 \xf1\xe5\xec\xfc\xe8 [\xd1\xe5\xec\xfc\xff]
    bank    = {},   -- \xee\xef\xe5\xf0\xe0\xf6\xe8\xe8 \xf1\xee \xf1\xea\xeb\xe0\xe4\xee\xec ($)
    coins   = {},   -- \xec\xee\xed\xe5\xf2\xfb / \xf2\xe0\xeb\xee\xed\xfb
    mute    = {},   -- \xec\xf3\xf2\xfb
    invite  = {},   -- \xe8\xed\xe2\xe0\xe9\xf2\xfb / \xe2\xf1\xf2\xf3\xef\xeb\xe5\xed\xe8\xff / \xe2\xfb\xf5\xee\xe4\xfb
    level   = {},   -- \xf3\xf0\xee\xe2\xed\xe8
    quest   = {},   -- \xea\xe2\xe5\xf1\xf2\xfb
    rank    = {},   -- \xe8\xe7\xec\xe5\xed\xe5\xed\xe8\xff \xf0\xe0\xed\xe3\xe0
}
local function save_log()
    local file = io.open(log_path, 'w')
    if file then
        local ok, encoded = pcall(encodeJson, famlog)
        file:write(ok and encoded or '{}'); file:close()
    end
end

local function load_log()
    if not doesFileExist(log_path) then return end
    local file = io.open(log_path, 'r')
    if file then
        local contents = file:read('*a'); file:close()
        if contents and contents ~= '' then
            local ok, data = pcall(decodeJson, contents)
            if ok and type(data) == 'table' then
                for k, v in pairs(data) do
                    if famlog[k] and type(v) == 'table' then
                        famlog[k] = v
                    end
                end
            end
        end
    end
end

local function merge_defaults(tbl, defaults)
    for k, v in pairs(defaults) do
        if tbl[k] == nil then tbl[k] = v
        elseif type(v) == 'table' and type(tbl[k]) == 'table' and not v[1] then merge_defaults(tbl[k], v) end
    end
end

local function validate_settings()
    
      settings.blacklist = settings.blacklist or {}
      settings.quests_stats = settings.quests_stats or {}
      settings.auto_tags = settings.auto_tags or {}
      settings.offline_kick_days = settings.offline_kick_days or 7
      settings.quest_reward_amount = settings.quest_reward_amount or 1000000
    settings.coins_stats = settings.coins_stats or {}
    settings.coin_reward_amount = settings.coin_reward_amount or 10000
    settings.talons_stats = settings.talons_stats or {}
    settings.talon_reward_amount = settings.talon_reward_amount or 30000
  settings.general = settings.general or {}
    settings.interface = settings.interface or {}
    settings.family_info = settings.family_info or {}
    settings.welcome = settings.welcome or {}
    settings.congrats = settings.congrats or {}
    settings.rp_invite = settings.rp_invite or {}
    for _, t in ipairs(settings.piar_templates or {}) do
        t.name=t.name or''; t.lines=t.lines or{}; t.waiting=t.waiting or 1.5; t.auto_interval=t.auto_interval or 300; t.last_time=t.last_time or 0
        if t.enable==nil then t.enable=true end; if t.auto==nil then t.auto=false end
    end
    for _, c in ipairs(settings.commands or {}) do
        c.cmd=c.cmd or''; c.description=c.description or''; c.text=c.text or''; c.arg=c.arg or''; c.waiting=c.waiting or'1.500'
        if c.enable==nil then c.enable=true end; if c.deleted==nil then c.deleted=false end
    end
    for _, n in ipairs(settings.note or {}) do
        n.note_name=n.note_name or''; n.note_text=n.note_text or''; if n.deleted==nil then n.deleted=false end
    end
    for _, i in ipairs(settings.interactions or {}) do
        i.name=i.name or''; i.lines=i.lines or{}; i.waiting=i.waiting or 1.5
    end
    -- \xcc\xe8\xe3\xf0\xe0\xf6\xe8\xff: welcome.items -> welcome.variants
    if settings.welcome.items and not settings.welcome.variants then
        settings.welcome.variants = {
            { items = settings.welcome.items },
            { items = {
                { text = '{player_name}, \xf0\xe0\xe4\xfb \xe2\xe8\xe4\xe5\xf2\xfc \xf2\xe5\xe1\xff \xf1\xf0\xe5\xe4\xe8 \xed\xe0\xf1!', waiting = 1.5 },
                { text = '\xd1\xe5\xec\xfc\xff {family_name} \x97 \xfd\xf2\xee \xed\xe5 \xef\xf0\xee\xf1\xf2\xee \xf2\xe5\xe3, \xfd\xf2\xee \xea\xee\xec\xe0\xed\xe4\xe0. \xc4\xee\xe1\xf0\xee \xef\xee\xe6\xe0\xeb\xee\xe2\xe0\xf2\xfc!', waiting = 2.0 },
                { text = '\xc5\xf1\xeb\xe8 \xf7\xf2\xee-\xf2\xee \xed\xe5\xef\xee\xed\xff\xf2\xed\xee \x97 \xee\xe1\xf0\xe0\xf9\xe0\xe9\xf1\xff, \xf0\xe0\xe7\xe1\xe5\xf0\xb8\xec\xf1\xff \xe2\xec\xe5\xf1\xf2\xe5.', waiting = 1.5 },
            }},
            { items = {
                { text = '\xcd\xee\xe2\xfb\xe9 \xf3\xf7\xe0\xf1\xf2\xed\xe8\xea \xe2 \xf0\xff\xe4\xe0\xf5 {family_name} \x97 {player_name}!', waiting = 1.5 },
                { text = '\xc1\xf3\xe4\xfc \xe0\xea\xf2\xe8\xe2\xe5\xed, \xef\xee\xec\xee\xe3\xe0\xe9 \xf1\xe2\xee\xe8\xec, \xe8 \xe2\xf1\xb8 \xe1\xf3\xe4\xe5\xf2 \xee\xf2\xeb\xe8\xf7\xed\xee.', waiting = 2.0 },
                { text = '\xc4\xee\xe1\xf0\xee \xef\xee\xe6\xe0\xeb\xee\xe2\xe0\xf2\xfc \xe4\xee\xec\xee\xe9!', waiting = 1.5 },
            }},
        }
        settings.welcome.items = nil
    end
    if not settings.welcome.variants then
        settings.welcome.variants = {
            { items = {
                { text = '\xc4\xee\xe1\xf0\xee \xef\xee\xe6\xe0\xeb\xee\xe2\xe0\xf2\xfc \xe2 \xf1\xe5\xec\xfc\xfe {family_name}, {player_name}!', waiting = 1.5 },
                { text = '\xce\xe7\xed\xe0\xea\xee\xec\xfc\xf1\xff \xf1 \xef\xf0\xe0\xe2\xe8\xeb\xe0\xec\xe8 \xe8 \xf7\xf3\xe2\xf1\xf2\xe2\xf3\xe9 \xf1\xe5\xe1\xff \xea\xe0\xea \xe4\xee\xec\xe0.', waiting = 1.5 },
                { text = '\xcf\xee \xe2\xee\xef\xf0\xee\xf1\xe0\xec \xef\xe8\xf8\xe8 \xe2 /fam, \xe2\xf1\xe5\xe3\xe4\xe0 \xef\xee\xec\xee\xe6\xe5\xec!', waiting = 1.5 },
            }},
            { items = {
                { text = '{player_name}, \xf0\xe0\xe4\xfb \xe2\xe8\xe4\xe5\xf2\xfc \xf2\xe5\xe1\xff \xf1\xf0\xe5\xe4\xe8 \xed\xe0\xf1!', waiting = 1.5 },
                { text = '\xd1\xe5\xec\xfc\xff {family_name} \x97 \xfd\xf2\xee \xed\xe5 \xef\xf0\xee\xf1\xf2\xee \xf2\xe5\xe3, \xfd\xf2\xee \xea\xee\xec\xe0\xed\xe4\xe0. \xc4\xee\xe1\xf0\xee \xef\xee\xe6\xe0\xeb\xee\xe2\xe0\xf2\xfc!', waiting = 2.0 },
                { text = '\xc5\xf1\xeb\xe8 \xf7\xf2\xee-\xf2\xee \xed\xe5\xef\xee\xed\xff\xf2\xed\xee \x97 \xee\xe1\xf0\xe0\xf9\xe0\xe9\xf1\xff, \xf0\xe0\xe7\xe1\xe5\xf0\xb8\xec\xf1\xff \xe2\xec\xe5\xf1\xf2\xe5.', waiting = 1.5 },
            }},
            { items = {
                { text = '\xcd\xee\xe2\xfb\xe9 \xf3\xf7\xe0\xf1\xf2\xed\xe8\xea \xe2 \xf0\xff\xe4\xe0\xf5 {family_name} \x97 {player_name}!', waiting = 1.5 },
                { text = '\xc1\xf3\xe4\xfc \xe0\xea\xf2\xe8\xe2\xe5\xed, \xef\xee\xec\xee\xe3\xe0\xe9 \xf1\xe2\xee\xe8\xec, \xe8 \xe2\xf1\xb8 \xe1\xf3\xe4\xe5\xf2 \xee\xf2\xeb\xe8\xf7\xed\xee.', waiting = 2.0 },
                { text = '\xc4\xee\xe1\xf0\xee \xef\xee\xe6\xe0\xeb\xee\xe2\xe0\xf2\xfc \xe4\xee\xec\xee\xe9!', waiting = 1.5 },
            }},
        }
    end
    if settings.welcome.variant_idx == nil then settings.welcome.variant_idx = 0 end
    while #settings.welcome.variants < 3 do
        table.insert(settings.welcome.variants, { items = {{text='\xc4\xee\xe1\xf0\xee \xef\xee\xe6\xe0\xeb\xee\xe2\xe0\xf2\xfc, {player_name}!', waiting=1.5}} })
    end
    for _, v in ipairs(settings.welcome.variants) do v.items = v.items or {} end

    -- \xcc\xe8\xe3\xf0\xe0\xf6\xe8\xff: congrats.items -> congrats.variants
    if settings.congrats.items and not settings.congrats.variants then
        settings.congrats.variants = {
            { items = settings.congrats.items },
            { items = {
                { text = '{player_name}, \xef\xee\xe7\xe4\xf0\xe0\xe2\xeb\xff\xfe \xf1 \xed\xee\xe2\xfb\xec \xf3\xf0\xee\xe2\xed\xe5\xec!', waiting = 1.5 },
                { text = '\xcf\xf0\xee\xea\xe0\xf7\xea\xe0 \xe8\xe4\xb8\xf2 \xef\xee\xeb\xed\xfb\xec \xf5\xee\xe4\xee\xec, \xef\xf0\xee\xe4\xee\xeb\xe6\xe0\xe9 \xe2 \xf2\xee\xec \xe6\xe5 \xe4\xf3\xf5\xe5!', waiting = 2.0 },
            }},
            { items = {
                { text = '\xce, {player_name} \xef\xee\xe4\xed\xff\xeb \xf3\xf0\xee\xe2\xe5\xed\xfc!', waiting = 1.5 },
                { text = '\xd0\xe0\xf1\xf2\xb8\xf8\xfc \xed\xe5 \xef\xee \xe4\xed\xff\xec, \xe0 \xef\xee \xf7\xe0\xf1\xe0\xec. \xd2\xe0\xea \xe4\xe5\xf0\xe6\xe0\xf2\xfc!', waiting = 2.0 },
            }},
        }
        settings.congrats.items = nil
    end
    if not settings.congrats.variants then
        settings.congrats.variants = {
            { items = {
                { text = '\xcf\xee\xe7\xe4\xf0\xe0\xe2\xeb\xff\xfe \xf1 \xed\xee\xe2\xfb\xec \xf3\xf0\xee\xe2\xed\xe5\xec, {player_name}!', waiting = 1.5 },
                { text = '\xd5\xee\xf0\xee\xf8\xe8\xe9 \xf0\xe5\xe7\xf3\xeb\xfc\xf2\xe0\xf2, \xf2\xe0\xea \xe4\xe5\xf0\xe6\xe0\xf2\xfc!', waiting = 2.0 },
            }},
            { items = {
                { text = '{player_name}, \xef\xee\xe7\xe4\xf0\xe0\xe2\xeb\xff\xfe \xf1 \xed\xee\xe2\xfb\xec \xf3\xf0\xee\xe2\xed\xe5\xec!', waiting = 1.5 },
                { text = '\xcf\xf0\xee\xea\xe0\xf7\xea\xe0 \xe8\xe4\xb8\xf2 \xef\xee\xeb\xed\xfb\xec \xf5\xee\xe4\xee\xec, \xef\xf0\xee\xe4\xee\xeb\xe6\xe0\xe9 \xe2 \xf2\xee\xec \xe6\xe5 \xe4\xf3\xf5\xe5!', waiting = 2.0 },
            }},
            { items = {
                { text = '\xce, {player_name} \xef\xee\xe4\xed\xff\xeb \xf3\xf0\xee\xe2\xe5\xed\xfc!', waiting = 1.5 },
                { text = '\xd0\xe0\xf1\xf2\xb8\xf8\xfc \xed\xe5 \xef\xee \xe4\xed\xff\xec, \xe0 \xef\xee \xf7\xe0\xf1\xe0\xec. \xd2\xe0\xea \xe4\xe5\xf0\xe6\xe0\xf2\xfc!', waiting = 2.0 },
            }},
        }
    end
    if settings.congrats.variant_idx == nil then settings.congrats.variant_idx = 0 end
    while #settings.congrats.variants < 3 do
        table.insert(settings.congrats.variants, { items = {{text='\xcf\xee\xe7\xe4\xf0\xe0\xe2\xeb\xff\xfe \xf1 \xf3\xf0\xee\xe2\xed\xe5\xec, {player_name}!', waiting=2.0}} })
    end
    for _, v in ipairs(settings.congrats.variants) do v.items = v.items or {} end
    settings.rp_invite.text=settings.rp_invite.text or''; settings.rp_invite.waiting=settings.rp_invite.waiting or 1.5
    settings.family_info.family_name=settings.family_info.family_name or''; settings.family_info.my_name=settings.family_info.my_name or''
    settings.family_info.my_rank=settings.family_info.my_rank or''; settings.family_info.family_tag=settings.family_info.family_tag or''
    settings.family_info.leader_name=settings.family_info.leader_name or''; settings.family_info.my_rank_number=settings.family_info.my_rank_number or 1
    settings.general.float_btn_x=settings.general.float_btn_x or 40; settings.general.float_btn_y=settings.general.float_btn_y or 300
    settings.general.float_btn_radius=settings.general.float_btn_radius or 15; settings.general.float_btn_size=settings.general.float_btn_size or 1.0
    settings.general.auto_mute_spam_time = settings.general.auto_mute_spam_time or 30
    settings.general.auto_mute_flood_time = settings.general.auto_mute_flood_time or 30
    settings.general.invite_unpaid = settings.general.invite_unpaid or 0
    settings.general.invite_price_normal = settings.general.invite_price_normal or 2000000
    settings.general.invite_price_bonus = settings.general.invite_price_bonus or 4000000
    settings.general.invite_bonus_threshold = settings.general.invite_bonus_threshold or 50
    if not settings.coins_thanks then
        settings.coins_thanks = {
            items = {{ text = '/b \xd1\xef\xe0\xf1\xe8\xe1\xee, {player_name}! \xcc\xee\xed\xe5\xf2\xfb \xef\xf0\xe8\xed\xff\xf2\xfb!', waiting = 1.0 }},
            use_fam = false, enabled = true
        }
    end
    if not settings.tg then
        settings.tg = {
            token    = '',
            chat_id  = '',
            enabled  = false,
            role     = 'main',  -- 'main' = \xe2\xf1\xe5 \xf1\xee\xe1\xfb\xf2\xe8\xff, 'deputy' = \xf2\xee\xeb\xfc\xea\xee \xf1\xe2\xee\xe8
            auto_role = true,   -- \xe0\xe2\xf2\xee-\xe3\xeb\xe0\xe2\xe5\xed\xf1\xf2\xe2\xee \xef\xee \xf0\xe0\xed\xe3\xf3 \xf7\xe5\xf0\xe5\xe7 \xec\xe0\xf0\xea\xe5\xf0 \xe2 /f
            ev_invite  = true,
            ev_join    = true,
            ev_leave   = true,
            ev_level   = true,
            ev_quest   = true,
            ev_mute    = true,
            ev_coins   = true,
            ev_bank    = true,
            last_update_id = 0,
            last_group_msg_id = 0,  -- \xef\xee\xf1\xeb\xe5\xe4\xed\xe8\xe9 message_id \xe2 \xe3\xf0\xf3\xef\xef\xe5 (\xe4\xeb\xff copyMessage)
            bot_username = 'FamilyGrozzybot',
            my_chat_id = '',
            relay_chat_id = '',
            relay_ids = {},
            registered = false,
        }
    end
    if settings.tg and settings.tg.role == nil then
        settings.tg.role = 'main'; save_settings()
    end
    if settings.tg and settings.tg.auto_role == nil then
        settings.tg.auto_role = true; save_settings()
    end
    if not settings.log_enabled then
        settings.log_enabled = {
            news   = true,
            chat   = false,  -- \xf7\xe0\xf2 \xf1\xe5\xec\xfc\xe8 (\xef\xee \xf3\xec\xee\xeb\xf7. \xe2\xfb\xea\xeb \x97 \xec\xed\xee\xe3\xee \xf1\xee\xee\xe1\xf9\xe5\xed\xe8\xe9)
            bank   = true,
            coins  = true,
            mute   = true,
            invite = true,
            level  = true,
            quest  = true,
            rank   = true,
        }
    end
    if settings.log_enabled and settings.log_enabled.news == nil then
        settings.log_enabled.news = true; save_settings()
    end
    if settings.log_enabled and settings.log_enabled.chat == nil then
        settings.log_enabled.chat = false; save_settings()
    end
    if not settings.reconnect then
        settings.reconnect = { enabled=false, auto_login=false, on_kicked=true, on_banned=false,
            on_rejected=true, on_password=false, delay=5.0, login='', password='' }
    end
    if settings.reconnect.delay == nil then settings.reconnect.delay = 5.0 end
    if settings.reconnect.login == nil then settings.reconnect.login = '' end
    if settings.reconnect.password == nil then settings.reconnect.password = '' end
    if not settings.invite_stats then
        settings.invite_stats = {}  -- {nick = {total=0, today=0, week=0, month=0, day_key='', week_key='', month_key=''}}
    end
    if not settings.quest_congrats then settings.quest_congrats = { use_fam = true, enabled = true } end
    -- \xcc\xe8\xe3\xf0\xe0\xf6\xe8\xff: quest_congrats.items -> quest_congrats.variants
    if settings.quest_congrats.items and not settings.quest_congrats.variants then
        settings.quest_congrats.variants = {
            { items = settings.quest_congrats.items },
            { items = {
                { text = '{player_name}, \xea\xe2\xe5\xf1\xf2 \xf1\xe4\xe0\xed \x97 \xec\xee\xeb\xee\xe4\xe5\xf6, \xed\xe5 \xeb\xe5\xed\xe8\xf8\xfc\xf1\xff!', waiting = 1.5 },
                { text = '\xcf\xf0\xee\xe4\xee\xeb\xe6\xe0\xe9 \xe2 \xf2\xee\xec \xe6\xe5 \xe4\xf3\xf5\xe5, \xf1\xe5\xec\xfc\xff \xfd\xf2\xee \xf6\xe5\xed\xe8\xf2.', waiting = 2.0 },
            }},
            { items = {
                { text = '\xd5\xee\xf0\xee\xf8\xe0\xff \xf0\xe0\xe1\xee\xf2\xe0, {player_name}!', waiting = 1.5 },
                { text = '\xca\xe2\xe5\xf1\xf2 \xe2\xfb\xef\xee\xeb\xed\xe5\xed, \xf1\xe5\xec\xfc\xff \xf0\xe0\xf1\xf2\xb8\xf2. \xd2\xe0\xea \xe4\xe5\xf0\xe6\xe0\xf2\xfc!', waiting = 2.0 },
            }},
        }
        settings.quest_congrats.items = nil
    end
    if not settings.quest_congrats.variants then
        settings.quest_congrats.variants = {
            { items = {
                { text = '{player_name}, \xee\xf2\xeb\xe8\xf7\xed\xe0\xff \xf0\xe0\xe1\xee\xf2\xe0! \xca\xe2\xe5\xf1\xf2 \xe2\xfb\xef\xee\xeb\xed\xe5\xed!', waiting = 1.5 },
                { text = '\xd2\xe0\xea \xe4\xe5\xf0\xe6\xe0\xf2\xfc, \xef\xf0\xee\xe4\xee\xeb\xe6\xe0\xe9 \xe2 \xf2\xee\xec \xe6\xe5 \xe4\xf3\xf5\xe5!', waiting = 2.0 },
            }},
            { items = {
                { text = '{player_name}, \xea\xe2\xe5\xf1\xf2 \xf1\xe4\xe0\xed \x97 \xec\xee\xeb\xee\xe4\xe5\xf6, \xed\xe5 \xeb\xe5\xed\xe8\xf8\xfc\xf1\xff!', waiting = 1.5 },
                { text = '\xcf\xf0\xee\xe4\xee\xeb\xe6\xe0\xe9 \xe2 \xf2\xee\xec \xe6\xe5 \xe4\xf3\xf5\xe5, \xf1\xe5\xec\xfc\xff \xfd\xf2\xee \xf6\xe5\xed\xe8\xf2.', waiting = 2.0 },
            }},
            { items = {
                { text = '\xd5\xee\xf0\xee\xf8\xe0\xff \xf0\xe0\xe1\xee\xf2\xe0, {player_name}!', waiting = 1.5 },
                { text = '\xca\xe2\xe5\xf1\xf2 \xe2\xfb\xef\xee\xeb\xed\xe5\xed, \xf1\xe5\xec\xfc\xff \xf0\xe0\xf1\xf2\xb8\xf2. \xd2\xe0\xea \xe4\xe5\xf0\xe6\xe0\xf2\xfc!', waiting = 2.0 },
            }},
        }
    end
    if settings.quest_congrats.variant_idx == nil then settings.quest_congrats.variant_idx = 0 end
    while #settings.quest_congrats.variants < 3 do
        table.insert(settings.quest_congrats.variants, { items = {{text='{player_name}, \xea\xe2\xe5\xf1\xf2 \xe2\xfb\xef\xee\xeb\xed\xe5\xed!', waiting=1.5}} })
    end
    for _, v in ipairs(settings.quest_congrats.variants) do v.items = v.items or {} end
    -- \xdf\xe2\xed\xe0\xff \xe7\xe0\xf9\xe8\xf2\xe0 \xe1\xf3\xeb\xe5\xe2\xfb\xf5 \xed\xe0\xf1\xf2\xf0\xee\xe5\xea \xee\xf2 \xef\xee\xf2\xe5\xf0\xe8 false \xef\xf0\xe8 JSON \xf1\xe5\xf0\xe8\xe0\xeb\xe8\xe7\xe0\xf6\xe8\xe8
    -- moonloader encodeJson \xec\xee\xe6\xe5\xf2 \xf2\xe5\xf0\xff\xf2\xfc false -> null -> nil -> merge \xef\xee\xe4\xf1\xf2\xe0\xe2\xeb\xff\xe5\xf2 default true
    local function def_bool(tbl, key, default)
        if tbl[key] == nil then tbl[key] = default end
    end
    def_bool(settings.quest_congrats, 'enabled', true)
    if not settings.general.keyword_invite_list or #settings.general.keyword_invite_list == 0 then
        settings.general.keyword_invite_list = {'\xe8\xed\xe2', '\xe8\xed\xe2\xe0\xe9\xf2', '\xe8\xed\xe2\xe0\xe9\xf2 \xef\xe6', '\xec\xee\xe6\xed\xee \xe2 \xf4\xe0\xec', '\xef\xf0\xe8\xec\xe8', '\xe8\xed\xe2 \xe2 \xf4\xe0\xec\xf3', '\xef\xf0\xe8\xec\xe8 \xe2 \xf1\xe5\xec\xfc\xfe', '\xf5\xee\xf7\xf3 \xe2 \xf4\xe0\xec', '\xe2\xee\xe7\xfc\xec\xe8 \xe2 \xf1\xe5\xec\xfc\xfe'}
    end
    def_bool(settings.general, 'auto_welcome',        true)
    def_bool(settings.general, 'auto_congrats',       true)
    def_bool(settings.general, 'auto_quest_congrats', true)
    def_bool(settings.general, 'auto_keyword_invite', true)
    def_bool(settings.general, 'auto_invite',         false)
    def_bool(settings.general, 'rp_chat',             true)
    def_bool(settings.general, 'auto_vr_confirm',     true)
    def_bool(settings.general, 'auto_ad_confirm', false)
    def_bool(settings.general, 'auto_storage_collect', false)
    def_bool(settings.general, 'auto_rp_guns', false)
    if settings.general.auto_ad_station_idx == nil then settings.general.auto_ad_station_idx = 2 end
    if settings.general.auto_ad_type        == nil then settings.general.auto_ad_type        = 0 end
    def_bool(settings.general, 'auto_mute_insults',   false)
    def_bool(settings.general, 'auto_mute_spam',      false)
    def_bool(settings.general, 'auto_mute_flood',     false)
    def_bool(settings.general, 'float_btn_enable',    true)
    -- \xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8 \xf4\xeb\xf3\xe4-\xea\xee\xed\xf2\xf0\xee\xeb\xff
    if settings.general.flood_msg_count == nil then settings.general.flood_msg_count = 5 end
    if settings.general.flood_interval  == nil then settings.general.flood_interval  = 15 end
    settings.invite_history = settings.invite_history or {}
    if settings.general.float_btn_enable==nil then settings.general.float_btn_enable=true end
    settings.interface.accent_r=settings.interface.accent_r or 1.0; settings.interface.accent_g=settings.interface.accent_g or 0.65
    settings.interface.accent_b=settings.interface.accent_b or 0.0; settings.interface.window_alpha=settings.interface.window_alpha or 0.97
    settings.interface.bg_brightness=settings.interface.bg_brightness or 0.13
end

function load_settings()
    if not doesDirectoryExist(configDirectory) then createDirectory(configDirectory) end
    if not doesFileExist(path) then
        settings = default_settings
    else
        local file = io.open(path, 'r')
        if file then
            local contents = file:read('*a'); file:close()
            if #contents == 0 then settings = default_settings
            else
                local ok, loaded = pcall(decodeJson, contents)
                if ok and loaded then
                    settings = loaded; merge_defaults(settings, default_settings); validate_settings()
                    if settings.general.version ~= thisScript().version then settings.general.version = thisScript().version; save_settings() end
                else settings = default_settings end
            end
        else settings = default_settings end
    end
    validate_settings()
end

function save_settings()
    local file = io.open(path, 'w')
    if file then
        local ok, encoded = pcall(encodeJson, settings)
        file:write(ok and encoded or ""); file:close(); return ok
    end
    return false
end

load_settings()
load_log()

------------------------------------------- MONET --------------------------------------------------
function isMonetLoader() return MONET_VERSION ~= nil end

if isMonetLoader() then
    gta = ffi.load('GTASA')
    pcall(ffi.cdef, [[ void _Z12AND_OpenLinkPKc(const char* link); ]])
end

if not settings.general.autofind_dpi then
    if isMonetLoader() then
        settings.general.custom_dpi = MONET_DPI_SCALE or 1.0
    else
        local bw, bh = 1366, 768; local cw, ch = getScreenResolution()
        settings.general.custom_dpi = ((cw / bw) + (ch / bh)) / 2
    end
    settings.general.autofind_dpi = true; save_settings()
end

---------------------------------------------- IMGUI VARS -------------------------------------------------
local imgui = require('mimgui')
local sizeX, sizeY = getScreenResolution()
local MainWindow = imgui.new.bool()
local InteractMenu = imgui.new.bool()

  
  local qa = {
    bl_name       = imgui.new.char[256](""),
    bl_reason     = imgui.new.char[256](""),
    offline_days  = imgui.new.int(7),
    reward_amount = imgui.new.int(50000),
    tag_rank      = imgui.new.char[32](""),
    tag_text      = imgui.new.char[128](""),
    -- Quick Actions State
    mute_id       = imgui.new.char[32](""),
    mute_time     = imgui.new.char[32](""),
    mute_reason   = imgui.new.char[128](""),
    rank_id       = imgui.new.char[32](""),
    rank_val      = imgui.new.char[32](""),
    kick_id       = imgui.new.char[32](""),
    kick_reason   = imgui.new.char[128](""),
    warn_id       = imgui.new.char[32](""),
    warn_reason   = imgui.new.char[128](""),
    invite_id     = imgui.new.char[32](""),
    unmute_id     = imgui.new.char[32](""),
    offkick_nick  = imgui.new.char[64](""),
  }
  
local InteractSelectPlayer = imgui.new.bool()
local FastMenu = imgui.new.bool()
local NoteWindow = imgui.new.bool()
local BinderWindow = imgui.new.bool()
local CommandStopWindow = imgui.new.bool()
local CommandPauseWindow = imgui.new.bool()
local PiarEditWindow = imgui.new.bool()
local InteractEditWindow = imgui.new.bool()
local piar_edit_index = nil
local interact_edit_index = nil

local input_family_name = imgui.new.char[256](u8(settings.family_info.family_name))
local input_family_tag = imgui.new.char[256](u8(settings.family_info.family_tag))
local input_my_name = imgui.new.char[256](u8(settings.family_info.my_name))
local input_my_rank = imgui.new.char[256](u8(settings.family_info.my_rank))
local sl = {
  dpi          = imgui.new.float(tonumber(settings.general.custom_dpi) or 1),
  invite_radius = imgui.new.float(settings.general.auto_invite_radius),
  invite_delay  = imgui.new.float(settings.general.auto_invite_delay),
  float_size    = imgui.new.float(settings.general.float_btn_size or 1.0),
  float_radius  = imgui.new.float(settings.general.float_btn_radius or 15),
  window_alpha  = imgui.new.float(settings.interface.window_alpha or 0.97),
  bg_bright     = imgui.new.float(settings.interface.bg_brightness or 0.13),
    auto_mute_time = imgui.new.int(settings.general.auto_mute_insults_time or 60),
  auto_mute_spam_time = imgui.new.int(settings.general.auto_mute_spam_time or 30),
  auto_mute_flood_time = imgui.new.int(settings.general.auto_mute_flood_time or 30),
}
local accent_color = imgui.new.float[3](settings.interface.accent_r or 1.0, settings.interface.accent_g or 0.65, settings.interface.accent_b or 0.0)
local waiting_slider = imgui.new.float(0)
local ComboTags = imgui.new.int()
local item_list = {u8'\xc1\xe5\xe7 \xe0\xf0\xe3\xf3\xec\xe5\xed\xf2\xe0', u8'{arg} - \xeb\xfe\xe1\xee\xe9', u8'{arg_id} - ID', u8'{arg_id} {arg2} - ID+\xf2\xe5\xea\xf1\xf2'}
local ImItems
do
    local _ok, _result = pcall(function()
        return imgui.new['const char*'][#item_list](item_list)
    end)
    if _ok and _result then
        ImItems = _result
    else
        local _tmp = imgui.new['const char*'][#item_list]()
        for _i = 0, #item_list - 1 do _tmp[_i] = item_list[_i + 1] end
        ImItems = _tmp
    end
end
local change_waiting, change_cmd, change_description, change_text, change_arg
local kw_input = imgui.new.char[128]("")
local event_log = {}
local congrats_batch = {}          -- \xc1\xf3\xf4\xe5\xf0 \xed\xe8\xea\xee\xe2 \xe4\xeb\xff \xef\xee\xe7\xe4\xf0\xe0\xe2\xeb\xe5\xed\xe8\xfe
local congrats_batch_timer = nil   -- \xf2\xe0\xe9\xec\xe5\xf0 \xe4\xeb\xff \xee\xf2\xef\xf0\xe0\xe2\xea\xe8 \xe1\xe0\xf2\xf7\xe0
local CONGRATS_BATCH_WINDOW = 2    -- \xf1\xe5\xea\xf3\xed\xe4 \xee\xe6\xe8\xe4\xe0\xed\xe8\xff (\xf1\xee\xe1\xe8\xf0\xe0\xe5\xec \xed\xe8\xea\xe8 \xe7\xe0 2 \xf1\xe5\xea\xf3\xed\xe4\xfb)
local CONGRATS_BATCH_SINGLE = 2    -- \xe5\xf1\xeb\xe8 \xef\xee\xe2\xfb\xf1\xe8\xeb\xee\xf1\xfc \xec\xe5\xed\xe5\xe5 N \xf7\xe5\xeb. \x97 \xee\xf2\xf1\xfb\xeb\xe0\xe5\xec \xef\xee \xe8\xec\xe5\xed\xe8
local CONGRATS_BATCH_MSG = '\xd0\xe5\xe1\xff\xf2\xe0, \xec\xee\xeb\xee\xe4\xf6\xfb! {names} \xef\xee\xe2\xfb\xf1\xe8\xeb\xe8 \xf3\xf0\xee\xe2\xe5\xed\xfc! \xd2\xe0\xea \xe4\xe5\xf0\xe6\xe0\xf2\xfc!'
local CONGRATS_BATCH_MSGS = {
    '\xd0\xe5\xe1\xff\xf2\xe0, \xec\xee\xeb\xee\xe4\xf6\xfb! {names} \xef\xee\xe2\xfb\xf1\xe8\xeb\xe8 \xf3\xf0\xee\xe2\xe5\xed\xfc! \xd2\xe0\xea \xe4\xe5\xf0\xe6\xe0\xf2\xfc!',
    '{names} \x97 \xef\xee\xe7\xe4\xf0\xe0\xe2\xeb\xff\xfe \xf1 \xed\xee\xe2\xfb\xec \xf3\xf0\xee\xe2\xed\xe5\xec! \xcf\xf0\xee\xea\xe0\xf7\xea\xe0 \xe8\xe4\xb8\xf2!',
    '\xce\xf2\xeb\xe8\xf7\xed\xe0\xff \xf0\xe0\xe1\xee\xf2\xe0, {names}! \xd3\xf0\xee\xe2\xe5\xed\xfc \xef\xee\xe4\xed\xff\xf2, \xef\xf0\xee\xe4\xee\xeb\xe6\xe0\xe9\xf2\xe5 \xe2 \xf2\xee\xec \xe6\xe5 \xe4\xf3\xf5\xe5!',
}
local CONGRATS_BATCH_MSG_IDX = 0  -- \xf1\xf7\xb8\xf2\xf7\xe8\xea \xf7\xe5\xf0\xe5\xe4\xee\xe2\xe0\xed\xe8\xff
local fmembers_online = {}       -- \xf1\xef\xe8\xf1\xee\xea \xee\xed\xeb\xe0\xe9\xed \xe8\xe7 \xef\xee\xf1\xeb\xe5\xe4\xed\xe5\xe3\xee /fmembers (\xe8\xec\xff -> \xf0\xe0\xed\xe3)
local fmembers_offline = {}  -- \xed\xe8\xea -> \xe4\xed\xe9 \xed\xe5\xe0\xea\xf2\xe8\xe2\xe0
local debug_dialog = false   -- \xf0\xe5\xe6\xe8\xec \xe4\xe5\xe1\xe0\xe3\xe0 \xe4\xe8\xe0\xeb\xee\xe3\xee\xe2
local FAMLOG_MAX = 999999  -- \xe1\xe5\xe7 \xeb\xe8\xec\xe8\xf2\xe0
local fmembers_last_update = 0   -- timestamp \xef\xee\xf1\xeb\xe5\xe4\xed\xe5\xe3\xee \xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xff
local fmember_ctx_nick = nil     -- \xed\xe8\xea \xe8\xe3\xf0\xee\xea\xe0 \xe4\xeb\xff \xea\xee\xed\xf2\xe5\xea\xf1\xf2\xed\xee\xe3\xee \xec\xe5\xed\xfe
local pending_call_nick = nil    -- \xee\xe6\xe8\xe4\xe0\xe5\xec \xed\xee\xec\xe5\xf0 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0 \xe4\xeb\xff \xe7\xe2\xee\xed\xea\xe0 \xfd\xf2\xee\xec\xf3 \xed\xe8\xea\xf3
local pending_sms_nick = nil     -- \xee\xe6\xe8\xe4\xe0\xe5\xec \xed\xee\xec\xe5\xf0 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0 \xe4\xeb\xff SMS
local pending_sms_text = ''      -- \xf2\xe5\xea\xf1\xf2 SMS \xea\xee\xf2\xee\xf0\xfb\xe9 \xed\xe0\xe4\xee \xee\xf2\xef\xf0\xe0\xe2\xe8\xf2\xfc
-- TG \xe1\xf3\xf4\xe5\xf0\xfb (\xf1\xee\xe7\xe4\xe0\xfe\xf2\xf1\xff \xee\xe4\xe8\xed \xf0\xe0\xe7, \xed\xe5 \xea\xe0\xe6\xe4\xfb\xe9 \xea\xe0\xe4\xf0)
local tg_token_buf  = nil
local tg_chatid_buf = nil
local fmember_ctx_open = false   -- \xf4\xeb\xe0\xe3 \xee\xf2\xea\xf0\xfb\xf2\xe8\xff \xec\xe5\xed\xfe
local MemberCtxWindow = imgui.new.bool(false)  -- \xee\xea\xed\xee \xe4\xe5\xe9\xf1\xf2\xe2\xe8\xe9 \xf1 \xe8\xe3\xf0\xee\xea\xee\xec
local ctx_rank_input = imgui.new.int(1)        -- \xe2\xe2\xee\xe4 \xf0\xe0\xed\xe3\xe0
local ctx_reason_buf = imgui.new.char[128]('')  -- \xe2\xe2\xee\xe4 \xef\xf0\xe8\xf7\xe8\xed\xfb
local ctx_sms_buf    = imgui.new.char[256]('')  -- \xe2\xe2\xee\xe4 \xf1\xec\xf1
local ctx_tag_buf    = imgui.new.char[64]('')   -- \xef\xee\xeb\xe5 \xe2\xe2\xee\xe4\xe0 \xf2\xe5\xe3\xe0
local function log_event(msg)
    table.insert(event_log, 1, os.date('[%H:%M] ') .. msg)
    if #event_log > 20 then table.remove(event_log) end
end
local interact_player_id = nil
local player_id = nil
local isActiveCommand = false
local command_stop = false
local command_pause = false
local reload_script = false
local show_note_name, show_note_text = nil, nil
local invited_players = {}
local invite_price_normal_input = imgui.new.int(settings.general.invite_price_normal or 2000000)
local invite_price_bonus_input  = imgui.new.int(settings.general.invite_price_bonus or 4000000)
local invite_bonus_thresh_input = imgui.new.int(settings.general.invite_bonus_threshold or 50)
local message_color = 0xFFA500
local message_color_hex = '{FFA500}'
local nearby_players = {}
local invite_session = 0
local nearby_time = 0


------------------------------------------------- UTILS --------------------------------------------------------
function TranslateNick(name)
    if not name or name == '' then return '' end
    if name:match('%a+') then
        for k, v in pairs({['ph']='\xf4',['Ph']='\xd4',['Ch']='\xd7',['ch']='\xf7',['Th']='\xd2',['th']='\xf2',['Sh']='\xd8',['sh']='\xf8',['Ck']='\xca',['ck']='\xea',['Kh']='\xd5',['kh']='\xf5',['Zh']='\xc6',['zh']='\xe6',['Yu']='\xde',['yu']='\xfe',['Yo']='\xa8',['yo']='\xb8',['Ya']='\xdf',['ya']='\xff',['oo']='\xf3',['ee']='\xe8'}) do name = name:gsub(k, v) end
        for k, v in pairs({['B']='\xc1',['Z']='\xc7',['T']='\xd2',['Y']='\xc9',['P']='\xcf',['J']='\xc4\xe6',['X']='\xca\xf1',['G']='\xc3',['V']='\xc2',['H']='\xd5',['N']='\xcd',['E']='\xc5',['I']='\xc8',['D']='\xc4',['O']='\xce',['K']='\xca',['F']='\xd4',['A']='\xc0',['C']='\xca',['L']='\xcb',['M']='\xcc',['W']='\xc2',['Q']='\xca',['U']='\xc0',['R']='\xd0',['S']='\xd1',['h']='\xf5',['q']='\xea',['y']='\xe8',['a']='\xe0',['w']='\xe2',['b']='\xe1',['v']='\xe2',['g']='\xe3',['d']='\xe4',['e']='\xe5',['z']='\xe7',['i']='\xe8',['j']='\xe6',['k']='\xea',['l']='\xeb',['m']='\xec',['n']='\xed',['o']='\xee',['p']='\xef',['r']='\xf0',['s']='\xf1',['t']='\xf2',['u']='\xf3',['f']='\xf4',['x']='\xea\xf1',['c']='\xea',['_']=' '}) do name = name:gsub(k, v) end
    end
    return name
end

function string.rupper(s)
    if not s or #s == 0 then return s or '' end
    local b = s:byte(1)
    if b and b >= 224 and b <= 255 then return string.char(b - 32) .. s:sub(2) end
    return s:sub(1,1):upper() .. s:sub(2)
end

function isParamSampID(id)
    id = tonumber(id)
    if id and id >= 0 and id <= 999 then return id == select(2, sampGetPlayerIdByCharHandle(PLAYER_PED)) or sampIsPlayerConnected(id) end
    return false
end

function get_players_in_radius(radius)
    local result = {}
    local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    local mx, my, mz = getCharCoordinates(PLAYER_PED)
    for _, h in pairs(getAllChars()) do
        if h ~= PLAYER_PED and doesCharExist(h) then
            local res, id = sampGetPlayerIdByCharHandle(h)
            if res and id ~= -1 and sampIsPlayerConnected(id) then
                local x, y, z = getCharCoordinates(h)
                if getDistanceBetweenCoords3d(mx, my, mz, x, y, z) <= radius then
                    table.insert(result, id)
                end
            end
        end
    end
    return result
end

function processText(text, target_id)
    if not text then return '' end
    if target_id then
        local nick = sampGetPlayerNickname(target_id) or ''
        local ru_nick = TranslateNick(nick)
        local rp_nick = nick:gsub('_', ' ')
        text = text:gsub('%{get_ru_nick%(%{arg_id%}%)%}', ru_nick)
        text = text:gsub('%{get_rp_nick%(%{arg_id%}%)%}', rp_nick)
        text = text:gsub('%{get_nick%(%{arg_id%}%)%}', nick)
        text = text:gsub('{get_ru_nick}', ru_nick)
        text = text:gsub('{get_rp_nick}', rp_nick)
        text = text:gsub('{get_nick}', nick)
        text = text:gsub('{arg_id}', tostring(target_id))
    end
    text = text:gsub('{my_name}', settings.family_info.my_name or '')
    text = text:gsub('{my_rank}', settings.family_info.my_rank or '')
    text = text:gsub('{family_name}', settings.family_info.family_name or '')
    text = text:gsub('{family_tag}', settings.family_info.family_tag or '')
    text = text:gsub('{leader_name}', settings.family_info.leader_name or '')
    text = text:gsub('{my_id}', tostring(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))))
    text = text:gsub('{my_nick}', sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))) or '')
    text = text:gsub('{get_time}', os.date("%H:%M:%S"))
    text = text:gsub('{get_date}', os.date("%d.%m.%Y"))
    return text
end

function change_dpi()
    if not isMonetLoader() then imgui.SetWindowFontScale(settings.general.custom_dpi) end
end

function send_lines(text, waiting, target_id, callback)
    if isActiveCommand then sampAddChatMessage('[Family Helper] {ffffff}\xc4\xee\xe6\xe4\xe8\xf2\xe5\xf1\xfc \xe7\xe0\xe2\xe5\xf0\xf8\xe5\xed\xe8\xff!', message_color) return end
    text = processText(text, target_id)
    lua_thread.create(function()
        isActiveCommand = true; CommandStopWindow[0] = true
        local lines = {}
        for line in text:gmatch("[^&]+") do table.insert(lines, line) end
        for i, line in ipairs(lines) do
            if command_stop then command_stop = false; break end
            if line == "{pause}" then
                command_pause = true; CommandPauseWindow[0] = true
                while command_pause do wait(0) end
                if command_stop then command_stop = false; break end
            else
                if i > 1 then wait((waiting or 1.5) * 1000) end
                if not command_stop then sampSendChat(line) end
            end
        end
        isActiveCommand = false; CommandStopWindow[0] = false
        if callback then callback() end
    end)
end

function send_interaction(index, target_id)
    local inter = settings.interactions[index]
    if not inter then return end
    send_lines(table.concat(inter.lines, '&'), inter.waiting, target_id)
end

function send_piar(index)
    local t = settings.piar_templates[index]
    if not t or not t.enable then return end
    send_lines(table.concat(t.lines, '&'), t.waiting, nil, function() t.last_time = os.time() end)
end

------------------------------------------------- MAIN --------------------------------------------------------
-- ========== \xce\xca\xcd\xce \xc4\xc5\xc9\xd1\xd2\xc2\xc8\xc9 \xd1 \xc8\xc3\xd0\xce\xca\xce\xcc ==========
imgui.OnFrame(function() return MemberCtxWindow[0] end, function()
    if not fmember_ctx_nick then MemberCtxWindow[0] = false; return end
    local d = settings.general.custom_dpi
    local ar = settings.interface.accent_r or 1.0
    local ag = settings.interface.accent_g or 0.65
    local ab = settings.interface.accent_b or 0.0
    imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY/2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(420*d, 0), imgui.Cond.Always)
    imgui.Begin(safe_u8(' \xc4\xe5\xe9\xf1\xf2\xe2\xe8\xff: ' .. fmember_ctx_nick), MemberCtxWindow,
        imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.AlwaysAutoResize)
    change_dpi()

    local nick = fmember_ctx_nick
    local bw = (imgui.GetWindowContentRegionWidth() - 8*d) / 2

    imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), safe_u8(' \xc8\xe3\xf0\xee\xea: ' .. nick))
    imgui.Separator(); imgui.Spacing()

    -- === \xc7\xc2\xce\xcd\xce\xca / \xd1\xcc\xd1 ===
    imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xd1\xe2\xff\xe7\xfc')
    imgui.Separator()
    if imgui.Button(u8' \xcf\xee\xe7\xe2\xee\xed\xe8\xf2\xfc ', imgui.ImVec2(-1, 28*d)) then
        local pid = nil
        for ci = 0, 999 do
            if sampIsPlayerConnected(ci) then
                if sampGetPlayerNickname(ci) == nick then pid = ci; break end
            end
        end
        if pid then
            pending_call_nick = nick
            sampSendChat('/number ' .. pid)
        else
            sampAddChatMessage('[Family Helper] {ff4444}\xc8\xe3\xf0\xee\xea ' .. nick .. ' \xed\xe5 \xed\xe0\xe9\xe4\xe5\xed \xe2 \xf1\xe5\xf2\xe8', 0xFFA500)
        end
        MemberCtxWindow[0] = false
    end
    imgui.Spacing()
    imgui.PushItemWidth(imgui.GetWindowContentRegionWidth() - 80*d)
    imgui.InputText(u8'##sms_buf', ctx_sms_buf, 256)
    imgui.PopItemWidth(); imgui.SameLine()
    if imgui.Button(u8' \xd1\xcc\xd1 ##send', imgui.ImVec2(-1, 0)) then
        local txt = u8:decode(ffi.string(ctx_sms_buf)):match('^%s*(.-)%s*$')
        if txt ~= '' then
            local pid = nil
            for ci = 0, 999 do
                if sampIsPlayerConnected(ci) then
                    if sampGetPlayerNickname(ci) == nick then pid = ci; break end
                end
            end
            if pid then
                pending_sms_nick = nick
                pending_sms_text = txt
                sampSendChat('/number ' .. pid)
            else
                -- \xc8\xe3\xf0\xee\xea \xed\xe5 \xed\xe0\xe9\xe4\xe5\xed \xe2 \xf1\xe5\xf2\xe8 \x97 \xef\xf0\xee\xe1\xf3\xe5\xec \xef\xee \xed\xe8\xea\xf3 (offline)
                sampSendChat('/sms ' .. nick .. ' ' .. txt)
            end
            MemberCtxWindow[0] = false
        end
    end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    -- === \xd0\xc0\xcd\xc3 ===
    imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xd0\xe0\xed\xe3')
    imgui.Separator()
    imgui.Text(u8' \xcd\xee\xe2\xfb\xe9 \xf0\xe0\xed\xe3:'); imgui.SameLine()
    if imgui.Button(u8'-##rnm', imgui.ImVec2(26*d, 0)) then ctx_rank_input[0] = math.max(1, ctx_rank_input[0]-1) end
    imgui.SameLine()
    imgui.PushItemWidth(50*d)
    imgui.InputInt(u8'##rni', ctx_rank_input, 0)
    ctx_rank_input[0] = math.max(1, math.min(10, ctx_rank_input[0]))
    imgui.PopItemWidth(); imgui.SameLine()
    if imgui.Button(u8'+##rnp', imgui.ImVec2(26*d, 0)) then ctx_rank_input[0] = math.min(10, ctx_rank_input[0]+1) end
    imgui.SameLine()
    if imgui.Button(u8' \xd3\xf1\xf2\xe0\xed\xee\xe2\xe8\xf2\xfc \xf0\xe0\xed\xe3 ##setrk', imgui.ImVec2(-1, 0)) then
        sampSendChat('/setfrank ' .. nick .. ' ' .. ctx_rank_input[0])
        MemberCtxWindow[0] = false

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    -- === \xd2\xc5\xc3 ===
    imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xd2\xe5\xe3')
    imgui.Separator()
    imgui.PushItemWidth(imgui.GetWindowContentRegionWidth() - 80*d)
    imgui.InputText(u8'##tag_buf', ctx_tag_buf, 64)
    imgui.PopItemWidth(); imgui.SameLine()
    if imgui.Button(u8' /ftag ##settag', imgui.ImVec2(-1, 0)) then
        local tag = u8:decode(ffi.string(ctx_tag_buf)):match('^%s*(.-)%s*$')
        if tag ~= '' then
            sampSendChat('/ftag ' .. nick .. ' ' .. tag)
            MemberCtxWindow[0] = false
        end
    end
    end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    -- === \xcc\xd3\xd2 / \xc2\xdb\xc3\xce\xc2\xce\xd0 / \xca\xc8\xca ===
    imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xcd\xe0\xea\xe0\xe7\xe0\xed\xe8\xe5')
    imgui.Separator()
    imgui.PushItemWidth(imgui.GetWindowContentRegionWidth())
    imgui.InputText(u8'##reason', ctx_reason_buf, 128)
    imgui.PopItemWidth()
    imgui.TextDisabled(u8'  \xef\xf0\xe8\xf7\xe8\xed\xe0 (\xed\xe5\xee\xe1\xff\xe7\xe0\xf2\xe5\xeb\xfc\xed\xee)')
    imgui.Spacing()
    local reason = u8:decode(ffi.string(ctx_reason_buf)):match('^%s*(.-)%s*$')
    if reason == '' then reason = '\xcd\xe0\xf0\xf3\xf8\xe5\xed\xe8\xe5 \xef\xf0\xe0\xe2\xe8\xeb' end
    if imgui.Button(u8' \xc2\xfb\xe4\xe0\xf2\xfc \xec\xf3\xf2 ##fmu', imgui.ImVec2(bw, 28*d)) then
        sampSendChat('/fammute ' .. nick)
        MemberCtxWindow[0] = false
    end
    imgui.SameLine()
    if imgui.Button(u8' \xd1\xed\xff\xf2\xfc \xec\xf3\xf2 ##fumu', imgui.ImVec2(bw, 28*d)) then
        sampSendChat('/famunmute ' .. nick)
        MemberCtxWindow[0] = false
    end
    if imgui.Button(u8' \xca\xe8\xea \xe8\xe7 \xf1\xe5\xec\xfc\xe8 ##funinv', imgui.ImVec2(bw, 28*d)) then
        sampSendChat('/famuninvite ' .. nick .. ' ' .. reason)
        MemberCtxWindow[0] = false
    end
    imgui.SameLine()
    if imgui.Button(u8' \xca\xe8\xea offline ##famoffk', imgui.ImVec2(bw, 28*d)) then
        sampSendChat('/famoffkick ' .. nick)
        MemberCtxWindow[0] = false
    end
    if imgui.Button(u8' \xcf\xee\xf5\xe2\xe0\xeb\xe0 ##prais', imgui.ImVec2(bw, 28*d)) then
        sampSendChat('/praise ' .. nick)
        MemberCtxWindow[0] = false
    end



    imgui.Spacing()
    if imgui.Button(u8' \xc7\xe0\xea\xf0\xfb\xf2\xfc ', imgui.ImVec2(-1, 28*d)) then MemberCtxWindow[0] = false end
    imgui.End()
end)


-- ========== \xcb\xce\xc3 \xd1\xc5\xcc\xdc\xc8 ==========
local function flog(category, entry)
    entry.time = entry.time or os.date('%H:%M:%S')
    entry.date = entry.date or os.date('%d.%m.%Y')
    local t = famlog[category]
    if not t then return end
    table.insert(t, 1, entry)
    if #t > 200 then t[#t] = nil end

    -- \xd1\xee\xf5\xf0\xe0\xed\xff\xe5\xec \xed\xe5 \xf7\xe0\xf9\xe5 \xf0\xe0\xe7\xe0 \xe2 10 \xf1\xe5\xea\xf3\xed\xe4\xfb
    local now = os.time()
    if not _G.log_last_save or now - _G.log_last_save >= 10 then
        _G.log_last_save = now
        save_log()
    end
end

-- ========== TELEGRAM \xc8\xcd\xd2\xc5\xc3\xd0\xc0\xd6\xc8\xdf ==========

-- \xc2\xee\xe7\xe2\xf0\xe0\xf9\xe0\xe5\xf2 \xed\xe8\xea \xf2\xe5\xea\xf3\xf9\xe5\xe3\xee \xe8\xe3\xf0\xee\xea\xe0
local function my_nick()
    local ok, pid = pcall(select, 2, sampGetPlayerIdByCharHandle(PLAYER_PED))
    if ok and pid then return sampGetPlayerNickname(pid) end
    return ''
end

-- ===== FH \xc0\xc2\xd2\xce-\xc3\xcb\xc0\xc2\xc5\xcd\xd1\xd2\xc2\xce =====
-- {\xed\xe8\xea = {rank=N, joined=timestamp, last_seen=timestamp}}
local fh_online = {}
local FH_MARKER        = '\xE2\x80\x8B[FH:'
local FH_PING_INTERVAL = 180
local FH_TIMEOUT       = 420
local fh_last_ping     = os.time()
local fh_joined        = os.time()  -- \xe2\xf0\xe5\xec\xff \xe2\xf5\xee\xe4\xe0 \xe2 \xe8\xe3\xf0\xf3 = \xef\xf0\xe8\xee\xf0\xe8\xf2\xe5\xf2 \xef\xf0\xe8 \xf0\xe0\xe2\xed\xee\xec \xf0\xe0\xed\xe3\xe5

local function fh_my_rank_num()
    return tonumber(settings.family_info.my_rank_number) or 1
end

local function fh_update_self()
    local me = my_nick()
    if me and me ~= '' then
        fh_online[me] = {rank=fh_my_rank_num(), joined=fh_joined, last_seen=os.time()}
    end
end

local FH_PING_PHRASES = {
    '\xc2\xf1\xe5\xec \xef\xf0\xe8\xe2\xe5\xf2!',
    '\xc2\xf1\xe5\xec \xe4\xee\xe1\xf0\xe0!',
    '\xc4\xee\xe1\xf0\xee\xe3\xee \xe2\xf1\xe5\xec!',
    '\xcf\xf0\xe8\xe2\xe5\xf2 \xe2\xf1\xe5\xec!',
    '\xc2\xf1\xe5\xec \xf3\xe4\xe0\xf7\xe8!',
    '\xcd\xe0 \xf1\xe2\xff\xe7\xe8!',
    '\xc2\xf1\xe5\xec \xf5\xee\xf0\xee\xf8\xe5\xe3\xee \xe4\xed\xff!',
    '\xc1\xf3\xe4\xfc\xf2\xe5 \xe0\xea\xf2\xe8\xe2\xed\xfb!',
}

local function fh_send_ping()
    if not settings.tg or not settings.tg.enabled or not settings.tg.auto_role then return end
    local me = my_nick()
    if not me or me == '' then return end
    fh_update_self()
    fh_last_ping = os.time()
    local token      = settings.tg.token      or ''
    local channel_id = settings.tg.channel_id or ''
    -- Шлём пинг в канал бота — все скрипты читают один канал через channel_post
    if token == '' or channel_id == '' then return end
    if not tg_effil then
        local ok, lib = pcall(require, 'effil')
        if ok and lib then tg_effil = lib end
    end
    if not tg_effil then return end
    local rank   = fh_my_rank_num()
    local joined = fh_joined
    local _pt = '[FH_PING:' .. rank .. ':' .. joined .. ':' .. me .. ']'
    local ping_text = _pt:gsub('([^%w%-_%.~])', function(c) return string.format('%%%02X', string.byte(c)) end)
    tg_effil.thread(function(tok, cid, ptxt)
        local ok_r, req = pcall(require, 'requests')
        if not ok_r then return end
        local url = ('https://api.telegram.org/bot%s/sendMessage?chat_id=%s&text=%s'):format(tok, cid, ptxt)
        pcall(req.request, 'POST', url, nil)
    end)(token, channel_id, ping_text)
end

local function fh_cleanup()
    local now = os.time()
    for nick, data in pairs(fh_online) do
        if now - data.last_seen > FH_TIMEOUT then fh_online[nick] = nil end
    end
end

local fh_start_time = os.time()

local function am_i_senior()
    if not settings.tg or not settings.tg.auto_role then return true end
    -- первые 20 секунд после запуска ждём пинги от других скриптов
    if os.time() - fh_start_time < 20 then return false end
    fh_cleanup()
    local me = my_nick()
    if not me or me == '' then return true end
    fh_update_self()
    local my_rank   = fh_my_rank_num()
    local my_joined = fh_joined
    for nick, data in pairs(fh_online) do
        if nick ~= me then
            if data.rank > my_rank then return false end
            if data.rank == my_rank and (data.joined or 0) < my_joined then return false end
        end
    end
    return true
end

local function tg_encode(str)
    str = tostring(str or ''):gsub('{%x%x%x%x%x%x}', '')
    return (str:gsub('([^%w%-_%.~])', function(c)
        return string.format('%%%02X', string.byte(c))
    end))
end

-- ============================================================
-- \xce\xf2\xef\xf0\xe0\xe2\xea\xe0 \xe2 Telegram \x97 effil.thread + requests (MCR \xec\xe5\xf2\xee\xe4)
-- ============================================================
local tg_effil = nil

local function tg_url_encode(s)
    local result = string.gsub(s, '([^%w%-_ %.~=])', function(c)
        return string.format('%%%02X', string.byte(c))
    end)
    return string.gsub(result, ' ', '+')
end

-- Forward declaration (\xf4\xf3\xed\xea\xf6\xe8\xff \xee\xe1\xfa\xff\xe2\xeb\xe5\xed\xe0 \xed\xe8\xe6\xe5)
local tg_fetch_missed

-- \xc2\xf1\xef\xee\xec\xee\xe3\xe0\xf2\xe5\xeb\xfc\xed\xe0\xff: HTTP GET \xf7\xe5\xf0\xe5\xe7 effil (\xf1\xe8\xed\xf5\xf0\xee\xed\xed\xee \xe2\xed\xf3\xf2\xf0\xe8 lua_thread)
local function tg_http_get(url, timeout)
    timeout = timeout or 15
    if not tg_effil then return '' end
    local t = tg_effil.thread(function(u)
        local ok_r, req = pcall(require, 'requests')
        if not ok_r then return '' end
        local ok_s, resp = pcall(req.request, 'GET', u, nil)
        if not ok_s or not resp then return '' end
        return tostring(resp.text or '')
    end)(url)
    local deadline = os.clock() + timeout
    while os.clock() < deadline do
        local st, err = t:status()
        if err or st == 'canceled' then return '' end
        if st == 'completed' then
            local ok_g, raw = pcall(function() return t:get() end)
            return (ok_g and raw) and raw or ''
        end
        wait(100)
    end
    return ''
end

-- \xd8\xc0\xc3 1: \xce\xef\xf0\xe5\xe4\xe5\xeb\xff\xe5\xec \xf1\xe2\xee\xe9 \xeb\xe8\xf7\xed\xfb\xe9 chat_id \xe8\xe7 getUpdates
local function tg_fetch_my_chat_id_sync()
    local tg = settings and settings.tg
    if not tg or not tg.enabled then return nil end
    if tg.my_chat_id and tg.my_chat_id ~= '' then return tg.my_chat_id end
    local token = tg.token or ''
    if token == '' then return nil end

    local url = ('https://api.telegram.org/bot%s/getUpdates?limit=100'):format(token) .. '&allowed_updates=%5B%22message%22%2C%22channel_post%22%5D'
    local raw = tg_http_get(url)
    if raw == '' then return nil end

    -- \xc8\xf9\xe5\xec \xeb\xe8\xf7\xed\xee\xe5 \xf1\xee\xee\xe1\xf9\xe5\xed\xe8\xe5 \xee\xf2 \xef\xee\xeb\xfc\xe7\xee\xe2\xe0\xf2\xe5\xeb\xff (\xed\xe5 \xe1\xee\xf2\xe0)
    for cid, rest in raw:gmatch('"chat":%s*{%s*"id":(%-?%d+)([^}]*)') do
        if rest:find('"type":"private"') then
            -- \xcf\xf0\xee\xe2\xe5\xf0\xff\xe5\xec \xf7\xf2\xee \xfd\xf2\xee \xee\xf2 \xe6\xe8\xe2\xee\xe3\xee \xef\xee\xeb\xfc\xe7\xee\xe2\xe0\xf2\xe5\xeb\xff \xe0 \xed\xe5 \xee\xf2 \xe1\xee\xf2\xe0
            local from_is_bot = raw:find('"from":%s*{[^}]*"id":' .. cid .. '[^}]*"is_bot":true')
            if not from_is_bot then
                settings.tg.my_chat_id = cid
                save_settings()
                sampAddChatMessage('[Family Helper] \xd2\xc3 \xeb\xe8\xf7\xea\xe0 \xef\xf0\xe8\xe2\xff\xe7\xe0\xed\xe0 ?', 0x00CC00)
                return cid
            end
        end
    end
    return nil
end

-- \xd8\xc0\xc3 2: \xd0\xe5\xe3\xe8\xf1\xf2\xf0\xe8\xf0\xf3\xe5\xec \xf1\xe5\xe1\xff \x97 \xef\xe8\xf8\xe5\xec \xe1\xee\xf2\xf3 [FH_REG:my_chat_id]


local function tg_autoregister()
    local tg = settings and settings.tg
    if not tg or not tg.enabled then return end
    if not tg_effil then
        local ok, lib = pcall(require, 'effil')
        if ok and lib then tg_effil = lib end
    end
    if not tg_effil then return end

    lua_thread.create(function()
        wait(5000)
        tg_fetch_missed()
    end)
end

local function tg_send(msg)
    local tg = settings and settings.tg
    if not tg or not tg.enabled then return end
    local token      = tg.token      or ''
    local chat_id    = tg.chat_id    or ''
    local channel_id = tg.channel_id or ''
    if token == '' or chat_id == '' then return end
    msg = msg:gsub('%[FH%]', '[' .. os.date('%d.%m.%Y') .. ' | ' .. os.date('%H:%M') .. ']')
    msg = msg:gsub('(\xc8\xe3\xf0\xee\xea [%a_]+ )([%a%d])', function(prefix, ch) return prefix .. ch:upper() end)
    if #msg > 4000 then msg = msg:sub(1, 4000) end

    local ok_enc, enc = pcall(require, 'encoding')
    if ok_enc and enc then
        local ok_u, utf_msg = pcall(function()
            return enc.UTF8:encode(enc.CP1251:decode(msg))
        end)
        if ok_u and utf_msg then msg = utf_msg end
    else
        local ok_u, utf_msg = pcall(function() return u8(msg) end)
        if ok_u and utf_msg then msg = utf_msg end
    end

    local encoded = tg_url_encode(msg)
    local url = ('https://api.telegram.org/bot%s/sendMessage?chat_id=%s&text=%s')
                :format(token, chat_id, encoded)
    local url_chan = channel_id ~= '' and
                ('https://api.telegram.org/bot%s/sendMessage?chat_id=%s&text=%s')
                :format(token, channel_id, encoded) or nil

    if not tg_effil then
        local ok, lib = pcall(require, 'effil')
        if ok and lib then tg_effil = lib end
    end

    if tg_effil then
        local t = tg_effil.thread(function(method, req_url, body)
            local ok_r, req = pcall(require, 'requests')
            if not ok_r then return 'no_requests:' .. tostring(req) end
            local ok_s, resp = pcall(req.request, method, req_url, body)
            if not ok_s then return 'pcall_err:' .. tostring(resp) end
            local status = tostring(resp and resp.status_code or '?')
            local body_text = tostring(resp and resp.text or ''):sub(1, 300)
            return status .. '|' .. body_text
        end)('POST', url, nil)
        if url_chan then
            tg_effil.thread(function(method, req_url, body)
                local ok_r, req = pcall(require, 'requests')
                if not ok_r then return end
                pcall(req.request, method, req_url, body)
            end)('POST', url_chan, nil)
        end

        lua_thread.create(function()
            local deadline = os.clock() + 15
            while os.clock() < deadline do
                local st, err = t:status()
                if err then return end
                if st == 'completed' then
                    local ok_g, res = pcall(function() return t:get() end)
                    local r = tostring(res or '?')
                    if r:find('^200') then
                        -- \xd1\xee\xf5\xf0\xe0\xed\xff\xe5\xec message_id \xe8\xe7 \xee\xf2\xe2\xe5\xf2\xe0 \xe4\xeb\xff copyMessage
                        if not settings.tg.pending then settings.tg.pending = {} end
                    else
                        sampAddChatMessage('TG: \xee\xf8\xe8\xe1\xea\xe0 (' .. r:sub(1, 60) .. ')', 0xFF6600)
                    end
                    return
                end
                if st == 'canceled' then return end
                wait(100)
            end
        end)
    else
        lua_thread.create(function()
            local ok_h, https = pcall(require, 'ssl.https')
            local ok_l, ltn12 = pcall(require, 'ltn12')
            if ok_h and https and ok_l and ltn12 then
                local resp = {}
                pcall(https.request, {url=url, method='GET', sink=ltn12.sink.table(resp)})
            end
        end)
    end

end

-- \xce\xf2\xef\xf0\xe0\xe2\xe8\xf2\xfc \xe2 \xd2\xc3 \xf2\xee\xeb\xfc\xea\xee \xe5\xf1\xeb\xe8: \xe0\xe2\xf2\xee-\xf0\xe5\xe6\xe8\xec (am_i_senior) \xc8\xcb\xc8 \xf0\xee\xeb\xfc 'main' \xc8\xcb\xc8 nick == \xff
-- Дедупликация: одно событие = одно сообщение в ТГ, даже если скрипт у нескольких замов
local _tg_dedup = {}
local function tg_is_dup(msg)
    local now = os.time()
    for k, t in pairs(_tg_dedup) do
        if now - t > 90 then _tg_dedup[k] = nil end
    end
    local key = msg:sub(1, 80) .. os.date('%d%H%M')
    if _tg_dedup[key] then return true end
    _tg_dedup[key] = now
    return false
end

local function tg_send_if(nick_in_event, msg)
    if not settings.tg or not settings.tg.enabled then return end
    -- Режим авто-главенства (пинг через TG, не /fam чат)
    if settings.tg.auto_role then
        if am_i_senior() and not tg_is_dup(msg) then
            tg_send(msg)
        end
        return
    end
    -- Ручной режим: дедупликация всегда активна
    if tg_is_dup(msg) then return end
    local role = settings.tg.role or 'main'
    if role == 'main' then
        tg_send(msg)
    elseif role == 'deputy' then
        if nick_in_event and nick_in_event == my_nick() then
            tg_send(msg)
        end
    end
end



-- \xc4\xe5\xea\xee\xe4\xe8\xf0\xf3\xe5\xf2 \uXXXX unicode escape \xe2 CP1251
local function decode_unicode_cp1251(s)
    return s:gsub('\\u(%x%x%x%x)', function(h)
        local cp = tonumber(h, 16)
        if not cp then return '' end
        local t = {
            [0x410]='\xc0',[0x411]='\xc1',[0x412]='\xc2',[0x413]='\xc3',
            [0x414]='\xc4',[0x415]='\xc5',[0x416]='\xc6',[0x417]='\xc7',
            [0x418]='\xc8',[0x419]='\xc9',[0x41a]='\xca',[0x41b]='\xcb',
            [0x41c]='\xcc',[0x41d]='\xcd',[0x41e]='\xce',[0x41f]='\xcf',
            [0x420]='\xd0',[0x421]='\xd1',[0x422]='\xd2',[0x423]='\xd3',
            [0x424]='\xd4',[0x425]='\xd5',[0x426]='\xd6',[0x427]='\xd7',
            [0x428]='\xd8',[0x429]='\xd9',[0x42a]='\xda',[0x42b]='\xdb',
            [0x42c]='\xdc',[0x42d]='\xdd',[0x42e]='\xde',[0x42f]='\xdf',
            [0x430]='\xe0',[0x431]='\xe1',[0x432]='\xe2',[0x433]='\xe3',
            [0x434]='\xe4',[0x435]='\xe5',[0x436]='\xe6',[0x437]='\xe7',
            [0x438]='\xe8',[0x439]='\xe9',[0x43a]='\xea',[0x43b]='\xeb',
            [0x43c]='\xec',[0x43d]='\xed',[0x43e]='\xee',[0x43f]='\xef',
            [0x440]='\xf0',[0x441]='\xf1',[0x442]='\xf2',[0x443]='\xf3',
            [0x444]='\xf4',[0x445]='\xf5',[0x446]='\xf6',[0x447]='\xf7',
            [0x448]='\xf8',[0x449]='\xf9',[0x44a]='\xfa',[0x44b]='\xfb',
            [0x44c]='\xfc',[0x44d]='\xfd',[0x44e]='\xfe',[0x44f]='\xff',
            [0x401]='\xa8',[0x451]='\xb8',
        }
        return t[cp] or ''
    end)
end
local function utf8_to_cp1251(s)
    -- конвертируем UTF-8 байты кириллицы в CP1251
    return (s:gsub('([РС])([Ђ-ї])', function(b1, b2)
        local hi = b1:byte()
        local lo = b2:byte()
        local cp
        if hi == 0xd0 then
            if lo == 0x81 then return 'Ё' end  -- РЃ = ЕЃ (ЙО)
            if lo >= 0x90 and lo <= 0xbf then cp = lo - 0x90 + 0xc0 end
        elseif hi == 0xd1 then
            if lo == 0x91 then return 'ё' end  -- С‘ = ё (йо)
            if lo >= 0x80 and lo <= 0x8f then cp = lo - 0x80 + 0xe0 end
        end
        return cp and string.char(cp) or ''
    end))
end


-- ===== \xd1\xc8\xcd\xd5\xd0\xce\xcd\xc8\xc7\xc0\xd6\xc8\xdf \xc8\xcd\xc2\xc0\xc9\xd2\xce\xc2 \xc8\xc7 \xd2\xc3 =====
-- \xca\xe0\xf7\xe0\xe5\xf2 \xe2\xf1\xfe \xe8\xf1\xf2\xee\xf0\xe8\xfe \xef\xee\xf1\xf2\xf0\xe0\xed\xe8\xf7\xed\xee (\xe8\xf2\xe5\xf0\xe0\xf2\xe8\xe2\xed\xee) \xe8 \xe2\xee\xf1\xf1\xf2\xe0\xed\xe0\xe2\xeb\xe8\xe2\xe0\xe5\xf2 invite_stats
local function tg_sync_invites(done_cb)
    if not settings.tg or not settings.tg.enabled then
        if done_cb then done_cb() end; return
    end
    local token = settings.tg.token or ''
    if token == '' then if done_cb then done_cb() end; return end
    if not tg_effil then
        local ok, lib = pcall(require, 'effil')
        if ok and lib then tg_effil = lib end
    end
    if not tg_effil then if done_cb then done_cb() end; return end

    local bot_username = settings.tg.bot_username or 'FamilyGrozzybot'

    lua_thread.create(function()
        local offset = 0
        local total_inv = 0
        local pages = 0
        local max_pages = 20  -- \xe7\xe0\xf9\xe8\xf2\xe0 \xee\xf2 \xe1\xe5\xf1\xea\xee\xed\xe5\xf7\xed\xee\xe3\xee \xf6\xe8\xea\xeb\xe0 (20 * 100 = 2000 \xf1\xee\xee\xe1\xf9\xe5\xed\xe8\xe9 \xec\xe0\xea\xf1)

        while pages < max_pages do
            pages = pages + 1
            local url = ('https://api.telegram.org/bot%s/getUpdates?offset=%d&limit=100'):format(token, offset) .. '&allowed_updates=%5B%22message%22%2C%22channel_post%22%5D'

            -- \xc7\xe0\xef\xf0\xee\xf1 \xe2 \xee\xf2\xe4\xe5\xeb\xfc\xed\xee\xec \xef\xee\xf2\xee\xea\xe5
            local t = tg_effil.thread(function(req_url)
                local ok_r, req = pcall(require, 'requests')
                if not ok_r then return '' end
                local ok_s, resp = pcall(req.request, 'GET', req_url, nil)
                if not ok_s or not resp then return '' end
                return tostring(resp.text or '')
            end)(url)

            -- \xc6\xe4\xb8\xec \xee\xf2\xe2\xe5\xf2\xe0
            local raw = ''
            local deadline = os.clock() + 15
            while os.clock() < deadline do
                local st, err = t:status()
                if err or st == 'canceled' then break end
                if st == 'completed' then
                    local ok_g, res = pcall(function() return t:get() end)
                    if ok_g and res then raw = res end
                    break
                end
                wait(100)
            end

            if raw == '' then break end

            -- \xcf\xe0\xf0\xf1\xe8\xec \xf1\xf2\xf0\xe0\xed\xe8\xf6\xf3
            local new_last = offset
            local found = false

            for update_id_s, from_block, msg_text in raw:gmatch('"update_id":(%d+).-"from":({.-}).-"text":"(.-)"') do
                local uid = tonumber(update_id_s) or 0
                found = true
                if uid > new_last then new_last = uid end

                local is_bot     = from_block:find('"is_bot":true') ~= nil
                local is_our_bot = from_block:find('"username":"' .. bot_username .. '"') ~= nil
                if not (is_bot and is_our_bot) then goto continue end

                local day, mon, year = msg_text:match('%[(%d+)%.(%d+)%.(%d+) |')
                if not day then goto continue end

                local decoded = decode_unicode_cp1251(msg_text)
                decoded = decoded:gsub('%[%d+%.%d+%.%d+ | %d+:%d+%]%s*', '')

                -- \xcf\xe0\xf0\xf1\xe8\xec \xe8\xed\xe2\xe0\xe9\xf2
                local inv_by = decoded:match('\xc8\xe3\xf0\xee\xea ([%a%d_]+) \xef\xf0\xe8\xe3\xeb\xe0\xf1\xe8\xeb [%a%d_]+ \xe2 \xf1\xe5\xec\xfc\xfe')
                if inv_by then
                    if not settings.invite_stats then settings.invite_stats = {} end
                    local st2 = settings.invite_stats[inv_by] or
                        {total=0, today=0, week=0, month=0, day_key='', week_key='', month_key=''}

                    local dk = day .. '.' .. mon .. '.' .. year
                    local mk = mon .. '.' .. year
                    local wk = tostring(math.floor((tonumber(day) or 1) / 7)) .. '.' .. mon .. '.' .. year

                    if st2.day_key   ~= dk then st2.today = 0; st2.day_key   = dk end
                    if st2.week_key  ~= wk then st2.week  = 0; st2.week_key  = wk end
                    if st2.month_key ~= mk then st2.month = 0; st2.month_key = mk end

                    st2.total = (st2.total or 0) + 1
                    st2.today = (st2.today or 0) + 1
                    st2.week  = (st2.week  or 0) + 1
                    st2.month = (st2.month or 0) + 1
                    settings.invite_stats[inv_by] = st2
                    total_inv = total_inv + 1
                end

                ::continue::
            end

            -- \xc5\xf1\xeb\xe8 \xed\xe5\xf2 \xed\xee\xe2\xfb\xf5 \xe4\xe0\xed\xed\xfb\xf5 \xe8\xeb\xe8 offset \xed\xe5 \xe8\xe7\xec\xe5\xed\xe8\xeb\xf1\xff \x97 \xea\xee\xed\xe5\xf6
            if not found or new_last <= offset then break end
            offset = new_last + 1
            wait(200)  -- \xed\xe5\xe1\xee\xeb\xfc\xf8\xe0\xff \xef\xe0\xf3\xe7\xe0 \xec\xe5\xe6\xe4\xf3 \xe7\xe0\xef\xf0\xee\xf1\xe0\xec\xe8
        end

        save_settings()
        if done_cb then done_cb(total_inv) end
    end)
end


-- ===== \xc7\xc0\xc3\xd0\xd3\xc7\xca\xc0 \xcf\xd0\xce\xcf\xd3\xd9\xc5\xcd\xcd\xdb\xd5 \xd1\xce\xc1\xdb\xd2\xc8\xc9 \xc8\xc7 \xd2\xc3 =====
-- \xc7\xe0\xef\xf0\xe0\xf8\xe8\xe2\xe0\xe5\xf2 \xf1\xee\xee\xe1\xf9\xe5\xed\xe8\xff \xe1\xee\xf2\xe0 \xe8\xe7 \xe3\xf0\xf3\xef\xef\xfb \xed\xe0\xf7\xe8\xed\xe0\xff \xf1 last_update_id
-- \xcf\xe0\xf0\xf1\xe8\xf2 [FH] \xf1\xee\xee\xe1\xf9\xe5\xed\xe8\xff \xe8 \xe4\xee\xe1\xe0\xe2\xeb\xff\xe5\xf2 \xe2 \xeb\xee\xe3 \xf1\xea\xf0\xe8\xef\xf2\xe0
tg_fetch_missed = function()
    if not settings.tg or not settings.tg.enabled then return end
    local token      = settings.tg.token      or ''
    local token2     = settings.tg.token2     or ''
    local channel_id = settings.tg.channel_id or ''
    if token == '' then
        sampAddChatMessage('[FH] TG: Токен 1 не заполнен', 0xFF4444); return
    end
    if channel_id == '' then
        sampAddChatMessage('[FH] TG: ID канала не заполнен', 0xFF6600); return
    end
    local read_token = (token2 ~= '' and token2 or token)
    if not tg_effil then
        local ok2, lib = pcall(require, 'effil')
        if ok2 and lib then tg_effil = lib end
    end
    if not tg_effil then
        sampAddChatMessage('[FH] TG: effil не загрузился', 0xFF4444); return
    end

    lua_thread.create(function()
        local offset = tonumber(settings.tg.last_update_offset) or 0
        sampAddChatMessage('[FH] TG: старт, offset=' .. offset, 0x00FFFF)

        if offset == 0 or offset < 1000000 then
            sampAddChatMessage('[FH] TG: синхронизация...', 0xFFAA00)
            local r0 = tg_http_get(('https://api.telegram.org/bot%s/getUpdates?limit=1&timeout=0&allowed_updates=%%5B%%22channel_post%%22%%5D'):format(read_token), 10)
            sampAddChatMessage('[FH] TG синхр: ' .. r0:sub(1,80), 0xAAAAAA)
            local uid0 = tonumber(r0:match('"update_id"%s*:%s*(%d+)')) or 0
            if uid0 > 0 then
                settings.tg.last_update_offset = uid0
                save_settings()
                sampAddChatMessage('[FH] TG: синхр OK, читаю с ' .. uid0, 0x00CC00)
                offset = uid0
            else
                settings.tg.last_update_offset = 1
                save_settings()
                sampAddChatMessage('[FH] TG: канал пуст', 0xFF6600)
                return
            end
        end

        local seen = {}
        local function do_log(msg, d, t)
            local clean = msg:gsub('%[%d+%.%d+%.%d+%s*|%s*%d+:%d+%]%s*', '')
                              :gsub('%[FH%]%s*', '')
                              :match('^%s*(.-)%s*$') or msg
            if clean == '' then return end
            local key = d .. t .. clean
            if seen[key] then return end
            seen[key] = true

            local ib, inew = clean:match('[Ии]грок ([%a%d_%.]+) пригласил ([%a%d_%.]+)')
            if ib and inew then
                flog('invite',{type='Приглашён',nick=inew,by=ib,date=d,time=t})
                if not settings.invite_stats then settings.invite_stats = {} end
                local _st = settings.invite_stats[ib] or {total=0,today=0,week=0,month=0,day_key='',week_key='',month_key=''}
                local _dm,_dy = d:match('%d+%.(%d+)%.(%d+)')
                local _mk = (_dm or '')..'.'..((_dy or ''))
                local _wk = tostring(math.floor((tonumber(d:match('^(%d+)')) or 1)/7))..'.'.. _mk
                if _st.day_key   ~= d   then _st.today=0; _st.day_key=d     end
                if _st.week_key  ~= _wk then _st.week=0;  _st.week_key=_wk  end
                if _st.month_key ~= _mk then _st.month=0; _st.month_key=_mk end
                _st.total=(_st.total or 0)+1; _st.today=(_st.today or 0)+1
                _st.week=(_st.week or 0)+1;   _st.month=(_st.month or 0)+1
                settings.invite_stats[ib] = _st
                save_settings(); return
            end

            local ib2, inew2 = clean:match('([%a%d_%.]+) Принял игрока ([%a%d_%.]+)')
            if ib2 and inew2 then
                flog('invite',{type='Приглашён',nick=inew2,by=ib2,date=d,time=t})
                if not settings.invite_stats then settings.invite_stats = {} end
                local _st = settings.invite_stats[ib2] or {total=0,today=0,week=0,month=0,day_key='',week_key='',month_key=''}
                local _dm,_dy = d:match('%d+%.(%d+)%.(%d+)')
                local _mk = (_dm or '')..'.'..((_dy or ''))
                local _wk = tostring(math.floor((tonumber(d:match('^(%d+)')) or 1)/7))..'.'.. _mk
                if _st.day_key   ~= d   then _st.today=0; _st.day_key=d     end
                if _st.week_key  ~= _wk then _st.week=0;  _st.week_key=_wk  end
                if _st.month_key ~= _mk then _st.month=0; _st.month_key=_mk end
                local cnt_msg = tonumber(clean:match('%(Инвайтов: (%d+)%)')) or 0
                if cnt_msg > (_st.total or 0) then _st.total = cnt_msg
                else _st.total = (_st.total or 0) + 1 end
                _st.today=(_st.today or 0)+1; _st.week=(_st.week or 0)+1; _st.month=(_st.month or 0)+1
                settings.invite_stats[ib2] = _st
                save_settings(); return
            end

            local n = clean:match('[Ии]грок ([%a%d_%.]+) вступил в семью')
            if n then flog('invite',{type='Вступил',nick=n,date=d,time=t}); return end

            n = clean:match('[Ии]грок ([%a%d_%.]+) самостоятельно покинул')
            if n then flog('invite',{type='Покинул',nick=n,date=d,time=t}); return end

            local b2, kd
            b2, kd = clean:match('[Ии]грок ([%a%d_%.]+) в оффлайне выгнал игрока ([%a%d_%.]+)')
            if not kd then b2, kd = clean:match('[Ии]грок ([%a%d_%.]+) выгнал игрока ([%a%d_%.]+)') end
            if not kd then b2, kd = clean:match('[Ии]грок ([%a%d_%.]+) исключил ([%a%d_%.]+)') end
            if kd then flog('invite',{type='Кик',nick=kd,by=b2 or '?',date=d,time=t}); return end

            local nn, lv = clean:match('[Ии]грок ([%a%d_%.]+) достиг (%d+) уровня')
            if not nn then nn = clean:match('[Ии]грок ([%a%d_%.]+) поднял уровень'); lv = '?' end
            if nn then flog('level',{nick=nn,lvl=lv or '?',date=d,time=t}); return end

            n = clean:match('[Ии]грок ([%a%d_%.]+) выполнил')
            if n then
                if not settings.quests_stats then settings.quests_stats = {} end
                settings.quests_stats[n] = (settings.quests_stats[n] or 0) + 1
                flog('quest',{nick=n,date=d,time=t})
                save_settings(); return
            end

            local b3   = clean:match('[Ии]грок ([%a%d_%.]+) выдал мут')
            local wh   = clean:match('мут игроку ([%a%d_%.]+)')
            local dur  = clean:match('на (%d+) мин')
            local reas = clean:match('Причина: (.+)')
            if wh then flog('mute',{nick=wh,by=b3 or '?',duration=dur or '?',reason=reas or '',date=d,time=t}); return end

            local who, amt = clean:match('[Ии]грок ([%a%d_%.]+) пополнил склад семьи на %$([%.%d]+)')
            if who then flog('bank',{nick=who,id='?',op='Пополнил',sum=amt,date=d,time=t}); return end

            local who2, amt2 = clean:match('[Ии]грок ([%a%d_%.]+) снял со склада семьи %$([%.%d]+)')
            if who2 then flog('bank',{nick=who2,id='?',op='Снял',sum=amt2,date=d,time=t}); return end

            local wco, tal, rep = clean:match('[Ии]грок ([%a%d_%.]+) обменял (%d+) талонов на %+?(%d+)')
            if wco then
                if not settings.talons_stats then settings.talons_stats = {} end
                settings.talons_stats[wco] = (settings.talons_stats[wco] or 0) + (tonumber(tal) or 0)
                flog('coins',{nick=wco,msg=tal..' тал -> +'..rep..' репы',date=d,time=t})
                save_settings(); return
            end

            local wco2 = clean:match('[Ии]грок ([%a%d_%.]+) сдал семейные монеты')
            if wco2 then
                if not settings.coins_stats then settings.coins_stats = {} end
                settings.coins_stats[wco2] = (settings.coins_stats[wco2] or 0) + 1
                flog('coins',{nick=wco2,msg='Сдал монеты',date=d,time=t})
                save_settings(); return
            end

            flog('news', {nick='[TG]', msg=clean, date=d, time=t})
        end

        local count, max_uid = 0, offset
        while true do
            local url = ('https://api.telegram.org/bot%s/getUpdates?offset=%d&limit=100&timeout=0&allowed_updates=%%5B%%22channel_post%%22%%5D'):format(read_token, max_uid)
            local raw = tg_http_get(url, 15)
            sampAddChatMessage('[FH] TG getUpdates: ' .. #raw .. 'б', 0xAAAAAA)
            if raw == '' or raw:find('"result":%[%]') then
                sampAddChatMessage('[FH] TG: пропущенных нет', 0xFFA500); break
            end
            local found_any, pos = false, 1
            while true do
                local uid_s = raw:find('"update_id"%s*:%s*%d+', pos)
                if not uid_s then break end
                local uid = tonumber(raw:match('"update_id"%s*:%s*(%d+)', uid_s)) or 0
                if uid + 1 > max_uid then max_uid = uid + 1 end
                found_any = true; pos = uid_s + 1
                local nxt = raw:find('"update_id"', pos) or #raw
                local block = raw:sub(uid_s, nxt)
                local txt = block:match('"text"%s*:%s*"([^"]*)"')
                if txt then
                    txt = decode_unicode_cp1251(txt)
                    txt = utf8_to_cp1251(txt)
                    txt = txt:gsub('\\n', ' '):gsub('\\r', '')
                    sampAddChatMessage('[FH] TG сооб: ' .. txt:sub(1,60), 0x00FF00)
                    -- FH_PING: синхронизация главенства (через TG, не /fam)
                    local fp_rank,fp_joined,fp_nick = txt:match('%[FH_PING:(%d+):(%d+):([%a%d_]+)%]')
                    if fp_nick then
                        fh_online[fp_nick] = {rank=tonumber(fp_rank) or 1,joined=tonumber(fp_joined) or 0,last_seen=os.time()}
                        count = count + 1
                    else
                        local d,m,y,hh,mm = txt:match('%[(%d+)%.(%d+)%.(%d+)%s*|%s*(%d+):(%d+)%]')
                        local id = d and (d..'.'..m..'.'..y) or os.date('%d.%m.%Y')
                        local it = hh and (hh..':'..mm..':00') or os.date('%H:%M:%S')
                        do_log(txt, id, it); count = count + 1
                    end
                end
            end
            if not found_any then break end
            wait(300)
        end
        settings.tg.last_update_offset = max_uid; save_settings()
        sampAddChatMessage('[FH] TG: загружено ' .. count .. ' соб.', count > 0 and 0x00CC00 or 0xFFA500)
    end)
end

-- ============================================================
-- РЕКОННЕКТ
-- ============================================================
local fh_reconnect_active = false
local fh_reconnect_delay_ms = 0

local function fh_do_reconnect()
    local sf = require 'sampfuncs'
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, sf.PACKET_DISCONNECTION_NOTIFICATION)
    raknetSendBitStreamEx(bs, sf.SYSTEM_PRIORITY, sf.RELIABLE, 0)
    raknetDeleteBitStream(bs)
    bs = raknetNewBitStream()
    raknetEmulPacketReceiveBitStream(sf.PACKET_CONNECTION_LOST, bs)
    raknetDeleteBitStream(bs)
end

local function fh_reconnect_delayed()
    if fh_reconnect_active then return end
    fh_reconnect_active = true
    local delay_ms = math.max(100, (settings.reconnect.delay or 5.0) * 1000)
    lua_thread.create(function()
        local ms = delay_ms
        while ms > 0 and fh_reconnect_active do
            printStringNow(string.format('Реконнект через %.1f сек...', ms/1000), 1000)
            wait(500)
            ms = ms - 500
        end
        if fh_reconnect_active then
            fh_do_reconnect()
        end
        fh_reconnect_active = false
    end)
end

-- Вспомогательные функции автологина (механизм из ConnectTools by Radare)
local function fh_readArzString(bs)
    local length  = raknetBitStreamReadInt16(bs)
    local encoded = raknetBitStreamReadInt8(bs)
    return (encoded ~= 0) and raknetBitStreamDecodeString(bs, length + encoded)
                           or  raknetBitStreamReadString(bs, length)
end

local function fh_showToolTip(text)
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 143)
    raknetBitStreamWriteBool(bs, true)
    raknetBitStreamWriteInt16(bs, #text)
    raknetBitStreamWriteInt8(bs, 0)
    raknetBitStreamWriteString(bs, text)
    raknetEmulPacketReceiveBitStream(220, bs)
    raknetDeleteBitStream(bs)
end

local function fh_sendFrontendClick(interfaceid, id, subid, json)
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 220)
    raknetBitStreamWriteInt8(bs, 63)
    raknetBitStreamWriteInt8(bs, interfaceid)
    raknetBitStreamWriteInt32(bs, id)
    raknetBitStreamWriteInt32(bs, subid)
    raknetBitStreamWriteInt16(bs, #json)
    raknetBitStreamWriteString(bs, json)
    raknetSendBitStreamEx(bs, 1, 7, 1)
    raknetDeleteBitStream(bs)
end

local function fh_send_auth()
    -- оставлено для совместимости, реальный автологин через onReceivePacket
end

local function fh_setup_autologin_handler()

    addEventHandler('onReceivePacket', function(id, bs)
        if id ~= 220 then return end
        raknetBitStreamIgnoreBits(bs, 8)
        if raknetBitStreamReadInt8(bs) ~= 84 then return end
        local interfaceid = raknetBitStreamReadInt8(bs)
        local subid       = raknetBitStreamReadInt8(bs)
        local json        = fh_readArzString(bs)
        if not settings.reconnect.auto_login then return end

        -- [FH DEBUG] логируем все интерфейсы пакета 220

        if interfaceid == 9 then
            if subid == 0 then
                lua_thread.create(function()
                    wait(300)
                    local login = settings.reconnect.login or ''
                    local pass  = settings.reconnect.password or ''
                    if login ~= '' and pass ~= '' then
                        fh_showToolTip('[FH] Автологин: ' .. login)
                        fh_sendFrontendClick(9, 0, 0, '{"password":"'..pass..'","username":"'..login..'"}')
                    end
                end)
            end
            if subid == 3 then
                if json == 'spawn' then
                    lua_thread.create(function()
                        wait(300)
                        fh_showToolTip('[FH] Автоспавн...')
                        fh_sendFrontendClick(9, 6, 0, '0')
                    end)
                end
                if json == 'user_already_game' then
                    lua_thread.create(function()
                        wait(2000)
                        local login = settings.reconnect.login or ''
                        local pass  = settings.reconnect.password or ''
                        if login ~= '' and pass ~= '' then
                            fh_showToolTip('[FH] Повтор логина: ' .. login)
                            fh_sendFrontendClick(9, 0, 0, '{"password":"'..pass..'","username":"'..login..'"}')
                        end
                    end)
                end
                if json == 'error' then
                    sampAddChatMessage('[FH] {ff4444}Неверный логин или пароль', 0xFF6600)
                end
            end
        end
    end)
end

function sampev.onConnectionBanned()
    if settings.reconnect.enabled and settings.reconnect.on_banned then
        sampAddChatMessage('[FH] Забан, реконнект...', 0xFF6600)
        fh_reconnect_delayed()
    end
end

function sampev.onConnectionClosed()
    if settings.reconnect.enabled and settings.reconnect.on_kicked then
        sampAddChatMessage('[FH] Соединение закрыто, реконнект...', 0xFF6600)
        fh_reconnect_delayed()
    end
end

function sampev.onConnectionRejected()
    if settings.reconnect.enabled and settings.reconnect.on_rejected then
        sampAddChatMessage('[FH] Ник занят/неверный, реконнект...', 0xFF6600)
        fh_reconnect_delayed()
    end
end

function sampev.onConnectionPasswordInvalid()
    if settings.reconnect.enabled and settings.reconnect.on_password then
        sampAddChatMessage('[FH] Неверный пароль сервера, реконнект...', 0xFF6600)
        fh_reconnect_delayed()
    end
end

function sampev.onConnectionRequestAccepted()
    fh_reconnect_active = false
    -- автологин через onReceivePacket
end


-- ===== FH MARKET v3 =====
fh_mkt_prices     = {}
fh_mkt_lavka      = {}
fh_mkt_log        = {}
fh_mkt_lavka_log  = {}
fh_mkt_last_update = nil
fh_mkt_lavka_ids  = {}
fh_mkt_lavka_sep  = {}
fh_mkt_lavka_page_id = -1
fh_mkt_cp_scanning  = false
fh_mkt_cp_page      = 0
fh_mkt_cp_prev_text = nil
fh_mkt_cp_go_idx    = nil
fh_mkt_lv_scanning  = false
fh_mkt_lv_done      = 0
fh_mkt_lv_total     = 0
fh_mkt_lv_cur_dialog = 3082
-- Авто-выкладка (продажа) и авто-покупка
fh_lv_autosell_running = false  -- флаг процесса авто-выкладки
fh_lv_autobuy_running  = false  -- флаг процесса авто-покупки
fh_lv_autosell_status  = ''     -- строка статуса
fh_lv_autobuy_status   = ''
fh_lv_trade_log        = {}     -- лог сделок
fh_lv_autosell_preset  = {}     -- [{name, price, qty}]
fh_lv_autobuy_preset   = {}     -- [{name, qty, max_price}]
fh_mkt_cp_deep_scanning  = false   -- новый глубокий скан
fh_mkt_cp_deep_page_idx  = 0      -- индекс товара на текущей странице
fh_mkt_cp_deep_cur_page_items = {}
fh_mkt_cp_deep_items    = {}      -- список товаров из списка
fh_mkt_cp_deep_idx      = 0       -- текущий индекс
fh_mkt_cp_deep_total    = 0       -- всего товаров
fh_mkt_cp_deep_done     = 0       -- обработано
fh_mkt_cp_deep_dlg_id   = nil     -- ID диалога списка
fh_mkt_cp_deep_state    = 'idle'  -- idle | list | item_detail
fh_mkt_cp_deep_item_dlg = nil     -- ID диалога деталей
fh_mkt_lavka_slot_w  = nil
fh_mkt_lavka_slot_h  = nil

-- ===== FH AUTO MARKET =====
fh_mkt_auto                = {}   -- {[name] = {price, date, hist=[{dt,price}], cp_hist=[{dt,qty,price}]}}
fh_mkt_auto_last_upd       = nil
fh_mkt_auto_scanning       = false
fh_mkt_auto_page           = 0
fh_mkt_auto_prev_text      = nil
fh_mkt_auto_go_idx         = nil
fh_mkt_auto_deep_scanning  = false
fh_mkt_auto_deep_go_idx    = nil
fh_mkt_auto_deep_done      = 0

local function fh_mkt_path(file)
    return getWorkingDirectory():gsub('\\\\','/') .. '/FH_' .. file
end

local function fh_mkt_save()
    for _,p in ipairs({
        {'mkt_prices.json',    fh_mkt_prices},
        {'mkt_log.json',       fh_mkt_log},
        {'mkt_lavka.json',     fh_mkt_lavka},
        {'mkt_lavka_log.json', fh_mkt_lavka_log},
        {'mkt_auto.json',      fh_mkt_auto},
    }) do
        local ok,j = pcall(encodeJson, p[2])
        if ok then local f=io.open(fh_mkt_path(p[1]),'w'); if f then f:write(j); f:close() end end
    end
    -- Сохраняем дату обновления
    if fh_mkt_last_update then
        local f=io.open(fh_mkt_path('mkt_last_update.txt'),'w')
        if f then f:write(fh_mkt_last_update); f:close() end
    end
end

local function fh_mkt_load()
    for _,p in ipairs({
        {'mkt_prices.json',    'fh_mkt_prices'},
        {'mkt_log.json',       'fh_mkt_log'},
        {'mkt_lavka.json',     'fh_mkt_lavka'},
        {'mkt_lavka_log.json', 'fh_mkt_lavka_log'},
        {'mkt_auto.json',      'fh_mkt_auto'},
    }) do
        local f=io.open(fh_mkt_path(p[1]),'r')
        if f then local ok,d=pcall(decodeJson,f:read('*a')); f:close()
            if ok and type(d)=='table' then _G[p[2]]=d end end
    end
    -- Загружаем дату обновления
    local fu=io.open(fh_mkt_path('mkt_last_update.txt'),'r')
    if fu then fh_mkt_last_update=fu:read('*a'); fu:close() end
    -- Чистим старые ключи ##aN из fh_mkt_auto (легаси от САМР tablist)
    local clean_auto = {}
    for k,v in pairs(fh_mkt_auto) do
        if type(k) ~= 'string' or type(v) ~= 'table' then goto continue_clean end
        local ck = k:gsub('##%a%d+$','')
        if ck ~= '' then
            if clean_auto[ck] then
                -- мержим повторые ключи
                local ex = clean_auto[ck]
                ex.s_avg = v.s_avg or ex.s_avg
                ex.s_min = (ex.s_min and v.s_min) and math.min(ex.s_min,v.s_min) or ex.s_min or v.s_min
                ex.s_max = (ex.s_max and v.s_max) and math.max(ex.s_max,v.s_max) or ex.s_max or v.s_max
                ex.date = ex.date or v.date
            else
                clean_auto[ck] = v
            end
        end
        ::continue_clean::
    end
    fh_mkt_auto = clean_auto
end

-- MCR-style обновление цен (totalPrice/totalCount)
local function fh_mkt_upd(e, price, qty, side)
    qty = qty or 1
    if side == 'buy' then
        e.b_totalP=(e.b_totalP or 0)+price*qty; e.b_totalC=(e.b_totalC or 0)+qty
        e.b_avg=math.floor(e.b_totalP/e.b_totalC)
        e.b_min=e.b_min and math.min(e.b_min,price) or price
        e.b_max=e.b_max and math.max(e.b_max,price) or price
        e.b_last=price; e.b_scans=(e.b_scans or 0)+1
    else
        e.s_totalP=(e.s_totalP or 0)+price*qty; e.s_totalC=(e.s_totalC or 0)+qty
        e.s_avg=math.floor(e.s_totalP/e.s_totalC)
        e.s_min=e.s_min and math.min(e.s_min,price) or price
        e.s_max=e.s_max and math.max(e.s_max,price) or price
        e.s_last=price; e.s_scans=(e.s_scans or 0)+1
    end
    e.date=os.date("%d.%m.%Y %H:%M"); return e
end

local function fh_mkt_record(item, qty, price, op, partner, is_vc)
    if not item or not price or price<=0 then return end
    local dt=os.date("%d.%m %H:%M"); qty=qty or 1
    local side=(op=='buy') and 'buy' or 'sell'
    table.insert(fh_mkt_log,{dt=dt,item=item,qty=qty,price=price,op=op,partner=partner or "",vc=is_vc})
    while #fh_mkt_log>2000 do table.remove(fh_mkt_log,1) end
    fh_mkt_prices[item]=fh_mkt_upd(fh_mkt_prices[item] or {},price,qty,side)
    fh_mkt_last_update=dt
end

-- Парсер диалога чекпоинта id=15073 (format: "Товар\t$ЖХЕНА" или "VC$ЖХЕНА")
-- Парсер детального диалога товара на чекпоинте
-- Возвращает { name, history={dt,buyer,price,qty,...} } или nil

local function fh_find_listitem(text, needle)
    local iline = 0
    for ln in text:gmatch('[^\n]+') do
        iline = iline + 1
        if iline > 1 and ln:find(needle, 1, true) then
            return iline - 2
        end
    end
    return nil
end

local function fh_mkt_parse_cp_detail(text, title_text)
    if not text or text == "" then return nil end
    -- Имя из заголовка: "Продажа товара 'Семейный талон' за последние 30 дней"
    local item_name = ""
    if title_text then
        local tn = title_text:gsub("{%x+}",""):match("^%s*(.-)%s*$") or ""
        local nm = tn:match("'(.+)'") or tn:match('"(.+)"')
        if nm and nm ~= "" then item_name = nm
        elseif not tn:find("Продажа") and not tn:find("последние") and tn ~= "" then item_name = tn
        end
    end
    if item_name == "" then return nil end
    local history = {}
    for line in text:gmatch("[^\n]+") do
        -- Убираем цветовые коды, trim
        local clean = line:gsub("{%x%x%x%x%x%x}",""):match("^%s*(.-)%s*$") or ""
        if clean ~= "" then
            local dt_s, qty_s, price_s
            -- Вариант 1: tab-разделитель: "2026-03-10	164	$40.582"
            dt_s, qty_s, price_s = clean:match("^(%d%d%d%d%-%d%d%-%d%d)%s*%t%s*(%d+)%s*%t%s*%$?([%d%.,]+)")
            -- Вариант 2: несколько пробелов: "2026-03-10  164  $40.582"
            if not dt_s then
                dt_s, qty_s, price_s = clean:match("^(%d%d%d%d%-%d%d%-%d%d)%s+(%d+)%s+%$?([%d%.,]+)")
            end
            -- Вариант 3: пайп: "2026-03-10 | 164 | $40.582"
            if not dt_s then
                dt_s, qty_s, price_s = clean:match("^(%d%d%d%d%-%d%d%-%d%d)%s*|%s*(%d+)%s*|%s*%$?([%d%.,]+)")
            end
            if dt_s and qty_s and price_s then
                -- Цена: убираем пробелы и запятые; точки - разделители тысяч (убираем все)
                local pc = price_s:gsub("%s",""):gsub(",",""):gsub("%.","")
                local price = tonumber(pc)
                local qty = tonumber(qty_s) or 0
                if price and price > 0 then
                    table.insert(history, {dt=dt_s, qty=qty, price=price})
                end
            end
        end
    end
    return { name = item_name, history = history }
end

-- Парсер старого формата (список цен) -- сохранен для обратной совместимости
local function fh_mkt_parse_cp(text)
    if not text or text=="" then return 0 end
    local count=0; local iline=0
    for raw in text:gmatch("[^\n]+") do
        iline=iline+1
        if iline>3 then
            local clean=raw:gsub("{%x+}","")
            local is_vc=clean:find("[Vv][Cc]%$") ~= nil
            local name,price_s
            if is_vc then name,price_s=clean:match("^(.-)	[Vv][Cc]%$?([%d%.,]+)")
            else name,price_s=clean:match("^(.-)	%$?([%d%.,]+)") end
            name=name and name:match("^%s*(.-)%s*$") or ""
            local price=price_s and tonumber((price_s:gsub("[,.]",""))) or nil
            if name~="" and price and price>10 then
                local e=fh_mkt_prices[name] or {}
                if is_vc then
                    if not e.vc_st or (os.time()-e.vc_st)>60 then e.vc_st=os.time(); e.vc_sp=nil end
                    if e.vc_sp then
                        e.vc_min=e.vc_min and math.min(e.vc_min,price) or math.min(e.vc_sp,price)
                        e.vc_max=e.vc_max and math.max(e.vc_max,price) or math.max(e.vc_sp,price)
                    else e.vc_sp=price end
                    e.vc_totalP=(e.vc_totalP or 0)+price; e.vc_totalC=(e.vc_totalC or 0)+1
                    e.vc_avg=math.floor(e.vc_totalP/e.vc_totalC)
                    e.vc_min=e.vc_min or price; e.vc_max=e.vc_max or price
                else
                    if not e.cp_st or (os.time()-e.cp_st)>60 then e.cp_st=os.time(); e.cp_sp=nil end
                    if e.cp_sp then
                        e.s_min=e.s_min and math.min(e.s_min,price) or math.min(e.cp_sp,price)
                        e.s_max=e.s_max and math.max(e.s_max,price) or math.max(e.cp_sp,price)
                    else e.cp_sp=price end
                    e.s_totalP=(e.s_totalP or 0)+price; e.s_totalC=(e.s_totalC or 0)+1
                    e.s_avg=math.floor(e.s_totalP/e.s_totalC)
                    e.s_min=e.s_min or price; e.s_max=e.s_max or price
                end
                e.date=os.date("%d.%m.%Y"); fh_mkt_prices[name]=e; count=count+1
            end
        end
    end
    if count>0 then fh_mkt_last_update=os.date("%d.%m %H:%M") end
    return count
end

-- ===== FH AUTO MARKET: парсер диалога авторынка =====
-- Формат строк: "Товар  	$ЦЕНА" (Tab-разделитель)
local function fh_mkt_parse_auto(text)
    if not text or text == "" then return 0 end
    local count = 0; local iline = 0
    for raw in text:gmatch("[^\n]+") do
        iline = iline + 1
        if iline > 1 then
            local clean = raw:gsub("{%x+}", "")
            local name, price_s = clean:match("^(.-)\t%$?([%d%.,]+)")
            if not name then
                name, price_s = clean:match("^(.-)%s{2,}%$?([%d%.,]+)")
            end
            name = name and name:match("^%s*(.-)%s*$") or ""
            -- Убираем суффикс ##aN (САМР добавляет для уникальности в tablist)
            name = name:gsub('##%a%d+$','')
            local price = price_s and tonumber((price_s:gsub("[,.]", ""))) or nil
            if name ~= "" and price and price > 1000 then
                local e = fh_mkt_auto[name] or {}
                -- Обновляем цену
                if not e.cp_st or (os.time() - (e.cp_st or 0)) > 60 then
                    e.cp_st = os.time(); e.cp_sp = nil
                end
                if e.cp_sp then
                    e.s_min = e.s_min and math.min(e.s_min, price) or math.min(e.cp_sp, price)
                    e.s_max = e.s_max and math.max(e.s_max, price) or math.max(e.cp_sp, price)
                else e.cp_sp = price end
                e.s_totalP = (e.s_totalP or 0) + price
                e.s_totalC = (e.s_totalC or 0) + 1
                e.s_avg = math.floor(e.s_totalP / e.s_totalC)
                e.s_min = e.s_min or price; e.s_max = e.s_max or price
                -- История цен
                if not e.hist then e.hist = {} end
                local dt_now = os.date("%d.%m")
                if not e.hist[1] or e.hist[1].dt ~= dt_now then
                    table.insert(e.hist, 1, {dt = dt_now, price = price})
                    while #e.hist > 30 do table.remove(e.hist) end
                else
                    e.hist[1].price = price
                end
                e.date = os.date("%d.%m.%Y"); fh_mkt_auto[name] = e; count = count + 1
            end
        end
    end
    if count > 0 then fh_mkt_auto_last_upd = os.date("%d.%m %H:%M") end
    return count
end

-- Парсер списка авто из таблицы (один элемент в списке = один listItem)
local function fh_mkt_parse_auto_list(text)
    local items = {}
    if not text or text == '' then return items end
    local iline = 0; local list_idx = -1
    for raw in text:gmatch('[^\n]+') do
        iline = iline + 1
        if iline == 1 then
            -- Червая строка = заголовок таблицы (не listItem)
        else
            list_idx = list_idx + 1
            local clean = raw:gsub('{%x+}',''):match('^%s*(.-)%s*$') or ''
            local skip = clean == '' or
                clean:find('^Поиск по') or
                clean:find('^Следующая страница') or
                clean:find('^Предыдущая страница') or
                clean:find('Сканировать все авто') or
                clean:find('Углублённый скан')
            if not skip and clean ~= '' then
                local nm = clean:match('^(.-)%s*	') or clean:match('^(.-)%s*%$') or clean
                nm = nm:gsub('##%a%d+$',''):match('^%s*(.-)%s*$') or ''
                if nm ~= '' and #nm > 1 then
                    table.insert(items, {name=nm, idx=list_idx})
                end
            end
        end
    end
    return items
end

-- Парсер детального диалога авто (экран с историей цен по дням)
-- По аналогии с fh_mkt_parse_cp_detail
local function fh_mkt_parse_auto_detail(text, title_text)
    if not text or text == '' then return nil end
    local item_name = ''
    if title_text then
        local tn = title_text:gsub('{%x+}',''):match('^%s*(.-)%s*$') or ''
        local nm = tn:match("'(.+)'") or tn:match('"(.+)"')
        if nm and nm ~= '' then item_name = nm
        elseif tn ~= '' and not tn:find('Продажа') and not tn:find('последние') then
            item_name = tn
        end
    end
    if item_name == '' then return nil end
    item_name = item_name:gsub('##%a%d+$','')
    local history = {}
    for line in text:gmatch('[^\n]+') do
        local clean = line:gsub('{%x%x%x%x%x%x}',''):match('^%s*(.-)%s*$') or ''
        if clean ~= '' then
            local dt_s, qty_s, price_s
            dt_s, qty_s, price_s = clean:match('^(%d%d%d%d%-%d%d%-%d%d)%s*	%s*(%d+)%s*	%s*%$?([%d%.,]+)')
            if not dt_s then
                dt_s, qty_s, price_s = clean:match('^(%d%d%d%d%-%d%d%-%d%d)%s+(%d+)%s+%$?([%d%.,]+)')
            end
            if not dt_s then
                dt_s, qty_s, price_s = clean:match('^(%d%d%d%d%-%d%d%-%d%d)%s*|%s*(%d+)%s*|%s*%$?([%d%.,]+)')
            end
            -- Авторынок может не содержать qty (только дату и цену)
            if not dt_s then
                local p2
                dt_s, p2 = clean:match('^(%d%d%d%d%-%d%d%-%d%d)%s*	%s*%$?([%d%.,]+)')
                if dt_s then qty_s = '1'; price_s = p2 end
            end
            if dt_s and price_s then
                local pc = price_s:gsub('%s',''):gsub(',',''):gsub('%.', '')
                local price = tonumber(pc)
                local qty = tonumber(qty_s) or 1
                if price and price > 0 then
                    table.insert(history, {dt=dt_s, qty=qty, price=price})
                end
            end
        end
    end
    return { name=item_name, history=history }
end

-- Сохранить детальную статистику авто и cp_hist
local function fh_mkt_save_auto_detail(item_name, history)
    if not item_name or item_name == '' or not history or #history == 0 then return end
    local dt = os.date('%d.%m %H:%M')
    local e = fh_mkt_auto[item_name] or {}
    e.cp_hist = history
    local total_pxq, total_q = 0, 0
    local s_min, s_max
    for _, h in ipairs(history) do
        if h.price and h.price > 0 then
            local q = h.qty or 1
            total_pxq = total_pxq + h.price * q; total_q = total_q + q
            if not s_min or h.price < s_min then s_min = h.price end
            if not s_max or h.price > s_max then s_max = h.price end
        end
    end
    if total_q > 0 then
        e.s_avg = math.floor(total_pxq/total_q)
        e.s_min = s_min; e.s_max = s_max
        e.s_totalC = total_q; e.date = dt
    end
    fh_mkt_auto[item_name] = e
    fh_mkt_auto_last_upd = dt
end


-- Сохранить детальную маркет статистику товара
local function fh_mkt_save_cp_detail(item_name, history)
    if not item_name or item_name == "" or not history then return end
    local dt = os.date("%d.%m %H:%M")
    local e = fh_mkt_prices[item_name] or {}
    e.cp_hist = history
    local total_pxq, total_q = 0, 0
    local s_min, s_max
    for _, h in ipairs(history) do
        if h.price and h.price > 0 then
            local q = h.qty or 1
            total_pxq = total_pxq + h.price * q; total_q = total_q + q
            if not s_min or h.price < s_min then s_min = h.price end
            if not s_max or h.price > s_max then s_max = h.price end
        end
    end
    if total_q > 0 then
        e.s_avg=math.floor(total_pxq/total_q); e.s_min=s_min; e.s_max=s_max
        e.s_totalC=total_q; e.date=dt
        fh_mkt_prices[item_name]=e; fh_mkt_last_update=dt
    end
end

-- Парсим список товаров из формата таблицы
-- Строка 1 = заголовок (не listItem), строка 2 = listItem 0
local function fh_mkt_parse_cp_list(text, style)
    local items = {}
    if not text or text == "" then return items end
    local iline = 0; local list_idx = -1
    for raw in text:gmatch("[^\n]+") do
        iline = iline + 1
        if iline == 1 then
            -- заголовок — не listItem
        else
            list_idx = list_idx + 1
            local clean = raw:gsub("{%x+}",""):match("^%s*(.-)%s*$") or ""
            local skip = clean=="" or clean:find("^Поиск по") or clean:find("^Следующая страница") or
                clean:find("^Предыдущая страница") or clean:find("^>>") or clean:find("^<<") or
                clean:find("Проанализировать все цены") or clean:find("Углублённый скан")
            if not skip and clean ~= "" then
                local nm = clean:match("^(.-)%s*\t") or clean:match("^(.-)%s*%$") or clean
                nm = nm:match("^%s*(.-)%s*$") or ""
                if nm ~= "" and #nm > 1 then table.insert(items, {name=nm, idx=list_idx}) end
            end
        end
    end
    return items
end

-- Рун глубокого скана (новый)
-- fh_mkt_run_cp_deep_scan is now triggered from dialog injection below


local function fh_mkt_parse_lavka(text, title_clean)
    if not text or text=="" then return nil end
    local name=""
    for line in text:gmatch("[^\n]+") do
        local n=line:match(":%s*{[^}]+}(.-)%s*{[^}]+}")
        if not n or n=="" then n=line:match("{[^}]+}(.-)%s*{[^}]+}") end
        if n and n~="" then name=n; break end
    end
    local price_s=""
    for line in text:gmatch("[^\n]+") do
        local p=line:match("Стоимость:.-$([%d,%.]+)")
        if not p then p=line:match("Стоимость:[^\n]-(%d[%d,%.]+)") end
        if p then price_s=p; break end
    end
    local qty_s="1"
    for line in text:gmatch("[^\n]+") do
        local q=line:match("В%s*наличии:%s*(.-)%s*шт")
        if not q then q=line:match("Игрок%s*покупает:%s*(.-)%s*шт") end
        if q then qty_s=q; break end
    end
    local price=tonumber(price_s:gsub("[,.]","")); local qty=tonumber(qty_s) or 1
    if name=="" or not price or price<=0 then return nil end
    local op=(title_clean and title_clean:find("Покупка")) and "sell" or "buy"
    return {name=name,price=price,qty=qty,op=op}
end

local function fh_mkt_lavka_record(name,price,qty,op)
    if not name or name=="" or not price or price<=0 then return end
    local dt=os.date("%d.%m %H:%M")
    fh_mkt_lavka[name]=fh_mkt_upd(fh_mkt_lavka[name] or {},price,qty or 1,op)
    table.insert(fh_mkt_lavka_log,{dt=dt,item=name,price=price,qty=qty or 1,op=op})
    while #fh_mkt_lavka_log>1000 do table.remove(fh_mkt_lavka_log,1) end
end


-- ================================================================
-- АВТО-ВЫКЛАДКА / АВТО-ПОКУПКА
-- ================================================================

local function fh_lv_log_trade(item, price, qty, op, status)
    local entry = {
        dt     = os.date('%d.%m %H:%M'),
        item   = item,
        price  = price,
        qty    = qty,
        op     = op,     -- 'sell' | 'buy'
        status = status  -- 'ok' | 'skip' | 'error'
    }
    table.insert(fh_lv_trade_log, 1, entry)
    while #fh_lv_trade_log > 500 do table.remove(fh_lv_trade_log) end
end

-- Авто-выкладка (пресет = fh_lv_autosell_preset)
-- Сценарий: /mm в чат, открылась лавка (textdraw IDs заполнены)
-- Перебираем слоты, подтверждаем стоимость + кол-во
-- Диалог 25668: Продажа товара - btn1=Ручной ввод, btn2=Закрыть
-- btn1 = listItem: 0=Цена, 1=Кол-во
-- После выбора Продать - появляется input dialog (ввод числа)

local function fh_run_autosell()
    if fh_lv_autosell_running or fh_lv_autobuy_running then return end
    if #fh_lv_autosell_preset == 0 then
        sampAddChatMessage('[FH Авто] {ff4444}Список авто-выкладки пуст. Добавьте товары.', 0xFFFFFF)
        return
    end
    fh_lv_autosell_running = true
    fh_lv_autosell_status  = 'Запуск...'

    lua_thread.create(function()
        -- 1. Открыть лавку если нет текстдров
        if #fh_mkt_lavka_ids == 0 then
            fh_lv_autosell_status = 'Открываю лавку...'
            sampSendChat('/mm')
            local w = 0
            while #fh_mkt_lavka_ids == 0 and w < 600 do wait(10); w=w+1 end
            if #fh_mkt_lavka_ids == 0 then
                sampAddChatMessage('[FH Авто] {ff4444}Лавка не открылась. Подойдите к прилавке!', 0xFFFFFF)
                fh_lv_autosell_running = false
                fh_lv_autosell_status = 'Лавка не доступна'
                return
            end
            wait(400)
        end

        local done, total = 0, #fh_lv_autosell_preset
        sampAddChatMessage('[FH Авто] {ffaa00}Авто-выкладка стартует: '..total..' позиций', 0xFFFFFF)

        for pi, preset_item in ipairs(fh_lv_autosell_preset) do
            if not fh_lv_autosell_running then break end
            fh_lv_autosell_status = preset_item.name..' ('..pi..'/'..total..')'

            -- Опрос строк лавки чтобы найти слот с товаром
            local found_slot = false
            for _, td_id in ipairs(fh_mkt_lavka_ids) do
                if not fh_lv_autosell_running then break end

                -- закрыть предыдущий диалог
                if sampIsDialogActive() then
                    sampSendDialogResponse(sampGetCurrentDialogId(),0,0,'')
                    wait(100)
                end

                sampSendClickTextdraw(td_id)
                wait(500)

                -- Цикл ожидания диалога 25668 с названием товара
                local wd, dlg_id, dlg_txt = 0, nil, nil
                while wd < 2000 do
                    wait(80); wd = wd + 80
                    if sampIsDialogActive() then
                        local cid = sampGetCurrentDialogId()
                        local ctxt = sampGetDialogText() or ''
                        if cid == 25668 then
                            local slot_name = ctxt:match('{57FF6B}(.-){%x+}') or ''
                            if slot_name == '' then
                                for line in ctxt:gmatch('[^\n]+') do
                                    local n = line:gsub('{%x+}',''):match('^%s*(.-)%s*$')
                                    if n and n ~= '' and not n:find(':') then slot_name=n; break end
                                end
                            end
                            if slot_name:lower() == preset_item.name:lower() then
                                dlg_id = cid; dlg_txt = ctxt; break
                            else
                                -- Чужой товар - закрываем
                                sampSendDialogResponse(cid,0,0,'')
                                wait(80)
                            end
                        elseif cid ~= fh_mkt_lv_cur_dialog then
                            -- Другой диалог - закрываем
                            sampSendDialogResponse(cid,0,0,'')
                            wait(80)
                        end
                    end
                end

                if dlg_id then
                    found_slot = true
                    -- Цена (listItem=0) или Кол-во (listItem=1) зависит от типа схемы
                    -- Основной способ: btn1 + listItem=0 (Цена) или =1 (Кол-во)
                    -- Затем появляется input диалог (стиль 1=edit)

                    -- Режим: сначала устанавливаем цену
                    sampSendDialogResponse(dlg_id, 1, 0, '')  -- Выбрать Цена
                    wait(400)

                    -- Ждём input-диалог для цены
                    local wi = 0
                    while wi < 2000 do
                        wait(80); wi = wi + 80
                        if sampIsDialogActive() then
                            local inp_id = sampGetCurrentDialogId()
                            sampSendDialogResponse(inp_id, 1, 0, tostring(preset_item.price))
                            wait(300)
                            break
                        end
                    end

                    -- Теперь устанавливаем количество (если задано qty > 1)
                    if (preset_item.qty or 1) > 1 then
                        -- Тот же слот снова, listItem=1=Кол-во
                        wait(200)
                        if sampIsDialogActive() then
                            sampSendDialogResponse(sampGetCurrentDialogId(),0,0,'')
                            wait(100)
                        end
                        sampSendClickTextdraw(td_id)
                        wait(500)

                        local wd2=0
                        while wd2<2000 do
                            wait(80); wd2=wd2+80
                            if sampIsDialogActive() and sampGetCurrentDialogId()==25668 then
                                sampSendDialogResponse(sampGetCurrentDialogId(),1,1,'')
                                wait(400)
                                if sampIsDialogActive() then
                                    sampSendDialogResponse(sampGetCurrentDialogId(),1,0,tostring(preset_item.qty))
                                    wait(300)
                                end
                                break
                            end
                        end
                    end

                    fh_lv_log_trade(preset_item.name, preset_item.price, preset_item.qty or 1, 'sell', 'ok')
                    done = done + 1
                    wait(200)
                    break  -- слот найдµн, переходим к следующему пресет-итему
                end
            end

            if not found_slot then
                sampAddChatMessage('[FH Авто] {ffaa00}Слот не найдµн: '..preset_item.name, 0xFFFFFF)
                fh_lv_log_trade(preset_item.name, preset_item.price or 0, preset_item.qty or 1, 'sell', 'skip')
            end
        end

        -- Закрыть лавку
        if sampIsDialogActive() then
            sampSendDialogResponse(sampGetCurrentDialogId(),0,0,'')
            wait(100)
        end
        sampSendClickTextdraw(65535)

        fh_lv_autosell_running = false
        fh_lv_autosell_status  = 'Завершµно: '..done..'/'..total
        sampAddChatMessage('[FH Авто] {00cc00}Авто-выкладка завершена. Успешно: '..done..'/'..total, 0xFFFFFF)
    end)
end

-- Авто-покупка (пресет = fh_lv_autobuy_preset)
-- Сценарий: открываем слот из fh_mkt_lavka, проверяем цену, покупаем нацельное кол-во
local function fh_run_autobuy()
    if fh_lv_autosell_running or fh_lv_autobuy_running then return end
    if #fh_lv_autobuy_preset == 0 then
        sampAddChatMessage('[FH Авто] {ff4444}Список авто-покупки пуст. Добавьте товары.', 0xFFFFFF)
        return
    end
    fh_lv_autobuy_running = true
    fh_lv_autobuy_status  = 'Запуск...'

    lua_thread.create(function()
        if #fh_mkt_lavka_ids == 0 then
            fh_lv_autobuy_status = 'Открываю лавку...'
            sampSendChat('/mm')
            local w=0
            while #fh_mkt_lavka_ids==0 and w<600 do wait(10); w=w+1 end
            if #fh_mkt_lavka_ids==0 then
                sampAddChatMessage('[FH Авто] {ff4444}Лавка не открылась!', 0xFFFFFF)
                fh_lv_autobuy_running=false
                fh_lv_autobuy_status='Лавка не доступна'
                return
            end
            wait(400)
        end

        local done, total = 0, #fh_lv_autobuy_preset
        sampAddChatMessage('[FH Авто] {ffaa00}Авто-покупка стартует: '..total..' позиций', 0xFFFFFF)

        for pi, buy_item in ipairs(fh_lv_autobuy_preset) do
            if not fh_lv_autobuy_running then break end
            fh_lv_autobuy_status = buy_item.name..' ('..pi..'/'..total..')'

            local found = false
            for _, td_id in ipairs(fh_mkt_lavka_ids) do
                if not fh_lv_autobuy_running then break end
                if sampIsDialogActive() then
                    sampSendDialogResponse(sampGetCurrentDialogId(),0,0,'')
                    wait(100)
                end
                sampSendClickTextdraw(td_id)
                wait(500)

                local wd, dlg_id, dlg_price = 0, nil, nil
                while wd<2000 do
                    wait(80); wd=wd+80
                    if sampIsDialogActive() then
                        local cid = sampGetCurrentDialogId()
                        local ctxt = sampGetDialogText() or ''
                        if cid==25668 then
                            local slot_name = ctxt:match('{57FF6B}(.-){%x+}') or ''
                            if slot_name=='' then
                                for line in ctxt:gmatch('[^\n]+') do
                                    local n=line:gsub('{%x+}',''):match('^%s*(.-)%s*$')
                                    if n and n~='' and not n:find(':') then slot_name=n; break end
                                end
                            end
                            if slot_name:lower()==buy_item.name:lower() then
                                -- Парсируем цену
                                for line in ctxt:gmatch('[^\n]+') do
                                    local p=line:match('Стоимость:%s*%$([%d,%.]+)')
                                         or line:match('Стоимость:%s*([%d,%.]+)')
                                    if p then dlg_price=tonumber(p:gsub('[,.]','')); break end
                                end
                                dlg_id=cid; break
                            else
                                sampSendDialogResponse(cid,0,0,'')
                                wait(80)
                            end
                        elseif cid~=fh_mkt_lv_cur_dialog then
                            sampSendDialogResponse(cid,0,0,'')
                            wait(80)
                        end
                    end
                end

                if dlg_id then
                    -- Чек максимальной цены
                    if buy_item.max_price and buy_item.max_price > 0 and dlg_price and dlg_price > buy_item.max_price then
                        sampAddChatMessage('[FH Авто] {ffaa00}Пропуск: '..buy_item.name..' цена $'..fh_num_fmt(dlg_price)..' > макс $'..fh_num_fmt(buy_item.max_price), 0xFFFFFF)
                        fh_lv_log_trade(buy_item.name, dlg_price or 0, buy_item.qty or 1, 'buy', 'skip')
                        sampSendDialogResponse(dlg_id,0,0,'')
                        wait(100)
                        found=true; break
                    end
                    -- Нажимаем Купить (btn2 или listItem зависит от схемы диалога)
                    -- Пробуем listItem=-1 (кнопка Магазина - btn1=Купить)
                    sampSendDialogResponse(dlg_id,1,2,'')  -- listItem 2 = Покупить
                    wait(400)

                    -- Если появился input для кол-ва
                    if sampIsDialogActive() then
                        local inp = sampGetCurrentDialogId()
                        sampSendDialogResponse(inp,1,0,tostring(buy_item.qty or 1))
                        wait(300)
                    end

                    fh_lv_log_trade(buy_item.name, dlg_price or 0, buy_item.qty or 1, 'buy', 'ok')
                    done=done+1
                    found=true
                    wait(200)
                    break
                end
            end

            if not found then
                fh_lv_log_trade(buy_item.name, 0, buy_item.qty or 1, 'buy', 'skip')
                sampAddChatMessage('[FH Авто] {ffaa00}Пропуск покупки: '..buy_item.name, 0xFFFFFF)
            end
        end

        if sampIsDialogActive() then
            sampSendDialogResponse(sampGetCurrentDialogId(),0,0,'')
            wait(100)
        end
        sampSendClickTextdraw(65535)

        fh_lv_autobuy_running=false
        fh_lv_autobuy_status='Завершµно: '..done..'/'..total
        sampAddChatMessage('[FH Авто] {00cc00}Авто-покупка завершена. Успешно: '..done..'/'..total, 0xFFFFFF)
    end)
end

local function fh_mkt_run_lavka_scan()
    if fh_mkt_lv_scanning then return end
    fh_mkt_lv_scanning = true
    lua_thread.create(function()
        -- Если лавка ещё не открыта (нет textdraw ID) — открываем через /mm
        if #fh_mkt_lavka_ids == 0 then
            sampAddChatMessage('[FH Market] {ffaa00}Открываю лавку...', 0xFFFFFF)
            fh_mkt_lavka_ids = {}; fh_mkt_lavka_sep = {}
            fh_mkt_lavka_slot_w = nil; fh_mkt_lavka_slot_h = nil
            sampSendChat('/mm')
            -- Циклически ждём появления слотов (max 5с)
            local waited = 0
            while #fh_mkt_lavka_ids == 0 and waited < 500 do
                wait(10); waited = waited + 1
            end
            if #fh_mkt_lavka_ids == 0 then
                sampAddChatMessage('[FH Market] {ff4444}Лавка не открылась. Подойдите к прилавке и повторите.', 0xFFFFFF)
                fh_mkt_lv_scanning = false; return
            end
            wait(500) -- доп. задержка после открытия
        end
        local ids_snap = {}
        for _,v in ipairs(fh_mkt_lavka_ids) do table.insert(ids_snap, v) end
        fh_mkt_lv_done = 0; fh_mkt_lv_total = #ids_snap
        sampAddChatMessage('[FH Market] {ffaa00}Сканирую лавку... Слотов: ' .. #ids_snap, 0xFFFFFF)
        for _, td_id in ipairs(ids_snap) do
            if not fh_mkt_lv_scanning then break end -- остановка
            local snap = fh_mkt_lv_done
            -- Закрыть предыдущий диалог хранением (если существует)
            if sampIsDialogActive() then
                sampSendDialogResponse(sampGetCurrentDialogId(), 0, 0, '')
                wait(80)
            end
            sampSendClickTextdraw(td_id)
            local w = 0
            while fh_mkt_lv_done == snap and w < 400 do wait(10); w = w + 1 end
            wait(50)
        end
        -- Закрыть лавку
        if sampIsDialogActive() then
            sampSendDialogResponse(sampGetCurrentDialogId(), 0, 0, '')
        end
        sampSendClickTextdraw(65535)
        wait(100)
        fh_mkt_lv_scanning = false; fh_mkt_save()
        local tot = 0; for _ in pairs(fh_mkt_lavka) do tot = tot + 1 end
        sampAddChatMessage('[FH Market] {00cc00}Скан лавки завершён. Товаров: '..tot, 0xFFFFFF)
    end)
end

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(0) end
    fh_setup_autologin_handler()
    while not sampIsLocalPlayerSpawned() do wait(0) end

    sampAddChatMessage('[Family Helper] {ffffff}v' .. thisScript().version .. ' | ' .. message_color_hex .. '/fh {ffffff}| /fhstats | /fspawn', message_color)
    init_commands()
    fh_mkt_load()

    -- \xc0\xe2\xf2\xee-\xe3\xeb\xe0\xe2\xe5\xed\xf1\xf2\xe2\xee: \xe4\xee\xe1\xe0\xe2\xeb\xff\xe5\xec \xf1\xe5\xe1\xff \xe8 \xf8\xeb\xb8\xec \xef\xe5\xf0\xe2\xfb\xe9 \xef\xe8\xed\xe3
    if settings.tg and settings.tg.auto_role then
        lua_thread.create(function()
            wait(8000)  -- \xe6\xe4\xb8\xec 8 \xf1\xe5\xea \xf7\xf2\xee\xe1\xfb \xf1\xe5\xf0\xe2\xe5\xf0 \xf2\xee\xf7\xed\xee \xe1\xfb\xeb \xe3\xee\xf2\xee\xe2 \xef\xf0\xe8\xed\xe8\xec\xe0\xf2\xfc \xf7\xe0\xf2
            if sampIsLocalPlayerSpawned() then
                fh_update_self()
                fh_send_ping()
            end
        end)
    end

    -- \xc0\xe2\xf2\xee\xf0\xe5\xe3\xe8\xf1\xf2\xf0\xe0\xf6\xe8\xff \xe8 \xe7\xe0\xe3\xf0\xf3\xe7\xea\xe0 \xef\xf0\xee\xef\xf3\xf9\xe5\xed\xed\xfb\xf5 \xf1\xee\xe1\xfb\xf2\xe8\xe9 \xe8\xe7 \xd2\xc3
    if settings.tg and settings.tg.enabled then
        tg_autoregister()
    end

    if (settings.family_info.my_name or '') == '' then
        sampAddChatMessage('[Family Helper] {ffffff}\xcd\xe0\xf1\xf2\xf0\xee\xe9\xf2\xe5 \xe8\xec\xff \xe2 ' .. message_color_hex .. '/fh', message_color)
    end

    local _autosave_timer   = os.time()
    while true do
        wait(0)
        nearby_players = get_players_in_radius(settings.general.float_btn_radius or 15)
        if settings.tg and settings.tg.auto_role then
            if os.time() - fh_last_ping >= FH_PING_INTERVAL then
                fh_send_ping()
            end
            -- Читать FH_PING из канала каждые 3 мин точно так же как tg_fetch_missed
            if not _G.fh_last_read   then _G.fh_last_read   = 0 end
            if not _G.fh_ping_offset then _G.fh_ping_offset = 0 end
            if os.time() - _G.fh_last_read >= 300 then
                _G.fh_last_read = os.time()
                local _tok  = (settings.tg.token2 ~= '' and settings.tg.token2 or settings.tg.token) or ''
                local _chan = settings.tg.channel_id or ''
                if _tok ~= '' and _chan ~= '' then
                    if not tg_effil then
                        local ok, lib = pcall(require, 'effil')
                        if ok and lib then tg_effil = lib end
                    end
                    if tg_effil then
                        lua_thread.create(function()
                            local off = _G.fh_ping_offset
                            local url = ('https://api.telegram.org/bot%s/getUpdates?offset=%d&limit=100&timeout=0&allowed_updates=%%5B%%22channel_post%%22%%5D'):format(_tok, off)
                            local raw2 = tg_http_get(url, 15)
                            if raw2 == '' or raw2:find('"result":%[%]') then return end
                            local max_uid = off
                            local pos = 1
                            while true do
                                local uid_s = raw2:find('"update_id"%s*:%s*%d+', pos)
                                if not uid_s then break end
                                local uid = tonumber(raw2:match('"update_id"%s*:%s*(%d+)', uid_s)) or 0
                                if uid + 1 > max_uid then max_uid = uid + 1 end
                                local nxt = raw2:find('"update_id"', uid_s + 1) or #raw2
                                local block = raw2:sub(uid_s, nxt)
                                local txt = block:match('"text"%s*:%s*"([^"]*)"')
                                if txt then
                                    txt = decode_unicode_cp1251(txt)
                                    txt = utf8_to_cp1251(txt)
                                    txt = txt:gsub('\\n', ' '):gsub('\\r', '')
                                    local fp_r, fp_j, fp_n = txt:match('%[FH_PING:(%d+):(%d+):([%a%d_]+)%]')
                                    if fp_n then
                                        fh_online[fp_n] = {rank=tonumber(fp_r) or 1, joined=tonumber(fp_j) or 0, last_seen=os.time()}
                                    end
                                end
                                pos = uid_s + 1
                            end
                            if max_uid > off then _G.fh_ping_offset = max_uid end
                        end)
                    end
                end
            end
        end

        -- \xc0\xe2\xf2\xee\xf1\xee\xf5\xf0\xe0\xed\xe5\xed\xe8\xe5 \xeb\xee\xe3\xe0 \xea\xe0\xe6\xe4\xfb\xe5 60 \xf1\xe5\xea\xf3\xed\xe4
        local _now = os.time()
        if _now - _autosave_timer >= 60 then
            _autosave_timer = _now
            save_log()
            save_settings()
        end

        -- \xc0\xe2\xf2\xee-\xee\xf2\xf7\xb8\xf2 \xef\xee \xe8\xed\xe2\xe0\xe9\xf2\xe0\xec \xe2 \xd2\xc3
        if settings.tg and settings.tg.enabled and settings.tg.auto_inv_report then
            local auto_h = tonumber(settings.tg.auto_inv_hour) or 23
            local auto_m = tonumber(settings.tg.auto_inv_min)  or 59
            local cur_h  = tonumber(os.date('%H'))
            local cur_m  = tonumber(os.date('%M'))
            local today_key = os.date('%d.%m.%Y')
            if cur_h == auto_h and cur_m == auto_m then
                if (settings.tg.auto_inv_last_date or '') ~= today_key then
                    settings.tg.auto_inv_last_date = today_key
                    save_settings()
                    -- \xd4\xee\xf0\xec\xe8\xf0\xf3\xe5\xec \xee\xf2\xf7\xb8\xf2 \xe7\xe0 \xf1\xe5\xe3\xee\xe4\xed\xff \xe4\xeb\xff \xf2\xe5\xea\xf3\xf9\xe5\xe3\xee \xe8\xe3\xf0\xee\xea\xe0
                    local self_nick = my_nick()
                    local stats = settings.invite_stats or {}
                    local s = stats[self_nick] or {}
                    local lines = {
                        '[FH] \xc4\xed\xe5\xe2\xed\xee\xe9 \xee\xf2\xf7\xb8\xf2 \xef\xee \xe8\xed\xe2\xe0\xe9\xf2\xe0\xec \x97 ' .. self_nick,
                        string.rep('-', 25),
                        '\xd1\xe5\xe3\xee\xe4\xed\xff:   ' .. (s.today or 0),
                        '\xcd\xe5\xe4\xe5\xeb\xff:    ' .. (s.week  or 0),
                        '\xcc\xe5\xf1\xff\xf6:     ' .. (s.month or 0),
                        '\xc2\xf1\xb8 \xe2\xf0\xe5\xec\xff: ' .. (s.total or 0),
                    }
                    tg_send(table.concat(lines, '\n'))
                    sampAddChatMessage('[Family Helper] {00cc00}\xc0\xe2\xf2\xee-\xee\xf2\xf7\xb8\xf2 \xef\xee \xe8\xed\xe2\xe0\xe9\xf2\xe0\xec \xee\xf2\xef\xf0\xe0\xe2\xeb\xe5\xed \xe2 \xd2\xc3!', 0xFFFFFF)
                end
            end
        end

        if settings.general.auto_invite and not isActiveCommand then
            local inv_players = get_players_in_radius(settings.general.auto_invite_radius)
            local tag = settings.family_info.family_tag or ''
            for _, pid in ipairs(inv_players) do
                if not invited_players[pid] and not isActiveCommand then
                    -- \xcd\xe5 \xe8\xed\xe2\xe0\xe9\xf2\xe8\xf2\xfc \xf2\xe5\xf5 \xf3 \xea\xee\xe3\xee \xf3\xe6\xe5 \xe5\xf1\xf2\xfc \xf2\xe5\xe3 \xf1\xe5\xec\xfc\xe8
                    local their_nick = sampGetPlayerNickname(pid) or ''
                    local already_member = tag ~= '' and their_nick:find(tag, 1, true)
                    if not already_member then
                        invited_players[pid] = os.time()
                        send_lines(settings.rp_invite.text or '', settings.rp_invite.waiting, pid)
                        break
                    end
                end
            end
        end

        for pid, ts in pairs(invited_players) do
            if os.time() - ts > 300 then invited_players[pid] = nil end
        end

        if not isActiveCommand then
            for idx, t in ipairs(settings.piar_templates) do
                local _piar_iv = t.auto_interval or 300
                    if (t.auto_interval_max or 0) > _piar_iv then
                        if not t._next_interval then t._next_interval = _piar_iv + math.random(0, t.auto_interval_max - _piar_iv) end
                        _piar_iv = t._next_interval
                    end
                    if t.enable and t.auto and os.time() - (t.last_time or 0) >= _piar_iv then
                        t._next_interval = nil
                    send_piar(idx); break
                end
            end
        end

        -- ===== \xce\xc1\xd0\xc0\xc1\xce\xd2\xca\xc0 \xc1\xc0\xd2\xd7\xc0 \xcf\xce\xc7\xc4\xd0\xc0\xc2\xd0\xc5\xcd\xc8\xc9 =====
        if congrats_batch_timer and not isActiveCommand then
            local elapsed = os.difftime(os.time(), congrats_batch_timer)
            if elapsed >= CONGRATS_BATCH_WINDOW and #congrats_batch > 0 then
                local batch = congrats_batch
                congrats_batch = {}
                congrats_batch_timer = nil
                local p = settings.congrats.use_fam and '/fam ' or ''
                local vars = settings.congrats.variants or {}
                local idx = (#vars > 0) and ((settings.congrats.variant_idx or 0) % #vars + 1) or 1
                settings.congrats.variant_idx = idx
                save_settings()
                local chosen = (vars[idx] or vars[1] or {}).items or {}
                lua_thread.create(function()
                    if #batch < CONGRATS_BATCH_SINGLE then
                        for _, nick in ipairs(batch) do
                            for _, item in ipairs(chosen) do
                                if item.text and item.text ~= '' then
                                    wait((item.waiting or 1.5) * 1000)
                                    sampSendChat(p .. processText(item.text, nil):gsub('{player_name}', nick))
                                end
                            end
                        end
                    else
                        local names = table.concat(batch, ', ')
                        CONGRATS_BATCH_MSG_IDX = CONGRATS_BATCH_MSG_IDX % #CONGRATS_BATCH_MSGS + 1
                        local bmsg = CONGRATS_BATCH_MSGS[CONGRATS_BATCH_MSG_IDX]:gsub('{names}', names)
                        wait(1500)
                        sampSendChat(p .. bmsg)
                    end
                end)
            elseif elapsed >= CONGRATS_BATCH_WINDOW then
                -- \xd2\xe0\xe9\xec\xe5\xf0 \xe2\xfb\xf8\xe5\xeb, \xed\xee \xe1\xe0\xf2\xf7 \xef\xf3\xf1\xf2\xee\xe9 \x97 \xf1\xe1\xf0\xee\xf1\xe8\xec
                congrats_batch_timer = nil
            end
        end
        -- Авто РП-оружие
        if settings.general.auto_rp_guns and sampIsLocalPlayerSpawned() then
            local cur_gun = getCurrentCharWeapon(PLAYER_PED)
            if cur_gun ~= fh_gun_now then
                fh_gun_old = fh_gun_now
                fh_gun_now = cur_gun
                local nm_new = fh_gun_names[fh_gun_now]
                local nm_old = fh_gun_names[fh_gun_old]
                local sl_new = fh_rp_take_slot[fh_gun_now] or 1
                local sl_old = fh_rp_take_slot[fh_gun_old] or 1
                local is_f   = (fh_sex == "Женщина")
                -- Выбираем глагол: гранаты/дубинкой = снял/повесил, остальное = достал/убрал
                local function is_hang(id) return id==3 or (id>=16 and id<=18) or id==39 or id==40 or id==90 or id==91 end
                local von  = is_hang(fh_gun_now) and (is_f and "сняла" or "снял")   or (is_f and "достала" or "достал")
                local voff = is_hang(fh_gun_old) and (is_f and "повесила" or "повесил") or (is_f and "убрала" or "убрал")
                if fh_gun_old == 0 and nm_new then
                    sampSendChat("/me " .. von  .. " " .. nm_new .. " " .. fh_take_from[sl_new])
                elseif fh_gun_now == 0 and nm_old then
                    sampSendChat("/me " .. voff .. " " .. nm_old .. " " .. fh_take_to[sl_old])
                elseif nm_old and nm_new then
                    sampSendChat("/me " .. voff .. " " .. nm_old .. " " .. fh_take_to[sl_old] .. ", после чего " .. von .. " " .. nm_new .. " " .. fh_take_from[sl_new])
                end
            end
        end

    end
end

function init_commands()
    sampRegisterChatCommand("fh", function()
        MainWindow[0] = not MainWindow[0]
        if MainWindow[0] and not _G.fmembers_collecting then
            lua_thread.create(function() wait(400); _G.fmembers_requested = true; sampSendChat('/fmembers') end)
        end
    end)
    sampRegisterChatCommand("fi", function(a)
        if isParamSampID(a) then interact_player_id = tonumber(a); InteractMenu[0] = true
        else sampAddChatMessage('[Family Helper] {ffffff}/fi [ID]', message_color) end
    end)
    sampRegisterChatCommand("fm", function(a)
        if isParamSampID(a) then player_id = tonumber(a); FastMenu[0] = true
        else sampAddChatMessage('[Family Helper] {ffffff}/fm [ID]', message_color) end
    end)
    sampRegisterChatCommand("stop", function()
        if isActiveCommand then command_stop = true
        else sampAddChatMessage('[Family Helper] {ffffff}\xcd\xe5\xf2 \xe0\xea\xf2\xe8\xe2\xed\xee\xe9 \xee\xf2\xfb\xe3\xf0\xee\xe2\xea\xe8.', message_color) end
    end)
    sampRegisterChatCommand("fai", function()
        settings.general.auto_invite = not settings.general.auto_invite; save_settings(); invited_players = {}
        sampAddChatMessage('[Family Helper] {ffffff}\xc0\xe2\xf2\xee-\xe8\xed\xe2\xe0\xe9\xf2: ' .. message_color_hex .. (settings.general.auto_invite and '\xc2\xca\xcb' or '\xc2\xdb\xca\xcb'), message_color)
    end)
    sampRegisterChatCommand("fhdebug", function()
        local allchars = getAllChars()
        local char_count = 0
        for _ in pairs(allchars) do char_count = char_count + 1 end
        sampAddChatMessage('[FH Debug] {ffffff}getAllChars: ' .. message_color_hex .. char_count .. ' {ffffff}\xf7\xe0\xf0\xee\xe2', message_color)
        local mx, my, mz = getCharCoordinates(PLAYER_PED)
        sampAddChatMessage('[FH Debug] {ffffff}\xcf\xee\xe7\xe8\xf6\xe8\xff: ' .. message_color_hex .. string.format('%.1f %.1f %.1f', mx, my, mz), message_color)
        local found = 0
        for _, h in pairs(allchars) do
            if h ~= PLAYER_PED and doesCharExist(h) then
                local res, pid = sampGetPlayerIdByCharHandle(h)
                if res then
                    local x, y, z = getCharCoordinates(h)
                    local dist = getDistanceBetweenCoords3d(mx, my, mz, x, y, z)
                    local nick = sampGetPlayerNickname(pid) or '???'
                    sampAddChatMessage('[FH Debug] {ffffff}' .. message_color_hex .. nick .. '[' .. pid .. '] {ffffff}\xf0\xe0\xf1\xf1\xf2: ' .. message_color_hex .. string.format('%.1f', dist), message_color)
                    found = found + 1
                    if found >= 10 then break end
                end
            end
        end
        if found == 0 then sampAddChatMessage('[FH Debug] {ffffff}\xc8\xe3\xf0\xee\xea\xee\xe2 \xf0\xff\xe4\xee\xec \xed\xe5\xf2', message_color) end
        sampAddChatMessage('[FH Debug] {ffffff}\xd0\xe0\xe4\xe8\xf3\xf1: ' .. message_color_hex .. (settings.general.float_btn_radius or 15) .. ' {ffffff}| \xca\xed\xee\xef\xea\xe0: ' .. message_color_hex .. (settings.general.float_btn_enable and 'ON' or 'OFF'), message_color)
    end)
    -- \xd1\xef\xe0\xe2\xed \xf2\xf0\xe0\xed\xf1\xef\xee\xf0\xf2\xe0 \xf1 \xf2\xe0\xe9\xec\xe5\xf0\xee\xec
        sampRegisterChatCommand("fhdlg", function()
        debug_dialog = not debug_dialog
        local state = debug_dialog and '{00FF00}\xc2\xca\xcb' or '{FF4444}\xc2\xdb\xca\xcb'
        sampAddChatMessage('[Family Helper] {ffffff}\xc4\xe5\xe1\xe0\xe3 \xd4\xc0\xcc\xcc\xc5\xcd\xde: ' .. state, 0xFFA500)
        if debug_dialog then
            sampAddChatMessage('[Family Helper] {aaaaaa}\xce\xf2\xea\xf0\xee\xe9\xf2\xe5 /fammenu \xe8 \xf1\xec\xee\xf2\xf0\xe8\xf2\xe5 \xf7\xf2\xee \xef\xf0\xe8\xf5\xee\xe4\xe8\xf2 \xe2 \xf7\xe0\xf2', 0xFFA500)
        end
    end)
    sampRegisterChatCommand("fspawn", function(a)
        local delay = tonumber(a) or settings.general.famspawn_delay or 30
        lua_thread.create(function()
            sampSendChat('/fam \xc2\xed\xe8\xec\xe0\xed\xe8\xe5! \xd7\xe5\xf0\xe5\xe7 ' .. delay .. ' \xf1\xe5\xea \xef\xf0\xee\xe8\xe7\xee\xe9\xe4\xb8\xf2 \xf1\xef\xe0\xe2\xed \xf1\xe5\xec\xe5\xe9\xed\xee\xe3\xee \xf2\xf0\xe0\xed\xf1\xef\xee\xf0\xf2\xe0!')
            wait(delay * 1000)
            sampSendChat('/famspawn')
            wait(200)
            sampSendChat('/fam \xd1\xe5\xec\xe5\xe9\xed\xfb\xe9 \xf2\xf0\xe0\xed\xf1\xef\xee\xf0\xf2 \xf3\xf1\xef\xe5\xf8\xed\xee \xe7\xe0\xf1\xef\xe0\xe2\xed\xe5\xed!')
        end)
    end)

    -- \xd1\xe1\xf0\xee\xf1 \xf1\xf7\xb8\xf2\xf7\xe8\xea\xe0 \xf1\xe5\xf1\xf1\xe8\xe8
    sampRegisterChatCommand("fhreset", function()
        invite_session = 0
        sampAddChatMessage('[Family Helper] {ffffff}\xd1\xf7\xb8\xf2\xf7\xe8\xea \xf1\xe5\xf1\xf1\xe8\xe8 \xf1\xe1\xf0\xee\xf8\xe5\xed!', message_color)
    end)

    sampRegisterChatCommand("fhstats", function()
        local total = 0
        local tag = settings.family_info.family_tag or ''
        if tag ~= '' then
            for i = 0, 999 do
                if sampIsPlayerConnected(i) then
                    local nick = sampGetPlayerNickname(i) or ''
                    if nick:find(tag, 1, true) then total = total + 1 end
                end
            end
            sampAddChatMessage('[Family Helper] {ffffff}\xce\xed\xeb\xe0\xe9\xed \xf1 \xf2\xe5\xe3\xee\xec ' .. message_color_hex .. tag .. '{ffffff}: ' .. message_color_hex .. total, message_color)
        else
            sampAddChatMessage('[Family Helper] {ffffff}\xd3\xea\xe0\xe6\xe8\xf2\xe5 \xf2\xe5\xe3 \xf1\xe5\xec\xfc\xe8 \xe2 \xed\xe0\xf1\xf2\xf0\xee\xe9\xea\xe0\xf5!', message_color)
        end
        sampAddChatMessage('[Family Helper] {ffffff}\xc8\xed\xe2\xe0\xe9\xf2\xee\xe2 \xe7\xe0 \xf1\xe5\xf1\xf1\xe8\xfe: ' .. message_color_hex .. invite_session .. ' {ffffff}| \xc2\xf1\xe5\xe3\xee: ' .. message_color_hex .. (settings.general.invite_total or 0), message_color)
    end)

    sampRegisterChatCommand("fp", function(a)
        local idx = tonumber(a)
        if idx and settings.piar_templates[idx] then send_piar(idx)
        else
            sampAddChatMessage('[Family Helper] {ffffff}/fp [1-' .. #settings.piar_templates .. ']', message_color)
            for i, t in ipairs(settings.piar_templates) do
                sampAddChatMessage(message_color_hex .. i .. '. {ffffff}' .. (t.name or ''), message_color)
            end
        end
    end)

    for _, c in ipairs(settings.commands) do
        if c.enable and not c.deleted and (c.cmd or '') ~= '' then
            reg_cmd(c.cmd, c.arg, c.text, tonumber(c.waiting))
        end
    end
end

function reg_cmd(cmd, arg, text, w)
    if not cmd or cmd == '' then return end
    sampRegisterChatCommand(cmd, function(a)
        if isActiveCommand then sampAddChatMessage('[Family Helper] {ffffff}\xc4\xee\xe6\xe4\xe8\xf2\xe5\xf1\xfc \xe7\xe0\xe2\xe5\xf0\xf8\xe5\xed\xe8\xff!', message_color); return end
        local ok, mt = false, text or ''
        if (arg or '') == '' then ok = true
        elseif arg == '{arg}' then
            if a and a ~= '' then mt = mt:gsub('{arg}', a); ok = true
            else sampAddChatMessage('[Family Helper] {ffffff}/' .. cmd .. ' [\xe0\xf0\xe3]', message_color) end
        elseif arg == '{arg_id}' then
            if isParamSampID(a) then ok = true; send_lines(mt, w, tonumber(a)); return
            else sampAddChatMessage('[Family Helper] {ffffff}/' .. cmd .. ' [ID]', message_color) end
        elseif arg == '{arg_id} {arg2}' then
            if a and a ~= '' then
                local a1, a2 = a:match('(%d+) (.+)')
                if isParamSampID(a1) and a2 then mt = mt:gsub('{arg2}', a2); ok = true
                    send_lines(mt, w, tonumber(a1)); return
                else sampAddChatMessage('[Family Helper] {ffffff}/' .. cmd .. ' [ID] [\xf2\xe5\xea\xf1\xf2]', message_color) end
            else sampAddChatMessage('[Family Helper] {ffffff}/' .. cmd .. ' [ID] [\xf2\xe5\xea\xf1\xf2]', message_color) end
        end
        if ok then send_lines(mt, w, nil) end
    end)
end

----------------------------------------------- CHAT EVENTS ------------------------------------------------

function sampev.onShowDialog(dialogId, style, title, button1, button2, text)
    -- FH Market: РѕР±РЅРѕРІР»СЏРµРј Р·Р°РіРѕР»РѕРІРѕРє РґР»СЏ deep scan coroutine
    fh_last_dlg_title = title and title:gsub('{%x+}',''):match('^%s*(.-)%s*$') or ''
    -- ===== DEBUG \xd0\xc5\xd6\xc8\xcc \xc4\xc8\xc0\xcb\xce\xc3\xce\xc2 =====
    if debug_dialog then
        sampAddChatMessage('[FH DEBUG] {00FFFF}Dialog ID: {ffffff}' .. tostring(dialogId) .. ' {00FFFF}style: {ffffff}' .. tostring(style), 0xFFFFFF)
        sampAddChatMessage('[FH DEBUG] {00FFFF}Title: {ffffff}' .. tostring(title), 0xFFFFFF)
        sampAddChatMessage('[FH DEBUG] {00FFFF}Btn1: {ffffff}' .. tostring(button1) .. ' {00FFFF}Btn2: {ffffff}' .. tostring(button2), 0xFFFFFF)
        if text then
            local lines = {}
            local n = 0
            for line in text:gmatch('[^\n]+') do
                n = n + 1
                if n <= 8 then
                    local clean = line:gsub('{%x%x%x%x%x%x}',''):match('^%s*(.-)%s*$') or ''
                    sampAddChatMessage('[FH DEBUG] {aaaaaa}[' .. n .. '] {ffffff}' .. clean, 0xFFFFFF)
                end
            end
            sampAddChatMessage('[FH DEBUG] {666666}... \xc2\xf1\xe5\xe3\xee \xf1\xf2\xf0\xee\xea: {ffffff}' .. n, 0xFFFFFF)
        end
    end
    -- ===== END DEBUG =====
    -- FH Market: \xc7\xe0\xf9\xe8\xf2\xe0 \xf1\xea\xe0\xed\xe0 \xf7\xe5\xea\xef\xee\xe8\xed\xf2\xe0 \xee\xf2 \xf1\xf2\xee\xf0\xee\xed\xed\xe8\xf5 \xe4\xe8\xe0\xeb\xee\xe3\xee\xe2
    if fh_mkt_cp_scanning and title and text then
        local ct2 = title:gsub('{%x+}',''):match('^%s*(.-)%s*$') or ''
        local is_our = (dialogId == 15073) or ct2:find('\xf0\xe5\xe4\xed\xff\xff') ~= nil
        if not is_our then
            fh_mkt_cp_prev_text = nil
            lua_thread.create(function()
                wait(150)
                sampSendDialogResponse(dialogId, 0, 0, '')
                wait(300)
            end)
            return false
        end
    end
    -- \xce\xf4\xf4\xeb\xe0\xe9\xed-\xef\xf0\xee\xe2\xe5\xf0\xea\xe0
    if title and (title:find("\xce\xf4\xf4\xeb\xe0\xe9\xed \xf7\xeb\xe5\xed\xfb \xf1\xe5\xec\xfc\xe8") or title:find("\xd3\xf7\xe0\xf1\xf2\xed\xe8\xea\xe8 \xee\xf4\xf4\xeb\xe0\xe9\xed")) then
        fmembers_offline = {}
        for line in text:gmatch("[^\n]+") do
            -- \xd4\xee\xf0\xec\xe0\xf2: "Nick_Name | \xd0\xe0\xed\xe3 N | \xc4\xed\xe5\xe9: X" \xe8\xeb\xe8 "Nick_Name(\xed\xe5 \xe2 \xf1\xe5\xf2\xe8 X \xee\xed\xeb\xe0\xe9\xed \xec\xe8\xed.)"
            local clean = line:gsub("{%x+}", ""):match("^%s*(.-)%s*$") or ""
            local nick = clean:match("^([%a_][%a%d_]+)")
            local days = clean:match("\xc4\xed\xe5\xe9:%s*(%d+)") or clean:match("\xed\xe5 \xe2 \xf1\xe5\xf2\xe8 (%d+)")
            if nick and nick ~= "" then
                fmembers_offline[nick] = tonumber(days) or 0
            end
        end
        -- \xd1\xea\xf0\xfb\xf2\xfc \xe4\xe8\xe0\xeb\xee\xe3 \xec\xee\xeb\xf7\xe0
        lua_thread.create(function() wait(100); sampSendDialogResponse(dialogId, 0, -1, "") end)
        return false
    end


    -- \xc0\xe2\xf2\xee-\xef\xee\xe4\xf2\xe2\xe5\xf0\xe6\xe4\xe5\xed\xe8\xe5 /vr
    -- Авто-сбор /storage хранилища

    

-- FH Market: ЧЕКПОИНТ скан (shallow + deep)
        local ct_mkt = title and title:gsub('{%x+}',''):match('^%s*(.-)%s*$') or ''
        local is_mkt_list = (dialogId == 15073) or (dialogId ~= 15376 and ct_mkt:find('Средняя цена товаров') ~= nil)
        if is_mkt_list and text then
            local scan_label = 'Проанализировать все цены [FH]'
            if fh_mkt_cp_scanning then
                if fh_mkt_cp_prev_text == text then
                    local tot = 0; for _ in pairs(fh_mkt_prices) do tot = tot + 1 end
                    sampAddChatMessage('[FH Market] {00cc00}Анализ завершён! Товаров: ' .. tot, 0xFFFFFF)
                    printStyledString('~w~FH Market: ~g~' .. tot .. ' ~w~items OK', 2500, 6)
                    fh_mkt_cp_prev_text = nil; fh_mkt_cp_scanning = false
                    fh_mkt_save()
                    lua_thread.create(function() wait(100); sampSendDialogResponse(dialogId, 0, 0, '') end)
                    return false
                end
                fh_mkt_parse_cp(text)
                local tot2 = 0; for _ in pairs(fh_mkt_prices) do tot2 = tot2 + 1 end
                fh_mkt_cp_page = (fh_mkt_cp_page or 0) + 1
                printStyledString('~w~FH: ~g~' .. tot2 .. ' ~w~items | p.~r~' .. fh_mkt_cp_page, 1800, 6)
                fh_mkt_cp_prev_text = text
                local next_idx = fh_find_listitem(text, 'Следующая страница')
                if next_idx then
                    lua_thread.create(function() wait(100); sampSendDialogResponse(dialogId, 1, next_idx, 0) end)
                else
                    local tot3 = 0; for _ in pairs(fh_mkt_prices) do tot3 = tot3 + 1 end
                    sampAddChatMessage('[FH Market] {00cc00}Скан завершён. Товаров: ' .. tot3, 0xFFFFFF)
                    fh_mkt_cp_scanning = false; fh_mkt_save()
                    lua_thread.create(function() wait(100); sampSendDialogResponse(dialogId, 0, 0, 0) end)
                end
                return false
            else
                local already = false
                for ln2 in text:gmatch('[^\n]+') do
                    if ln2:find(scan_label, 1, true) then already = true; break end
                end
                if not already then
                    local deep_label = 'Углублённый скан [FH]'
                    -- Вставляем обе кнопки на строку поиска
                    local new_text = string.gsub(text, '(\xcf\xee\xe8\xf1\xea \xef\xee \xed\xe0\xe7\xe2\xe0\xed\xe8\xfe\t%s)\n', '%1\n{00FF00}' .. scan_label .. '\t \n{FFAA00}' .. deep_label .. '\t \n', 1)
                    if new_text == text then
                        local fl = text:match('^([^\n]*)')
                        new_text = fl .. '\n{00FF00}' .. scan_label .. '\t \n{FFAA00}' .. deep_label .. '\t \n' .. text:sub(#fl + 1)
                    end
                    fh_mkt_cp_go_idx = fh_find_listitem(new_text, scan_label)
                    fh_mkt_cp_deep_go_idx = fh_find_listitem(new_text, deep_label)
                    return { dialogId, style, title, button1, button2, new_text }
                end
            end
        end

    -- ===== FH AUTO MARKET: onShowDialog (dialog 15376) =====
    local is_auto_dlg = (dialogId == 15376)
    if not is_auto_dlg and title then
        local ct_a = title:gsub('{%x+}',''):match('^%s*(.-)%s*$') or ''
        is_auto_dlg = ct_a:find('Средняя цена автомобилей') ~= nil
    end
    if is_auto_dlg and text then
        local auto_scan_label = 'Сканировать все авто [FH]'
        if fh_mkt_auto_scanning then
            -- Скан идёт -- парсим текст и листаем
            if fh_mkt_auto_prev_text == text then
                local tot = 0; for _ in pairs(fh_mkt_auto) do tot = tot + 1 end
                sampAddChatMessage('[FH Auto] {00cc00}Скан завершён! Авто: ' .. tot, 0xFFFFFF)
                printStyledString('~w~FH Auto: ~g~' .. tot .. ' ~w~OK', 2500, 6)
                fh_mkt_auto_prev_text = nil; fh_mkt_auto_scanning = false
                fh_mkt_save()
                lua_thread.create(function() wait(100); sampSendDialogResponse(dialogId, 0, 0, '') end)
                return false
            end
            fh_mkt_parse_auto(text)
            local atot = 0; for _ in pairs(fh_mkt_auto) do atot = atot + 1 end
            fh_mkt_auto_page = (fh_mkt_auto_page or 0) + 1
            printStyledString('~w~FH Auto: ~g~' .. atot .. ' ~w~| p.~r~' .. fh_mkt_auto_page, 1800, 6)
            fh_mkt_auto_prev_text = text
            local nxt_a = fh_find_listitem(text, 'Следующая страница')
            if nxt_a then
                lua_thread.create(function() wait(100); sampSendDialogResponse(dialogId, 1, nxt_a, 0) end)
            else
                local atot3 = 0; for _ in pairs(fh_mkt_auto) do atot3 = atot3 + 1 end
                sampAddChatMessage('[FH Auto] {00cc00}Скан завершён. Авто: ' .. atot3, 0xFFFFFF)
                fh_mkt_auto_scanning = false; fh_mkt_save()
                lua_thread.create(function() wait(100); sampSendDialogResponse(dialogId, 0, 0, 0) end)
            end
            return false
        else
            -- Скан не идёт -- вставляем обе кнопки (как цр)
            local auto_deep_label = 'Углублённый скан авто [FH]'
            local already_a = false
            for ln_a in text:gmatch('[^\n]+') do
                if ln_a:find(auto_scan_label, 1, true) then already_a = true; break end
            end
            if not already_a then
                local new_text_a = string.gsub(text,
                    '(Поиск по названию	[^\n]*)\n',
                    '%1\n{00FF00}' .. auto_scan_label .. '\t \n{FFAA00}' .. auto_deep_label .. '\t \n', 1)
                if new_text_a == text then
                    local fl_a = text:match('^([^\n]*)')
                    new_text_a = fl_a .. '\n{00FF00}' .. auto_scan_label .. '\t \n{FFAA00}' .. auto_deep_label .. '\t \n' .. text:sub(#fl_a+1)
                end
                fh_mkt_auto_go_idx      = fh_find_listitem(new_text_a, auto_scan_label)
                fh_mkt_auto_deep_go_idx = fh_find_listitem(new_text_a, auto_deep_label)
                return { dialogId, style, title, button1, button2, new_text_a }
            end
        end
    end


function sampev.onShowTextDraw(td_id, td_data)
    -- FH Market: Сбор ID слотов лавки (по MCR: x==325, y~164/169, фон слота)
    -- MCR маркер: текстдрав с x==325, yимеет фракц. часть .xxx
    if td_data and td_data.position then
        local px = td_data.position.x or 0
        local py = td_data.position.y or 0
        local py_s = tostring(py)
        -- Слоты товаров прилавки: x==325, y ИМЕЕТ фракционную часть (164.x или 169.x в Arizona)
        if px == 325 and (py_s:find('164%.') or py_s:find('169%.') or py_s:find('165%.') or py_s:find('168%.')) then
            local exists = false
            for _,v in ipairs(fh_mkt_lavka_ids) do if v==td_id then exists=true; break end end
            if not exists then
                table.insert(fh_mkt_lavka_ids, td_id)
                -- Сохраняем размеры слота для снятия товара
                if not fh_mkt_lavka_slot_w then
                    fh_mkt_lavka_slot_w = td_data.lineWidth
                    fh_mkt_lavka_slot_h = td_data.lineHeight
                end
            end
        end
    end
end

function sampev.onTextDrawHide(td_id)
    for _,v in ipairs(fh_mkt_lavka_ids) do
        if v == td_id then
            fh_mkt_lavka_ids={}
            fh_mkt_lavka_sep={}
            fh_mkt_lavka_page_id=-1
            break
        end
    end
end


    -- FH Market: СКАН лавки -- РЕЦИМ 1: НОВЫЙ UI Arizona (dialog 25668, как в MCR)
    -- При подтверждении нового UI: скрипт сам кликает на textdraw прилавки и получает dialog 25668
    -- Формат: {57FF6B}ItemName{xxxxxx} ... Стоимость: $PRICE за шт. ... В наличии: QTY шт.
    if fh_mkt_lv_scanning and dialogId == 25668 and text then
        local name = text:match('{57FF6B}(.-){%x+}')
        if not name or name == '' then
            -- Формат без цветского сты: первая латинская строка = название
            for line in text:gmatch('[^\n]+') do
                local n = line:gsub('{%x+}',''):match('^%s*(.-)%s*$')
                if n and n ~= '' and not n:find(':') then name=n; break end
            end
        end
        -- Цена: MCR GetPriceFromTextDialog - "Стоимость: $N за шт."
        local price_s = ''
        for line in text:gmatch('[^\n]+') do
            local p = line:match('Стоимость:%s*[Vv][Cc]%$([%d,%.]+)')
                   or line:match('Стоимость:%s*%$([%d,%.]+)')
                   or line:match('Стоимость:%s*([%d,%.]+)%s*за')
            if p then price_s=p; break end
        end
        local qty_s = '1'
        for line in text:gmatch('[^\n]+') do
            local q = line:match('В%s*наличии:%s*([%d]+)')
                   or line:match('Количество:%s*([%d]+)')
            if q then qty_s=q; break end
        end
        local is_vc = text:find('[Vv][Cc]%$') ~= nil
        local price = tonumber(price_s:gsub('[,.]',''))
        local qty   = tonumber(qty_s) or 1
        local ct    = title and title:gsub('{%x+}',''):match('^%s*(.-)%s*$') or ''
        local op    = (ct:find('Покуп') or ct:find('Скуп')) and 'sell' or 'buy'
        if name and name ~= '' and price and price > 0 then
            fh_mkt_lavka_record(name, price, qty, op)
        end
        fh_mkt_lv_cur_dialog = dialogId
        fh_mkt_lv_done = fh_mkt_lv_done + 1
        lua_thread.create(function() wait(80); sampSendDialogResponse(dialogId,0,0,'') end)
        return false
    end

    -- FH Market: СКАН лавки -- РЕЖИМ 2: СТАРЫЙ UI Arizona (по title "Информация..." / "Покупка..." / "Продажа...")
    if fh_mkt_lv_scanning and text then
        local ct = title and title:gsub('{%x+}',''):match('^%s*(.-)%s*$') or ''
        if ct:find('Информ') or ct:find('Покуп') or ct:find('Продаж') then
            local r = fh_mkt_parse_lavka(text, ct)
            if r then fh_mkt_lavka_record(r.name,r.price,r.qty,r.op) end
            fh_mkt_lv_cur_dialog = dialogId
            fh_mkt_lv_done = fh_mkt_lv_done + 1
            lua_thread.create(function() wait(80); sampSendDialogResponse(dialogId,0,0,'') end)
            return false
        end
    end
    if settings.general.auto_storage_collect then
        local ct = title and title:gsub('{%x+}',''):match('^%s*(.-)%s*$') or ''
        if ct == 'Хранилище предметов' then
            lua_thread.create(function() wait(300)
                sampSendDialogResponse(dialogId, 1, 0, '') end)
            return false
        end
        if ct == 'Хранилище' and (style == 4 or style == 5) then
            -- Считаем строки в tablist (\t = разделитель колонок)
            local item_count = 0
            if text then
                for _ in text:gmatch('[^\n]+') do item_count = item_count + 1 end
            end
            if item_count > 0 then
                lua_thread.create(function() wait(300)
                    sampSendDialogResponse(dialogId, 1, 0, '') end)
            else
                lua_thread.create(function() wait(300)
                    sampSendDialogResponse(dialogId, 0, 0, '') end)
            end
            return false
        end
        if ct == 'Хранилище' and style == 2 and text then
            local pick_all = nil  -- 'Забсать все предметы за последний час'
            local pick_one = nil  -- 'Забрать предмет'
            local idx = 0
            for line_t in text:gmatch('[^\n]+') do
                local cl = line_t:gsub('{%x+}',''):match('^%s*(.-)%s*$') or ''
                -- Забрать все предметы за последний час -- офруВт максимальный сбор
                if cl:find('Забрать все') then
                    pick_all = idx
                elseif cl:find('Забрать предмет') and not cl:find('Все') then
                    if pick_one == nil then pick_one = idx end
                end
                idx = idx + 1
            end
            -- Если есть 'Забрать все' -- Кликаем его (забирает все сразу)
            local chosen = pick_all or pick_one
            if chosen then
                lua_thread.create(function() wait(300)
                    sampSendDialogResponse(dialogId, 1, chosen, '') end)
                return false
            end
        end
        -- Реакция на диалог подтверждения 'Забрать все предметы'
        if ct:find('Хранилище') and style == 0 and text then
            local cl = text:gsub('{%x+}',''):lower()
            if cl:find('забрать') or cl:find('забира') then
                lua_thread.create(function() wait(200)
                    sampSendDialogResponse(dialogId, 1, 0, '') end)
                return false
            end
        end
    end

    if text ~= nil and settings.general.auto_vr_confirm then
        if string.find(text, "\xc2\xe0\xf8\xe5 \xf1\xee\xee\xe1\xf9\xe5\xed\xe8\xe5 \xff\xe2\xeb\xff\xe5\xf2\xf1\xff \xf0\xe5\xea\xeb\xe0\xec\xee\xe9?") then
            sampSendDialogResponse(dialogId, 1, "", "")
            return false
        end
    end

    -- Авто-подтверждение /ad диалогов
    if title and settings.general.auto_ad_confirm then
        local ct = title:gsub('{%x+}',''):match('^%s*(.-)%s*$') or ''
        if ct:find('\xcf\xee\xe4\xe0\xf7\xe0') and not ct:find('\xcf\xee\xe4\xf2\xe2') then
            lua_thread.create(function() wait(400)
                sampSendDialogResponse(dialogId, 1, 0, text and text:match('^%s*(.-)%s*$') or '') end)
            return false
        end
        if ct:find('\xf0\xe0\xe4\xe8\xee') or ct:find('\xd0\xe0\xe4\xe8\xee') then
            lua_thread.create(function() wait(400)
                sampSendDialogResponse(dialogId, 1, settings.general.auto_ad_station_idx or 2, '') end)
            return false
        end
        if ct:find('\xf2\xe8\xef') or ct:find('\xd2\xe8\xef') then
            lua_thread.create(function() wait(400)
                sampSendDialogResponse(dialogId, 1, settings.general.auto_ad_type or 0, '') end)
            return false
        end
        if ct:find('\xcf\xee\xe4\xf2\xe2') then
            lua_thread.create(function() wait(400)
                sampSendDialogResponse(dialogId, 1, -1, '') end)
            return false
        end
    end


    -- /fmembers \x97 \xef\xe5\xf0\xe5\xf5\xe2\xe0\xf2 \xe4\xe8\xe0\xeb\xee\xe3\xe0 \xf1 \xee\xed\xeb\xe0\xe9\xed-\xf1\xef\xe8\xf1\xea\xee\xec
    -- \xc7\xe0\xe3\xee\xeb\xee\xe2\xee\xea \xf2\xee\xf7\xed\xee: "\xc8\xec\xff\xd1\xe5\xec\xfc\xe8(\xc2 \xf1\xe5\xf2\xe8: N) | \xd1\xe5\xec\xfc\xff"
    -- \xd1\xf2\xf0\xee\xea\xe0 \xf2\xee\xf7\xed\xee:    "(10) Nick_Name(ID) [\xf3\xf0\xee\xe2\xe5\xed\xfc] [\xea\xe2\xe5\xf1\xf2\xfb]  \xf1\xeb\xee\xf2\xfb  \xe4\xe8\xf1\xf2  \xec\xee\xed\xe5\xf2\xfb"
    -- \xc4\xee\xef. \xe7\xe0\xf9\xe8\xf2\xe0: \xe5\xf1\xeb\xe8 \xe8\xe4\xb8\xf2 \xf1\xe1\xee\xf0 \xed\xee \xef\xf0\xee\xf8\xeb\xee > 12 \xf1\xe5\xea\xf3\xed\xe4 \x97 \xf1\xf7\xe8\xf2\xe0\xe5\xec \xe7\xe0\xe2\xe8\xf1\xf8\xe8\xec \xe8 \xf1\xe1\xf0\xe0\xf1\xfb\xe2\xe0\xe5\xec
    if _G.fmembers_collecting and _G.fmembers_collect_start and os.time() - _G.fmembers_collect_start > 60 then
        _G.fmembers_collecting = false
        _G.fmembers_collect_start = nil
        _G.fmembers_last_dlg_time = nil
        sampAddChatMessage('[Family Helper] {ff4444}\xd1\xe1\xee\xf0 \xf3\xf7\xe0\xf1\xf2\xed\xe8\xea\xee\xe2 \xe7\xe0\xe2\xe8\xf1 \x97 \xf1\xe1\xf0\xee\xf8\xe5\xed.', 0xFFFFFF)
    end
    local clean_title = title and title:gsub('{%x%x%x%x%x%x}', '') or ''
    local is_fmembers_dialog = _G.fmembers_requested and (clean_title:find('| \xd1\xe5\xec\xfc\xff') or clean_title:find('\xc2 \xf1\xe5\xf2\xe8:'))
    if not is_fmembers_dialog and _G.fmembers_collecting and style == 5 then
        is_fmembers_dialog = true
    end
    if is_fmembers_dialog then
        -- \xc1\xeb\xee\xea\xe8\xf0\xf3\xe5\xec \xef\xee\xe2\xf2\xee\xf0 \xf2\xee\xeb\xfc\xea\xee \xe5\xf1\xeb\xe8 \xef\xf0\xee\xf8\xeb\xee < 300\xec\xf1
        local now_ms = os.clock() * 1000
        if _G.fmembers_last_dlg_time and (now_ms - _G.fmembers_last_dlg_time) < 300 then
            return false
        end
        _G.fmembers_last_dlg_time = now_ms

        if not _G.fmembers_collecting then
            fmembers_online = {}
            _G.fmembers_collecting = true
            _G.fmembers_collect_start = os.time()
        end

        local has_prev = false
        local item_idx = -1
        local next_page_idx = nil
        for line in text:gmatch('[^\n]+') do
            local clean = line:gsub('{%x%x%x%x%x%x}', ''):match('^%s*(.-)%s*$')
            item_idx = item_idx + 1
            if clean and clean ~= '' then
                local rank_num = clean:match('^%((%d+)%)')
                local nick     = clean:match('^%(%d+%)%s+([%a_][%a%d_]*)%(')
                if nick then
                    fmembers_online[nick] = rank_num and ('\xd0\xe0\xed\xe3 ' .. rank_num) or '\xd3\xf7\xe0\xf1\xf2\xed\xe8\xea'
                elseif clean:find('\xd1\xeb\xe5\xe4\xf3\xfe\xf9\xe0\xff') or clean:find('>>') or clean:find('\xbb') then
                    next_page_idx = item_idx
                elseif clean:find('\xef\xf0\xe5\xe4\xfb\xe4\xf3\xf9\xe5\xe9') or clean:find('<<') or clean:find('\xab') then
                    has_prev = true
                end
            end
        end

        local cnt = 0; for _ in pairs(fmembers_online) do cnt = cnt + 1 end

        if next_page_idx ~= nil then
            local saved_id = dialogId
            local click_idx = has_prev and (next_page_idx - 1) or next_page_idx
            lua_thread.create(function()
                wait(100)
                sampSendDialogResponse(saved_id, 1, click_idx, '')
            end)
            return false
        else
            _G.fmembers_collecting = false
            _G.fmembers_collect_start = nil
            _G.fmembers_requested = false
            _G.fmembers_last_dlg_time = nil
            fmembers_last_update = os.time()
            lua_thread.create(function()
                wait(100)
                sampSendDialogResponse(dialogId, 0, 0, '')
            end)
            sampAddChatMessage('[Family Helper] {ffffff}\xce\xed\xeb\xe0\xe9\xed \xee\xe1\xed\xee\xe2\xeb\xb8\xed: ' .. cnt .. ' \xf7\xe5\xeb.', 0xFFA500)
            return false
        end
    end
end

-- ===== FH Market: onSendDialogResponse (точно из референса) =====
function sampev.onSendDialogResponse(dialogId, button, listItem, inputText)
    local is_mkt = (dialogId == 15073)
    if not is_mkt then
        local ct = (sampIsDialogActive() and sampGetDialogTitle() or ''):gsub('{%x+}',''):match('^%s*(.-)%s*$') or ''
        is_mkt = ct:find('Средняя цена товаров при продаже') ~= nil
    end
    -- [DBG] все клики по маркет-диалогу
    if is_mkt then
        -- [DBG] SendResp отключён
    end

    -- ===== ГЛУБОКИЙ СКАН: проверяем ПЕРВЫМ (до shallow) =====
    -- Во время deep scan блокируем все ручные клики на диалог рынка
    if is_mkt and fh_mkt_cp_deep_scanning then
        -- Клики lua_thread проходят напрямую через sampSendDialogResponse, не через это событие
        -- Но на всякий случай блокируем внешние клики
        return false
    end

    if is_mkt and not fh_mkt_cp_deep_scanning and fh_mkt_cp_deep_go_idx ~= nil then
        if button == 1 and listItem == fh_mkt_cp_deep_go_idx then
            fh_mkt_cp_deep_go_idx = nil
            fh_mkt_cp_deep_scanning = true
            fh_mkt_cp_deep_done     = 0
            sampAddChatMessage('[FH Market] {ffaa00}Углублённый скан запущен!', 0xFFFFFF)

            -- Получаем текущий текст диалога ДО того как он закроется
            local txt0 = sampGetDialogText() or ''
            local dlg0 = dialogId

            lua_thread.create(function()
                -- lua_thread START
                -- Даём диалогу остаться открытым (не закрываем его)
                -- Читаем страницы напрямую из открытого диалога
                -- fh_last_dlg_title обновляется в onShowDialog (sampGetDialogTitle не работает в coroutine)
                local function wait_for_list(timeout_ms, old_txt)
                    if not old_txt then
                        local wc = 0
                        while sampIsDialogActive() and sampGetCurrentDialogId() ~= 15073 and wc < 1500 do
                            wait(80); wc = wc + 80
                        end
                    else
                        -- Листание: просто ждём пока сервер обработает перелистание
                        wait(800)
                    end
                    local t = 0
                    while t < timeout_ms do
                        wait(80); t = t + 80
                        if sampIsDialogActive() and sampGetCurrentDialogId() == 15073 then
                            return sampGetCurrentDialogId(), sampGetDialogText() or ''
                        end
                    end
                    return nil, nil
                end

                local function wait_for_detail(timeout_ms)
                    local t = 0
                    while t < timeout_ms do
                        wait(80); t = t + 80
                        if sampIsDialogActive() then
                            local tt = fh_last_dlg_title or ''
                            if tt:find('Продажа товара') then
                                return sampGetCurrentDialogId(),
                                       sampGetDialogText() or '',
                                       tt
                            end
                        end
                    end
                    return nil, nil, nil
                end

                -- Стартуем со страницы которая уже открыта
                -- sampGetDialogText() всегда возвращает оригинальный текст от сервера
                local cur_dlg = dlg0
                local cur_txt = txt0

                -- Скрываем диалог от пользователя во время скана
                -- (диалог остаётся открытым на сервере, мы просто его прячем)
                local _was_main_open = MainWindow[0]
                MainWindow[0] = false

                while fh_mkt_cp_deep_scanning do
                    local page_items = fh_mkt_parse_cp_list(cur_txt, 5)
                    -- DBG: page_items count
                    if #page_items > 0 then
                                           -- прогресс без спама
                    end

                    if #page_items == 0 then
                        -- Остановка: на странице нет товаров, нечем листать вперёд
                        goto continue_deep
                    end

                    -- Кликаем на каждый товар страницы
                    for _, item in ipairs(page_items) do
                        if not fh_mkt_cp_deep_scanning then break end

                        -- click item
                        sampSendDialogResponse(cur_dlg, 1, item.idx - 2, 0)
                        wait(300)

                        -- Ждём детальный диалог
                        local det_dlg, det_txt, det_title = wait_for_detail(5000)
                        -- det_dlg received (или таймаут)
                        if det_dlg then
                            local detail = fh_mkt_parse_cp_detail(det_txt, det_title)
                            if detail and detail.name ~= '' and #detail.history > 0 then
                                fh_mkt_save_cp_detail(detail.name, detail.history)
                            end
                            fh_mkt_cp_deep_done = fh_mkt_cp_deep_done + 1
                            printStyledString('~w~FH deep: ~y~'..fh_mkt_cp_deep_done, 1000, 6)
                            -- Назад = Btn1 = button 1 (синяя левая кнопка на скрине)
                            sampSendDialogResponse(det_dlg, 1, 0, '')
                            wait(300)
                        else
                            -- Таймаут детали: возможно диалог уже открыт под другим id
                            fh_mkt_cp_deep_done = fh_mkt_cp_deep_done + 1
                            if sampIsDialogActive() then
                                local cid2 = sampGetCurrentDialogId()
                                if cid2 ~= 15073 then
                                    sampSendDialogResponse(cid2, 1, 0, '')
                                    wait(300)
                                end
                            end
                        end
                        -- В любом случае ждём возврата к списку
                        local nld, ntxt = wait_for_list(4000)
                        if nld then
                            cur_dlg = nld; cur_txt = ntxt
                        end
                    end

                    if not fh_mkt_cp_deep_scanning then break end

                    ::continue_deep::
                    -- Листаем вперёд (Следующая страница)
                    local cur_txt2 = sampIsDialogActive() and (sampGetDialogText() or '') or cur_txt

                    local next_i = fh_find_listitem(cur_txt2, 'Следующая страница')

                    if not next_i then
                        break
                    end
                    local cid = sampIsDialogActive() and sampGetCurrentDialogId() or cur_dlg
                    local old_page_txt = sampIsDialogActive() and sampGetDialogText() or cur_txt
                    local srv_idx = next_i - 2
                    sampSendDialogResponse(cid, 1, srv_idx, 0)
                    wait(600)
                    -- Передаём старый текст чтобы дождаться реальной смены страницы
                    local nld2, ntxt2 = wait_for_list(6000, old_page_txt)

                    if nld2 then cur_dlg = nld2; cur_txt = ntxt2
                    else break end
                end

                fh_mkt_cp_deep_scanning = false
                fh_mkt_save()
                -- Закрываем диалог и восстанавливаем окно
                if sampIsDialogActive() then
                    sampSendDialogResponse(sampGetCurrentDialogId(), 0, 0, '')
                end
                MainWindow[0] = _was_main_open
                sampAddChatMessage('[FH Market] {00cc00}Скан завершён! Товаров: '..fh_mkt_cp_deep_done, 0xFFFFFF)
                printStyledString('~w~FH DONE: ~g~'..fh_mkt_cp_deep_done, 3000, 6)
            end)

            -- НЕ закрываем диалог — пусть lua_thread работает с открытым
            -- Просто отменяем обработку этого клика (не отправляем на сервер)
            return false
        end
        -- Клик не на нашу кнопку — корректируем listItem (убираем 2 наши вставленные строки)
        if button == 1 and listItem > fh_mkt_cp_deep_go_idx then
            fh_mkt_cp_deep_go_idx = nil
            return { dialogId, button, listItem - 2, inputText }
        end
        fh_mkt_cp_deep_go_idx = nil
    end

    -- ===== SHALLOW СКАН: обработка клика =====
    if is_mkt and not fh_mkt_cp_scanning and fh_mkt_cp_go_idx ~= nil then
        if button == 1 and listItem == fh_mkt_cp_go_idx then
            local txt = sampGetDialogText() or ''
            local nxt_raw = fh_mkt_cp_prev_text or txt
            local nxt = fh_find_listitem(nxt_raw, 'Следующая страница')
            if nxt == nil then
                sampAddChatMessage('[FH Market] {ff4444}Ошибка: не найдена след. страница!', 0xFFFFFF)
                fh_mkt_cp_go_idx = nil
                return { dialogId, 0, listItem, inputText }
            end
            fh_mkt_cp_scanning  = true
            fh_mkt_cp_prev_text = txt
            sampAddChatMessage('[FH Market] {ffaa00}Запущен анализ цен. Не открывайте другие диалоги!', 0xFFFFFF)
            fh_mkt_parse_cp(txt)
            local tot = 0; for _ in pairs(fh_mkt_prices) do tot = tot + 1 end
            printStyledString('~w~FH scan p.1: ~r~' .. tot, 2000, 6)
            -- Убираем смещение от наших 2 кнопок для "Следующая страница"
            local fixed = nxt - 2
            fh_mkt_cp_go_idx = nil
            return { dialogId, 1, fixed, inputText }
        end
        -- Клик на другую строку — убираем смещение наших 2 кнопок
        local fixed2 = listItem - 2
        fh_mkt_cp_go_idx = nil
        return { dialogId, button, fixed2, inputText }
    end

    -- ===== FH AUTO MARKET: обработка кликов =====
    local is_auto_resp = (dialogId == 15376)
    if not is_auto_resp and sampIsDialogActive() then
        local ct_ar = (sampGetDialogTitle() or ''):gsub('{%x+}',''):match('^%s*(.-)%s*$') or ''
        is_auto_resp = ct_ar:find('Средняя цена автомобилей') ~= nil
    end

    -- Блокируем мануальные клики во время deep scan
    if is_auto_resp and fh_mkt_auto_deep_scanning then return false end

    -- ===== ГЛУБОКИЙ СКАН АВТО =====
    if is_auto_resp and not fh_mkt_auto_deep_scanning and fh_mkt_auto_deep_go_idx ~= nil then
        if button == 1 and listItem == fh_mkt_auto_deep_go_idx then
            fh_mkt_auto_deep_go_idx = nil
            fh_mkt_auto_deep_scanning = true
            fh_mkt_auto_deep_done = 0
            sampAddChatMessage('[FH Auto] {ffaa00}Углублённый скан авторынка запущен!', 0xFFFFFF)
            local txt0 = sampGetDialogText() or ''
            local dlg0 = dialogId
            lua_thread.create(function()
                local function wait_for_auto_list(timeout_ms, old_txt)
                    if not old_txt then
                        local wc = 0
                        while sampIsDialogActive() and sampGetCurrentDialogId() ~= 15376 and wc < 1500 do
                            wait(80); wc = wc + 80
                        end
                    else
                        wait(800)
                    end
                    local t = 0
                    while t < timeout_ms do
                        wait(80); t = t + 80
                        if sampIsDialogActive() and sampGetCurrentDialogId() == 15376 then
                            return sampGetCurrentDialogId(), sampGetDialogText() or ''
                        end
                    end
                    return nil, nil
                end
                local function wait_for_auto_detail(timeout_ms)
                    local t = 0
                    while t < timeout_ms do
                        wait(80); t = t + 80
                        if sampIsDialogActive() then
                            local tt = fh_last_dlg_title or ''
                            -- Диалог деталей авто -- заголовок содержит название авто (не 15376)
                            if sampGetCurrentDialogId() ~= 15376 then
                                return sampGetCurrentDialogId(), sampGetDialogText() or '', tt
                            end
                        end
                    end
                    return nil, nil, nil
                end
                local cur_dlg = dlg0
                local cur_txt = txt0
                local _was_main_open = MainWindow[0]
                MainWindow[0] = false
                while fh_mkt_auto_deep_scanning do
                    local page_items = fh_mkt_parse_auto_list(cur_txt)
                    if #page_items == 0 then
                        goto continue_auto_deep
                    end
                    for _, item in ipairs(page_items) do
                        if not fh_mkt_auto_deep_scanning then break end
                        sampSendDialogResponse(cur_dlg, 1, item.idx - 2, 0)
                        wait(300)
                        local det_dlg, det_txt, det_title = wait_for_auto_detail(5000)
                        if det_dlg and det_txt then
                            local detail = fh_mkt_parse_auto_detail(det_txt, det_title)
                            if detail and detail.name ~= '' and #detail.history > 0 then
                                fh_mkt_save_auto_detail(detail.name, detail.history)
                            else
                            end
                            fh_mkt_auto_deep_done = fh_mkt_auto_deep_done + 1
                            printStyledString('~w~FH Auto deep: ~y~'..fh_mkt_auto_deep_done, 1000, 6)
                            sampSendDialogResponse(det_dlg, 1, 0, '')
                            wait(300)
                        else
                            fh_mkt_auto_deep_done = fh_mkt_auto_deep_done + 1
                            if sampIsDialogActive() and sampGetCurrentDialogId() ~= 15376 then
                                sampSendDialogResponse(sampGetCurrentDialogId(), 1, 0, '')
                                wait(300)
                            end
                        end
                        local nld, ntxt = wait_for_auto_list(4000)
                        if nld then
                            cur_dlg = nld; cur_txt = ntxt
                        else
                        end
                    end
                    if not fh_mkt_auto_deep_scanning then break end
                    ::continue_auto_deep::
                    local cur_txt2 = sampIsDialogActive() and (sampGetDialogText() or '') or cur_txt
                    local next_i = fh_find_listitem(cur_txt2, 'Следующая страница')
                    if not next_i then break end
                    local cid = sampIsDialogActive() and sampGetCurrentDialogId() or cur_dlg
                    local old_txt2 = sampIsDialogActive() and sampGetDialogText() or cur_txt
                    sampSendDialogResponse(cid, 1, next_i - 2, 0)
                    wait(600)
                    local nld2, ntxt2 = wait_for_auto_list(6000, old_txt2)
                    if nld2 then cur_dlg = nld2; cur_txt = ntxt2
                    else break end
                end
                fh_mkt_auto_deep_scanning = false
                fh_mkt_save()
                if sampIsDialogActive() then
                    sampSendDialogResponse(sampGetCurrentDialogId(), 0, 0, '')
                end
                MainWindow[0] = _was_main_open
                sampAddChatMessage('[FH Auto] {00cc00}Углублённый скан завершён! Авто: '..fh_mkt_auto_deep_done, 0xFFFFFF)
                printStyledString('~w~FH Auto DONE: ~g~'..fh_mkt_auto_deep_done, 3000, 6)
            end)
            return false
        end
        if button == 1 and fh_mkt_auto_deep_go_idx and listItem > fh_mkt_auto_deep_go_idx then
            fh_mkt_auto_deep_go_idx = nil
            return { dialogId, button, listItem - 2, inputText }
        end
        fh_mkt_auto_deep_go_idx = nil
    end

    -- ===== ШАЛОВСКИЙ СКАН АВТО =====
    if is_auto_resp and not fh_mkt_auto_scanning and fh_mkt_auto_go_idx ~= nil then
        if button == 1 and listItem == fh_mkt_auto_go_idx then
            local txt = sampGetDialogText() or ''
            local nxt = fh_find_listitem(txt, 'Следующая страница')
            if nxt == nil then
                sampAddChatMessage('[FH Auto] {ff4444}Ошибка: нет след. страницы!', 0xFFFFFF)
                fh_mkt_auto_go_idx = nil
                return { dialogId, 0, listItem, inputText }
            end
            fh_mkt_auto_scanning  = true
            fh_mkt_auto_prev_text = txt
            fh_mkt_auto_page      = 1
            sampAddChatMessage('[FH Auto] {ffaa00}Скан авторынка запущен. Не открывайте другие диалоги!', 0xFFFFFF)
            fh_mkt_parse_auto(txt)
            local tot = 0; for _ in pairs(fh_mkt_auto) do tot = tot + 1 end
            printStyledString('~w~FH Auto p.1: ~r~' .. tot, 2000, 6)
            local fixed_a = nxt - 2  -- 2 вставленные строки
            fh_mkt_auto_go_idx = nil
            return { dialogId, 1, fixed_a, inputText }
        end
        fh_mkt_auto_go_idx = nil
        return { dialogId, button, listItem - 2, inputText }
    end
end

function sampev.onServerMessage(color, text)
    -- FH Market: auto trade log (MCR patterns + color check)
    do
        local paters = {
            -- Цвет -65281 (Вы успешно продали/купили)
            {c=-65281,  op='sell', pat='Вы успешно продали (.+) %((%d+) шт%.) торговцу ([%a_]+), .* ([%d,%.]+)',   item=1,qty=2,partner=3,price=4},
            {c=-65281,  op='sell', pat='Вы успешно продали (.+) торговцу ([%a_]+), .* ([%d,%.]+)',                     item=1,qty=nil,partner=2,price=3},
            {c=-65281,  op='buy',  pat='Вы успешно купили (.+) %((%d+) шт%.) у ([%a_]+) .* ([%d,%.]+)',                                 item=1,qty=2,partner=3,price=4},
            {c=-65281,  op='buy',  pat='Вы успешно купили (.+) у ([%a_]+) .* ([%d,%.]+)',                                                     item=1,qty=nil,partner=2,price=3},
            -- Цвет -1347440641 (Вы купили / NAME купил у вас)
            {c=-1347440641, op='sell', pat='([%a_]+) купил у вас (.+) %((%d+) шт%.%), .* ([%d,%.]+)',                                                         item=2,qty=3,partner=1,price=4},
            {c=-1347440641, op='sell', pat='([%a_]+) купил у вас (.+), .* ([%d,%.]+)',                                                                              item=2,qty=nil,partner=1,price=3},
            {c=-1347440641, op='buy',  pat='Вы купили (.+) %((%d+) шт%.) у игрока ([%a_]+) .* ([%d,%.]+)',                                item=1,qty=2,partner=3,price=4},
            {c=-1347440641, op='buy',  pat='Вы купили (.+) у игрока ([%a_]+) .* ([%d,%.]+)',                                                     item=1,qty=nil,partner=2,price=3},
        }
        if color and message then
            local m = message:gsub('{%x+}','')
            for _,p in ipairs(paters) do
                if color == p.c then
                    local r = {m:match(p.pat)}
                    if r[1] then
                        local item    = tostring(r[p.item] or ''):match('^%s*(.-)%s*$')
                        local qty     = p.qty and tonumber(r[p.qty]) or 1
                        local partner = tostring(r[p.partner] or ''):match('^%s*(.-)%s*$')
                        local price_s = tostring(r[p.price] or ''):gsub('[,%.%s]','')
                        local price   = tonumber(price_s)
                        if item ~= '' and price and price > 0 then
                            fh_mkt_record(item, qty, price, p.op, partner)
                            lua_thread.create(function() wait(300); fh_mkt_save() end)
                        end
                        break
                    end
                end
            end
        end
    end

    -- Парсим /ad объявления — определяем активную радиостанцию

    if not text then return end

    -- ===== \xcf\xc5\xd0\xc5\xd5\xc2\xc0\xd2 FH \xcc\xc0\xd0\xca\xc5\xd0\xc0 (\xe0\xe2\xf2\xee-\xe3\xeb\xe0\xe2\xe5\xed\xf1\xf2\xe2\xee) =====
    -- \xd4\xee\xf0\xec\xe0\xf2 \xec\xe0\xf0\xea\xe5\xf0\xe0: ?[FH:\xf0\xe0\xed\xe3:joined:\xed\xe8\xea]
    local fh_rank_s, fh_joined_s, fh_nick = text:match('\xE2\x80\x8B%[FH:(%d+):(%d+):([%a%d_%.]+)%]')
    if fh_nick then
        -- \xce\xe1\xed\xee\xe2\xeb\xff\xe5\xec \xf2\xe0\xe1\xeb\xe8\xf6\xf3 \xee\xed\xeb\xe0\xe9\xed
        fh_online[fh_nick] = {
            rank      = tonumber(fh_rank_s)  or 1,
            joined    = tonumber(fh_joined_s) or 0,
            last_seen = os.time()
        }
        -- \xd3\xe1\xe8\xf0\xe0\xe5\xec \xec\xe0\xf0\xea\xe5\xf0 \xe8\xe7 \xf2\xe5\xea\xf1\xf2\xe0
        local stripped = text:gsub(' ?\xE2\x80\x8B%[FH:%d+:%d+:[%a%d_%.]+%]', '')
        -- \xcf\xf0\xee\xe2\xe5\xf0\xff\xe5\xec: \xfd\xf2\xee \xef\xe8\xed\xe3 (\xf4\xf0\xe0\xe7\xe0 \xe8\xe7 \xed\xe0\xf8\xe5\xe3\xee \xf1\xef\xe8\xf1\xea\xe0) \xe8\xeb\xe8 \xf0\xe5\xe0\xeb\xfc\xed\xee\xe5 \xf1\xee\xee\xe1\xf9\xe5\xed\xe8\xe5?
        -- \xd3\xe1\xe8\xf0\xe0\xe5\xec \xf6\xe2\xe5\xf2\xee\xe2\xfb\xe5 \xf2\xe5\xe3\xe8 \xe8 \xef\xf0\xe5\xf4\xe8\xea\xf1 "[\xd1\xe5\xec\xfc\xff] Nick[ID]: "
        local clean = stripped:gsub('{%x+}', ''):gsub('%[.-%]%s*[%a%d_%.]+%[%d+%]:%s*', ''):match('^%s*(.-)%s*$') or ''
        local is_ping = (clean == '')
        if not is_ping then
            for _, phrase in ipairs(FH_PING_PHRASES) do
                if clean == phrase then is_ping = true; break end
            end
        end
        if is_ping then
            return false  -- \xef\xe8\xed\xe3 \x97 \xf1\xea\xf0\xfb\xe2\xe0\xe5\xec \xef\xee\xeb\xed\xee\xf1\xf2\xfc\xfe
        end
        return {color, stripped}  -- \xf0\xe5\xe0\xeb\xfc\xed\xee\xe5 \xf1\xee\xee\xe1\xf9\xe5\xed\xe8\xe5 \x97 \xef\xee\xea\xe0\xe7\xfb\xe2\xe0\xe5\xec \xe1\xe5\xe7 \xec\xe0\xf0\xea\xe5\xf0\xe0
    end

    -- \xd1\xf7\xb8\xf2\xf7\xe8\xea \xe8\xed\xe2\xe0\xe9\xf2\xee\xe2
        if text:find('\xef\xf0\xe8\xed\xff\xeb \xe2\xe0\xf8\xe5 \xef\xf0\xe5\xe4\xeb\xee\xe6\xe5\xed\xe8\xe5 \xe2\xf1\xf2\xf3\xef\xe8\xf2\xfc \xe2 \xf1\xe5\xec\xfc\xfe') then
        invite_session = invite_session + 1
        settings.general.invite_total = (settings.general.invite_total or 0) + 1
        settings.general.invite_unpaid = (settings.general.invite_unpaid or 0) + 1
        save_settings()
        log_event('\xcf\xf0\xe8\xed\xff\xeb \xe8\xed\xe2\xe0\xe9\xf2: +1 (\xe2\xf1\xe5\xe3\xee ' .. (settings.general.invite_total) .. ')')
        if settings.log_enabled and settings.log_enabled.invite then flog('invite', {type='\xc8\xed\xe2\xe0\xe9\xf2 \xef\xf0\xe8\xed\xff\xf2', nick='(\xe2\xe0\xf8 \xe8\xed\xe2\xe0\xe9\xf2)', total=tostring(settings.general.invite_total or 0)}) end
    end

    -- \xcf\xe5\xf0\xe5\xf5\xe2\xe0\xf2 \xee\xf2\xe2\xe5\xf2\xe0 /number \xe4\xeb\xff \xe7\xe2\xee\xed\xea\xe0 \xef\xee ID
    -- \xd4\xee\xf0\xec\xe0\xf2: "{\xd6\xc2\xc5\xd2}Nick_Name[ID]:    {\xd6\xc2\xc5\xd2}79001234567"
    if pending_call_nick then
        local phone = text:match('^{%x+}[%a_]+%[%d+%]:%s+{%x+}(%d+)$')
        if phone then
            local captured_nick = pending_call_nick
            pending_call_nick = nil
            lua_thread.create(function()
                wait(300)
                sampSendChat('/call ' .. phone)
                sampAddChatMessage('[Family Helper] {ffffff}\xc7\xe2\xee\xed\xe8\xec ' .. captured_nick .. ': ' .. phone, 0xFFA500)
            end)
            return false
        end
    end

    if pending_sms_nick then
        local phone = text:match('^{%x+}[%a_]+%[%d+%]:%s+{%x+}(%d+)$')
        if phone then
            local captured_nick = pending_sms_nick
            local captured_txt  = pending_sms_text
            pending_sms_nick = nil
            pending_sms_text = ''
            lua_thread.create(function()
                wait(300)
                sampSendChat('/sms ' .. phone .. ' ' .. captured_txt)
                sampAddChatMessage('[Family Helper] {ffffff}SMS -> ' .. captured_nick .. ' (' .. phone .. '): ' .. captured_txt, 0xFFA500)
            end)
            return false
        end
    end

    -- \xcb\xce\xc3: \xf7\xe8\xf1\xf2\xe8\xec \xf6\xe2\xe5\xf2\xe0 \xee\xe4\xe8\xed \xf0\xe0\xe7 \xe8 \xef\xe0\xf0\xf1\xe8\xec \xed\xe0\xe4\xb8\xe6\xed\xee
    local ct = text:gsub('{%x%x%x%x%x%x}', '')

    -- ========== \xc2\xd1\xc5 [\xd1\xe5\xec\xfc\xff (\xcd\xee\xe2\xee\xf1\xf2\xe8)] \xd1\xce\xc1\xdb\xd2\xc8\xdf ==========
    if ct:find('%[\xd1\xe5\xec\xfc') and ct:find('%(\xcd\xee\xe2\xee\xf1\xf2\xe8%)') then

        -- \xcf\xee\xef\xee\xeb\xed\xe8\xeb \xf1\xea\xeb\xe0\xe4 \xed\xe0 $
        local n, id, sum = ct:match('%[.+ %(\xcd\xee\xe2\xee\xf1\xf2\xe8%)%] ([%a_]+)%[(%d+)%]: *[\xcf\xef]\xee\xef\xee\xeb\xed\xe8\xeb \xf1\xea\xeb\xe0\xe4.+ \xed\xe0 %$(.+)')
        if n then
            if settings.log_enabled and settings.log_enabled.bank then flog('bank', {nick=n, id=id or '?', op='\xcf\xee\xef\xee\xeb\xed\xe8\xeb', sum=sum}) end
            if settings.log_enabled and settings.log_enabled.news then flog('news', {nick=n, msg='\xcf\xee\xef\xee\xeb\xed\xe8\xeb \xf1\xea\xeb\xe0\xe4 \xf1\xe5\xec\xfc\xe8 \xed\xe0 $'..sum}) end
            if settings.tg and settings.tg.enabled and settings.tg.ev_bank then
                tg_send_if(n, '[FH] \xc8\xe3\xf0\xee\xea '..n..' \xef\xee\xef\xee\xeb\xed\xe8\xeb \xf1\xea\xeb\xe0\xe4 \xf1\xe5\xec\xfc\xe8 \xed\xe0 $'..sum..'.') end
        end

        -- \xc2\xe7\xff\xeb/\xd1\xed\xff\xeb \xf1\xee \xf1\xea\xeb\xe0\xe4\xe0 $
        local n2, id2, sum2 = ct:match('%[.+ %(\xcd\xee\xe2\xee\xf1\xf2\xe8%)%] ([%a_]+)%[(%d+)%]: *[\xc2\xe2]\xe7\xff\xeb? %$(.+) \xf1\xee \xf1\xea\xeb\xe0\xe4\xe0')
        if not n2 then
            n2, id2, sum2 = ct:match('%[.+ %(\xcd\xee\xe2\xee\xf1\xf2\xe8%)%] ([%a_]+)%[(%d+)%]: *[\xd1\xf1]\xed\xff\xeb? %$(.+) \xf1\xee \xf1\xea\xeb\xe0\xe4\xe0')
        end
        if n2 then
            if settings.log_enabled and settings.log_enabled.bank then flog('bank', {nick=n2, id=id2 or '?', op='\xc2\xe7\xff\xeb', sum=sum2}) end
            if settings.log_enabled and settings.log_enabled.news then flog('news', {nick=n2, msg='\xc2\xe7\xff\xeb \xf1\xee \xf1\xea\xeb\xe0\xe4\xe0 $'..sum2}) end
            if settings.tg and settings.tg.enabled and settings.tg.ev_bank then
                tg_send_if(n2, '[FH] \xc8\xe3\xf0\xee\xea '..n2..' \xf1\xed\xff\xeb \xf1\xee \xf1\xea\xeb\xe0\xe4\xe0 \xf1\xe5\xec\xfc\xe8 $'..sum2..'.') end
        end

        -- \xce\xe1\xec\xe5\xed\xff\xeb \xf2\xe0\xeb\xee\xed\xfb \xed\xe0 \xf0\xe5\xef\xf3\xf2\xe0\xf6\xe8\xfe
        local nt, talons, repa = ct:match('%[.+ %(\xcd\xee\xe2\xee\xf1\xf2\xe8%)%] ([%a_]+)%[%d+%]: *\xee\xe1\xec\xe5\xed\xff\xeb (%d+) \xf2\xe0\xeb\xee\xed\xee\xe2 \xed\xe0 (%d+) \xee\xf7\xea\xee\xe2 \xf0\xe5\xef\xf3\xf2\xe0\xf6\xe8\xe8')
        if nt then
            if settings.log_enabled and settings.log_enabled.coins then flog('coins', {nick=nt, msg='\xee\xe1\xec\xe5\xed\xff\xeb '..talons..' \xf2\xe0\xeb\xee\xed\xee\xe2 -> +'..repa..' \xf0\xe5\xef\xfb'}) end
            if settings.log_enabled and settings.log_enabled.news then flog('news', {nick=nt, msg='\xee\xe1\xec\xe5\xed\xff\xeb '..talons..' \xf2\xe0\xeb\xee\xed\xee\xe2 \xed\xe0 '..repa..' \xf0\xe5\xef\xf3\xf2\xe0\xf6\xe8\xe8'}) end
            if settings.tg and settings.tg.enabled and settings.tg.ev_coins then
                tg_send_if(nt, '[FH] \xc8\xe3\xf0\xee\xea '..nt..' \xee\xe1\xec\xe5\xed\xff\xeb '..talons..' \xf2\xe0\xeb\xee\xed\xee\xe2 \xed\xe0 +'..repa..' \xf0\xe5\xef\xf3\xf2\xe0\xf6\xe8\xe8.') end
            -- \xd1\xf7\xb8\xf2\xf7\xe8\xea \xf2\xe0\xeb\xee\xed\xee\xe2 \xe4\xeb\xff \xef\xf0\xe5\xec\xe8\xe9
            if not settings.talons_stats then settings.talons_stats = {} end
            local talon_count = tonumber(talons) or 0
            settings.talons_stats[nt] = (settings.talons_stats[nt] or 0) + talon_count
            save_settings()
            -- \xc0\xe2\xf2\xee-\xef\xee\xe7\xe4\xf0\xe0\xe2\xeb\xe5\xed\xe8\xe5 \xf1 \xee\xe1\xec\xe5\xed\xee\xec \xf2\xe0\xeb\xee\xed\xee\xe2
            if settings.talon_congrats and settings.talon_congrats.enabled then
                local tlcitems = settings.talon_congrats.items or {}
                local use_fam_tlc = settings.talon_congrats.use_fam
                if #tlcitems > 0 then
                    lua_thread.create(function()
                        local p = use_fam_tlc and '/fam ' or ''
                        for _, tlcitem in ipairs(tlcitems) do
                            local msg = tlcitem.text:gsub('{player_name}', nt)
                            sampSendChat(p .. msg)
                            wait((tlcitem.waiting or 1.5) * 1000)
                        end
                    end)
                end
            end
        end

        -- \xc2\xfb\xef\xee\xeb\xed\xe8\xeb \xe5\xe6\xe5\xe4\xed\xe5\xe2\xed\xfb\xe9 \xea\xe2\xe5\xf1\xf2
        local nq, exp, repa2 = ct:match('%[.+ %(\xcd\xee\xe2\xee\xf1\xf2\xe8%)%] ([%a_]+)%[%d+%]: *\xe2\xfb\xef\xee\xeb\xed\xe8\xeb \xe5\xe6\xe5\xe4\xed\xe5\xe2\xed\xee\xe5 \xe7\xe0\xe4\xe0\xed\xe8\xe5.+ \xef\xee\xeb\xf3\xf7\xe8\xeb\xe0 (%d+) \xc5\xd5\xd0 \xe8 (%d+) \xf0\xe5\xef\xf3\xf2\xe0\xf6\xe8\xe8')
        if nq then
            if settings.log_enabled and settings.log_enabled.quest then flog('quest', {nick=nq, msg='\xea\xe2\xe5\xf1\xf2: +'..exp..' XP, +'..repa2..' \xf0\xe5\xef\xfb'}) end
            if settings.log_enabled and settings.log_enabled.news then flog('news', {nick=nq, msg='\xe2\xfb\xef\xee\xeb\xed\xe8\xeb \xea\xe2\xe5\xf1\xf2: +'..exp..' XP +'..repa2..' \xf0\xe5\xef\xfb'}) end
            if settings.tg and settings.tg.enabled and settings.tg.ev_quest then
                tg_send_if(nq, '[FH] \xc8\xe3\xf0\xee\xea '..nq..' \xe2\xfb\xef\xee\xeb\xed\xe8\xeb \xe5\xe6\xe5\xe4\xed\xe5\xe2\xed\xfb\xe9 \xea\xe2\xe5\xf1\xf2. +'..exp..' XP, +'..repa2..' \xf0\xe5\xef\xfb.') end
        end

        -- \xc8\xf1\xef\xee\xeb\xfc\xe7\xee\xe2\xe0\xeb \xf1\xe5\xf0\xf2\xe8\xf4\xe8\xea\xe0\xf2 \xf0\xe5\xef\xf3\xf2\xe0\xf6\xe8\xe8
        local nc, cert_pts = ct:match('%[.+ %(\xcd\xee\xe2\xee\xf1\xf2\xe8%)%] ([%a_]+)%[%d+%]: *\xe8\xf1\xef\xee\xeb\xfc\xe7\xee\xe2\xe0\xeb \xf1\xe5\xf0\xf2\xe8\xf4\xe8\xea\xe0\xf2.+%(+(%d+)%)')
        if nc then
            if settings.log_enabled and settings.log_enabled.news then flog('news', {nick=nc, msg='\xe8\xf1\xef\xee\xeb\xfc\xe7\xee\xe2\xe0\xeb \xf1\xe5\xf0\xf2\xe8\xf4\xe8\xea\xe0\xf2 \xf0\xe5\xef\xf3\xf2\xe0\xf6\xe8\xe8 (+'..cert_pts..')'}) end
        end

        -- \xcf\xf0\xe8\xe3\xeb\xe0\xf1\xe8\xeb \xed\xee\xe2\xee\xe3\xee \xf7\xeb\xe5\xed\xe0
        local n_inv, n_new = ct:match('%[.+ %(\xcd\xee\xe2\xee\xf1\xf2\xe8%)%] ([%a_]+)%[%d+%]: *\xef\xf0\xe8\xe3\xeb\xe0\xf1\xe8\xeb.+ \xed\xee\xe2\xee\xe3\xee \xf7\xeb\xe5\xed\xe0: ([%a_]+)')
        if n_new then
            if settings.log_enabled and settings.log_enabled.invite then flog('invite', {type='\xcf\xf0\xe8\xe3\xeb\xe0\xf8\xb8\xed', nick=n_new, by=n_inv or ''}) end
            if settings.log_enabled and settings.log_enabled.news then flog('news', {nick=n_inv or '', msg='\xef\xf0\xe8\xe3\xeb\xe0\xf1\xe8\xeb '..n_new}) end
            -- \xd1\xf2\xe0\xf2\xe8\xf1\xf2\xe8\xea\xe0 \xe8\xed\xe2\xe0\xe9\xf2\xee\xe2 \xef\xee \xea\xe0\xe6\xe4\xee\xec\xf3 \xe8\xe3\xf0\xee\xea\xf3
            if n_inv and n_inv ~= '' then
                if not settings.invite_stats then settings.invite_stats = {} end
                local st = settings.invite_stats[n_inv]
                if not st then st = {total=0, today=0, week=0, month=0, day_key='', week_key='', month_key=''} end
                local dk = os.date('%d.%m.%Y')
                local wk = os.date('%V.%G')
                local mk = os.date('%m.%Y')
                if st.day_key   ~= dk then st.today = 0; st.day_key   = dk end
                if st.week_key  ~= wk then st.week  = 0; st.week_key  = wk end
                if st.month_key ~= mk then st.month = 0; st.month_key = mk end
                st.total = (st.total or 0) + 1
                st.today = (st.today or 0) + 1
                st.week  = (st.week  or 0) + 1
                st.month = (st.month or 0) + 1
                settings.invite_stats[n_inv] = st
                save_settings()
                -- \xc0\xe2\xf2\xee\xee\xf2\xef\xf0\xe0\xe2\xea\xe0 \xe2 \xd2\xc3
                if settings.tg and settings.tg.enabled then
                    if n_inv == my_nick() then
                        -- \xd1\xe2\xee\xe9 \xe8\xed\xe2\xe0\xe9\xf2 \x97 \xef\xee\xeb\xed\xfb\xe9 \xee\xf2\xf7\xb8\xf2 \xf1\xee \xf1\xf2\xe0\xf2\xe8\xf1\xf2\xe8\xea\xee\xe9
                        local lines = {
                            '[FH] ' .. n_inv .. ' \xcf\xf0\xe8\xed\xff\xeb \xe8\xe3\xf0\xee\xea\xe0 ' .. n_new .. ' (\xe8\xed\xe2\xe0\xe9\xf2\xee\xe2: ' .. (st.total or 0) .. ')',
                            string.rep('-', 25),
                            '\xd1\xe5\xe3\xee\xe4\xed\xff:   ' .. (st.today or 0),
                            '\xcd\xe5\xe4\xe5\xeb\xff:    ' .. (st.week  or 0),
                            '\xcc\xe5\xf1\xff\xf6:     ' .. (st.month or 0),
                            '\xc2\xf1\xb8 \xe2\xf0\xe5\xec\xff: ' .. (st.total or 0),
                        }
                        tg_send(table.concat(lines, '\n'))
                    elseif settings.tg.ev_invite then
                        -- \xd7\xf3\xe6\xee\xe9 \xe8\xed\xe2\xe0\xe9\xf2 \x97 \xef\xf0\xee\xf1\xf2\xee\xe5 \xf3\xe2\xe5\xe4\xee\xec\xeb\xe5\xed\xe8\xe5 (\xf2\xee\xeb\xfc\xea\xee \xe5\xf1\xeb\xe8 \xf0\xee\xeb\xfc main)
                        tg_send_if(n_inv, '[FH] \xc8\xe3\xf0\xee\xea '..n_inv..' \xef\xf0\xe8\xe3\xeb\xe0\xf1\xe8\xeb '..n_new..' \xe2 \xf1\xe5\xec\xfc\xfe.')
                    end
                end
            end
        end

        -- \xc2\xf1\xf2\xf3\xef\xe8\xeb \xe2 \xf1\xe5\xec\xfc\xfe
        local n_join = ct:match('%[.+ %(\xcd\xee\xe2\xee\xf1\xf2\xe8%)%] ([%a_]+)%[%d+%]: *\xe2\xf1\xf2\xf3\xef\xe8\xeb')
        if n_join then
            if settings.log_enabled and settings.log_enabled.invite then flog('invite', {type='\xc2\xf1\xf2\xf3\xef\xe8\xeb', nick=n_join}) end
            if settings.log_enabled and settings.log_enabled.news then flog('news', {nick=n_join, msg='\xe2\xf1\xf2\xf3\xef\xe8\xeb \xe2 \xf1\xe5\xec\xfc\xfe'}) end
            if settings.tg and settings.tg.enabled and settings.tg.ev_join then
                tg_send_if(n_inv or '', '[FH] \xc8\xe3\xf0\xee\xea '..n_join..' \xe2\xf1\xf2\xf3\xef\xe8\xeb \xe2 \xf1\xe5\xec\xfc\xfe.') end
        end

        -- \xd1\xe0\xec\xee\xf1\xf2\xee\xff\xf2\xe5\xeb\xfc\xed\xee \xef\xee\xea\xe8\xed\xf3\xeb \xf1\xe5\xec\xfc\xfe
        local n_left = ct:match('%[.+ %(\xcd\xee\xe2\xee\xf1\xf2\xe8%)%] ([%a_]+)%[%d+%]: *\xf1\xe0\xec\xee\xf1\xf2\xee\xff\xf2\xe5\xeb\xfc\xed\xee \xef\xee\xea\xe8\xed\xf3\xeb')
        if n_left then
            if settings.log_enabled and settings.log_enabled.invite then flog('invite', {type='\xcf\xee\xea\xe8\xed\xf3\xeb', nick=n_left}) end
            if settings.log_enabled and settings.log_enabled.news then flog('news', {nick=n_left, msg='\xf1\xe0\xec\xee\xf1\xf2\xee\xff\xf2\xe5\xeb\xfc\xed\xee \xef\xee\xea\xe8\xed\xf3\xeb \xf1\xe5\xec\xfc\xfe'}) end
            if settings.tg and settings.tg.enabled and settings.tg.ev_leave then
                tg_send_if('', '[FH] \xc8\xe3\xf0\xee\xea '..n_left..' \xf1\xe0\xec\xee\xf1\xf2\xee\xff\xf2\xe5\xeb\xfc\xed\xee \xef\xee\xea\xe8\xed\xf3\xeb \xf1\xe5\xec\xfc\xfe!') end
        end

        -- \xca\xe8\xea \xee\xf4\xf4\xeb\xe0\xe9\xed / \xee\xed\xeb\xe0\xe9\xed
        local n_kicker, n_kicked = ct:match('%[.+ %(\xcd\xee\xe2\xee\xf1\xf2\xe8%)%] ([%a_]+)%[%d+%]: *\xe2 \xee\xf4\xf4\xeb\xe0\xe9\xed\xe5 \xe2\xfb\xe3\xed\xe0\xeb \xe8\xe3\xf0\xee\xea\xe0 ([%a_]+)')
        local kick_offline = n_kicked ~= nil
        if not n_kicked then
            n_kicker, n_kicked = ct:match('%[.+ %(\xcd\xee\xe2\xee\xf1\xf2\xe8%)%] ([%a_]+)%[%d+%]: *\xe2\xfb\xe3\xed\xe0\xeb \xe8\xe3\xf0\xee\xea\xe0 ([%a_]+)')
        end
        if n_kicked then
            if settings.log_enabled and settings.log_enabled.invite then flog('invite', {type='\xca\xe8\xea', nick=n_kicked, by=n_kicker or ''}) end
            if settings.log_enabled and settings.log_enabled.news then
                local kick_msg = kick_offline and ('\xe2 \xee\xf4\xf4\xeb\xe0\xe9\xed\xe5 \xea\xe8\xea\xed\xf3\xeb '..n_kicked..' \xe8\xe7 \xf1\xe5\xec\xfc\xe8') or ('\xea\xe8\xea\xed\xf3\xeb '..n_kicked..' \xe8\xe7 \xf1\xe5\xec\xfc\xe8')
                flog('news', {nick=n_kicker or '', msg=kick_msg})
            end
            if settings.tg and settings.tg.enabled and settings.tg.ev_leave then
                local tg_kick_msg = kick_offline
                    and ('[FH] \xc8\xe3\xf0\xee\xea '..(n_kicker or '?')..' \xe2 \xee\xf4\xf4\xeb\xe0\xe9\xed\xe5 \xe2\xfb\xe3\xed\xe0\xeb \xe8\xe3\xf0\xee\xea\xe0 '..n_kicked..' \xe8\xe7 \xf1\xe5\xec\xfc\xe8!')
                    or  ('[FH] \xc8\xe3\xf0\xee\xea '..(n_kicker or '?')..' \xe2\xfb\xe3\xed\xe0\xeb \xe8\xe3\xf0\xee\xea\xe0 '..n_kicked..' \xe8\xe7 \xf1\xe5\xec\xfc\xe8!')
                tg_send_if(n_kicker or '', tg_kick_msg)
            end
        end

        -- \xcc\xf3\xf2 \xf1\xe5\xec\xe5\xe9\xed\xee\xe3\xee \xf7\xe0\xf2\xe0
        local n_muter, n_muted, dur, reason =
            ct:match('%[.+ %(\xcd\xee\xe2\xee\xf1\xf2\xe8%)%] ([%a_]+)%[%d+%]: *\xe2\xfb\xe4\xe0\xeb \xe1\xe0\xed \xf1\xe5\xec\xe5\xe9\xed\xee\xe3\xee \xf7\xe0\xf2\xe0 ([%a_]+)%[%d+%], \xed\xe0 (%d+)\xec\xe8\xed, \xef\xf0\xe8\xf7\xe8\xed\xe0: (.*)')
        if n_muted then
            if settings.log_enabled and settings.log_enabled.mute then flog('mute', {nick=n_muted, by=n_muter or '?', duration=dur or '?', reason=reason or ''}) end
            if settings.log_enabled and settings.log_enabled.news then flog('news', {nick=n_muter or '', msg='\xec\xf3\xf2 '..n_muted..' \xed\xe0 '..dur..'\xec\xe8\xed: '..(reason or '')}) end
            if settings.tg and settings.tg.enabled and settings.tg.ev_mute then
                tg_send_if(n_muter or '', '[FH] \xc8\xe3\xf0\xee\xea '..(n_muter or '?')..' \xe2\xfb\xe4\xe0\xeb \xec\xf3\xf2 \xe8\xe3\xf0\xee\xea\xf3 '..n_muted..' \xed\xe0 '..(dur or '?')..' \xec\xe8\xed. \xcf\xf0\xe8\xf7\xe8\xed\xe0: '..(reason or '\x97')) end
        end

        -- \xcd\xe0\xe7\xed\xe0\xf7\xe8\xeb \xe7\xe0\xec\xe5\xf1\xf2\xe8\xf2\xe5\xeb\xff
        local n_ldr, n_zam = ct:match('%[.+ %(\xcd\xee\xe2\xee\xf1\xf2\xe8%)%] ([%a_]+)%[%d+%]: *\xed\xe0\xe7\xed\xe0\xf7\xe8\xeb ([%a_]+)%[%d+%] \xe7\xe0\xec\xe5\xf1\xf2\xe8\xf2\xe5\xeb\xe5\xec')
        if n_zam then
            if settings.log_enabled and settings.log_enabled.rank then flog('rank', {nick=n_zam, rank='\xe7\xe0\xec', by=n_ldr or ''}) end
            if settings.log_enabled and settings.log_enabled.news then flog('news', {nick=n_ldr or '', msg=n_zam..' \xed\xe0\xe7\xed\xe0\xf7\xe5\xed \xe7\xe0\xec\xe5\xf1\xf2\xe8\xf2\xe5\xeb\xe5\xec'}) end
        end

        -- \xd1\xed\xff\xeb \xf1 \xef\xee\xf1\xf2\xe0 \xe7\xe0\xec\xe5\xf1\xf2\xe8\xf2\xe5\xeb\xff
        local n_ldr2, n_zam2 = ct:match('%[.+ %(\xcd\xee\xe2\xee\xf1\xf2\xe8%)%] ([%a_]+)%[%d+%]: *\xf1\xed\xff\xeb ([%a_]+) \xf1 \xef\xee\xf1\xf2\xe0 \xe7\xe0\xec\xe5\xf1\xf2\xe8\xf2\xe5\xeb\xff')
        if n_zam2 then
            if settings.log_enabled and settings.log_enabled.news then flog('news', {nick=n_ldr2 or '', msg=n_zam2..' \xf1\xed\xff\xf2 \xf1 \xef\xee\xf1\xf2\xe0 \xe7\xe0\xec\xe0'}) end
        end

        -- \xd3\xf1\xf2\xe0\xed\xee\xe2\xe8\xeb \xf0\xe0\xed\xe3 \xe8\xe3\xf0\xee\xea\xf3
        local n_admin_r, n_rank_num = ct:match('%[.+ %(\xcd\xee\xe2\xee\xf1\xf2\xe8%)%] ([%a_]+)%[%d+%]: *\xf3\xf1\xf2\xe0\xed\xee\xe2\xe8\xeb \xf0\xe0\xed\xe3 (%d+)')
        local n_rank_target = ct:match('\xe8\xe3\xf0\xee\xea\xf3 ([%a_]+)%[')
        if n_admin_r and n_rank_num and n_rank_target then
            if settings.log_enabled and settings.log_enabled.rank then flog('rank', {nick=n_rank_target, rank=n_rank_num, by=n_admin_r}) end
            if settings.log_enabled and settings.log_enabled.news then flog('news', {nick=n_admin_r, msg='\xf0\xe0\xed\xe3 '..n_rank_num..' -> '..n_rank_target}) end
        end

    -- [\xcd\xee\xe2\xee\xf1\xf2\xe8 \xd1\xe5\xec\xfc\xe8] \xf3\xf0\xee\xe2\xe5\xed\xfc (\xe4\xf0\xf3\xe3\xee\xe9 \xf4\xee\xf0\xec\xe0\xf2!)
    elseif ct:find('%[\xcd\xee\xe2\xee\xf1\xf2\xe8 \xd1\xe5\xec\xfc\xe8%]') then
        local n_lvl, lvl = ct:match('%[\xcd\xee\xe2\xee\xf1\xf2\xe8 \xd1\xe5\xec\xfc\xe8%] \xd7\xeb\xe5\xed \xf1\xe5\xec\xfc\xe8: ([%a_]+)%[%d+%] \xe4\xee\xf1\xf2\xe8\xe3 (%d+) \xf3\xf0\xee\xe2\xed\xff')
        if n_lvl then
            if settings.log_enabled and settings.log_enabled.level then flog('level', {nick=n_lvl, lvl=lvl}) end
            if settings.log_enabled and settings.log_enabled.news then flog('news', {nick=n_lvl, msg='\xe4\xee\xf1\xf2\xe8\xe3 '..lvl..' \xf3\xf0\xee\xe2\xed\xff'}) end
            if settings.tg and settings.tg.enabled and settings.tg.ev_level then
                tg_send_if('', '[FH] \xc8\xe3\xf0\xee\xea '..n_lvl..' \xe4\xee\xf1\xf2\xe8\xe3 '..lvl..' \xf3\xf0\xee\xe2\xed\xff.') end
            -- \xd4\xe5\xe4\xe8\xec \xe2 \xe1\xe0\xf2\xf7 \xef\xee\xe7\xe4\xf0\xe0\xe2\xeb\xe5\xed\xe8\xe9
            if settings.general.auto_congrats then
                local already = false
                for _, n in ipairs(congrats_batch) do
                    if n == n_lvl then already = true; break end
                end
                if not already then table.insert(congrats_batch, n_lvl) end
                if not congrats_batch_timer then congrats_batch_timer = os.time() end
            end
        end

    -- [\xd1\xe5\xec\xfc\xff] \xee\xe1\xfb\xf7\xed\xfb\xe9 \xf7\xe0\xf2 (\xed\xe5 \xcd\xee\xe2\xee\xf1\xf2\xe8)
    elseif ct:find('%[\xd1\xe5\xec\xfc') then
        local chat_nick = ct:match('([%a_][%a%d_]+)%[%d+%]:%s*.+')
        local chat_msg  = ct:match('[%a_][%a%d_]+%[%d+%]:%s*(.*)')
        if chat_nick and chat_msg and chat_msg ~= '' then
            chat_msg = chat_msg:match('^%s*(.-)%s*$')
            if settings.log_enabled and settings.log_enabled.chat then
                flog('chat', {nick=chat_nick, msg=chat_msg})
            end
        end
    end
    -- \xc1\xeb\xe0\xe3\xee\xe4\xe0\xf0\xed\xee\xf1\xf2\xfc \xe7\xe0 \xf1\xe5\xec\xe5\xe9\xed\xfb\xe5 \xec\xee\xed\xe5\xf2\xfb / \xf2\xe0\xeb\xee\xed\xfb
    -- Arizona RP: "\xc8\xe3\xf0\xee\xea X \xee\xe1\xec\xe5\xed\xff\xeb N \xf1\xe5\xec\xe5\xe9\xed\xfb\xf5 \xec\xee\xed\xe5\xf2" / "\xef\xe5\xf0\xe5\xe4\xe0\xeb N \xec\xee\xed\xe5\xf2 \xe2 \xf1\xe5\xec\xe5\xe9\xed\xfb\xe9 \xe1\xe0\xed\xea"
    local coins_nick = nil
    coins_nick = coins_nick or text:match('([%a_]+) \xee\xe1\xec\xe5\xed\xff\xeb %d+ \xf1\xe5\xec\xe5\xe9\xed')
    coins_nick = coins_nick or text:match('([%a_]+) \xef\xe5\xf0\xe5\xe4\xe0\xeb %d+ \xf1\xe5\xec\xe5\xe9\xed')
    coins_nick = coins_nick or text:match('([%a_]+) \xf1\xe4\xe0\xeb %d+ \xf1\xe5\xec\xe5\xe9\xed')
    coins_nick = coins_nick or text:match('([%a_]+) \xe2\xed\xb8\xf1 %d+ \xec\xee\xed\xe5\xf2 \xe2 \xf1\xe5\xec\xe5\xe9\xed\xfb\xe9')
    if coins_nick and (settings.coins_thanks and settings.coins_thanks.enabled) then
        local items = settings.coins_thanks and settings.coins_thanks.items or {}
        if #items > 0 then
            local use_fam = settings.coins_thanks.use_fam
            lua_thread.create(function()
                for _, item in ipairs(items) do
                    wait(math.floor((item.waiting or 1.0) * 1000))
                    local msg = (item.text or ''):gsub('{player_name}', coins_nick)
                    msg = msg:gsub('{my_name}', settings.family_info.my_name or '')
                    msg = msg:gsub('{family_name}', settings.family_info.family_name or '')
                    if msg ~= '' then
                        if use_fam then msg = '/fam ' .. msg end
                        sampSendChat(msg)
                    end
                end
            end)
            log_event('\xcc\xee\xed\xe5\xf2\xfb \xee\xf2: ' .. coins_nick)
            if settings.log_enabled and settings.log_enabled.coins then flog('coins', {nick=coins_nick}) end
            if not settings.coins_stats then settings.coins_stats = {} end
            settings.coins_stats[coins_nick] = (settings.coins_stats[coins_nick] or 0) + 1
            save_settings()
            if settings.tg and settings.tg.enabled and settings.tg.ev_coins then
                tg_send_if(coins_nick, '[FH] \xc8\xe3\xf0\xee\xea ' .. coins_nick .. ' \xf1\xe4\xe0\xeb \xf1\xe5\xec\xe5\xe9\xed\xfb\xe5 \xec\xee\xed\xe5\xf2\xfb.')
            end
        end
    end

    -- \xc0\xe2\xf2\xee-\xef\xf0\xe8\xe2\xe5\xf2\xf1\xf2\xe2\xe8\xe5 (\xed\xee\xe2\xfb\xe9 \xf7\xeb\xe5\xed \xf1\xe5\xec\xfc\xe8)
    if settings.general.auto_welcome then
        local nm = text:match('([%a][%w_]+) \xe2\xf1\xf2\xf3\xef\xe8\xeb%(\xe0%) \xe2 \xe2\xe0\xf8\xf3 \xf1\xe5\xec\xfc\xfe')
            or text:match('([%a][%w_]+)%[%d+%] \xef\xf0\xe8\xed\xff\xf2%(\xe0%) \xe2 \xf1\xe5\xec\xfc\xfe')
            or text:match('\xef\xf0\xe8\xe3\xeb\xe0\xf1\xe8\xeb \xe2 \xf1\xe5\xec\xfc\xfe \xed\xee\xe2\xee\xe3\xee \xf7\xeb\xe5\xed\xe0: ([%a][%w_]+)')
            or text:match('(.+) \xef\xf0\xe8\xed\xff\xf2%(\xe0%) \xe2 \xf1\xe5\xec\xfc\xfe')
            or text:match('(.+) \xc2\xf1\xf2\xf3\xef\xe8\xeb%(\xe0%) \xe2 \xe2\xe0\xf8\xf3 \xf1\xe5\xec\xfc\xfe')
            or text:match('\xef\xf0\xe8\xe3\xeb\xe0\xf1\xe8\xeb \xe2 \xf1\xe5\xec\xfc\xfe \xed\xee\xe2\xee\xe3\xee \xf7\xeb\xe5\xed\xe0: (.+)')
        if nm then
            nm = nm:gsub('{%x+}', ''):gsub('%[%d+%]', ''):gsub('%s+', ''):match('^%s*(.-)%s*$') or ''
            lua_thread.create(function()
                local p = settings.welcome.use_fam and '/fam ' or ''
                local vars = settings.welcome.variants or {}
                local idx = (settings.welcome.variant_idx or 0) % #vars + 1
                settings.welcome.variant_idx = idx
                save_settings()
                local chosen = vars[idx] or vars[1] or {}
                -- \xc0\xe2\xf2\xee-\xe3\xeb\xe0\xe2\xe5\xed\xf1\xf2\xe2\xee: \xef\xe8\xed\xe3 \xef\xf0\xe8 \xf1\xee\xe1\xfb\xf2\xe8\xe8 (\xed\xe5 \xe1\xeb\xee\xea\xe8\xf0\xf3\xe5\xf2 \xef\xf0\xe8\xe2\xe5\xf2\xf1\xf2\xe2\xe8\xe5)
                if settings.tg and settings.tg.auto_role then
                    fh_update_self()
                    fh_send_ping()
                end
                local first = true
                for _, item in ipairs(chosen.items or {}) do
                    if item.text and item.text ~= '' then
                        wait((item.waiting or 1.5) * 1000)
                        local msg_text = p .. processText(item.text, nil):gsub('{player_name}', nm)
                        -- \xc2 \xef\xe5\xf0\xe2\xee\xe5 \xf1\xee\xee\xe1\xf9\xe5\xed\xe8\xe5 \xe2\xf8\xe8\xe2\xe0\xe5\xec \xec\xe0\xf0\xea\xe5\xf0 (\xed\xe5\xe2\xe8\xe4\xe8\xec \xe4\xeb\xff \xeb\xfe\xe4\xe5\xe9)
                        if first and settings.tg and settings.tg.auto_role then
                            msg_text = msg_text .. ' \xE2\x80\x8B[FH:' .. fh_my_rank_num() .. ':' .. fh_joined .. ':' .. (my_nick() or '') .. ']'
                            first = false
                        end
                        sampSendChat(msg_text)
                    end
                end
            end)
        end
    end

    -- \xc0\xe2\xf2\xee-\xef\xee\xe7\xe4\xf0\xe0\xe2\xeb\xe5\xed\xe8\xe5 (\xed\xee\xe2\xfb\xe9 \xf3\xf0\xee\xe2\xe5\xed\xfc)
    -- \xc8\xf1\xef\xee\xeb\xfc\xe7\xf3\xe5\xec (.+) \xea\xe0\xea \xe2 welcome \x97 \xe1\xe5\xe7 ^ \xff\xea\xee\xf0\xff, Arizona \xf8\xeb\xb8\xf2 "{\xf6\xe2\xe5\xf2}\xcd\xe8\xea \xef\xee\xe2\xfb\xf1\xe8\xeb(\xe0) \xf1\xe2\xee\xe9 \xf3\xf0\xee\xe2\xe5\xed\xfc \xe4\xee N"
    if settings.general.auto_congrats then
        local lp = nil
        local lp_lvl = nil
        -- \xd4\xee\xf0\xec\xe0\xf2 raw: {\xf6\xe2\xe5\xf2}Nick[ID] \xef\xee\xe2\xfb\xf1\xe8\xeb(\xe0) \xf1\xe2\xee\xe9 \xf3\xf0\xee\xe2\xe5\xed\xfc \xe4\xee N
        if not lp then lp, lp_lvl = text:match('(.+) \xef\xee\xe2\xfb\xf1\xe8\xeb%(\xe0%) \xf1\xe2\xee\xe9 \xf3\xf0\xee\xe2\xe5\xed\xfc \xe4\xee (%d+)') end
        if not lp then lp, lp_lvl = text:match('(.+) \xef\xee\xe2\xfb\xf1\xe8\xeb \xf1\xe2\xee\xe9 \xf3\xf0\xee\xe2\xe5\xed\xfc \xe4\xee (%d+)') end
        if not lp then lp, lp_lvl = text:match('(.+) \xef\xee\xeb\xf3\xf7\xe8\xeb%(\xe0%) \xed\xee\xe2\xfb\xe9 \xf3\xf0\xee\xe2\xe5\xed\xfc[%s%-]*(%d*)') end
        if not lp then lp, lp_lvl = text:match('(.+) \xef\xee\xeb\xf3\xf7\xe8\xeb \xed\xee\xe2\xfb\xe9 \xf3\xf0\xee\xe2\xe5\xed\xfc[%s%-]*(%d*)') end
        if not lp then lp = text:match('(.+) \xe4\xee\xf1\xf2\xe8\xe3%(\xeb\xe0%) \xed\xee\xe2\xee\xe3\xee \xf3\xf0\xee\xe2\xed\xff') end
        if not lp then lp = text:match('(.+) \xe4\xee\xf1\xf2\xe8\xe3 \xed\xee\xe2\xee\xe3\xee \xf3\xf0\xee\xe2\xed\xff') end
        -- \xd3\xe1\xf0\xe0\xf2\xfc \xf6\xe2\xe5\xf2\xee\xe2\xfb\xe5 \xf2\xe5\xe3\xe8 {RRGGBB}, [ID], \xef\xf0\xee\xe1\xe5\xeb\xfb
        if lp then
            lp = lp:gsub('{%x+}', ''):gsub('%[%d+%]', ''):match('^%s*(.-)%s*$') or lp
        end
        if lp_lvl == '' then lp_lvl = nil end
        local family_xp = text:find('\xc2 \xf1\xe5\xec\xfc\xfe \xed\xe0\xf7\xe8\xf1\xeb\xe5\xed \xee\xef\xfb\xf2')
        if (lp and lp ~= '') or family_xp then
            local send_nick = lp or ''
            if send_nick ~= '' then
                if settings.log_enabled and settings.log_enabled.level then flog('level', {nick=send_nick, lvl=lp_lvl}) end
                if settings.tg and settings.tg.enabled and settings.tg.ev_level then
                    if settings.tg.auto_role then
                        fh_update_self(); fh_send_ping()
                        lua_thread.create(function()
                            wait(8000)
                            if am_i_senior() then
                                tg_send('[FH] \xc8\xe3\xf0\xee\xea ' .. send_nick .. (lp_lvl and (' \xe4\xee\xf1\xf2\xe8\xe3 ' .. lp_lvl .. ' \xf3\xf0\xee\xe2\xed\xff.') or ' \xef\xee\xe4\xed\xff\xeb \xf3\xf0\xee\xe2\xe5\xed\xfc.'))
                            end
                        end)
                    else
                        tg_send('[FH] \xc8\xe3\xf0\xee\xea ' .. send_nick .. (lp_lvl and (' \xe4\xee\xf1\xf2\xe8\xe3 ' .. lp_lvl .. ' \xf3\xf0\xee\xe2\xed\xff.') or ' \xef\xee\xe4\xed\xff\xeb \xf3\xf0\xee\xe2\xe5\xed\xfc.'))
                    end
                end
                -- \xc4\xee\xe1\xe0\xe2\xeb\xff\xe5\xec \xed\xe8\xea \xe2 \xe1\xe0\xf2\xf7, \xe8\xe7\xe1\xe5\xe3\xe0\xe5\xec \xe4\xf3\xe1\xeb\xe8\xea\xe0\xf2\xee\xe2
                local already = false
                for _, n in ipairs(congrats_batch) do
                    if n == send_nick then already = true; break end
                end
                if not already then
                    table.insert(congrats_batch, send_nick)
                end
            end
            -- \xc0\xed\xed\xf3\xeb\xe8\xf0\xf3\xe5\xec / \xf1\xf2\xe0\xf0\xf2\xf3\xe5\xec \xf2\xe0\xe9\xec\xe5\xf0 \xe1\xe0\xf2\xf7\xe0 (\xee\xe1\xf0\xe0\xe1\xee\xf2\xea\xe0 \xe2 main-\xeb\xf3\xef\xe5)
            if not congrats_batch_timer then
                congrats_batch_timer = os.time()
            end
        end
    end -- auto_congrats

        -- \xce\xf2\xf1\xeb\xe5\xe6\xe8\xe2\xe0\xed\xe8\xe5 \xea\xe2\xe5\xf1\xf2\xee\xe2 \xf1\xe5\xec\xfc\xe8 + \xe0\xe2\xf2\xee-\xef\xee\xe7\xe4\xf0\xe0\xe2\xeb\xe5\xed\xe8\xe5
    local q_name = nil
    q_name = q_name or text:match('\xd7\xeb\xe5\xed \xf1\xe5\xec\xfc\xe8 (.-)%s+\xe2\xfb\xef\xee\xeb\xed\xe8\xeb \xe5\xe6\xe5\xe4\xed\xe5\xe2\xed\xee\xe5 \xe7\xe0\xe4\xe0\xed\xe8\xe5')
    q_name = q_name or text:match('^(.-)%s+\xe2\xfb\xef\xee\xeb\xed\xe8\xeb%b()%s+\xe5\xe6\xe5\xe4\xed\xe5\xe2\xed\xee\xe5 \xe7\xe0\xe4\xe0\xed\xe8\xe5')
    q_name = q_name or text:match('^(.-)%s+\xe2\xfb\xef\xee\xeb\xed\xe8\xeb \xf1\xe5\xec\xe5\xe9\xed\xfb\xe9 \xea\xe2\xe5\xf1\xf2')
    q_name = q_name or text:match('^(.-)%s+\xf1\xe4\xe0\xeb \xf1\xe5\xec\xe5\xe9\xed\xfb\xe9 \xea\xe2\xe5\xf1\xf2')
    if q_name then
        q_name = q_name:gsub('{%x%x%x%x%x%x}', ''):match('^%s*(.-)%s*$')
        settings.quests_stats[q_name] = (settings.quests_stats[q_name] or 0) + 1
        save_settings()
        if settings.log_enabled and settings.log_enabled.quest then flog('quest', {nick=q_name}) end
        if settings.tg and settings.tg.enabled and settings.tg.ev_quest then
            if settings.tg.auto_role then
                fh_update_self(); fh_send_ping()
                local _qn = q_name
                lua_thread.create(function()
                    wait(8000)
                    if am_i_senior() then
                        tg_send('[FH] \xc8\xe3\xf0\xee\xea ' .. _qn .. ' \xe2\xfb\xef\xee\xeb\xed\xe8\xeb \xf1\xe5\xec\xe5\xe9\xed\xfb\xe9 \xea\xe2\xe5\xf1\xf2.')
                    end
                end)
            else
                tg_send('[FH] \xc8\xe3\xf0\xee\xea ' .. q_name .. ' \xe2\xfb\xef\xee\xeb\xed\xe8\xeb \xf1\xe5\xec\xe5\xe9\xed\xfb\xe9 \xea\xe2\xe5\xf1\xf2.')
            end
        end
        -- \xc0\xe2\xf2\xee-\xef\xee\xe7\xe4\xf0\xe0\xe2\xeb\xe5\xed\xe8\xe5 \xf1 \xea\xe2\xe5\xf1\xf2\xee\xec
        if settings.quest_congrats and settings.quest_congrats.enabled then
            local vars = settings.quest_congrats.variants or {}
            local idx = (#vars > 0) and ((settings.quest_congrats.variant_idx or 0) % #vars + 1) or 1
            settings.quest_congrats.variant_idx = idx
            save_settings()
            local chosen = (vars[idx] or vars[1] or {}).items or {}
            local use_fam_q = settings.quest_congrats.use_fam
            if #chosen > 0 then
                lua_thread.create(function()
                    local p = use_fam_q and '/fam ' or ''
                    for _, qitem in ipairs(chosen) do
                        if qitem.text and qitem.text ~= '' then
                            wait((qitem.waiting or 1.5) * 1000)
                            sampSendChat(p .. processText(qitem.text, nil):gsub('{player_name}', q_name))
                        end
                    end
                end)
            end
        end
    end

    -- \xce\xf2\xf1\xeb\xe5\xe6\xe8\xe2\xe0\xed\xe8\xe5 \xd7\xd1: \xef\xf0\xe5\xe4\xf3\xef\xf0\xe5\xe4\xe8\xf2\xfc \xe5\xf1\xeb\xe8 \xe2\xf1\xf2\xf3\xef\xe8\xeb \xf7\xe5\xeb\xee\xe2\xe5\xea \xe8\xe7 \xf7\xb8\xf0\xed\xee\xe3\xee \xf1\xef\xe8\xf1\xea\xe0
    -- \xc8\xe7\xec\xe5\xed\xe5\xed\xe8\xe5 \xf0\xe0\xed\xe3\xe0 \xe8\xe7 \xed\xee\xe2\xee\xf1\xf2\xe5\xe9
    local rank_admin, rank_nick, rank_new =
        text:match('%[%S+ %(\xcd\xee\xe2\xee\xf1\xf2\xe8%)%] ([%a_]+)%[%d+%]:.+ (\xe8\xe7\xec\xe5\xed\xe8\xeb \xf0\xe0\xed\xe3|\xe2\xfb\xe4\xe0\xeb \xf0\xe0\xed\xe3|\xf3\xf1\xf2\xe0\xed\xee\xe2\xe8\xeb \xf0\xe0\xed\xe3).-([%a_]+)%[%d+%]')
    if not rank_nick then
        -- \xd4\xee\xf0\xec\xe0\xf2: "Admin[ID]: \xf3\xf1\xf2\xe0\xed\xee\xe2\xe8\xeb \xf0\xe0\xed\xe3 N \xe8\xe3\xf0\xee\xea\xf3 Nick[ID]"
        rank_admin = text:match('%[%S+ %(\xcd\xee\xe2\xee\xf1\xf2\xe8%)%] ([%a_]+)%[')
        rank_nick  = text:match('\xe8\xe3\xf0\xee\xea\xf3 ([%a_]+)%[%d+%]')
        rank_new   = text:match('\xf0\xe0\xed\xe3 (%d+)')
    end
    if rank_nick and rank_new then
        if settings.log_enabled and settings.log_enabled.rank then
            flog('rank', {nick=rank_nick:gsub('{%x%x%x%x%x%x}',''), rank=rank_new,
                          by=(rank_admin or ''):gsub('{%x%x%x%x%x%x}','')})
        end
    end

    local joined_name = text:match('(.+) \xe2\xf1\xf2\xf3\xef\xe8\xeb%(\xe0%) \xe2 \xe2\xe0\xf8\xf3 \xf1\xe5\xec\xfc\xfe') or text:match('(.+) \xef\xf0\xe8\xed\xff\xeb \xe2\xe0\xf8\xe5 \xef\xf0\xe5\xe4\xeb\xee\xe6\xe5\xed\xe8\xe5')
 or text:match('\xef\xf0\xe8\xe3\xeb\xe0\xf1\xe8\xeb \xe2 \xf1\xe5\xec\xfc\xfe \xed\xee\xe2\xee\xe3\xee \xf7\xeb\xe5\xed\xe0: (.+)')
    if joined_name then
        joined_name = joined_name:gsub('{%x+}', '')
        for _, bl_user in ipairs(settings.blacklist) do
            if bl_user.name == joined_name then
                lua_thread.create(function()
                    wait(1000)
                    sampSendChat("/fam [\xc2\xcd\xc8\xcc\xc0\xcd\xc8\xc5] \xc8\xe3\xf0\xee\xea " .. joined_name .. " \xed\xe0\xf5\xee\xe4\xe8\xf2\xf1\xff \xe2 \xd7\xd1 \xf1\xe5\xec\xfc\xe8! \xcf\xf0\xe8\xf7\xe8\xed\xe0: " .. tostring(bl_user.reason))
                end)
            end
        end
    end

    -- \xc0\xe2\xf2\xee-\xec\xf3\xf2 \xe7\xe0 \xee\xf1\xea\xee\xf0\xe1\xeb\xe5\xed\xe8\xff, \xf1\xef\xe0\xec \xe8 \xf4\xeb\xf3\xe4 \xe2 /fam
    if settings.general.auto_mute_insults or settings.general.auto_mute_spam or settings.general.auto_mute_flood then
        local clean_text = text:gsub('{%x%x%x%x%x%x}', '')
        local fm_name, fm_id, fm_text = nil, nil, nil

        if clean_text:find('^%[.-%]') then
            -- Формат: [Чат семьи] Nick[ID]: text  ИЛИ  [Чат семьи] Nick: text
            fm_name, fm_id, fm_text = clean_text:match('^%[.-%]%s+(.-)%s*%[(%d+)%]%s*:%s*(.+)')
            if not fm_id then
                -- Формат без ID: [Чат семьи] Nick: text
                local nm, tx = clean_text:match('^%[.-%]%s+(.-)%s*:%s*(.+)')
                if nm and tx then
                    fm_name = nm
                    fm_text = tx
                    -- Получаем ID по нику
                    local ok, pid = pcall(sampGetPlayerIdByNickname, nm)
                    if ok and pid and pid >= 0 then fm_id = tostring(pid) end
                end
            end
        end

        if fm_id and fm_text then
            -- \xc7\xe0\xf9\xe8\xf2\xe0: \xed\xe5 \xec\xf3\xf2\xe8\xf2\xfc \xf1\xe0\xec\xee\xe3\xee \xf1\xe5\xe1\xff
            local my_name = settings.family_info and settings.family_info.my_name or ''
            if fm_name and my_name ~= '' and fm_name:lower() == my_name:lower() then
                fm_id = nil
            end
        end

        if fm_id and fm_text then
            if not mute_tracker then mute_tracker = {} end
            if not mute_tracker[fm_id] then
                mute_tracker[fm_id] = { last_mute = 0, msgs = {}, spam_text = '', spam_count = 0, spam_time = 0 }
            end
            local tr = mute_tracker[fm_id]
            local now = os.time()

            -- \xca\xf3\xeb\xe4\xe0\xf3\xed: \xed\xe5 \xec\xf3\xf2\xe8\xf2\xfc \xef\xee\xe2\xf2\xee\xf0\xed\xee \xe2 \xf2\xe5\xf7\xe5\xed\xe8\xe5 5 \xec\xe8\xed\xf3\xf2
            local function do_mute(reason, mute_min)
                if os.difftime(now, tr.last_mute) < 300 then return end
                tr.last_mute = now
                lua_thread.create(function()
                    wait(600)
                    sampSendChat(string.format('/fammute %s %d %s', fm_id, mute_min, reason))
                    log_event(reason .. ' -> ID ' .. fm_id)
                end)
            end

            -- \xcf\xf0\xee\xe2\xe5\xf0\xea\xe0 \xed\xe0 \xee\xf1\xea\xee\xf0\xe1\xeb\xe5\xed\xe8\xff (\xf2\xee\xeb\xfc\xea\xee \xff\xe2\xed\xfb\xe5 \xec\xe0\xf2\xfb, \xef\xf0\xee\xe2\xe5\xf0\xea\xe0 \xef\xee \xe3\xf0\xe0\xed\xe8\xf6\xe0\xec \xf1\xeb\xee\xe2\xe0)
            if settings.general.auto_mute_insults then
                local lt = ' ' .. fm_text:lower() .. ' '
                -- \xd2\xee\xeb\xfc\xea\xee \xee\xe4\xed\xee\xe7\xed\xe0\xf7\xed\xfb\xe5 \xec\xe0\xf2\xe5\xf0\xed\xfb\xe5 \xf1\xeb\xee\xe2\xe0, \xed\xe5 \xe1\xfb\xf2\xee\xe2\xfb\xe5
                -- Матерные и оскорбительные слова
                local insults = {
                    '\xf1\xf3\xea\xe0','\xf1\xf3\xea\xf3','\xf1\xf3\xea\xe8','\xf1\xf3\xea\xe5','\xf1\xf3\xea\xe0\xf0',
                    '\xe1\xeb\xff\xf2\xfc','\xe1\xeb\xff\xe4\xfc','\xe1\xeb\xff\xe4\xf1\xea',
                    '\xef\xe8\xe4\xee\xf0','\xef\xe8\xe4\xf0\xe8\xeb\xe0','\xef\xe8\xe4\xee\xf0\xe0\xf1',
                    '\xf5\xf3\xe9','\xf5\xf3\xe9\xeb\xee','\xf5\xf3\xe9\xed\xff',
                    '\xf8\xeb\xfe\xf5\xe0','\xf8\xe0\xeb\xe0\xe2\xe0',
                    '\xef\xe8\xe7\xe4\xe5\xf6','\xef\xe8\xe7\xe4\xe0','\xef\xe8\xe7\xe4\xe0\xe1\xee\xeb',
                    '\xe5\xe1\xeb\xe0\xed','\xf3\xe5\xe1\xe8\xf9\xe5',
                    '\xb8\xe1\xe0\xed\xfb\xe9','\xb8\xe1\xe0\xf2\xfc','\xe4\xee\xeb\xe1\xee\xb8\xe1',
                    '\xe3\xe0\xed\xe4\xee\xed','\xec\xf3\xe4\xe0\xea','\xe7\xe0\xeb\xf3\xef\xe0','\xf1\xf3\xf7\xea\xe0','\xf3\xe1\xeb\xfe\xe4\xee\xea',
                    '\xef\xee\xf1\xf1\xfb\xf8\xfc','\xef\xee\xf1\xf1\xfb',
                    '\xee\xf1\xeb\xe0\xe5\xe1\xe8\xed\xe0','\xee\xf1\xeb\xe0\xe5\xe1',
                    '\xe1\xf0\xe0\xea\xee\xe2\xe0\xed',
                    '\xee\xf1\xea\xe0\xe5\xf8\xfc','\xee\xf1\xea\xe0\xe5\xf2',
                    '\xe4\xfb\xe8\xe6',
                    '\xf2\xf3\xef\xe0\xff','\xf2\xf3\xef\xee\xe9','\xf2\xf3\xef\xfb\xe5',
                    '\xe8\xe4\xe8\xee\xf2','\xe4\xe5\xe1\xe8\xeb','\xea\xf0\xe5\xf2\xe8\xed','\xf3\xf0\xee\xe4',
                    '\xeb\xee\xf5'
                }
                for _, w in ipairs(insults) do
                    if lt:find(w, 1, true) then
                        do_mute('\xc0\xe2\xf2\xee-\xec\xf3\xf2: \xce\xf1\xea\xee\xf0\xe1\xeb\xe5\xed\xe8\xff', settings.general.auto_mute_insults_time or 60)
                        break
                    end
                end
            end

            -- \xcf\xf0\xee\xe2\xe5\xf0\xea\xe0 \xed\xe0 \xf1\xef\xe0\xec (3+ \xee\xe4\xe8\xed\xe0\xea\xee\xe2\xfb\xf5 \xf1\xee\xee\xe1\xf9\xe5\xed\xe8\xff \xe7\xe0 90 \xf1\xe5\xea)
            if settings.general.auto_mute_spam then
                if tr.spam_text == fm_text and os.difftime(now, tr.spam_time) < 90 then
                    tr.spam_count = tr.spam_count + 1
                else
                    tr.spam_text  = fm_text
                    tr.spam_count = 1
                    tr.spam_time  = now
                end
                if tr.spam_count >= 3 then
                    tr.spam_count = 0
                    do_mute('\xc0\xe2\xf2\xee-\xec\xf3\xf2: \xd1\xef\xe0\xec', settings.general.auto_mute_spam_time or 30)
                end
            end

            -- \xcf\xf0\xee\xe2\xe5\xf0\xea\xe0 \xed\xe0 \xf4\xeb\xf3\xe4 (\xed\xe0\xf1\xf2\xf0\xe0\xe8\xe2\xe0\xe5\xec\xfb\xe5: \xea\xee\xeb-\xe2\xee \xf1\xee\xee\xe1\xf9\xe5\xed\xe8\xe9 \xe7\xe0 \xe8\xed\xf2\xe5\xf0\xe2\xe0\xeb \xf1\xe5\xea)
            if settings.general.auto_mute_flood then
                local flood_n   = settings.general.flood_msg_count or 5
                local flood_sec = settings.general.flood_interval  or 15
                table.insert(tr.msgs, now)
                -- \xd3\xe4\xe0\xeb\xff\xe5\xec \xf1\xee\xee\xe1\xf9\xe5\xed\xe8\xff \xf1\xf2\xe0\xf0\xf8\xe5 \xe8\xed\xf2\xe5\xf0\xe2\xe0\xeb\xe0
                local i = 1
                while i <= #tr.msgs do
                    if os.difftime(now, tr.msgs[i]) > flood_sec then
                        table.remove(tr.msgs, i)
                    else
                        i = i + 1
                    end
                end
                if #tr.msgs >= flood_n then
                    tr.msgs = {}
                    do_mute('\xc0\xe2\xf2\xee-\xec\xf3\xf2: \xd4\xeb\xf3\xe4', settings.general.auto_mute_flood_time or 30)
                end
            end
        end
    end

  -- \xc0\xe2\xf2\xee-\xef\xee\xe7\xe4\xf0\xe0\xe2\xeb\xe5\xed\xe8\xe5 \xe7\xe0 \xea\xe2\xe5\xf1\xf2 \xf1\xe5\xec\xfc\xe8
    if settings.general.auto_quest_congrats then
        if text:find('\xe2\xfb\xef\xee\xeb\xed\xe8\xeb \xe5\xe6\xe5\xe4\xed\xe5\xe2\xed\xee\xe5 \xe7\xe0\xe4\xe0\xed\xe8\xe5, \xf1\xe5\xec\xfc\xff \xef\xee\xeb\xf3\xf7\xe8\xeb\xe0') then
            lua_thread.create(function()
                wait(1500)
                sampSendChat('/fam \xd1\xef\xe0\xf1\xe8\xe1\xee \xe7\xe0 \xe2\xfb\xef\xee\xeb\xed\xe5\xed\xe8\xe5 \xe7\xe0\xe4\xe0\xed\xe8\xff! \xd2\xe0\xea \xe4\xe5\xf0\xe6\xe0\xf2\xfc!')
            end)
        end
    end

    -- \xc0\xe2\xf2\xee-\xe8\xed\xe2\xe0\xe9\xf2 \xef\xee \xea\xeb\xfe\xf7\xe5\xe2\xfb\xec \xf1\xeb\xee\xe2\xe0\xec \xe2 \xf7\xe0\xf2\xe5
    if settings.general.auto_keyword_invite then
        local clean = text:gsub('{%x+}', ''):lower()
        -- \xd4\xee\xf0\xec\xe0\xf2 \xf1\xee\xee\xe1\xf9\xe5\xed\xe8\xff: Nick_Name[ID]: \xf2\xe5\xea\xf1\xf2
        local kid, msg = clean:match('^.-%[(%d+)%]%s*:%s*(.+)$')
        if kid and msg then
            local myid = select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))
            local tid = tonumber(kid)
            -- \xcd\xe5 \xe8\xed\xe2\xe0\xe9\xf2\xe8\xf2\xfc \xf1\xe5\xe1\xff \xe8 \xf3\xe6\xe5 \xef\xf0\xe8\xe3\xeb\xe0\xf8\xb8\xed\xed\xfb\xf5
            if tid and tid ~= myid and not invited_players[tid] then
                -- \xcd\xe5 \xe8\xed\xe2\xe0\xe9\xf2\xe8\xf2\xfc \xf2\xe5\xf5 \xf3 \xea\xee\xe3\xee \xf3\xe6\xe5 \xe5\xf1\xf2\xfc \xf2\xe5\xe3 \xf1\xe5\xec\xfc\xe8
                local their_nick = sampGetPlayerNickname(tid) or ''
                local tag = settings.family_info.family_tag or ''
                local already_member = tag ~= '' and their_nick:find(tag, 1, true)
                if not already_member then
                    local msg_trim = msg:match('^%s*(.-)%s*$')
                    local keywords = settings.general.keyword_invite_list or {'\xe8\xed\xe2', '\xe8\xed\xe2\xe0\xe9\xf2', '\xef\xf0\xe8\xec\xe8'}
                    for _, word in ipairs(keywords) do
                        if msg_trim == word or msg_trim:find('^' .. word) then
                            invited_players[tid] = os.time()
                            sampSendChat('/faminvite ' .. kid)
                            log_event('\xc0\xe2\xf2\xee-\xe8\xed\xe2\xe0\xe9\xf2: ' .. their_nick)
                            break
                        end
                    end
                end
            end
        end
    end
end

function sampev.onSendChat(text)
    if not text then return end
    if settings.general.rp_chat then
        local orig = text
        text = text:sub(1,1):rupper() .. text:sub(2)
        if not text:find('[%.%!%?]$') then text = text .. '.' end
        if text ~= orig then return {text} end
    end
end

function sampev.onSendCommand(text)
    if not text then return end
    -- \xcd\xe5 \xf2\xf0\xee\xe3\xe0\xf2\xfc FH \xef\xe8\xed\xe3-\xec\xe0\xf0\xea\xe5\xf0\xfb \xe8 \xf1\xee\xee\xe1\xf9\xe5\xed\xe8\xff \xf1 \xe2\xf8\xe8\xf2\xfb\xec \xec\xe0\xf0\xea\xe5\xf0\xee\xec
    if text:find('\xE2\x80\x8B%[FH:', 1, false) then return {text} end
    if settings.general.rp_chat then
        local orig = text
        for _, c in ipairs({'/fam','/vr','/al','/s','/b','/n','/r','/rb','/f','/fb','/do','/me'}) do
            if text:find('^' .. c .. ' ') then
                local ct = text:match('^' .. c .. ' (.+)')
                if ct then ct = ct:sub(1,1):rupper() .. ct:sub(2); text = c .. ' ' .. ct
                    if not text:find('[%.%!%?]$') then text = text .. '.' end
                end
            end
        end
        if text ~= orig then return {text} end
    end
end

----------------------------------------------- IMGUI ---------------------------------------------------------

-- \xcc\xe3\xed\xee\xe2\xe5\xed\xed\xe0\xff \xef\xe5\xf0\xe5\xe4\xe0\xf7\xe0 \xf0\xee\xeb\xe8 \xef\xf0\xe8 \xe2\xfb\xf5\xee\xe4\xe5 \xe8\xe3\xf0\xee\xea\xe0
function sampev.onPlayerDisconnect(playerId, reason)
    local ok, nick = pcall(sampGetPlayerNickname, playerId)
    if ok and nick and fh_online[nick] then
        fh_online[nick] = nil
        -- \xf1\xeb\xe5\xe4\xf3\xfe\xf9\xe8\xe9 am_i_senior() \xe0\xe2\xf2\xee\xec\xe0\xf2\xe8\xf7\xe5\xf1\xea\xe8 \xef\xe5\xf0\xe5\xf1\xf7\xe8\xf2\xe0\xe5\xf2 \xea\xf2\xee \xe3\xeb\xe0\xe2\xed\xfb\xe9
    end
end
imgui.OnInitialize(function() imgui.GetIO().IniFilename = nil; apply_theme() end)

-- ========== \xcf\xcb\xc0\xc2\xc0\xde\xd9\xc0\x9f \xca\xcd\xce\xcf\xca\xc0 ==========
imgui.OnFrame(
    function() return settings.general.float_btn_enable and #nearby_players > 0 and not InteractMenu[0] and not InteractSelectPlayer[0] end,
    function()
        local d = settings.general.custom_dpi
        local bs = settings.general.float_btn_size or 1.0
        local bw = 110 * d * bs
        local bh = 36 * d * bs
        local ar = settings.interface.accent_r or 1.0
        local ag = settings.interface.accent_g or 0.65
        local ab = settings.interface.accent_b or 0.0
        imgui.SetNextWindowPos(imgui.ImVec2(settings.general.float_btn_x, settings.general.float_btn_y), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowSize(imgui.ImVec2(120 * d * bs, 46 * d * bs))
        local dummy = imgui.new.bool(true)
        imgui.Begin("##fbtn", dummy, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoTitleBar)
        if not isMonetLoader() then imgui.SetWindowFontScale(d * bs) end
        local pos = imgui.GetWindowPos()
        if pos.x ~= settings.general.float_btn_x or pos.y ~= settings.general.float_btn_y then
            settings.general.float_btn_x = pos.x; settings.general.float_btn_y = pos.y; save_settings()
        end
        local cnt = #nearby_players
        local flabel = safe_u8(cnt .. ' \xe8\xe3\xf0.')
        if imgui.Button(flabel, imgui.ImVec2(-1, -1)) then
            if cnt == 1 then interact_player_id = nearby_players[1]; InteractMenu[0] = true
            elseif cnt > 1 then InteractSelectPlayer[0] = true end
        end
        imgui.End()
    end
)

-- ========== \xc2\xdb\xc1\xce\xd0 \xc8\xc3\xd0\xce\xca\xc0 ==========
imgui.OnFrame(function() return InteractSelectPlayer[0] end, function()
    local d = settings.general.custom_dpi
    imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.Begin(u8' \xc8\xe3\xf0\xee\xea\xe8 \xf0\xff\xe4\xee\xec##isp', InteractSelectPlayer, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.AlwaysAutoResize)
    change_dpi()
    local pl = get_players_in_radius(settings.general.float_btn_radius or 15)
    if #pl == 0 then imgui.Text(u8'\xcd\xe8\xea\xee\xe3\xee \xed\xe5\xf2')
    else
        for _, pid in ipairs(pl) do
            local ru = TranslateNick(sampGetPlayerNickname(pid) or '')
            if imgui.Button(safe_u8(ru .. ' [' .. pid .. ']'), imgui.ImVec2(240*d, 26*d)) then
                interact_player_id = pid; InteractMenu[0] = true; InteractSelectPlayer[0] = false
            end
        end
    end
    if imgui.Button(u8' \xc7\xe0\xea\xf0\xfb\xf2\xfc##isp', imgui.ImVec2(-1, 0)) then InteractSelectPlayer[0] = false end
    imgui.End()
end)

-- ========== \xcc\xc5\xcd\xde \xc2\xc7\xc0\xc8\xcc\xce\xc4\xc5\xc9\xd1\xd2\xc2\xc8\xdf ==========
imgui.OnFrame(function() return InteractMenu[0] end, function()
    if not interact_player_id or not sampIsPlayerConnected(interact_player_id) then InteractMenu[0] = false; return end
    local d = settings.general.custom_dpi
    local nick = sampGetPlayerNickname(interact_player_id) or '???'
    local ru = TranslateNick(nick)
    local ar = settings.interface.accent_r or 1.0
    local ag = settings.interface.accent_g or 0.65
    local ab = settings.interface.accent_b or 0.0
    imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.Begin(safe_u8(' ' .. ru .. ' [' .. interact_player_id .. ']'), InteractMenu, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.AlwaysAutoResize)
    change_dpi()
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(ar*0.3, ag*0.3, ab*0.3, 1))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(ar*0.5, ag*0.5, ab*0.5, 1))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(ar*0.7, ag*0.7, ab*0.7, 1))
    local bw = 130 * d
    local bh = 24 * d
    local cols = 2
    local count = #settings.interactions
    if isActiveCommand then imgui.TextDisabled(u8'\xc2\xfb\xef\xee\xeb\xed\xff\xe5\xf2\xf1\xff...')
    else
        for i, inter in ipairs(settings.interactions) do
            if imgui.Button(safe_u8(inter.name or ''), imgui.ImVec2(bw, bh)) then
                send_interaction(i, interact_player_id)
            end
            if i % cols ~= 0 and i < count then imgui.SameLine() end
        end
    end
    imgui.PopStyleColor(3)
    if imgui.SmallButton(u8'X##close_im') then InteractMenu[0] = false end
    imgui.End()
end)

-- ========== \xc3\xcb\xc0\xc2\xcd\xce\xc5 \xcc\xc5\xcd\xde ==========

-- ===== FH MARKET TAB: функция рисовки =====

-- ===== DETAIL POPUP STATE =====
if not _G.mkt_detail_open  then _G.mkt_detail_open  = false end
if not _G.mkt_detail_item  then _G.mkt_detail_item  = '' end
if not _G.mkt_detail_src   then _G.mkt_detail_src   = 'cp' end
if not _G.mkt_auto_detail_open then _G.mkt_auto_detail_open = false end
if not _G.mkt_auto_detail_item then _G.mkt_auto_detail_item = '' end
if not _G.mkt_cp_page      then _G.mkt_cp_page      = 1 end
if not _G.mkt_lv_page      then _G.mkt_lv_page      = 1 end
local MKT_PAGE_SIZE = 50

-- ================================================================
-- FH MARKET UI v3 — полная переработка
-- Источники данных:
--   cp_hist  = история по дням с чекпоинта (deep scan)
--              [{dt="2026-03-10", qty=168, price=8330}, ...]
--   s_avg/min/max = поверхностный скан (shallow)
--   b_avg/min/max = цены в лавках игроков
--   fh_mkt_log    = реальные сделки из чата
-- ================================================================

-- Мини-график из блок-символов ????????
local SPARK_CHARS = {'.', ',', '_', '-', '=', '~', '+', '#'}

local function fh_spark(history, max_days)
    -- history = cp_hist (новейший = первый)
    max_days = max_days or 10
    if not history or #history == 0 then return '—' end
    local slice = {}
    for i = math.min(#history, max_days), 1, -1 do
        table.insert(slice, history[i].price or 0)
    end
    if #slice == 0 then return '—' end
    local mn, mx = slice[1], slice[1]
    for _, v in ipairs(slice) do
        if v < mn then mn = v end
        if v > mx then mx = v end
    end
    local range = mx - mn
    local result = ''
    for _, v in ipairs(slice) do
        local idx = 1
        if range > 0 then
            idx = math.floor((v - mn) / range * 7) + 1
        else
            idx = 4
        end
        result = result .. SPARK_CHARS[idx]
    end
    return result
end

-- Тренд: сравниваем первую и вторую половины истории
-- Возвращает строку типа "? +12%" или "? -5%" или "? 0%"
local function fh_trend(history)
    if not history or #history < 4 then return '?' end
    local n = #history
    local half = math.floor(n / 2)
    -- "новые" = начало массива (индекс 1 = последний день)
    local new_sum, new_cnt = 0, 0
    for i = 1, half do
        if history[i].price and history[i].price > 0 then
            new_sum = new_sum + history[i].price
            new_cnt = new_cnt + 1
        end
    end
    local old_sum, old_cnt = 0, 0
    for i = half+1, n do
        if history[i].price and history[i].price > 0 then
            old_sum = old_sum + history[i].price
            old_cnt = old_cnt + 1
        end
    end
    if new_cnt == 0 or old_cnt == 0 then return '?' end
    local new_avg = new_sum / new_cnt
    local old_avg = old_sum / old_cnt
    if old_avg == 0 then return '?' end
    local pct = math.floor((new_avg - old_avg) / old_avg * 100)
    if pct > 2 then
        return string.format('(+) +%d%%', pct)
    elseif pct < -2 then
        return string.format('(-) %d%%', pct)
    else
        return string.format('(=) %+d%%', pct)
    end
end

-- Цвет тренда
local function fh_trend_color(trend_str)
    if trend_str:find('%(+%)') then
        return imgui.ImVec4(0.3, 0.95, 0.3, 1)   -- зелёный — растёт
    elseif trend_str:find('^%-') then
        return imgui.ImVec4(1, 0.4, 0.3, 1)       -- красный — падает
    else
        return imgui.ImVec4(0.7, 0.7, 0.7, 1)     -- серый — стабильно
    end
end

-- Посчитать статистику по cp_hist за N дней
local function fh_hist_stats(history, days)
    if not history or #history == 0 then return nil end
    local pxq, qty = 0, 0
    local mn, mx
    local count = math.min(#history, days or 30)
    for i = 1, count do
        local h = history[i]
        if h and h.price and h.price > 0 then
            local q = h.qty or 1
            pxq = pxq + h.price * q
            qty = qty + q
            if not mn or h.price < mn then mn = h.price end
            if not mx or h.price > mx then mx = h.price end
        end
    end
    if qty == 0 then return nil end
    return {
        avg  = math.floor(pxq / qty),
        qty  = qty,
        min  = mn,
        max  = mx,
        days = count,
    }
end

-- ================================================================
-- POPUP: детальная статистика товара
-- ================================================================
local function fh_draw_item_detail(item_name, src)
    local d  = settings.general.custom_dpi
    local ar = settings.interface.accent_r or 1
    local ag = settings.interface.accent_g or .65
    local ac = imgui.ImVec4(ar, ag, 0, 1)

    local cp_e   = fh_mkt_prices[item_name]
    local lv_e   = fh_mkt_lavka[item_name]
    local cp_hist = cp_e and cp_e.cp_hist

    imgui.TextColored(ac, safe_u8('Товар: ' .. item_name))
    if cp_e and cp_e.date then
        imgui.SameLine()
        imgui.TextDisabled(safe_u8('  обновлено ' .. cp_e.date))
    end
    imgui.Separator()
    imgui.Spacing()

    -- === Статистика из deep scan ===
    if cp_hist and #cp_hist > 0 then
        local s7  = fh_hist_stats(cp_hist, 7)
        local s30 = fh_hist_stats(cp_hist, 30)
        local trend = fh_trend(cp_hist)
        local tc    = fh_trend_color(trend)

        imgui.TextColored(imgui.ImVec4(ar, ag, 0, 1), u8'  Статистика рынка (история по дням)')
        imgui.Spacing()
        imgui.Columns(4, '##dtl_stat2', false)
        imgui.SetColumnWidth(0, 85*d); imgui.SetColumnWidth(1, 90*d)
        imgui.SetColumnWidth(2, 80*d); imgui.SetColumnWidth(3, 125*d)

        imgui.TextColored(imgui.ImVec4(0.6,0.6,0.6,1), u8''); imgui.NextColumn()
        imgui.TextColored(imgui.ImVec4(0.6,0.6,0.6,1), u8'Ср. цена $'); imgui.NextColumn()
        imgui.TextColored(imgui.ImVec4(0.6,0.6,0.6,1), u8'Продано шт.'); imgui.NextColumn()
        imgui.TextColored(imgui.ImVec4(0.6,0.6,0.6,1), u8'Мин / Макс'); imgui.NextColumn()

        -- Сегодня (cp_hist[1] = найсвежаяя дата)
        local today_h = cp_hist[1]
        imgui.TextColored(imgui.ImVec4(0.4,0.95,1,1), u8' Сегодня'); imgui.NextColumn()
        if today_h and today_h.price and today_h.price > 0 then
            imgui.TextColored(imgui.ImVec4(0.4,0.95,1,1), safe_u8(' $'..fh_num_fmt(today_h.price))); imgui.NextColumn()
            imgui.TextColored(imgui.ImVec4(1,1,1,0.8), safe_u8(' '..(today_h.qty or 0)..' шт.')); imgui.NextColumn()
            imgui.TextColored(imgui.ImVec4(1,1,1,0.4), safe_u8(' '..(today_h.dt or ''))); imgui.NextColumn()
        else
            imgui.TextDisabled(u8' —'); imgui.NextColumn()
            imgui.TextDisabled(u8' —'); imgui.NextColumn()
            imgui.TextDisabled(u8' —'); imgui.NextColumn()
        end
        -- 7 дней
        imgui.TextColored(imgui.ImVec4(1,0.85,0.2,1), u8' За 7 дней'); imgui.NextColumn()
        if s7 then
            imgui.TextColored(imgui.ImVec4(1,0.85,0.2,1), safe_u8(' $'..fh_num_fmt(s7.avg))); imgui.NextColumn()
            imgui.TextColored(imgui.ImVec4(1,1,1,0.8), safe_u8(' '..fh_num_fmt(s7.qty))); imgui.NextColumn()
            imgui.TextColored(imgui.ImVec4(1,1,1,0.6), safe_u8(' '..fh_num_short(s7.min)..'/'..fh_num_short(s7.max))); imgui.NextColumn()
        else
            imgui.TextDisabled(u8' —'); imgui.NextColumn()
            imgui.TextDisabled(u8' —'); imgui.NextColumn()
            imgui.TextDisabled(u8' —'); imgui.NextColumn()
        end

        -- 30 дней
        imgui.TextColored(imgui.ImVec4(0.4,0.95,0.4,1), u8' За 30 дней'); imgui.NextColumn()
        if s30 then
            imgui.TextColored(imgui.ImVec4(0.4,0.95,0.4,1), safe_u8(' $'..fh_num_fmt(s30.avg))); imgui.NextColumn()
            imgui.TextColored(imgui.ImVec4(1,1,1,0.8), safe_u8(' '..fh_num_fmt(s30.qty))); imgui.NextColumn()
            imgui.TextColored(imgui.ImVec4(1,1,1,0.6), safe_u8(' '..fh_num_short(s30.min)..'/'..fh_num_short(s30.max))); imgui.NextColumn()
        else
            imgui.TextDisabled(u8' —'); imgui.NextColumn()
            imgui.TextDisabled(u8' —'); imgui.NextColumn()
            imgui.TextDisabled(u8' —'); imgui.NextColumn()
        end

        imgui.Columns(1)
        imgui.Spacing()

        -- PlotLines график СВЕРХУ (встроенный ImGui виджет)
        imgui.Spacing()
        -- Строим массив float значений для PlotLines
        local plot_n = math.min(#cp_hist, 30)
        -- Собираем значения в обычную Lua таблицу (от старого к новому)
        local p_min, p_max = math.huge, -math.huge
        local plot_tbl = {}
        for i = plot_n, 1, -1 do
            local v = (cp_hist[i] and cp_hist[i].price) or 0
            table.insert(plot_tbl, v)
            if v > 0 then
                if v < p_min then p_min = v end
                if v > p_max then p_max = v end
            end
        end
        -- Конвертируем в ffi float array для PlotLines.
        -- Умная нормализация: %g даёт scientific notation для чисх >= 1млн
        local plot_scale, overlay_s
        local p_real_max = (p_max ~= -math.huge) and p_max or 0
        if p_real_max >= 1000000000 then
            plot_scale = 1000000
            overlay_s = safe_u8('млн $')
        elseif p_real_max >= 1000000 then
            plot_scale = 1000
            overlay_s = safe_u8('тыс $')
        else
            plot_scale = 1
            overlay_s = safe_u8('$')
        end
        local plot_vals = ffi.new('float[?]', plot_n)
        for i = 0, plot_n - 1 do
            plot_vals[i] = (plot_tbl[i + 1] or 0) / plot_scale
        end
        local p_min_sc = (p_min ~= math.huge)  and (p_min / plot_scale * 0.95) or 0
        local p_max_sc = (p_max ~= -math.huge) and (p_max / plot_scale * 1.05) or 1
        imgui.PushStyleColor(imgui.Col.PlotLines, imgui.ImVec4(0.3, 0.8, 1, 1))
        imgui.PushStyleColor(imgui.Col.PlotLinesHovered, imgui.ImVec4(1, 0.85, 0.2, 1))
        imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.06, 0.06, 0.10, 1))
        imgui.TextColored(imgui.ImVec4(0.5, 0.8, 1, 1), safe_u8('  График цен (' .. plot_n .. ' дн):'))
        imgui.PlotLines('##fhspark', plot_vals, plot_n, 0, overlay_s,
            p_min_sc, p_max_sc,
            imgui.ImVec2(imgui.GetWindowContentRegionWidth() - 16*d, 80*d))
        imgui.PopStyleColor(3)
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        -- Таблица по дням
        imgui.TextColored(imgui.ImVec4(ar,ag,0,1), safe_u8('  История по дням (' .. #cp_hist .. '):'))
        local hist_h = math.min(#cp_hist * 18*d + 30*d, 220*d)
        if imgui.BeginChild('##dtl_hist_days', imgui.ImVec2(-1, hist_h), true) then
            imgui.Columns(3, '##dtl_hd', false)
            imgui.SetColumnWidth(0, 120*d); imgui.SetColumnWidth(1, 70*d); imgui.SetColumnWidth(2, 110*d)
            imgui.TextColored(imgui.ImVec4(0.5,0.5,0.5,1), u8' Дата'); imgui.NextColumn()
            imgui.TextColored(imgui.ImVec4(0.5,0.5,0.5,1), u8' Продано'); imgui.NextColumn()
            imgui.TextColored(imgui.ImVec4(0.5,0.5,0.5,1), u8' Ср. цена за день'); imgui.NextColumn()
            imgui.Separator()
            for i, h in ipairs(cp_hist) do
                local row_c = (i == 1) and imgui.ImVec4(1,0.85,0.2,1) or imgui.ImVec4(0.85,0.85,0.85,1)
                imgui.TextColored(imgui.ImVec4(0.65,0.65,0.65,1), safe_u8(' '..(h.dt or ''))); imgui.NextColumn()
                imgui.TextColored(imgui.ImVec4(1,1,1,0.75), safe_u8(' '..(h.qty or 0))); imgui.NextColumn()
                imgui.TextColored(row_c, safe_u8(' $'..fh_num_fmt(h.price))); imgui.NextColumn()
            end
            imgui.Columns(1); imgui.EndChild()
        end
    elseif cp_e then
        -- Только shallow данные
        imgui.TextColored(imgui.ImVec4(1,0.75,0,1), u8'  Только поверхностный скан (нет истории по дням)')
        imgui.TextDisabled(u8'  Запустите Углублённый скан для получения истории')
        imgui.Spacing()
        if cp_e.s_avg then
            imgui.Text(safe_u8('  Ср. цена (shallow): $' .. fh_num_fmt(cp_e.s_avg)))
            if cp_e.s_min then imgui.Text(safe_u8('  Мин: $'..fh_num_fmt(cp_e.s_min)..'   Макс: $'..fh_num_fmt(cp_e.s_max))) end
        end
        imgui.Separator()
    else
        imgui.TextDisabled(u8'  Нет данных с чекпоинта.')
        imgui.Separator()
    end

    -- === Цена в лавке vs рынок ===
    if lv_e or (cp_e and (cp_e.b_avg or cp_e.b_min)) then
        imgui.Spacing()
        imgui.TextColored(imgui.ImVec4(0.4,0.7,1,1), u8'  Цены в лавках игроков')
        imgui.Spacing()
        local b_avg = (lv_e and lv_e.b_avg) or (cp_e and cp_e.b_avg)
        local b_min = (lv_e and lv_e.b_min) or (cp_e and cp_e.b_min)
        local s7c   = cp_hist and fh_hist_stats(cp_hist, 7)
        if b_avg then
            imgui.Text(safe_u8('  Ср. цена в лавке: $' .. fh_num_fmt(b_avg)))
        end
        if b_min then
            imgui.Text(safe_u8('  Мин. цена в лавке: $' .. fh_num_fmt(b_min)))
        end
        -- Выгода: разница лавка vs рынок
        if b_avg and s7c and s7c.avg and s7c.avg > 0 then
            local diff = s7c.avg - b_avg
            local pct  = math.floor(diff / s7c.avg * 100)
            imgui.Spacing()
            if diff > 0 then
                imgui.TextColored(imgui.ImVec4(0.3,0.95,0.3,1),
                    safe_u8('  Лавка дешевле рынка на $'..fh_num_fmt(diff)..' ('..pct..'%) — выгодно покупать!'))
            elseif diff < 0 then
                imgui.TextColored(imgui.ImVec4(1,0.5,0.3,1),
                    safe_u8('  Лавка дороже рынка на $'..fh_num_fmt(-diff)..' ('..(-pct)..'%)'))
            else
                imgui.TextColored(imgui.ImVec4(0.7,0.7,0.7,1), u8'  Цена лавки = цене рынка')
            end
        end
        imgui.Separator()
    end

    -- === Лог личных сделок ===
    imgui.Spacing()
    local my_hist = {}
    local nm_low = item_name:lower()
    for i = #fh_mkt_log, 1, -1 do
        local le = fh_mkt_log[i]
        if le and le.item and le.item:lower() == nm_low then
            table.insert(my_hist, le)
            if #my_hist >= 50 then break end
        end
    end
    imgui.TextColored(imgui.ImVec4(ar,ag,0,1), safe_u8('  Мои сделки (' .. #my_hist .. '):'))
    local log_h = math.min(math.max(#my_hist, 1) * 18*d + 30*d, 140*d)
    if imgui.BeginChild('##dtl_mylog', imgui.ImVec2(-1, log_h), true) then
        if #my_hist == 0 then
            imgui.TextDisabled(u8'  Сделок по этому товару нет')
        else
            imgui.Columns(4, '##dtl_ml', false)
            imgui.SetColumnWidth(0,80*d); imgui.SetColumnWidth(1,50*d)
            imgui.SetColumnWidth(2,100*d); imgui.SetColumnWidth(3,60*d)
            imgui.TextColored(imgui.ImVec4(0.5,0.5,0.5,1),u8'Дата'); imgui.NextColumn()
            imgui.TextColored(imgui.ImVec4(0.5,0.5,0.5,1),u8'Кол.'); imgui.NextColumn()
            imgui.TextColored(imgui.ImVec4(0.5,0.5,0.5,1),u8'Цена $'); imgui.NextColumn()
            imgui.TextColored(imgui.ImVec4(0.5,0.5,0.5,1),u8'Тип'); imgui.NextColumn()
            imgui.Separator()
            for _, le in ipairs(my_hist) do
                local is_sell = (le.op == 'sell') or (le.op ~= 'buy')
                local tc2 = is_sell and imgui.ImVec4(0.4,0.95,0.4,1) or imgui.ImVec4(0.4,0.7,1,1)
                imgui.TextColored(imgui.ImVec4(0.5,0.5,0.5,1), safe_u8(' '..(le.dt or ''))); imgui.NextColumn()
                imgui.TextColored(imgui.ImVec4(1,1,1,0.7), safe_u8(' '..(le.qty or 1))); imgui.NextColumn()
                imgui.TextColored(tc2, safe_u8(' $'..fh_num_fmt(le.price))); imgui.NextColumn()
                imgui.TextColored(tc2, is_sell and u8'Продажа' or u8'Покупка'); imgui.NextColumn()
            end
            imgui.Columns(1)
        end
        imgui.EndChild()
    end
end

-- ================================================================
-- ОСНОВНОЙ UI МАРКЕТА
-- ================================================================
local function fh_draw_market()
    local d  = settings.general.custom_dpi
    local ar = settings.interface.accent_r or 1
    local ag = settings.interface.accent_g or .65

    -- Инициализация состояния
    if not _G.mkt_srch      then _G.mkt_srch      = imgui.new.char[256]('') end
    if not _G.mkt_srch_s    then _G.mkt_srch_s    = '' end
    if not _G.mkt_lv_srch   then _G.mkt_lv_srch   = imgui.new.char[256]('') end
    if not _G.mkt_lv_ss     then _G.mkt_lv_ss     = '' end
    if not _G.mkt_log_f     then _G.mkt_log_f     = imgui.new.char[128](''); _G.mkt_log_fs = '' end
    if not _G.mkt_cp_page   then _G.mkt_cp_page   = 1 end
    if not _G.mkt_lv_page   then _G.mkt_lv_page   = 1 end
    if not _G.mkt_log_f2    then _G.mkt_log_f2    = imgui.new.char[128](''); _G.mkt_log_fs2 = '' end
    if not _G.mkt_log_page  then _G.mkt_log_page  = 1 end
    if not _G.mkt_cp_filter then _G.mkt_cp_filter = 0 end  -- 0=все 1=только с историей
    if not _G.mkt_cp_sort   then _G.mkt_cp_sort   = 0 end  -- 0=Последние продажи 1=Прод.30д 2=Цена 3=А-Я
    local cw = imgui.GetWindowContentRegionWidth()


if imgui.BeginTabBar('##mkt_tabs') then

    -- ================================================================
    -- ВКЛАДКА: РЫНОК (чекпоинт, история по дням)
    -- ================================================================
    if imgui.BeginTabItem(u8'Рынок') then
        local cp_tot = 0; local deep_tot = 0
        for _, e in pairs(fh_mkt_prices) do
            cp_tot = cp_tot + 1
            if e.cp_hist and #e.cp_hist > 0 then deep_tot = deep_tot + 1 end
        end

        -- Статус сканирования
        if fh_mkt_cp_deep_scanning then
            local deep_done = fh_mkt_cp_deep_done or 0
            local deep_pct = (cp_tot > 0) and math.min(deep_done / cp_tot, 1) or (-1 * os.clock())
            imgui.TextColored(imgui.ImVec4(1,0.7,0,1),
                safe_u8('  Углубённый скан: ' .. deep_done .. ' / ' .. cp_tot .. ' товаров...'))
            imgui.ProgressBar(deep_pct, imgui.ImVec2(-1, 8*d))
        elseif fh_mkt_cp_scanning then
            imgui.TextColored(imgui.ImVec4(1,0.75,0,1),
                safe_u8('  Поверхностный скан: стр.' .. fh_mkt_cp_page .. ' | товаров: ' .. cp_tot))
            imgui.ProgressBar(-1 * os.clock(), imgui.ImVec2(-1, 6*d))
        else
            -- Строка состояния: товаров / с историей / обновлено
            local upd_s = fh_mkt_last_update and fh_mkt_last_update or '—'
            imgui.TextDisabled(safe_u8('  Товаров: ' .. cp_tot ..
                ' | С историей: ' .. deep_tot ..
                ' | Обновлено: ' .. upd_s))
            imgui.TextDisabled(u8'  Путь: /gps > Поиск > Центральный Рынок — откройте список товаров')
        end

        -- scan buttons removed

        -- Поиск + фильтр
        imgui.Spacing()
        imgui.PushItemWidth(cw - 110*d)
        if imgui.InputText(u8'##cp_srch', _G.mkt_srch, 256) then
            _G.mkt_srch_s = u8:decode(ffi.string(_G.mkt_srch)):lower()
            _G.mkt_cp_page = 1
            _G.mkt_cp_cache_srch = nil
        end
        imgui.PopItemWidth()
        imgui.SameLine(0, 6*d)
        local filter_lbl = _G.mkt_cp_filter == 1 and u8'? Только' or u8'Все'
        if imgui.Button(filter_lbl .. u8'##cpfltr', imgui.ImVec2(-1, 0)) then
            _G.mkt_cp_filter = (_G.mkt_cp_filter == 0) and 1 or 0
            _G.mkt_cp_cache_srch = nil
            _G.mkt_cp_page = 1
        end
        -- Сортировка
        imgui.Spacing()
        local sort_labels = {
            u8'Посл.  прод.##s0',
            u8'Прод. 30д##s1',
            u8'Цена##s2',
            u8'А-Я##s3',
        }
        local sw4 = (cw - 18*d) / 4
        for si = 0, 3 do
            if si > 0 then imgui.SameLine(0, 6*d) end
            local is_active = (_G.mkt_cp_sort == si)
            if is_active then
                imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(ar*0.6, ag*0.6, 0, 1))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(ar*0.8, ag*0.8, 0, 1))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(ar,     ag,     0, 1))
            end
            if imgui.Button(sort_labels[si+1], imgui.ImVec2(sw4, 0)) then
                _G.mkt_cp_sort = si
                _G.mkt_cp_cache_srch = nil
                _G.mkt_cp_page = 1
            end
            if is_active then imgui.PopStyleColor(3) end
        end
        imgui.Separator()

        -- Кэш списка
        if not _G.mkt_cp_cache_srch then _G.mkt_cp_cache_srch = nil end
        if not _G.mkt_cp_cache_list then _G.mkt_cp_cache_list = {} end
        local srch = _G.mkt_srch_s or ''
        local cache_key = srch .. '|' .. (_G.mkt_cp_filter or 0) .. '|' .. (_G.mkt_cp_sort or 0)
        if _G.mkt_cp_cache_srch ~= cache_key then
            _G.mkt_cp_cache_srch = cache_key
            local mf_new = {}
            for nm, e in pairs(fh_mkt_prices) do
                if type(nm)=='string' and type(e)=='table' then
                    local has_deep = e.cp_hist and #e.cp_hist > 0
                    if _G.mkt_cp_filter == 1 and not has_deep then
                        -- пропускаем товары без истории
                    else
                        if srch == '' or nm:lower():find(srch, 1, true) then
                            if has_deep or e.s_avg or e.b_avg then
                                table.insert(mf_new, {nm=nm, e=e})
                            end
                        end
                    end
                end
            end
            -- Сортируем в зависимости от режима
            local sort_mode = _G.mkt_cp_sort or 0
            if sort_mode == 0 then
                -- Последние продажи (сорт по дате первой записи в истории)
                table.sort(mf_new, function(a, b)
                    local da = (a.e.cp_hist and a.e.cp_hist[1] and a.e.cp_hist[1].dt) or ''
                    local db = (b.e.cp_hist and b.e.cp_hist[1] and b.e.cp_hist[1].dt) or ''
                    if da ~= db then return da > db end
                    return tostring(a.nm) < tostring(b.nm)
                end)
            elseif sort_mode == 1 then
                -- Наибольше продаж за 30 дней
                table.sort(mf_new, function(a, b)
                    local qa = (a.e.s_totalC or 0)
                    local qb = (b.e.s_totalC or 0)
                    if qa ~= qb then return qa > qb end
                    return tostring(a.nm) < tostring(b.nm)
                end)
            elseif sort_mode == 2 then
                -- Цена по средней за 30 дней (по убыванию)
                table.sort(mf_new, function(a, b)
                    local pa = (a.e.s_avg or 0)
                    local pb = (b.e.s_avg or 0)
                    if pa ~= pb then return pa > pb end
                    return tostring(a.nm) < tostring(b.nm)
                end)
            else
                -- Р-П (по алфавиту)
                table.sort(mf_new, function(a, b) return tostring(a.nm) < tostring(b.nm) end)
            end
            _G.mkt_cp_cache_list = mf_new
        end
        local mf = _G.mkt_cp_cache_list
        local MKT_PAGE_SIZE = 50
        local cp_pages = math.max(1, math.ceil(#mf / MKT_PAGE_SIZE))
        if _G.mkt_cp_page > cp_pages then _G.mkt_cp_page = cp_pages end
        local cp_from = (_G.mkt_cp_page-1)*MKT_PAGE_SIZE+1
        local cp_to   = math.min(_G.mkt_cp_page*MKT_PAGE_SIZE, #mf)

        -- Список товаров
        -- Колонки: Товар | Сег. цена | 7дн ср.$ | 30дн ср.$ | Прод.30дн | Тренд
        local list_h = imgui.GetWindowHeight() - 260*d
        if imgui.BeginChild('##cp_list', imgui.ImVec2(-1, list_h), true) then
            imgui.Columns(8, '##cphdr', false)
            imgui.SetColumnWidth(0, 140*d)
            imgui.SetColumnWidth(1, 105*d)
            imgui.SetColumnWidth(2, 50*d)
            imgui.SetColumnWidth(3, 105*d)
            imgui.SetColumnWidth(4, 50*d)
            imgui.SetColumnWidth(5, 105*d)
            imgui.SetColumnWidth(6, 50*d)
            imgui.SetColumnWidth(7, 50*d)
            local hc = imgui.ImVec4(0.6, 0.6, 0.6, 1)
            imgui.TextColored(imgui.ImVec4(ar,ag,0,1), u8' Товар'); imgui.NextColumn()
            imgui.TextColored(imgui.ImVec4(1,0.85,0.2,1), u8' Сег. $'); imgui.NextColumn()
            imgui.TextColored(hc, u8' шт'); imgui.NextColumn()
            imgui.TextColored(imgui.ImVec4(1,0.85,0.2,1), u8' 7дн $'); imgui.NextColumn()
            imgui.TextColored(hc, u8' шт'); imgui.NextColumn()
            imgui.TextColored(imgui.ImVec4(0.4,0.95,0.4,1), u8' 30дн $'); imgui.NextColumn()
            imgui.TextColored(hc, u8' шт'); imgui.NextColumn()
            imgui.TextColored(hc, u8' Тренд'); imgui.NextColumn()
            imgui.Separator()

            if #mf == 0 then
                imgui.TextDisabled(u8'  База пуста. Запустите скан на чекпоинте.')
                for _=1,7 do imgui.NextColumn() end
            end

            for ri = cp_from, cp_to do
                local r = mf[ri]; if not r then break end
                local e = r.e
                local hist = e.cp_hist
                local has_deep = hist and #hist > 0

                -- Считаем статистику
                local today_price = nil
                local s7, s30
                if has_deep then
                    s7  = fh_hist_stats(hist, 7)
                    s30 = fh_hist_stats(hist, 30)
                    -- сегодня = первый элемент истории (самый новый)
                    if hist[1] and hist[1].price then today_price = hist[1].price end
                else
                    -- fallback на shallow
                    s30 = e.s_avg and {avg=e.s_avg, min=e.s_min, max=e.s_max, qty=e.s_totalC or 0} or nil
                    -- сегодня = текущая цена чекпоинта (shallow)
                    if e.cp_sp and e.cp_sp > 0 then today_price = e.cp_sp end
                    -- 7 дней = s_avg (средняя по shallow сканам)
                    if e.s_avg and e.s_avg > 0 then s7 = {avg=e.s_avg} end
                end

                local trend_str = has_deep and fh_trend(hist) or '—'
                local tc = has_deep and fh_trend_color(trend_str) or imgui.ImVec4(0.5,0.5,0.5,1)

                -- Имя товара: ? если есть история
                local nm_lbl = u8'  ' .. safe_u8(r.nm .. '##cp'..ri)
                local nm_c = has_deep and imgui.ImVec4(1,1,1,1) or imgui.ImVec4(0.75,0.75,0.75,1)
                imgui.PushStyleColor(imgui.Col.Text, nm_c)
                if imgui.Selectable(nm_lbl, false,
                    imgui.SelectableFlags.SpanAllColumns + imgui.SelectableFlags.AllowDoubleClick,
                    imgui.ImVec2(0, 0)) then
                    _G.mkt_detail_item = r.nm
                    _G.mkt_detail_src  = 'cp'
                    _G.mkt_detail_open = true
                end
                imgui.PopStyleColor()
                imgui.NextColumn()

                -- Сегодня
                if today_price then
                    imgui.TextColored(imgui.ImVec4(1,0.85,0.2,1), safe_u8(' $'..fh_num_fmt(today_price)))
                else
                    imgui.TextDisabled(u8' —')
                end
                imgui.NextColumn()

                -- Сегодня объём
                local today_qty = has_deep and (fh_hist_stats(hist,1) and fh_hist_stats(hist,1).qty or nil) or nil
                if today_qty and today_qty > 0 then
                    imgui.TextColored(imgui.ImVec4(0.7,0.7,0.7,1), safe_u8(' '..fh_num_fmt(today_qty)))
                else
                    imgui.TextDisabled(u8' —')
                end
                imgui.NextColumn()

                -- 7 дней
                if s7 then
                    imgui.TextColored(imgui.ImVec4(1,0.85,0.2,1), safe_u8(' $'..fh_num_fmt(s7.avg)))
                else
                    imgui.TextDisabled(u8' —')
                end
                imgui.NextColumn()

                -- 7 дней объём
                if s7 and s7.qty and s7.qty > 0 then
                    imgui.TextColored(imgui.ImVec4(0.7,0.7,0.7,1), safe_u8(' '..fh_num_fmt(s7.qty)))
                else
                    imgui.TextDisabled(u8' —')
                end
                imgui.NextColumn()

                -- 30 дней
                if s30 then
                    imgui.TextColored(imgui.ImVec4(0.4,0.95,0.4,1), safe_u8(' $'..fh_num_fmt(s30.avg)))
                else
                    imgui.TextDisabled(u8' —')
                end
                imgui.NextColumn()

                -- Продано за 30дн
                if s30 and s30.qty and s30.qty > 0 then
                    imgui.TextColored(imgui.ImVec4(0.7,0.7,0.7,1), safe_u8(' '..fh_num_fmt(s30.qty)))
                else
                    imgui.TextDisabled(u8' —')
                end
                imgui.NextColumn()

                -- Тренд
                imgui.TextColored(tc, safe_u8(' '..trend_str))
                imgui.NextColumn()
            end
            imgui.Columns(1)
            imgui.EndChild()
        end

        -- Пагинация
        imgui.Spacing()
        local pw = 42*d
        if imgui.Button(u8'<<##cpp',  imgui.ImVec2(pw,0)) then _G.mkt_cp_page=1 end
        imgui.SameLine(0,4*d)
        if imgui.Button(u8'<##cppr',  imgui.ImVec2(pw,0)) then if _G.mkt_cp_page>1 then _G.mkt_cp_page=_G.mkt_cp_page-1 end end
        imgui.SameLine(0,6*d)
        imgui.TextColored(imgui.ImVec4(ar,ag,0,1), safe_u8('Стр. '.._G.mkt_cp_page..'/'..cp_pages..' ('..#mf..' товаров)'))
        imgui.SameLine(0,6*d)
        if imgui.Button(u8'>##cpnx',  imgui.ImVec2(pw,0)) then if _G.mkt_cp_page<cp_pages then _G.mkt_cp_page=_G.mkt_cp_page+1 end end
        imgui.SameLine(0,4*d)
        if imgui.Button(u8'>>##cpls', imgui.ImVec2(pw,0)) then _G.mkt_cp_page=cp_pages end
        imgui.Spacing()
        local hw = (cw - 8*d) / 2
        if imgui.Button(u8'Сохранить##cptsave', imgui.ImVec2(hw,0)) then
            fh_mkt_save(); sampAddChatMessage('[FH Market] {00cc00}Сохранено.',0xFFFFFF)
        end
        imgui.SameLine(0,8*d)
        if imgui.Button(u8'Очистить базу##cptclr', imgui.ImVec2(hw,0)) then
            fh_mkt_prices={}; fh_mkt_last_update=nil; fh_mkt_save()
            _G.mkt_cp_cache_srch=nil; _G.mkt_cp_cache_list={}
            sampAddChatMessage('[FH Market] {ff4444}База цен очищена.',0xFFFFFF)
        end
        imgui.EndTabItem()
    end


    -- ================================================================
    -- ВКЛАДКА: АВТО (цены Авторынка)
    -- ================================================================
    if imgui.BeginTabItem(u8'Авто') then
        if not _G.mkt_auto_srch    then _G.mkt_auto_srch    = imgui.new.char[256]('') end
        if not _G.mkt_auto_srch_s  then _G.mkt_auto_srch_s  = '' end
        if not _G.mkt_auto_page    then _G.mkt_auto_page    = 1 end
        if not _G.mkt_auto_sort    then _G.mkt_auto_sort    = 0 end
        if not _G.mkt_auto_cache_k then _G.mkt_auto_cache_k = nil end
        if not _G.mkt_auto_cache_l then _G.mkt_auto_cache_l = {} end

        local auto_tot = 0; for _ in pairs(fh_mkt_auto) do auto_tot = auto_tot + 1 end

        -- Статус
        if fh_mkt_auto_scanning then
            imgui.TextColored(imgui.ImVec4(1,0.75,0,1),
                safe_u8('  Скан авторынка... стр. ' .. fh_mkt_auto_page))
            imgui.ProgressBar(-1*os.clock(), imgui.ImVec2(-1, 6*d))
        else
            local upd_a = fh_mkt_auto_last_upd or '—'
            imgui.TextDisabled(safe_u8('  Авто: ' .. auto_tot .. ' | Обновлено: ' .. upd_a))
            imgui.TextDisabled(u8'  Путь: /gps > Поиск > Авторынок — откройте список авто')
        end

        imgui.Spacing()
        -- Поиск
        imgui.PushItemWidth(cw - 6*d)
        if imgui.InputText(u8'##auto_srch', _G.mkt_auto_srch, 256) then
            _G.mkt_auto_srch_s = u8:decode(ffi.string(_G.mkt_auto_srch)):lower()
            _G.mkt_auto_page = 1
            _G.mkt_auto_cache_k = nil
        end
        imgui.PopItemWidth()

        -- Сортировка
        imgui.Spacing()
        local auto_sort_labels = {
            u8'Цена (уб.##as0',
            u8'Цена (воз.##as1',
            u8'А-Я##as2',
        }
        local sw3 = (cw - 12*d) / 3
        for si = 0, 2 do
            if si > 0 then imgui.SameLine(0, 6*d) end
            local is_act = (_G.mkt_auto_sort == si)
            if is_act then
                imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(ar*0.6, ag*0.6, 0, 1))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(ar*0.8, ag*0.8, 0, 1))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(ar,     ag,     0, 1))
            end
            if imgui.Button(auto_sort_labels[si+1], imgui.ImVec2(sw3, 0)) then
                _G.mkt_auto_sort = si; _G.mkt_auto_cache_k = nil; _G.mkt_auto_page = 1
            end
            if is_act then imgui.PopStyleColor(3) end
        end
        imgui.Separator()

        -- Кэш + сорт
        local auto_srch = _G.mkt_auto_srch_s or ''
        local auto_ck = auto_srch .. '|' .. (_G.mkt_auto_sort or 0)
        if _G.mkt_auto_cache_k ~= auto_ck then
            _G.mkt_auto_cache_k = auto_ck
            local al = {}
            for nm, e in pairs(fh_mkt_auto) do
                if type(nm)=='string' and type(e)=='table' then
                    if auto_srch=='' or nm:lower():find(auto_srch,1,true) then
                        if e.s_avg or e.cp_sp then table.insert(al, {nm=nm,e=e}) end
                    end
                end
            end
            local sm = _G.mkt_auto_sort or 0
            if sm == 0 then
                table.sort(al, function(a,b)
                    local pa=(a.e.s_avg or a.e.cp_sp or 0); local pb=(b.e.s_avg or b.e.cp_sp or 0)
                    if pa~=pb then return pa > pb end; return tostring(a.nm)<tostring(b.nm)
                end)
            elseif sm == 1 then
                table.sort(al, function(a,b)
                    local pa=(a.e.s_avg or a.e.cp_sp or 0); local pb=(b.e.s_avg or b.e.cp_sp or 0)
                    if pa~=pb then return pa < pb end; return tostring(a.nm)<tostring(b.nm)
                end)
            else
                table.sort(al, function(a,b) return tostring(a.nm)<tostring(b.nm) end)
            end
            _G.mkt_auto_cache_l = al
        end
        local amf = _G.mkt_auto_cache_l or {}
        local AUTO_PAGE = 30
        local auto_pages = math.max(1, math.ceil(#amf / AUTO_PAGE))
        if _G.mkt_auto_page > auto_pages then _G.mkt_auto_page = auto_pages end
        local a_from = (_G.mkt_auto_page-1)*AUTO_PAGE+1
        local a_to   = math.min(_G.mkt_auto_page*AUTO_PAGE, #amf)

        local list_h_a = imgui.GetWindowHeight() - 220*d
        if imgui.BeginChild('##auto_list', imgui.ImVec2(-1, list_h_a), true) then
            imgui.Columns(5,'##autohdr',false)
            imgui.SetColumnWidth(0, cw*0.35); imgui.SetColumnWidth(1, cw*0.20)
            imgui.SetColumnWidth(2, cw*0.15); imgui.SetColumnWidth(3, cw*0.15)
            imgui.SetColumnWidth(4, cw*0.15)
            local hc = imgui.ImVec4(0.6,0.6,0.6,1)
            imgui.TextColored(hc, u8'  Автомобиль'); imgui.NextColumn()
            imgui.TextColored(hc, u8'  Цена $'); imgui.NextColumn()
            imgui.TextColored(hc, u8'  Мин'); imgui.NextColumn()
            imgui.TextColored(hc, u8'  Макс'); imgui.NextColumn()
            imgui.TextColored(hc, u8'  Обнов.'); imgui.NextColumn()
            imgui.Separator()

            if #amf == 0 then
                imgui.TextDisabled(u8'  Список пуст. Откройте Рынок авто и подождите.')
                for _=1,4 do imgui.NextColumn() end
            end

            for ri = a_from, a_to do
                local r = amf[ri]; if not r then break end
                local e = r.e
                local price = e.s_avg or e.cp_sp
                local p_min = e.s_min
                local p_max = e.s_max

                if imgui.Selectable(safe_u8('  ' .. r.nm .. '##asel'..ri), false,
                    imgui.SelectableFlags.SpanAllColumns) then
                    _G.mkt_auto_detail_item = r.nm
                    _G.mkt_auto_detail_open = true
                end
                imgui.NextColumn()
                if price then
                    imgui.TextColored(imgui.ImVec4(1,0.85,0.2,1), safe_u8(' $'..fh_num_fmt(price)))
                else imgui.TextDisabled(u8' —') end
                imgui.NextColumn()
                if p_min then
                    imgui.TextColored(imgui.ImVec4(0.4,0.95,0.4,1), safe_u8(' $'..fh_num_fmt(p_min)))
                else imgui.TextDisabled(u8' —') end
                imgui.NextColumn()
                if p_max then
                    imgui.TextColored(imgui.ImVec4(1,0.5,0.5,1), safe_u8(' $'..fh_num_fmt(p_max)))
                else imgui.TextDisabled(u8' —') end
                imgui.NextColumn()
                imgui.TextColored(imgui.ImVec4(0.55,0.55,0.55,1), safe_u8(' '..(e.date or '—'))); imgui.NextColumn()
            end
            imgui.Columns(1)
            imgui.EndChild()
        end

        -- Пагинация
        imgui.Spacing()
        local pw_a = 42*d
        if imgui.Button(u8'<<##app',  imgui.ImVec2(pw_a,0)) then _G.mkt_auto_page=1 end
        imgui.SameLine(0,4*d)
        if imgui.Button(u8'<##apr',   imgui.ImVec2(pw_a,0)) then if _G.mkt_auto_page>1 then _G.mkt_auto_page=_G.mkt_auto_page-1 end end
        imgui.SameLine(0,6*d)
        imgui.TextColored(imgui.ImVec4(ar,ag,0,1), safe_u8('Стр. '.._G.mkt_auto_page..'/'..auto_pages..' ('..#amf..' авто)'))
        imgui.SameLine(0,6*d)
        if imgui.Button(u8'>##apnx',  imgui.ImVec2(pw_a,0)) then if _G.mkt_auto_page<auto_pages then _G.mkt_auto_page=_G.mkt_auto_page+1 end end
        imgui.SameLine(0,4*d)
        if imgui.Button(u8'>>##apls', imgui.ImVec2(pw_a,0)) then _G.mkt_auto_page=auto_pages end
        imgui.Spacing()
        local hw_a = (cw - 8*d) / 2
        if imgui.Button(u8'Сохранить##atsave', imgui.ImVec2(hw_a,0)) then
            fh_mkt_save(); sampAddChatMessage('[FH Auto] {00cc00}Сохранено.',0xFFFFFF)
        end
        imgui.SameLine(0,8*d)
        if imgui.Button(u8'Очистить базу##atclr', imgui.ImVec2(hw_a,0)) then
            fh_mkt_auto={}; fh_mkt_auto_last_upd=nil; fh_mkt_save()
            _G.mkt_auto_cache_k=nil; _G.mkt_auto_cache_l={}
            sampAddChatMessage('[FH Auto] {ff4444}База авто очищена.',0xFFFFFF)
        end
        imgui.EndTabItem()
    end

    imgui.EndTabBar()
end
end

imgui.OnFrame(function() return MainWindow[0] end, function()
    local d = settings.general.custom_dpi
    -- \xc0\xea\xf6\xe5\xed\xf2\xed\xfb\xe5 \xf6\xe2\xe5\xf2\xe0 \xe2 scope \xe2\xf1\xe5\xe3\xee \xee\xea\xed\xe0 \x97 \xee\xe1\xfa\xff\xe2\xeb\xe5\xed\xfb \xc4\xce \xeb\xfe\xe1\xfb\xf5 child/tab \xe1\xeb\xee\xea\xee\xe2
    local ar = settings.interface.accent_r or 1.0
    local ag = settings.interface.accent_g or 0.65
    local ab = settings.interface.accent_b or 0.0
    imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(780*d, 500*d), imgui.Cond.Always)
    -- Только тайтлбар двигает окно
    imgui.GetIO().ConfigWindowsMoveFromTitleBarOnly = true
    imgui.Begin(u8(' Family Helper v' .. thisScript().version), MainWindow, imgui.WindowFlags.NoCollapse)

    change_dpi()

    if imgui.BeginTabBar('MT', 128) then
        -- ===== \xc3\xcb\xc0\xc2\xcd\xce\xc5 =====
        if imgui.BeginTabItem(u8'\xc3\xeb\xe0\xe2\xed\xee\xe5') then
            local main_h = imgui.GetWindowHeight() - 80*d
            if imgui.BeginTabBar('##maintabs') then
                if imgui.BeginTabItem(u8'\xc4\xe0\xf8\xe1\xee\xf0\xe4') then
                    if imgui.BeginChild('##info', imgui.ImVec2(-1, -1), false) then
                        imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xc8\xed\xf4\xee\xf0\xec\xe0\xf6\xe8\xff \xee \xf1\xe5\xec\xfc\xe5'); imgui.Separator()
                        local online_count = 0
                        for _ in pairs(fmembers_online) do online_count = online_count + 1 end
                        local cw4 = imgui.GetWindowContentRegionWidth() / 4
                        imgui.Columns(4, '##dashcols', false)
                        imgui.SetColumnWidth(0, cw4); imgui.SetColumnWidth(1, cw4); imgui.SetColumnWidth(2, cw4); imgui.SetColumnWidth(3, cw4)
                        imgui.TextColored(imgui.ImVec4(.55,.55,.55,1), u8' \xd1\xe5\xec\xfc\xff:')
                        imgui.Text(safe_u8(' ' .. (settings.family_info.family_name ~= '' and settings.family_info.family_name or '\x97')))
                        imgui.NextColumn()
                        imgui.TextColored(imgui.ImVec4(.55,.55,.55,1), u8' \xcd\xe8\xea:')
                        imgui.Text(safe_u8(' ' .. (settings.family_info.my_name ~= '' and settings.family_info.my_name or '\x97')))
                        imgui.NextColumn()
                        imgui.TextColored(imgui.ImVec4(.55,.55,.55,1), u8' \xd0\xe0\xed\xe3:')
                        imgui.Text(safe_u8(' ' .. (settings.family_info.my_rank ~= '' and settings.family_info.my_rank or '\x97')))
                        imgui.NextColumn()
                        imgui.TextColored(imgui.ImVec4(.55,.55,.55,1), u8' \xce\xed\xeb\xe0\xe9\xed:')
                        if online_count > 0 then
                            imgui.TextColored(imgui.ImVec4(0.2,1.0,0.3,1.0), safe_u8(' ' .. online_count .. ' \xf7\xe5\xeb.'))
                        elseif fmembers_last_update > 0 then
                            imgui.TextColored(imgui.ImVec4(1.0,0.6,0.2,1.0), u8' 0')
                        else
                            imgui.TextDisabled(u8' \x97')
                        end
                        imgui.Columns(1); imgui.Separator()
                        local rows = {
                            {'\xd1\xe5\xec\xfc\xff', 'family_name', input_family_name},
                            {'\xc8\xec\xff',   'my_name',     input_my_name},
                            {'\xd0\xe0\xed\xe3',  'my_rank',     input_my_rank},
                        }
                        local rw = (imgui.GetWindowContentRegionWidth() - 10*d) / #rows
                        for ri, r in ipairs(rows) do
                            if ri > 1 then imgui.SameLine() end
                            if imgui.Button(safe_u8('\xd0\xe5\xe4. ' .. r[1] .. '##rb' .. r[2]), imgui.ImVec2(rw, 24*d)) then
                                if r[2] == 'my_name' then
                                    settings.family_info.my_name = TranslateNick(sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))) or '')
                                    input_my_name = imgui.new.char[256](u8(settings.family_info.my_name)); save_settings()
                                end
                                imgui.OpenPopup(u8('##p' .. r[2]))
                            end
                            if imgui.BeginPopupModal(u8('##p' .. r[2]), nil, imgui.WindowFlags.NoResize + imgui.WindowFlags.AlwaysAutoResize) then
                                change_dpi(); imgui.PushItemWidth(280*d); imgui.InputText('##i' .. r[2], r[3], 256)
                                if imgui.Button(u8' OK##' .. r[2], imgui.ImVec2(280*d, 0)) then
                                    settings.family_info[r[2]] = u8:decode(ffi.string(r[3]))
                                    -- Если сохранили ранг — сразу берём как число
                                    if r[2] == 'my_rank' then
                                        local rval = settings.family_info.my_rank
                                        local rnum = tonumber(rval)
                                        if rnum then
                                            -- Ввели число напрямую
                                            settings.family_info.my_rank_number = math.max(1, math.min(10, rnum))
                                        else
                                            -- Ввели название — ищем в auto_tags
                                            for _, at in ipairs(settings.auto_tags or {}) do
                                                if at.tag == rval then
                                                    settings.family_info.my_rank_number = tonumber(at.rank) or 1
                                                    break
                                                end
                                            end
                                        end
                                    end
                                    save_settings(); imgui.CloseCurrentPopup()
                                end
                                imgui.EndPopup()
                            end
                        end
                        imgui.SameLine()
                        local upd_label = fmembers_last_update > 0
                            and safe_u8('\xce\xed\xeb\xe0\xe9\xed: ' .. (function() local c=0; for _ in pairs(fmembers_online) do c=c+1 end; return c end)() .. ' | \xce\xe1\xed\xee\xe2\xe8\xf2\xfc')
                            or u8('\xc7\xe0\xe3\xf0\xf3\xe7\xe8\xf2\xfc \xee\xed\xeb\xe0\xe9\xed')
                        if imgui.Button(upd_label, imgui.ImVec2(rw, 24*d)) then _G.fmembers_requested = true; sampSendChat('/fmembers') end
                        imgui.SameLine()
                        local cur_rn = settings.family_info.my_rank_number or 1
                        if imgui.Button(safe_u8('\xd0\xe0\xed\xe3: ' .. cur_rn .. ' [-]##rnd'), imgui.ImVec2(rw/2-2, 24*d)) then
                            settings.family_info.my_rank_number = math.max(1, cur_rn - 1); save_settings()
                        end
                        imgui.SameLine()
                        if imgui.Button(u8'[+]##rnu', imgui.ImVec2(rw/2-2, 24*d)) then
                            settings.family_info.my_rank_number = math.min(10, cur_rn + 1); save_settings()
                        end
                        imgui.Spacing(); imgui.Separator(); imgui.Spacing()
                        imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xd1\xef\xe0\xe2\xed \xf2\xf0\xe0\xed\xf1\xef\xee\xf0\xf2\xe0'); imgui.Separator()
                        local spawn_hw = (imgui.GetWindowContentRegionWidth() - 12*d) / 4
                        local spawn_opts = {
                            {'10\xf1##sp10', 10000},
                            {'20\xf1##sp20', 20000},
                            {'30\xf1##sp30', 30000},
                            {'\xd1\xe5\xe9\xf7\xe0\xf1##sp0', 0},
                        }
                        for si, sd in ipairs(spawn_opts) do
                            if si > 1 then imgui.SameLine() end
                            if imgui.Button(u8(sd[1]), imgui.ImVec2(spawn_hw, 28*d)) then
                                lua_thread.create(function()
                                    if sd[2] > 0 then
                                        sampSendChat('/fam \xc2\xed\xe8\xec\xe0\xed\xe8\xe5! \xd7\xe5\xf0\xe5\xe7 ' .. (sd[2]/1000) .. ' \xf1\xe5\xea \xf1\xef\xe0\xe2\xed \xf2\xf0\xe0\xed\xf1\xef\xee\xf0\xf2\xe0!')
                                        wait(sd[2])
                                    end
                                    sampSendChat('/famspawn')
                                    wait(200); sampSendChat('/fam \xd2\xf0\xe0\xed\xf1\xef\xee\xf0\xf2 \xe7\xe0\xf1\xef\xe0\xe2\xed\xe5\xed!')
                                end)
                            end
                        end
                        imgui.Spacing(); imgui.Separator(); imgui.Spacing()
                        imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xc8\xed\xe2\xe0\xe9\xf2\xfb'); imgui.Separator()
                        imgui.TextDisabled(safe_u8('  \xd1\xe5\xf1\xf1\xe8\xff: ' .. invite_session .. '   \xc2\xf1\xe5\xe3\xee: ' .. (settings.general.invite_total or 0) .. '   \xcd\xe5\xee\xef\xeb\xe0\xf7.: ' .. (settings.general.invite_unpaid or 0)))
                        local stat_hw = (imgui.GetWindowContentRegionWidth() - 8*d) / 2
                        if imgui.Button(u8'\xd1\xe1\xf0\xee\xf1 \xf1\xe5\xf1\xf1\xe8\xe8##rstinv', imgui.ImVec2(stat_hw, 24*d)) then invite_session = 0 end
                        imgui.SameLine()
                        if imgui.Button(u8'\xd1\xe1\xf0\xee\xf1 \xe2\xf1\xe5\xe3\xee##rstall', imgui.ImVec2(stat_hw, 24*d)) then
                            invite_session = 0; settings.general.invite_total = 0; save_settings()
                        end
                        imgui.Spacing(); imgui.Separator(); imgui.Spacing()
                        imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xcf\xee\xf1\xeb\xe5\xe4\xed\xe8\xe5 \xf1\xee\xe1\xfb\xf2\xe8\xff'); imgui.Separator()
                        local combined_events = {}
                        local news = famlog and famlog.news or {}
                        for i = 1, math.min(8, #news) do
                            local ev = news[i]
                            if ev then
                                local nick = ev.nick or ''
                                local msg  = ev.msg  or ''
                                local t    = (ev.time or '') ~= '' and ('[' .. ev.time .. '] ') or ''
                                table.insert(combined_events, t .. nick .. (nick ~= '' and ': ' or '') .. msg)
                            end
                        end
                        for _, ev in ipairs(event_log) do
                            table.insert(combined_events, ev)
                            if #combined_events >= 10 then break end
                        end
                        if #combined_events == 0 then
                            imgui.TextDisabled(u8'  \xcd\xe5\xf2 \xf1\xee\xe1\xfb\xf2\xe8\xe9')
                        else
                            for ei = 1, math.min(8, #combined_events) do
                                imgui.TextDisabled(safe_u8('  ' .. combined_events[ei]))
                            end
                        end
                        imgui.EndChild()
                    end
                    imgui.EndTabItem()
                end
                if imgui.BeginTabItem(u8'\xd4\xf3\xed\xea\xf6\xe8\xe8') then
                    if imgui.BeginChild('##func', imgui.ImVec2(-1, -1), false) then
                        imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xd4\xf3\xed\xea\xf6\xe8\xe8 \xf1\xea\xf0\xe8\xef\xf2\xe0'); imgui.Separator()
                        local funcs = {
                            -- столбик 1 (5 штук)
                            {u8'\xc0\xe2\xf2\xee-\xe8\xed\xe2\xe0\xe9\xf2',        'auto_invite',         'g'},
                            {u8'\xc0\xe2\xf2\xee-\xef\xf0\xe8\xe2\xe5\xf2\xf1\xf2\xe2\xe8\xe5',  'auto_welcome',        'g'},
                            {u8'\xc0\xe2\xf2\xee-\xef\xee\xe7\xe4\xf0\xe0\xe2\xeb\xe5\xed\xe8\xe5','auto_congrats',       'g'},
                            {u8'\xc0\xe2\xf2\xee \xea\xe2\xe5\xf1\xf2',            'auto_quest_congrats',  'g'},
                            {u8'\xc8\xed\xe2\xe0\xe9\xf2 \xef\xee \xf1\xeb\xee\xe2\xe0\xec',  'auto_keyword_invite',  'g'},
                            -- столбик 2 (5 штук)
                            {u8'\xd0\xcf-\xf7\xe0\xf2',                   'rp_chat',             'g'},
                            {u8'\xc0\xe2\xf2\xee /vr \xf0\xe5\xea\xeb\xe0\xec\xe0',  'auto_vr_confirm',     'g'},
                            {u8'\xc0\xe2\xf2\xee /ad \xef\xee\xe4\xf2\xe2\xe5\xf0\xe6\xe4\xe5\xed\xe8\xe5',  'auto_ad_confirm',     'g'},
                            {u8'\xc0\xe2\xf2\xee /storage \xf1\xe1\xee\xf0',   'auto_storage_collect', 'g'},
                            {u8'\xc0\xe2\xf2\xee \xd0\xcf-\xee\xf0\xf3\xe6\xe8\xe5',        'auto_rp_guns',         'g'},
                            {u8'\xc0\xe2\xf2\xee-\xec\xf3\xf2 \xec\xe0\xf2\xee\xe2',  'auto_mute_insults',   'g'},
                            {u8'\xc0\xe2\xf2\xee-\xec\xf3\xf2 \xf1\xef\xe0\xec\xe0',  'auto_mute_spam',      'g'},
                            {u8'\xc0\xe2\xf2\xee-\xec\xf3\xf2 \xf4\xeb\xf3\xe4\xe0',  'auto_mute_flood',     'g'},
                            -- столбик 3 (4 штуки — последние)
                            {u8'\xcf\xeb\xe0\xe2\xe0\xfe\xf9\xe0\xff \xea\xed\xee\xef\xea\xe0','float_btn_enable',   'g'},
                            {u8'\xc0\xe2\xf2\xee\xf0\xe5\xea\xee\xed\xed\xe5\xea\xf2','__reconnect',         'r'},
                        }
                        local cw3 = imgui.GetWindowContentRegionWidth()
                        local col_w3 = (cw3 - 12*d) / 3
                        local btn_x3 = col_w3 - 52*d
                        local per_col = 5  -- 5, 6, 4
                        imgui.Columns(3, '##funcols', false)
                        imgui.SetColumnWidth(0, col_w3)
                        imgui.SetColumnWidth(1, col_w3)
                        imgui.SetColumnWidth(2, col_w3)
                        for fi, f in ipairs(funcs) do
                            if fi == per_col + 1 or fi == per_col * 2 + 1 then imgui.NextColumn() end
                            local on
                            if f[3] == 'r' then
                                on = settings.reconnect.enabled
                            else
                                on = settings.general[f[2]]
                            end
                            if on then imgui.TextColored(imgui.ImVec4(0.2,0.85,0.2,1), u8'\x95')
                            else      imgui.TextColored(imgui.ImVec4(0.85,0.2,0.2,1), u8'\x95') end
                            imgui.SameLine(0, 3*d)
                            imgui.Text(f[1])
                            imgui.SameLine(btn_x3)
                            if on then
                                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.15,0.5,0.15,1))
                                if imgui.SmallButton(u8'\xc2\xfb\xea\xeb##fn'..fi) then
                                    if f[3]=='r' then settings.reconnect.enabled=false
                                    else settings.general[f[2]]=false end
                                    save_settings()
                                end
                                imgui.PopStyleColor()
                            else
                                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.4,0.15,0.15,1))
                                if imgui.SmallButton(u8' \xc2\xea\xeb##fn'..fi) then
                                    if f[3]=='r' then settings.reconnect.enabled=true
                                    else settings.general[f[2]]=true end
                                    save_settings()
                                end
                                imgui.PopStyleColor()
                            end
                        end
                        imgui.Columns(1)
                        imgui.Separator(); imgui.Spacing()
                        imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8'); imgui.Separator()
                        local lbl_w = 160*d
                        local sld_w = imgui.GetWindowContentRegionWidth() - lbl_w - 8*d
                        if settings.general.auto_ad_confirm then
                            imgui.TextDisabled(u8' \xd1\xf2\xe0\xed\xf6\xe8\xff /ad:'); imgui.SameLine(lbl_w)
                            local st_names = {u8'Los Santos##adst', u8'Las Venturas##adst', u8'San Fierro##adst'}
                            local st_idx = settings.general.auto_ad_station_idx or 2
                            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.15,0.25,0.45,1))
                            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.2,0.35,0.6,1))
                            if imgui.SmallButton(st_names[st_idx + 1]) then
                                settings.general.auto_ad_station_idx = (st_idx + 1) % 3; save_settings()
                            end
                            imgui.SameLine(0, 16*d)
                            local ad_type_lbl = (settings.general.auto_ad_type or 0) == 0 and u8'\xce\xe1\xfb\xf7\xed\xee\xe5##adtype' or u8'VIP##adtype'
                            if imgui.SmallButton(ad_type_lbl) then
                                settings.general.auto_ad_type = (settings.general.auto_ad_type or 0) == 0 and 1 or 0; save_settings()
                            end
                            imgui.PopStyleColor(2)
                        end
                        if settings.general.auto_mute_insults then
                            imgui.TextDisabled(u8' \xc2\xf0\xe5\xec\xff \xec\xf3\xf2\xe0 \xec\xe0\xf2\xee\xe2 (\xec\xe8\xed):'); imgui.SameLine(lbl_w); imgui.PushItemWidth(sld_w)
                            if imgui.SliderInt('##amtime_insults', sl.auto_mute_time, 1, 300) then settings.general.auto_mute_insults_time=sl.auto_mute_time[0]; save_settings() end
                            imgui.PopItemWidth()
                        end
                        if settings.general.auto_mute_spam then
                            imgui.TextDisabled(u8' \xc2\xf0\xe5\xec\xff \xec\xf3\xf2\xe0 \xf1\xef\xe0\xec\xe0 (\xec\xe8\xed):'); imgui.SameLine(lbl_w); imgui.PushItemWidth(sld_w)
                            if imgui.SliderInt('##amtime_spam', sl.auto_mute_spam_time, 1, 300) then settings.general.auto_mute_spam_time=sl.auto_mute_spam_time[0]; save_settings() end
                            imgui.PopItemWidth()
                        end
                        if settings.general.auto_mute_flood then
                            imgui.TextDisabled(u8' \xc2\xf0\xe5\xec\xff \xec\xf3\xf2\xe0 \xf4\xeb\xf3\xe4\xe0 (\xec\xe8\xed):'); imgui.SameLine(lbl_w); imgui.PushItemWidth(sld_w)
                            if imgui.SliderInt('##amtime_flood', sl.auto_mute_flood_time, 1, 300) then settings.general.auto_mute_flood_time=sl.auto_mute_flood_time[0]; save_settings() end
                            imgui.PopItemWidth()
                            imgui.TextDisabled(u8' \xd4\xeb\xf3\xe4: \xf1\xee\xee\xe1\xf9\xe5\xed\xe8\xe9:'); imgui.SameLine(lbl_w); imgui.PushItemWidth(sld_w)
                            if not sl.flood_msg_count then sl.flood_msg_count = imgui.new.int(settings.general.flood_msg_count or 5) end
                            if imgui.SliderInt('##flood_msg', sl.flood_msg_count, 2, 20) then settings.general.flood_msg_count=sl.flood_msg_count[0]; save_settings() end
                            imgui.PopItemWidth()
                            imgui.TextDisabled(u8' \xd4\xeb\xf3\xe4: \xe7\xe0 \xf1\xe5\xea\xf3\xed\xe4:'); imgui.SameLine(lbl_w); imgui.PushItemWidth(sld_w)
                            if not sl.flood_interval then sl.flood_interval = imgui.new.int(settings.general.flood_interval or 15) end
                            if imgui.SliderInt('##flood_sec', sl.flood_interval, 3, 60) then settings.general.flood_interval=sl.flood_interval[0]; save_settings() end
                            imgui.PopItemWidth()
                            imgui.TextDisabled(safe_u8('  \xec\xf3\xf2 \xe5\xf1\xeb\xe8 ' .. (settings.general.flood_msg_count or 5) .. '+ \xf1\xee\xee\xe1\xf9\xe5\xed\xe8\xe9 \xe7\xe0 ' .. (settings.general.flood_interval or 15) .. ' \xf1\xe5\xea'))
                        end
                        imgui.TextDisabled(u8' \xd0\xe0\xe4\xe8\xf3\xf1 \xe8\xed\xe2\xe0\xe9\xf2\xe0:'); imgui.SameLine(lbl_w); imgui.PushItemWidth(sld_w)
                        if imgui.SliderFloat('##invite_r', sl.invite_radius, 2, 20) then settings.general.auto_invite_radius=sl.invite_radius[0]; save_settings() end
                        imgui.PopItemWidth()
                        imgui.TextDisabled(u8' \xc7\xe0\xe4\xe5\xf0\xe6\xea\xe0 \xe8\xed\xe2\xe0\xe9\xf2\xe0:'); imgui.SameLine(lbl_w); imgui.PushItemWidth(sld_w)
                        if imgui.SliderFloat('##invite_d', sl.invite_delay, 1, 15) then settings.general.auto_invite_delay=sl.invite_delay[0]; save_settings() end
                        imgui.PopItemWidth()
                        imgui.TextDisabled(u8' \xd0\xe0\xe4\xe8\xf3\xf1 \xea\xed\xee\xef\xea\xe8:'); imgui.SameLine(lbl_w); imgui.PushItemWidth(sld_w)
                        if imgui.SliderFloat('##float_r', sl.float_radius, 5, 50) then settings.general.float_btn_radius=sl.float_radius[0]; save_settings() end
                        imgui.PopItemWidth()
                        imgui.EndChild()
                    end
                    imgui.EndTabItem()
                end
                imgui.EndTabBar()
            end
            imgui.EndTabItem()
        end


        -- ===== КОМАНДЫ + ВЕРБОВКА + ПИАР + ТЕКСТЫ =====
        if imgui.BeginTabItem(u8'\xca\xee\xec\xe0\xed\xe4\xfb') then
            if imgui.BeginTabBar('##cmdtabs') then
            if imgui.BeginTabItem(u8'\xca\xee\xec\xe0\xed\xe4\xfb') then
            -- ===== \xc1\xdb\xd1\xd2\xd0\xdb\xc5 \xc4\xc5\xc9\xd1\xd2\xc2\xc8\xdf =====
            local qa_h = 125*d
            if imgui.BeginChild('##quick_actions', imgui.ImVec2(-1, 192*d), true) then
                imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xc1\xfb\xf1\xf2\xf0\xfb\xe5 \xe4\xe5\xe9\xf1\xf2\xe2\xe8\xff'); imgui.Separator()

                -- ===== \xd0\xcf \xc8\xcd\xc2\xc0\xc9\xd2 =====
                imgui.PushItemWidth(50*d); imgui.InputTextWithHint('##inv_id', 'ID', qa.invite_id, 32); imgui.PopItemWidth()
                imgui.SameLine(0,4)
                if imgui.Button(u8' \xd0\xcf \xc8\xed\xe2\xe0\xe9\xf2 ', imgui.ImVec2(120*d, 0)) then
                    local id = ffi.string(qa.invite_id)
                    if id ~= '' then send_lines(settings.rp_invite.text, settings.rp_invite.waiting, tonumber(id)) end
                end
                imgui.SameLine(0,6); imgui.TextDisabled(u8'/faminvite ID \xcf\xee \xd0\xcf')

                -- ===== \xcc\xd3\xd2 =====
                imgui.PushItemWidth(50*d); imgui.InputTextWithHint('##mute_id2', 'ID', qa.mute_id, 32); imgui.PopItemWidth()
                imgui.SameLine(0,4)
                imgui.PushItemWidth(55*d); imgui.InputTextWithHint(u8'##mute2', u8'\xcc\xe8\xed.', qa.mute_time, 32); imgui.PopItemWidth()
                imgui.SameLine(0,4)
                imgui.PushItemWidth(330*d); imgui.InputTextWithHint(u8'##muter', u8'\xcf\xf0\xe8\xf7\xe8\xed\xe0', qa.mute_reason, 128); imgui.PopItemWidth()
                imgui.SameLine(0,4)
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.6,0.1,0.1,1))
                if imgui.Button(u8'\xcc\xf3\xf2##m2', imgui.ImVec2(85*d, 0)) then
                    local id=ffi.string(qa.mute_id); local t=ffi.string(qa.mute_time); local r=u8:decode(ffi.string(qa.mute_reason))
                    if id~='' and t~='' then sampSendChat(string.format('/fammute %s %s %s', id, t, r)) end
                end
                imgui.PopStyleColor()
                imgui.SameLine(0,2)
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.1,0.45,0.1,1))
                if imgui.Button(u8'-\xcc\xf3\xf2##um2', imgui.ImVec2(85*d, 0)) then
                    local id=ffi.string(qa.mute_id)
                    if id~='' then sampSendChat(string.format('/famunmute %s', id)) end
                end
                imgui.PopStyleColor()

                -- ===== \xd0\xc0\xcd\xc3 =====
                imgui.PushItemWidth(50*d); imgui.InputTextWithHint('##rank_id2', 'ID', qa.rank_id, 32); imgui.PopItemWidth()
                imgui.SameLine(0,4)
                if imgui.Button(u8'-##rkd2', imgui.ImVec2(22*d,0)) then local v=tonumber(ffi.string(qa.rank_val)) or 1; ffi.copy(qa.rank_val, tostring(math.max(1,v-1))) end
                imgui.SameLine(0,2)
                imgui.PushItemWidth(32*d); imgui.InputText('##rkv2', qa.rank_val, 32); imgui.PopItemWidth()
                imgui.SameLine(0,2)
                if imgui.Button(u8'+##rku2', imgui.ImVec2(22*d,0)) then local v=tonumber(ffi.string(qa.rank_val)) or 0; ffi.copy(qa.rank_val, tostring(math.min(10,v+1))) end
                imgui.SameLine(0,4)
                if imgui.Button(u8'\xd0\xe0\xed\xe3##rkset2', imgui.ImVec2(85*d, 0)) then
                    local id=ffi.string(qa.rank_id); local rank=ffi.string(qa.rank_val)
                    if id~='' and rank~='' then
                    if id~='' and rank~='' then
                        sampSendChat(string.format('/setfrank %s %s', id, rank))
                        -- \xc0\xe2\xf2\xee-\xf2\xe5\xe3: \xe5\xf1\xeb\xe8 \xe5\xf1\xf2\xfc \xed\xe8\xea \xe8\xe3\xf1\xee\xea\xe0 (\xe8\xe7 fmembers_online) -> /ftag
                        local rank_nick = nil
                        -- \xef\xfb\xf2\xe0\xe5\xec\xf1\xff \xed\xe0\xe9\xf2\xe8 \xed\xe8\xea \xef\xee ID
                        if sampIsPlayerConnected(tonumber(id)) then
                            rank_nick = sampGetPlayerNickname(tonumber(id))
                        end
                        if rank_nick then
                            for _, t in ipairs(settings.auto_tags) do
                                if tostring(t.rank) == tostring(rank) and t.tag ~= '' then
                                    lua_thread.create(function()
                                        wait(600)
                                        sampSendChat('/ftag ' .. rank_nick .. ' ' .. t.tag)
                                        sampAddChatMessage('[Family Helper] {aaffaa}/ftag ' .. rank_nick .. ' ' .. t.tag, 0xFFA500)
                                    end)
                                    break
                                end
                            end
                        end
                    end
                    end
                end

                -- ===== \xca\xc8\xca =====
                imgui.PushItemWidth(50*d); imgui.InputTextWithHint('##kick_id2', 'ID', qa.kick_id, 32); imgui.PopItemWidth()
                imgui.SameLine(0,4)
                imgui.PushItemWidth(400*d); imgui.InputTextWithHint(u8'##kickr', u8'\xcf\xf0\xe8\xf7\xe8\xed\xe0', qa.kick_reason, 128); imgui.PopItemWidth()
                imgui.SameLine(0,4)
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.55,0.1,0.1,1))
                if imgui.Button(u8'\xca\xe8\xea##k2', imgui.ImVec2(85*d, 0)) then
                    local id=ffi.string(qa.kick_id); local r=u8:decode(ffi.string(qa.kick_reason))
                    if id~='' then sampSendChat(string.format('/famuninvite %s %s', id, r)) end
                end
                imgui.PopStyleColor()

                -- ===== \xca\xc8\xca \xce\xd4\xd4\xcb\xc0\xc9\xcd =====
                imgui.PushItemWidth(460*d)
                imgui.InputTextWithHint(u8'##offkick_n', 'Nick_Name', qa.offkick_nick, 64)
                imgui.PopItemWidth()
                imgui.SameLine(0,4)
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.55,0.1,0.1,1))
                if imgui.Button(u8'\xca\xe8\xea \xee\xf4\xf4\xeb\xe0\xe9\xed##offk', imgui.ImVec2(125*d, 0)) then
                    local nick = u8:decode(ffi.string(qa.offkick_nick)):match('^%s*(.-)%s*$')
                    if nick ~= '' then sampSendChat('/famoffkick ' .. nick) end
                end
                imgui.PopStyleColor()

                imgui.EndChild()
            end

                        -- ===== \xcb\xc8\xd1\xd2 \xca\xce\xcc\xc0\xcd\xc4 =====
            local cmds_h = imgui.GetWindowHeight() - qa_h - 80*d
            if imgui.BeginChild('##cmds', imgui.ImVec2(-1, cmds_h), true) then
                local cw = imgui.GetWindowContentRegionWidth()
                local col_cmd = 115*d; local col_desc = cw - col_cmd - 130*d; local col_btns = 130*d
                imgui.Columns(4, '##cmdhdr', false)
                imgui.SetColumnWidth(0, 18*d)
                imgui.SetColumnWidth(1, col_cmd)
                imgui.SetColumnWidth(2, col_desc)
                imgui.SetColumnWidth(3, col_btns)
                -- header
                imgui.NextColumn(); imgui.TextDisabled(u8'\xca\xee\xec\xe0\xed\xe4\xe0')
                imgui.NextColumn(); imgui.TextDisabled(u8'\xce\xef\xe8\xf1\xe0\xed\xe8\xe5')
                imgui.NextColumn(); imgui.TextDisabled(u8'\xc4\xe5\xe9\xf1\xf2\xe2\xe8\xff')
                imgui.NextColumn(); imgui.Columns(1); imgui.Separator()

                for _, c in ipairs(settings.commands) do
                    if not c.deleted then
                        imgui.Columns(4, '##cmdrow_'..(c.cmd or''), false)
                        imgui.SetColumnWidth(0, 18*d)
                        imgui.SetColumnWidth(1, col_cmd)
                        imgui.SetColumnWidth(2, col_desc)
                        imgui.SetColumnWidth(3, col_btns)
                        -- dot indicator
                        if c.enable then
                            imgui.TextColored(imgui.ImVec4(0.2,0.85,0.2,1), u8'\x95')
                        else
                            imgui.TextColored(imgui.ImVec4(0.85,0.2,0.2,1), u8'\x95')
                        end
                        imgui.NextColumn()
                        local cn = '/'..safe_u8(c.cmd)
                        if c.enable then imgui.Text(cn) else imgui.TextDisabled(cn) end
                        imgui.NextColumn()
                        local cd = safe_u8(c.description)
                        if c.enable then imgui.Text(cd) else imgui.TextDisabled(cd) end
                        imgui.NextColumn()
                        -- toggle ON/OFF
                        if c.enable then
                            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.15,0.5,0.15,1))
                            if imgui.SmallButton(u8'\xc2\xca\xcb##t'..(c.cmd or'')) then c.enable=false; save_settings(); pcall(sampUnregisterChatCommand, c.cmd) end
                            imgui.PopStyleColor()
                        else
                            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.4,0.15,0.15,1))
                            if imgui.SmallButton(u8'\xc2\xdb\xca\xcb##t'..(c.cmd or'')) then c.enable=true; save_settings(); if(c.cmd or'')~='' then reg_cmd(c.cmd,c.arg,c.text,tonumber(c.waiting)) end end
                            imgui.PopStyleColor()
                        end
                        imgui.SameLine()
                        if imgui.SmallButton(u8'\xd0\xe5\xe4##e'..(c.cmd or'')) then
                            change_description=c.description or''; input_description=imgui.new.char[256](safe_u8(change_description))
                            change_arg=c.arg or''; ComboTags[0]=({['']=0,['{arg}']=1,['{arg_id}']=2,['{arg_id} {arg2}']=3})[change_arg] or 0
                            change_cmd=c.cmd or''; input_cmd=imgui.new.char[256](safe_u8(c.cmd))
                            change_text=(c.text or''):gsub('&','\n'); input_text=imgui.new.char[8192](safe_u8(change_text))
                            change_waiting=c.waiting or'1.500'; waiting_slider=imgui.new.float(tonumber(change_waiting) or 1.5)
                            BinderWindow[0]=true
                        end
                        imgui.SameLine()
                        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.4,0.1,0.1,1))
                        if imgui.SmallButton('X##d'..(c.cmd or'')) then c.deleted=true; c.enable=false; pcall(sampUnregisterChatCommand, c.cmd); save_settings() end
                        imgui.PopStyleColor()
                        imgui.NextColumn(); imgui.Columns(1); imgui.Separator()
                    end
                end
                imgui.EndChild()
            end
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(ar*0.3,ag*0.3,ab*0.3,1))
            if imgui.Button(u8' + \xca\xee\xec\xe0\xed\xe4\xe0', imgui.ImVec2(-1, 0)) then
                local nc={cmd='',description='\xcd\xee\xe2\xe0\xff',text='',arg='',enable=true,waiting='1.500',deleted=false}
                table.insert(settings.commands, nc)
                change_description=nc.description; input_description=imgui.new.char[256](u8(nc.description))
                change_arg=''; ComboTags[0]=0; change_cmd=''; input_cmd=imgui.new.char[256]('')
                change_text=''; input_text=imgui.new.char[8192](''); change_waiting='1.500'; waiting_slider=imgui.new.float(1.5)
                BinderWindow[0]=true
            end
            imgui.PopStyleColor()
            imgui.EndTabItem()
            end
            if imgui.BeginTabItem(u8'\xc2\xe5\xf0\xe1\xee\xe2\xea\xe0') then
            local verb_h = imgui.GetWindowHeight() - 80*d
            local ar3 = settings.interface.accent_r or 1
            local ag3 = settings.interface.accent_g or .65
            if imgui.BeginTabBar('##verbtabs') then
                if imgui.BeginTabItem(u8'\xd8\xe0\xe3\xe8') then
                    if imgui.BeginChild('##verb_steps', imgui.ImVec2(-1, verb_h), false) then
                        imgui.TextColored(imgui.ImVec4(ar3,ag3,0,1), u8' \xd8\xe0\xe3\xe8 \xe2\xe5\xf0\xe1\xee\xe2\xea\xe8')
                        imgui.SameLine()
                        imgui.TextDisabled(u8'  {get_ru_nick} {arg_id} {family_name} {my_name}  | /fi [ID]')
                        imgui.Separator()
                        if imgui.BeginChild('##inters', imgui.ImVec2(-1, 215*d), true) then
                            for i, inter in ipairs(settings.interactions) do
                                imgui.Columns(2, '##intcol'..i, false)
                                imgui.SetColumnWidth(0, 555*d)
                                imgui.TextColored(imgui.ImVec4(0.2,0.85,0.2,1), u8'\x95')
                                imgui.SameLine(0, 4)
                                imgui.Text(safe_u8(' ' .. (inter.name or '')))
                                imgui.NextColumn()
                                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.15,0.35,0.55,1))
                                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.2,0.45,0.7,1))
                                if imgui.SmallButton(u8('\xd0\xe5\xe4.##ie'..i)) then interact_edit_index=i; InteractEditWindow[0]=true end
                                imgui.PopStyleColor(2)
                                imgui.SameLine()
                                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.45,0.1,0.1,1))
                                if imgui.SmallButton('X##id'..i) then table.remove(settings.interactions, i); save_settings() end
                                imgui.PopStyleColor()
                                imgui.Columns(1)
                                imgui.PushStyleColor(imgui.Col.Separator, imgui.ImVec4(0.3,0.2,0.0,0.6))
                                imgui.Separator()
                                imgui.PopStyleColor()
                            end
                            imgui.EndChild()
                        end
                        local add_bw = (imgui.GetWindowContentRegionWidth() - 4*d) / 2
                        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.1,0.35,0.1,1))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.15,0.5,0.15,1))
                        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.2,0.6,0.2,1))
                        if imgui.Button(u8' + \xc4\xee\xe1\xe0\xe2\xe8\xf2\xfc \xf8\xe0\xe3##addstp', imgui.ImVec2(add_bw, 0)) then
                            table.insert(settings.interactions, {name='\xcd\xee\xe2\xfb\xe9', lines={'\xd2\xe5\xea\xf1\xf2'}, waiting=1.5}); save_settings()
                            interact_edit_index=#settings.interactions; InteractEditWindow[0]=true
                        end
                        imgui.PopStyleColor(3)
                        imgui.SameLine()
                        imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(0.5,0.1,0.1,1))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.7,0.2,0.2,1))
                        imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(0.9,0.3,0.3,1))
                        if imgui.Button(u8' \xd1\xe1\xf0\xee\xf1\xe8\xf2\xfc \xed\xe0 \xf1\xf2\xe0\xed\xe4\xe0\xf0\xf2\xed\xfb\xe5##rststp', imgui.ImVec2(add_bw, 0)) then
                    settings.interactions = {
                        { name = '1. \xcf\xf0\xe8\xe2\xe5\xf2\xf1\xf2\xe2\xe8\xe5', lines = {
                            '/me \xef\xee\xe4\xf5\xee\xe4\xe8\xf2 \xea {get_ru_nick} \xe8 \xef\xf0\xee\xf2\xff\xe3\xe8\xe2\xe0\xe5\xf2 \xf0\xf3\xea\xf3',
                            '\xcf\xf0\xe8\xe2\xe5\xf2, {get_ru_nick}! \xc5\xf1\xf2\xfc \xec\xe8\xed\xf3\xf2\xea\xe0 \xef\xee\xe3\xee\xe2\xee\xf0\xe8\xf2\xfc?',
                        }, waiting = 2.5 },
                        { name = '2. \xcf\xf0\xe5\xe4\xeb\xee\xe6\xe5\xed\xe8\xe5', lines = {
                            '\xdf \xef\xf0\xe5\xe4\xf1\xf2\xe0\xe2\xeb\xff\xfe \xf1\xe5\xec\xfc\xfe {family_name}, \xec\xfb \xf1\xe5\xe9\xf7\xe0\xf1 \xed\xe0\xe1\xe8\xf0\xe0\xe5\xec \xeb\xfe\xe4\xe5\xe9.',
                            '\xd5\xee\xf2\xe5\xeb \xe1\xfb \xef\xf0\xe5\xe4\xeb\xee\xe6\xe8\xf2\xfc \xf2\xe5\xe1\xe5 \xea \xed\xe0\xec \xe2\xf1\xf2\xf3\xef\xe8\xf2\xfc.',
                        }, waiting = 2.5 },
                        { name = '3. \xce \xf1\xe5\xec\xfc\xe5', lines = {
                            '\xd1\xe5\xec\xfc\xff {family_name} \x97 \xe0\xea\xf2\xe8\xe2\xed\xfb\xe9 \xea\xee\xeb\xeb\xe5\xea\xf2\xe8\xe2, \xe4\xe0\xe2\xed\xee \xed\xe0 \xf1\xe5\xf0\xe2\xe5\xf0\xe5.',
                            '\xc5\xf1\xf2\xfc \xf1\xe2\xee\xff \xea\xe2\xe0\xf0\xf2\xe8\xf0\xe0, \xf2\xf0\xe0\xed\xf1\xef\xee\xf0\xf2, \xef\xf0\xee\xea\xe0\xf7\xe0\xed\xed\xfb\xe5 \xf3\xeb\xf3\xf7\xf8\xe5\xed\xe8\xff.',
                        }, waiting = 2.5 },
                        { name = '4. \xcf\xeb\xfe\xf1\xfb', lines = {
                            '\xc8\xe7 \xef\xeb\xfe\xf1\xee\xe2: \xef\xee\xe2\xfb\xf8\xe5\xed\xed\xe0\xff \xe7\xe0\xf0\xef\xeb\xe0\xf2\xe0 \xed\xe0 \xf0\xe0\xe1\xee\xf2\xe0\xf5 \xee\xf2 \xf3\xeb\xf3\xf7\xf8\xe5\xed\xe8\xe9 \xf1\xe5\xec\xfc\xe8,',
                            '\xe4\xee\xf1\xf2\xf3\xef \xea \xf1\xe5\xec\xe5\xe9\xed\xee\xe9 \xea\xe2\xe0\xf0\xf2\xe8\xf0\xe5, \xf1\xee\xe2\xec\xe5\xf1\xf2\xed\xfb\xe5 \xea\xe2\xe5\xf1\xf2\xfb \xe8 \xed\xe0\xe3\xf0\xe0\xe4\xfb.',
                        }, waiting = 2.5 },
                        { name = '5. \xd3\xf1\xeb\xee\xe2\xe8\xff', lines = {
                            '\xd3\xf1\xeb\xee\xe2\xe8\xff \xef\xf0\xee\xf1\xf2\xfb\xe5 \x97 \xe0\xea\xf2\xe8\xe2\xed\xee\xf1\xf2\xfc \xe8 \xf1\xee\xe1\xeb\xfe\xe4\xe5\xed\xe8\xe5 \xef\xf0\xe0\xe2\xe8\xeb \xf1\xe5\xec\xfc\xe8.',
                            '\xcb\xe8\xe4\xe5\xf0 \x97 {my_name}, \xe2\xf1\xe5\xe3\xe4\xe0 \xed\xe0 \xf1\xe2\xff\xe7\xe8, \xef\xee\xec\xee\xe6\xe5\xec \xee\xf1\xe2\xee\xe8\xf2\xfc\xf1\xff.',
                        }, waiting = 2.5 },
                        { name = '6. \xc8\xed\xe2\xe0\xe9\xf2 (\xd0\xcf)', lines = {
                            '/me \xe4\xee\xf1\xf2\xe0\xb8\xf2 \xf2\xe5\xeb\xe5\xf4\xee\xed \xe8 \xee\xf2\xea\xf0\xfb\xe2\xe0\xe5\xf2 \xef\xf0\xe8\xeb\xee\xe6\xe5\xed\xe8\xe5 \xf1\xe5\xec\xfc\xe8',
                            '/do \xcd\xe0 \xfd\xea\xf0\xe0\xed\xe5 \xef\xee\xff\xe2\xeb\xff\xe5\xf2\xf1\xff \xf4\xee\xf0\xec\xe0 \xef\xf0\xe8\xe3\xeb\xe0\xf8\xe5\xed\xe8\xff.',
                            '\xce\xf2\xef\xf0\xe0\xe2\xeb\xff\xfe \xf2\xe5\xe1\xe5 \xef\xf0\xe8\xe3\xeb\xe0\xf8\xe5\xed\xe8\xe5 \x97 \xed\xe0\xef\xe8\xf8\xe8 /offer \xf7\xf2\xee\xe1\xfb \xe2\xf1\xf2\xf3\xef\xe8\xf2\xfc.',
                            '/faminvite {arg_id}',
                        }, waiting = 2.0 },
                        { name = '7. \xcd\xe0\xef\xee\xec\xed\xe8\xf2\xfc /offer', lines = {
                            '\xcf\xee\xeb\xf3\xf7\xe8\xeb \xef\xf0\xe8\xe3\xeb\xe0\xf8\xe5\xed\xe8\xe5? \xcd\xe0\xef\xe8\xf8\xe8 \xe2 \xf7\xe0\xf2 /offer \xf7\xf2\xee\xe1\xfb \xe2\xf1\xf2\xf3\xef\xe8\xf2\xfc!',
                        }, waiting = 2.0 },
                        { name = '8. \xce\xf2\xea\xe0\xe7', lines = {
                            '/me \xef\xee\xed\xe8\xec\xe0\xfe\xf9\xe5 \xea\xe8\xe2\xe0\xe5\xf2',
                            '\xc1\xe5\xe7 \xef\xf0\xee\xe1\xeb\xe5\xec, \xe5\xf1\xeb\xe8 \xef\xe5\xf0\xe5\xe4\xf3\xec\xe0\xe5\xf8\xfc \x97 \xef\xe8\xf8\xe8 \xe2 \xeb\xfe\xe1\xee\xe5 \xe2\xf0\xe5\xec\xff. \xd3\xe4\xe0\xf7\xe8!',
                        }, waiting = 2.5 },
                    }
                            save_settings()
                        end
                        imgui.PopStyleColor(3)
                    imgui.EndChild()
                    end
                    imgui.EndTabItem()
                end
                if imgui.BeginTabItem(u8'\xc0\xe2\xf2\xee-\xe8\xed\xe2\xe0\xe9\xf2') then
                    if imgui.BeginChild('##verb_ai', imgui.ImVec2(-1, verb_h), false) then
                        imgui.TextColored(imgui.ImVec4(ar3,ag3,0,1), u8' \xc0\xe2\xf2\xee-\xe8\xed\xe2\xe0\xe9\xf2: \xea\xeb\xfe\xf7\xe5\xe2\xfb\xe5 \xf1\xeb\xee\xe2\xe0'); imgui.Separator()
                        imgui.TextDisabled(u8' \xc8\xe3\xf0\xee\xea \xed\xe0\xef\xe8\xf1\xe0\xeb \xf1\xeb\xee\xe2\xee \xe8\xe7 \xf1\xef\xe8\xf1\xea\xe0 -> \xf1\xea\xf0\xe8\xef\xf2 \xf1\xe0\xec \xee\xf2\xef\xf0\xe0\xe2\xe8\xf2 /faminvite')
                        imgui.Spacing()
                        imgui.TextDisabled(u8' \xd0\xe0\xe4\xe8\xf3\xf1 \xe8\xed\xe2\xe0\xe9\xf2\xe0:'); imgui.SameLine(); imgui.PushItemWidth(140*d)
                        if imgui.SliderFloat('##kai_r', sl.invite_radius, 2, 20) then settings.general.auto_invite_radius=sl.invite_radius[0]; save_settings() end
                        imgui.PopItemWidth()
                        imgui.TextDisabled(u8' \xc7\xe0\xe4\xe5\xf0\xe6\xea\xe0 (\xf1):'); imgui.SameLine(); imgui.PushItemWidth(140*d)
                        if imgui.SliderFloat('##kai_d', sl.invite_delay, 1, 15) then settings.general.auto_invite_delay=sl.invite_delay[0]; save_settings() end
                        imgui.PopItemWidth()
                        imgui.Spacing(); imgui.Separator(); imgui.Spacing()
                        do
                            local kai = settings.general.auto_keyword_invite
                            if kai then imgui.TextColored(imgui.ImVec4(0.2,0.85,0.2,1), u8'\x95')
                            else        imgui.TextColored(imgui.ImVec4(0.85,0.2,0.2,1), u8'\x95') end
                            imgui.SameLine()
                            imgui.Text(u8'\xc0\xe2\xf2\xee \xef\xee \xf1\xeb\xee\xe2\xe0\xec'); imgui.SameLine()
                            if kai then
                                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.15,0.5,0.15,1))
                                if imgui.SmallButton(u8'\xc2\xfb\xea\xeb##kai') then settings.general.auto_keyword_invite=false; save_settings() end
                                imgui.PopStyleColor()
                            else
                                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.4,0.15,0.15,1))
                                if imgui.SmallButton(u8' \xc2\xea\xeb##kai') then settings.general.auto_keyword_invite=true; save_settings() end
                                imgui.PopStyleColor()
                            end
                        end
                        imgui.Spacing()
                        if imgui.BeginChild('##kwlist', imgui.ImVec2(-1, 75*d), true) then
                            local kwl = settings.general.keyword_invite_list or {}
                            local rm_kw = nil
                            local cols = 3
                            for ki, kw in ipairs(kwl) do
                                if (ki-1) % cols ~= 0 then imgui.SameLine() end
                                local bw_kw = (imgui.GetWindowContentRegionWidth() - (cols-1)*5*d) / cols
                                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.18,0.18,0.28,1))
                                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.5,0.12,0.12,1))
                                if imgui.Button(safe_u8(kw .. ' x##kw'..ki), imgui.ImVec2(bw_kw, 22*d)) then rm_kw = ki end
                                imgui.PopStyleColor(2)
                            end
                            if rm_kw then table.remove(settings.general.keyword_invite_list, rm_kw); save_settings() end
                            imgui.EndChild()
                        end
                        imgui.PushItemWidth(340*d)
                        imgui.InputText(u8'##kwinput', kw_input, 128)
                        imgui.PopItemWidth(); imgui.SameLine()
                        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.1,0.35,0.1,1))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.15,0.5,0.15,1))
                        if imgui.Button(u8' + \xc4\xee\xe1\xe0\xe2\xe8\xf2\xfc##kwbtn') then
                            local kw_new = u8:decode(ffi.string(kw_input)):match('^%s*(.-)%s*$')
                            if kw_new ~= '' then
                                if not settings.general.keyword_invite_list then settings.general.keyword_invite_list = {} end
                                table.insert(settings.general.keyword_invite_list, kw_new:lower())
                                save_settings(); kw_input[0] = 0
                            end
                        end
                        imgui.PopStyleColor(2)
                    imgui.EndChild()
                    end
                    imgui.EndTabItem()
                end
                imgui.EndTabBar()
            end
            imgui.EndTabItem()
            end
            if imgui.BeginTabItem(u8'\xd2\xe5\xea\xf1\xf2\xfb') then
            local texts_h = imgui.GetWindowHeight() - 80*d
            if imgui.BeginChild('##texts_wrap', imgui.ImVec2(-1, texts_h), false) then
                local ar_t = settings.interface.accent_r or 1
                local ag_t = settings.interface.accent_g or .65
                local avail_w = imgui.GetWindowContentRegionWidth()
                local tw_btns = 80*d   -- \xea\xed\xee\xef\xea\xe8 - + \xf1 X
                local tw_time = 80*d   -- \xef\xee\xeb\xe5 \xf2\xe0\xe9\xec\xe5\xf0\xe0
                local tw_idx  = 16*d   -- \xed\xee\xec\xe5\xf0 \xf1\xf2\xf0\xee\xea\xe8
                local tw_gap  = 24*d   -- \xee\xf2\xf1\xf2\xf3\xef\xfb \xec\xe5\xe6\xe4\xf3 \xfd\xeb\xe5\xec\xe5\xed\xf2\xe0\xec\xe8
                local tw_field = math.max(80*d, avail_w - tw_btns - tw_time - tw_idx - tw_gap)

                -- \xc2\xf1\xef\xee\xec\xee\xe3\xe0\xf2\xe5\xeb\xfc\xed\xe0\xff \xf4\xf3\xed\xea\xf6\xe8\xff \xee\xf2\xf0\xe8\xf1\xee\xe2\xea\xe8 \xe7\xe0\xe3\xee\xeb\xee\xe2\xea\xe0 \xf1\xe5\xea\xf6\xe8\xe8
                local function section_header(icon_text, title_text, hint_text)
                    imgui.Spacing()
                    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(ar_t*0.12, ag_t*0.12, 0.0, 1.0))
                    imgui.BeginChild('##hdr_'..title_text, imgui.ImVec2(-1, 26*d), false)
                        imgui.SetCursorPosY(imgui.GetCursorPosY() + 4*d)
                        imgui.TextColored(imgui.ImVec4(ar_t, ag_t, 0.1, 1), u8(icon_text .. '  ' .. title_text))
                    imgui.EndChild()
                    imgui.PopStyleColor()
                    if hint_text and hint_text ~= '' then
                        imgui.TextDisabled(u8('  ' .. hint_text))
                    end
                    imgui.Spacing()
                end

                -- \xc2\xf1\xef\xee\xec\xee\xe3\xe0\xf2\xe5\xeb\xfc\xed\xe0\xff \xf4\xf3\xed\xea\xf6\xe8\xff \xea\xed\xee\xef\xea\xe8 \xc2\xea\xeb/\xc2\xfb\xea\xeb
                local function toggle_button(label_on, label_off, id, state, on_cb, off_cb)
                    if state then
                        imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(0.10, 0.45, 0.10, 1))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered,  imgui.ImVec4(0.12, 0.55, 0.12, 1))
                        imgui.PushStyleColor(imgui.Col.ButtonActive,   imgui.ImVec4(0.08, 0.38, 0.08, 1))
                        if imgui.Button(u8('  ' .. label_on .. '  ##' .. id), imgui.ImVec2(70*d, 22*d)) then off_cb() end
                        imgui.PopStyleColor(3)
                    else
                        imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(0.38, 0.10, 0.10, 1))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered,  imgui.ImVec4(0.48, 0.12, 0.12, 1))
                        imgui.PushStyleColor(imgui.Col.ButtonActive,   imgui.ImVec4(0.30, 0.08, 0.08, 1))
                        if imgui.Button(u8('  ' .. label_off .. '  ##' .. id), imgui.ImVec2(70*d, 22*d)) then on_cb() end
                        imgui.PopStyleColor(3)
                    end
                end

                -- \xc2\xf1\xef\xee\xec\xee\xe3\xe0\xf2\xe5\xeb\xfc\xed\xe0\xff \xf4\xf3\xed\xea\xf6\xe8\xff \xf1\xf2\xf0\xee\xea\xe8 \xf2\xe5\xea\xf1\xf2\xe0 \xf1 \xe7\xe0\xe4\xe5\xf0\xe6\xea\xee\xe9 \xe8 \xea\xed\xee\xef\xea\xee\xe9 \xf3\xe4\xe0\xeb\xe5\xed\xe8\xff
                local function text_row(prefix, idx, item, buf, wbuf, on_delete)
                    if not buf then return end
                    imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.08, 0.08, 0.10, 1))
                    -- \xcd\xee\xec\xe5\xf0 \xf1\xf2\xf0\xee\xea\xe8
                    imgui.TextColored(imgui.ImVec4(ar_t*0.6, ag_t*0.6, 0.1, 1), u8(tostring(idx)))
                    imgui.SameLine(0, 6*d)
                    -- \xcf\xee\xeb\xe5 \xf2\xe5\xea\xf1\xf2\xe0
                    imgui.PushItemWidth(tw_field)
                    if imgui.InputText('##' .. prefix .. 't' .. idx, buf, 512) then
                        item.text = u8:decode(ffi.string(buf)); save_settings()
                    end
                    imgui.PopItemWidth()
                    imgui.SameLine(0, 6*d)
                    -- \xc7\xe0\xe4\xe5\xf0\xe6\xea\xe0
                    imgui.PushItemWidth(tw_time)
                    if imgui.InputFloat('##' .. prefix .. 'w' .. idx, wbuf, 0.5, 1.0, '%.1f') then
                        item.waiting = math.max(0.5, wbuf[0]); save_settings()
                    end
                    imgui.PopItemWidth()
                    imgui.SameLine(0, 6*d)
                    imgui.TextDisabled(u8'\xf1')
                    imgui.SameLine(0, 8*d)
                    -- \xd3\xe4\xe0\xeb\xe5\xed\xe8\xe5
                    imgui.PushStyleColor(imgui.Col.Button,       imgui.ImVec4(0.45, 0.08, 0.08, 1))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.60, 0.10, 0.10, 1))
                    if imgui.SmallButton('X##' .. prefix .. 'r' .. idx) then on_delete() end
                    imgui.PopStyleColor(2)
                    imgui.PopStyleColor() -- FrameBg
                end

                -- \xc2\xf1\xef\xee\xec\xee\xe3\xe0\xf2\xe5\xeb\xfc\xed\xe0\xff \xf4\xf3\xed\xea\xf6\xe8\xff: \xf1\xe5\xea\xf6\xe8\xff \xf1 \xf2\xf0\xe5\xec\xff \xe2\xe0\xf0\xe8\xe0\xed\xf2\xe0\xec\xe8
                local function variants_section(key, sett, prefix, on_toggle, toggle_state, extra_controls)
                    if not sett.variants then return end
                    -- \xc2\xea\xeb/\xe2\xfb\xea\xeb + /fam + \xe4\xee\xef \xea\xee\xed\xf2\xf0\xee\xeb\xfb
                    on_toggle()
                    imgui.SameLine(0, 8*d)
                    local uf = sett.use_fam
                    imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.10,0.10,0.14,1))
                    if imgui.Checkbox(u8'/fam##'..key..'f', imgui.new.bool(uf)) then sett.use_fam = not uf; save_settings() end
                    imgui.PopStyleColor()
                    if extra_controls then extra_controls() end
                    imgui.Spacing()

                    -- \xd2\xe5\xea\xf3\xf9\xe8\xe9 \xe2\xe0\xf0\xe8\xe0\xed\xf2 (next to fire)
                    local next_vi = (sett.variant_idx or 0) % 3 + 1
                    imgui.TextDisabled(safe_u8('  \xd1\xeb\xe5\xe4\xf3\xfe\xf9\xe8\xe9: \xc2\xe0\xf0\xe8\xe0\xed\xf2 ' .. next_vi))
                    imgui.Spacing()

                    -- \xcf\xee\xe4\xe2\xea\xeb\xe0\xe4\xea\xe8 \xe2\xe0\xf0\xe8\xe0\xed\xf2\xee\xe2
                    if not _G['vtab_'..key] then _G['vtab_'..key] = 1 end
                    local vtab = _G['vtab_'..key]
                    local vbw = (imgui.GetWindowContentRegionWidth() - 8*d) / 3
                    for vi = 1, 3 do
                        if vi > 1 then imgui.SameLine(0, 4*d) end
                        local is_next = (vi == next_vi)
                        local is_cur  = (vtab == vi)
                        if is_cur then
                            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(ar_t*0.5, ag_t*0.5, 0.05, 1))
                        elseif is_next then
                            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.10, 0.35, 0.10, 1))
                        else
                            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.18, 0.18, 0.22, 1))
                        end
                        local lbl = safe_u8('\xc2\xe0\xf0\xe8\xe0\xed\xf2 ' .. vi .. (is_next and ' (\xf1\xeb\xe5\xe4.)' or '') .. '##vt'..key..vi)
                        if imgui.Button(lbl, imgui.ImVec2(vbw, 22*d)) then _G['vtab_'..key] = vi end
                        imgui.PopStyleColor()
                    end
                    imgui.Spacing()

                    -- \xd1\xf2\xf0\xee\xea\xe8 \xf2\xe5\xea\xf3\xf9\xe5\xe3\xee \xe2\xe0\xf0\xe8\xe0\xed\xf2\xe0
                    local var = sett.variants[vtab] or {items={}}
                    local bkey = prefix .. vtab
                    if not _G['vbufs_'..bkey] or #_G['vbufs_'..bkey] ~= #(var.items or {}) then
                        _G['vbufs_'..bkey] = {}; _G['vwbufs_'..bkey] = {}
                        for i, it in ipairs(var.items or {}) do
                            _G['vbufs_'..bkey][i]  = imgui.new.char[512](safe_u8(it.text or ''))
                            _G['vwbufs_'..bkey][i] = imgui.new.float(it.waiting or 1.5)
                        end
                    end
                    local to_rm = nil
                    for ri, ritem in ipairs(var.items or {}) do
                        if _G['vbufs_'..bkey][ri] then
                            text_row(bkey, ri, ritem, _G['vbufs_'..bkey][ri], _G['vwbufs_'..bkey][ri],
                                function() to_rm = ri; _G['vbufs_'..bkey]=nil; _G['vwbufs_'..bkey]=nil end)
                        end
                    end
                    if to_rm then table.remove(var.items, to_rm); save_settings() end

                    -- \xca\xed\xee\xef\xea\xe0 + \xd1\xf2\xf0\xee\xea\xe0
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.15,0.25,0.40,1))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.18,0.32,0.52,1))
                    if imgui.Button(u8'+ \xd1\xf2\xf0\xee\xea\xe0##'..key..'add'..vtab, imgui.ImVec2(90*d, 0)) then
                        if not var.items then var.items = {} end
                        table.insert(var.items, {text='', waiting=1.5}); save_settings()
                        _G['vbufs_'..bkey]=nil; _G['vwbufs_'..bkey]=nil
                    end
                    imgui.PopStyleColor(2)
                end

                -- =========================================================
                -- \xcf\xd0\xc8\xc2\xc5\xd2\xd1\xd2\xc2\xc8\xc5
                -- =========================================================
                section_header('>', '\xcf\xf0\xe8\xe2\xe5\xf2\xf1\xf2\xe2\xe8\xe5 \xef\xf0\xe8 \xe2\xf1\xf2\xf3\xef\xeb\xe5\xed\xe8\xe8', '{player_name} = \xed\xe8\xea.  \xd1\xf0\xe0\xe1\xe0\xf2\xfb\xe2\xe0\xe5\xf2 \xea\xee\xe3\xe4\xe0 \xea\xf2\xee-\xf2\xee \xe2\xf1\xf2\xf3\xef\xe8\xeb \xe2 \xf1\xe5\xec\xfc\xfe.')
                do
                    local uw_auto = settings.general.auto_welcome
                    variants_section('wel', settings.welcome, 'w',
                        function()
                            toggle_button('\xc2\xca\xcb', '\xc2\xdb\xca\xcb', 'welcome_tog', uw_auto,
                                function() settings.general.auto_welcome=true;  save_settings() end,
                                function() settings.general.auto_welcome=false; save_settings() end)
                        end, uw_auto, nil)
                end

                -- =========================================================
                -- \xcf\xce\xc7\xc4\xd0\xc0\xc2\xcb\xc5\xcd\xc8\xc5 \xd1 \xd3\xd0\xce\xc2\xcd\xc5\xcc
                -- =========================================================
                section_header('>', '\xcf\xee\xe7\xe4\xf0\xe0\xe2\xeb\xe5\xed\xe8\xe5 \xf1 \xf3\xf0\xee\xe2\xed\xe5\xec', '{player_name} = \xed\xe8\xea.  \xd1\xf0\xe0\xe1\xe0\xf2\xfb\xe2\xe0\xe5\xf2 \xea\xee\xe3\xe4\xe0 \xf7\xeb\xe5\xed \xf1\xe5\xec\xfc\xe8 \xef\xee\xe4\xed\xff\xeb \xf3\xf0\xee\xe2\xe5\xed\xfc.')
                do
                    local uc_auto = settings.general.auto_congrats
                    variants_section('cng', settings.congrats, 'c',
                        function()
                            toggle_button('\xc2\xca\xcb', '\xc2\xdb\xca\xcb', 'congrats_tog', uc_auto,
                                function() settings.general.auto_congrats=true;  save_settings() end,
                                function() settings.general.auto_congrats=false; save_settings() end)
                        end, uc_auto, nil)
                end
                -- \xc1\xe0\xf2\xf7-\xed\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8
                imgui.Spacing()
                imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.07,0.07,0.09,1))
                imgui.BeginChild('##batch_box', imgui.ImVec2(-1, 178*d), true)
                    imgui.Spacing()
                    imgui.TextColored(imgui.ImVec4(ar_t*0.7, ag_t*0.7, 0.1, 1), u8'  \xc3\xf0\xf3\xef\xef\xee\xe2\xee\xe5 \xef\xee\xe7\xe4\xf0\xe0\xe2\xeb\xe5\xed\xe8\xe5:')
                    imgui.SameLine(0, 10*d)
                    imgui.TextDisabled(u8'\xe5\xf1\xeb\xe8')
                    imgui.SameLine(0, 5*d)
                    imgui.PushItemWidth(40*d)
                    local _bs = imgui.new.int(CONGRATS_BATCH_SINGLE)
                    if imgui.InputInt('##bsingle', _bs, 0) then CONGRATS_BATCH_SINGLE = math.max(2, math.min(20, _bs[0])) end
                    imgui.PopItemWidth()
                    imgui.SameLine(0, 5*d)
                    imgui.TextDisabled(u8'\xe8 \xe1\xee\xeb\xe5\xe5 \xf7\xe5\xeb. \xef\xee\xe4\xed\xff\xeb\xe8 \xf3\xf0\xee\xe2\xe5\xed\xfc \xe7\xe0')
                    imgui.SameLine(0, 5*d)
                    imgui.PushItemWidth(40*d)
                    local _bw = imgui.new.int(CONGRATS_BATCH_WINDOW)
                    if imgui.InputInt('##bwin', _bw, 0) then CONGRATS_BATCH_WINDOW = math.max(2, math.min(30, _bw[0])) end
                    imgui.PopItemWidth()
                    imgui.SameLine(0, 5*d)
                    imgui.TextDisabled(u8'\xf1 \x97 3 \xe2\xe0\xf0\xe8\xe0\xed\xf2\xe0 \xef\xee \xea\xf0\xf3\xe3\xf3:')
                    imgui.Spacing()
                    imgui.TextDisabled(u8'  {names} = \xf1\xef\xe8\xf1\xee\xea \xed\xe8\xea\xee\xe2 \xf7\xe5\xf0\xe5\xe7 \xe7\xe0\xef\xff\xf2\xf3\xfe')
                    imgui.Spacing()
                    if not _G.bmsg_bufs then
                        _G.bmsg_bufs = {}
                        for bi = 1, 3 do
                            _G.bmsg_bufs[bi] = imgui.new.char[256](safe_u8(CONGRATS_BATCH_MSGS[bi] or ''))
                        end
                    end
                    local next_bi = CONGRATS_BATCH_MSG_IDX % 3 + 1
                    for bi = 1, 3 do
                        local is_next = (bi == next_bi)
                        if is_next then
                            imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.10, 0.25, 0.10, 1))
                        else
                            imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.08, 0.08, 0.10, 1))
                        end
                        imgui.TextDisabled(safe_u8(bi .. (is_next and ' (\xf1\xeb\xe5\xe4.)' or '') .. ':'))
                        imgui.SameLine(0, 6*d)
                        imgui.PushItemWidth(-1)
                        if imgui.InputText('##bmsg'..bi, _G.bmsg_bufs[bi], 256) then
                            CONGRATS_BATCH_MSGS[bi] = u8:decode(ffi.string(_G.bmsg_bufs[bi]))
                        end
                        imgui.PopItemWidth()
                        imgui.PopStyleColor()
                    end
                    imgui.Spacing()
                    imgui.TextDisabled(u8'  \xc5\xf1\xeb\xe8 \xec\xe5\xed\xfc\xf8\xe5 \xef\xee\xf0\xee\xe3\xe0 \x97 \xea\xe0\xe6\xe4\xfb\xe9 \xef\xee\xe7\xe4\xf0\xe0\xe2\xeb\xff\xe5\xf2\xf1\xff \xee\xf2\xe4\xe5\xeb\xfc\xed\xee \xe2\xe0\xf0\xe8\xe0\xed\xf2\xee\xec \xe2\xfb\xf8\xe5.')
                imgui.EndChild()
                imgui.PopStyleColor()

                -- =========================================================
                -- \xcf\xce\xc7\xc4\xd0\xc0\xc2\xcb\xc5\xcd\xc8\xc5 \xd1 \xca\xc2\xc5\xd1\xd2\xce\xcc
                -- =========================================================
                if not settings.quest_congrats then settings.quest_congrats = {variants={{items={{text='{player_name}, \xee\xf2\xeb\xe8\xf7\xed\xe0\xff \xf0\xe0\xe1\xee\xf2\xe0! \xca\xe2\xe5\xf1\xf2 \xe2\xfb\xef\xee\xeb\xed\xe5\xed!',waiting=1.5}}}}, use_fam=true, enabled=true, variant_idx=0} end
                section_header('>', '\xcf\xee\xe7\xe4\xf0\xe0\xe2\xeb\xe5\xed\xe8\xe5 \xf1 \xea\xe2\xe5\xf1\xf2\xee\xec', '{player_name} = \xed\xe8\xea.  \xd1\xf0\xe0\xe1\xe0\xf2\xfb\xe2\xe0\xe5\xf2 \xea\xee\xe3\xe4\xe0 \xea\xf2\xee-\xf2\xee \xe2\xfb\xef\xee\xeb\xed\xe8\xeb \xf1\xe5\xec\xe5\xe9\xed\xfb\xe9 \xea\xe2\xe5\xf1\xf2.')
                do
                    local uqe = settings.quest_congrats.enabled
                    variants_section('qcg', settings.quest_congrats, 'q',
                        function()
                            toggle_button('\xc2\xca\xcb', '\xc2\xdb\xca\xcb', 'qcong_tog', uqe,
                                function() settings.quest_congrats.enabled=true;  save_settings() end,
                                function() settings.quest_congrats.enabled=false; save_settings() end)
                        end, uqe, nil)
                end

                -- =========================================================
                -- \xc1\xcb\xc0\xc3\xce\xc4\xc0\xd0\xcd\xce\xd1\xd2\xdc \xc7\xc0 \xcc\xce\xcd\xc5\xd2\xdb/\xd2\xc0\xcb\xce\xcd\xdb
                -- =========================================================
                if not settings.coins_thanks then settings.coins_thanks = {items={{text='/b \xd1\xef\xe0\xf1\xe8\xe1\xee, {player_name}! \xcc\xee\xed\xe5\xf2\xfb \xef\xf0\xe8\xed\xff\xf2\xfb!',waiting=1.0}}, use_fam=false, enabled=true} end
                section_header('>', '\xc1\xeb\xe0\xe3\xee\xe4\xe0\xf0\xed\xee\xf1\xf2\xfc \xe7\xe0 \xec\xee\xed\xe5\xf2\xfb / \xf2\xe0\xeb\xee\xed\xfb', '{player_name} = \xed\xe8\xea.  \xd1\xf0\xe0\xe1\xe0\xf2\xfb\xe2\xe0\xe5\xf2 \xea\xee\xe3\xe4\xe0 \xe8\xe3\xf0\xee\xea \xf1\xe4\xe0\xeb \xf1\xe5\xec\xe5\xe9\xed\xfb\xe5 \xec\xee\xed\xe5\xf2\xfb.')
                do
                    local ect = settings.coins_thanks.enabled
                    toggle_button('\xc2\xca\xcb', '\xc2\xdb\xca\xcb', 'cthx_tog',
                        ect,
                        function() settings.coins_thanks.enabled=true;  save_settings() end,
                        function() settings.coins_thanks.enabled=false; save_settings() end
                    )
                    imgui.SameLine(0, 8*d)
                    local uct = settings.coins_thanks.use_fam
                    imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.10,0.10,0.14,1))
                    if imgui.Checkbox(u8'/fam##cthxf', imgui.new.bool(uct)) then settings.coins_thanks.use_fam = not uct; save_settings() end
                    imgui.PopStyleColor()
                    imgui.SameLine(0, 12*d)
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.15,0.25,0.40,1))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.18,0.32,0.52,1))
                    if imgui.Button(u8'+ \xd1\xf2\xf0\xee\xea\xe0##cthx', imgui.ImVec2(90*d,0)) then
                        table.insert(settings.coins_thanks.items, {text='', waiting=1.0}); save_settings(); _G.tbufs=nil; _G.twbufs=nil
                    end
                    imgui.PopStyleColor(2)
                end
                imgui.Spacing()
                if not _G.tbufs or #_G.tbufs ~= #settings.coins_thanks.items then
                    _G.tbufs = {}; _G.twbufs = {}
                    for i, it in ipairs(settings.coins_thanks.items) do
                        _G.tbufs[i]  = imgui.new.char[512](safe_u8(it.text))
                        _G.twbufs[i] = imgui.new.float(it.waiting or 1.0)
                    end
                end
                local to_rm_ct = nil
                for ti, titem in ipairs(settings.coins_thanks.items) do
                    if _G.tbufs[ti] then
                        text_row('th', ti, titem, _G.tbufs[ti], _G.twbufs[ti],
                            function() to_rm_ct = ti; _G.tbufs=nil; _G.twbufs=nil end)
                    end
                end
                if to_rm_ct then table.remove(settings.coins_thanks.items, to_rm_ct); save_settings() end

                -- =========================================================
                -- \xcf\xce\xc7\xc4\xd0\xc0\xc2\xcb\xc5\xcd\xc8\xc5 \xd1 \xce\xc1\xcc\xc5\xcd\xce\xcc \xd2\xc0\xcb\xce\xcd\xce\xc2
                -- =========================================================
                if not settings.talon_congrats then settings.talon_congrats = {items={{text='{player_name}, \xf1\xef\xe0\xf1\xe8\xe1\xee \xe7\xe0 \xf2\xe0\xeb\xee\xed\xfb! \xcc\xee\xeb\xee\xe4\xe5\xf6!',waiting=1.5}}, use_fam=true, enabled=true} end
                section_header('>', '\xcf\xee\xe7\xe4\xf0\xe0\xe2\xeb\xe5\xed\xe8\xe5 \xf1 \xee\xe1\xec\xe5\xed\xee\xec \xf2\xe0\xeb\xee\xed\xee\xe2', '{player_name} = \xed\xe8\xea.  \xd1\xf0\xe0\xe1\xe0\xf2\xfb\xe2\xe0\xe5\xf2 \xea\xee\xe3\xe4\xe0 \xe8\xe3\xf0\xee\xea \xee\xe1\xec\xe5\xed\xff\xeb \xf2\xe0\xeb\xee\xed\xfb \xed\xe0 \xf0\xe5\xef\xf3\xf2\xe0\xf6\xe8\xfe.')
                do
                    local etlc = settings.talon_congrats.enabled
                    toggle_button('\xc2\xca\xcb', '\xc2\xdb\xca\xcb', 'tlc_tog',
                        etlc,
                        function() settings.talon_congrats.enabled=true;  save_settings() end,
                        function() settings.talon_congrats.enabled=false; save_settings() end
                    )
                    imgui.SameLine(0, 8*d)
                    local utlf = settings.talon_congrats.use_fam
                    imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.10,0.10,0.14,1))
                    if imgui.Checkbox(u8'/fam##tlcf', imgui.new.bool(utlf)) then settings.talon_congrats.use_fam = not utlf; save_settings() end
                    imgui.PopStyleColor()
                    imgui.SameLine(0, 12*d)
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.15,0.25,0.40,1))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.18,0.32,0.52,1))
                    if imgui.Button(u8'+ \xd1\xf2\xf0\xee\xea\xe0##tlcl', imgui.ImVec2(90*d,0)) then
                        table.insert(settings.talon_congrats.items, {text='', waiting=1.5}); save_settings(); _G.tlcbufs=nil; _G.tlcwbufs=nil
                    end
                    imgui.PopStyleColor(2)
                end
                imgui.Spacing()
                if not _G.tlcbufs or #_G.tlcbufs ~= #settings.talon_congrats.items then
                    _G.tlcbufs = {}; _G.tlcwbufs = {}
                    for i, it in ipairs(settings.talon_congrats.items) do
                        _G.tlcbufs[i]  = imgui.new.char[512](safe_u8(it.text))
                        _G.tlcwbufs[i] = imgui.new.float(it.waiting or 1.5)
                    end
                end
                local to_rm_tlc = nil
                for tlci, tlcitem in ipairs(settings.talon_congrats.items) do
                    if _G.tlcbufs[tlci] then
                        text_row('tlc', tlci, tlcitem, _G.tlcbufs[tlci], _G.tlcwbufs[tlci],
                            function() to_rm_tlc = tlci; _G.tlcbufs=nil; _G.tlcwbufs=nil end)
                    end
                end
                if to_rm_tlc then table.remove(settings.talon_congrats.items, to_rm_tlc); save_settings() end

                -- =========================================================
                -- \xd0\xcf-\xc8\xcd\xc2\xc0\xc9\xd2 \xd2\xc5\xca\xd1\xd2
                -- =========================================================
                section_header('>', '\xd0\xcf-\xe8\xed\xe2\xe0\xe9\xf2 \xf2\xe5\xea\xf1\xf2', '& = \xef\xe5\xf0\xe5\xed\xee\xf1 \xf1\xf2\xf0\xee\xea\xe8,  {arg_id} = ID \xe8\xe3\xf0\xee\xea\xe0.  \xce\xf2\xef\xf0\xe0\xe2\xeb\xff\xe5\xf2\xf1\xff \xef\xf0\xe8 /fi [ID].')
                local rpt = (settings.rp_invite.text or ''):gsub('&', '\n')
                if not _G._rpi_buf then _G._rpi_buf = imgui.new.char[4096](safe_u8(rpt)) end
                imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.08,0.08,0.10,1))
                imgui.PushItemWidth(-1)
                if imgui.InputTextMultiline('##rpi', _G._rpi_buf, 4096, imgui.ImVec2(-1, 72*d)) then
                    settings.rp_invite.text = u8:decode(ffi.string(_G._rpi_buf)):gsub('\n', '&'); save_settings()
                end
                imgui.PopItemWidth()
                imgui.PopStyleColor()

                imgui.Spacing()
                imgui.Spacing()
                imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xc0\xe2\xf2\xee-\xee\xf2\xf7\xb8\xf2 \xef\xee \xe8\xed\xe2\xe0\xe9\xf2\xe0\xec')
                imgui.Separator()
                if not settings.tg.auto_inv_hour then settings.tg.auto_inv_hour = 23 end
                if not settings.tg.auto_inv_min  then settings.tg.auto_inv_min  = 59 end
                local auto_en = settings.tg.auto_inv_report or false
                imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.10,0.10,0.14,1))
                if imgui.Checkbox(u8'\xc0\xe2\xf2\xee-\xee\xf2\xf7\xb8\xf2 \xe2 \xea\xee\xed\xf6\xe5 \xe4\xed\xff##tg_autoinv', imgui.new.bool(auto_en)) then
                    settings.tg.auto_inv_report = not auto_en; save_settings()
                end
                imgui.PopStyleColor()
                imgui.SameLine(0, 16*d)
                imgui.TextDisabled(u8'\xc2\xf0\xe5\xec\xff:')
                imgui.SameLine(0, 6*d)
                imgui.PushItemWidth(44*d)
                local _aih = imgui.new.int(settings.tg.auto_inv_hour or 23)
                if imgui.InputInt('##tg_aih', _aih, 0) then
                    settings.tg.auto_inv_hour = math.max(0, math.min(23, _aih[0])); save_settings()
                end
                imgui.PopItemWidth()
                imgui.SameLine(0, 4*d)
                imgui.TextDisabled(u8':')
                imgui.SameLine(0, 4*d)
                imgui.PushItemWidth(44*d)
                local _aim = imgui.new.int(settings.tg.auto_inv_min or 59)
                if imgui.InputInt('##tg_aim', _aim, 0) then
                    settings.tg.auto_inv_min = math.max(0, math.min(59, _aim[0])); save_settings()
                end
                imgui.PopItemWidth()
                imgui.SameLine(0, 12*d)
                imgui.TextDisabled(u8'\x97 \xea\xe0\xe6\xe4\xfb\xe9 \xe7\xe0\xec \xee\xf2\xef\xf0\xe0\xe2\xeb\xff\xe5\xf2 \xf1\xe2\xee\xe9 \xee\xf2\xf7\xb8\xf2')

                imgui.EndChild()
            end
            imgui.EndTabItem()
            end
                imgui.EndTabBar()
            end
        imgui.EndTabItem()
        end
        if imgui.BeginTabItem(u8'\xc0\xe2\xf2\xee\xef\xe8\xe0\xf0') then
        local ar=settings.interface.accent_r or 1
        local ag=settings.interface.accent_g or .65
        local ab=settings.interface.accent_b or 0
        -- \xc7\xe0\xe3\xee\xeb\xee\xe2\xee\xea
        imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xd8\xe0\xe1\xeb\xee\xed\xfb \xe0\xe2\xf2\xee\xef\xe8\xe0\xf0\xe0')
        imgui.SameLine()
        imgui.TextDisabled(u8'/fp [\xed\xee\xec\xe5\xf0] \x97 \xf0\xf3\xf7\xed\xee\xe9 \xe7\xe0\xef\xf3\xf1\xea')
        imgui.Separator()

        local piar_h = imgui.GetWindowHeight() - 80*d
        if imgui.BeginChild('##piars', imgui.ImVec2(-1, piar_h - 34*d), true) then
            local cw = imgui.GetWindowContentRegionWidth()
            -- \xd8\xe8\xf0\xe8\xed\xfb \xea\xee\xeb\xee\xed\xee\xea
            local col_dot  = 18*d
            local col_info = cw - col_dot - 340*d
            local col_btns = 340*d
            -- \xc7\xe0\xe3\xee\xeb\xee\xe2\xee\xea \xf2\xe0\xe1\xeb\xe8\xf6\xfb
            imgui.Columns(3, '##phdr', false)
            imgui.SetColumnWidth(0, col_dot)
            imgui.SetColumnWidth(1, col_info)
            imgui.SetColumnWidth(2, col_btns)
            imgui.NextColumn()
            imgui.TextDisabled(u8'\xd8\xe0\xe1\xeb\xee\xed')
            imgui.NextColumn()
            imgui.TextDisabled(u8'\xc4\xe5\xe9\xf1\xf2\xe2\xe8\xff')
            imgui.NextColumn(); imgui.Columns(1); imgui.Separator()

            for i, t in ipairs(settings.piar_templates) do
                imgui.Columns(3, '##pr'..i, false)
                imgui.SetColumnWidth(0, col_dot)
                imgui.SetColumnWidth(1, col_info)
                imgui.SetColumnWidth(2, col_btns)
                -- \xc4\xee\xf2 \xe0\xe2\xf2\xee-\xef\xe8\xe0\xf0\xe0
                if t.auto then
                    imgui.TextColored(imgui.ImVec4(0.2,0.85,0.2,1), u8'\x95')
                else
                    imgui.TextColored(imgui.ImVec4(0.85,0.2,0.2,1), u8'\x95')
                end
                imgui.NextColumn()
                -- \xcd\xe0\xe7\xe2\xe0\xed\xe8\xe5 + \xe8\xed\xf4\xee
                imgui.Text(safe_u8(' ' .. (t.name or '')))
                imgui.TextDisabled(safe_u8('  ' .. #(t.lines or {}) .. ' \xf1\xf2\xf0 | ' .. (t.waiting or 1.5) .. '\xf1'))
                if t.auto then
                    local elapsed = os.time() - (t.last_time or 0)
                    local interval = t._next_interval or t.auto_interval or 300
                    local left = math.max(0, interval - elapsed)
                    local rng_str = (t.auto_interval_max or 0) > (t.auto_interval or 300) and (' [\xf0\xe0\xed\xe4 ' .. (t.auto_interval or 300) .. '-' .. t.auto_interval_max .. '\xf1]') or ''
                    imgui.TextDisabled(safe_u8('  \xce\xf7\xe5\xf0\xe5\xe4\xfc: ' .. left .. '\xf1 / ' .. interval .. '\xf1' .. rng_str))
                end
                imgui.NextColumn()
                -- \xca\xed\xee\xef\xea\xe8 \xe4\xe5\xe9\xf1\xf2\xe2\xe8\xe9
                local bw3 = (col_btns - 12*d) / 3
                if imgui.Button(u8'\xcf\xf3\xf1\xea##p'..i, imgui.ImVec2(bw3, 0)) then send_piar(i) end
                imgui.SameLine(0,4)
                if t.auto then
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.15,0.5,0.15,1))
                    if imgui.Button(u8'\xc0\xe2\xf2\xee:\xc2\xca\xcb##a'..i, imgui.ImVec2(bw3, 0)) then t.auto=false; save_settings() end
                    imgui.PopStyleColor()
                else
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.4,0.15,0.15,1))
                    if imgui.Button(u8'\xc0\xe2\xf2\xee:\xc2\xdb\xca\xcb##a'..i, imgui.ImVec2(bw3, 0)) then t.auto=true; t.last_time=os.time(); save_settings() end
                    imgui.PopStyleColor()
                end
                imgui.SameLine(0,4)
                if imgui.Button(u8'\xd0\xe5\xe4.##e'..i, imgui.ImVec2(bw3, 0)) then piar_edit_index=i; PiarEditWindow[0]=true end
                imgui.NextColumn(); imgui.Columns(1); imgui.Separator()
            end
            imgui.EndChild()
        end
        if imgui.Button(u8' + \xd8\xe0\xe1\xeb\xee\xed', imgui.ImVec2(-1, 0)) then
            table.insert(settings.piar_templates, {name='\xcd\xee\xe2\xfb\xe9',enable=true,auto=false,auto_interval=300,auto_interval_max=0,waiting=1.5,lines={'/s \xd2\xe5\xea\xf1\xf2 {family_name}'},last_time=0})
            save_settings(); piar_edit_index=#settings.piar_templates; PiarEditWindow[0]=true
        end
        imgui.EndTabItem()
        end
        -- ===== \xd3\xd7\xc0\xd1\xd2\xcd\xc8\xca\xc8 =====
        -- ===== \xd3\xd7\xc0\xd1\xd2\xcd\xc8\xca\xc8 =====
        if imgui.BeginTabItem(u8'\xd3\xf7\xe0\xf1\xf2\xed\xe8\xea\xe8') then
            if imgui.BeginTabBar('##onltabs') then
                if imgui.BeginTabItem(u8'\xd3\xf7\xe0\xf1\xf2\xed\xe8\xea\xe8') then
                local onl_h = imgui.GetWindowHeight() - 80*d
                -- \xc7\xe0\xe3\xee\xeb\xee\xe2\xee\xea + \xea\xed\xee\xef\xea\xe0 \xee\xe1\xed\xee\xe2\xe8\xf2\xfc
                imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xd7\xeb\xe5\xed\xfb \xf1\xe5\xec\xfc\xe8 \xee\xed\xeb\xe0\xe9\xed')
                if fmembers_last_update > 0 then
                    imgui.SameLine()
                    imgui.TextDisabled(safe_u8(' (\xee\xe1\xed\xee\xe2\xeb\xe5\xed\xee: ' .. os.date('%H:%M:%S', fmembers_last_update) .. ')'))
                end
                imgui.Separator()
                if _G.fmembers_collecting then
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.5,0.4,0.0,1))
                    imgui.Button(u8' \xd1\xe1\xee\xf0... ', imgui.ImVec2(-1 - 80*d, 28*d))
                    imgui.PopStyleColor()
                    imgui.SameLine(0, 4*d)
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.4,0.1,0.1,1))
                    if imgui.Button(u8'\xd1\xe1\xf0\xee\xf1\xe8\xf2\xfc##fmreset', imgui.ImVec2(-1, 28*d)) then
                        _G.fmembers_collecting = false; _G.fmembers_collect_start = nil
                    end
                    imgui.PopStyleColor()
                else
                    if imgui.Button(u8' \xce\xe1\xed\xee\xe2\xe8\xf2\xfc (/fmembers) ', imgui.ImVec2(-1, 28*d)) then
                        _G.fmembers_collecting = false
                        _G.fmembers_requested = true
                        sampSendChat('/fmembers')
                    end
                end
                imgui.Spacing()
    
                if fmembers_last_update == 0 and not _G.fmembers_collecting then
                    imgui.TextDisabled(u8'  \xcd\xe0\xe6\xec\xe8\xf2\xe5 "\xce\xe1\xed\xee\xe2\xe8\xf2\xfc" \x97 \xf1\xea\xf0\xe8\xef\xf2 \xee\xf2\xef\xf0\xe0\xe2\xe8\xf2 /fmembers')
                    imgui.TextDisabled(u8'  \xe8 \xe0\xe2\xf2\xee\xec\xe0\xf2\xe8\xf7\xe5\xf1\xea\xe8 \xef\xe5\xf0\xe5\xf5\xe2\xe0\xf2\xe8\xf2 \xf1\xef\xe8\xf1\xee\xea \xee\xed\xeb\xe0\xe9\xed')
                elseif _G.fmembers_collecting then
                    local cnt_so_far = 0; for _ in pairs(fmembers_online) do cnt_so_far = cnt_so_far + 1 end
                    imgui.TextColored(imgui.ImVec4(1,0.8,0.2,1), safe_u8('  \xd1\xe1\xee\xf0 \xf1\xef\xe8\xf1\xea\xe0... \xed\xe0\xe9\xe4\xe5\xed\xee: ' .. cnt_so_far))
                else
                    local count = 0
                    for _ in pairs(fmembers_online) do count = count + 1 end
                    if count == 0 then
                        imgui.TextColored(imgui.ImVec4(1,0.6,0.2,1), u8'  \xcd\xe8\xea\xee\xe3\xee \xe8\xe7 \xf1\xe5\xec\xfc\xe8 \xed\xe5\xf2 \xee\xed\xeb\xe0\xe9\xed')
                    else
                        -- \xd2\xe0\xe1\xeb\xe8\xf6\xe0: \xed\xe8\xea | \xf0\xe0\xed\xe3
                        imgui.Columns(2, '##onlcols', false)
                        imgui.SetColumnWidth(0, 420*d)
                        imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xcd\xe8\xea')
                        imgui.NextColumn()
                        imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xd0\xe0\xed\xe3')
                        imgui.NextColumn(); imgui.Separator(); imgui.Columns(1)
    
                        if imgui.BeginChild('##onllist', imgui.ImVec2(-1, -1), false) then
                            imgui.Columns(3, '##onlcols2', false)
                            imgui.SetColumnWidth(0, 370*d)
                            imgui.SetColumnWidth(1, 200*d)
                            imgui.SetColumnWidth(2,  60*d)
                            -- \xd1\xee\xf0\xf2\xe8\xf0\xf3\xe5\xec: \xf1\xed\xe0\xf7\xe0\xeb\xe0 \xef\xee \xf0\xe0\xed\xe3\xf3 (\xf3\xe1\xfb\xe2.), \xef\xee\xf2\xee\xec \xef\xee \xed\xe8\xea\xf3
                            local sorted = {}
                            for nick, rank in pairs(fmembers_online) do
                                local rn = tonumber(rank:match('%d+')) or 0
                                sorted[#sorted+1] = {nick=nick, rank=rank, rn=rn}
                            end
                            table.sort(sorted, function(a,b)
                                if a.rn ~= b.rn then return a.rn > b.rn end
                                return a.nick < b.nick
                            end)
                            for _, m in ipairs(sorted) do
                                imgui.Text(safe_u8(' ' .. m.nick)); imgui.NextColumn()
                                imgui.TextDisabled(safe_u8(' ' .. m.rank)); imgui.NextColumn()
                                if imgui.SmallButton(u8('...##ctx_' .. m.nick)) then
                                    fmember_ctx_nick = m.nick
                                    ctx_rank_input[0] = m.rn > 0 and m.rn or 1
                                    ffi.copy(ctx_reason_buf, '')
                                    ffi.copy(ctx_sms_buf, '')
                                    MemberCtxWindow[0] = true
                                end
                                imgui.NextColumn()
                            end
                            imgui.Columns(1)
                            imgui.EndChild()
                        end
                    end
                end
                    imgui.EndTabItem()
                end
                if imgui.BeginTabItem(u8'\xd7\xd1') then
                    local ar=settings.interface.accent_r or 1
                    local ag=settings.interface.accent_g or .65
                    local ab=settings.interface.accent_b or 0
                    imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xd7\xb8\xf0\xed\xfb\xe9 \xf1\xef\xe8\xf1\xee\xea \xf1\xe5\xec\xfc\xe8'); imgui.Separator()
                    imgui.PushItemWidth(150*d)
                    imgui.InputTextWithHint(u8'##bl_n', u8'\xcd\xe8\xea\xed\xe5\xe9\xec', qa.bl_name, 256)
                    imgui.SameLine(0,4)
                    imgui.PushItemWidth(300*d)
                    imgui.InputTextWithHint(u8'##bl_r', u8'\xcf\xf0\xe8\xf7\xe8\xed\xe0', qa.bl_reason, 256)
                    imgui.PopItemWidth(); imgui.PopItemWidth()
                    imgui.SameLine(0,4)
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.55,0.1,0.1,1))
                    if imgui.Button(u8'+ \xc2 \xd7\xd1', imgui.ImVec2(90*d, 0)) then
                        local n = ffi.string(qa.bl_name)
                        local r = u8:decode(ffi.string(qa.bl_reason))
                        if n ~= '' then
                            table.insert(settings.blacklist, {name=n, reason=r})
                            save_settings(); qa.bl_name[0]=0; qa.bl_reason[0]=0
                        end
                    end
                    imgui.PopStyleColor()
                    imgui.Separator()
                    local bl_h = imgui.GetWindowHeight() - 140*d
                    if imgui.BeginChild('##bl_list', imgui.ImVec2(-1, bl_h), true) then
                        if #settings.blacklist == 0 then
                            imgui.TextDisabled(u8'  \xd1\xef\xe8\xf1\xee\xea \xef\xf3\xf1\xf2')
                        else
                            imgui.Columns(3, '##blcols', false)
                            imgui.SetColumnWidth(0, 250*d)
                            imgui.SetColumnWidth(1, 310*d)
                            imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xcd\xe8\xea'); imgui.NextColumn()
                            imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xcf\xf0\xe8\xf7\xe8\xed\xe0'); imgui.NextColumn()
                            imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xc4\xe5\xe9\xf1\xf2\xe2\xe8\xe5'); imgui.NextColumn()
                            imgui.Separator()
                            local rm_bl = nil
                            for i, v in ipairs(settings.blacklist) do
                                imgui.Text(safe_u8(' ' .. (v.name or ''))); imgui.NextColumn()
                                imgui.TextDisabled(safe_u8(' ' .. tostring(v.reason or ''))); imgui.NextColumn()
                                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.4,0.1,0.1,1))
                                if imgui.SmallButton(u8'\xd3\xe4\xe0\xeb\xe8\xf2\xfc##bl'..i) then rm_bl = i end
                                imgui.PopStyleColor()
                                imgui.NextColumn()
                            end
                            if rm_bl then table.remove(settings.blacklist, rm_bl); save_settings() end
                            imgui.Columns(1)
                        end
                        imgui.EndChild()
                    end
                    imgui.EndTabItem()
                end
                imgui.EndTabBar()
            end
            imgui.EndTabItem()
        end


        -- ===== \xd3\xcf\xd0\xc0\xc2\xcb\xc5\xcd\xc8\xc5 (\xcf\xd0\xc5\xcc\xc8\xc8, \xd2\xc5\xc3\xc8, \xce\xd4\xd4\xcb\xc0\xc9\xcd) =====
        if imgui.BeginTabItem(u8'\xcf\xf0\xe5\xec\xe8\xe8') then
          local pr_h = imgui.GetWindowHeight() - 80*d
          if imgui.BeginChild('##premii_wrap', imgui.ImVec2(-1, pr_h), false) then
              local ar=settings.interface.accent_r or 1
              local ag=settings.interface.accent_g or .65
              local ab=settings.interface.accent_b or 0

              -- === \xcd\xc0\xd1\xd2\xd0\xce\xc9\xca\xc8 \xd0\xc0\xd1\xd6\xc5\xcd\xce\xca \xc2 \xce\xc4\xcd\xd3 \xd1\xd2\xd0\xce\xca\xd3 ===
              imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xd0\xe0\xf1\xf6\xe5\xed\xea\xe8:')
              imgui.SameLine(0, 16*d)
              imgui.PushItemWidth(120*d)
              qa.reward_amount[0] = settings.quest_reward_amount or 1000000
              if imgui.InputInt(u8'\xc7\xe0 \xea\xe2\xe5\xf1\xf2##qra', qa.reward_amount, 0) then end
              if imgui.IsItemDeactivatedAfterEdit() then
                  settings.quest_reward_amount = math.max(0, qa.reward_amount[0]); save_settings()
              end
              imgui.SameLine(0, 16*d)
              if not _G.coin_reward_buf then _G.coin_reward_buf = imgui.new.int(1) end
              _G.coin_reward_buf[0] = settings.coin_reward_amount or 10000
              if imgui.InputInt(u8'\xc7\xe0 \xec\xee\xed\xe5\xf2\xf3##cra', _G.coin_reward_buf, 0) then end
              if imgui.IsItemDeactivatedAfterEdit() then
                  settings.coin_reward_amount = math.max(0, _G.coin_reward_buf[0]); save_settings()
              end
              imgui.SameLine(0, 16*d)
              if not _G.talon_reward_buf then _G.talon_reward_buf = imgui.new.int(1) end
              _G.talon_reward_buf[0] = settings.talon_reward_amount or 30000
              if imgui.InputInt(u8'\xc7\xe0 \xf2\xe0\xeb\xee\xed##tra', _G.talon_reward_buf, 0) then end
              if imgui.IsItemDeactivatedAfterEdit() then
                  settings.talon_reward_amount = math.max(0, _G.talon_reward_buf[0]); save_settings()
              end
              imgui.PopItemWidth()
              imgui.Separator()

              -- === \xc4\xc2\xc5 \xd2\xc0\xc1\xcb\xc8\xd6\xdb \xd0\xdf\xc4\xce\xcc ===
              local half_w = (imgui.GetWindowContentRegionWidth() - 8*d) / 2

              -- \xca\xe2\xe5\xf1\xf2\xfb
              if imgui.BeginChild('##q_panel', imgui.ImVec2(half_w, 220*d), true) then
                  imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xca\xe2\xe5\xf1\xf2\xfb')
                  imgui.SameLine()
                  if imgui.SmallButton(u8'\xd1\xe1\xf0\xee\xf1##qrst') then settings.quests_stats = {}; save_settings() end
                  imgui.Separator()
                  local q_total_sum = 0
                  local q_list = {}
                  for k, v in pairs(settings.quests_stats or {}) do
                      q_total_sum = q_total_sum + v * (settings.quest_reward_amount or 1000000)
                      table.insert(q_list, {nick=k, count=v})
                  end
                  table.sort(q_list, function(a,b) return a.count > b.count end)
                  imgui.TextDisabled(safe_u8('\xc8\xf2\xee\xe3\xee \xef\xf0\xe5\xec\xe8\xe9: ' .. q_total_sum .. '$'))
                  imgui.Separator()
                  if #q_list == 0 then
                      imgui.TextDisabled(u8'  \xcd\xe5\xf2 \xe4\xe0\xed\xed\xfb\xf5')
                  else
                      imgui.Columns(3, '##qcols', false)
                      imgui.SetColumnWidth(0, half_w * 0.45)
                      imgui.SetColumnWidth(1, half_w * 0.25)
                      imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xcd\xe8\xea'); imgui.NextColumn()
                      imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xca\xe2.'); imgui.NextColumn()
                      imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xd1\xf3\xec\xec\xe0'); imgui.NextColumn()
                      imgui.Separator()
                      for _, row in ipairs(q_list) do
                          local sum = row.count * (settings.quest_reward_amount or 1000000)
                          imgui.Text(safe_u8(' '..row.nick)); imgui.NextColumn()
                          imgui.Text(safe_u8(' '..row.count)); imgui.NextColumn()
                          imgui.Text(safe_u8(' '..sum..'$')); imgui.NextColumn()
                      end
                      imgui.Columns(1)
                  end
                  imgui.EndChild()
              end

              imgui.SameLine(0, 8*d)

              -- \xcc\xee\xed\xe5\xf2\xfb
              if imgui.BeginChild('##c_panel', imgui.ImVec2(half_w, 220*d), true) then
                  imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xcc\xee\xed\xe5\xf2\xfb')
                  imgui.SameLine()
                  if imgui.SmallButton(u8'\xd1\xe1\xf0\xee\xf1##crst') then settings.coins_stats = {}; save_settings() end
                  imgui.Separator()
                  local c_total_sum = 0
                  local c_list = {}
                  for k, v in pairs(settings.coins_stats or {}) do
                      c_total_sum = c_total_sum + v * (settings.coin_reward_amount or 10000)
                      table.insert(c_list, {nick=k, count=v})
                  end
                  table.sort(c_list, function(a,b) return a.count > b.count end)
                  imgui.TextDisabled(safe_u8('\xc8\xf2\xee\xe3\xee \xef\xf0\xe5\xec\xe8\xe9: ' .. c_total_sum .. '$'))
                  imgui.Separator()
                  if #c_list == 0 then
                      imgui.TextDisabled(u8'  \xcd\xe5\xf2 \xe4\xe0\xed\xed\xfb\xf5')
                  else
                      imgui.Columns(3, '##ccols', false)
                      imgui.SetColumnWidth(0, half_w * 0.45)
                      imgui.SetColumnWidth(1, half_w * 0.25)
                      imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xcd\xe8\xea'); imgui.NextColumn()
                      imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xd0\xe0\xe7.'); imgui.NextColumn()
                      imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xd1\xf3\xec\xec\xe0'); imgui.NextColumn()
                      imgui.Separator()
                      for _, row in ipairs(c_list) do
                          local sum = row.count * (settings.coin_reward_amount or 10000)
                          imgui.Text(safe_u8(' '..row.nick)); imgui.NextColumn()
                          imgui.Text(safe_u8(' '..row.count)); imgui.NextColumn()
                          imgui.Text(safe_u8(' '..sum..'$')); imgui.NextColumn()
                      end
                      imgui.Columns(1)
                  end
                  imgui.EndChild()
              end

              imgui.Spacing()
              imgui.Separator()
              imgui.Spacing()

              -- \xd2\xe0\xeb\xee\xed\xfb
              local full_w = imgui.GetWindowContentRegionWidth()
              if imgui.BeginChild('##t_panel', imgui.ImVec2(full_w, 220*d), true) then
                  imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xd2\xe0\xeb\xee\xed\xfb (\xee\xe1\xec\xe5\xed \xed\xe0 \xf0\xe5\xef\xf3\xf2\xe0\xf6\xe8\xfe)')
                  imgui.SameLine()
                  if imgui.SmallButton(u8'\xd1\xe1\xf0\xee\xf1##trst') then settings.talons_stats = {}; save_settings() end
                  imgui.Separator()
                  local t_total_sum = 0
                  local t_list = {}
                  for k, v in pairs(settings.talons_stats or {}) do
                      t_total_sum = t_total_sum + v * (settings.talon_reward_amount or 30000)
                      table.insert(t_list, {nick=k, count=v})
                  end
                  table.sort(t_list, function(a,b) return a.count > b.count end)
                  imgui.TextDisabled(safe_u8('\xc8\xf2\xee\xe3\xee \xef\xf0\xe5\xec\xe8\xe9: ' .. t_total_sum .. '$  |  30 000$ \xe7\xe0 \xea\xe0\xe6\xe4\xfb\xe9 \xf2\xe0\xeb\xee\xed'))
                  imgui.Separator()
                  if #t_list == 0 then
                      imgui.TextDisabled(u8'  \xcd\xe5\xf2 \xe4\xe0\xed\xed\xfb\xf5 \x97 \xf2\xe0\xeb\xee\xed\xfb \xe5\xf9\xb8 \xed\xe5 \xee\xe1\xec\xe5\xed\xe8\xe2\xe0\xeb\xe8\xf1\xfc')
                  else
                      local col_w = full_w / 3
                      imgui.Columns(3, '##tcols', false)
                      imgui.SetColumnWidth(0, col_w * 1.4)
                      imgui.SetColumnWidth(1, col_w * 0.8)
                      imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xcd\xe8\xea'); imgui.NextColumn()
                      imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xd2\xe0\xeb\xee\xed\xee\xe2'); imgui.NextColumn()
                      imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xd1\xf3\xec\xec\xe0'); imgui.NextColumn()
                      imgui.Separator()
                      for _, row in ipairs(t_list) do
                          local sum = row.count * (settings.talon_reward_amount or 30000)
                          imgui.Text(safe_u8(' '..row.nick)); imgui.NextColumn()
                          imgui.Text(safe_u8(' '..row.count)); imgui.NextColumn()
                          imgui.Text(safe_u8(' '..sum..'$')); imgui.NextColumn()
                      end
                      imgui.Columns(1)
                  end
                  imgui.EndChild()
              end

              imgui.Spacing()
              imgui.Separator()
              imgui.Spacing()

              -- === \xca\xcd\xce\xcf\xca\xc8 \xce\xd2\xcf\xd0\xc0\xc2\xca\xc8 \xc2 \xd2\xc3 ===
              imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xce\xf2\xef\xf0\xe0\xe2\xe8\xf2\xfc \xe2 Telegram:')
              imgui.SameLine(0, 12*d)

              local btn_w3 = (imgui.GetWindowContentRegionWidth() - imgui.GetCursorPosX() + 8*d) / 3 - 4*d

              -- \xca\xed\xee\xef\xea\xe0: \xca\xe2\xe5\xf1\xf2\xfb
              imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(0.10,0.30,0.15,1))
              imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.13,0.40,0.20,1))
              if imgui.Button(u8' \xca\xe2\xe5\xf1\xf2\xfb ##pr_tg_q', imgui.ImVec2(btn_w3, 26*d)) then
                  local q_list = {}
                  local q_total = 0
                  for k, v in pairs(settings.quests_stats or {}) do
                      local sum = v * (settings.quest_reward_amount or 1000000)
                      table.insert(q_list, {nick=k, count=v, sum=sum})
                      q_total = q_total + sum
                  end
                  table.sort(q_list, function(a,b) return a.count > b.count end)
                  local lines = {
                      '[FH] \xcf\xf0\xe5\xec\xe8\xe8 \x97 \xca\xe2\xe5\xf1\xf2\xfb',
                      string.rep('-', 25),
                  }
                  if #q_list == 0 then
                      table.insert(lines, '\xcd\xe5\xf2 \xe4\xe0\xed\xed\xfb\xf5')
                  else
                      for i, r in ipairs(q_list) do
                          local marker_q = r.nick == (my_nick()) and '' or ' (\xed\xe5 \xf2\xee\xf7\xed\xee)'
                      table.insert(lines, i..'. '..r.nick..' \x97 '..r.count..' \xea\xe2. ('..r.sum..'$)'..marker_q)
                      end
                      table.insert(lines, string.rep('-', 25))
                      table.insert(lines, '\xc8\xf2\xee\xe3\xee: '..q_total..'$  |  '..
                          (settings.quest_reward_amount or 1000000)..'$ \xe7\xe0 \xea\xe2\xe5\xf1\xf2')
                  end
                  tg_send(table.concat(lines, '\n'))
                  sampAddChatMessage('[Family Helper] {00cc00}\xce\xf2\xf7\xb8\xf2 \xef\xee \xea\xe2\xe5\xf1\xf2\xe0\xec \xee\xf2\xef\xf0\xe0\xe2\xeb\xe5\xed \xe2 \xd2\xc3!', 0xFFFFFF)
              end
              imgui.PopStyleColor(2)
              imgui.SameLine(0, 4*d)

              -- \xca\xed\xee\xef\xea\xe0: \xcc\xee\xed\xe5\xf2\xfb
              imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(0.30,0.20,0.05,1))
              imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.40,0.28,0.07,1))
              if imgui.Button(u8' \xcc\xee\xed\xe5\xf2\xfb ##pr_tg_c', imgui.ImVec2(btn_w3, 26*d)) then
                  local c_list = {}
                  local c_total = 0
                  for k, v in pairs(settings.coins_stats or {}) do
                      local sum = v * (settings.coin_reward_amount or 10000)
                      table.insert(c_list, {nick=k, count=v, sum=sum})
                      c_total = c_total + sum
                  end
                  table.sort(c_list, function(a,b) return a.count > b.count end)
                  local lines = {
                      '[FH] \xcf\xf0\xe5\xec\xe8\xe8 \x97 \xcc\xee\xed\xe5\xf2\xfb',
                      string.rep('-', 25),
                  }
                  if #c_list == 0 then
                      table.insert(lines, '\xcd\xe5\xf2 \xe4\xe0\xed\xed\xfb\xf5')
                  else
                      for i, r in ipairs(c_list) do
                          local marker_c = r.nick == (my_nick()) and '' or ' (\xed\xe5 \xf2\xee\xf7\xed\xee)'
                      table.insert(lines, i..'. '..r.nick..' \x97 '..r.count..' \xf0\xe0\xe7 ('..r.sum..'$)'..marker_c)
                      end
                      table.insert(lines, string.rep('-', 25))
                      table.insert(lines, '\xc8\xf2\xee\xe3\xee: '..c_total..'$  |  '..
                          (settings.coin_reward_amount or 10000)..'$ \xe7\xe0 \xec\xee\xed\xe5\xf2\xf3')
                  end
                  tg_send(table.concat(lines, '\n'))
                  sampAddChatMessage('[Family Helper] {00cc00}\xce\xf2\xf7\xb8\xf2 \xef\xee \xec\xee\xed\xe5\xf2\xe0\xec \xee\xf2\xef\xf0\xe0\xe2\xeb\xe5\xed \xe2 \xd2\xc3!', 0xFFFFFF)
              end
              imgui.PopStyleColor(2)
              imgui.SameLine(0, 4*d)

              -- \xca\xed\xee\xef\xea\xe0: \xd2\xe0\xeb\xee\xed\xfb
              imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(0.10,0.15,0.35,1))
              imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.14,0.20,0.48,1))
              if imgui.Button(u8' \xd2\xe0\xeb\xee\xed\xfb ##pr_tg_t', imgui.ImVec2(btn_w3, 26*d)) then
                  local t_list = {}
                  local t_total = 0
                  for k, v in pairs(settings.talons_stats or {}) do
                      local sum = v * (settings.talon_reward_amount or 30000)
                      table.insert(t_list, {nick=k, count=v, sum=sum})
                      t_total = t_total + sum
                  end
                  table.sort(t_list, function(a,b) return a.count > b.count end)
                  local lines = {
                      '[FH] \xcf\xf0\xe5\xec\xe8\xe8 \x97 \xd2\xe0\xeb\xee\xed\xfb',
                      string.rep('-', 25),
                  }
                  if #t_list == 0 then
                      table.insert(lines, '\xcd\xe5\xf2 \xe4\xe0\xed\xed\xfb\xf5')
                  else
                      for i, r in ipairs(t_list) do
                          local marker_t = r.nick == (my_nick()) and '' or ' (\xed\xe5 \xf2\xee\xf7\xed\xee)'
                      table.insert(lines, i..'. '..r.nick..' \x97 '..r.count..' \xf2\xe0\xeb. ('..r.sum..'$)'..marker_t)
                      end
                      table.insert(lines, string.rep('-', 25))
                      table.insert(lines, '\xc8\xf2\xee\xe3\xee: '..t_total..'$  |  '..
                          (settings.talon_reward_amount or 30000)..'$ \xe7\xe0 \xf2\xe0\xeb\xee\xed')
                  end
                  tg_send(table.concat(lines, '\n'))
                  sampAddChatMessage('[Family Helper] {00cc00}\xce\xf2\xf7\xb8\xf2 \xef\xee \xf2\xe0\xeb\xee\xed\xe0\xec \xee\xf2\xef\xf0\xe0\xe2\xeb\xe5\xed \xe2 \xd2\xc3!', 0xFFFFFF)
              end
              imgui.PopStyleColor(2)

              imgui.Spacing()

              imgui.EndChild()
          end
          imgui.EndTabItem()
        end

        if imgui.BeginTabItem(u8'\xc8\xed\xe2\xe0\xe9\xf2\xfb') then
          local inv_total_h = imgui.GetWindowHeight() - 80*d
          if imgui.BeginChild('##inv_wrap', imgui.ImVec2(-1, inv_total_h), false) then
              local ar4=settings.interface.accent_r or 1
              local ag4=settings.interface.accent_g or .65
              local ab4=settings.interface.accent_b or 0
              local unpaid = settings.general.invite_unpaid or 0
              local price_n = settings.general.invite_price_normal or 2000000
              local price_b = settings.general.invite_price_bonus or 4000000
              local thresh  = settings.general.invite_bonus_threshold or 50
              local pay_sum = unpaid * (unpaid >= thresh and price_b or price_n)
              local total_paid = settings.general.total_paid_amount or 0

              -- === \xd1\xd2\xc0\xd2\xc8\xd1\xd2\xc8\xca\xc0 + \xcd\xc0\xd1\xd2\xd0\xce\xc9\xca\xc8 \xe2 \xee\xe4\xed\xee\xe9 \xf1\xf2\xf0\xee\xea\xe5 ===
              imgui.TextColored(imgui.ImVec4(ar4,ag4,ab4,1), u8' \xd1\xf2\xe0\xf2\xe8\xf1\xf2\xe8\xea\xe0 \xe8\xed\xe2\xe0\xe9\xf2\xee\xe2:')
              imgui.SameLine()
              imgui.TextDisabled(safe_u8('\xcd\xe5\xee\xef\xeb\xe0\xf7\xe5\xed\xed\xfb\xf5: ' .. unpaid .. '   \xd1\xf3\xec\xec\xe0: ' .. pay_sum .. '$   \xc2\xf1\xe5\xe3\xee \xe7\xe0\xf0\xe0\xe1\xee\xf2\xe0\xed\xee: ' .. total_paid .. '$'))
              imgui.Separator()

              -- === \xcd\xc0\xd1\xd2\xd0\xce\xc9\xca\xc8 \xd0\xc0\xd1\xd6\xc5\xcd\xce\xca (\xc3\xd0\xc8\xc4) ===
              imgui.PushItemWidth(140*d)
              invite_price_normal_input[0] = settings.general.invite_price_normal or 2000000
              if imgui.InputInt(u8'\xd6\xe5\xed\xe0 \xe7\xe0 \xe8\xed\xe2\xe0\xe9\xf2##ipn', invite_price_normal_input, 0) then end
              if imgui.IsItemDeactivatedAfterEdit() then settings.general.invite_price_normal = math.max(0, invite_price_normal_input[0]); save_settings() end
              imgui.SameLine(0, 16*d)
              invite_price_bonus_input[0] = settings.general.invite_price_bonus or 4000000
              if imgui.InputInt(u8'\xd6\xe5\xed\xe0 \xe1\xee\xed\xf3\xf1##ipb', invite_price_bonus_input, 0) then end
              if imgui.IsItemDeactivatedAfterEdit() then settings.general.invite_price_bonus = math.max(0, invite_price_bonus_input[0]); save_settings() end
              imgui.SameLine(0, 16*d)
              invite_bonus_thresh_input[0] = settings.general.invite_bonus_threshold or 50
              if imgui.InputInt(u8'\xcf\xee\xf0\xee\xe3 \xe1\xee\xed\xf3\xf1\xe0##ipt', invite_bonus_thresh_input, 0) then end
              if imgui.IsItemDeactivatedAfterEdit() then settings.general.invite_bonus_threshold = math.max(1, invite_bonus_thresh_input[0]); save_settings() end
              imgui.PopItemWidth()

              -- === \xca\xcd\xce\xcf\xca\xc0 \xc2\xdb\xcf\xcb\xc0\xd7\xc5\xcd\xce ===
              if unpaid > 0 then
                  if imgui.Button(safe_u8(' \xc2\xfb\xef\xeb\xe0\xf7\xe5\xed\xee (' .. pay_sum .. '$) '), imgui.ImVec2(-1, 26*d)) then
                      if not settings.invite_history then settings.invite_history = {} end
                      table.insert(settings.invite_history, 1, {
                          date = os.date('%d.%m.%Y %H:%M'),
                          invites = unpaid,
                          amount = pay_sum
                      })
                      settings.general.total_paid_amount = (settings.general.total_paid_amount or 0) + pay_sum
                      settings.general.invite_unpaid = 0
                      save_settings()
                      log_event('\xc2\xfb\xef\xeb\xe0\xf7\xe5\xed\xee: ' .. pay_sum .. '$ \xe7\xe0 ' .. unpaid .. ' \xe8\xed\xe2')
                  end
              else
                  imgui.TextDisabled(u8'  \xcd\xe5\xf2 \xed\xe5\xee\xef\xeb\xe0\xf7\xe5\xed\xed\xfb\xf5 \xe8\xed\xe2\xe0\xe9\xf2\xee\xe2')
              end
              imgui.Spacing()

              -- === \xc8\xd1\xd2\xce\xd0\xc8\xdf \xc2\xdb\xcf\xcb\xc0\xd2 ===
              imgui.TextColored(imgui.ImVec4(ar4,ag4,ab4,1), safe_u8(' \xc8\xf1\xf2\xee\xf0\xe8\xff \xe2\xfb\xef\xeb\xe0\xf2 (\xe2\xf1\xe5\xe3\xee \xe7\xe0\xf0\xe0\xe1\xee\xf2\xe0\xed\xee: ' .. total_paid .. '$)'))
              if imgui.BeginChild('##inv_hist', imgui.ImVec2(-1, 120*d), true) then
                  local hist = settings.invite_history or {}
                  if #hist == 0 then
                      imgui.TextDisabled(u8'  \xcd\xe5\xf2 \xe7\xe0\xef\xe8\xf1\xe5\xe9')
                  else
                      imgui.Columns(3, '##inv_hist_cols', false)
                      imgui.SetColumnWidth(0, 160*d)
                      imgui.SetColumnWidth(1, 80*d)
                      imgui.TextColored(imgui.ImVec4(ar4,ag4,ab4,1), u8' \xc4\xe0\xf2\xe0'); imgui.NextColumn()
                      imgui.TextColored(imgui.ImVec4(ar4,ag4,ab4,1), u8' \xc8\xed\xe2.'); imgui.NextColumn()
                      imgui.TextColored(imgui.ImVec4(ar4,ag4,ab4,1), u8' \xd1\xf3\xec\xec\xe0'); imgui.NextColumn()
                      imgui.Separator()
                      for _, h in ipairs(hist) do
                          imgui.Text(safe_u8('  ' .. (h.date or ''))); imgui.NextColumn()
                          imgui.Text(safe_u8('  ' .. (h.invites or 0))); imgui.NextColumn()
                          imgui.Text(safe_u8('  ' .. (h.amount or 0) .. '$')); imgui.NextColumn()
                      end
                      imgui.Columns(1)
                  end
                  imgui.EndChild()
              end
              imgui.Spacing()

              -- === \xd1\xd2\xc0\xd2\xc8\xd1\xd2\xc8\xca\xc0 \xcf\xce \xc8\xc3\xd0\xce\xca\xc0\xcc ===
              imgui.TextColored(imgui.ImVec4(ar4,ag4,ab4,1), u8' \xd1\xf2\xe0\xf2\xe8\xf1\xf2\xe8\xea\xe0 \xe8\xed\xe2\xe0\xe9\xf2\xee\xe2 \xef\xee \xe8\xe3\xf0\xee\xea\xe0\xec')
              imgui.SameLine(0, 12*d)

              -- \xc5\xe4\xe8\xed\xf1\xf2\xe2\xe5\xed\xed\xe0\xff \xea\xed\xee\xef\xea\xe0 \xd2\xc3: \xec\xee\xe8 \xe8\xed\xe2\xe0\xe9\xf2\xfb \xe7\xe0 \xe2\xf1\xe5 4 \xef\xe5\xf0\xe8\xee\xe4\xe0
              imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(0.10,0.30,0.10,1))
              imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.14,0.42,0.14,1))
              if imgui.SmallButton(u8'  \xce\xf2\xef\xf0\xe0\xe2\xe8\xf2\xfc \xe2 \xd2\xc3  ##invtg_mine') then
                  local stats2    = settings.invite_stats or {}
                  local self_nick = my_nick()
                  local self_s    = stats2[self_nick] or {}
                  local lines = {
                      '[FH] \xcc\xee\xe8 \xe8\xed\xe2\xe0\xe9\xf2\xfb \x97 ' .. self_nick,
                      string.rep('-', 25),
                      '\xd1\xe5\xe3\xee\xe4\xed\xff:   ' .. (self_s.today or 0),
                      '\xcd\xe5\xe4\xe5\xeb\xff:    ' .. (self_s.week  or 0),
                      '\xcc\xe5\xf1\xff\xf6:     ' .. (self_s.month or 0),
                      '\xc2\xf1\xb8 \xe2\xf0\xe5\xec\xff: ' .. (self_s.total or 0),
                  }
                  tg_send(table.concat(lines, '\n'))
                  sampAddChatMessage('[Family Helper] {00cc00}\xcc\xee\xe8 \xe8\xed\xe2\xe0\xe9\xf2\xfb \xee\xf2\xef\xf0\xe0\xe2\xeb\xe5\xed\xfb \xe2 \xd2\xc3!', 0xFFFFFF)
              end
              imgui.PopStyleColor(2)

              if not _G.inv_sort then _G.inv_sort = 'total' end
              local st_list = {}
              local stats = settings.invite_stats or {}
              for nick, s in pairs(stats) do
                  local dk = os.date('%d.%m.%Y')
                  local wk = os.date('%V.%G')
                  local mk = os.date('%m.%Y')
                  if s.day_key   ~= dk then s.today = 0; s.day_key   = dk end
                  if s.week_key  ~= wk then s.week  = 0; s.week_key  = wk end
                  if s.month_key ~= mk then s.month = 0; s.month_key = mk end
                  table.insert(st_list, {nick=nick, s=s})
              end
              table.sort(st_list, function(a, b)
                  return (a.s[_G.inv_sort] or 0) > (b.s[_G.inv_sort] or 0)
              end)
              if imgui.BeginChild('##inv_stats', imgui.ImVec2(-1, -1), true) then
                  local cw1 = 180*d
                  local cw2 = (imgui.GetWindowContentRegionWidth() - cw1) / 4
                  imgui.Columns(5, 'inv_stats_cols', true)
                  imgui.SetColumnWidth(0, cw1)
                  imgui.SetColumnWidth(1, cw2)
                  imgui.SetColumnWidth(2, cw2)
                  imgui.SetColumnWidth(3, cw2)
                  imgui.SetColumnWidth(4, cw2)
                  imgui.Text(u8' \xc8\xe3\xf0\xee\xea'); imgui.NextColumn()
                  local sorts = {{'today','\xd1\xe5\xe3\xee\xe4\xed\xff'},{'week','\xcd\xe5\xe4\xe5\xeb\xff'},{'month','\xcc\xe5\xf1\xff\xf6'},{'total','\xc2\xf1\xe5\xe3\xee'}}
                  for _, sv in ipairs(sorts) do
                      local active = _G.inv_sort == sv[1]
                      if active then imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(ar4*0.6,ag4*0.6,ab4*0.6+0.3,1)) end
                      if imgui.Button(safe_u8(sv[2]..(active and ' v' or '')..'##isort_'..sv[1]), imgui.ImVec2(-1,0)) then
                          _G.inv_sort = sv[1]
                      end
                      if active then imgui.PopStyleColor() end
                      imgui.NextColumn()
                  end
                  imgui.Separator()
                  if #st_list == 0 then
                      imgui.Text(u8'  \xcd\xe5\xf2 \xe4\xe0\xed\xed\xfb\xf5.')
                      imgui.NextColumn(); imgui.NextColumn(); imgui.NextColumn(); imgui.NextColumn()
                  end
                  for ri, item in ipairs(st_list) do
                      local s = item.s
                      local row_color = ri % 2 == 0 and imgui.ImVec4(1,1,1,0.6) or imgui.ImVec4(1,1,1,1)
                      imgui.TextColored(row_color, safe_u8(' '..item.nick)); imgui.NextColumn()
                      imgui.TextColored(row_color, safe_u8(' '..(s.today or 0))); imgui.NextColumn()
                      imgui.TextColored(row_color, safe_u8(' '..(s.week  or 0))); imgui.NextColumn()
                      imgui.TextColored(row_color, safe_u8(' '..(s.month or 0))); imgui.NextColumn()
                      imgui.TextColored(row_color, safe_u8(' '..(s.total or 0))); imgui.NextColumn()
                  end
                  imgui.Columns(1)
                  imgui.EndChild()
              end
              imgui.Spacing()
              imgui.Separator()
              imgui.Spacing()
              -- \xca\xed\xee\xef\xea\xe0 \xf1\xe1\xf0\xee\xf1\xe0 \x97 \xe2\xed\xe8\xe7\xf3, \xee\xf2\xe4\xe5\xeb\xfc\xed\xee, \xe7\xe0\xf9\xe8\xf2\xe0 \xee\xf2 \xf1\xeb\xf3\xf7\xe0\xe9\xed\xee\xe3\xee \xed\xe0\xe6\xe0\xf2\xe8\xff
              imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(0.35,0.08,0.08,1))
              imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.55,0.12,0.12,1))
              if imgui.Button(u8'  !! \xd1\xe1\xf0\xee\xf1\xe8\xf2\xfc \xe2\xf1\xfe \xf1\xf2\xe0\xf2\xe8\xf1\xf2\xe8\xea\xf3 \xe8\xed\xe2\xe0\xe9\xf2\xee\xe2  ##invst_reset', imgui.ImVec2(-1, 22*d)) then
                  settings.invite_stats = {}; save_settings()
                  sampAddChatMessage('[Family Helper] {ff4444}\xd1\xf2\xe0\xf2\xe8\xf1\xf2\xe8\xea\xe0 \xe8\xed\xe2\xe0\xe9\xf2\xee\xe2 \xf1\xe1\xf0\xee\xf8\xe5\xed\xe0.', 0xFFFFFF)
              end
              imgui.PopStyleColor(2)
              imgui.EndChild()
          end
          imgui.EndTabItem()
        end




        -- ===== \xcb\xce\xc3 =====
        if imgui.BeginTabItem(u8'\xcb\xee\xe3') then
            local log_h = imgui.GetWindowHeight() - 80*d
            if imgui.BeginChild('##log_wrap', imgui.ImVec2(-1, log_h), false) then
                imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xcb\xee\xe3 \xf1\xee\xe1\xfb\xf2\xe8\xe9 \xf1\xe5\xec\xfc\xe8')
                imgui.Separator()
                if not _G.log_tab then _G.log_tab = 1 end
                if not settings.log_enabled then settings.log_enabled = {bank=true,coins=true,mute=true,invite=true,level=true,quest=true,rank=true} end
                local log_cats = {
                    {1, '\xcd\xee\xe2\xee\xf1\xf2\xe8', 'news'},
                    {2, '\xd7\xe0\xf2',     'chat'},
                    {3, '\xd1\xea\xeb\xe0\xe4 $', 'bank'},
                    {4, '\xcc\xee\xed\xe5\xf2\xfb',  'coins'},
                    {5, '\xcc\xf3\xf2\xfb',    'mute'},
                    {6, '\xd1\xee\xf1\xf2\xe0\xe2',  'invite'},
                    {7, '\xd3\xf0\xee\xe2\xed\xe8',  'level'},
                    {8, '\xca\xe2\xe5\xf1\xf2\xfb',  'quest'},
                    {9, '\xd0\xe0\xed\xe3\xe8',   'rank'},
                }
                -- \xca\xed\xee\xef\xea\xe8 \xeb\xee\xe3\xe8\xf0\xee\xe2\xe0\xf2\xfc / \xef\xf0\xee\xf1\xec\xee\xf2\xf0 \xe2 2 \xf0\xff\xe4\xe0
                local half = math.ceil(#log_cats / 2)
                local full_w = imgui.GetWindowContentRegionWidth()
                local btn_h = 21*d

                imgui.TextDisabled(u8' \xcb\xee\xe3\xe8\xf0\xee\xe2\xe0\xf2\xfc:')
                for li, cat in ipairs(log_cats) do
                    if li > 1 and (li-1) % half ~= 0 then imgui.SameLine() end
                    local bw = (full_w - (half-1)*4*d) / half
                    local enabled = settings.log_enabled[cat[3]]
                    if enabled then
                        imgui.PushStyleColor(imgui.Col.Button,       imgui.ImVec4(ar*0.4,ag*0.4,ab*0.4,1))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(ar*0.6,ag*0.6,ab*0.6,1))
                    else
                        imgui.PushStyleColor(imgui.Col.Button,       imgui.ImVec4(0.12,0.12,0.12,1))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.22,0.22,0.22,1))
                    end
                    if imgui.Button(safe_u8((enabled and '+' or '-')..' '..cat[2]..'##ltog'..li), imgui.ImVec2(bw, btn_h)) then
                        settings.log_enabled[cat[3]] = not enabled; save_settings()
                    end
                    imgui.PopStyleColor(2)
                end
                imgui.Spacing()

                imgui.TextDisabled(u8' \xcf\xf0\xee\xf1\xec\xee\xf2\xf0:')
                local view_cols = half + 1  -- +1 \xe4\xeb\xff \xea\xed\xee\xef\xea\xe8 \xc2\xf1\xe5
                local vbw = (full_w - (view_cols-1)*4*d) / view_cols
                for li, cat in ipairs(log_cats) do
                    if li > 1 and (li-1) % half ~= 0 then imgui.SameLine() end
                    local active = _G.log_tab == cat[1]
                    if active then imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(ar*0.6,ag*0.6,ab*0.6,1)) end
                    local cnt = #famlog[cat[3]]
                    if imgui.Button(safe_u8(cat[2]..(cnt>0 and (' '..cnt) or '')..'##lcat'..li), imgui.ImVec2(vbw, btn_h)) then
                        _G.log_tab = cat[1]; _G.log_page = 1
                    end
                    if active then imgui.PopStyleColor() end
                    -- \xcf\xee\xf1\xeb\xe5 \xef\xee\xeb\xee\xe2\xe8\xed\xfb \xe2\xf1\xf2\xe0\xe2\xe8\xf2\xfc \xea\xed\xee\xef\xea\xf3 \xc2\xf1\xe5
                    if li == half then
                        imgui.SameLine()
                        local active_all = _G.log_tab == 0
                        if active_all then imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(ar*0.6,ag*0.6,ab*0.6,1)) end
                        if imgui.Button(u8'\xc2\xf1\xe5##logall', imgui.ImVec2(vbw, btn_h)) then _G.log_tab = 0; _G.log_page = 1 end
                        if active_all then imgui.PopStyleColor() end
                    end
                end
                imgui.SameLine()
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.4,0.1,0.1,1))
                if imgui.SmallButton(u8'X##logclear') then
                    for _, cat in ipairs(log_cats) do famlog[cat[3]] = {} end
                    lua_thread.create(function() save_log() end)
                end
                imgui.PopStyleColor()
                imgui.Separator(); imgui.Spacing()

                -- \xc2\xf1\xef\xee\xec\xee\xe3\xe0\xf2\xe5\xeb\xfc\xed\xe0\xff \xf4\xf3\xed\xea\xf6\xe8\xff \xf4\xee\xf0\xec\xe0\xf2\xe8\xf0\xee\xe2\xe0\xed\xe8\xff \xf1\xf2\xf0\xee\xea\xe8 \xeb\xee\xe3\xe0
                local function fmt_entry(e, cat_key)
                    local line = '[' .. (e.date or '') .. ' ' .. (e.time or '') .. '] '
                    if cat_key == 'news' then
                        -- \xcd\xee\xe2\xee\xf1\xf2\xe8: \xf0\xe0\xe7\xe2\xee\xf0\xe0\xf7\xe8\xe2\xe0\xe5\xec \xef\xee\xed\xff\xf2\xed\xfb\xe9 \xf2\xe5\xea\xf1\xf2 \xed\xe0 \xee\xf1\xed\xee\xe2\xe5 msg
                        local nick = e.nick or ''
                        local msg  = e.msg  or ''
                        if msg:find('\xf1\xe0\xec\xee\xf1\xf2\xee\xff\xf2\xe5\xeb\xfc\xed\xee \xef\xee\xea\xe8\xed\xf3\xeb') then
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. nick .. ' \xf1\xe0\xec\xee\xf1\xf2\xee\xff\xf2\xe5\xeb\xfc\xed\xee \xef\xee\xea\xe8\xed\xf3\xeb \xf1\xe5\xec\xfc\xfe!'
                        elseif msg:find('\xe2\xf1\xf2\xf3\xef\xe8\xeb \xe2 \xf1\xe5\xec\xfc\xfe') then
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. nick .. ' \xe2\xf1\xf2\xf3\xef\xe8\xeb \xe2 \xf1\xe5\xec\xfc\xfe.'
                        elseif msg:find('\xef\xf0\xe8\xe3\xeb\xe0\xf1\xe8\xeb ') then
                            local inv = msg:match('\xef\xf0\xe8\xe3\xeb\xe0\xf1\xe8\xeb (.+)')
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. nick .. ' \xef\xf0\xe8\xe3\xeb\xe0\xf1\xe8\xeb \xe8\xe3\xf0\xee\xea\xe0 ' .. (inv or '?') .. ' \xe2 \xf1\xe5\xec\xfc\xfe.'
                        elseif msg:find('\xea\xe8\xea\xed\xf3\xeb ') then
                            local kicked = msg:match('\xea\xe8\xea\xed\xf3\xeb (.+) \xe8\xe7 \xf1\xe5\xec\xfc\xe8')
                            if msg:find('\xee\xf4\xf4\xeb\xe0\xe9\xed') then
                                line = line .. '\xc8\xe3\xf0\xee\xea ' .. nick .. ' \xe2 \xee\xf4\xf4\xeb\xe0\xe9\xed\xe5 \xe2\xfb\xe3\xed\xe0\xeb \xe8\xe3\xf0\xee\xea\xe0 ' .. (kicked or '?') .. ' \xe8\xe7 \xf1\xe5\xec\xfc\xe8!'
                            else
                                line = line .. '\xc8\xe3\xf0\xee\xea ' .. nick .. ' \xe2\xfb\xe3\xed\xe0\xeb \xe8\xe3\xf0\xee\xea\xe0 ' .. (kicked or '?') .. ' \xe8\xe7 \xf1\xe5\xec\xfc\xe8!'
                            end
                        elseif msg:find('\xec\xf3\xf2 ') then
                            local muted = msg:match('\xec\xf3\xf2 (.+) \xed\xe0')
                            local dur   = msg:match('\xed\xe0 (%d+)\xec\xe8\xed')
                            local reas  = msg:match(': (.+)')
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. nick .. ' \xe2\xfb\xe4\xe0\xeb \xec\xf3\xf2 \xe8\xe3\xf0\xee\xea\xf3 ' .. (muted or '?') .. ' \xed\xe0 ' .. (dur or '?') .. ' \xec\xe8\xed.' .. (reas and (' \xcf\xf0\xe8\xf7\xe8\xed\xe0: ' .. reas) or '')
                        elseif msg:find('\xe4\xee\xf1\xf2\xe8\xe3 ') then
                            local lvl = msg:match('\xe4\xee\xf1\xf2\xe8\xe3 (%d+) \xf3\xf0\xee\xe2\xed\xff')
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. nick .. ' \xe4\xee\xf1\xf2\xe8\xe3 ' .. (lvl or '?') .. ' \xf3\xf0\xee\xe2\xed\xff.'
                        elseif msg:find('\xf3\xf0\xee\xe2\xe5\xed\xfc') or msg:find('\xf3\xf0\xee\xe2\xed\xff') then
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. nick .. ' \xef\xee\xe4\xed\xff\xeb \xf3\xf0\xee\xe2\xe5\xed\xfc.'
                        elseif msg:find('\xe2\xfb\xef\xee\xeb\xed\xe8\xeb \xea\xe2\xe5\xf1\xf2') or msg:find('\xea\xe2\xe5\xf1\xf2') then
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. nick .. ' \xe2\xfb\xef\xee\xeb\xed\xe8\xeb \xf1\xe5\xec\xe5\xe9\xed\xfb\xe9 \xea\xe2\xe5\xf1\xf2.'
                        elseif msg:find('\xcf\xee\xef\xee\xeb\xed\xe8\xeb \xf1\xea\xeb\xe0\xe4') or msg:find('\xcf\xee\xef\xee\xeb') then
                            local sum = msg:match('%$(.+)')
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. nick .. ' \xef\xee\xef\xee\xeb\xed\xe8\xeb \xf1\xea\xeb\xe0\xe4 \xf1\xe5\xec\xfc\xe8 \xed\xe0 $' .. (sum or '?') .. '.'
                        elseif msg:find('\xc2\xe7\xff\xeb') or msg:find('\xe2\xe7\xff\xeb') then
                            local sum = msg:match('%$(.+)')
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. nick .. ' \xf1\xed\xff\xeb \xf1\xee \xf1\xea\xeb\xe0\xe4\xe0 \xf1\xe5\xec\xfc\xe8 $' .. (sum or '?') .. '.'
                        elseif msg:find('\xed\xe0\xe7\xed\xe0\xf7\xe5\xed \xe7\xe0\xec\xe5\xf1\xf2\xe8\xf2\xe5\xeb\xe5\xec') then
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. nick .. ' \xed\xe0\xe7\xed\xe0\xf7\xe8\xeb ' .. (msg:match('(.+) \xed\xe0\xe7\xed\xe0\xf7\xe5\xed') or '?') .. ' \xe7\xe0\xec\xe5\xf1\xf2\xe8\xf2\xe5\xeb\xe5\xec!'
                        elseif msg:find('\xf1\xed\xff\xf2 \xf1 \xef\xee\xf1\xf2\xe0 \xe7\xe0\xec\xe0') then
                            local zam = msg:match('(.+) \xf1\xed\xff\xf2 \xf1 \xef\xee\xf1\xf2\xe0 \xe7\xe0\xec\xe0')
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. nick .. ' \xf1\xed\xff\xeb ' .. (zam or '?') .. ' \xf1 \xef\xee\xf1\xf2\xe0 \xe7\xe0\xec\xe5\xf1\xf2\xe8\xf2\xe5\xeb\xff!'
                        elseif msg:find('\xf0\xe0\xed\xe3 ') then
                            local rn = msg:match('\xf0\xe0\xed\xe3 (%d+) %->') or msg:match('\xf0\xe0\xed\xe3 (%d+)')
                            local tgt = msg:match('-> (.+)')
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. nick .. ' \xf3\xf1\xf2\xe0\xed\xee\xe2\xe8\xeb \xf0\xe0\xed\xe3 ' .. (rn or '?') .. (tgt and (' \xe8\xe3\xf0\xee\xea\xf3 ' .. tgt) or '') .. '.'
                        elseif msg:find('\xee\xe1\xec\xe5\xed\xff\xeb') and msg:find('\xf2\xe0\xeb\xee\xed') then
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. nick .. ' ' .. msg .. '.'
                        elseif msg:find('\xf1\xe5\xf0\xf2\xe8\xf4\xe8\xea\xe0\xf2') then
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. nick .. ' \xe8\xf1\xef\xee\xeb\xfc\xe7\xee\xe2\xe0\xeb \xf1\xe5\xf0\xf2\xe8\xf4\xe8\xea\xe0\xf2 \xf0\xe5\xef\xf3\xf2\xe0\xf6\xe8\xe8.'
                        else
                            line = line .. (nick ~= '' and ('\xc8\xe3\xf0\xee\xea ' .. nick .. ': ') or '') .. msg
                        end
                    elseif cat_key == 'chat' then
                        line = line .. '[\xd7\xe0\xf2 \xf1\xe5\xec\xfc\xe8] ' .. (e.nick or '?') .. ': ' .. (e.msg or '')
                    elseif cat_key == 'bank' then
                        if (e.op or '') == '\xcf\xee\xef\xee\xeb\xed\xe8\xeb' then
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. (e.nick or '?') .. ' \xef\xee\xef\xee\xeb\xed\xe8\xeb \xf1\xea\xeb\xe0\xe4 \xf1\xe5\xec\xfc\xe8 \xed\xe0 $' .. (e.sum or '?') .. '.'
                        else
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. (e.nick or '?') .. ' \xf1\xed\xff\xeb \xf1\xee \xf1\xea\xeb\xe0\xe4\xe0 \xf1\xe5\xec\xfc\xe8 $' .. (e.sum or '?') .. '.'
                        end
                    elseif cat_key == 'coins' then
                        local msg = e.msg or ''
                        if msg:find('\xee\xe1\xec\xe5\xed\xff\xeb') and msg:find('\xf2\xe0\xeb\xee\xed') then
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. (e.nick or '?') .. ' ' .. msg .. '.'
                        else
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. (e.nick or '?') .. ' \xf1\xe4\xe0\xeb \xf1\xe5\xec\xe5\xe9\xed\xfb\xe5 \xec\xee\xed\xe5\xf2\xfb/\xf2\xe0\xeb\xee\xed\xfb.'
                        end
                    elseif cat_key == 'mute' then
                        line = line .. '\xc8\xe3\xf0\xee\xea ' .. (e.by or '?') .. ' \xe2\xfb\xe4\xe0\xeb \xec\xf3\xf2 \xe8\xe3\xf0\xee\xea\xf3 ' .. (e.nick or '?') .. ' \xed\xe0 ' .. (e.duration or '?') .. ' \xec\xe8\xed.'
                        if e.reason and e.reason ~= '' then line = line .. ' \xcf\xf0\xe8\xf7\xe8\xed\xe0: ' .. e.reason end
                    elseif cat_key == 'invite' then
                        local tp = e.type or '?'
                        local nick = e.nick or '?'
                        if tp == '\xc8\xed\xe2\xe0\xe9\xf2 \xef\xf0\xe8\xed\xff\xf2' or tp == '\xcf\xf0\xe8\xe3\xeb\xe0\xf8\xb8\xed' then
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. (e.by ~= '' and e.by or '?') .. ' \xef\xf0\xe8\xe3\xeb\xe0\xf1\xe8\xeb \xe8\xe3\xf0\xee\xea\xe0 ' .. nick .. ' \xe2 \xf1\xe5\xec\xfc\xfe.'
                        elseif tp == '\xc2\xf1\xf2\xf3\xef\xe8\xeb' then
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. nick .. ' \xe2\xf1\xf2\xf3\xef\xe8\xeb \xe2 \xf1\xe5\xec\xfc\xfe.'
                        elseif tp == '\xcf\xee\xea\xe8\xed\xf3\xeb' then
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. nick .. ' \xf1\xe0\xec\xee\xf1\xf2\xee\xff\xf2\xe5\xeb\xfc\xed\xee \xef\xee\xea\xe8\xed\xf3\xeb \xf1\xe5\xec\xfc\xfe!'
                        elseif tp == '\xca\xe8\xea' then
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. (e.by ~= '' and e.by or '?') .. ' \xe2\xfb\xe3\xed\xe0\xeb \xe8\xe3\xf0\xee\xea\xe0 ' .. nick .. ' \xe8\xe7 \xf1\xe5\xec\xfc\xe8!'
                        else
                            line = line .. tp .. ': ' .. nick
                        end
                        if e.total then line = line .. ' (\xe2\xf1\xe5\xe3\xee \xe8\xed\xe2\xe0\xe9\xf2\xee\xe2: ' .. e.total .. ')' end
                    elseif cat_key == 'level' then
                        line = line .. '\xc8\xe3\xf0\xee\xea ' .. (e.nick or '?') .. ' \xe4\xee\xf1\xf2\xe8\xe3 ' .. (e.lvl and (e.lvl .. ' \xf3\xf0\xee\xe2\xed\xff') or '\xed\xee\xe2\xee\xe3\xee \xf3\xf0\xee\xe2\xed\xff') .. '.'
                    elseif cat_key == 'quest' then
                        line = line .. '\xc8\xe3\xf0\xee\xea ' .. (e.nick or '?') .. ' \xe2\xfb\xef\xee\xeb\xed\xe8\xeb \xf1\xe5\xec\xe5\xe9\xed\xfb\xe9 \xea\xe2\xe5\xf1\xf2.'
                    elseif cat_key == 'rank' then
                        local rk = e.rank or '?'
                        local who = e.nick or '?'
                        local by  = e.by or ''
                        if rk == '\xe7\xe0\xec' then
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. by .. ' \xed\xe0\xe7\xed\xe0\xf7\xe8\xeb ' .. who .. ' \xe7\xe0\xec\xe5\xf1\xf2\xe8\xf2\xe5\xeb\xe5\xec!'
                        else
                            line = line .. '\xc8\xe3\xf0\xee\xea ' .. (by ~= '' and by or '?') .. ' \xf3\xf1\xf2\xe0\xed\xee\xe2\xe8\xeb \xf0\xe0\xed\xe3 ' .. rk .. ' \xe8\xe3\xf0\xee\xea\xf3 ' .. who .. '.'
                        end
                    end
                    return line
                end

                -- \xd4\xe8\xeb\xfc\xf2\xf0 \xf1\xf2\xf0\xee\xea\xe8 (\xe4\xeb\xff \xcd\xee\xe2\xee\xf1\xf2\xe5\xe9 \xe8 \xc2\xf1\xe5)
                if not _G.log_filter_buf then _G.log_filter_buf = imgui.new.char[128]() end
                local show_filter = (_G.log_tab == 0 or (log_cats[_G.log_tab] and (log_cats[_G.log_tab][3] == 'news' or log_cats[_G.log_tab][3] == 'chat')))
                if show_filter then
                    if not _G.log_qf then _G.log_qf = '' end
                    -- \xd1\xf2\xf0\xee\xea\xe0 \xef\xee\xe8\xf1\xea\xe0
                    imgui.PushItemWidth(full_w - 36*d)
                    if imgui.InputTextWithHint('##logflt', u8'\xcf\xee\xe8\xf1\xea...', _G.log_filter_buf, 128) then _G.log_page = 1 end
                    imgui.PopItemWidth()
                    imgui.SameLine()
                    if imgui.Button(u8'X##logfltcl', imgui.ImVec2(-1, 0)) then
                        ffi.fill(_G.log_filter_buf, 128); _G.log_qf = ''
                    end
                    -- \xc1\xfb\xf1\xf2\xf0\xfb\xe5 \xf4\xe8\xeb\xfc\xf2\xf0\xfb \xe2 \xf0\xff\xe4
                    local qfilters = {{'', '\xc2\xf1\xe5'}, {'\xf1\xea\xeb\xe0\xe4', '\xd1\xea\xeb\xe0\xe4'}, {'\xf2\xe0\xeb\xee\xed', '\xd2\xe0\xeb\xee\xed'}, {'\xf0\xe5\xef\xf3\xf2\xe0\xf6', '\xd0\xe5\xef\xe0'}, {'\xec\xf3\xf2', '\xcc\xf3\xf2'}, {'\xe2\xf1\xf2\xf3\xef', '\xc2\xf1\xf2\xf3\xef'}, {'\xf3\xf0\xee\xe2\xed', '\xd3\xf0\xee\xe2\xe5\xed\xfc'}}
                    local qbw = (full_w - (#qfilters-1)*4*d) / #qfilters
                    for qi, qf in ipairs(qfilters) do
                        if qi > 1 then imgui.SameLine() end
                        local qactive = _G.log_qf == qf[1]
                        if qactive then imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(ar*0.6,ag*0.6,ab*0.6,1)) end
                        if imgui.Button(safe_u8(qf[2]..'##qf'..qi), imgui.ImVec2(qbw, 20*d)) then
                            _G.log_qf = qf[1]; ffi.fill(_G.log_filter_buf, 128); _G.log_page = 1
                        end
                        if qactive then imgui.PopStyleColor() end
                    end
                    imgui.Spacing()
                end

                -- \xd1\xee\xe1\xf0\xe0\xf2\xfc \xe7\xe0\xef\xe8\xf1\xe8 \xe4\xeb\xff \xee\xf2\xee\xe1\xf0\xe0\xe6\xe5\xed\xe8\xff
                local filter_str = show_filter and u8:decode(ffi.string(_G.log_filter_buf)):lower() or ''
                if show_filter and _G.log_qf and _G.log_qf ~= '' and filter_str == '' then
                    filter_str = _G.log_qf
                end

                local show_entries = {}
                if _G.log_tab == 0 then
                    for _, cat in ipairs(log_cats) do
                        for _, e in ipairs(famlog[cat[3]]) do
                            table.insert(show_entries, {e=e, k=cat[3]})
                        end
                    end
                    table.sort(show_entries, function(a, b)
                        return ((a.e.date or '')  .. (a.e.time or '')) > ((b.e.date or '') .. (b.e.time or ''))
                    end)
                else
                    local cur_cat = log_cats[_G.log_tab]
                    if cur_cat then
                        for _, e in ipairs(famlog[cur_cat[3]]) do
                            table.insert(show_entries, {e=e, k=cur_cat[3]})
                        end
                        -- Если вкладка "Новости" и включён кто-то из кторотких фильтров:
                        -- добавляем записи из структурированных категорий
                        if cur_cat[3] == 'news' then
                            local qf = _G.log_qf or ''
                            if qf == 'мут' then
                                for _, e in ipairs(famlog['mute'] or {}) do
                                    table.insert(show_entries, {e=e, k='mute'})
                                end
                            elseif qf == 'вступ' then
                                for _, e in ipairs(famlog['invite'] or {}) do
                                    table.insert(show_entries, {e=e, k='invite'})
                                end
                            elseif qf == 'уровн' then
                                for _, e in ipairs(famlog['level'] or {}) do
                                    table.insert(show_entries, {e=e, k='level'})
                                end
                            end
                            -- сразу сортируем по дате
                            table.sort(show_entries, function(a, b)
                                return ((a.e.date or '') .. (a.e.time or '')) > ((b.e.date or '') .. (b.e.time or ''))
                            end)
                        end
                    end
                end

                -- \xcf\xf0\xe8\xec\xe5\xed\xe8\xf2\xfc \xf4\xe8\xeb\xfc\xf2\xf0
                if filter_str ~= '' then
                    local filtered = {}
                    for _, item in ipairs(show_entries) do
                        local line = ((item.e.nick or '') .. ' ' .. (item.e.msg or '') .. ' ' ..
                                      (item.e.op or '') .. ' ' .. (item.e.sum or '') .. ' ' ..
                                      (item.e.reason or '') .. ' ' .. (item.e.type or '')):lower()
                        if line:find(filter_str, 1, true) then
                            table.insert(filtered, item)
                        end
                    end
                    show_entries = filtered
                end

                if #show_entries == 0 then
                    imgui.TextDisabled(u8'  \xcd\xe5\xf2 \xe7\xe0\xef\xe8\xf1\xe5\xe9.')
                else
                    local page_size = 50
                    local total_pages = math.max(1, math.ceil(#show_entries / page_size))
                    if not _G.log_page then _G.log_page = 1 end
                    -- \xd1\xe1\xf0\xee\xf1 \xf1\xf2\xf0\xe0\xed\xe8\xf6\xfb \xef\xf0\xe8 \xf1\xec\xe5\xed\xe5 \xe2\xea\xeb\xe0\xe4\xea\xe8 \xe8\xeb\xe8 \xf4\xe8\xeb\xfc\xf2\xf0\xe0
                    if _G.log_page > total_pages then _G.log_page = total_pages end

                    -- \xc7\xe0\xe3\xee\xeb\xee\xe2\xee\xea: \xea\xee\xeb-\xe2\xee \xe7\xe0\xef\xe8\xf1\xe5\xe9 + \xef\xe0\xe3\xe8\xed\xe0\xf6\xe8\xff
                    imgui.TextDisabled(safe_u8('  \xc7\xe0\xef\xe8\xf1\xe5\xe9: ' .. #show_entries))
                    imgui.SameLine()
                    -- \xca\xed\xee\xef\xea\xe0 <<
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.18,0.18,0.22,1))
                    if imgui.SmallButton(u8'<<##logp_first') then _G.log_page = 1 end
                    imgui.SameLine(0, 2*d)
                    if imgui.SmallButton(u8'<##logp_prev') then
                        if _G.log_page > 1 then _G.log_page = _G.log_page - 1 end
                    end
                    imgui.PopStyleColor()
                    imgui.SameLine(0, 6*d)
                    imgui.TextDisabled(safe_u8('\xf1\xf2\xf0. ' .. _G.log_page .. ' / ' .. total_pages))
                    imgui.SameLine(0, 6*d)
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.18,0.18,0.22,1))
                    if imgui.SmallButton(u8'>##logp_next') then
                        if _G.log_page < total_pages then _G.log_page = _G.log_page + 1 end
                    end
                    imgui.SameLine(0, 2*d)
                    if imgui.SmallButton(u8'>>##logp_last') then _G.log_page = total_pages end
                    imgui.PopStyleColor()

                    -- \xd1\xf0\xe5\xe7 \xe7\xe0\xef\xe8\xf1\xe5\xe9 \xe4\xeb\xff \xf2\xe5\xea\xf3\xf9\xe5\xe9 \xf1\xf2\xf0\xe0\xed\xe8\xf6\xfb
                    local i_from = (_G.log_page - 1) * page_size + 1
                    local i_to   = math.min(_G.log_page * page_size, #show_entries)

                    if imgui.BeginChild('##loglist', imgui.ImVec2(-1, -1), false) then
                        for i = i_from, i_to do
                            local item = show_entries[i]
                            imgui.PushTextWrapPos(0)
                            imgui.TextDisabled(safe_u8(fmt_entry(item.e, item.k)))
                            imgui.PopTextWrapPos()
                        end
                        imgui.EndChild()
                    end
                end
                imgui.EndChild()
            end
            imgui.EndTabItem()
        end



        -- ===== TELEGRAM =====
        -- ===== РЕКОННЕКТ =====
        if imgui.BeginTabItem(u8'Реконнект') then
            local rcon = settings.reconnect
            local cw = imgui.GetWindowContentRegionWidth()
            local bw = (cw - 8*d) / 2

            -- Хелпер: кнопка-тогл с точкой (зелёная/красная) для mimgui Android
            local function dot_btn(label, key, tbl, w, h)
                local is_on = tbl[key]
                local dot   = is_on and u8'[*] ' or u8'[ ] '
                local state = is_on and u8'Вкл  ' or u8'Выкл '
                if is_on then
                    imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(0.08, 0.30, 0.08, 1))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.12, 0.46, 0.12, 1))
                    imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(0.06, 0.22, 0.06, 1))
                    imgui.PushStyleColor(imgui.Col.Text,          imgui.ImVec4(0.4, 1.0, 0.4, 1))
                else
                    imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(0.30, 0.08, 0.08, 1))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.46, 0.12, 0.12, 1))
                    imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(0.22, 0.06, 0.06, 1))
                    imgui.PushStyleColor(imgui.Col.Text,          imgui.ImVec4(1.0, 0.4, 0.4, 1))
                end
                local clicked = imgui.Button(dot .. state .. u8(label) .. '##dot_' .. key, imgui.ImVec2(w or -1, h or 30*d))
                imgui.PopStyleColor(4)
                if clicked then tbl[key] = not tbl[key]; save_settings() end
            end

            imgui.Spacing()

            -- Автореконнект + Реконнект сейчас
            dot_btn('Автореконнект', 'enabled', rcon, bw, 34*d)
            imgui.SameLine(0, 8*d)
            imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(0.13, 0.20, 0.38, 1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.30, 0.58, 1))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(0.10, 0.15, 0.28, 1))
            if imgui.Button(u8'>> Реконнект сейчас', imgui.ImVec2(bw, 34*d)) then
                fh_reconnect_active = false
                fh_do_reconnect()
            end
            imgui.PopStyleColor(3)

            -- Кнопка отмены (если активен)
            if fh_reconnect_active then
                imgui.Spacing()
                imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(0.40, 0.12, 0.08, 1))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.60, 0.18, 0.10, 1))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(0.30, 0.08, 0.06, 1))
                if imgui.Button(u8'X  Отменить реконнект', imgui.ImVec2(-1, 30*d)) then
                    fh_reconnect_active = false
                end
                imgui.PopStyleColor(3)
            end

            imgui.Spacing(); imgui.Separator(); imgui.Spacing()

            -- Задержка перед реконнектом
            imgui.TextColored(imgui.ImVec4(ar, ag, ab, 1), u8' Задержка перед реконнектом:')
            imgui.Spacing()
            if not _G.rec_delay_buf then _G.rec_delay_buf = imgui.new.float(rcon.delay or 5.0) end
            imgui.PushItemWidth(-1)
            if imgui.SliderFloat('##rec_delay', _G.rec_delay_buf, 0.0, 60.0) then
                rcon.delay = _G.rec_delay_buf[0]; save_settings()
            end
            imgui.PopItemWidth()

            imgui.Spacing(); imgui.Separator(); imgui.Spacing()

            -- Реконнект при:
            imgui.TextColored(imgui.ImVec4(ar, ag, ab, 1), u8' Реконнект при:')
            imgui.Spacing()
            local triggers = {
                {'Кик  (соед. закрыто)',           'on_kicked'},
                {'Отказ ника  (занят / неверный)', 'on_rejected'},
                {'Бан  (забанен)',                 'on_banned'},
                {'Чужой пароль сервера',           'on_password'},
            }
            for _, tr in ipairs(triggers) do
                dot_btn(tr[1], tr[2], rcon, -1, 30*d)
                imgui.Spacing()
            end

            imgui.Separator(); imgui.Spacing()

            -- Автологин
            dot_btn('Автологин', 'auto_login', rcon, -1, 34*d)

            if rcon.auto_login then
                imgui.Spacing()
                if not _G.rec_login_buf then _G.rec_login_buf = imgui.new.char[256](u8(rcon.login or '')) end
                if not _G.rec_pass_buf  then _G.rec_pass_buf  = imgui.new.char[256](u8(rcon.password or '')) end
                imgui.TextColored(imgui.ImVec4(ar, ag, ab, 1), u8' Никнейм:')
                imgui.PushItemWidth(-1)
                if imgui.InputText('##rec_login', _G.rec_login_buf, 256) then
                    rcon.login = u8:decode(ffi.string(_G.rec_login_buf)):match('^%s*(.-)%s*$'); save_settings()
                end
                imgui.PopItemWidth()
                imgui.Spacing()
                imgui.TextColored(imgui.ImVec4(ar, ag, ab, 1), u8' Пароль:')
                imgui.PushItemWidth(-1)
                if imgui.InputText('##rec_pass', _G.rec_pass_buf, 256) then
                    rcon.password = u8:decode(ffi.string(_G.rec_pass_buf)):match('^%s*(.-)%s*$'); save_settings()
                end
                imgui.PopItemWidth()
                imgui.Spacing()
                imgui.TextDisabled(u8'  Автовход после реконнекта')
            end
            imgui.Spacing()
            imgui.EndTabItem()
        end
        -- ===== /РЕКОННЕКТ =====
        if imgui.BeginTabItem(u8'Telegram') then
            local tg_h = imgui.GetWindowHeight() - 80*d
            if imgui.BeginChild('##tg_wrap', imgui.ImVec2(-1, tg_h), false) then
                if not settings.tg then settings.tg = {token='',chat_id='',enabled=false,ev_invite=true,ev_join=true,ev_leave=true,ev_level=true,ev_quest=true,ev_mute=true,ev_coins=true} end

                -- \xc8\xed\xe8\xf6\xe8\xe0\xeb\xe8\xe7\xe0\xf6\xe8\xff \xe1\xf3\xf4\xe5\xf0\xee\xe2 \xee\xe4\xe8\xed \xf0\xe0\xe7
                if not tg_token_buf then
                    tg_token_buf  = imgui.new.char[512](safe_u8(settings.tg.token  or ''))
                    tg_chatid_buf = imgui.new.char[128](safe_u8(settings.tg.chat_id or ''))
                    tg_token2_buf = imgui.new.char[512](safe_u8(settings.tg.token2   or ''))
                    tg_chanid_buf   = imgui.new.char[128](safe_u8(settings.tg.channel_id or ''))
                end

                imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' Telegram \xf3\xe2\xe5\xe4\xee\xec\xeb\xe5\xed\xe8\xff')
                imgui.Separator()

                -- \xc2\xea\xeb/\xe2\xfb\xea\xeb
                local tg_en = settings.tg.enabled
                if imgui.Checkbox(u8'\xc2\xea\xeb\xfe\xf7\xe8\xf2\xfc \xf3\xe2\xe5\xe4\xee\xec\xeb\xe5\xed\xe8\xff##tgen', imgui.new.bool(tg_en)) then
                    settings.tg.enabled = not tg_en; save_settings()
                end
                imgui.Spacing()

                -- \xd2\xee\xea\xe5\xed
                imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe0 \xe1\xee\xf2\xe0')
                imgui.Separator()
                imgui.TextDisabled(u8' 1. \xcd\xe0\xef\xe8\xf8\xe8\xf2\xe5 @BotFather \xe2 Telegram -> /newbot')
                imgui.TextDisabled(u8' 2. \xd1\xea\xee\xef\xe8\xf0\xf3\xe9\xf2\xe5 \xf2\xee\xea\xe5\xed \xe1\xee\xf2\xe0 \xf1\xfe\xe4\xe0')
                imgui.TextDisabled(u8' 3. \xc4\xee\xe1\xe0\xe2\xfc\xf2\xe5 \xe1\xee\xf2\xe0 \xe2 \xe2\xe0\xf8 \xf7\xe0\xf2/\xea\xe0\xed\xe0\xeb')
                imgui.TextDisabled(u8' 4. \xd3\xe7\xed\xe0\xe9\xf2\xe5 ID \xf7\xe0\xf2\xe0 \xf7\xe5\xf0\xe5\xe7 @getmyid_bot')
                imgui.Spacing()
                -- \xd0\xe5\xe6\xe8\xec: \xf2\xee\xeb\xfc\xea\xee \xc0\xe2\xf2\xee
                imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xd0\xe5\xe6\xe8\xec \xf0\xe0\xe1\xee\xf2\xfb')
                imgui.Separator()
                local d = settings.general.custom_dpi

                -- \xd1\xf2\xe0\xf2\xf3\xf1 \xe0\xe2\xf2\xee-\xe3\xeb\xe0\xe2\xe5\xed\xf1\xf2\xe2\xe0
                settings.tg.auto_role = true  -- \xe2\xf1\xe5\xe3\xe4\xe0 \xe0\xe2\xf2\xee
                local senior = am_i_senior()
                local cnt = 0; for _ in pairs(fh_online) do cnt = cnt + 1 end
                if senior then
                    imgui.TextColored(imgui.ImVec4(0.2,1,0.2,1), u8'  \xc2\xfb \xe3\xeb\xe0\xe2\xed\xfb\xe9 \x97 \xe2\xf1\xe5 \xf1\xee\xe1\xfb\xf2\xe8\xff \xe8\xe4\xf3\xf2 \xe2 \xd2\xc3')
                else
                    imgui.TextColored(imgui.ImVec4(1,0.8,0.2,1), u8'  \xc7\xe0\xec \x97 \xe5\xf1\xf2\xfc \xea\xf2\xee \xf1\xf2\xe0\xf0\xf8\xe5 \xee\xed\xeb\xe0\xe9\xed')
                end
                imgui.TextDisabled(safe_u8('  \xd1\xea\xf0\xe8\xef\xf2\xee\xe2 \xee\xed\xeb\xe0\xe9\xed: ' .. cnt))
                if cnt > 0 then
                    local names = {}
                    for nick, data in pairs(fh_online) do
                        local marker = (nick == my_nick()) and ' <' or ''
                        table.insert(names, nick .. '(\xf0' .. data.rank .. ')' .. marker)
                    end
                    table.sort(names)
                    imgui.TextDisabled(safe_u8('  ' .. table.concat(names, ', ')))
                end
                imgui.TextDisabled(u8'  \xc3\xeb\xe0\xe2\xed\xfb\xe9 \xee\xef\xf0\xe5\xe4\xe5\xeb\xff\xe5\xf2\xf1\xff \xe0\xe2\xf2\xee\xec\xe0\xf2\xe8\xf7\xe5\xf1\xea\xe8 \xef\xee \xf0\xe0\xed\xe3\xf3 \xe8 \xe2\xf0\xe5\xec\xe5\xed\xe8 \xe2\xf5\xee\xe4\xe0')
                imgui.Spacing(); imgui.Separator(); imgui.Spacing()

                imgui.Text(u8' \xd2\xee\xea\xe5\xed \xe1\xee\xf2\xe0:')
                imgui.PushItemWidth(-1)
                if imgui.InputText('##tg_token', tg_token_buf, 512) then
                    settings.tg.token = u8:decode(ffi.string(tg_token_buf)):match('^%s*(.-)%s*$')
                    save_settings()
                end
                imgui.PopItemWidth()
                imgui.Spacing()
                imgui.Text(u8' Токен бота 2 (чтение из канала):')
                imgui.TextDisabled(u8'  Бот 2 видит сообщения бота 1 - необходим для записи лога')
                imgui.PushItemWidth(-1)
                if imgui.InputText('##tg_token2', tg_token2_buf, 512) then
                    settings.tg.token2 = u8:decode(ffi.string(tg_token2_buf)):match('^%s*(.-)%s*$')
                    save_settings()
                end
                imgui.PopItemWidth()
                imgui.Text(u8' ID \xf7\xe0\xf2\xe0 (\xef\xf0\xe8\xec\xe5\xf0: -100123456789):')
                imgui.PushItemWidth(-1)
                if imgui.InputText('##tg_chatid', tg_chatid_buf, 128) then
                    settings.tg.chat_id = u8:decode(ffi.string(tg_chatid_buf)):match('^%s*(.-)%s*$')
                    save_settings()
                end
                imgui.PopItemWidth()
                imgui.Spacing()
                imgui.Text(u8' ID канала (чтение пропущенных):')
                imgui.TextDisabled(u8'  Создай канал и добавь бота админом')
                imgui.PushItemWidth(-1)
                if imgui.InputText('##tg_chanid', tg_chanid_buf, 128) then
                    settings.tg.channel_id = u8:decode(ffi.string(tg_chanid_buf)):match('^%s*(.-)%s*$')
                    save_settings()
                end
                imgui.PopItemWidth()
                if imgui.Button(u8' Сбросить offset ##tgreset', imgui.ImVec2(-1, 28*d)) then
                    settings.tg.last_update_offset = 0
                    save_settings()
                    sampAddChatMessage('[Family Helper] TG: offset сброшен, при след. входе пречитается всё', 0xFFAA00)
                end
                imgui.Spacing()
                if imgui.Button(u8' Отправить тест в Telegram ##tgtest', imgui.ImVec2(-1, 28*d)) then
                    local ttest_tok = settings.tg.token or ''
                    local ttest_cid = settings.tg.chat_id or ''
                    if ttest_tok == '' or ttest_cid == '' then
                        sampAddChatMessage('[Family Helper] {ff4444}TG: заполни токен и chat_id!', 0xFFFFFF)
                    elseif not settings.tg.enabled then
                        sampAddChatMessage('[Family Helper] {ff4444}TG: включи уведомления!', 0xFFFFFF)
                    else
                        tg_send('[Family Helper] Тест! Семья: ' .. (settings.family_info.family_name or '?'))
                        sampAddChatMessage('[Family Helper] {00cc00}TG: отправлено!', 0xFFFFFF)
                    end
                end
                imgui.Spacing()
                -- \xcf\xee\xe4\xf1\xea\xe0\xe7\xea\xe0 \xef\xee \xf7\xe0\xf1\xf2\xfb\xec \xee\xf8\xe8\xe1\xea\xe0\xec
                imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.07,0.07,0.07,1))
                imgui.BeginChild('##tg_hint', imgui.ImVec2(-1, 70*d), true)
                    imgui.TextDisabled(u8' \xc5\xf1\xeb\xe8 \xf2\xe5\xf1\xf2 \xed\xe5 \xef\xf0\xe8\xf5\xee\xe4\xe8\xf2:')
                    imgui.TextDisabled(u8'  - \xd3\xe1\xe5\xe4\xe8\xf2\xe5\xf1\xfc \xf7\xf2\xee \xe1\xee\xf2 \xc4\xce\xc1\xc0\xc2\xcb\xc5\xcd \xe2 \xf7\xe0\xf2/\xea\xe0\xed\xe0\xeb \xea\xe0\xea \xe0\xe4\xec\xe8\xed\xe8\xf1\xf2\xf0\xe0\xf2\xee\xf0')
                    imgui.TextDisabled(u8'  - chat_id \xe4\xeb\xff \xeb\xe8\xf7\xed\xfb\xf5 \xf1\xee\xee\xe1\xf9\xe5\xed\xe8\xe9: \xef\xf0\xee\xf1\xf2\xee \xe2\xe0\xf8 ID \xe1\xe5\xe7 \xec\xe8\xed\xf3\xf1\xe0')
                    imgui.TextDisabled(u8'  - \xc4\xeb\xff \xe3\xf0\xf3\xef\xef\xfb/\xea\xe0\xed\xe0\xeb\xe0 ID \xed\xe0\xf7\xe8\xed\xe0\xe5\xf2\xf1\xff \xf1 -100...')
                imgui.EndChild()
                imgui.PopStyleColor()
                imgui.Spacing(); imgui.Separator(); imgui.Spacing()

                -- \xc2\xfb\xe1\xee\xf0 \xf1\xee\xe1\xfb\xf2\xe8\xe9
                imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xca\xe0\xea\xe8\xe5 \xf1\xee\xe1\xfb\xf2\xe8\xff \xee\xf2\xef\xf0\xe0\xe2\xeb\xff\xf2\xfc:')
                imgui.Separator()
                local evs = {
                    {'ev_invite', '\xcf\xf0\xe8\xed\xff\xeb \xe8\xed\xe2\xe0\xe9\xf2'},
                    {'ev_join',   '\xc2\xf1\xf2\xf3\xef\xe8\xeb \xe2 \xf1\xe5\xec\xfc\xfe'},
                    {'ev_leave',  '\xcf\xee\xea\xe8\xed\xf3\xeb / \xea\xe8\xea\xed\xf3\xf2'},
                    {'ev_level',  '\xcf\xee\xe4\xed\xff\xeb \xf3\xf0\xee\xe2\xe5\xed\xfc'},
                    {'ev_quest',  '\xc2\xfb\xef\xee\xeb\xed\xe8\xeb \xea\xe2\xe5\xf1\xf2'},
                    {'ev_mute',   '\xcc\xf3\xf2 (\xf1\xe5\xec\xe5\xe9\xed\xfb\xe9)'},
                    {'ev_coins',  '\xcc\xee\xed\xe5\xf2\xfb/\xf2\xe0\xeb\xee\xed\xfb'},
                    {'ev_bank',   '\xd1\xea\xeb\xe0\xe4 ($)'},
                }
                local ev_w = (imgui.GetWindowContentRegionWidth() - 4*d) / 2
                for ei, ev in ipairs(evs) do
                    if ei % 2 == 0 then imgui.SameLine() end
                    local val = settings.tg[ev[1]]
                    if val == nil then val = true; settings.tg[ev[1]] = true; save_settings() end
                    if imgui.Checkbox(safe_u8(ev[2] .. '##tgev_' .. ev[1]), imgui.new.bool(val)) then
                        settings.tg[ev[1]] = not val; save_settings()
                    end
                end

                imgui.EndChild()
            end
            imgui.EndTabItem()
        end



        -- ===== \xc2\xc8\xc4 =====
        if imgui.BeginTabItem(u8'\xc2\xe8\xe4') then
            local vid_h = imgui.GetWindowHeight() - 80*d
            if imgui.BeginChild('##vid_wrap', imgui.ImVec2(-1, vid_h), false) then
                imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xc2\xed\xe5\xf8\xed\xe8\xe9 \xe2\xe8\xe4'); imgui.Separator()
                imgui.Spacing()
                imgui.TextDisabled(u8' \xc0\xea\xf6\xe5\xed\xf2\xed\xfb\xe9 \xf6\xe2\xe5\xf2:')
                imgui.PushItemWidth(-1)
                if imgui.ColorEdit3('##acc', accent_color) then
                    settings.interface.accent_r=accent_color[0]; settings.interface.accent_g=accent_color[1]
                    settings.interface.accent_b=accent_color[2]; save_settings(); apply_theme()
                end
                imgui.PopItemWidth()
                imgui.Spacing()
                imgui.TextDisabled(u8' \xcf\xf0\xe5\xf1\xe5\xf2\xfb:')
                local presets = {
                    {u8'\xce\xf0\xe0\xed\xe6', 1,.65,0},
                    {u8'\xd1\xe8\xed\xe8\xe9', .2,.5,1},
                    {u8'\xc7\xe5\xeb\xb8\xed', .2,.8,.3},
                    {u8'\xca\xf0\xe0\xf1\xed', .9,.2,.2},
                    {u8'\xd4\xe8\xee\xeb', .6,.3,.9},
                    {u8'\xc1\xe5\xeb\xfb\xe9', .85,.85,.85},
                }
                local pw = (imgui.GetWindowContentRegionWidth() - 5*4*d) / #presets
                for pi, pr in ipairs(presets) do
                    if pi > 1 then imgui.SameLine() end
                    imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(pr[2]*.4,pr[3]*.4,pr[4]*.4,1))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(pr[2]*.6,pr[3]*.6,pr[4]*.6,1))
                    imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(pr[2]*.8,pr[3]*.8,pr[4]*.8,1))
                    if imgui.Button(pr[1]..'##pr'..pi, imgui.ImVec2(pw, 28*d)) then
                        settings.interface.accent_r=pr[2]; settings.interface.accent_g=pr[3]; settings.interface.accent_b=pr[4]
                        accent_color[0]=pr[2]; accent_color[1]=pr[3]; accent_color[2]=pr[4]; save_settings(); apply_theme()
                    end
                    imgui.PopStyleColor(3)
                end
                imgui.Spacing(); imgui.Separator(); imgui.Spacing()
                imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xcf\xe0\xf0\xe0\xec\xe5\xf2\xf0\xfb'); imgui.Separator()
                imgui.TextDisabled(u8' \xdf\xf0\xea\xee\xf1\xf2\xfc \xf4\xee\xed\xe0:'); imgui.SameLine(); imgui.PushItemWidth(-1)
                if imgui.SliderFloat('##\xd1\x8f\xd1\x80\xd0\xba\xd0\xbe_v', sl.bg_bright, 0.05, 0.30) then settings.interface.bg_brightness=sl.bg_bright[0]; save_settings(); apply_theme() end
                imgui.PopItemWidth()
                imgui.TextDisabled(u8' \xcf\xf0\xee\xe7\xf0\xe0\xf7\xed\xee\xf1\xf2\xfc:'); imgui.SameLine(); imgui.PushItemWidth(-1)
                if imgui.SliderFloat('##\xd0\xbf\xd1\x80\xd0\xbe\xd0\xb7_v', sl.window_alpha, 0.5, 1.0) then settings.interface.window_alpha=sl.window_alpha[0]; save_settings(); apply_theme() end
                imgui.PopItemWidth()
                imgui.TextDisabled(u8' \xd0\xe0\xe7\xec\xe5\xf0 \xea\xed\xee\xef\xea\xe8:'); imgui.SameLine(); imgui.PushItemWidth(-1)
                if imgui.SliderFloat('##\xd1\x80\xd0\xb0\xd0\xb7\xd0\xbc_v', sl.float_size, 0.5, 2.0) then settings.general.float_btn_size=sl.float_size[0]; save_settings() end
                imgui.PopItemWidth()
                imgui.Spacing(); imgui.Separator(); imgui.Spacing()
                imgui.TextColored(imgui.ImVec4(ar,ag,ab,1), u8' \xcc\xe0\xf1\xf8\xf2\xe0\xe1 (DPI)'); imgui.Separator()
                imgui.TextDisabled(u8'  \xd2\xe5\xea\xf3\xf9\xe8\xe9: ' .. string.format('%.2f', settings.general.custom_dpi or 1.0))
                imgui.PushItemWidth(-1)
                if imgui.SliderFloat('##dpi_sl', sl.dpi, 0.5, 3.0, '%.2f') then
                    settings.general.custom_dpi=sl.dpi[0]; save_settings(); apply_theme()
                end
                imgui.PopItemWidth()
                imgui.EndChild()
            end
            imgui.EndTabItem()
        end


        if imgui.BeginTabItem(u8'Wiki') then
            local ar=settings.interface.accent_r or 1
            local ag=settings.interface.accent_g or .65
            local ab=settings.interface.accent_b or 0
            local wiki_h = imgui.GetWindowHeight() - 80*d
            if imgui.BeginTabBar('##wikitabs') then
                if imgui.BeginTabItem(u8'\xca\xee\xec\xe0\xed\xe4\xfb') then
                    if imgui.BeginChild('##wiki_cmds', imgui.ImVec2(-1, wiki_h - 50*d), false) then
                        imgui.TextColored(imgui.ImVec4(ar,ag,0,1), u8' \xd1\xe5\xf0\xe2\xe5\xf0\xed\xfb\xe5 \xea\xee\xec\xe0\xed\xe4\xfb \xf1\xe5\xec\xfc\xe8'); imgui.Separator()
                        local cmds = {
                            {u8'/fam [\xf2\xe5\xea\xf1\xf2]', u8'\xd7\xe0\xf2 \xf1\xe5\xec\xfc\xe8'},
                            {u8'/fammenu', u8'\xcc\xe5\xed\xfe \xf1\xe5\xec\xfc\xe8'},
                            {u8'/fmembers', u8'\xd1\xef\xe8\xf1\xee\xea \xee\xed\xeb\xe0\xe9\xed'},
                            {u8'/faminvite [ID]', u8'\xcf\xf0\xe8\xe3\xeb\xe0\xf1\xe8\xf2\xfc \xe8\xe3\xf0\xee\xea\xe0'},
                            {u8'/famuninvite [ID] [\xef\xf0\xe8\xf7\xe8\xed\xe0]', u8'\xca\xe8\xea \xe8\xe7 \xf1\xe5\xec\xfc\xe8'},
                            {u8'/famoffkick [\xed\xe8\xea]', u8'\xca\xe8\xea \xee\xf4\xf4\xeb\xe0\xe9\xed'},
                            {u8'/fammute [ID] [\xec\xe8\xed.] [\xef\xf0\xe8\xf7\xe8\xed\xe0]', u8'\xcc\xf3\xf2 \xf3\xf7\xe0\xf1\xf2\xed\xe8\xea\xe0'},
                            {u8'/famunmute [ID]', u8'\xd1\xed\xff\xf2\xfc \xec\xf3\xf2'},
                            {u8'/setfrank [ID] [\xf0\xe0\xed\xe3]', u8'\xd3\xf1\xf2\xe0\xed\xee\xe2\xe8\xf2\xfc \xf0\xe0\xed\xe3'},
                            {u8'/ftag [\xed\xe8\xea] [\xf2\xe5\xe3]', u8'\xd3\xf1\xf2\xe0\xed\xee\xe2\xe8\xf2\xfc \xf2\xe5\xe3'},
                            {u8'/famwarn [ID] [\xef\xf0\xe8\xf7\xe8\xed\xe0]', u8'\xc2\xfb\xe3\xee\xe2\xee\xf0'},
                            {u8'/famunwarn [ID]', u8'\xd1\xed\xff\xf2\xfc \xe2\xfb\xe3\xee\xe2\xee\xf0'},
                            {u8'/famdeposit [\xf1\xf3\xec\xec\xe0]', u8'\xcf\xee\xef\xee\xeb\xed\xe8\xf2\xfc \xea\xe0\xe7\xed\xf3'},
                            {u8'/famwithdraw [\xf1\xf3\xec\xec\xe0]', u8'\xc2\xe7\xff\xf2\xfc \xe8\xe7 \xea\xe0\xe7\xed\xfb'},
                            {u8'/famdisband', u8'\xd0\xe0\xf1\xf4\xee\xf0\xec\xe8\xf0\xee\xe2\xe0\xf2\xfc \xf1\xe5\xec\xfc\xfe'},
                            {u8'/faminfoset', u8'\xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8 \xf1\xe5\xec\xfc\xe8'},
                        }
                        local half = imgui.GetWindowContentRegionWidth() / 2 - 8*d
                        imgui.Columns(2, '##cmgrid', false)
                        imgui.SetColumnWidth(0, imgui.GetWindowContentRegionWidth() / 2)
                        imgui.SetColumnWidth(1, imgui.GetWindowContentRegionWidth() / 2)
                        for ci, row in ipairs(cmds) do
                            imgui.TextColored(imgui.ImVec4(ar,ag,0,1), row[1])
                            imgui.SameLine(0,4)
                            imgui.TextDisabled(safe_u8(' \x97 ' .. u8:decode(row[2])))
                            imgui.NextColumn()
                        end
                        imgui.Columns(1)
                        imgui.EndChild()
                    end
                    imgui.EndTabItem()
                end
                if imgui.BeginTabItem(u8'\xc7\xe0\xec\xe5\xf2\xea\xe8') then
                    if imgui.BeginChild('##wiki_notes', imgui.ImVec2(-1, wiki_h - 86*d), true) then
                        imgui.TextColored(imgui.ImVec4(ar,ag,0,1), u8' \xc7\xe0\xec\xe5\xf2\xea\xe8'); imgui.Separator()
                        for i, n in ipairs(settings.note) do
                            if not n.deleted then
                                imgui.Columns(2, '##nr'..i, false)
                                imgui.SetColumnWidth(0, 450*d)
                                imgui.Text(safe_u8(' ' .. (n.note_name or '')))
                                imgui.NextColumn()
                                if imgui.SmallButton(u8'\xce\xf2\xea\xf0\xfb\xf2\xfc##n'..i) then
                                    show_note_name=safe_u8(n.note_name); show_note_text=safe_u8(n.note_text); NoteWindow[0]=true
                                end
                                imgui.SameLine()
                                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.4,0.1,0.1,1))
                                if imgui.SmallButton('X##nd'..i) then n.deleted=true; save_settings() end
                                imgui.PopStyleColor()
                                imgui.Columns(1); imgui.Separator()
                            end
                        end
                        imgui.EndChild()
                    end
                    if imgui.Button(u8' + \xc7\xe0\xec\xe5\xf2\xea\xe0', imgui.ImVec2(-1, 0)) then
                        table.insert(settings.note, {note_name='\xcd\xee\xe2\xe0\xff', note_text='\xd2\xe5\xea\xf1\xf2', deleted=false}); save_settings()
                    end
                    imgui.EndTabItem()
                end
                if imgui.BeginTabItem(u8'\xce \xf1\xea\xf0\xe8\xef\xf2\xe5') then
                    if imgui.BeginChild('##wiki_about', imgui.ImVec2(-1, wiki_h - 50*d), false) then
                        imgui.Spacing()
                        imgui.TextColored(imgui.ImVec4(ar,ag,0,1), u8'  Family Helper v' .. thisScript().version)
                        imgui.TextDisabled(u8'  \xc0\xe2\xf2\xee\xf0: Shinik_Pupckin')
                        imgui.Spacing(); imgui.Separator(); imgui.Spacing()
                        imgui.TextColored(imgui.ImVec4(ar,ag,0,1), u8'  \xc8\xed\xf1\xf2\xf0\xf3\xea\xf6\xe8\xff'); imgui.Separator()
                        imgui.TextDisabled(u8'  1. /fh \x97 \xee\xf2\xea\xf0\xfb\xf2\xfc/\xe7\xe0\xea\xf0\xfb\xf2\xfc \xe3\xeb\xe0\xe2\xed\xee\xe5 \xee\xea\xed\xee')
                        imgui.TextDisabled(u8'  2. /fi [ID] \x97 \xe1\xfb\xf1\xf2\xf0\xee\xe5 \xec\xe5\xed\xfe \xe4\xe5\xe9\xf1\xf2\xe2\xe8\xe9 \xf1 \xe8\xe3\xf0\xee\xea\xee\xec')
                        imgui.TextDisabled(u8'  3. /fm [ID] \x97 \xe1\xfb\xf1\xf2\xf0\xee\xe5 \xec\xe5\xed\xfe \xe8\xe3\xf0\xee\xea\xe0')
                        imgui.TextDisabled(u8'  4. /fai \x97 \xe0\xe2\xf2\xee-\xe8\xed\xe2\xe0\xe9\xf2 \xe2\xea\xeb/\xe2\xfb\xea\xeb')
                        imgui.TextDisabled(u8'  5. /fp [\xed\xee\xec\xe5\xf0] \x97 \xe7\xe0\xef\xf3\xf1\xf2\xe8\xf2\xfc \xf8\xe0\xe1\xeb\xee\xed \xef\xe8\xe0\xf0\xe0')
                        imgui.TextDisabled(u8'  6. /fhdlg \x97 \xe4\xe5\xe1\xe0\xe3 \xe4\xe8\xe0\xeb\xee\xe3\xee\xe2 \xe2\xea\xeb/\xe2\xfb\xea\xeb')
                        imgui.TextDisabled(u8'  7. /fhstats \x97 \xf1\xf2\xe0\xf2\xe8\xf1\xf2\xe8\xea\xe0 \xf1\xea\xf0\xe8\xef\xf2\xe0')
                        imgui.TextDisabled(u8'  8. /stop \x97 \xee\xf1\xf2\xe0\xed\xee\xe2\xe8\xf2\xfc \xe2\xfb\xef\xee\xeb\xed\xe5\xed\xe8\xe5 \xea\xee\xec\xe0\xed\xe4\xfb')
                        imgui.Spacing(); imgui.Separator(); imgui.Spacing()
                        imgui.TextColored(imgui.ImVec4(ar,ag,0,1), u8'  \xd3\xef\xf0\xe0\xe2\xeb\xe5\xed\xe8\xe5 \xf1\xea\xf0\xe8\xef\xf2\xee\xec'); imgui.Separator()
                        local bw2 = (imgui.GetWindowContentRegionWidth() - 8*d) / 3
                        if imgui.Button(u8' \xcf\xe5\xf0\xe5\xe7\xe0\xe3\xf0\xf3\xe7\xe8\xf2\xfc', imgui.ImVec2(bw2, 0)) then reload_script=true; thisScript():reload() end
                        imgui.SameLine(0,4)
                        if imgui.Button(u8' \xd1\xe1\xf0\xee\xf1 \xed\xe0\xf1\xf2\xf0\xee\xe5\xea', imgui.ImVec2(bw2, 0)) then settings=default_settings; save_settings(); reload_script=true; thisScript():reload() end
                        imgui.SameLine(0,4)
                        if imgui.Button(u8' \xc2\xfb\xea\xeb\xfe\xf7\xe8\xf2\xfc', imgui.ImVec2(bw2, 0)) then reload_script=true; thisScript():unload() end
                        imgui.EndChild()
                    end
                    imgui.EndTabItem()
                end
                imgui.EndTabBar()
            end
            imgui.EndTabItem()
        end


        -- ===== МАРКЕТ v3 =====
        if imgui.BeginTabItem(u8'Маркет') then
            fh_draw_market()
            imgui.EndTabItem()
        end


        imgui.EndTabBar()
    end

    imgui.End()
end)

-- ========== FH MARKET: ДЕТАЛЬu ТОВАРА (отдельное окно) ==========
imgui.OnFrame(
    function() return _G.mkt_detail_open == true end,
    function()
        local d  = settings.general.custom_dpi
        local sw, sh = imgui.GetIO().DisplaySize.x, imgui.GetIO().DisplaySize.y
        local pop_w = math.min(sw - 20*d, 480*d)
        local pop_h = math.min(sh - 60*d, 560*d)
        imgui.SetNextWindowSize(imgui.ImVec2(pop_w, pop_h), imgui.Cond.Always)
        imgui.SetNextWindowPos(imgui.ImVec2(sw/2, sh/2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
        local closed = imgui.new.bool(true)
        if imgui.Begin(u8'Статистика товара##dtlpop', closed,
            imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize) then
            change_dpi()
            if _G.mkt_detail_item then
                fh_draw_item_detail(_G.mkt_detail_item, _G.mkt_detail_src)
            end
            imgui.Spacing()
            if imgui.Button(u8'Закрыть##dtlclose', imgui.ImVec2(-1, 0)) then
                _G.mkt_detail_open = false
            end
        end
        if not closed[0] then _G.mkt_detail_open = false end
        imgui.End()
    end
)

-- ========== FH AUTO: ДЕТАЛЬu АВТО ==========
imgui.OnFrame(
    function() return _G.mkt_auto_detail_open == true end,
    function()
        local d  = settings.general.custom_dpi
        local ar = settings.interface.accent_r or 1
        local ag = settings.interface.accent_g or .65
        local ac = imgui.ImVec4(ar, ag, 0, 1)
        local sw, sh = imgui.GetIO().DisplaySize.x, imgui.GetIO().DisplaySize.y
        local pop_w = math.min(sw - 20*d, 480*d)
        local pop_h = math.min(sh - 40*d, 560*d)
        imgui.SetNextWindowSize(imgui.ImVec2(pop_w, pop_h), imgui.Cond.Always)
        imgui.SetNextWindowPos(imgui.ImVec2(sw/2, sh/2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
        local closed2 = imgui.new.bool(true)
        if imgui.Begin(u8'Статистика авто##autopop', closed2,
            imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize) then
            change_dpi()
            local nm = _G.mkt_auto_detail_item or ''
            local e  = fh_mkt_auto[nm]
            local cp_hist = e and e.cp_hist
            imgui.TextColored(ac, safe_u8('Авто: ' .. nm))
            if e and e.date then
                imgui.SameLine()
                imgui.TextDisabled(safe_u8('  обновлено ' .. e.date))
            end
            imgui.Separator(); imgui.Spacing()
            if e then
                if cp_hist and #cp_hist > 0 then
                    local s7  = fh_hist_stats(cp_hist, 7)
                    local s30 = fh_hist_stats(cp_hist, 30)
                    local trend = fh_trend(cp_hist)
                    local tc_tr = fh_trend_color(trend)
                    imgui.TextColored(ac, u8'Статистика (мировой рынок)')
                    imgui.Spacing()
                    imgui.Columns(4, '##adtl2', false)
                    imgui.SetColumnWidth(0, 85*d); imgui.SetColumnWidth(1, 100*d)
                    imgui.SetColumnWidth(2, 70*d);  imgui.SetColumnWidth(3, 130*d)
                    imgui.TextColored(imgui.ImVec4(0.6,0.6,0.6,1), u8''); imgui.NextColumn()
                    imgui.TextColored(imgui.ImVec4(0.6,0.6,0.6,1), u8'Ср. цена $'); imgui.NextColumn()
                    imgui.TextColored(imgui.ImVec4(0.6,0.6,0.6,1), u8'Сделок'); imgui.NextColumn()
                    imgui.TextColored(imgui.ImVec4(0.6,0.6,0.6,1), u8'Мин / Макс'); imgui.NextColumn()
                    local today_h = cp_hist[1]
                    imgui.TextColored(imgui.ImVec4(0.4,0.95,1,1), u8'Сегодня'); imgui.NextColumn()
                    if today_h and today_h.price and today_h.price > 0 then
                        imgui.TextColored(imgui.ImVec4(0.4,0.95,1,1), safe_u8('$'..fh_num_fmt(today_h.price))); imgui.NextColumn()
                        imgui.TextColored(imgui.ImVec4(1,1,1,0.8), safe_u8(tostring(today_h.qty or 0))); imgui.NextColumn()
                        imgui.TextColored(imgui.ImVec4(1,1,1,0.4), safe_u8(today_h.dt or '')); imgui.NextColumn()
                    else
                        for _=1,3 do imgui.TextDisabled(u8'—'); imgui.NextColumn() end
                    end
                    imgui.TextColored(imgui.ImVec4(1,0.85,0.2,1), u8'За 7 дн.'); imgui.NextColumn()
                    if s7 then
                        imgui.TextColored(imgui.ImVec4(1,0.85,0.2,1), safe_u8('$'..fh_num_fmt(s7.avg))); imgui.NextColumn()
                        imgui.TextColored(imgui.ImVec4(1,1,1,0.8), safe_u8(fh_num_fmt(s7.qty))); imgui.NextColumn()
                        imgui.TextColored(imgui.ImVec4(1,1,1,0.6), safe_u8(fh_num_short(s7.min)..'/'..fh_num_short(s7.max))); imgui.NextColumn()
                    else for _=1,3 do imgui.TextDisabled(u8'—'); imgui.NextColumn() end end
                    imgui.TextColored(imgui.ImVec4(0.4,0.95,0.4,1), u8'За 30 дн.'); imgui.NextColumn()
                    if s30 then
                        imgui.TextColored(imgui.ImVec4(0.4,0.95,0.4,1), safe_u8('$'..fh_num_fmt(s30.avg))); imgui.NextColumn()
                        imgui.TextColored(imgui.ImVec4(1,1,1,0.8), safe_u8(fh_num_fmt(s30.qty))); imgui.NextColumn()
                        imgui.TextColored(imgui.ImVec4(1,1,1,0.6), safe_u8(fh_num_short(s30.min)..'/'..fh_num_short(s30.max))); imgui.NextColumn()
                    else for _=1,3 do imgui.TextDisabled(u8'—'); imgui.NextColumn() end end
                    imgui.Columns(1); imgui.Spacing()
                    imgui.TextColored(imgui.ImVec4(0.6,0.6,0.6,1), u8'Тренд: ')
                    imgui.SameLine()
                    imgui.TextColored(tc_tr, safe_u8(trend))
                    imgui.Spacing()
                    local plot_n = math.min(#cp_hist, 30)
                    local p_min_v, p_max_v = math.huge, -math.huge
                    local plot_tbl = {}
                    for i = plot_n, 1, -1 do
                        local pv = cp_hist[i].price or 0
                        table.insert(plot_tbl, pv)
                        if pv < p_min_v then p_min_v = pv end
                        if pv > p_max_v then p_max_v = pv end
                    end
                    if #plot_tbl > 1 then
                        local plot_arr = imgui.new.float[#plot_tbl]()
                        for i, v in ipairs(plot_tbl) do plot_arr[i-1] = v end
                        local lbl = safe_u8('Мин: $'..fh_num_short(p_min_v)..'  Макс: $'..fh_num_short(p_max_v))
                        imgui.PlotLines('##autoplot', plot_arr, #plot_tbl, 0, lbl, p_min_v*0.98, p_max_v*1.02,
                            imgui.ImVec2(imgui.GetContentRegionAvail().x, 70*d))
                    end
                    imgui.Spacing(); imgui.Separator(); imgui.Spacing()
                elseif e.s_avg or e.cp_sp then
                    imgui.TextColored(ac, u8'Цены (пов. скан)')
                    imgui.Spacing()
                    local price = e.s_avg or e.cp_sp
                    imgui.TextColored(imgui.ImVec4(1,0.85,0.2,1), safe_u8('$'..fh_num_fmt(price)))
                    if e.s_min then imgui.TextColored(imgui.ImVec4(0.4,0.95,0.4,1), safe_u8('Мин: $'..fh_num_fmt(e.s_min))) end
                    if e.s_max then imgui.TextColored(imgui.ImVec4(1,0.5,0.5,1), safe_u8('Макс: $'..fh_num_fmt(e.s_max))) end
                    imgui.Spacing()
                    imgui.TextDisabled(u8'Для графика -- Углублённый скан авто [FH]')
                    imgui.Spacing(); imgui.Separator(); imgui.Spacing()
                end
                -- Таблица по дням из cp_hist (аналог цр)
                if cp_hist and #cp_hist > 0 then
                    imgui.TextColored(imgui.ImVec4(1,0.85,0.2,0.9), safe_u8('  История по дням (' .. #cp_hist .. '):'  ))
                    local hist_h = math.min(#cp_hist * 18*d + 30*d, 220*d)
                    if imgui.BeginChild('##autohistch', imgui.ImVec2(-1, hist_h), true) then
                        imgui.Columns(3, '##auto_hd', false)
                        imgui.SetColumnWidth(0, 120*d); imgui.SetColumnWidth(1, 70*d); imgui.SetColumnWidth(2, 110*d)
                        imgui.TextColored(imgui.ImVec4(0.5,0.5,0.5,1), u8' Дата'); imgui.NextColumn()
                        imgui.TextColored(imgui.ImVec4(0.5,0.5,0.5,1), u8' Сделок'); imgui.NextColumn()
                        imgui.TextColored(imgui.ImVec4(0.5,0.5,0.5,1), u8' Ср. цена за день'); imgui.NextColumn()
                        imgui.Separator()
                        for i, h in ipairs(cp_hist) do
                            local rc = (i==1) and imgui.ImVec4(1,0.85,0.2,1) or imgui.ImVec4(0.85,0.85,0.85,1)
                            imgui.TextColored(imgui.ImVec4(0.65,0.65,0.65,1), safe_u8(' '..(h.dt or ''))); imgui.NextColumn()
                            imgui.TextColored(imgui.ImVec4(1,1,1,0.75), safe_u8(' '..(h.qty or 0))); imgui.NextColumn()
                            imgui.TextColored(rc, safe_u8(' $'..fh_num_fmt(h.price or 0))); imgui.NextColumn()
                        end
                        imgui.Columns(1); imgui.EndChild()
                    end
                elseif e.hist and #e.hist > 0 then
                    -- Только поверхностный скан
                    local hist = e.hist
                    imgui.TextColored(imgui.ImVec4(0.6,0.6,0.6,1), u8'История сканов:')
                    if imgui.BeginChild('##autohistch', imgui.ImVec2(-1, 100*d), true) then
                        for hi = 1, #hist do
                            local h = hist[hi]
                            imgui.TextColored(imgui.ImVec4(0.5,0.5,0.5,1), safe_u8(h.dt or ''))
                            imgui.SameLine(70*d)
                            imgui.TextColored(imgui.ImVec4(1,0.85,0.2,1), safe_u8('$'..fh_num_fmt(h.price or 0)))
                        end
                        imgui.EndChild()
                    end
                end
            else
                imgui.TextDisabled(u8'Данные не найдены')
            end
            imgui.Spacing()
            if imgui.Button(u8'Закрыть##autodtlclose', imgui.ImVec2(-1, 0)) then
                _G.mkt_auto_detail_open = false
            end
        end
        if not closed2[0] then _G.mkt_auto_detail_open = false end
        imgui.End()
    end
)

-- ========== \xd0\xc5\xc4\xc0\xca\xd2\xce\xd0 \xd8\xc0\xc3\xc0 ==========
imgui.OnFrame(function() return InteractEditWindow[0] and interact_edit_index ~= nil end, function()
    if not interact_edit_index or not settings.interactions[interact_edit_index] then InteractEditWindow[0]=false; interact_edit_index=nil; return end
    local inter = settings.interactions[interact_edit_index]; local d = settings.general.custom_dpi
    imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(480*d, 350*d), imgui.Cond.FirstUseEver)
    imgui.Begin(safe_u8(' \xd8\xe0\xe3: '..(inter.name or'')), InteractEditWindow, imgui.WindowFlags.NoCollapse+imgui.WindowFlags.NoResize)
    change_dpi()
    imgui.Text(u8'\xcd\xe0\xe7\xe2\xe0\xed\xe8\xe5:'); local inn=imgui.new.char[256](safe_u8(inter.name)); imgui.PushItemWidth(-1)
    if imgui.InputText('##ien',inn,256) then inter.name=u8:decode(ffi.string(inn)); save_settings() end
    imgui.Text(u8'\xc7\xe0\xe4\xe5\xf0\xe6\xea\xe0 (\xf1):'); local sl=imgui.new.float(inter.waiting or 1.5); imgui.PushItemWidth(-1)
    if imgui.SliderFloat('##iew',sl,0.5,10) then inter.waiting=sl[0]; save_settings() end
    imgui.Separator(); imgui.Text(u8'\xd1\xf2\xf0\xee\xea\xe8:')
    if imgui.BeginChild('##iel', imgui.ImVec2(-1, 140*d), true) then
        local rm=nil
        for li, line in ipairs(inter.lines or{}) do
            local inp=imgui.new.char[512](safe_u8(line)); imgui.PushItemWidth(370*d)
            if imgui.InputText('##il'..li,inp,512) then inter.lines[li]=u8:decode(ffi.string(inp)); save_settings() end
            imgui.SameLine(); if imgui.SmallButton('X##ild'..li) then rm=li end
        end
        if rm then table.remove(inter.lines, rm); save_settings() end
        imgui.EndChild()
    end
    if imgui.Button(u8' + \xd1\xf2\xf0\xee\xea\xe0', imgui.ImVec2(imgui.GetMiddleButtonX(2),0)) then table.insert(inter.lines,'\xd2\xe5\xea\xf1\xf2'); save_settings() end
    imgui.SameLine()
    if imgui.Button(u8' \xd3\xe4\xe0\xeb\xe8\xf2\xfc', imgui.ImVec2(imgui.GetMiddleButtonX(2),0)) then
        table.remove(settings.interactions, interact_edit_index); save_settings(); InteractEditWindow[0]=false; interact_edit_index=nil
    end
    imgui.End()
end)

-- ========== \xd0\xc5\xc4\xc0\xca\xd2\xce\xd0 \xcf\xc8\xc0\xd0\xc0 ==========
imgui.OnFrame(function() return PiarEditWindow[0] and piar_edit_index ~= nil end, function()
    if not piar_edit_index or not settings.piar_templates[piar_edit_index] then PiarEditWindow[0]=false; piar_edit_index=nil; return end
    local t = settings.piar_templates[piar_edit_index]; local d = settings.general.custom_dpi
    imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(500*d, 380*d), imgui.Cond.FirstUseEver)
    imgui.Begin(safe_u8(' \xcf\xe8\xe0\xf0: '..(t.name or'')), PiarEditWindow, imgui.WindowFlags.NoCollapse+imgui.WindowFlags.NoResize)
    change_dpi()
    imgui.Text(u8'\xcd\xe0\xe7\xe2\xe0\xed\xe8\xe5:'); local pn=imgui.new.char[256](safe_u8(t.name)); imgui.PushItemWidth(-1)
    if imgui.InputText('##pn',pn,256) then t.name=u8:decode(ffi.string(pn)); save_settings() end
    imgui.Text(u8'\xc7\xe0\xe4\xe5\xf0\xe6\xea\xe0:'); local pw=imgui.new.float(t.waiting or 1.5); imgui.PushItemWidth(-1)
    if imgui.SliderFloat('##pw',pw,0.5,10) then t.waiting=pw[0]; save_settings() end
    imgui.Text(u8'\xc0\xe2\xf2\xee-\xe8\xed\xf2\xe5\xf0\xe2\xe0\xeb \xec\xe8\xed:')
    local pi=imgui.new.int(t.auto_interval or 300); imgui.PushItemWidth(-1)
    if imgui.SliderInt('##pi',pi,30,3600) then t.auto_interval=pi[0]; if (t.auto_interval_max or 0) < pi[0] then t.auto_interval_max=pi[0] end; save_settings() end
    imgui.Text(u8'\xc0\xe2\xf2\xee-\xe8\xed\xf2\xe5\xf0\xe2\xe0\xeb \xec\xe0\xea\xf1 (0=\xed\xe5\xf2 \xf0\xe0\xed\xe4\xee\xec\xe0):')
    local pm=imgui.new.int(t.auto_interval_max or 0); imgui.PushItemWidth(-1)
    if imgui.SliderInt('##pm',pm,0,3600) then t.auto_interval_max=pm[0]; save_settings() end
    imgui.Separator()
    if imgui.BeginChild('##pl', imgui.ImVec2(-1, 120*d), true) then
        local rm=nil
        for li, line in ipairs(t.lines or{}) do
            local inp=imgui.new.char[512](safe_u8(line)); imgui.PushItemWidth(390*d)
            if imgui.InputText('##pli'..li,inp,512) then t.lines[li]=u8:decode(ffi.string(inp)); save_settings() end
            imgui.SameLine(); if imgui.SmallButton('X##pld'..li) then rm=li end
        end
        if rm then table.remove(t.lines, rm); save_settings() end
        imgui.EndChild()
    end
    if imgui.Button(u8' + \xd1\xf2\xf0\xee\xea\xe0', imgui.ImVec2(imgui.GetMiddleButtonX(2),0)) then table.insert(t.lines,'/s \xd2\xe5\xea\xf1\xf2'); save_settings() end
    imgui.SameLine()
    if imgui.Button(u8' \xd3\xe4\xe0\xeb\xe8\xf2\xfc', imgui.ImVec2(imgui.GetMiddleButtonX(2),0)) then
        table.remove(settings.piar_templates, piar_edit_index); save_settings(); PiarEditWindow[0]=false; piar_edit_index=nil
    end
    imgui.End()
end)

-- ========== \xc1\xdb\xd1\xd2\xd0\xce\xc5 \xcc\xc5\xcd\xde ==========
imgui.OnFrame(function() return FastMenu[0] end, function()
    if not player_id or not sampIsPlayerConnected(player_id) then FastMenu[0]=false; return end
    local d = settings.general.custom_dpi
    imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.Begin(' '..(sampGetPlayerNickname(player_id) or'???')..' ['..player_id..']##FM', FastMenu, imgui.WindowFlags.NoCollapse+imgui.WindowFlags.NoResize+imgui.WindowFlags.AlwaysAutoResize)
    change_dpi()
    for _, c in ipairs(settings.commands) do
        if c.enable and not c.deleted and c.arg == '{arg_id}' then
            if imgui.Button(safe_u8(c.description), imgui.ImVec2(250*d, 26*d)) then
                sampProcessChatInput("/"..(c.cmd or'').." "..player_id); FastMenu[0]=false
            end
        end
    end
    imgui.Separator()
    if imgui.Button(u8' \xc2\xe5\xf0\xe1\xee\xe2\xea\xe0', imgui.ImVec2(-1, 0)) then interact_player_id=player_id; InteractMenu[0]=true; FastMenu[0]=false end
    imgui.End()
end)

-- ========== \xd1\xd2\xce\xcf / \xcf\xc0\xd3\xc7\xc0 ==========
imgui.OnFrame(function() return CommandStopWindow[0] end, function()
    local d=settings.general.custom_dpi
    imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY-50*d), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5,0.5))
    imgui.Begin("##stop",_,imgui.WindowFlags.NoCollapse+imgui.WindowFlags.NoResize+imgui.WindowFlags.AlwaysAutoResize+imgui.WindowFlags.NoTitleBar)
    change_dpi()
    if isActiveCommand then
        if imgui.Button(u8' \xd1\xf2\xee\xef') then command_stop=true; CommandStopWindow[0]=false end
    else CommandStopWindow[0]=false end
    imgui.End()
end)

imgui.OnFrame(function() return CommandPauseWindow[0] end, function()
    local d=settings.general.custom_dpi
    imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY-50*d), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5,0.5))
    imgui.Begin("##pause",_,imgui.WindowFlags.NoCollapse+imgui.WindowFlags.NoResize+imgui.WindowFlags.AlwaysAutoResize+imgui.WindowFlags.NoTitleBar)
    change_dpi()
    if command_pause then
        if imgui.Button(u8' \xc4\xe0\xeb\xe5\xe5', imgui.ImVec2(120*d,0)) then command_pause=false; CommandPauseWindow[0]=false end
        imgui.SameLine()
        if imgui.Button(u8' \xd1\xf2\xee\xef', imgui.ImVec2(120*d,0)) then command_stop=true; command_pause=false; CommandPauseWindow[0]=false end
    else CommandPauseWindow[0]=false end
    imgui.End()
end)

-- ========== \xc7\xc0\xcc\xc5\xd2\xca\xc8 ==========
imgui.OnFrame(function() return NoteWindow[0] end, function()
    imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.Begin(' '..(show_note_name or''), NoteWindow, imgui.WindowFlags.AlwaysAutoResize)
    change_dpi(); imgui.Text((show_note_text or''):gsub('&','\n')); imgui.Separator()
    if imgui.Button(u8' \xc7\xe0\xea\xf0\xfb\xf2\xfc', imgui.ImVec2(-1, 0)) then NoteWindow[0]=false end
    imgui.End()
end)

-- ========== \xc1\xc8\xcd\xc4\xc5\xd0 ==========
imgui.OnFrame(function() return BinderWindow[0] end, function()
    local d=settings.general.custom_dpi
    imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(560*d, 380*d), imgui.Cond.FirstUseEver)
    imgui.Begin(u8' \xd0\xe5\xe4\xe0\xea\xf2\xee\xf0 \xea\xee\xec\xe0\xed\xe4\xfb', BinderWindow, imgui.WindowFlags.NoCollapse+imgui.WindowFlags.NoResize)
    change_dpi()
    if imgui.BeginChild('##be', imgui.ImVec2(549*d, 300*d), true) then
        imgui.CenterText(u8'\xce\xef\xe8\xf1\xe0\xed\xe8\xe5:'); imgui.PushItemWidth(-1); imgui.InputText("##bd",input_description,256)
        imgui.Separator()
        imgui.CenterText(u8'\xca\xee\xec\xe0\xed\xe4\xe0 (\xe1\xe5\xe7 /):'); imgui.PushItemWidth(-1); imgui.InputText("##bc",input_cmd,256)
        imgui.Separator()
        imgui.CenterText(u8'\xc0\xf0\xe3\xf3\xec\xe5\xed\xf2\xfb:'); imgui.Combo('##ba',ComboTags,ImItems,#item_list)
        imgui.Separator()
        imgui.CenterText(u8'\xd2\xe5\xea\xf1\xf2 (& = \xf1\xf2\xf0\xee\xea\xe0):')
        imgui.InputTextMultiline("##bt",input_text,8192,imgui.ImVec2(-1,100*d))
        imgui.EndChild()
    end
    imgui.Text(u8'\xc7\xe0\xe4\xe5\xf0\xe6\xea\xe0:'); imgui.SameLine(); imgui.PushItemWidth(180*d); imgui.SliderFloat('##bw',waiting_slider,0.5,5)
    if imgui.Button(u8' \xce\xf2\xec\xe5\xed\xe0', imgui.ImVec2(imgui.GetMiddleButtonX(2),0)) then BinderWindow[0]=false end
    imgui.SameLine()
    if imgui.Button(u8' \xd1\xee\xf5\xf0\xe0\xed\xe8\xf2\xfc', imgui.ImVec2(imgui.GetMiddleButtonX(2),0)) then
        local nc=ffi.string(input_cmd); local nt=ffi.string(input_text)
        if nc~='' and nt~='' then
            local na=({'','{arg}','{arg_id}','{arg_id} {arg2}'})[ComboTags[0]+1] or''
            for _, c in ipairs(settings.commands) do
                if c.cmd==change_cmd and c.description==change_description then
                    pcall(sampUnregisterChatCommand, c.cmd)
                    c.cmd=u8:decode(nc); c.arg=na; c.description=u8:decode(ffi.string(input_description))
                    c.text=u8:decode(nt):gsub('\n','&'); c.waiting=tostring(waiting_slider[0])
                    c.enable=true; c.deleted=false; save_settings()
                    reg_cmd(c.cmd, c.arg, c.text, tonumber(c.waiting)); break
                end
            end
            BinderWindow[0]=false
        end
    end
    imgui.End()
end)

----------------------------------------------- HELPERS -------------------------------------------
function imgui.CenterText(t)
    t=t or''; local w=imgui.GetWindowWidth(); imgui.SetCursorPosX(w/2-imgui.CalcTextSize(t).x/2); imgui.Text(t)
end
function imgui.CenterColumnText(t)
    t=t or''; imgui.SetCursorPosX((imgui.GetColumnOffset()+(imgui.GetColumnWidth()/2))-imgui.CalcTextSize(t).x/2); imgui.Text(t)
end
function imgui.CenterColumnTextDisabled(t)
    t=t or''; imgui.SetCursorPosX((imgui.GetColumnOffset()+(imgui.GetColumnWidth()/2))-imgui.CalcTextSize(t).x/2); imgui.TextDisabled(t)
end
function imgui.CenterColumnSmallButton(t)
    local d=(t or''):match('(.+)##') or t or''; imgui.SetCursorPosX((imgui.GetColumnOffset()+(imgui.GetColumnWidth()/2))-imgui.CalcTextSize(d).x/2); return imgui.SmallButton(t or'')
end
function imgui.GetMiddleButtonX(c)
    local w=imgui.GetWindowContentRegionWidth(); local s=imgui.GetStyle().ItemSpacing.x; return c==1 and w or w/c-((s*(c-1))/c)
end

----------------------------------------------- THEME ---------------------------------------------------
function apply_theme()
    imgui.SwitchContext()
    local s=imgui.GetStyle(); local d=settings.general.custom_dpi
    local bg=settings.interface.bg_brightness or 0.13
    local wa=settings.interface.window_alpha or 0.97
    local ar=settings.interface.accent_r or 1; local ag=settings.interface.accent_g or .65; local ab=settings.interface.accent_b or 0
    s.WindowPadding=imgui.ImVec2(5*d,5*d); s.FramePadding=imgui.ImVec2(5*d,5*d)
    s.ItemSpacing=imgui.ImVec2(5*d,5*d); s.ItemInnerSpacing=imgui.ImVec2(2*d,2*d)
    s.ScrollbarSize=15*d; s.GrabMinSize=15*d
    s.WindowBorderSize=1*d; s.ChildBorderSize=1*d; s.PopupBorderSize=1*d; s.FrameBorderSize=1*d; s.TabBorderSize=1*d
    s.WindowRounding=8*d; s.ChildRounding=8*d; s.FrameRounding=8*d; s.PopupRounding=8*d
    s.ScrollbarRounding=6*d; s.GrabRounding=6*d; s.TabRounding=8*d
    s.WindowTitleAlign=imgui.ImVec2(.5,.5); s.ButtonTextAlign=imgui.ImVec2(.5,.5); s.SelectableTextAlign=imgui.ImVec2(.5,.5)
    s.Colors[imgui.Col.Text]=imgui.ImVec4(.92,.92,.92,1)
    s.Colors[imgui.Col.TextDisabled]=imgui.ImVec4(.55,.55,.55,1)
    s.Colors[imgui.Col.WindowBg]=imgui.ImVec4(bg,bg,bg+.01,wa)
    s.Colors[imgui.Col.ChildBg]=imgui.ImVec4(bg+.02,bg+.02,bg+.03,wa)
    s.Colors[imgui.Col.PopupBg]=imgui.ImVec4(bg+.01,bg+.01,bg+.02,wa)
    s.Colors[imgui.Col.Border]=imgui.ImVec4(bg+.17,bg+.17,bg+.19,.65)
    s.Colors[imgui.Col.BorderShadow]=imgui.ImVec4(0,0,0,0)
    s.Colors[imgui.Col.FrameBg]=imgui.ImVec4(bg+.05,bg+.05,bg+.07,1)
    s.Colors[imgui.Col.FrameBgHovered]=imgui.ImVec4(bg+.13,bg+.13,bg+.15,1)
    s.Colors[imgui.Col.FrameBgActive]=imgui.ImVec4(bg+.17,bg+.17,bg+.20,1)
    s.Colors[imgui.Col.TitleBg]=imgui.ImVec4(bg-.01,bg-.01,bg,1)
    s.Colors[imgui.Col.TitleBgActive]=imgui.ImVec4(ar*.25,ag*.25,ab*.25,1)
    s.Colors[imgui.Col.TitleBgCollapsed]=imgui.ImVec4(bg-.01,bg-.01,bg,1)
    s.Colors[imgui.Col.MenuBarBg]=imgui.ImVec4(bg+.03,bg+.03,bg+.05,1)
    s.Colors[imgui.Col.ScrollbarBg]=imgui.ImVec4(bg+.01,bg+.01,bg+.02,1)
    s.Colors[imgui.Col.ScrollbarGrab]=imgui.ImVec4(bg+.15,bg+.15,bg+.17,1)
    s.Colors[imgui.Col.ScrollbarGrabHovered]=imgui.ImVec4(bg+.25,bg+.25,bg+.27,1)
    s.Colors[imgui.Col.ScrollbarGrabActive]=imgui.ImVec4(bg+.35,bg+.35,bg+.37,1)
    s.Colors[imgui.Col.CheckMark]=imgui.ImVec4(ar,ag,ab,1)
    s.Colors[imgui.Col.SliderGrab]=imgui.ImVec4(ar*.5,ag*.5,ab*.5,1)
    s.Colors[imgui.Col.SliderGrabActive]=imgui.ImVec4(ar*.7,ag*.7,ab*.7,1)
    s.Colors[imgui.Col.Button]=imgui.ImVec4(bg+.07,bg+.07,bg+.09,1)
    s.Colors[imgui.Col.ButtonHovered]=imgui.ImVec4(ar*.35,ag*.35,ab*.35,1)
    s.Colors[imgui.Col.ButtonActive]=imgui.ImVec4(ar*.5,ag*.5,ab*.5,1)
    s.Colors[imgui.Col.Header]=imgui.ImVec4(ar*.2,ag*.2,ab*.2,1)
    s.Colors[imgui.Col.HeaderHovered]=imgui.ImVec4(ar*.35,ag*.35,ab*.35,1)
    s.Colors[imgui.Col.HeaderActive]=imgui.ImVec4(ar*.5,ag*.5,ab*.5,1)
    s.Colors[imgui.Col.Separator]=imgui.ImVec4(bg+.12,bg+.12,bg+.14,1)
    s.Colors[imgui.Col.Tab]=imgui.ImVec4(bg+.03,bg+.03,bg+.05,1)
    s.Colors[imgui.Col.TabHovered]=imgui.ImVec4(ar*.4,ag*.4,ab*.4,1)
    s.Colors[imgui.Col.TabActive]=imgui.ImVec4(ar*.3,ag*.3,ab*.3,1)
    s.Colors[imgui.Col.ModalWindowDimBg]=imgui.ImVec4(.1,.1,.1,.85)
end

function onScriptTerminate(s, q)
    if s==thisScript() then
        save_log()
        save_settings()
        if not q and not reload_script then
            sampAddChatMessage('[Family Helper] {ffffff}\xd5\xe5\xeb\xef\xe5\xf0 \xee\xf1\xf2\xe0\xed\xee\xe2\xeb\xe5\xed!', message_color)
        end
    end
end
