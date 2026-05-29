# Changelog

Alle wichtigen Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

## [2.1] - 2026-05-29

### Neue Features

- **Dark Mode**: Dunkles Theme per Button im Header umschaltbar (alle Elemente korrekt eingefärbt)
- **Verwaiste GPOs erkennen**: Findet GPOs ohne OU-Verknüpfung in der gesamten Domäne
- **Änderungshistorie**: Zeigt Timeline aller GPO-Änderungen der letzten 90 Tage
- **GPO-Vergleich (Diff)**: Zwei ausgewählte GPOs nebeneinander vergleichen – zeigt alle Unterschiede in Einstellungen
- **Konflikterkennung**: Erkennt widersprüchliche Einstellungen die auf gleichen OUs in verschiedenen GPOs konfiguriert sind (nur echte Konflikte zwischen unterschiedlichen GPOs)
- **Doppelte Einstellungen**: Listet am Ende des Exports alle Einstellungen auf, die in mehreren unterschiedlichen GPOs konfiguriert sind
- **PDF-Export**: Erstellt druckfertiges PDF im Querformat via Edge/Chrome Headless-Modus mit kompakter Schriftgröße

### Verbessert

- Export-Berichte (HTML/Markdown) enthalten jetzt am Ende eine Analyse-Sektion mit Duplikaten und Konflikten
- Neue Buttons in der GPO-Toolbar für schnellen Zugriff auf Analyse-Funktionen
- PDF wird im Querformat mit optimierter Schriftgröße erstellt
- Deduplizierung in `Get-GPOSettingsFromXml` verhindert doppelte Einträge im Report
- Dark Mode färbt alle GUI-Elemente korrekt ein (Labels, CheckBoxen, TextBoxen, ComboBoxen, TreeView, DataGrid)
- Footer zeigt jetzt Autor und GitHub-Link

## [2.0.3] - 2026-05-29

### Verbessert

- **XML-Ordnername nutzt Datei-Prefix**: Der Ordner für Roh-XML-Exporte verwendet jetzt den konfigurierten Dateinamen-Prefix (z.B. `GPO-XML_Desktop22_2026-05-29_14-30` statt nur `GPO-XML_2026-05-29_14-30`).

## [2.0.2] - 2026-05-28

### Features

- Moderne WPF-GUI mit OU-Baumansicht und GPO-DataGrid
- Mehrsprachig (DE/EN) mit automatischer Systemerkennung
- Volltextsuche über GPO-Namen und Einstellungswerte
- Farbcodierter HTML-Report mit Executive-Übersicht
- Markdown-Export für Wikis und Git-Repos
- Status-Filter (Alle aktiv, Deaktiviert, Teilweise)
- Kürzlich geänderte GPOs farbig hervorgehoben
- Klickbare OU-Baumstruktur im HTML mit Sprunglinks
- Collapsible Sektionen mit Alle auf-/zuklappen
- Anpassbarer Dateiname-Prefix
- RSAT Auto-Installation
- Vererbungsanzeige mit Blockierungs-Markierung
- Single-Click Checkbox für GPO-Auswahl
