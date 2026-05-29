# 📋 GPO-Documentation-GUI

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![Platform](https://img.shields.io/badge/Platform-Windows%20Server%202016%2B-lightgrey.svg)](https://www.microsoft.com/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-2.0.2-brightgreen.svg)]()
[![Language](https://img.shields.io/badge/Language-DE%20%7C%20EN-blueviolet.svg)]()

> Ein umfassendes PowerShell WPF-Tool zur automatisierten Dokumentation von Gruppenrichtlinien (GPOs) in Active Directory-Umgebungen. Mit OU-Baumansicht, Volltextsuche, farbcodiertem HTML-Report und Markdown-Export.

## 📑 Inhaltsverzeichnis

- [Features](#-features)
- [Unterstützte GPO-Typen](#-unterstützte-gpo-typen)
- [Systemanforderungen](#-systemanforderungen)
- [Installation](#-installation)
- [Verwendung](#-verwendung)
- [Export-Formate](#-export-formate)
- [Suche](#-suche)
- [Sprachunterstützung](#-sprachunterstützung)
- [Architektur](#-architektur)
- [Troubleshooting](#-troubleshooting)
- [License](#-license)

---

## ✨ Features

- 🖥️ **Moderne WPF-GUI** mit OU-Baumansicht und GPO-DataGrid
- 🌍 **Mehrsprachig (DE/EN)** – Automatische Systemerkennung + Sprachumschaltung zur Laufzeit
- 🔍 **Volltextsuche** – Durchsucht GPO-Namen UND alle Einstellungswerte (Registry-Keys, Pfade, etc.)
- 🎨 **Farbcodierter HTML-Report** mit Executive-Übersicht und OU-Baumstruktur
- 📄 **Markdown-Export** für Wikis, Git-Repos oder Copilot-Import
- 📊 **Status-Filter** – GPOs nach Status filtern (Alle aktiv, Deaktiviert, Teilweise)
- 🕐 **Kürzlich geändert** – GPOs der letzten 30 Tage farbig hervorgehoben
- 🔗 **Klickbare OU-Baumstruktur** im HTML mit Sprunglinks zu GPO-Sektionen
- 📂 **Collapsible Sektionen** – Alle auf-/zuklappen per Button
- ↩️ **Zurück-nach-oben Links** nach jeder GPO-Sektion
- 📝 **Anpassbarer Dateiname** – Export-Prefix frei konfigurierbar
- 🔧 **RSAT Auto-Install** – Fehlende Module werden automatisch installiert
- 🚫 **Vererbungsanzeige** – Blockierte Vererbung im OU-Baum markiert
- ✅ **Single-Click Checkbox** – GPOs direkt mit einem Klick auswählen

---

## 📋 Unterstützte GPO-Typen

### 🏗️ Registry & Policies
| Typ | Beschreibung |
|---|---|
| **Registry (GPP)** | Group Policy Preferences – Registry-Einstellungen mit Hive/Key/Value |
| **Registry (Security)** | Security-Extension Registry-ACLs |
| **Administrative Vorlagen** | Policies mit DropDown, EditText, Numeric, CheckBox, ListBox |
| **Account-Richtlinien** | Passwort-, Sperrung- und Kerberos-Richtlinien |
| **Sicherheitsoptionen** | SecurityOptions mit Display-Infos |

### 📂 Dateisystem & Ordner
| Typ | Beschreibung |
|---|---|
| **Dateien (GPP)** | Dateioperationen (Erstellen, Ersetzen, Löschen) |
| **Ordner (GPP)** | Ordneroperationen mit Aktionen |
| **Ordnerumleitung** | Folder Redirection mit bekannten Folder-IDs |

### ⚙️ System & Dienste
| Typ | Beschreibung |
|---|---|
| **Skripte** | Startup/Shutdown/Logon/Logoff mit Parametern |
| **Geplante Tasks** | TaskV2/ImmediateTaskV2 mit Trigger-Infos |
| **Dienste (GPP)** | NTServices mit Starttyp und Aktion |
| **System Services** | Dienste über Security-Extension |
| **Umgebungsvariablen** | Environment Variables mit Aktionen |

### 👥 Benutzer & Netzwerk
| Typ | Beschreibung |
|---|---|
| **Lokale Benutzer/Gruppen** | Gruppenmitgliedschaften und Aktionen |
| **Verknüpfungen** | Shortcuts mit Ziel und Aktion |
| **Firewall-Regeln** | Inbound/Outbound/Profile/GlobalSettings |

---

## 💻 Systemanforderungen

- **Windows Server 2016+** oder **Windows 10/11** mit RSAT
- **PowerShell 5.1+**
- **Active Directory**-Domänenmitgliedschaft
- **Administratorrechte** (für RSAT-Installation falls nötig)
- Benötigte Module (werden automatisch installiert):
  - `ActiveDirectory`
  - `GroupPolicy`

---

## 🚀 Installation

powershell
# Repository klonen
git clone https://github.com/RoccoAmmon/GPO-Documentation.git
cd GPO-Documentation

# Direkt starten (als Administrator)
.\GPO-Documentation-GUI.ps1


> ⚠️ Das Skript muss als **Administrator** ausgeführt werden. Fehlende RSAT-Features werden automatisch installiert.

---

## 🎮 Verwendung

### Workflow

1. **🖱️ OU auswählen** – Im linken Baum eine Organisationseinheit anklicken
2. **👀 GPOs prüfen** – Rechts erscheinen alle verknüpften (und vererbten) GPOs
3. **🔍 Filtern/Suchen** – Status-Filter oder Freitextsuche nutzen
4. **☑️ Auswählen** – Einzelne GPOs per Checkbox markieren oder "Alle auswählen"
5. **📤 Exportieren** – Format wählen (HTML/Markdown/Beides) und exportieren

### Optionen

| Option | Beschreibung |
|---|---|
| **Vererbte GPOs anzeigen** | Zeigt auch von übergeordneten OUs vererbte GPOs |
| **Detaillierter Bericht** | Parst GPO-XML und zeigt alle Einstellungen |
| **Roh-XML speichern** | Speichert GPO-Reports als XML-Dateien |
| **Dateiname-Prefix** | Anpassbarer Prefix für Export-Dateien |

---

## 📤 Export-Formate

### 🌐 HTML

- Selbstständige HTML-Datei ohne externe Abhängigkeiten
- Professionelles Design mit Segoe UI
- Collapsible `<details>`-Sektionen pro GPO
- JavaScript-Buttons: Alle auf-/zuklappen
- Klickbare OU-Baumstruktur mit Sprunglinks
- Farbcodierung: 🟢 Enabled | 🔴 Disabled | ⚪ NotConfigured
- Druckoptimiertes CSS (`@media print`)
- Zurück-nach-oben Links nach jeder Sektion

### 📄 Markdown

- Kompatibel mit GitHub, Azure DevOps, Confluence
- Tabellenformat für alle Einstellungen
- Inhaltsverzeichnis mit Ankerlinks
- Ideal für Git-Versionierung von GPO-Änderungen

---

## 🔍 Suche

| Zeichen | Verhalten |
|---|---|
| **1-2 Zeichen** | Filtert nur nach GPO-Namen (sofort) |
| **Ab 3 Zeichen** | Durchsucht auch alle GPO-Einstellungswerte |

> 💡 Beim ersten Verwenden der Wertsuche wird ein einmaliger Cache aufgebaut (Progress-Anzeige + Wait-Cursor). Danach ist die Suche instant.

**Beispiele:** `server-xx`, `HKLM\Software`, `Disabled`, `192.168`

---

## 🌍 Sprachunterstützung

| Sprache | Erkennung | GUI | HTML-Export | Markdown-Export |
|---|---|---|---|---|
| 🇩🇪 Deutsch | Automatisch bei deutschem OS | ✅ | ✅ | ✅ |
| 🇬🇧 English | Automatisch bei englischem OS | ✅ | ✅ | ✅ |

Umschaltung jederzeit über das **Sprach-Dropdown** im Header möglich. Alle Labels, Statusmeldungen, Dialoge und Exports werden sofort übersetzt.

---

## 🏗️ Architektur


GPO-Documentation-GUI.ps1
├── RSAT Auto-Installation
├── Sprachsystem (DE/EN Dictionary)
├── XAML GUI Definition (WPF)
│   ├── Header (Titel, Suche, Sprache)
│   ├── OU TreeView (Lazy-Loading)
│   ├── GPO DataGrid (ObservableCollection)
│   └── Export-Optionen
├── C# Hilfsklasse (GpoItem + INotifyPropertyChanged)
├── Funktionen
│   ├── Apply-Language()
│   ├── Update-GpoFilter() (Name + Wertsuche)
│   ├── Load-OUTree() / Add-OUTreeNode()
│   ├── Get-LinkedGPOs()
│   ├── Parse-SettingNode() (16+ Typen)
│   ├── Get-GPOSettingsFromXml()
│   ├── Export-GPOasHTML()
│   └── Export-GPOasMarkdown()
└── Event-Handler


---

## 🔧 Troubleshooting

| Problem | Lösung |
|---|---|
| RSAT-Module nicht gefunden | Neustart nach automatischer Installation erforderlich |
| GPOs laden langsam | Normal bei vielen vererbten GPOs (Netzwerk-Calls zum DC) |
| Suche dauert beim ersten Mal | Einmaliger Cache-Aufbau – danach instant |
| Checkbox braucht Doppelklick | Update auf aktuelle Version (Single-Click implementiert) |
| HTML-Export leer | "Detaillierter Bericht" Checkbox aktivieren |

---

## 📜 License

Intern – Für den Einsatz in der eigenen Active Directory-Umgebung.
