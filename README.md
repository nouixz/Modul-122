# PowerShell BackupTool

Automatisierte Backup-Lösung mit Protokollierung, Fehlerbehandlung und einer einfachen GUI.  
**Modul 122 – Automatisierung eines wiederkehrenden Prozesses**  
Autor: Chavo Moser

## Funktionen

- Sichert Dateien von einem Quell- in ein Zielverzeichnis
- Schließt Dateien nach Erweiterung aus (konfigurierbar)
- Protokolliert alle Backup-Vorgänge und Fehler
- Einfache Windows Forms GUI für die Bedienung
- Konfiguration über `config.json`

## Verwendung

1. **Konfigurieren**  
    Bearbeiten Sie die `config.json`, um Quell-, Ziel-, Protokolldatei und auszuschließende Erweiterungen festzulegen.

2. **Tool ausführen**  
    Öffnen Sie PowerShell und führen Sie aus:

    ```powershell
    .\LB1-Powershell\BackupTool.ps1
    ```

3. **Backup starten**  
    Klicken Sie im GUI auf die Schaltfläche „Backup starten“.

## Konfiguration

Beispiel für `config.json`:

```json
{
  "SourcePath": "C:\\Quelle",
  "TargetPath": "C:\\Backup",
  "LogFile": ".\\backup.log",
  "Exclude": [".tmp", ".log"]
}
```

- `SourcePath`: Zu sichernder Ordner
- `TargetPath`: Zielordner für das Backup
- `LogFile`: Pfad zur Protokolldatei
- `Exclude`: Liste von Dateierweiterungen, die übersprungen werden

## Protokolldatei

Alle Backup-Vorgänge und Fehler werden in `backup.log` protokolliert.

## Voraussetzungen

- Windows mit PowerShell
- .NET Framework (für Windows Forms GUI)

##