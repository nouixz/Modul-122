README / Kurzdokumentation

Beschreibung:
Dieses Projekt automatisiert periodische Backups von beliebigen Quellpfaden zu einem Ziel (lokal, Netzpfad, gemountetes Cloud-Drive). Backups werden komprimiert (ZIP), optional mit AES‑256 verschlüsselt, versioniert (Zeitstempel) und durch Retention bereinigt.

Hauptfunktionen:

Mehrere Quellen (inkl. Exclude‑Muster) → ein gemeinsames Backup‑Artefakt pro Durchlauf

Komprimierung (ZIP) und optionale Verschlüsselung (AES‑GCM, .zip.enc)

Protokollierung: Text-Log + optional JSON-Log (Ereignisebene: Info/Warning/Error)

Benachrichtigung (optional): SMTP‑Mail und/oder Microsoft Teams Webhook

Fehlerrobust: isolierte Fehler stoppen den Gesamtprozess nicht; am Ende Aggregatstatus

Aufbewahrung: löscht alte Artefakte nach RetentionDays

Plattformunabhängig: PowerShell 7+ (Core). ZIP via Compress-Archive (Core-kompatibel); AES via .NET AesGcm.

Voraussetzungen:

PowerShell 7.2+ (pwsh -v prüfen)

Schreibrechte im Zielverzeichnis

Optional: SMTP-Zugang oder Teams Incoming Webhook

Schnellstart:

config.sample.json als config.json anpassen

Skript ausführen: pwsh ./backup.ps1 -ConfigPath ./config.json

Task planen (Windows Task Scheduler / systemd timer / cron)