--[[
2-kosync-cancel-v5.lua  (version 5)
User patch for KOReader's "Progress sync" plugin (KOSync). Tested on KOReader v2026.07.2.

Goal: opening a book (or waking the device) must never be blocked by Wi-Fi,
and no reading position must ever be lost while offline.

1. SHORT PAUSE: if you wake the reader less than 5 minutes after putting it to
   sleep, the progress is not pulled from the server: you go straight back to reading.
2. "TAP TO CANCEL": whenever the plugin would turn Wi-Fi on to pull your progress
   (opening a book, waking up after a longer pause), it first shows this message
   for 3 seconds:
   "Syncing reading progress…\nTap to cancel."
   - Don't touch anything -> it syncs as usual.
   - Tap -> sync is cancelled: you are back to reading at once, no Wi-Fi, no download.
3. SLEEP: unchanged. When you put the reader to sleep it still tries to connect and
   push your progress; if there is no network it turns Wi-Fi off.
4. OFFLINE QUEUE (new in v5): books closed while offline (for example one you finish
   on the go before starting the next) are queued by KOSync. The plugin used to
   throw the queue away even when sending it failed, so the finished book never
   reached the server. Now, for each queued book, the server's position is read
   first: if the server is further on (or newer), e.g. because you finished the book
   on another device, the queued position is dropped; otherwise it is sent. An entry
   leaves the queue only after one of these, and the queue is handled before the
   position of the open book, i.e. before Wi-Fi is turned off again on sleep.

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
    local orig_updateProgress = KOSync.updateProgress

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

    -- Send the offline queue. Replaces KOSync:drainQueue, which judged success with
    -- pcall(client.update_progress): that never fails (KOSyncClient catches every
    -- error and reports it through the callback), so the queue was emptied even when
    -- nothing had been sent. Here an entry leaves the queue only once the server has
    -- accepted it, or once the server turned out to be ahead of it.
    KOSync.drainQueue = function(self)
        if not self.settings.username or not self.settings.userkey then return end
        local KOSyncQueue = require("KOSyncQueue")
        local queue = KOSyncQueue:load()
        if #queue == 0 then return end

        local KOSyncClient = require("KOSyncClient")
        local function newClient()
            return KOSyncClient:new{
                custom_url = self.settings.custom_server,
                service_spec = self.path .. "/api.json"
            }
        end
        -- The open book is not sent from the queue: its live position is pushed by
        -- the plugin itself (on sleep, on close, every few pages).
        local current = self.ui and self.ui.document and self:getDocumentDigest()
        local remaining = {}
        local sent, skipped = 0, 0
        for i, item in ipairs(queue) do
            -- Without the Turbo looper (the default) requests are synchronous and the
            -- callback has run by the time the call returns. If it has not, the entry
            -- is simply kept and handled again next time.
            local done = item.document == current
            if not done then
                -- Ask the server first: the book may have been read further, or more
                -- recently, on another device (e.g. finished there while offline too).
                local reached, server = false, nil
                local client = newClient()
                pcall(client.get_progress, client,
                    self.settings.username, self.settings.userkey, item.document,
                    function(ok, body)
                        reached = ok
                        server = type(body) == "table" and body or nil
                    end)
                if reached and server and tonumber(server.percentage) then
                    -- The server's timestamp is when it received the position, so a
                    -- timestamp older than our entry means the server copy is older.
                    -- Otherwise keep whichever is further into the book.
                    local server_older = (tonumber(server.timestamp) or 0) < (item.queued_at or 0)
                    if not server_older and tonumber(server.percentage) >= (item.percentage or 0) then
                        logger.info("KOSync cancel: server is ahead for", item.document,
                            server.percentage, ">=", item.percentage, "- queued position dropped")
                        skipped = skipped + 1
                        done = true
                    end
                end
                if reached and not done then
                    client = newClient()
                    pcall(client.update_progress, client,
                        self.settings.username, self.settings.userkey,
                        item.document, item.metadata, item.progress, item.percentage,
                        item.device, item.device_id,
                        function(ok) done = ok end)
                    if done then sent = sent + 1 end
                end
            end
            if not done then
                -- Server not reachable: keep this entry and the following ones
                for j = i, #queue do
                    table.insert(remaining, queue[j])
                end
                break
            end
        end
        KOSyncQueue:save(remaining)
        logger.info("KOSync cancel: queue sent", sent, "dropped", skipped, "kept", #remaining)
    end

    -- Every push of the open book first sends the queue, while the network is up.
    -- On sleep the push is followed by Wi-Fi being turned off, so the plugin's own
    -- drain (scheduled 0.5 s after "network connected") would run with no network.
    KOSync.updateProgress = function(self, ...)
        if NetworkMgr:isOnline() then
            self:drainQueue()
        end
        return orig_updateProgress(self, ...)
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
