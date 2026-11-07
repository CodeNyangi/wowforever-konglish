local _, Konglish = ...
local label = "|cff66d6b7[Konglish]|r "

local function ShowGloss(frame, _, message)
    if KonglishSettings and KonglishSettings.enabled == false then return end
    if issecretvalue and issecretvalue(message) then return end
    if type(message) ~= "string" then return end

    local key = message:lower():match("^%s*(.-)%s*$"):gsub("%s+", " "):gsub("[.!]+$", "")
    local gloss = Konglish.glossary[key]
    if gloss then
        C_Timer.After(0, function()
            frame:AddMessage(label .. gloss)
        end)
    end
end

for _, event in ipairs({
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
}) do
    ChatFrameUtil.AddMessageEventFilter(event, ShowGloss)
end

SLASH_KONGLISH1 = "/konglish"
SlashCmdList.KONGLISH = function()
    KonglishSettings = KonglishSettings or {}
    KonglishSettings.enabled = KonglishSettings.enabled == false
    DEFAULT_CHAT_FRAME:AddMessage(label .. (KonglishSettings.enabled and "약어 풀이 켜짐" or "약어 풀이 꺼짐"))
end
