-- Whisper push-to-talk (toggle mode).
-- Paste this into ~/.hammerspoon/init.lua and reload Hammerspoon.
--
-- Two hotkeys, both toggle the same recorder:
--   Ctrl+Alt+Space        -> transcribe, paste, auto-press Return (send)
--   Ctrl+Alt+Shift+Space  -> transcribe, paste only (no Return)
--
-- The two hotkeys share state, so you can start with one and stop with the
-- other. Whichever key you *stop* with decides whether Return is sent — handy
-- when you change your mind mid-dictation.

local WHISPER_SCRIPT = os.getenv("HOME") .. "/personal/whisper/toggle.sh"

local menubar = hs.menubar.new()
menubar:setTitle("")

local function trigger(autoSend, lang)
    return function()
        local args = {WHISPER_SCRIPT}
        if lang then
            table.insert(args, "-l")
            table.insert(args, lang)
        end

        hs.task.new("/bin/bash", function(exitCode, stdout, stderr)
            stdout = stdout or ""
            stderr = stderr or ""

            if exitCode ~= 0 then
                menubar:setTitle("")
                hs.alert.show("Whisper error: " .. stderr)
                return
            end

            local suffix = lang and (" [" .. lang .. "]") or ""
            if stdout:find("RECORDING") then
                menubar:setTitle(autoSend and ("● REC" .. suffix) or ("● REC (paste)" .. suffix))
            elseif stdout:find("PASTE") then
                menubar:setTitle("")
                hs.eventtap.keyStroke({"cmd"}, "v", 0)
                if autoSend then
                    hs.timer.doAfter(0.05, function()
                        hs.eventtap.keyStroke({}, "return", 0)
                    end)
                end
            elseif stdout:find("EMPTY") then
                menubar:setTitle("")
                hs.alert.show("Whisper: no speech detected")
            end
        end, args):start()
    end
end

-- English (translate any language to English)
hs.hotkey.bind({"ctrl", "alt"},          "space", trigger(true))
hs.hotkey.bind({"ctrl", "alt", "shift"}, "space", trigger(false))
-- Spanish (transcribe in Spanish)
hs.hotkey.bind({"ctrl", "alt"},          "e", trigger(true, "es"))
hs.hotkey.bind({"ctrl", "alt", "shift"}, "e", trigger(false, "es"))
