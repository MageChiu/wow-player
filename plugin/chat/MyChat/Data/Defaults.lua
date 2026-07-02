local addonName, ns = ...

-- Default database shape, aligned with execution plan §7.
-- profile: user-tunable settings (reset by /mychat reset).
-- runtime: transient/session state (preserved across reset).
ns.Defaults = {
  profile = {
    autoJoinChannels = { "世界频道" },
    restoreCustomChannels = true,
    showTimestamps = true,
    abbreviateChannels = true,
    colorPlayerNamesByClass = true,
    highlightKeywords = { "来T", "来奶", "集合" },
    highlightSelfName = true,
    enableWhisperIndex = true,
    enableRepeatCollapse = true,
    routeWorldTradeParty = true,
    mirrorPanelEnabled = false,
    channelBarEnabled = false,
    safeMode = true,
  },
  runtime = {
    lastWhisperTargets = {},
    joinedChannels = {},
  },
}
