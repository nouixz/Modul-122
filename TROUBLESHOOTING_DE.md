# Fehlerbehebung (Troubleshooting)

Typische Probleme und Lösungen beim Einsatz des Dateimanagers.

## Ausführungsrichtlinie blockiert Skript
**Symptom:** Beim Start erscheint eine Meldung zu „Execution Policy“ bzw. „Skript ist deaktiviert“.

**Lösung:**
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```
PowerShell neu starten und erneut versuchen.

## Keine Treffer bei der Suche
- Prüfen, ob **Wurzelpfad** korrekt ist und existiert.
- **Muster**: Bei aktivierter **Regex** muss ein gültiger regulärer Ausdruck eingegeben werden (z. B. `^Report_.*\.pdf$`).
- **Größen-/Datumsfilter** ggf. auf `0` bzw. leer setzen.
- **Unterordner einbeziehen** aktivieren, wenn rekursiv gesucht werden soll.

## Kopieren/Verschieben schlägt fehl
- **Zielordner** prüfen (Schreibrechte, genügend Speicherplatz).
- Dateien, die von anderen Programmen **gesperrt** sind, können nicht bewegt werden – Programme schließen oder später erneut versuchen.
- Fehlerdetails im **Log (log.html)** nachlesen.

## ZIP-Archiv wird nicht erstellt
- Pfad in **Archiv-Ziel (ZIP)** muss auf `.zip` enden.
- Ausreichende Schreibrechte im Zielordner sicherstellen.
- Bei sehr großen Dateien kann die Erstellung länger dauern – ggf. zuerst nur wenige Dateien testen.

## Backup nicht möglich
- **Backup Basisordner** muss existieren oder wird erstellt; prüfen, ob genügend Speicherplatz vorhanden ist.
- Antivirus/Endpoint-Schutz kann Kopiervorgänge blockieren – Ausnahmen konfigurieren.

## UI reagiert nicht / flackert
- Bei sehr großen Trefferlisten kann die Anzeige etwas träge sein. Filter enger setzen.
- PowerShell 7+ kann Performance verbessern.

## Log wird nicht aktualisiert
- Prüfen, ob `log.html` beschreibbar ist (keine Schreibsperre/keine geöffnete exklusive Sitzung).
- Falls die Datei beschädigt ist, löschen/umbenennen – sie wird automatisch neu erstellt.

## Preset wird nicht geladen
- Inhalt von `config.json` auf **gültiges JSON** prüfen.
- Felder wie `ModifiedAfter`/`ModifiedBefore` im Format `yyyy-MM-dd` angeben.
- Bei Bedarf das Preset aus der UI **neu speichern**.

## Allgemeine Tipps
- PowerShell **als Administrator** starten, wenn auf Systemordner zugegriffen wird.
- Lange Pfade vermeiden oder **NTFS-Lange-Pfade** in Windows aktivieren (Gruppenrichtlinie/Registry).

Wenn das Problem weiterhin besteht, die **log.html** mitsamt Fehlerzeile prüfen und die genutzten Filter/Optionen dokumentieren.
