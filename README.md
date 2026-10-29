# KOReader "tap to cancel" patch for progress sync

This repository contains:

- `2-kosync-cancel-v5.lua`: the patch itself.
- `README.md`: this file. It explains what the patch does and how to install it. At the end there is a section for Claude or another AI assistant.
- `LICENSE`: AGPL-3.0, the same licence as KOReader.

---

## 1. The problem it solves

In KOReader, with **automatic progress sync** enabled (the *Progress sync* / KOSync plugin), every time you open a book or wake the e-reader, KOReader turns Wi-Fi on to pull your reading position from the server.

If no network is available, for example when you are out, the **"Connecting to Wi-Fi…"** popup appears and the reader is stuck for 15–40 seconds. The popup cannot be dismissed, so you cannot read until the attempt fails.

## 2. What the patch does

1. **Short pause.** If you wake the reader less than **5 minutes** after putting it to sleep, nothing is downloaded and you go straight back to reading.
2. **Tap to cancel.** Whenever KOReader would turn Wi-Fi on to pull your position (opening a book, or waking up after more than 5 minutes), it *first* shows this message for **3 seconds**:
   > Syncing reading progress…
   > Tap to cancel.
   - **Don't touch anything:** it syncs as usual.
   - **Tap the message:** sync is cancelled and you are back to reading at once, with no Wi-Fi and no download.
3. **Sleep is unchanged.** When you put the reader to sleep, KOReader still tries to connect and push your position, as it does without the patch. If there is no network, it turns Wi-Fi off and queues the position, then sends it automatically on the next successful connection.

4. **Books finished offline are no longer lost.** If you close a book without a network (for example you finish it on the go and start the next one), KOSync puts its position in a queue to send later. Without the patch the plugin emptied that queue even when sending had failed, typically when you put the reader to sleep at home: it connected, pushed the *new* book, turned Wi-Fi off, and only then tried to send the queue, with no network. The finished book never reached the server. With the patch, for each queued book the reader first asks the server where you are:
   - if the server is further on, or got a position *after* this one was queued (for example you finished the book on another device), the queued position is dropped, so an old position never overwrites a newer one;
   - otherwise it is sent.

   A position leaves the queue only after one of the two, and the queue is handled *before* the open book's position, while Wi-Fi is still on. If the server cannot be reached, everything stays queued for next time.

The manual menu commands (*Push progress from this device now*, *Pull progress from other devices now*) are not affected and work as always.

The message only appears when Wi-Fi is off. If the reader is already online, sync happens immediately, with no message.

## 3. Requirements

- A recent **KOReader**. The patch has been tested on **v2026.07.2**, on both a Kobo and a Kindle Paperwhite. On very different versions it should be checked first (see section 7).
- The **Progress sync** plugin already set up, with a working server and login.
- In KOReader:
  - **Network → Action when Wi-Fi is off → Turn on**
  - **Progress sync → Automatically keep documents in sync** enabled. This option can only be turned on when the previous setting is *Turn on*.

## 4. Installation

1. Connect the e-reader to your computer over USB.
2. Find the KOReader folder:
   - **Kobo:** `.adds/koreader/`. The `.adds` folder is hidden: on a Mac, press `Cmd+Shift+.` in Finder to show hidden files.
   - **Kindle:** `koreader/` in the Kindle's root folder.
   - **Other devices:** the folder that contains KOReader's `reader.lua` and `plugins/` folder.
3. Inside that folder, create a folder called **`patches`** if it does not exist yet.
4. Copy **`2-kosync-cancel-v5.lua`** into `patches` and keep the name as it is. The leading `2-` is required: it tells KOReader when to load the patch.
   If you already have an earlier version (for example `2-kosync-ora-no.lua`, `2-kosync-ora-no-v2.lua`, `2-kosync-interrompi-v3.lua` or `2-kosync-cancel-v4.lua`), **delete it**: there must be only one version of the patch in the `patches` folder.
5. Eject the e-reader from the computer.
6. In KOReader: **☰ menu → Exit → Restart KOReader**.
7. Check the settings in section 3.

If **"Error applying patch"** appears at startup, the patch is not compatible with your version: delete the file and see section 7.

## 5. How to test it

Use an open book. You can do all of this at home, because the message appears before Wi-Fi is turned on.

1. **Opening a book:** open a book and the 3-second message should appear. Tap it: you are back to reading at once.
2. **Short pause:** put the reader to sleep and wake it after 1–2 minutes. No message, you can read straight away.
3. **Long pause:** put it to sleep and wake it after more than 5 minutes. The message appears. Don't touch it: after 3 seconds it connects and syncs.
4. **Sleep:** read a few pages and put the reader to sleep. At home it connects, pushes your position and goes to sleep. Another synced device should show the updated position.

In KOReader's log (`crash.log`, in the KOReader folder) the patch writes lines starting with **`KOSync cancel:`**, which help you see what happened.

## 6. Customising or removing

- **Change the timings or the message:** open the `.lua` file in a plain text editor. Near the top there are three lines:
  ```lua
  local SHORT_PAUSE = 5 * 60 -- seconds
  local WAIT = 3             -- seconds
  local MESSAGE = "Syncing reading progress…\nTap to cancel."
  ```
  Change the numbers, or translate the message into your language (`\n` is a line break), save and restart KOReader.
- **Remove it completely:** delete `2-kosync-cancel-v5.lua` from the `patches` folder and restart KOReader.

If your Mac creates a `._2-kosync-cancel-v5.lua` file next to the patch, you can ignore it: KOReader does not load it.

---

## 7. Instructions for Claude (or another AI assistant)

> This section is written for the assistant the user has shared these files with.

**Context.** `2-kosync-cancel-v5.lua` is a KOReader *user patch*. At startup KOReader runs, with `dofile`, the files in `koreader/patches/` whose names start with `2-`. This patch uses `userpatch.registerPatchPluginFunc("kosync", fn)` to modify the KOSync plugin class every time the plugin is instantiated, i.e. every time a book is opened. It does not change any KOReader file.

**What it wraps (each wrapper always calls the original):**

- `KOSync.getProgress(self, ensure_networking, interactive, ...)`: when `ensure_networking == true`, `interactive == false`, the device is not online (`NetworkMgr:isOnline()`) and the account is configured, it shows an `InfoMessage` with `timeout = WAIT`. On that instance, `onTapClose` and `onAnyKeyPressed` are overridden to mark the tap as "cancelled". In `dismiss_callback`, if the user did not tap, it schedules the original `getProgress` with `UIManager:scheduleIn(0.5, ...)`; if they tapped, it does nothing.
  - **Important:** do not call `getProgress` directly inside `dismiss_callback`. The callback runs inside `InfoMessage:onCloseWidget`, while the message is being torn down, and connecting calls `UIManager:forceRePaint()`. KOReader then tries to repaint the already-freed message and crashes (`textboxwidget.lua: attempt to index field '_bb' (a nil value)`). This was a bug in version 1.
  - This is what prevents the freeze: on Kobo and Kindle, `NetworkMgr:turnOnWifiAndWaitForConnection` → `turnOnWifi` → `reconnectOrShowNetworkMenu` is **blocking** (a network scan, then a wait of up to about 15 s in a `usleep` loop), so the "Connecting to Wi-Fi…" popup cannot be dismissed while it is up. The choice has to be made before Wi-Fi is turned on.
- `KOSync._onSuspend`: stores `os.time()` in a file-local variable shared across plugin instances, then calls the original. Pushing on sleep is unchanged.
- `KOSync._onResume`: if fewer than `SHORT_PAUSE` seconds have passed since the last suspend, it returns without doing anything; otherwise it calls the original, whose download goes through the wrapped `getProgress`.
- `KOSync.drainQueue` (**replaced**, not wrapped): in v2026.07.2 the original sends each queued item with `pcall(client.update_progress, ...)` and treats `true` as success. `KOSyncClient:update_progress` catches every error inside its own coroutine and reports it only through the callback, so the pcall is always `true` and the queue (`settings/kosync_queue.lua`) was emptied even when nothing was sent. The replacement handles each item with a fresh `KOSyncClient`: it first calls `get_progress` for that document. If the server has a `percentage` and its `timestamp` (time of receipt on the server) is not older than the item's `queued_at`, and the server percentage is `>=` the queued one, the item is dropped (another device is ahead or newer). Otherwise it calls `update_progress` and counts the item as done only when the callback gets `ok == true` (HTTP 200). It stops at the first unreachable request and saves the unhandled items back. Queued items for the open book are dropped: the plugin pushes its live position anyway. Without the Turbo looper (the default) the request is synchronous, so the callback has run when `update_progress` returns; if it has not, the item is kept and resent later.
- `KOSync.updateProgress`: when `NetworkMgr:isOnline()`, it calls `self:drainQueue()` first, then the original. This matters on sleep: `_onSuspend` → `updateProgress(true, false, true)` connects through `willRerunWhenOnline`, reruns `self:updateProgress` (now online), pushes and immediately calls `NetworkMgr:disableWifi()`. The plugin's own drain is scheduled 0.5 s after `NetworkConnected`, so it used to run with Wi-Fi already off.
- `_onSuspend` and `_onResume` are assigned to `self.onSuspend` and `self.onResume` by `KOSync:registerEvents()` in `onReaderReady`, i.e. after the patch has run, so patching them on the class is enough.

**Before installing it on a device, check against the user's installed version:**

1. Version: the `git-rev` file in the KOReader folder. The patch is tested with v2026.07.x.
2. `frontend/userpatch.lua` must define `userpatch.registerPatchPluginFunc`.
3. `plugins/kosync.koplugin/main.lua` must define `KOSync:drainQueue()`, `KOSync:updateProgress(ensure_networking, interactive, on_suspend)`, `KOSync._onSuspend`, `KOSync._onResume`, `KOSync:getProgress(ensure_networking, interactive)` and a `KOSync:registerEvents()` that assigns them. `onReaderReady` must also call `self:getProgress(true, false)`.
4. `frontend/ui/widget/infomessage.lua`: `InfoMessage` must support `timeout` and `dismiss_callback` (called in `onCloseWidget`) and have `onTapClose` / `onAnyKeyPressed` handlers.
5. Settings: in `settings.reader.lua`, `wifi_enable_action` must be `"turn_on"`; in `settings/kosync.lua`, `auto_sync` must be `true`. The plugin turns `auto_sync` off by itself when `wifi_enable_action` is not `turn_on`.

If names have changed, adapt the wrappers and keep the same logic.

**For debugging:** look in `crash.log` for `KOSync cancel:` lines (`patch applied`, `sync cancelled by the user`, `no tap, syncing`, `woke up after N s, no download`, `queue sent N dropped D kept M`, `server is ahead for <digest> ... queued position dropped`) and for NetworkMgr messages (`turnOnWifiAndWaitForConnection: Connection failed!`, `Wi-Fi successfully restored`).

**Intended behaviour,** to keep if you change the patch:

- Opening a book or waking the reader must never be blocked by Wi-Fi.
- Sleep must still push the position. Without a network, it is fine for it to try and then turn Wi-Fi off.
- A position queued offline must never be dropped before the server has accepted it, unless the server already holds a further or newer position for that book.
- A cancel only applies that one time: on the next wake-up, the 5-minute rule and then the message apply again.

---

## Versions

- **v5**: positions queued offline (for example a book finished on the go) are no longer lost. Before sending a queued book, the server's position is checked: if another device is further on or newer, the queued position is dropped instead of overwriting it. Entries leave the queue only after that, and the queue is handled before the open book's position, while Wi-Fi is still on. File renamed to `2-kosync-cancel-v5.lua`.
- **v4**: everything in English (code, comments, log lines, message: "Tap to cancel."). The message text is now a setting at the top of the file, so it can be translated. File renamed to `2-kosync-cancel-v4.lua`.
- **v3**: message changed to "Tocca per interrompere." (Italian); file renamed to `2-kosync-interrompi-v3.lua`.
- **v2**: fixed a crash ("Don't Panic!") that happened when the 3-second message was left to time out without tapping it.
- **v1**: first version.

---

## Licence

Released under the **AGPL-3.0**, the same licence as [KOReader](https://github.com/koreader/koreader). See the `LICENSE` file.
