local addonName, ns = ...

local C = {}
ns.Constants = C

C.ADDON_TITLE = "MyChat"
C.VERSION = "0.1.1"

-- Bus topics: modules communicate only through these named channels.
C.TOPIC = {
  MESSAGE_RAW = "message.raw",
  MESSAGE_NORMALIZED = "message.normalized",
  COMBAT_ENTER = "combat.enter",
  COMBAT_LEAVE = "combat.leave",
  PLAYER_LOGIN = "lifecycle.login",
  ENTERING_WORLD = "lifecycle.entering_world",
}

-- Chat events forwarded to the bus as raw messages.
C.CHAT_EVENTS = {
  "CHAT_MSG_CHANNEL",
  "CHAT_MSG_WHISPER",
  "CHAT_MSG_WHISPER_INFORM",
  "CHAT_MSG_GUILD",
  "CHAT_MSG_PARTY",
  "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID",
  "CHAT_MSG_RAID_LEADER",
  "CHAT_MSG_INSTANCE_CHAT",
  "CHAT_MSG_INSTANCE_CHAT_LEADER",
  "CHAT_MSG_SYSTEM",
}

-- Lifecycle / combat events handled directly by Events.
C.LIFECYCLE_EVENTS = {
  "PLAYER_LOGIN",
  "PLAYER_ENTERING_WORLD",
  "PLAYER_REGEN_DISABLED",
  "PLAYER_REGEN_ENABLED",
}

-- messageClass values produced by the Parser.
C.CLASS = {
  WHISPER = "whisper",
  GUILD = "guild",
  PARTY = "party",
  RAID = "raid",
  INSTANCE = "instance",
  TRADE = "trade",
  WORLD = "world",
  CHANNEL = "channel",
  SYSTEM = "system",
}

-- Short labels for channel display (T05 uses these).
C.CHANNEL_ABBREV = {
  [C.CLASS.WHISPER] = "密",
  [C.CLASS.GUILD] = "会",
  [C.CLASS.PARTY] = "队",
  [C.CLASS.RAID] = "团",
  [C.CLASS.INSTANCE] = "本",
  [C.CLASS.TRADE] = "交易",
  [C.CLASS.WORLD] = "世界",
  [C.CLASS.CHANNEL] = "频道",
  [C.CLASS.SYSTEM] = "系统",
}

-- Fallback author color when class color is unavailable.
C.DEFAULT_AUTHOR_COLOR = "ffffffff"

-- Tunables (named to avoid magic numbers elsewhere).
C.WHISPER_HISTORY_LIMIT = 10
C.DUPLICATE_WINDOW_SECONDS = 8
C.CHANNEL_JOIN_RETRY_LIMIT = 5
C.CHANNEL_JOIN_RETRY_INTERVAL = 3
C.ERROR_DEGRADE_THRESHOLD = 25
