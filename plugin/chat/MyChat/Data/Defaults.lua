local addonName, ns = ...

-- Default database shape, aligned with execution plan §7.
-- profile: user-tunable settings (reset by /mychat reset).
-- runtime: transient/session state (preserved across reset).
--
-- Design rule: every key here MUST be read by some module. We do not keep
-- "decorative" toggles for things 12.0 already does natively (timestamps,
-- class-colored names) — those were removed because faking them either
-- duplicated native output or corrupted chat hyperlinks.
ns.Defaults = {
  profile = {
    -- 频道：自动加入的频道名列表（可在设置面板增删）。
    autoJoinChannels = { "大脚世界频道" },

    -- 频道切换条外观与行为。
    channelBarEnabled = false,
    channelBarShowSay = true,     -- 显示"说"按钮
    channelBarShowParty = true,   -- 显示"队"按钮（仅在组队时可用）
    channelBarShowRaid = true,    -- 显示"团"按钮（仅在团队时可用）
    channelBarShowGuild = true,   -- 显示"会"按钮（仅在公会时可用）
    channelBarShowNumber = false, -- 频道按钮是否带编号前缀（如 6大脚）
    abbreviateChannels = true,    -- 频道按钮是否用短名（截取前几个字）
    channelBarAbbrevChars = 2,    -- 短名取前几个字符（最小 1）
    -- 频道短名自定义映射：频道名（可含子串）-> 显示名。命中时优先于自动截取。
    -- 例：{ ["大脚世界频道"] = "大脚", ["交易"] = "商" }
    channelAbbrevMap = {},

    -- 高亮与关键词。
    highlightKeywords = { "来T", "来奶", "集合" },
    highlightSelfName = true,

    -- 重复折叠。
    enableRepeatCollapse = true,
    dupWindowSeconds = 8,         -- 重复判定的时间窗口（秒）

    -- 密语索引。
    enableWhisperIndex = true,
    whisperHistoryLimit = 10,     -- 记住最近多少个密语对象

    -- 镜像面板。
    mirrorPanelEnabled = false,
    mirrorSystemMessages = false, -- 是否镜像系统消息（默认关，避免噪音刷屏）
    mirrorMaxLines = 100,         -- 镜像面板最多保留多少行
    routeWorldTradeParty = true,  -- 镜像面板按频道分色（世界/交易/队伍等）

    -- 安全模式：仅保留只读增强（高亮/折叠/镜像），关闭一切"会主动操作游戏"
    -- 的功能（自动加入频道、密语发送）。出问题时用来快速隔离。
    safeMode = false,
  },
  runtime = {
    lastWhisperTargets = {},
    joinedChannels = {},
  },
}
