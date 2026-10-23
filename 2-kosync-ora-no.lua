--[[
2-kosync-ora-no.lua
Patch per il plugin "Sincronizzazione progressi" (KOSync) di KOReader (testata su v2026.07.2)

Obiettivo: l'apertura della lettura non deve mai restare bloccata dal Wi-Fi.

1. PAUSA BREVE: se riapri il lettore entro 5 minuti da quando l'hai bloccato,
   non scarica la posizione dal server: riprendi subito a leggere.
2. "ORA NO": quando il plugin vorrebbe accendere il Wi-Fi per scaricare la
   posizione (apertura di un libro, riapertura dopo una pausa lunga), PRIMA di
   accenderlo compare per 3 secondi l'avviso
   "Sincronizzo la posizione… Tocca per saltare".
   - Non tocchi niente -> sincronizza come sempre.
   - Tocchi -> torni subito a leggere, senza Wi-Fi e senza download.
3. CHIUSURA: invariata. Quando blocchi il lettore prova a connettersi e a inviare
   la posizione; se non trova la rete spegne il Wi-Fi e la posizione resta in
   coda (la invia da solo alla prossima connessione riuscita).

Requisiti: Rete -> "Azione quando il Wi-Fi è spento" = Accendi,
           Sincronizzazione progressi -> "Mantieni automaticamente sincronizzati" attivo.
Per toglierla: cancella questo file e riavvia KOReader.
]]

local userpatch = require("userpatch")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local PAUSA_BREVE = 5 * 60 -- secondi: sotto questa soglia, niente download alla riapertura
local ATTESA = 3           -- secondi in cui puoi toccare per dire "ora no"

-- Condiviso tra un libro e l'altro (il plugin viene ricreato a ogni libro aperto)
local bloccato_alle = nil

userpatch.registerPatchPluginFunc("kosync", function(KOSync)
    if KOSync._ora_no_patched then return end
    KOSync._ora_no_patched = true

    local orig_onSuspend = KOSync._onSuspend
    local orig_onResume = KOSync._onResume
    local orig_getProgress = KOSync.getProgress

    -- Download automatico della posizione: se servirebbe accendere il Wi-Fi, chiedi prima.
    -- (ensure_networking = true e interactive = false: apertura libro e riapertura del lettore.
    --  I comandi manuali "Ricevi progressi" sono interactive e non vengono toccati.)
    KOSync.getProgress = function(self, ensure_networking, interactive, ...)
        if not ensure_networking or interactive
                or NetworkMgr:isOnline()
                or not self.settings.username or not self.settings.userkey then
            return orig_getProgress(self, ensure_networking, interactive, ...)
        end
        if self._ora_no_avviso_aperto then return end
        self._ora_no_avviso_aperto = true

        local args = { ... }
        local saltato = false
        local msg = InfoMessage:new{
            text = "Sincronizzo la posizione…\nTocca per saltare (ora no).",
            timeout = ATTESA,
        }
        msg.onTapClose = function(widget)
            saltato = true
            UIManager:close(widget)
            return true
        end
        msg.onAnyKeyPressed = msg.onTapClose
        msg.dismiss_callback = function()
            self._ora_no_avviso_aperto = nil
            if saltato then
                logger.info("KOSync ora-no: download saltato dall'utente")
                return
            end
            -- NON connettersi qui dentro: siamo nel mezzo della chiusura dell'avviso,
            -- e la connessione ridisegna lo schermo (crash su widget già smontato).
            -- Rimandiamo a dopo che la chiusura è completata.
            UIManager:scheduleIn(0.5, function()
                -- Il libro potrebbe essere stato chiuso nel frattempo
                if not self.ui or not self.ui.document then return end
                logger.info("KOSync ora-no: nessun tocco, sincronizzo")
                orig_getProgress(self, ensure_networking, interactive, unpack(args))
            end)
        end
        UIManager:show(msg)
    end

    KOSync._onSuspend = function(self, ...)
        bloccato_alle = os.time()
        return orig_onSuspend(self, ...) -- invio alla chiusura: comportamento originale
    end

    KOSync._onResume = function(self, ...)
        if bloccato_alle and os.time() - bloccato_alle < PAUSA_BREVE then
            logger.info("KOSync ora-no: riaperto dopo", os.time() - bloccato_alle, "s, niente download")
            return
        end
        return orig_onResume(self, ...) -- il download passa da getProgress, che chiede prima
    end

    logger.info("KOSync ora-no: patch applicata")
end)
