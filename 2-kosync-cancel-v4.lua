--[[
2-kosync-cancel-v4.lua  (version 4)
User patch for KOReader's "Progress sync" plugin (KOSync). Tested on KOReader v2026.07.2.

Goal: opening a book (or waking the device) must never be blocked by Wi-Fi.

1. SHORT PAUSE: if you wake the reader less than 5 minutes after putting it to
   sleep, the progress is not pulled from the server: you go straight back to reading.
2. "TAP TO CANCEL": whenever the plugin would turn Wi-Fi on to pull your progress
   (opening a book, waking up after a longer pause), it first shows this message
   for 3 seconds:
   "Syncing reading progress… Tap to cancel."
   - Don't touch anything -> it syncs as usual.
   - Tap -> sync is cancelled: you are back to reading at once, no Wi-Fi, no download.
3. SLEEP: unchanged. When you put the reader to sleep it still tries to connect and
   push your progress; if there is no network it turns Wi-Fi off and the progress
   stays queued (it is sent automatically on the next successful connection).

Requirements: Network -> "Action when Wi-Fi is off" = Turn on,
              Progress sync -> "Auto sync" enabled.
To remove it: delete this file and restart KOReader.
]]

local userpatch = require("userpatch")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local logger = require("logger")

-- Settings you can change
local SHORT_PAUSE = 5 * 60 -- seconds: wake up within this time -> no download
local WAIT = 3             -- seconds the message stays on screen (time to tap)
local MESSAGE = "Syncing reading progress…\nTap to cancel." -- translate if you like

-- Shared across books (the plugin is re-created every time a book is opened)
local slept_at = nil

userpatch.registerPatchPluginFunc("kosync", function(KOSync)
    if KOSync._cancel_patched then return end
    KOSync._cancel_patched = true

    local orig_onSuspend = KOSync._onSuspend
    local orig_onResume = KOSync._onResume
    local orig_getProgress = KOSync.getProgress

    -- Automatic progress pull: if Wi-Fi would have to be turned on, ask first.
    -- (ensure_networking = true and interactive = false: opening a book, waking up.
    --  The manual "Pull progress" commands are interactive and are left untouched.)
    KOSync.getProgress = function(self, ensure_networking, interactive, ...)
        if not ensure_networking or interactive
                or NetworkMgr:isOnline()
                or not self.settings.username or not self.settings.userkey then
            return orig_getProgress(self, ensure_networking, interactive, ...)
        end
        if self._cancel_prompt_open then return end
        self._cancel_prompt_open = true

        local args = { ... }
        local cancelled = false
        local msg = InfoMessage:new{
            text = MESSAGE,
            timeout = WAIT,
        }
        msg.onTapClose = function(widget)
            cancelled = true
            UIManager:close(widget)
            return true
        end
        msg.onAnyKeyPressed = msg.onTapClose
        msg.dismiss_callback = function()
            self._cancel_prompt_open = nil
            if cancelled then
                logger.info("KOSync cancel: sync cancelled by the user")
                return
            end
            -- Do NOT connect from inside this callback: the message is still being torn
            -- down, and connecting repaints the screen (crash on a freed widget).
            -- Defer until the close has completed.
            UIManager:scheduleIn(0.5, function()
                -- The book may have been closed in the meantime
                if not self.ui or not self.ui.document then return end
                logger.info("KOSync cancel: no tap, syncing")
                orig_getProgress(self, ensure_networking, interactive, unpack(args))
            end)
        end
        UIManager:show(msg)
    end

    KOSync._onSuspend = function(self, ...)
        slept_at = os.time()
        return orig_onSuspend(self, ...) -- push on sleep: original behaviour
    end

    KOSync._onResume = function(self, ...)
        if slept_at and os.time() - slept_at < SHORT_PAUSE then
            logger.info("KOSync cancel: woke up after", os.time() - slept_at, "s, no download")
            return
        end
        return orig_onResume(self, ...) -- the pull goes through getProgress, which asks first
    end

    logger.info("KOSync cancel: patch applied")
end)
