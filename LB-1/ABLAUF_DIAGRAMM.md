# Ablaufdiagramm (Mermaid)

```mermaid
flowchart TD
    A[Start: PS7 & WPF laden] --> B[Config laden (config.json) & log.html initialisieren]
    B --> C[GUI anzeigen]
    C -->|Suchen| D[Get-MatchingFiles(RootPath, Pattern, Recurse)]
    D --> E[Treffer -> ObservableCollection -> DataGrid]
    E -->|Copy| F[Copy-Or-MoveFiles(items, Destination)]
    E -->|Move| G[Copy-Or-MoveFiles(items, Destination, -Move)]
    E -->|Archive| H[New-Archive(items, ArchivePath)
Temp-Ordner -> Compress-Archive]
    E -->|Backup| I[New-Backup(items, BackupRoot)
Backup_yyyyMMdd_HHmmss]
    F --> J[Write-LogHtml(OK/ERROR pro Datei)]
    G --> J
    H --> J
    I --> J
    J --> C
    C -->|Fenster schließen| K{Log behalten?
Ja/Nein/Abbrechen}
    K -->|Ja| L[Write-LogHtml(INFO: Ende)]
    K -->|Nein| M[log.html löschen -> Initialize-LogHtml -> Write-LogHtml(INFO: Reset)]
    K -->|Abbrechen| C
    L --> N[Ende]
    M --> N[Ende]
```
