local registered = {}
local displayed = {}
local private = {}
local chatFrame = {
    AddMessage = function(_, text) displayed[#displayed + 1] = text end,
}
local addon = {}
ChatFrameUtil = { AddMessageEventFilter = function(event, filter) registered[event] = filter end }
C_Timer = { After = function(_, callback) callback() end }
SlashCmdList = {}
DEFAULT_CHAT_FRAME = chatFrame
issecretvalue = function(value) return value == private end

assert(loadfile("addon/Konglish/Glossary.lua"))("Konglish", addon)
assert(loadfile("addon/Konglish/Konglish.lua"))("Konglish", addon)

assert(SLASH_KONGLISH1 == "/konglish")
assert(not registered.CHAT_MSG_WHISPER and not registered.CHAT_MSG_GUILD)
assert(registered.CHAT_MSG_INSTANCE_CHAT_LEADER)
local party = assert(registered.CHAT_MSG_PARTY)
assert(party(chatFrame, "CHAT_MSG_PARTY", " OOM! ") == nil)
assert(displayed[1]:find("마나 다 썼어요.", 1, true))
party(chatFrame, "CHAT_MSG_PARTY", private)
party(chatFrame, "CHAT_MSG_PARTY", "A full sentence with no matching glossary entry.")
assert(#displayed == 1)
SlashCmdList.KONGLISH()
assert(KonglishSettings.enabled == false)
party(chatFrame, "CHAT_MSG_PARTY", "oom")
assert(#displayed == 2)
SlashCmdList.KONGLISH()
party(chatFrame, "CHAT_MSG_PARTY", "ready?")
assert(displayed[4]:find("준비됐나요?", 1, true))
print("Konglish addon checks passed")
