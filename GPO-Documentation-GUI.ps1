<#
.SYNOPSIS
    GPO-Dokumentations-GUI - Gruppenrichtlinien dokumentieren und exportieren.
.DESCRIPTION
    Grafische Oberfläche zur Auswahl von OUs und verknüpften GPOs.
    Exportiert ausgewählte GPOs als HTML- und/oder Markdown-Bericht.
    Unterstützt Volltextsuche, Farbcodierung, OU-Baumstruktur und Mehrsprachigkeit (DE/EN).
.NOTES
    Autor:      Rocco Ammon
    Datum:      29.05.2026
    Version:    2.1
    Benötigt:   ActiveDirectory-Modul, GroupPolicy-Modul, RSAT-Tools
    Installiert fehlende RSAT-Features automatisch (erfordert Admin-Rechte).
.LINK
    https://github.com/RoccoAmmon/GPO-Dokumentation
#>

# Auto-Elevation: Als Administrator neu starten falls nötig
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`""
    Start-Process PowerShell -Verb RunAs -ArgumentList $arguments
    exit
}

# RSAT-Features prüfen und installieren
$rsatFeatures = @(
    @{ Module = 'ActiveDirectory';  Feature = 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0' },
    @{ Module = 'GroupPolicy';      Feature = 'Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0' }
)

$installedNew = $false
$needsRestart = $false
foreach ($rsat in $rsatFeatures) {
    if (-not (Get-Module -ListAvailable -Name $rsat.Module)) {
        # Prüfen ob Feature bereits installiert aber Modul noch nicht sichtbar
        $capability = Get-WindowsCapability -Online -Name $rsat.Feature -ErrorAction SilentlyContinue
        if ($capability -and $capability.State -eq 'Installed') {
            Write-Host "$($rsat.Feature) ist installiert, aber Modul nicht geladen. Neustart erforderlich." -ForegroundColor Yellow
            $needsRestart = $true
            continue
        }

        Write-Host "Installiere RSAT-Feature: $($rsat.Feature) ..." -ForegroundColor Yellow
        try {
            $result = Add-WindowsCapability -Online -Name $rsat.Feature -ErrorAction Stop
            Write-Host "  -> $($rsat.Feature) installiert." -ForegroundColor Green
            $installedNew = $true
            if ($result.RestartNeeded) { $needsRestart = $true }
        } catch {
            Write-Error "Fehler beim Installieren von $($rsat.Feature): $($_.Exception.Message)"
            Write-Error "Bitte installieren Sie die RSAT-Tools manuell: Settings > Apps > Optional Features > RSAT"
            Read-Host "Druecken Sie Enter zum Beenden"
            exit 1
        }
    }
}

# Nach Neuinstallation: Modulpfade aktualisieren und erneut prüfen
if ($installedNew -or $needsRestart) {
    $env:PSModulePath = [System.Environment]::GetEnvironmentVariable('PSModulePath', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PSModulePath', 'User')

    # Prüfen ob Module jetzt verfügbar sind (ohne Neustart)
    $allFound = $true
    foreach ($rsat in $rsatFeatures) {
        if (-not (Get-Module -ListAvailable -Name $rsat.Module)) {
            $allFound = $false
            break
        }
    }

    if (-not $allFound) {
        Write-Warning "RSAT-Features wurden installiert, aber die Module sind im aktuellen Prozess noch nicht verfuegbar."
        $choice = Read-Host "Computer jetzt neu starten? (J/N)"
        if ($choice -match '^[jJyY]') {
            Restart-Computer -Force
        } else {
            Write-Host "Bitte starten Sie den Computer manuell neu und fuehren Sie das Skript erneut aus." -ForegroundColor Yellow
            Read-Host "Druecken Sie Enter zum Beenden"
            exit 0
        }
    }
}

# Module laden
Import-Module ActiveDirectory -ErrorAction Stop
Import-Module GroupPolicy -ErrorAction Stop

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

#region Sprachsystem
$script:lang = if ((Get-Culture).TwoLetterISOLanguageName -eq 'de') { 'de' } else { 'en' }
$script:L = @{}
$script:langData = @{
    de = @{
        windowTitle='GPO-Dokumentation'; domainPrefix='Domäne:'; searchLabel='Suche:'
        ouHeader='Organisationseinheiten (OUs)'; refreshBtn='Aktualisieren'; expandAllBtn='Alle aufklappen'
        gpoHeader='Gruppenrichtlinien (GPOs)'; selectAll='Alle auswählen'; showInherited='Vererbte GPOs anzeigen'
        statusLabel='Status:'; filterAll='Alle'; filterAllActive='Alle aktiv'; filterDisabled='Deaktiviert'; filterPartial='Teilweise'
        colName='GPO-Name'; colStatus='Status'; colLink='Verknüpfung'; colCreated='Erstellt'; colModified='Geändert'
        exportHeader='Export-Optionen'; formatLabel='Format:'; detailCheck='Detaillierter Bericht (GPO-XML)'; rawXmlCheck='Roh-XML speichern'
        outputLabel='Ausgabepfad:'; filePrefix='Dateiname-Prefix:'; exportSelected='Ausgewählte exportieren'; exportAll='Alle exportieren'
        statusReady='Bereit. Bitte eine OU auswählen.'
        allEnabled='Alle aktiv'; allDisabled='Alle deaktiviert'; userDisabled='Benutzer deaktiviert'; computerDisabled='Computer deaktiviert'
        linkDirect='Direkt'; linkInherited='Vererbt'; loading='Laden...'
        loadingOUs='OUs werden geladen...'; loadedOUs='OUs geladen. Bitte eine OU auswählen.'
        loadingGPOs='GPOs werden geladen für:'; loadedGPOs='GPOs geladen für:'
        expandingAll='Alle OUs werden aufgeklappt...'; expandedAll='Alle OUs aufgeklappt.'
        gpoCount='{0} von {1} GPO(s)'; inheritBlocked='Vererbung blockiert'
        adError='Fehler beim Verbinden mit Active Directory:'; adErrorTitle='AD-Verbindungsfehler'
        exportComplete='Export abgeschlossen!'; files='Dateien:'; openFolder='Ordner öffnen?'; exportSuccess='Export erfolgreich'
        noSelection='Bitte mindestens eine GPO auswählen.'; noSelectionTitle='Keine Auswahl'
        noGpos='Keine GPOs vorhanden.'; noGposTitle='Keine GPOs'
        invalidPath='Der Ausgabepfad existiert nicht:'; invalidPathTitle='Ungültiger Pfad'
        exporting='Exportiere'; gpos='GPO(s)'; creatingHtml='Erstelle HTML-Bericht...'; creatingMd='Erstelle Markdown-Bericht...'
        savingXml='Speichere XML:'; exportError='Fehler beim Export:'; exportErrorTitle='Exportfehler'
        filesCreated='Datei(en) erstellt.'; loadError='Fehler beim Laden:'; gpoLoadError='Fehler beim Laden der GPOs:'
        chooseFolder='Ausgabeordner wählen'
        htmlTitle='GPO-Dokumentation'; createdOn='Erstellt am:'; domain='Domäne:'; gpoCountLabel='Anzahl GPOs:'
        toc='Inhaltsverzeichnis'; ouTree='OU-Struktur mit GPO-Verknüpfungen'
        gpoId='GPO-ID'; status='Status'; link='Verknüpfung'; created='Erstellt'; modified='Zuletzt geändert'
        linkedOUs='Verknuepfte OUs'; ouNameLabel='OU-Name'; pathLabel='Pfad'; activeLabel='Aktiv'; yes='Ja'; no='Nein'
        permissions='Berechtigungen'; userGroup='Benutzer/Gruppe'; permission='Berechtigung'; typeLabel='Typ'
        compSettings='Computereinstellungen'; userSettings='Benutzereinstellungen'
        settingLabel='Einstellung'; valueLabel='Wert'
        noSettings='Keine Einstellungen konfiguriert.'; configDetails='Konfigurationsdetails'
        detailError='Detailbericht konnte nicht generiert werden:'
        generatedWith='Generiert mit GPO-Dokumentation Tool'
        expandAllHtml='Alle aufklappen'; collapseAllHtml='Alle zuklappen'; backToTop='↑ Nach oben'
        recentlyModified='Kürzlich geändert (letzte 30 Tage)'
        actionReplace='Ersetzen'; actionUpdate='Aktualisieren'; actionCreate='Erstellen'; actionDelete='Loeschen'
        configured='Konfiguriert'; enabled='Aktiviert'; disabled='Deaktiviert'
        darkMode='Dark Mode'; lightMode='Light Mode'
        orphanedGpos='Verwaiste GPOs'; orphanedDesc='GPOs ohne OU-Verknüpfung'; noOrphaned='Keine verwaisten GPOs gefunden.'
        orphanedFound='{0} verwaiste GPO(s) gefunden:'; loadingOrphaned='Suche verwaiste GPOs...'
        historyBtn='Änderungshistorie'; historyTitle='Änderungshistorie (letzte 90 Tage)'
        diffBtn='Vergleichen'; diffTitle='GPO-Vergleich'; diffSelectTwo='Bitte genau 2 GPOs auswählen zum Vergleichen.'
        diffOnlyIn='Nur in'; diffDifference='Unterschied'; diffSetting='Einstellung'; diffGpo1='GPO 1'; diffGpo2='GPO 2'
        conflictsTitle='Konflikterkennung'; conflictsDesc='Einstellungen die in mehreren GPOs auf gleichen OUs konfiguriert sind'
        noConflicts='Keine Konflikte erkannt.'; conflictSetting='Einstellung'; conflictGpos='Betroffene GPOs'; conflictOu='Gemeinsame OU'
        duplicatesTitle='Doppelte Einstellungen'; duplicatesDesc='Einstellungen die in mehreren GPOs konfiguriert sind'
        noDuplicates='Keine doppelten Einstellungen gefunden.'; duplicateCount='Anzahl GPOs'
        pdfExport='PDF-Export'; creatingPdf='Erstelle PDF...'; pdfError='PDF-Erstellung fehlgeschlagen (Edge/Chrome nicht gefunden)'
    }
    en = @{
        windowTitle='GPO Documentation'; domainPrefix='Domain:'; searchLabel='Search:'
        ouHeader='Organizational Units (OUs)'; refreshBtn='Refresh'; expandAllBtn='Expand All'
        gpoHeader='Group Policies (GPOs)'; selectAll='Select All'; showInherited='Show Inherited GPOs'
        statusLabel='Status:'; filterAll='All'; filterAllActive='All Enabled'; filterDisabled='Disabled'; filterPartial='Partial'
        colName='GPO Name'; colStatus='Status'; colLink='Link'; colCreated='Created'; colModified='Modified'
        exportHeader='Export Options'; formatLabel='Format:'; detailCheck='Detailed Report (GPO-XML)'; rawXmlCheck='Save Raw XML'
        outputLabel='Output Path:'; filePrefix='Filename Prefix:'; exportSelected='Export Selected'; exportAll='Export All'
        statusReady='Ready. Please select an OU.'
        allEnabled='All Enabled'; allDisabled='All Disabled'; userDisabled='User Disabled'; computerDisabled='Computer Disabled'
        linkDirect='Direct'; linkInherited='Inherited'; loading='Loading...'
        loadingOUs='Loading OUs...'; loadedOUs='OUs loaded. Please select an OU.'
        loadingGPOs='Loading GPOs for:'; loadedGPOs='GPOs loaded for:'
        expandingAll='Expanding all OUs...'; expandedAll='All OUs expanded.'
        gpoCount='{0} of {1} GPO(s)'; inheritBlocked='Inheritance Blocked'
        adError='Error connecting to Active Directory:'; adErrorTitle='AD Connection Error'
        exportComplete='Export complete!'; files='Files:'; openFolder='Open folder?'; exportSuccess='Export successful'
        noSelection='Please select at least one GPO.'; noSelectionTitle='No Selection'
        noGpos='No GPOs available.'; noGposTitle='No GPOs'
        invalidPath='The output path does not exist:'; invalidPathTitle='Invalid Path'
        exporting='Exporting'; gpos='GPO(s)'; creatingHtml='Creating HTML report...'; creatingMd='Creating Markdown report...'
        savingXml='Saving XML:'; exportError='Export error:'; exportErrorTitle='Export Error'
        filesCreated='file(s) created.'; loadError='Error loading:'; gpoLoadError='Error loading GPOs:'
        chooseFolder='Choose output folder'
        htmlTitle='GPO Documentation'; createdOn='Created on:'; domain='Domain:'; gpoCountLabel='Number of GPOs:'
        toc='Table of Contents'; ouTree='OU Structure with GPO Links'
        gpoId='GPO ID'; status='Status'; link='Link'; created='Created'; modified='Last Modified'
        linkedOUs='Linked OUs'; ouNameLabel='OU Name'; pathLabel='Path'; activeLabel='Active'; yes='Yes'; no='No'
        permissions='Permissions'; userGroup='User/Group'; permission='Permission'; typeLabel='Type'
        compSettings='Computer Settings'; userSettings='User Settings'
        settingLabel='Setting'; valueLabel='Value'
        noSettings='No settings configured.'; configDetails='Configuration Details'
        detailError='Detail report could not be generated:'
        generatedWith='Generated with GPO Documentation Tool'
        expandAllHtml='Expand All'; collapseAllHtml='Collapse All'; backToTop='↑ Back to top'
        recentlyModified='Recently modified (last 30 days)'
        actionReplace='Replace'; actionUpdate='Update'; actionCreate='Create'; actionDelete='Delete'
        configured='Configured'; enabled='Enabled'; disabled='Disabled'
        darkMode='Dark Mode'; lightMode='Light Mode'
        orphanedGpos='Orphaned GPOs'; orphanedDesc='GPOs without OU link'; noOrphaned='No orphaned GPOs found.'
        orphanedFound='{0} orphaned GPO(s) found:'; loadingOrphaned='Searching for orphaned GPOs...'
        historyBtn='Change History'; historyTitle='Change History (last 90 days)'
        diffBtn='Compare'; diffTitle='GPO Comparison'; diffSelectTwo='Please select exactly 2 GPOs to compare.'
        diffOnlyIn='Only in'; diffDifference='Difference'; diffSetting='Setting'; diffGpo1='GPO 1'; diffGpo2='GPO 2'
        conflictsTitle='Conflict Detection'; conflictsDesc='Settings configured in multiple GPOs on same OUs'
        noConflicts='No conflicts detected.'; conflictSetting='Setting'; conflictGpos='Affected GPOs'; conflictOu='Common OU'
        duplicatesTitle='Duplicate Settings'; duplicatesDesc='Settings configured in multiple GPOs'
        noDuplicates='No duplicate settings found.'; duplicateCount='Number of GPOs'
        pdfExport='PDF Export'; creatingPdf='Creating PDF...'; pdfError='PDF creation failed (Edge/Chrome not found)'
    }
}
function Set-AppLanguage { param([string]$Lang) $script:lang = $Lang; $script:L = $script:langData[$Lang] }
Set-AppLanguage $script:lang

function Get-ActionText {
    param([string]$action)
    switch ($action) {
        'R' { $script:L.actionReplace } 'U' { $script:L.actionUpdate }
        'C' { $script:L.actionCreate } 'D' { $script:L.actionDelete }
        default { $action }
    }
}
#endregion

#region XAML GUI Definition
[xml]$XAML = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="GPO-Dokumentation" Height="750" Width="1100"
    WindowStartupLocation="CenterScreen"
    Background="#F5F5F5">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="Margin" Value="4"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Background" Value="#0078D4"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#106EBE"/>
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Background" Value="#CCCCCC"/>
                    <Setter Property="Foreground" Value="#888888"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="GroupBox">
            <Setter Property="Margin" Value="6"/>
            <Setter Property="Padding" Value="6"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>
    </Window.Resources>
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,8">
            <TextBlock Name="txtTitle" Text="GPO-Dokumentation" FontSize="22" FontWeight="Bold" Foreground="#0078D4" VerticalAlignment="Center"/>
            <TextBlock Name="txtDomain" FontSize="13" Foreground="#666" VerticalAlignment="Center" Margin="20,0,0,0"/>
            <TextBlock Name="lblSearch" Text="Suche:" VerticalAlignment="Center" FontSize="12" Margin="30,0,6,0"/>
            <TextBox Name="txtSearch" Width="200" FontSize="12" VerticalAlignment="Center" Padding="4,3"/>
            <Button Name="btnSearchClear" Content="✕" FontSize="10" Padding="6,3" Margin="2,0,0,0" Background="#888"/>
            <ComboBox Name="cmbLanguage" Width="85" FontSize="11" VerticalAlignment="Center" Margin="20,0,0,0" SelectedIndex="0">
                <ComboBoxItem Content="Deutsch"/>
                <ComboBoxItem Content="English"/>
            </ComboBox>
            <Button Name="btnDarkMode" Content="🌙 Dark Mode" FontSize="11" Padding="8,3" Margin="15,0,0,0" Background="#555"/>
        </StackPanel>

        <!-- Main Content -->
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="350"/>
                <ColumnDefinition Width="5"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- OU TreeView -->
            <GroupBox Name="grpOU" Grid.Column="0" Header="Organisationseinheiten (OUs)">
                <DockPanel>
                    <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,6">
                        <Button Name="btnRefreshOU" Content="Aktualisieren" FontSize="11" Padding="8,3"/>
                        <Button Name="btnExpandAll" Content="Alle aufklappen" FontSize="11" Padding="8,3"/>
                    </StackPanel>
                    <TreeView Name="treeOU" FontSize="12" FontWeight="Normal" BorderThickness="1" BorderBrush="#CCC"/>
                </DockPanel>
            </GroupBox>

            <GridSplitter Grid.Column="1" Width="5" HorizontalAlignment="Center" VerticalAlignment="Stretch" Background="#DDD"/>

            <!-- GPO Liste -->
            <GroupBox Name="grpGPO" Grid.Column="2" Header="Gruppenrichtlinien (GPOs)">
                <DockPanel>
                    <!-- Toolbar -->
                    <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,6">
                        <CheckBox Name="chkSelectAll" Content="Alle auswählen" VerticalAlignment="Center" FontWeight="Normal" FontSize="12" Margin="4,0,10,0"/>
                        <CheckBox Name="chkIncludeInherited" Content="Vererbte GPOs anzeigen" VerticalAlignment="Center" FontWeight="Normal" FontSize="12" Margin="4,0,10,0" IsChecked="True"/>
                        <TextBlock Name="lblStatusFilter" Text="Status:" VerticalAlignment="Center" FontWeight="Normal" FontSize="12" Margin="10,0,4,0"/>
                        <ComboBox Name="cmbStatusFilter" Width="130" FontWeight="Normal" FontSize="12" SelectedIndex="0">
                            <ComboBoxItem Content="Alle"/>
                            <ComboBoxItem Content="Alle aktiv"/>
                            <ComboBoxItem Content="Deaktiviert"/>
                            <ComboBoxItem Content="Teilweise"/>
                        </ComboBox>
                        <TextBlock Name="txtGpoCount" VerticalAlignment="Center" FontWeight="Normal" FontSize="12" Foreground="#666" Margin="10,0,0,0"/>
                    </StackPanel>
                    <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,6">
                        <Button Name="btnOrphaned" Content="🔍 Verwaiste GPOs" FontSize="11" Padding="8,3" Background="#8B5E3C"/>
                        <Button Name="btnHistory" Content="🕐 Änderungshistorie" FontSize="11" Padding="8,3" Background="#5B7A3A"/>
                        <Button Name="btnDiff" Content="⚖️ Vergleichen" FontSize="11" Padding="8,3" Background="#6B5B95"/>
                    </StackPanel>
                    <!-- GPO DataGrid -->
                    <DataGrid Name="gridGPO" AutoGenerateColumns="False" CanUserAddRows="False"
                              IsReadOnly="False" SelectionMode="Single" SelectionUnit="FullRow" FontWeight="Normal" FontSize="12"
                              HeadersVisibility="Column" GridLinesVisibility="Horizontal"
                              BorderThickness="1" BorderBrush="#CCC" AlternatingRowBackground="#F9F9F9">
                        <DataGrid.RowStyle>
                            <Style TargetType="DataGridRow">
                                <Style.Triggers>
                                    <DataTrigger Binding="{Binding IsRecentlyModified}" Value="True">
                                        <Setter Property="Background" Value="#FFF8E1"/>
                                    </DataTrigger>
                                </Style.Triggers>
                            </Style>
                        </DataGrid.RowStyle>
                        <DataGrid.Columns>
                            <DataGridTemplateColumn Header="✓" Width="40">
                                <DataGridTemplateColumn.CellTemplate>
                                    <DataTemplate>
                                        <CheckBox IsChecked="{Binding Selected, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </DataTemplate>
                                </DataGridTemplateColumn.CellTemplate>
                            </DataGridTemplateColumn>
                            <DataGridTextColumn Header="GPO-Name" Binding="{Binding DisplayName}" Width="*" IsReadOnly="True"/>
                            <DataGridTextColumn Header="Status" Binding="{Binding GpoStatus}" Width="120" IsReadOnly="True">
                                <DataGridTextColumn.ElementStyle>
                                    <Style TargetType="TextBlock">
                                        <Style.Triggers>
                                            <Trigger Property="Text" Value="Alle aktiv">
                                                <Setter Property="Foreground" Value="#107C10"/>
                                                <Setter Property="FontWeight" Value="SemiBold"/>
                                            </Trigger>
                                            <Trigger Property="Text" Value="Alle deaktiviert">
                                                <Setter Property="Foreground" Value="#D13438"/>
                                                <Setter Property="FontWeight" Value="SemiBold"/>
                                            </Trigger>
                                            <Trigger Property="Text" Value="Computer deaktiviert">
                                                <Setter Property="Foreground" Value="#8A6D00"/>
                                                <Setter Property="FontWeight" Value="SemiBold"/>
                                            </Trigger>
                                            <Trigger Property="Text" Value="Benutzer deaktiviert">
                                                <Setter Property="Foreground" Value="#8A6D00"/>
                                                <Setter Property="FontWeight" Value="SemiBold"/>
                                            </Trigger>
                                            <Trigger Property="Text" Value="All Enabled">
                                                <Setter Property="Foreground" Value="#107C10"/>
                                                <Setter Property="FontWeight" Value="SemiBold"/>
                                            </Trigger>
                                            <Trigger Property="Text" Value="All Disabled">
                                                <Setter Property="Foreground" Value="#D13438"/>
                                                <Setter Property="FontWeight" Value="SemiBold"/>
                                            </Trigger>
                                            <Trigger Property="Text" Value="Computer Disabled">
                                                <Setter Property="Foreground" Value="#8A6D00"/>
                                                <Setter Property="FontWeight" Value="SemiBold"/>
                                            </Trigger>
                                            <Trigger Property="Text" Value="User Disabled">
                                                <Setter Property="Foreground" Value="#8A6D00"/>
                                                <Setter Property="FontWeight" Value="SemiBold"/>
                                            </Trigger>
                                        </Style.Triggers>
                                    </Style>
                                </DataGridTextColumn.ElementStyle>
                            </DataGridTextColumn>
                            <DataGridTextColumn Header="Verknüpfung" Binding="{Binding LinkType}" Width="90" IsReadOnly="True"/>
                            <DataGridTextColumn Header="Erstellt" Binding="{Binding CreationTime, StringFormat=\{0:dd.MM.yyyy\}}" Width="90" IsReadOnly="True"/>
                            <DataGridTextColumn Header="Geändert" Binding="{Binding ModificationTime, StringFormat=\{0:dd.MM.yyyy\}}" Width="90" IsReadOnly="True"/>
                        </DataGrid.Columns>
                    </DataGrid>
                </DockPanel>
            </GroupBox>
        </Grid>

        <!-- Export Options -->
        <GroupBox Name="grpExport" Grid.Row="2" Header="Export-Optionen">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Name="lblFormat" Text="Format:" VerticalAlignment="Center" FontWeight="Normal" FontSize="12" Margin="0,0,8,0"/>
                    <ComboBox Name="cmbFormat" Width="150" FontWeight="Normal" FontSize="12" SelectedIndex="0">
                        <ComboBoxItem Content="HTML"/>
                        <ComboBoxItem Content="Markdown"/>
                        <ComboBoxItem Content="HTML + Markdown"/>
                        <ComboBoxItem Content="PDF"/>
                    </ComboBox>
                    <CheckBox Name="chkDetailReport" Content="Detaillierter Bericht (GPO-XML)" VerticalAlignment="Center" FontWeight="Normal" FontSize="12" Margin="20,0,0,0" IsChecked="True"/>
                    <CheckBox Name="chkSaveRawXml" Content="Roh-XML speichern" VerticalAlignment="Center" FontWeight="Normal" FontSize="12" Margin="20,0,0,0"/>
                    <TextBlock Name="lblFilePrefix" Text="Dateiname-Prefix:" VerticalAlignment="Center" FontWeight="Normal" FontSize="12" Margin="20,0,8,0"/>
                    <TextBox Name="txtFilePrefix" Width="180" FontWeight="Normal" FontSize="12" VerticalAlignment="Center" Padding="4,3" Text="GPO-Dokumentation"/>
                </StackPanel>
                <StackPanel Grid.Column="2" Orientation="Horizontal">
                    <TextBlock Name="lblOutputPath" Text="Ausgabepfad:" VerticalAlignment="Center" FontWeight="Normal" FontSize="12" Margin="0,0,8,0"/>
                    <TextBox Name="txtOutputPath" Width="250" FontWeight="Normal" FontSize="12" VerticalAlignment="Center" Padding="4,3"/>
                    <Button Name="btnBrowse" Content="..." FontSize="11" Padding="8,3"/>
                </StackPanel>
                <StackPanel Grid.Column="3" Orientation="Horizontal">
                    <Button Name="btnExportSelected" Content="Ausgewählte exportieren" FontSize="12" Padding="10,6" Margin="6,4,2,4" Background="#106EBE"/>
                    <Button Name="btnExport" Content="Alle exportieren" FontSize="14" Padding="16,8" Margin="2,4,4,4"/>
                </StackPanel>
            </Grid>
        </GroupBox>

        <!-- Status Bar -->
        <StatusBar Grid.Row="3" Background="#E8E8E8" Margin="0,4,0,0">
            <StatusBarItem>
                <TextBlock Name="txtStatus" Text="Bereit. Bitte eine OU auswählen." FontSize="12"/>
            </StatusBarItem>
            <StatusBarItem HorizontalAlignment="Right">
                <StackPanel Orientation="Horizontal">
                    <ProgressBar Name="progressBar" Width="200" Height="16" Visibility="Collapsed" Margin="0,0,12,0"/>
                    <TextBlock Name="txtVersionInfo" Text="v2.1 | Rocco Ammon | github.com/RoccoAmmon/GPO-Dokumentation" FontSize="10" Foreground="#999" VerticalAlignment="Center"/>
                </StackPanel>
            </StatusBarItem>
        </StatusBar>
    </Grid>
</Window>
"@
#endregion

#region GUI laden
$reader = New-Object System.Xml.XmlNodeReader $XAML
$window = [Windows.Markup.XamlReader]::Load($reader)

# Controls referenzieren
$txtDomain         = $window.FindName("txtDomain")
$treeOU             = $window.FindName("treeOU")
$btnRefreshOU       = $window.FindName("btnRefreshOU")
$btnExpandAll       = $window.FindName("btnExpandAll")
$gridGPO            = $window.FindName("gridGPO")
$chkSelectAll       = $window.FindName("chkSelectAll")
$chkIncludeInherited= $window.FindName("chkIncludeInherited")
$cmbStatusFilter    = $window.FindName("cmbStatusFilter")
$txtGpoCount        = $window.FindName("txtGpoCount")
$txtSearch          = $window.FindName("txtSearch")
$btnSearchClear     = $window.FindName("btnSearchClear")
$cmbFormat          = $window.FindName("cmbFormat")
$chkDetailReport    = $window.FindName("chkDetailReport")
$chkSaveRawXml      = $window.FindName("chkSaveRawXml")
$txtOutputPath      = $window.FindName("txtOutputPath")
$btnBrowse          = $window.FindName("btnBrowse")
$btnExportSelected  = $window.FindName("btnExportSelected")
$btnExport          = $window.FindName("btnExport")
$txtStatus          = $window.FindName("txtStatus")
$progressBar        = $window.FindName("progressBar")
$txtTitle           = $window.FindName("txtTitle")
$lblSearch          = $window.FindName("lblSearch")
$cmbLanguage        = $window.FindName("cmbLanguage")
$grpOU              = $window.FindName("grpOU")
$grpGPO             = $window.FindName("grpGPO")
$grpExport          = $window.FindName("grpExport")
$lblStatusFilter    = $window.FindName("lblStatusFilter")
$lblFormat          = $window.FindName("lblFormat")
$lblOutputPath      = $window.FindName("lblOutputPath")
$lblFilePrefix      = $window.FindName("lblFilePrefix")
$txtFilePrefix      = $window.FindName("txtFilePrefix")
$btnDarkMode        = $window.FindName("btnDarkMode")
$btnOrphaned        = $window.FindName("btnOrphaned")
$btnHistory         = $window.FindName("btnHistory")
$btnDiff            = $window.FindName("btnDiff")

# Sprache initialisieren
if ($script:lang -eq 'en') { $cmbLanguage.SelectedIndex = 1 }
#endregion

#region Hilfsklasse für GPO-Daten
Add-Type -Language CSharp @"
using System;
using System.ComponentModel;
public class GpoItem : INotifyPropertyChanged
{
    private bool _selected;
    public bool Selected
    {
        get { return _selected; }
        set { _selected = value; OnPropertyChanged("Selected"); }
    }
    public string DisplayName { get; set; }
    public Guid Id { get; set; }
    public string GpoStatusKey { get; set; }
    public string GpoStatus { get; set; }
    public string LinkType { get; set; }
    public DateTime CreationTime { get; set; }
    public DateTime ModificationTime { get; set; }
    public bool IsRecentlyModified { get; set; }
    public string DomainName { get; set; }

    public event PropertyChangedEventHandler PropertyChanged;
    protected void OnPropertyChanged(string name)
    {
        if (PropertyChanged != null)
            PropertyChanged(this, new PropertyChangedEventArgs(name));
    }
}
"@
#endregion

#region Funktionen

# Globale Variablen
$script:allGpoItems = $null
$script:gpoSearchCache = @{}
$script:gpoSearchCacheBuilt = $false

function Apply-Language {
    $L = $script:L
    $window.Title = $L.windowTitle
    $txtTitle.Text = $L.windowTitle
    $lblSearch.Text = $L.searchLabel
    $grpOU.Header = $L.ouHeader
    $btnRefreshOU.Content = $L.refreshBtn
    $btnExpandAll.Content = $L.expandAllBtn
    $grpGPO.Header = $L.gpoHeader
    $chkSelectAll.Content = $L.selectAll
    $chkIncludeInherited.Content = $L.showInherited
    $lblStatusFilter.Text = $L.statusLabel
    $cmbStatusFilter.Items[0].Content = $L.filterAll
    $cmbStatusFilter.Items[1].Content = $L.filterAllActive
    $cmbStatusFilter.Items[2].Content = $L.filterDisabled
    $cmbStatusFilter.Items[3].Content = $L.filterPartial
    $gridGPO.Columns[1].Header = $L.colName
    $gridGPO.Columns[2].Header = $L.colStatus
    $gridGPO.Columns[3].Header = $L.colLink
    $gridGPO.Columns[4].Header = $L.colCreated
    $gridGPO.Columns[5].Header = $L.colModified
    $grpExport.Header = $L.exportHeader
    $lblFormat.Text = $L.formatLabel
    $chkDetailReport.Content = $L.detailCheck
    $chkSaveRawXml.Content = $L.rawXmlCheck
    $lblOutputPath.Text = $L.outputLabel
    $lblFilePrefix.Text = $L.filePrefix
    $txtFilePrefix.Text = $L.htmlTitle
    $btnExportSelected.Content = $L.exportSelected
    $btnExport.Content = $L.exportAll
    $txtStatus.Text = $L.statusReady
    $btnDarkMode.Content = if ($script:isDarkMode) { "☀️ $($L.lightMode)" } else { "🌙 $($L.darkMode)" }
    $btnOrphaned.Content = "🔍 $($L.orphanedGpos)"
    $btnHistory.Content = "🕐 $($L.historyBtn)"
    $btnDiff.Content = "⚖️ $($L.diffBtn)"
    # GPO-Status-Texte aktualisieren
    if ($script:allGpoItems) {
        $directVals = @('Direkt','Direct')
        foreach ($item in $script:allGpoItems) {
            $item.GpoStatus = switch ($item.GpoStatusKey) {
                'AllSettingsEnabled'       { $L.allEnabled }
                'AllSettingsDisabled'      { $L.allDisabled }
                'UserSettingsDisabled'     { $L.userDisabled }
                'ComputerSettingsDisabled' { $L.computerDisabled }
                default                    { $item.GpoStatusKey }
            }
            $item.LinkType = if ($item.LinkType -in $directVals) { $L.linkDirect } else { $L.linkInherited }
        }
        Update-GpoFilter
    }
}

function Set-Status {
    param([string]$Message)
    $txtStatus.Text = $Message
    $window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [Action]{})
}

function Update-GpoFilter {
    <#
    .SYNOPSIS
        Filtert die GPO-Liste nach Suchtext und Status.
    #>
    if (-not $script:allGpoItems) { return }

    $searchText = $txtSearch.Text.Trim()
    $statusIdx = $cmbStatusFilter.SelectedIndex

    $filtered = [System.Collections.ObjectModel.ObservableCollection[GpoItem]]::new()
    foreach ($item in $script:allGpoItems) {
        # Status-Filter (key-basiert)
        $statusMatch = switch ($statusIdx) {
            0 { $true }
            1 { $item.GpoStatusKey -eq 'AllSettingsEnabled' }
            2 { $item.GpoStatusKey -match 'Disabled' }
            3 { $item.GpoStatusKey -in @('UserSettingsDisabled','ComputerSettingsDisabled') }
            default { $true }
        }
        if (-not $statusMatch) { continue }

        # Suchtext-Filter (Name + Einstellungswerte ab 3 Zeichen)
        if ($searchText) {
            $escaped = [regex]::Escape($searchText)
            if ($item.DisplayName -notmatch $escaped) {
                # Wertsuche erst ab 3 Zeichen (vermeidet versehentliches Cache-Laden)
                if ($searchText.Length -lt 3) { continue }
                # Lazy-Cache: XML erst beim ersten Suchen laden
                if (-not $script:gpoSearchCacheBuilt) {
                    $window.Cursor = [System.Windows.Input.Cursors]::Wait
                    $progressBar.Visibility = "Visible"
                    $progressBar.IsIndeterminate = $true
                    Set-Status "$($script:L.searchLabel) Cache ($($script:allGpoItems.Count) GPOs)..."
                    $window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [Action]{})
                    foreach ($g in $script:allGpoItems) {
                        if (-not $script:gpoSearchCache.ContainsKey($g.Id)) {
                            try { $script:gpoSearchCache[$g.Id] = (Get-GPOReport -Guid $g.Id -ReportType Xml) } catch {}
                        }
                    }
                    $script:gpoSearchCacheBuilt = $true
                    $progressBar.Visibility = "Collapsed"
                    $window.Cursor = $null
                    Set-Status $script:L.statusReady
                }
                $xmlText = $script:gpoSearchCache[$item.Id]
                if (-not $xmlText -or $xmlText -notmatch $escaped) { continue }
            }
        }

        $filtered.Add($item)
    }

    $gridGPO.ItemsSource = $filtered
    $txtGpoCount.Text = ($script:L.gpoCount -f $filtered.Count, $script:allGpoItems.Count)
}

function Get-DomainInfo {
    try {
        $domain = Get-ADDomain
        $txtDomain.Text = "$($script:L.domainPrefix) $($domain.DNSRoot)"
        return $domain
    } catch {
        [System.Windows.MessageBox]::Show(
            "$($script:L.adError)`n$($_.Exception.Message)",
            $script:L.adErrorTitle, "OK", "Error")
        return $null
    }
}

function Add-OUTreeNode {
    param(
        [string]$ParentDN,
        [System.Windows.Controls.ItemCollection]$ParentItems
    )

    $ous = Get-ADOrganizationalUnit -Filter * -SearchBase $ParentDN -SearchScope OneLevel -Properties Name, DistinguishedName, gPOptions |
           Sort-Object Name

    foreach ($ou in $ous) {
        $item = New-Object System.Windows.Controls.TreeViewItem
        $isBlocked = ($ou.gPOptions -eq 1)
        $headerText = if ($isBlocked) { "[OU] $($ou.Name) 🚫 $($script:L.inheritBlocked)" } else { "[OU] $($ou.Name)" }
        $item.Header = $headerText
        $item.Tag = $ou.DistinguishedName
        $item.FontWeight = "Normal"
        $item.FontSize = 12
        if ($isBlocked) { $item.Foreground = [System.Windows.Media.Brushes]::OrangeRed }

        # Placeholder für Lazy-Loading
        $placeholder = New-Object System.Windows.Controls.TreeViewItem
        $placeholder.Header = $script:L.loading
        $item.Items.Add($placeholder) | Out-Null

        $item.Add_Expanded({
            param($sender, $e)
            $treeItem = $sender
            if ($treeItem.Items.Count -eq 1 -and $treeItem.Items[0].Header -match '^(Laden|Loading)') {
                $treeItem.Items.Clear()
                Add-OUTreeNode -ParentDN $treeItem.Tag -ParentItems $treeItem.Items
            }
        })

        $ParentItems.Add($item) | Out-Null
    }
}

function Load-OUTree {
    Set-Status $script:L.loadingOUs
    $treeOU.Items.Clear()

    $domain = Get-DomainInfo
    if (-not $domain) { return }

    # Domain-Root als ersten Eintrag
    $rootItem = New-Object System.Windows.Controls.TreeViewItem
    $rootItem.Header = "[Domain] $($domain.DNSRoot)"
    $rootItem.Tag = $domain.DistinguishedName
    $rootItem.FontWeight = "SemiBold"
    $rootItem.FontSize = 13
    $rootItem.IsExpanded = $true

    Add-OUTreeNode -ParentDN $domain.DistinguishedName -ParentItems $rootItem.Items
    $treeOU.Items.Add($rootItem) | Out-Null

    Set-Status $script:L.loadedOUs
}

function Get-LinkedGPOs {
    param(
        [string]$OU_DN,
        [bool]$IncludeInherited = $true
    )

    $gpoItems = [System.Collections.ObjectModel.ObservableCollection[GpoItem]]::new()

    try {
        # Direkt verknüpfte GPOs
        $inheritance = Get-GPInheritance -Target $OU_DN

        foreach ($link in $inheritance.GpoLinks) {
            $gpo = Get-GPO -Guid $link.GpoId -ErrorAction SilentlyContinue
            if ($gpo) {
                $item = New-Object GpoItem
                $item.Selected = $false
                $item.DisplayName = $gpo.DisplayName
                $item.Id = $gpo.Id
                $item.GpoStatusKey = $gpo.GpoStatus.ToString()
                $item.GpoStatus = switch ($gpo.GpoStatus) {
                    "AllSettingsEnabled"        { $script:L.allEnabled }
                    "AllSettingsDisabled"        { $script:L.allDisabled }
                    "UserSettingsDisabled"       { $script:L.userDisabled }
                    "ComputerSettingsDisabled"   { $script:L.computerDisabled }
                    default                      { $gpo.GpoStatus }
                }
                $item.LinkType = $script:L.linkDirect
                $item.CreationTime = $gpo.CreationTime
                $item.ModificationTime = $gpo.ModificationTime
                $item.IsRecentlyModified = ($gpo.ModificationTime -gt (Get-Date).AddDays(-30))
                $item.DomainName = $gpo.DomainName
                $gpoItems.Add($item)
            }
        }

        # Vererbte GPOs
        if ($IncludeInherited) {
            foreach ($inheritedLink in $inheritance.InheritedGpoLinks) {
                $alreadyAdded = $gpoItems | Where-Object { $_.Id -eq $inheritedLink.GpoId }
                if (-not $alreadyAdded) {
                    $gpo = Get-GPO -Guid $inheritedLink.GpoId -ErrorAction SilentlyContinue
                    if ($gpo) {
                        $item = New-Object GpoItem
                        $item.Selected = $false
                        $item.DisplayName = $gpo.DisplayName
                        $item.Id = $gpo.Id
                        $item.GpoStatusKey = $gpo.GpoStatus.ToString()
                        $item.GpoStatus = switch ($gpo.GpoStatus) {
                            "AllSettingsEnabled"        { $script:L.allEnabled }
                            "AllSettingsDisabled"        { $script:L.allDisabled }
                            "UserSettingsDisabled"       { $script:L.userDisabled }
                            "ComputerSettingsDisabled"   { $script:L.computerDisabled }
                            default                      { $gpo.GpoStatus }
                        }
                        $item.LinkType = $script:L.linkInherited
                        $item.CreationTime = $gpo.CreationTime
                        $item.ModificationTime = $gpo.ModificationTime
                        $item.IsRecentlyModified = ($gpo.ModificationTime -gt (Get-Date).AddDays(-30))
                        $item.DomainName = $gpo.DomainName
                        $gpoItems.Add($item)
                    }
                }
            }
        }
    } catch {
        Set-Status "$($script:L.gpoLoadError) $($_.Exception.Message)"
    }

    return $gpoItems
}

function Get-GPOSettingsFromXml {
    <#
    .SYNOPSIS
        Extrahiert alle Einstellungen aus einem GPO-XML-Report als flache Liste.
    #>
    param($ExtensionData)

    $extArray = @($ExtensionData)
    $results = @()

    foreach ($ext in $extArray) {
        $extName = $ext.Name
        $settings = @()
        $extension = $ext.Extension
        $seenKeys = @{}

        foreach ($node in $extension.ChildNodes) {
            if ($node -isnot [System.Xml.XmlElement]) { continue }
            $parsed = @(Parse-SettingNode -Node $node)
            if ($parsed.Count -gt 0) {
                foreach ($entry in $parsed) {
                    $dedupKey = "$($entry.Name)|$($entry.Value)"
                    if (-not $seenKeys.ContainsKey($dedupKey)) {
                        $seenKeys[$dedupKey] = $true
                        $settings += $entry
                    }
                }
            }
        }

        if ($settings.Count -gt 0) {
            $results += [PSCustomObject]@{
                ExtensionName = $extName
                Settings = $settings
            }
        }
    }

    return $results
}

function Get-GPOLinksFromXml {
    <#
    .SYNOPSIS
        Extrahiert die OUs/Verknüpfungen aus dem GPO-XML-Report.
    #>
    param([System.Xml.XmlDocument]$ReportXml)

    $links = @()
    $linksTo = $ReportXml.GPO.LinksTo
    if ($linksTo) {
        foreach ($link in @($linksTo)) {
            $links += [PSCustomObject]@{
                Name    = $link.SOMName
                Path    = $link.SOMPath
                Enabled = $link.Enabled
            }
        }
    }
    return $links
}

function Get-GPOPermissionsFromXml {
    <#
    .SYNOPSIS
        Extrahiert die relevanten Berechtigungen (Apply Group Policy) aus dem GPO-XML-Report.
    #>
    param([System.Xml.XmlDocument]$ReportXml)

    $permissions = @()
    $secDesc = $ReportXml.GPO.SecurityDescriptor
    if ($secDesc) {
        $permNodes = $secDesc.Permissions.TrusteePermissions
        if ($permNodes) {
            foreach ($perm in @($permNodes)) {
                $trusteeName = $perm.Trustee.Name.'#text'
                if (-not $trusteeName) { $trusteeName = $perm.Trustee.Name }
                if (-not $trusteeName) { $trusteeName = $perm.Trustee.SID.'#text' }

                $permType = ""
                if ($perm.Standard) {
                    $permType = $perm.Standard.GPOGroupedAccessEnum
                }

                $permissions += [PSCustomObject]@{
                    Trustee    = $trusteeName
                    Permission = $permType
                    Type       = if ($perm.Type) { $perm.Type.PermissionType } else { "-" }
                }
            }
        }
    }
    return $permissions
}

function Parse-SettingNode {
    <#
    .SYNOPSIS
        Parst einen XML-Knoten aus einem GPO-Report und extrahiert Name/Wert-Paare.
    #>
    param([System.Xml.XmlElement]$Node)

    $localName = $Node.LocalName
    $entries = @()

    # === Blocked-Knoten ignorieren (kommt als Geschwister von Policy vor) ===
    if ($localName -eq 'Blocked') { return $entries }

    # === GPP Registry Settings (Windows Registry Extension) ===
    # Container: RegistrySettings > Registry > Properties
    if ($localName -eq 'RegistrySettings') {
        $registryNodes = $Node.SelectNodes('.//*[local-name()="Registry"]')
        foreach ($reg in $registryNodes) {
            $props = $reg.SelectSingleNode('*[local-name()="Properties"]')
            if ($props) {
                $hive = $props.GetAttribute('hive')
                $key = $props.GetAttribute('key')
                $name = $props.GetAttribute('name')
                $type = $props.GetAttribute('type')
                $value = $props.GetAttribute('value')
                $action = $props.GetAttribute('action')

                # Aktion übersetzen
                $actionText = Get-ActionText $action

                # Kurzer Hive-Name
                $hiveShort = switch ($hive) {
                    'HKEY_CURRENT_USER'  { 'HKCU' }
                    'HKEY_LOCAL_MACHINE' { 'HKLM' }
                    'HKEY_CLASSES_ROOT'  { 'HKCR' }
                    'HKEY_USERS'         { 'HKU' }
                    default              { $hive }
                }

                $fullPath = "$hiveShort\$key"
                if ($name) { $fullPath += "\$name" }

                # Wert kürzen wenn zu lang
                $displayValue = $value
                if ($displayValue -and $displayValue.Length -gt 80) {
                    $displayValue = $displayValue.Substring(0, 77) + "..."
                }

                $valueText = "Typ: $type"
                if ($displayValue) { $valueText += " | Wert: $displayValue" }
                $valueText += " | Aktion: $actionText"

                $entries += [PSCustomObject]@{ Name = $fullPath; Value = $valueText }
            } else {
                # Fallback: Attribute des Registry-Knotens
                $regName = $reg.GetAttribute('name')
                $regDescr = $reg.GetAttribute('descr')
                $displayName = if ($regDescr) { $regDescr } elseif ($regName) { $regName } else { "Registry" }
                $entries += [PSCustomObject]@{ Name = $displayName; Value = $script:L.configured }
            }
        }
        if ($entries.Count -eq 0) {
            $entries += [PSCustomObject]@{ Name = "RegistrySettings"; Value = $script:L.configured }
        }
        return $entries
    }

    # === Account-Knoten (Password/Lockout/Kerberos): Flat-Liste von Name/SettingXxx/Type Triplets ===
    if ($localName -eq 'Account') {
        $children = @($Node.ChildNodes | Where-Object { $_ -is [System.Xml.XmlElement] })
        $i = 0
        while ($i -lt $children.Count) {
            $child = $children[$i]
            $childName = $child.LocalName

            # Wenn das Kind selbst ein Container ist (z.B. PasswordPolicies, LockoutPolicies)
            if ($child.HasChildNodes -and $child.SelectSingleNode('*[local-name()="Name"]')) {
                $nameEl = $child.SelectSingleNode('*[local-name()="Name"]')
                $sName = if ($nameEl) { $nameEl.InnerText } else { $childName }
                $sValue = "-"

                $numEl = $child.SelectSingleNode('*[local-name()="SettingNumber"]')
                $boolEl = $child.SelectSingleNode('*[local-name()="SettingBoolean"]')
                $strEl = $child.SelectSingleNode('*[local-name()="SettingString"]')

                if ($numEl) { $sValue = $numEl.InnerText }
                elseif ($boolEl) { $sValue = if ($boolEl.InnerText -eq 'true') { $script:L.enabled } else { $script:L.disabled } }
                elseif ($strEl) { $sValue = $strEl.InnerText }

                $entries += [PSCustomObject]@{ Name = $sName; Value = $sValue }
                $i++
                continue
            }

            # Flat-Triplets: Name, SettingXxx, Type
            if ($childName -eq 'Name') {
                $sName = $child.InnerText
                $sValue = "-"

                # Nächstes Element = Wert
                if (($i + 1) -lt $children.Count) {
                    $valChild = $children[$i + 1]
                    $valName = $valChild.LocalName
                    if ($valName -eq 'SettingNumber') { $sValue = $valChild.InnerText }
                    elseif ($valName -eq 'SettingBoolean') { $sValue = if ($valChild.InnerText -eq 'true') { $script:L.enabled } else { $script:L.disabled } }
                    elseif ($valName -eq 'SettingString') { $sValue = $valChild.InnerText }
                }

                $entries += [PSCustomObject]@{ Name = $sName; Value = $sValue }

                # Überspringe SettingXxx und Type
                $i += 3
                continue
            }

            $i++
        }
        return $entries
    }

    # === SecurityOptions ===
    if ($localName -eq 'SecurityOptions') {
        $sName = $null
        $sValue = $null

        $sysAccess = $Node.SelectSingleNode('*[local-name()="SystemAccessPolicyName"]')
        $keyNode = $Node.SelectSingleNode('*[local-name()="KeyName"]')
        $displayNode = $Node.SelectSingleNode('*[local-name()="Display"]')

        if ($sysAccess) { $sName = $sysAccess.InnerText }
        elseif ($keyNode) { $sName = $keyNode.InnerText }

        # Display enthält benutzerfreundlichen Namen
        if ($displayNode) {
            $dispName = $displayNode.SelectSingleNode('*[local-name()="Name"]')
            $dispUnits = $displayNode.SelectSingleNode('*[local-name()="Units"]')
            if ($dispName) {
                $displayText = $dispName.InnerText
                if ($dispUnits) { $displayText += " ($($dispUnits.InnerText))" }
                if (-not $sName) { $sName = $displayText }
            }
        }

        $numEl = $Node.SelectSingleNode('*[local-name()="SettingNumber"]')
        $strEl = $Node.SelectSingleNode('*[local-name()="SettingString"]')
        $boolEl = $Node.SelectSingleNode('*[local-name()="SettingBoolean"]')

        if ($numEl) { $sValue = $numEl.InnerText }
        elseif ($strEl) { $sValue = $strEl.InnerText }
        elseif ($boolEl) { $sValue = if ($boolEl.InnerText -eq 'true') { $script:L.enabled } else { $script:L.disabled } }

        if ($displayNode -and $sValue) {
            $dispName = $displayNode.SelectSingleNode('*[local-name()="Name"]')
            if ($dispName) { $sValue = "$sValue ($($dispName.InnerText))" }
        }

        if (-not $sName) { $sName = $localName }
        if (-not $sValue) { $sValue = "-" }

        $entries += [PSCustomObject]@{ Name = $sName; Value = $sValue }
        return $entries
    }

    # === RegistrySetting (Security-Extension: Registry-ACLs) ===
    if ($localName -eq 'RegistrySetting') {
        $sName = $null
        $sValue = $null

        # Security-Extension Registry hat Path + SecurityDescriptor
        $pathNode = $Node.SelectSingleNode('*[local-name()="Path"]')
        $sddlNode = $Node.SelectSingleNode('.//*[local-name()="SDDL"]')

        if ($pathNode) {
            $sName = $pathNode.InnerText

            if ($sddlNode) {
                $sValue = "$($script:L.permissions) $($script:L.configured)"
            } else {
                $sValue = $script:L.configured
            }

            $entries += [PSCustomObject]@{ Name = $sName; Value = $sValue }
            return $entries
        }

        # Registry-Extension: KeyPath/KeyName + ValueName + Value
        $keyPath = $Node.SelectSingleNode('*[local-name()="KeyPath"]')
        $keyName = $Node.SelectSingleNode('*[local-name()="KeyName"]')
        $valueName = $Node.SelectSingleNode('*[local-name()="ValueName"]')
        $valueNode = $Node.SelectSingleNode('*[local-name()="Value"]')

        $key = if ($keyPath) { $keyPath.InnerText } elseif ($keyName) { $keyName.InnerText } else { $null }

        if ($valueName -and $valueName.InnerText) {
            $sName = if ($key) { "$key\$($valueName.InnerText)" } else { $valueName.InnerText }
        } elseif ($key) {
            $sName = $key
        }

        if ($valueNode) {
            $numNode = $valueNode.SelectSingleNode('*[local-name()="Number"]')
            $strNode = $valueNode.SelectSingleNode('*[local-name()="String"]')
            if ($numNode) { $sValue = $numNode.InnerText }
            elseif ($strNode) { $sValue = $strNode.InnerText }
            else { $sValue = $valueNode.InnerText.Trim() }
        }

        if (-not $sName) { $sName = "RegistrySetting" }
        if (-not $sValue) { $sValue = "-" }

        $entries += [PSCustomObject]@{ Name = $sName; Value = $sValue }
        return $entries
    }

    # === Policy (Administrative Vorlagen via Registry) ===
    if ($localName -eq 'Policy') {
        $sName = $null
        $sValue = $null

        $nameNode = $Node.SelectSingleNode('*[local-name()="Name"]')
        $stateNode = $Node.SelectSingleNode('*[local-name()="State"]')
        $categoryNode = $Node.SelectSingleNode('*[local-name()="Category"]')

        if ($nameNode) { $sName = $nameNode.InnerText }
        if ($stateNode) { $sValue = $stateNode.InnerText }
        if ($categoryNode -and $sName) { $sName = "$($categoryNode.InnerText) > $sName" }

        # Konfigurierte Werte aus DropDownList, EditText, Numeric, CheckBox extrahieren
        $valueParts = @()

        # DropDownList (case-sensitive: DropDownList im XML)
        $dropdowns = $Node.SelectNodes('*[local-name()="DropDownList"] | .//*[local-name()="DropDownList"] | .//*[local-name()="DropdownList"]')
        foreach ($dd in $dropdowns) {
            $ddName = $dd.SelectSingleNode('*[local-name()="Name"]')
            $ddValue = $dd.SelectSingleNode('*[local-name()="Value"]')
            if ($ddValue) {
                $ddNameVal = $ddValue.SelectSingleNode('*[local-name()="Name"]')
                $ddNum = $ddValue.SelectSingleNode('*[local-name()="Number"]')
                $ddStr = $ddValue.SelectSingleNode('*[local-name()="String"]')
                $ddData = $null
                if ($ddNameVal -and $ddNameVal.InnerText) { $ddData = $ddNameVal.InnerText }
                elseif ($ddStr -and $ddStr.InnerText) { $ddData = $ddStr.InnerText }
                elseif ($ddNum) { $ddData = $ddNum.InnerText }
                if (-not $ddData -and $ddValue.InnerText.Trim()) { $ddData = $ddValue.InnerText.Trim() }
                if ($ddName -and $ddData) { $valueParts += "$($ddName.InnerText): $ddData" }
                elseif ($ddData) { $valueParts += $ddData }
            }
        }

        # EditText (Textfelder mit Pfaden, Strings etc.)
        $editTexts = $Node.SelectNodes('*[local-name()="EditText"] | .//*[local-name()="EditText"]')
        foreach ($et in $editTexts) {
            $etName = $et.SelectSingleNode('*[local-name()="Name"]')
            $etValue = $et.SelectSingleNode('*[local-name()="Value"]')
            if ($etValue) {
                $etStr = $etValue.SelectSingleNode('*[local-name()="String"]')
                $etNum = $etValue.SelectSingleNode('*[local-name()="Number"]')
                $etData = $null
                if ($etStr -and $etStr.InnerText) { $etData = $etStr.InnerText }
                elseif ($etNum) { $etData = $etNum.InnerText }
                # Fallback: Value ist Plain-Text ohne Kindelemente
                if (-not $etData -and $etValue.InnerText.Trim()) { $etData = $etValue.InnerText.Trim() }
                if ($etName -and $etData) { $valueParts += "$($etName.InnerText): $etData" }
                elseif ($etData) { $valueParts += $etData }
            }
        }

        # Numeric (Zahlenwerte)
        $numerics = $Node.SelectNodes('*[local-name()="Numeric"] | .//*[local-name()="Numeric"]')
        foreach ($nf in $numerics) {
            $nfName = $nf.SelectSingleNode('*[local-name()="Name"]')
            $nfValue = $nf.SelectSingleNode('*[local-name()="Value"]')
            if ($nfValue) {
                $nfNum = $nfValue.SelectSingleNode('*[local-name()="Number"]')
                $nfStr = $nfValue.SelectSingleNode('*[local-name()="String"]')
                $nfData = $null
                if ($nfNum) { $nfData = $nfNum.InnerText }
                elseif ($nfStr) { $nfData = $nfStr.InnerText }
                if ($nfName -and $nfData) { $valueParts += "$($nfName.InnerText): $nfData" }
                elseif ($nfData) { $valueParts += $nfData }
            }
        }

        # CheckBox
        $checkboxes = $Node.SelectNodes('*[local-name()="CheckBox"] | .//*[local-name()="CheckBox"]')
        foreach ($cb in $checkboxes) {
            $cbName = $cb.SelectSingleNode('*[local-name()="Name"]')
            $cbValue = $cb.SelectSingleNode('*[local-name()="Value"]')
            $cbState = $cb.SelectSingleNode('*[local-name()="State"]')
            if ($cbName) {
                $cbDisplayState = $null
                if ($cbValue) {
                    $cbNum = $cbValue.SelectSingleNode('*[local-name()="Number"]')
                    if ($cbNum) {
                    $cbDisplayState = if ($cbNum.InnerText -eq '1') { $script:L.enabled } else { $script:L.disabled }
                    }
                }
                if (-not $cbDisplayState -and $cbState) {
                    $cbDisplayState = switch ($cbState.InnerText) {
                        'Enabled' { $script:L.enabled }
                        'Disabled' { $script:L.disabled }
                        default { $cbState.InnerText }
                    }
                }
                if ($cbDisplayState) {
                    $valueParts += "$($cbName.InnerText): $cbDisplayState"
                }
            }
        }

        # ListBox (z.B. Site2Zone-Zuweisungen, Listen mit Key=Value)
        $listBoxes = $Node.SelectNodes('*[local-name()="ListBox"] | .//*[local-name()="ListBox"]')
        foreach ($lb in $listBoxes) {
            $lbName = $lb.SelectSingleNode('*[local-name()="Name"]')
            $lbValue = $lb.SelectSingleNode('*[local-name()="Value"]')
            if ($lbValue) {
                $elements = $lbValue.SelectNodes('*[local-name()="Element"]')
                $listParts = @()
                foreach ($el in $elements) {
                    $elName = $el.SelectSingleNode('*[local-name()="Name"]')
                    $elData = $el.SelectSingleNode('*[local-name()="Data"]')
                    if ($elName -and $elData) {
                        $listParts += "$($elName.InnerText)=$($elData.InnerText)"
                    } elseif ($elName) {
                        $listParts += $elName.InnerText
                    }
                }
                if ($listParts.Count -gt 0) {
                    $listLabel = if ($lbName) { $lbName.InnerText } else { 'Liste' }
                    $valueParts += "$listLabel`: $($listParts -join ', ')"
                }
            }
        }

        # Werte an Status anhängen
        if ($valueParts.Count -gt 0) {
            $uniqueParts = $valueParts | Select-Object -Unique
            $configValues = ($uniqueParts | Where-Object { $_ }) -join "; "
            if ($configValues) {
                $sValue = "$sValue ($configValues)"
            }
        }

        if (-not $sName) { $sName = "Policy" }
        if (-not $sValue) { $sValue = "-" }

        $entries += [PSCustomObject]@{ Name = $sName; Value = $sValue }
        return $entries
    }

    # === GPP FilesSettings ===
    if ($localName -eq 'FilesSettings') {
        $fileNodes = $Node.SelectNodes('.//*[local-name()="File"]')
        foreach ($file in $fileNodes) {
            $props = $file.SelectSingleNode('*[local-name()="Properties"]')
            $desc = $file.GetAttribute('desc')
            if ($props) {
                $action = $props.GetAttribute('action')
                $fromPath = $props.GetAttribute('fromPath')
                $targetPath = $props.GetAttribute('targetPath')

                $actionText = Get-ActionText $action

                $sName = if ($targetPath) { $targetPath } else { "Datei" }
                $parts = @("Aktion: $actionText")
                if ($fromPath) { $parts += "Quelle: $fromPath" }
                if ($desc) { $parts += "Beschreibung: $desc" }
                $sValue = $parts -join " | "

                $entries += [PSCustomObject]@{ Name = $sName; Value = $sValue }
            }
        }
        if ($entries.Count -eq 0) {
            $entries += [PSCustomObject]@{ Name = "FilesSettings"; Value = $script:L.configured }
        }
        return $entries
    }

    # === GPP FoldersSettings ===
    if ($localName -eq 'FoldersSettings' -or $localName -eq 'Folders') {
        $folderNodes = $Node.SelectNodes('.//*[local-name()="Folder"]')
        foreach ($folder in $folderNodes) {
            $props = $folder.SelectSingleNode('*[local-name()="Properties"]')
            $desc = $folder.GetAttribute('desc')
            if ($props) {
                $action = $props.GetAttribute('action')
                $path = $props.GetAttribute('path')

                $actionText = Get-ActionText $action

                $sName = if ($path) { $path } else { "Ordner" }
                $parts = @("Aktion: $actionText")
                if ($desc) { $parts += "Beschreibung: $desc" }
                $sValue = $parts -join " | "

                $entries += [PSCustomObject]@{ Name = $sName; Value = $sValue }
            }
        }
        if ($entries.Count -eq 0) {
            $entries += [PSCustomObject]@{ Name = "FoldersSettings"; Value = $script:L.configured }
        }
        return $entries
    }

    # === GPP Scripts (Startup/Shutdown/Logon/Logoff) ===
    if ($localName -eq 'Script') {
        $cmdNode = $Node.SelectSingleNode('*[local-name()="Command"]')
        $paramNode = $Node.SelectSingleNode('*[local-name()="Parameters"]')
        $typeNode = $Node.SelectSingleNode('*[local-name()="Type"]')
        $orderNode = $Node.SelectSingleNode('*[local-name()="Order"]')
        $runOrderNode = $Node.SelectSingleNode('*[local-name()="RunOrder"]')

        $scriptType = if ($typeNode) { $typeNode.InnerText } else { 'Script' }
        $cmd = if ($cmdNode) { $cmdNode.InnerText } else { '-' }
        $parts = @("Typ: $scriptType")
        if ($paramNode -and $paramNode.InnerText) { $parts += "Parameter: $($paramNode.InnerText)" }
        if ($runOrderNode -and $runOrderNode.InnerText) { $parts += "Reihenfolge: $($runOrderNode.InnerText)" }

        $entries += [PSCustomObject]@{ Name = $cmd; Value = ($parts -join ' | ') }
        return $entries
    }

    # === GPP ScheduledTasks ===
    if ($localName -eq 'ScheduledTasks') {
        $tasks = $Node.SelectNodes('.//*[local-name()="TaskV2"] | .//*[local-name()="ImmediateTaskV2"]')
        foreach ($task in $tasks) {
            $taskName = $task.GetAttribute('name')
            $taskDisabled = $task.GetAttribute('disabled')
            $taskDesc = $task.GetAttribute('desc')
            $props = $task.SelectSingleNode('*[local-name()="Properties"]')

            $parts = @()
            if ($taskDisabled -eq '1') { $parts += 'Deaktiviert' }
            $runAs = if ($props) { $props.GetAttribute('runAs') } else { $null }
            if ($runAs) { $parts += "Ausfuehren als: $runAs" }

            # Command extrahieren
            $execCmd = $task.SelectSingleNode('.//*[local-name()="Command"]')
            $execArgs = $task.SelectSingleNode('.//*[local-name()="Arguments"]')
            if ($execCmd) { $parts += "Befehl: $($execCmd.InnerText)" }
            if ($execArgs -and $execArgs.InnerText) { $parts += "Argumente: $($execArgs.InnerText)" }

            # Trigger-Info
            $triggers = $task.SelectNodes('.//*[local-name()="CalendarTrigger"] | .//*[local-name()="LogonTrigger"] | .//*[local-name()="BootTrigger"]')
            if ($triggers.Count -gt 0) {
                $triggerInfo = $triggers[0].LocalName
                $startBound = $triggers[0].SelectSingleNode('*[local-name()="StartBoundary"]')
                if ($startBound) { $triggerInfo += " ($($startBound.InnerText))" }
                $parts += "Trigger: $triggerInfo"
            }

            if (-not $taskName) { $taskName = 'Geplanter Task' }
            $sValue = if ($parts.Count -gt 0) { $parts -join ' | ' } else { 'Konfiguriert' }
            $entries += [PSCustomObject]@{ Name = $taskName; Value = $sValue }
        }
        if ($entries.Count -eq 0) {
            $entries += [PSCustomObject]@{ Name = 'ScheduledTasks'; Value = $script:L.configured }
        }
        return $entries
    }

    # === GPP EnvironmentVariables ===
    if ($localName -eq 'EnvironmentVariables') {
        $envVars = $Node.SelectNodes('.//*[local-name()="EnvironmentVariable"]')
        foreach ($ev in $envVars) {
            $props = $ev.SelectSingleNode('*[local-name()="Properties"]')
            if ($props) {
                $evName = $props.GetAttribute('name')
                $evValue = $props.GetAttribute('value')
                $evAction = $props.GetAttribute('action')
                $actionText = Get-ActionText $evAction
                $sValue = "$evValue ($actionText)"
                $entries += [PSCustomObject]@{ Name = $evName; Value = $sValue }
            }
        }
        if ($entries.Count -eq 0) {
            $entries += [PSCustomObject]@{ Name = 'EnvironmentVariables'; Value = $script:L.configured }
        }
        return $entries
    }

    # === GPP ShortcutSettings ===
    if ($localName -eq 'ShortcutSettings') {
        $shortcuts = $Node.SelectNodes('.//*[local-name()="Shortcut"]')
        foreach ($sc in $shortcuts) {
            $scName = $sc.GetAttribute('name')
            $scDisabled = $sc.GetAttribute('disabled')
            $props = $sc.SelectSingleNode('*[local-name()="Properties"]')
            if ($props) {
                $targetPath = $props.GetAttribute('targetPath')
                $shortcutPath = $props.GetAttribute('shortcutPath')
                $scAction = $props.GetAttribute('action')
                $actionText = Get-ActionText $scAction
                $parts = @("Ziel: $targetPath", $actionText)
                if ($scDisabled -eq '1') { $parts += 'Deaktiviert' }
                $displayName = if ($shortcutPath) { $shortcutPath } elseif ($scName) { $scName } else { 'Verknuepfung' }
                $entries += [PSCustomObject]@{ Name = $displayName; Value = ($parts -join ' | ') }
            }
        }
        if ($entries.Count -eq 0) {
            $entries += [PSCustomObject]@{ Name = 'ShortcutSettings'; Value = $script:L.configured }
        }
        return $entries
    }

    # === GPP LocalUsersAndGroups (Lugs) ===
    if ($localName -eq 'LocalUsersAndGroups') {
        $groups = $Node.SelectNodes('.//*[local-name()="Group"]')
        foreach ($grp in $groups) {
            $grpName = $grp.GetAttribute('name')
            $grpDisabled = $grp.GetAttribute('disabled')
            $grpDesc = $grp.GetAttribute('desc')
            $props = $grp.SelectSingleNode('*[local-name()="Properties"]')
            if ($props) {
                $groupName = $props.GetAttribute('groupName')
                $grpAction = $props.GetAttribute('action')
                $actionText = Get-ActionText $grpAction
                $members = $props.SelectNodes('.//*[local-name()="Member"]')
                $memberList = @()
                foreach ($m in $members) {
                    $mName = $m.GetAttribute('name')
                    $mAction = $m.GetAttribute('action')
                    if ($mName) { $memberList += "$mName ($mAction)" }
                }
                $displayName = if ($groupName) { $groupName } elseif ($grpName) { $grpName } else { 'Gruppe' }
                $parts = @("Aktion: $actionText")
                if ($memberList.Count -gt 0) { $parts += "Mitglieder: $($memberList -join ', ')" }
                if ($grpDisabled -eq '1') { $parts += 'Deaktiviert' }
                $entries += [PSCustomObject]@{ Name = $displayName; Value = ($parts -join ' | ') }
            }
        }
        if ($entries.Count -eq 0) {
            $entries += [PSCustomObject]@{ Name = 'LocalUsersAndGroups'; Value = $script:L.configured }
        }
        return $entries
    }

    # === GPP NTServices ===
    if ($localName -eq 'NTServices') {
        $services = $Node.SelectNodes('.//*[local-name()="NTService"]')
        foreach ($svc in $services) {
            $svcName = $svc.GetAttribute('name')
            $svcDisabled = $svc.GetAttribute('disabled')
            $props = $svc.SelectSingleNode('*[local-name()="Properties"]')
            if ($props) {
                $serviceName = $props.GetAttribute('serviceName')
                $startupType = $props.GetAttribute('startupType')
                $serviceAction = $props.GetAttribute('serviceAction')
                $parts = @()
                if ($startupType) { $parts += "Starttyp: $startupType" }
                if ($serviceAction) { $parts += "Aktion: $serviceAction" }
                if ($svcDisabled -eq '1') { $parts += 'GPO-Eintrag deaktiviert' }
                $displayName = if ($serviceName) { $serviceName } elseif ($svcName) { $svcName } else { 'Dienst' }
                $entries += [PSCustomObject]@{ Name = $displayName; Value = ($parts -join ' | ') }
            }
        }
        if ($entries.Count -eq 0) {
            $entries += [PSCustomObject]@{ Name = 'NTServices'; Value = $script:L.configured }
        }
        return $entries
    }

    # === Folder Redirection ===
    if ($localName -eq 'Folder' -and $Node.SelectSingleNode('*[local-name()="Location"]')) {
        $folderId = $Node.SelectSingleNode('*[local-name()="Id"]')
        $location = $Node.SelectSingleNode('*[local-name()="Location"]')
        $destPath = $location.SelectSingleNode('*[local-name()="DestinationPath"]')
        $redirectToLocal = $Node.SelectSingleNode('*[local-name()="RedirectToLocal"]')
        $followParent = $Node.SelectSingleNode('*[local-name()="FollowParent"]')

        # Bekannte Folder-IDs
        $folderNames = @{
            '{FDD39AD0-238F-46AF-ADB4-6C85480369C7}' = 'Dokumente'
            '{33E28130-4E1E-4676-835A-98395C3BC3BB}' = 'Bilder'
            '{4BD8D571-6D19-48D3-BE97-422220080E43}' = 'Musik'
            '{18989B1D-99B5-455B-841C-AB7C74E4DDFC}' = 'Videos'
            '{1777F761-68AD-4D8A-87BD-30B759FA33DD}' = 'Favoriten'
            '{374DE290-123F-4565-9164-39C4925E467B}' = 'Downloads'
            '{625B53C3-AB48-4EC1-BA1F-A1EF4146FC19}' = 'Startmenue'
            '{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}' = 'Desktop'
            '{A520A1A4-1780-4FF6-BD18-167343C5AF16}' = 'AppData (Roaming)'
        }
        $idText = if ($folderId) { $folderId.InnerText } else { '' }
        $folderDisplayName = if ($folderNames.ContainsKey($idText)) { $folderNames[$idText] } else { "Ordner ($idText)" }

        $dest = if ($destPath -and $destPath.InnerText) { $destPath.InnerText } else { '(lokal)' }
        $parts = @("Ziel: $dest")
        if ($followParent -and $followParent.InnerText -eq 'true') { $parts += 'Folgt uebergeordnetem Ordner' }
        if ($redirectToLocal -and $redirectToLocal.InnerText -eq 'true') { $parts += 'Umleitung auf lokal' }

        $entries += [PSCustomObject]@{ Name = $folderDisplayName; Value = ($parts -join ' | ') }
        return $entries
    }

    # === SystemServices ===
    if ($localName -eq 'SystemServices' -or $localName -eq 'Service') {
        $sName = $Node.SelectSingleNode('*[local-name()="Name"]')
        $startMode = $Node.SelectSingleNode('*[local-name()="StartupMode"]')

        $name = if ($sName) { $sName.InnerText } else { $localName }
        $value = if ($startMode) { $startMode.InnerText } else { "-" }

        $entries += [PSCustomObject]@{ Name = $name; Value = $value }
        return $entries
    }

    # === Firewall-Regeln ===
    if ($localName -in @('InboundFirewallRules', 'OutboundFirewallRules', 'DomainProfile',
                         'PrivateProfile', 'PublicProfile', 'GlobalSettings')) {
        $sName = $Node.SelectSingleNode('*[local-name()="Name"]')
        $name = if ($sName) { $sName.InnerText } else { $localName }

        # Firewall-Profil: Alle relevanten Einstellungen sammeln
        $settingParts = @()
        foreach ($child in $Node.ChildNodes) {
            if ($child -is [System.Xml.XmlElement] -and $child.LocalName -ne 'Name') {
                $childVal = $child.InnerText.Trim()
                if ($childVal -and $childVal.Length -lt 100) {
                    $settingParts += "$($child.LocalName): $childVal"
                } elseif ($childVal) {
                    $settingParts += "$($child.LocalName): (konfiguriert)"
                }
            }
        }
        $value = if ($settingParts.Count -gt 0) { $settingParts -join "; " } else { "Konfiguriert" }

        $entries += [PSCustomObject]@{ Name = $name; Value = $value }
        return $entries
    }

    # === Generischer Fallback: Versuche Name + Value zu extrahieren ===
    $sName = $null
    $sValue = $null

    # Name-Kandidaten
    foreach ($nameTag in @('Name', 'PolicyName', 'KeyName', 'KeyPath')) {
        $n = $Node.SelectSingleNode("*[local-name()='$nameTag']")
        if ($n -and $n.InnerText) { $sName = $n.InnerText; break }
    }

    # Wert-Kandidaten
    foreach ($valTag in @('SettingNumber', 'SettingBoolean', 'SettingString', 'State', 'Value')) {
        $v = $Node.SelectSingleNode("*[local-name()='$valTag']")
        if ($v) {
            if ($valTag -eq 'SettingBoolean') {
                $sValue = if ($v.InnerText -eq 'true') { $script:L.enabled } else { $script:L.disabled }
            } elseif ($valTag -eq 'Value') {
                $numN = $v.SelectSingleNode('*[local-name()="Number"]')
                $strN = $v.SelectSingleNode('*[local-name()="String"]')
                if ($numN) { $sValue = $numN.InnerText }
                elseif ($strN) { $sValue = $strN.InnerText }
                else { $sValue = $v.InnerText.Trim() }
            } else {
                $sValue = $v.InnerText
            }
            break
        }
    }

    # Wenn kein Name gefunden, aber Knoten hat bedeutungsvolle Kinder
    if (-not $sName -and $Node.HasChildNodes) {
        $childElements = @($Node.ChildNodes | Where-Object { $_ -is [System.Xml.XmlElement] })
        if ($childElements.Count -gt 0 -and $childElements.Count -le 8) {
            # Kompakte Darstellung aller Kind-Werte
            $sName = $localName
            $parts = @()
            foreach ($child in $childElements) {
                $cText = $child.InnerText.Trim()
                if ($cText -and $cText.Length -lt 150) {
                    $parts += "$($child.LocalName): $cText"
                }
            }
            if ($parts.Count -gt 0) { $sValue = $parts -join "; " }
        }
    }

    if (-not $sName) { $sName = $localName }
    if (-not $sValue) { $sValue = "-" }

    $entries += [PSCustomObject]@{ Name = $sName; Value = $sValue }
    return $entries
}

function Export-GPOasHTML {
    param(
        [GpoItem[]]$GPOs,
        [string]$OutputPath,
        [bool]$Detailed = $true,
        [string]$FilePrefix = '',
        [hashtable]$DuplicateSettings = @{},
        [array]$ConflictData = @()
    )

    $L = $script:L
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
    $prefix = if ($FilePrefix) { $FilePrefix } else { $L.htmlTitle }
    $safePfx = $prefix -replace '[\\/:*?"<>|]', '_'
    $htmlFile = Join-Path $OutputPath "${safePfx}_$timestamp.html"
    $langCode = if ($script:lang -eq 'de') { 'de' } else { 'en' }

    $htmlHeader = @"
<!DOCTYPE html>
<html lang="$langCode" id="top">
<head>
    <meta charset="UTF-8">
    <title>$($L.htmlTitle)</title>
    <style>
        body { font-family: 'Segoe UI', Calibri, Arial, sans-serif; margin: 30px; color: #333; line-height: 1.6; }
        h1 { color: #0078D4; border-bottom: 3px solid #0078D4; padding-bottom: 10px; }
        h2 { color: #106EBE; margin-top: 40px; border-bottom: 1px solid #DDD; padding-bottom: 6px; }
        h3 { color: #333; margin-top: 20px; }
        h4 { color: #555; margin-top: 15px; }
        table { border-collapse: collapse; width: 100%; margin: 15px 0; }
        th { background: #0078D4; color: white; padding: 10px 12px; text-align: left; font-weight: 600; }
        td { padding: 8px 12px; border-bottom: 1px solid #E0E0E0; }
        tr:nth-child(even) { background: #F5F8FA; }
        .meta-table { width: auto; min-width: 400px; }
        .meta-table td:first-child { font-weight: 600; width: 200px; color: #555; }
        .gpo-section { margin-top: 10px; border: 1px solid #E0E0E0; border-radius: 4px; }
        .detail-report { margin: 15px 0; padding: 15px; background: #FAFAFA; border: 1px solid #E8E8E8; border-radius: 4px; }
        .detail-report table { font-size: 0.9em; }
        .badge { display: inline-block; padding: 2px 10px; border-radius: 12px; font-size: 0.85em; font-weight: 600; }
        .badge-active { background: #DFF6DD; color: #107C10; }
        .badge-disabled { background: #FDE7E9; color: #D13438; }
        .badge-partial { background: #FFF4CE; color: #8A6D00; }
        .badge-recent { background: #FFF8E1; color: #8A6D00; font-size: 0.75em; margin-left: 6px; }
        .val-enabled { color: #107C10; font-weight: 600; }
        .val-disabled { color: #D13438; font-weight: 600; }
        .val-notconfigured { color: #888; font-style: italic; }
        .toc { background: #F5F8FA; padding: 20px; border-radius: 4px; margin: 20px 0; }
        .toc ul { list-style-type: none; padding-left: 0; }
        .toc li { padding: 4px 0; }
        .toc a { color: #0078D4; text-decoration: none; }
        .toc .toc-badge { font-size: 0.8em; margin-left: 8px; }
        .footer { margin-top: 40px; padding-top: 15px; border-top: 1px solid #DDD; color: #888; font-size: 0.85em; }
        .back-to-top { text-align: right; margin-top: 10px; font-size: 0.85em; }
        .back-to-top a { color: #0078D4; text-decoration: none; }
        .toggle-btn { background: #0078D4; color: white; border: none; padding: 8px 16px; border-radius: 4px; cursor: pointer; font-size: 13px; margin: 4px; }
        .toggle-btn:hover { background: #106EBE; }
        details.gpo-details { margin: 5px 0; }
        details.gpo-details > summary { cursor: pointer; padding: 12px 20px; font-size: 1.1em; font-weight: 600; color: #106EBE; background: #F5F8FA; border-bottom: 1px solid #E0E0E0; border-radius: 4px 4px 0 0; user-select: none; }
        details.gpo-details > summary:hover { background: #E8F0FE; }
        details.gpo-details[open] > summary { border-radius: 4px 4px 0 0; }
        details.gpo-details > .gpo-content { padding: 15px 20px; }
        .ou-tree { margin: 20px 0; padding: 15px; background: #F9FAFB; border: 1px solid #E0E0E0; border-radius: 4px; }
        .ou-tree ul { list-style: none; padding-left: 20px; margin: 4px 0; }
        .ou-tree > ul { padding-left: 0; }
        .ou-tree li { padding: 2px 0; }
        .ou-tree .ou-name { font-weight: 600; color: #333; }
        .ou-tree .gpo-link { color: #0078D4; font-size: 0.9em; margin-left: 4px; }
        .ou-tree .gpo-link-disabled { color: #D13438; text-decoration: line-through; }
        .ou-tree .inheritance-blocked { color: #D13438; font-weight: 600; font-size: 0.85em; }
        @page { size: landscape; margin: 10mm; }
        @media print {
            body { font-size: 10px; line-height: 1.3; margin: 10px; }
            h1 { font-size: 16px; }
            h2 { font-size: 13px; }
            h3 { font-size: 11px; }
            h4 { font-size: 10px; }
            table { font-size: 9px; }
            th, td { padding: 4px 6px; }
            details.gpo-details { display: block; }
            details.gpo-details > summary { display: block; font-size: 12px; }
            .gpo-section { page-break-before: always; }
            .gpo-section:first-of-type { page-break-before: avoid; }
            .toggle-btn { display: none; }
            .back-to-top { display: none; }
            .toc { font-size: 9px; padding: 10px; }
            .meta-table { font-size: 8px; }
        }
    </style>
</head>
<body>
    <h1>$($L.htmlTitle)</h1>
    <p><strong>$($L.createdOn)</strong> $(Get-Date -Format "dd.MM.yyyy HH:mm") | <strong>$($L.domain)</strong> $($GPOs[0].DomainName) | <strong>$($L.gpoCountLabel)</strong> $($GPOs.Count)</p>
    <div>
        <button class="toggle-btn" onclick="document.querySelectorAll('details.gpo-details').forEach(d=>d.open=true)">$($L.expandAllHtml)</button>
        <button class="toggle-btn" onclick="document.querySelectorAll('details.gpo-details').forEach(d=>d.open=false)">$($L.collapseAllHtml)</button>
    </div>
"@

    # Inhaltsverzeichnis
    $tocHtml = @"
    <div class="toc">
        <h3>$($L.toc)</h3>
        <ul>
"@
    $index = 0
    foreach ($gpo in $GPOs) {
        $index++
        $safeId = $gpo.Id.ToString().Replace("-","")
        $tocBadgeClass = switch ($gpo.GpoStatusKey) {
            "AllSettingsEnabled"  { "badge-active" }
            "AllSettingsDisabled" { "badge-disabled" }
            default              { "badge-partial" }
        }
        $recentBadge = if ($gpo.IsRecentlyModified) { " <span class=`"badge badge-recent`">$($L.recentlyModified)</span>" } else { "" }
        $tocHtml += "            <li>$index. <a href=`"#gpo_$safeId`">$([System.Web.HttpUtility]::HtmlEncode($gpo.DisplayName))</a> <span class=`"badge toc-badge $tocBadgeClass`">$($gpo.GpoStatus)</span>$recentBadge</li>`n"
    }
    $tocHtml += @"
        </ul>
    </div>
"@

    # OU-Baum generieren
    $ouTreeHtml = ""
    if ($Detailed) {
        $ouMap = @{}
        foreach ($gpo in $GPOs) {
            try {
                $rXml = [xml](Get-GPOReport -Guid $gpo.Id -ReportType Xml)
                $gpoLinks = Get-GPOLinksFromXml -ReportXml $rXml
                foreach ($link in $gpoLinks) {
                    $path = $link.Path
                    if (-not $ouMap.ContainsKey($path)) {
                        $ouMap[$path] = @{ Name = $link.Name; GPOs = [System.Collections.ArrayList]::new() }
                    }
                    $ouMap[$path].GPOs.Add(@{ DisplayName = $gpo.DisplayName; Enabled = $link.Enabled; Id = $gpo.Id }) | Out-Null
                }
            } catch { }
        }

        if ($ouMap.Count -gt 0) {
            $ouTreeHtml = "<div class=`"ou-tree`">`n<h3>$($L.ouTree)</h3>`n<ul>`n"
            $sortedPaths = $ouMap.Keys | Sort-Object

            function Build-OUTreeHtml($paths, $ouMap) {
                $html = ""
                $grouped = @{}
                foreach ($p in $paths) {
                    $parts = $p -split '/'
                    $root = $parts[0]
                    if (-not $grouped.ContainsKey($root)) { $grouped[$root] = @() }
                    $grouped[$root] += $p
                }
                foreach ($root in ($grouped.Keys | Sort-Object)) {
                    foreach ($path in ($grouped[$root] | Sort-Object)) {
                        $info = $ouMap[$path]
                        $ouName = [System.Web.HttpUtility]::HtmlEncode($info.Name)
                        $indent = (($path -split '/').Count - 1)
                        $padding = $indent * 20
                        $html += "<li style=`"padding-left: ${padding}px`"><span class=`"ou-name`">📁 $ouName</span>"
                        $html += " <span style=`"color:#888;font-size:0.8em`">($([System.Web.HttpUtility]::HtmlEncode($path)))</span>"
                        foreach ($gLink in $info.GPOs) {
                            $gpoName = [System.Web.HttpUtility]::HtmlEncode($gLink.DisplayName)
                            $gpoAnchor = $gLink.Id.ToString().Replace('-','')
                            $linkClass = if ($gLink.Enabled -eq 'true') { 'gpo-link' } else { 'gpo-link gpo-link-disabled' }
                            $html += "<br/>&nbsp;&nbsp;&nbsp;📋 <a href=`"#gpo_$gpoAnchor`" class=`"$linkClass`">$gpoName</a>"
                        }
                        $html += "</li>`n"
                    }
                }
                return $html
            }
            $ouTreeHtml += Build-OUTreeHtml -paths $sortedPaths -ouMap $ouMap
            $ouTreeHtml += "</ul></div>`n"
        }
    }

    # Hilfsfunktion: Wert farbig formatieren
    function Format-HtmlValue {
        param([string]$Value)
        $encoded = [System.Web.HttpUtility]::HtmlEncode($Value)
        if ($Value -match '^Enabled') {
            return "<span class=`"val-enabled`">$encoded</span>"
        } elseif ($Value -match '^Disabled') {
            return "<span class=`"val-disabled`">$encoded</span>"
        } elseif ($Value -match '^NotConfigured') {
            return "<span class=`"val-notconfigured`">$encoded</span>"
        }
        return $encoded
    }

    # GPO-Sektionen
    $gpoSections = ""
    $index = 0
    foreach ($gpo in $GPOs) {
        $index++
        $safeId = $gpo.Id.ToString().Replace("-","")
        $badgeClass = switch ($gpo.GpoStatusKey) {
            "AllSettingsEnabled"  { "badge-active" }
            "AllSettingsDisabled" { "badge-disabled" }
            default              { "badge-partial" }
        }
        $recentBadge = if ($gpo.IsRecentlyModified) { " <span class=`"badge badge-recent`">$($L.recentlyModified)</span>" } else { "" }

        $gpoSections += @"
    <div class="gpo-section" id="gpo_$safeId">
        <details class="gpo-details" open>
            <summary>$index. $([System.Web.HttpUtility]::HtmlEncode($gpo.DisplayName)) <span class="badge $badgeClass">$($gpo.GpoStatus)</span>$recentBadge</summary>
            <div class="gpo-content">
        <table class="meta-table">
            <tr><td>$($L.gpoId)</td><td>$($gpo.Id)</td></tr>
            <tr><td>$($L.status)</td><td><span class="badge $badgeClass">$($gpo.GpoStatus)</span></td></tr>
            <tr><td>$($L.link)</td><td>$($gpo.LinkType)</td></tr>
            <tr><td>$($L.created)</td><td>$($gpo.CreationTime.ToString("dd.MM.yyyy HH:mm"))</td></tr>
            <tr><td>$($L.modified)</td><td>$($gpo.ModificationTime.ToString("dd.MM.yyyy HH:mm"))</td></tr>
        </table>
"@

        if ($Detailed) {
            try {
                $reportXml = [xml](Get-GPOReport -Guid $gpo.Id -ReportType Xml)
                $detailHtml = ""

                # Verknüpfungen
                $links = Get-GPOLinksFromXml -ReportXml $reportXml
                if ($links.Count -gt 0) {
                    $detailHtml += "<h3>$($L.linkedOUs)</h3>`n"
                    $detailHtml += "<table><tr><th>$($L.ouNameLabel)</th><th>$($L.pathLabel)</th><th>$($L.activeLabel)</th></tr>`n"
                    foreach ($link in $links) {
                        $enabledText = if ($link.Enabled -eq 'true') { $L.yes } else { $L.no }
                        $detailHtml += "<tr><td>$([System.Web.HttpUtility]::HtmlEncode($link.Name))</td><td>$([System.Web.HttpUtility]::HtmlEncode($link.Path))</td><td>$enabledText</td></tr>`n"
                    }
                    $detailHtml += "</table>`n"
                }

                # Berechtigungen
                $permissions = Get-GPOPermissionsFromXml -ReportXml $reportXml
                if ($permissions.Count -gt 0) {
                    $detailHtml += "<h3>$($L.permissions)</h3>`n"
                    $detailHtml += "<table><tr><th>$($L.userGroup)</th><th>$($L.permission)</th><th>$($L.typeLabel)</th></tr>`n"
                    foreach ($perm in $permissions) {
                        $detailHtml += "<tr><td>$([System.Web.HttpUtility]::HtmlEncode($perm.Trustee))</td><td>$([System.Web.HttpUtility]::HtmlEncode($perm.Permission))</td><td>$($perm.Type)</td></tr>`n"
                    }
                    $detailHtml += "</table>`n"
                }

                # Computereinstellungen
                $compExt = $reportXml.GPO.Computer.ExtensionData
                if ($compExt) {
                    $parsedSections = Get-GPOSettingsFromXml -ExtensionData $compExt
                    $detailHtml += "<h3>$($L.compSettings)</h3>`n"
                    foreach ($section in $parsedSections) {
                        $detailHtml += "<h4>$([System.Web.HttpUtility]::HtmlEncode($section.ExtensionName))</h4>`n"
                        $detailHtml += "<table><tr><th>$($L.settingLabel)</th><th>$($L.valueLabel)</th></tr>`n"
                        foreach ($s in $section.Settings) {
                            $detailHtml += "<tr><td>$([System.Web.HttpUtility]::HtmlEncode($s.Name))</td><td>$(Format-HtmlValue $s.Value)</td></tr>`n"
                        }
                        $detailHtml += "</table>`n"
                    }
                }

                # Benutzereinstellungen
                $userExt = $reportXml.GPO.User.ExtensionData
                if ($userExt) {
                    $parsedSections = Get-GPOSettingsFromXml -ExtensionData $userExt
                    $detailHtml += "<h3>$($L.userSettings)</h3>`n"
                    foreach ($section in $parsedSections) {
                        $detailHtml += "<h4>$([System.Web.HttpUtility]::HtmlEncode($section.ExtensionName))</h4>`n"
                        $detailHtml += "<table><tr><th>$($L.settingLabel)</th><th>$($L.valueLabel)</th></tr>`n"
                        foreach ($s in $section.Settings) {
                            $detailHtml += "<tr><td>$([System.Web.HttpUtility]::HtmlEncode($s.Name))</td><td>$(Format-HtmlValue $s.Value)</td></tr>`n"
                        }
                        $detailHtml += "</table>`n"
                    }
                }

                if (-not $compExt -and -not $userExt -and $links.Count -eq 0) {
                    $detailHtml = "<p><em>$($L.noSettings)</em></p>"
                }

                $gpoSections += @"
        <div class="detail-report">
            <h3>$($L.configDetails)</h3>
            $detailHtml
        </div>
"@
            } catch {
                $gpoSections += "        <p><em>$($L.detailError) $($_.Exception.Message)</em></p>`n"
            }
        }

        $gpoSections += "        <p class=`"back-to-top`"><a href=`"#top`">$($L.backToTop)</a></p>`n"
        $gpoSections += "        </div></details></div>`n"
    }

    $htmlFooter = @"
    <div class="footer">
        <p>$($L.generatedWith) | $(Get-Date -Format "dd.MM.yyyy HH:mm:ss")</p>
    </div>
</body>
</html>
"@

    # Duplikate und Konflikte Sektionen
    $analysisHtml = ""
    if ($DuplicateSettings.Count -gt 0) {
        $analysisHtml += "<div class=`"gpo-section`" style=`"border-color: #FF8C00;`">`n"
        $analysisHtml += "<h2 style=`"color: #FF8C00;`">⚠️ $($L.duplicatesTitle)</h2>`n"
        $analysisHtml += "<p><em>$($L.duplicatesDesc)</em></p>`n"
        $analysisHtml += "<table><tr><th>$($L.settingLabel)</th><th>$($L.duplicateCount)</th><th>$($L.conflictGpos)</th></tr>`n"
        foreach ($key in ($DuplicateSettings.Keys | Sort-Object)) {
            $entry = $DuplicateSettings[$key]
            $gpoNames = ($entry.GPOs | Sort-Object) -join ', '
            $analysisHtml += "<tr><td>$([System.Web.HttpUtility]::HtmlEncode($key))</td><td>$($entry.GPOs.Count)</td><td>$([System.Web.HttpUtility]::HtmlEncode($gpoNames))</td></tr>`n"
        }
        $analysisHtml += "</table></div>`n"
    }

    if ($ConflictData.Count -gt 0) {
        $analysisHtml += "<div class=`"gpo-section`" style=`"border-color: #D13438;`">`n"
        $analysisHtml += "<h2 style=`"color: #D13438;`">🔥 $($L.conflictsTitle)</h2>`n"
        $analysisHtml += "<p><em>$($L.conflictsDesc)</em></p>`n"
        $analysisHtml += "<table><tr><th>$($L.conflictSetting)</th><th>$($L.conflictGpos)</th><th>$($L.conflictOu)</th></tr>`n"
        foreach ($conflict in $ConflictData) {
            $gpoNames = ($conflict.GPOs | Sort-Object) -join ', '
            $ouNames = ($conflict.OUs | Sort-Object) -join ', '
            $analysisHtml += "<tr><td>$([System.Web.HttpUtility]::HtmlEncode($conflict.Setting))</td><td>$([System.Web.HttpUtility]::HtmlEncode($gpoNames))</td><td>$([System.Web.HttpUtility]::HtmlEncode($ouNames))</td></tr>`n"
        }
        $analysisHtml += "</table></div>`n"
    }

    $fullHtml = $htmlHeader + $tocHtml + $ouTreeHtml + $gpoSections + $analysisHtml + $htmlFooter
    $fullHtml | Out-File -FilePath $htmlFile -Encoding UTF8

    return $htmlFile
}

function Export-GPOasMarkdown {
    param(
        [GpoItem[]]$GPOs,
        [string]$OutputPath,
        [bool]$Detailed = $true,
        [string]$FilePrefix = '',
        [hashtable]$DuplicateSettings = @{},
        [array]$ConflictData = @()
    )

    $L = $script:L
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
    $prefix = if ($FilePrefix) { $FilePrefix } else { $L.htmlTitle }
    $safePfx = $prefix -replace '[\\/:*?"<>|]', '_'
    $mdFile = Join-Path $OutputPath "${safePfx}_$timestamp.md"

    $md = @"
# $($L.htmlTitle)

**$($L.createdOn)** $(Get-Date -Format "dd.MM.yyyy HH:mm")
**$($L.domain)** $($GPOs[0].DomainName)
**$($L.gpoCountLabel)** $($GPOs.Count)

---

## $($L.toc)

"@

    $index = 0
    foreach ($gpo in $GPOs) {
        $index++
        $anchor = ($gpo.DisplayName -replace '[^a-zA-Z0-9äöüÄÖÜß\s-]', '' -replace '\s+', '-').ToLower()
        $md += "$index. [$($gpo.DisplayName)](#$index-$anchor)`n"
    }

    $md += "`n---`n`n"

    $index = 0
    foreach ($gpo in $GPOs) {
        $index++
        $md += @"

## $index. $($gpo.DisplayName)

| $($L.settingLabel) | $($L.valueLabel) |
|---|---|
| **$($L.gpoId)** | ``$($gpo.Id)`` |
| **$($L.status)** | $($gpo.GpoStatus) |
| **$($L.link)** | $($gpo.LinkType) |
| **$($L.created)** | $($gpo.CreationTime.ToString("dd.MM.yyyy HH:mm")) |
| **$($L.modified)** | $($gpo.ModificationTime.ToString("dd.MM.yyyy HH:mm")) |

"@

        if ($Detailed) {
            try {
                $reportXml = [xml](Get-GPOReport -Guid $gpo.Id -ReportType Xml)

                $links = Get-GPOLinksFromXml -ReportXml $reportXml
                if ($links.Count -gt 0) {
                    $md += "### $($L.linkedOUs)`n`n"
                    $md += "| $($L.ouNameLabel) | $($L.pathLabel) | $($L.activeLabel) |`n|---|---|---|`n"
                    foreach ($link in $links) {
                        $enabledText = if ($link.Enabled -eq 'true') { $L.yes } else { $L.no }
                        $md += "| $($link.Name) | $($link.Path) | $enabledText |`n"
                    }
                    $md += "`n"
                }

                $permissions = Get-GPOPermissionsFromXml -ReportXml $reportXml
                if ($permissions.Count -gt 0) {
                    $md += "### $($L.permissions)`n`n"
                    $md += "| $($L.userGroup) | $($L.permission) | $($L.typeLabel) |`n|---|---|---|`n"
                    foreach ($perm in $permissions) {
                        $md += "| $($perm.Trustee) | $($perm.Permission) | $($perm.Type) |`n"
                    }
                    $md += "`n"
                }

                $computerExtensions = $reportXml.GPO.Computer.ExtensionData
                if ($computerExtensions) {
                    $parsedSections = Get-GPOSettingsFromXml -ExtensionData $computerExtensions
                    $md += "### $($L.compSettings)`n`n"
                    foreach ($section in $parsedSections) {
                        $md += "#### $($section.ExtensionName)`n`n"
                        $md += "| $($L.settingLabel) | $($L.valueLabel) |`n|---|---|`n"
                        foreach ($s in $section.Settings) {
                            $md += "| $($s.Name) | $($s.Value) |`n"
                        }
                        $md += "`n"
                    }
                }

                $userExtensions = $reportXml.GPO.User.ExtensionData
                if ($userExtensions) {
                    $parsedSections = Get-GPOSettingsFromXml -ExtensionData $userExtensions
                    $md += "### $($L.userSettings)`n`n"
                    foreach ($section in $parsedSections) {
                        $md += "#### $($section.ExtensionName)`n`n"
                        $md += "| $($L.settingLabel) | $($L.valueLabel) |`n|---|---|`n"
                        foreach ($s in $section.Settings) {
                            $md += "| $($s.Name) | $($s.Value) |`n"
                        }
                        $md += "`n"
                    }
                }

                if (-not $computerExtensions -and -not $userExtensions -and $links.Count -eq 0) {
                    $md += "*$($L.noSettings)*`n`n"
                }
            } catch {
                $md += "*$($L.detailError) $($_.Exception.Message)*`n`n"
            }
        }

        $md += "---`n`n"
    }

    $md += "`n> $($L.generatedWith) | $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')`n"

    # Duplikate und Konflikte anhängen
    if ($DuplicateSettings.Count -gt 0) {
        $md += "`n---`n`n## ⚠️ $($L.duplicatesTitle)`n`n"
        $md += "*$($L.duplicatesDesc)*`n`n"
        $md += "| $($L.settingLabel) | $($L.duplicateCount) | $($L.conflictGpos) |`n|---|---|---|`n"
        foreach ($key in ($DuplicateSettings.Keys | Sort-Object)) {
            $entry = $DuplicateSettings[$key]
            $gpoNames = ($entry.GPOs | Sort-Object) -join ', '
            $md += "| $key | $($entry.GPOs.Count) | $gpoNames |`n"
        }
    }

    if ($ConflictData.Count -gt 0) {
        $md += "`n---`n`n## 🔥 $($L.conflictsTitle)`n`n"
        $md += "*$($L.conflictsDesc)*`n`n"
        $md += "| $($L.conflictSetting) | $($L.conflictGpos) | $($L.conflictOu) |`n|---|---|---|`n"
        foreach ($conflict in $ConflictData) {
            $gpoNames = ($conflict.GPOs | Sort-Object) -join ', '
            $ouNames = ($conflict.OUs | Sort-Object) -join ', '
            $md += "| $($conflict.Setting) | $gpoNames | $ouNames |`n"
        }
    }

    $md | Out-File -FilePath $mdFile -Encoding UTF8

    return $mdFile
}

function Find-DuplicateSettings {
    <#
    .SYNOPSIS
        Findet Einstellungen die in mehreren GPOs konfiguriert sind.
    #>
    param([GpoItem[]]$GPOs)

    $settingMap = @{}

    foreach ($gpo in $GPOs) {
        try {
            $reportXml = [xml](Get-GPOReport -Guid $gpo.Id -ReportType Xml)

            # Computer-Einstellungen
            $compExt = $reportXml.GPO.Computer.ExtensionData
            if ($compExt) {
                $sections = Get-GPOSettingsFromXml -ExtensionData $compExt
                foreach ($section in $sections) {
                    foreach ($s in $section.Settings) {
                        $key = "[Computer] $($section.ExtensionName) > $($s.Name)"
                        if (-not $settingMap.ContainsKey($key)) {
                            $settingMap[$key] = @{ GPOs = [System.Collections.ArrayList]::new(); Values = [System.Collections.ArrayList]::new() }
                        }
                        # Nur hinzufügen wenn diese GPO noch nicht für diesen Key erfasst ist
                        if ($gpo.DisplayName -notin $settingMap[$key].GPOs) {
                            $settingMap[$key].GPOs.Add($gpo.DisplayName) | Out-Null
                        }
                        $settingMap[$key].Values.Add($s.Value) | Out-Null
                        $settingMap[$key].Values.Add($s.Value) | Out-Null
                    }
                }
            }

            # Benutzer-Einstellungen
            $userExt = $reportXml.GPO.User.ExtensionData
            if ($userExt) {
                $sections = Get-GPOSettingsFromXml -ExtensionData $userExt
                foreach ($section in $sections) {
                    foreach ($s in $section.Settings) {
                        $key = "[User] $($section.ExtensionName) > $($s.Name)"
                        if (-not $settingMap.ContainsKey($key)) {
                            $settingMap[$key] = @{ GPOs = [System.Collections.ArrayList]::new(); Values = [System.Collections.ArrayList]::new() }
                        }
                        # Nur hinzufügen wenn diese GPO noch nicht für diesen Key erfasst ist
                        if ($gpo.DisplayName -notin $settingMap[$key].GPOs) {
                            $settingMap[$key].GPOs.Add($gpo.DisplayName) | Out-Null
                        }
                        $settingMap[$key].Values.Add($s.Value) | Out-Null
                    }
                }
            }
        } catch { }
    }

    # Nur Einstellungen behalten die in mehr als einer UNTERSCHIEDLICHEN GPO vorkommen
    $duplicates = @{}
    foreach ($key in $settingMap.Keys) {
        if ($settingMap[$key].GPOs.Count -gt 1) {
            $duplicates[$key] = $settingMap[$key]
        }
    }

    return $duplicates
}

function Find-ConflictingSettings {
    <#
    .SYNOPSIS
        Findet widersprüchliche Einstellungen auf gleichen OUs.
    #>
    param([GpoItem[]]$GPOs)

    $conflicts = @()
    $settingsByOU = @{}

    foreach ($gpo in $GPOs) {
        try {
            $reportXml = [xml](Get-GPOReport -Guid $gpo.Id -ReportType Xml)
            $gpoOUs = @()
            $linksTo = $reportXml.GPO.LinksTo
            if ($linksTo) {
                foreach ($link in @($linksTo)) {
                    if ($link.Enabled -eq 'true') {
                        $gpoOUs += $link.SOMPath
                    }
                }
            }

            # Einstellungen sammeln
            $allSettings = @()
            $compExt = $reportXml.GPO.Computer.ExtensionData
            if ($compExt) {
                $sections = Get-GPOSettingsFromXml -ExtensionData $compExt
                foreach ($section in $sections) {
                    foreach ($s in $section.Settings) {
                        $allSettings += [PSCustomObject]@{ Key = "[Computer] $($section.ExtensionName) > $($s.Name)"; Value = $s.Value }
                    }
                }
            }
            $userExt = $reportXml.GPO.User.ExtensionData
            if ($userExt) {
                $sections = Get-GPOSettingsFromXml -ExtensionData $userExt
                foreach ($section in $sections) {
                    foreach ($s in $section.Settings) {
                        $allSettings += [PSCustomObject]@{ Key = "[User] $($section.ExtensionName) > $($s.Name)"; Value = $s.Value }
                    }
                }
            }

            foreach ($ou in $gpoOUs) {
                if (-not $settingsByOU.ContainsKey($ou)) {
                    $settingsByOU[$ou] = @{}
                }
                foreach ($setting in $allSettings) {
                    if (-not $settingsByOU[$ou].ContainsKey($setting.Key)) {
                        $settingsByOU[$ou][$setting.Key] = @()
                    }
                    $settingsByOU[$ou][$setting.Key] += [PSCustomObject]@{ GPO = $gpo.DisplayName; Value = $setting.Value }
                }
            }
        } catch { }
    }

    # Konflikte: Gleiche Einstellung, unterschiedliche Werte, gleiche OU, VERSCHIEDENE GPOs
    $conflictMap = @{}
    foreach ($ou in $settingsByOU.Keys) {
        foreach ($settingKey in $settingsByOU[$ou].Keys) {
            $entries = $settingsByOU[$ou][$settingKey]
            # Nur betrachten wenn mindestens 2 verschiedene GPOs beteiligt sind
            $uniqueGPOs = $entries | Select-Object -ExpandProperty GPO -Unique
            if (@($uniqueGPOs).Count -lt 2) { continue }

            $uniqueValues = $entries | Select-Object -ExpandProperty Value -Unique
            if (@($uniqueValues).Count -gt 1) {
                if (-not $conflictMap.ContainsKey($settingKey)) {
                    $conflictMap[$settingKey] = @{ GPOs = [System.Collections.ArrayList]::new(); OUs = [System.Collections.ArrayList]::new() }
                }
                foreach ($e in $entries) {
                    if ($e.GPO -notin $conflictMap[$settingKey].GPOs) {
                        $conflictMap[$settingKey].GPOs.Add($e.GPO) | Out-Null
                    }
                }
                if ($ou -notin $conflictMap[$settingKey].OUs) {
                    $conflictMap[$settingKey].OUs.Add($ou) | Out-Null
                }
            }
        }
    }

    foreach ($key in $conflictMap.Keys) {
        $conflicts += [PSCustomObject]@{
            Setting = $key
            GPOs = $conflictMap[$key].GPOs
            OUs = $conflictMap[$key].OUs
        }
    }

    return $conflicts
}

function Export-HTMLtoPDF {
    <#
    .SYNOPSIS
        Konvertiert eine HTML-Datei zu PDF mittels Edge oder Chrome Headless.
    #>
    param(
        [string]$HtmlPath,
        [string]$OutputPath
    )

    $pdfFile = [System.IO.Path]::ChangeExtension($HtmlPath, '.pdf')

    # Edge oder Chrome suchen
    $browsers = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
    )

    $browser = $null
    foreach ($b in $browsers) {
        if (Test-Path $b) {
            $browser = $b
            break
        }
    }

    if (-not $browser) { return $null }

    try {
        $browserArgs = "--headless --disable-gpu --no-sandbox --print-to-pdf=`"$pdfFile`" --print-to-pdf-no-header --landscape `"$HtmlPath`""
        Start-Process -FilePath $browser -ArgumentList $browserArgs -Wait -WindowStyle Hidden
        if ((Test-Path $pdfFile) -and (Get-Item $pdfFile).Length -gt 0) {
            return $pdfFile
        }
    } catch { }

    return $null
}

function Find-OrphanedGPOs {
    <#
    .SYNOPSIS
        Findet GPOs ohne OU-Verknüpfung in der gesamten Domäne.
    #>
    $allGPOs = Get-GPO -All
    $orphaned = @()

    foreach ($gpo in $allGPOs) {
        try {
            $reportXml = [xml](Get-GPOReport -Guid $gpo.Id -ReportType Xml)
            $linksTo = $reportXml.GPO.LinksTo
            if (-not $linksTo) {
                $orphaned += $gpo
            }
        } catch {
            # Falls Report nicht geladen werden kann, als verwaist markieren
            $orphaned += $gpo
        }
    }

    return $orphaned
}

function Show-ChangeHistory {
    <#
    .SYNOPSIS
        Zeigt eine Änderungshistorie aller GPOs der letzten 90 Tage.
    #>
    $allGPOs = Get-GPO -All | Where-Object { $_.ModificationTime -gt (Get-Date).AddDays(-90) } |
        Sort-Object ModificationTime -Descending

    $L = $script:L
    $msg = "$($L.historyTitle)`n" + ("=" * 50) + "`n`n"

    foreach ($gpo in $allGPOs) {
        $daysAgo = [math]::Round(((Get-Date) - $gpo.ModificationTime).TotalDays)
        $msg += "[$($gpo.ModificationTime.ToString('dd.MM.yyyy HH:mm'))] $($gpo.DisplayName) (vor $daysAgo Tagen)`n"
    }

    if ($allGPOs.Count -eq 0) {
        $msg += "Keine Änderungen in den letzten 90 Tagen.`n"
    }

    return $msg
}

function Compare-TwoGPOs {
    <#
    .SYNOPSIS
        Vergleicht zwei GPOs und zeigt Unterschiede.
    #>
    param(
        [GpoItem]$GPO1,
        [GpoItem]$GPO2
    )

    $L = $script:L
    $settings1 = @{}
    $settings2 = @{}

    # GPO1 Einstellungen laden
    try {
        $xml1 = [xml](Get-GPOReport -Guid $GPO1.Id -ReportType Xml)
        $comp1 = $xml1.GPO.Computer.ExtensionData
        if ($comp1) {
            $sections = Get-GPOSettingsFromXml -ExtensionData $comp1
            foreach ($section in $sections) {
                foreach ($s in $section.Settings) {
                    $settings1["[Computer] $($section.ExtensionName) > $($s.Name)"] = $s.Value
                }
            }
        }
        $user1 = $xml1.GPO.User.ExtensionData
        if ($user1) {
            $sections = Get-GPOSettingsFromXml -ExtensionData $user1
            foreach ($section in $sections) {
                foreach ($s in $section.Settings) {
                    $settings1["[User] $($section.ExtensionName) > $($s.Name)"] = $s.Value
                }
            }
        }
    } catch { }

    # GPO2 Einstellungen laden
    try {
        $xml2 = [xml](Get-GPOReport -Guid $GPO2.Id -ReportType Xml)
        $comp2 = $xml2.GPO.Computer.ExtensionData
        if ($comp2) {
            $sections = Get-GPOSettingsFromXml -ExtensionData $comp2
            foreach ($section in $sections) {
                foreach ($s in $section.Settings) {
                    $settings2["[Computer] $($section.ExtensionName) > $($s.Name)"] = $s.Value
                }
            }
        }
        $user2 = $xml2.GPO.User.ExtensionData
        if ($user2) {
            $sections = Get-GPOSettingsFromXml -ExtensionData $user2
            foreach ($section in $sections) {
                foreach ($s in $section.Settings) {
                    $settings2["[User] $($section.ExtensionName) > $($s.Name)"] = $s.Value
                }
            }
        }
    } catch { }

    $allKeys = @($settings1.Keys) + @($settings2.Keys) | Select-Object -Unique | Sort-Object

    $diff = @()
    foreach ($key in $allKeys) {
        $val1 = if ($settings1.ContainsKey($key)) { $settings1[$key] } else { "---" }
        $val2 = if ($settings2.ContainsKey($key)) { $settings2[$key] } else { "---" }

        if ($val1 -ne $val2) {
            $diff += [PSCustomObject]@{
                Setting = $key
                Value1 = $val1
                Value2 = $val2
            }
        }
    }

    return $diff
}

#region Dark Mode
$script:isDarkMode = $false

function Toggle-DarkMode {
    $script:isDarkMode = -not $script:isDarkMode
    $L = $script:L

    # Hilfsfunktion: TreeViewItems rekursiv umfärben
    function Set-TreeItemForeground($items, $brush) {
        foreach ($item in $items) {
            $item.Foreground = $brush
            if ($item.Items.Count -gt 0) { Set-TreeItemForeground $item.Items $brush }
        }
    }

    $darkBg = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#1E1E1E")
    $darkBg2 = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#2D2D2D")
    $darkBg3 = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#383838")
    $darkFg = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E0E0E0")
    $darkFgDim = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#AAA")
    $darkAccent = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#4FC3F7")

    $lightBg = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#F5F5F5")
    $lightFg = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#333")
    $lightAccent = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#0078D4")

    if ($script:isDarkMode) {
        # Hauptfenster
        $window.Background = $darkBg

        # Header-Texte
        $txtTitle.Foreground = $darkAccent
        $txtDomain.Foreground = $darkFgDim
        $txtGpoCount.Foreground = $darkFgDim

        # Alle Labels/TextBlocks im Fenster
        $lblSearch.Foreground = $darkFg
        $lblStatusFilter.Foreground = $darkFg
        $lblFormat.Foreground = $darkFg
        $lblOutputPath.Foreground = $darkFg
        $lblFilePrefix.Foreground = $darkFg

        # GroupBoxen (Header + Content)
        foreach ($gb in @($grpOU, $grpGPO, $grpExport)) {
            $gb.Foreground = $darkFg
            $gb.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#555")
        }

        # CheckBoxen
        $chkSelectAll.Foreground = $darkFg
        $chkIncludeInherited.Foreground = $darkFg
        $chkDetailReport.Foreground = $darkFg
        $chkSaveRawXml.Foreground = $darkFg

        # TextBoxen
        foreach ($tb in @($txtSearch, $txtOutputPath, $txtFilePrefix)) {
            $tb.Background = $darkBg2
            $tb.Foreground = $darkFg
            $tb.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#555")
        }

        # ComboBoxen - Hintergrund dunkel, Text bleibt schwarz (Dropdown-Popup ist hell)
        foreach ($cb in @($cmbFormat, $cmbStatusFilter, $cmbLanguage)) {
            $cb.Background = $darkBg2
            $cb.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#555")
        }

        # DataGrid
        $gridGPO.Background = $darkBg2
        $gridGPO.Foreground = $darkFg
        $gridGPO.RowBackground = $darkBg2
        $gridGPO.AlternatingRowBackground = $darkBg3
        $gridGPO.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#555")

        # DataGrid Spaltenheader - Text schwarz lassen (blauer Header-Hintergrund)
        $headerStyle = New-Object System.Windows.Style([System.Windows.Controls.Primitives.DataGridColumnHeader])
        $headerStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::ForegroundProperty, [System.Windows.Media.Brushes]::Black)))
        $gridGPO.ColumnHeaderStyle = $headerStyle

        # TreeView + alle TreeViewItems auf weiß setzen
        $treeOU.Background = $darkBg2
        $treeOU.Foreground = $darkFg
        $treeOU.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#555")
        Set-TreeItemForeground $treeOU.Items $darkFg

        # StatusBar
        $txtStatus.Foreground = $darkFg
        $statusBar = $txtStatus.Parent.Parent
        if ($statusBar) {
            $statusBar.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#252525")
        }

        $btnDarkMode.Content = "☀️ $($L.lightMode)"
    } else {
        # Hauptfenster
        $window.Background = $lightBg

        # Header-Texte
        $txtTitle.Foreground = $lightAccent
        $txtDomain.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#666")
        $txtGpoCount.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#666")

        # Alle Labels
        $lblSearch.Foreground = $lightFg
        $lblStatusFilter.Foreground = $lightFg
        $lblFormat.Foreground = $lightFg
        $lblOutputPath.Foreground = $lightFg
        $lblFilePrefix.Foreground = $lightFg

        # GroupBoxen
        foreach ($gb in @($grpOU, $grpGPO, $grpExport)) {
            $gb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#000")
            $gb.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#D5DFE5")
        }

        # CheckBoxen
        $chkSelectAll.Foreground = $lightFg
        $chkIncludeInherited.Foreground = $lightFg
        $chkDetailReport.Foreground = $lightFg
        $chkSaveRawXml.Foreground = $lightFg

        # TextBoxen
        foreach ($tb in @($txtSearch, $txtOutputPath, $txtFilePrefix)) {
            $tb.Background = [System.Windows.Media.Brushes]::White
            $tb.Foreground = $lightFg
            $tb.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#CCC")
        }

        # ComboBoxen
        foreach ($cb in @($cmbFormat, $cmbStatusFilter, $cmbLanguage)) {
            $cb.Background = [System.Windows.Media.Brushes]::White
            $cb.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#CCC")
        }

        # DataGrid
        $gridGPO.Background = [System.Windows.Media.Brushes]::White
        $gridGPO.Foreground = $lightFg
        $gridGPO.RowBackground = [System.Windows.Media.Brushes]::White
        $gridGPO.AlternatingRowBackground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#F9F9F9")
        $gridGPO.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#CCC")
        $gridGPO.ColumnHeaderStyle = $null

        # TreeView + TreeViewItems zurücksetzen
        $treeOU.Background = [System.Windows.Media.Brushes]::White
        $treeOU.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#000")
        $treeOU.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#CCC")
        Set-TreeItemForeground $treeOU.Items ([System.Windows.Media.BrushConverter]::new().ConvertFrom("#000"))

        # StatusBar
        $txtStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#000")
        $statusBar = $txtStatus.Parent.Parent
        if ($statusBar) {
            $statusBar.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E8E8E8")
        }

        $btnDarkMode.Content = "🌙 $($L.darkMode)"
    }
}
#endregion

function Invoke-GPOExport {
    param([GpoItem[]]$GPOsToExport)

    $L = $script:L
    $outputPath = $txtOutputPath.Text
    if (-not (Test-Path $outputPath)) {
        [System.Windows.MessageBox]::Show(
            "$($L.invalidPath) $outputPath",
            $L.invalidPathTitle, "OK", "Error")
        return
    }

    $formatIndex = $cmbFormat.SelectedIndex
    $detailed = $chkDetailReport.IsChecked
    $saveRawXml = $chkSaveRawXml.IsChecked
    $filePrefix = $txtFilePrefix.Text.Trim()

    $progressBar.Visibility = "Visible"
    $progressBar.IsIndeterminate = $true
    $btnExport.IsEnabled = $false
    $btnExportSelected.IsEnabled = $false

    $exportedFiles = @()

    try {
        Set-Status "$($L.exporting) $($GPOsToExport.Count) $($L.gpos)..."

        # Roh-XML speichern
        if ($saveRawXml) {
            $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
            $xmlFolderName = if ($filePrefix) { "GPO-XML_${filePrefix}_$timestamp" } else { "GPO-XML_$timestamp" }
            $xmlFolder = Join-Path $outputPath $xmlFolderName
            New-Item -Path $xmlFolder -ItemType Directory -Force | Out-Null
            foreach ($gpo in $GPOsToExport) {
                Set-Status "$($L.savingXml) $($gpo.DisplayName)..."
                $safeName = $gpo.DisplayName -replace '[\\/:*?"<>|]', '_'
                $xmlContent = Get-GPOReport -Guid $gpo.Id -ReportType Xml
                $xmlContent | Out-File -FilePath (Join-Path $xmlFolder "$safeName.xml") -Encoding UTF8
            }
            $exportedFiles += $xmlFolder
        }

        # Duplikate und Konflikte sammeln (für detaillierte Berichte)
        $duplicateSettings = @{}
        $conflictData = @()
        if ($detailed) {
            $duplicateSettings = Find-DuplicateSettings -GPOs $GPOsToExport
            $conflictData = Find-ConflictingSettings -GPOs $GPOsToExport
        }

        # HTML Export
        if ($formatIndex -eq 0 -or $formatIndex -eq 2) {
            Set-Status $L.creatingHtml
            $htmlFile = Export-GPOasHTML -GPOs $GPOsToExport -OutputPath $outputPath -Detailed $detailed -FilePrefix $filePrefix -DuplicateSettings $duplicateSettings -ConflictData $conflictData
            $exportedFiles += $htmlFile
        }

        # Markdown Export
        if ($formatIndex -eq 1 -or $formatIndex -eq 2) {
            Set-Status $L.creatingMd
            $mdFile = Export-GPOasMarkdown -GPOs $GPOsToExport -OutputPath $outputPath -Detailed $detailed -FilePrefix $filePrefix -DuplicateSettings $duplicateSettings -ConflictData $conflictData
            $exportedFiles += $mdFile
        }

        # PDF Export
        if ($formatIndex -eq 3) {
            Set-Status $L.creatingPdf
            $htmlFile = Export-GPOasHTML -GPOs $GPOsToExport -OutputPath $outputPath -Detailed $detailed -FilePrefix $filePrefix -DuplicateSettings $duplicateSettings -ConflictData $conflictData
            $pdfFile = Export-HTMLtoPDF -HtmlPath $htmlFile -OutputPath $outputPath
            if ($pdfFile) {
                $exportedFiles += $pdfFile
                # HTML-Zwischendatei entfernen
                Remove-Item -Path $htmlFile -Force -ErrorAction SilentlyContinue
            } else {
                $exportedFiles += $htmlFile
                [System.Windows.MessageBox]::Show($L.pdfError, $L.exportErrorTitle, "OK", "Warning")
            }
        }

        $fileList = ($exportedFiles | ForEach-Object { Split-Path $_ -Leaf }) -join "`n"
        $result = [System.Windows.MessageBox]::Show(
            "$($L.exportComplete)`n`n$($L.files)`n$fileList`n`n$($L.openFolder)",
            $L.exportSuccess, "YesNo", "Information")

        if ($result -eq "Yes") {
            Start-Process "explorer.exe" -ArgumentList $outputPath
        }

        Set-Status "$($L.exportComplete) $($exportedFiles.Count) $($L.filesCreated)"
    } catch {
        [System.Windows.MessageBox]::Show(
            "$($L.exportError)`n$($_.Exception.Message)",
            $L.exportErrorTitle, "OK", "Error")
        Set-Status "$($L.exportErrorTitle): $($_.Exception.Message)"
    } finally {
        $progressBar.Visibility = "Collapsed"
        $btnExport.IsEnabled = $true
        $btnExportSelected.IsEnabled = $true
    }
}

#endregion

#region Event-Handler

# OU-Baum laden beim Start
$window.Add_Loaded({
    try {
        Add-Type -AssemblyName System.Web
        $txtOutputPath.Text = [Environment]::GetFolderPath("Desktop")
        Apply-Language
        Load-OUTree
    } catch {
        Set-Status "$($script:L.loadError) $($_.Exception.Message)"
    }
})

# OU-Auswahl -> GPOs laden
$treeOU.Add_SelectedItemChanged({
    $selectedItem = $treeOU.SelectedItem
    if ($selectedItem -and $selectedItem.Tag) {
        Set-Status "$($script:L.loadingGPOs) $($selectedItem.Tag)..."
        $includeInherited = $chkIncludeInherited.IsChecked
        $script:allGpoItems = Get-LinkedGPOs -OU_DN $selectedItem.Tag -IncludeInherited $includeInherited
        $script:gpoSearchCache = @{}
        $script:gpoSearchCacheBuilt = $false
        $chkSelectAll.IsChecked = $false
        $txtSearch.Text = ''
        $cmbStatusFilter.SelectedIndex = 0
        Update-GpoFilter
        Set-Status "$($script:L.loadedGPOs) $($selectedItem.Tag)"
    }
})

# Alle auswählen
$chkSelectAll.Add_Checked({
    $items = $gridGPO.ItemsSource
    if ($items) {
        foreach ($item in $items) { $item.Selected = $true }
        $gridGPO.Items.Refresh()
    }
})

$chkSelectAll.Add_Unchecked({
    $items = $gridGPO.ItemsSource
    if ($items) {
        foreach ($item in $items) { $item.Selected = $false }
        $gridGPO.Items.Refresh()
    }
})

# Vererbte GPOs Checkbox
$chkIncludeInherited.Add_Click({
    $selectedItem = $treeOU.SelectedItem
    if ($selectedItem -and $selectedItem.Tag) {
        $includeInherited = $chkIncludeInherited.IsChecked
        $script:allGpoItems = Get-LinkedGPOs -OU_DN $selectedItem.Tag -IncludeInherited $includeInherited
        Update-GpoFilter
    }
})

# Status-Filter
$cmbStatusFilter.Add_SelectionChanged({ Update-GpoFilter })

# Suchfeld - Live-Suche
$txtSearch.Add_TextChanged({ Update-GpoFilter })

# Suche löschen
$btnSearchClear.Add_Click({
    $txtSearch.Text = ''
})

# OU aktualisieren
$btnRefreshOU.Add_Click({ Load-OUTree })

# Alle aufklappen
$btnExpandAll.Add_Click({
    function Expand-AllItems($items) {
        foreach ($item in $items) {
            $item.IsExpanded = $true
            if ($item.Items.Count -gt 0) {
                # Trigger lazy load
                $window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [Action]{})
                Expand-AllItems $item.Items
            }
        }
    }
    Set-Status $script:L.expandingAll
    Expand-AllItems $treeOU.Items
    Set-Status $script:L.expandedAll
})

# Ausgabepfad wählen
$btnBrowse.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $script:L.chooseFolder
    $dialog.SelectedPath = $txtOutputPath.Text
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtOutputPath.Text = $dialog.SelectedPath
    }
})

# Exportieren (ausgewählte GPOs)
$btnExportSelected.Add_Click({
    $selectedGPOs = @($gridGPO.ItemsSource | Where-Object { $_.Selected -eq $true })

    if ($selectedGPOs.Count -eq 0) {
        [System.Windows.MessageBox]::Show(
            $script:L.noSelection,
            $script:L.noSelectionTitle, "OK", "Warning")
        return
    }

    Invoke-GPOExport -GPOsToExport $selectedGPOs
})

# Exportieren (alle sichtbaren GPOs)
$btnExport.Add_Click({
    $allVisible = @($gridGPO.ItemsSource)

    if ($allVisible.Count -eq 0) {
        [System.Windows.MessageBox]::Show(
            $script:L.noGpos,
            $script:L.noGposTitle, "OK", "Warning")
        return
    }

    Invoke-GPOExport -GPOsToExport $allVisible
})

# Sprachumschaltung
$cmbLanguage.Add_SelectionChanged({
    $newLang = if ($cmbLanguage.SelectedIndex -eq 0) { 'de' } else { 'en' }
    if ($newLang -ne $script:lang) {
        Set-AppLanguage $newLang
        Apply-Language
    }
})

# Dark Mode Toggle
$btnDarkMode.Add_Click({ Toggle-DarkMode })

# Verwaiste GPOs suchen
$btnOrphaned.Add_Click({
    $L = $script:L
    Set-Status $L.loadingOrphaned
    $progressBar.Visibility = "Visible"
    $progressBar.IsIndeterminate = $true
    $window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [Action]{})

    try {
        $orphaned = Find-OrphanedGPOs

        if ($orphaned.Count -eq 0) {
            [System.Windows.MessageBox]::Show($L.noOrphaned, $L.orphanedGpos, "OK", "Information")
        } else {
            # Verwaiste GPOs ins Grid laden
            $script:allGpoItems = [System.Collections.ObjectModel.ObservableCollection[GpoItem]]::new()
            foreach ($gpo in $orphaned) {
                $item = New-Object GpoItem
                $item.Selected = $false
                $item.DisplayName = $gpo.DisplayName
                $item.Id = $gpo.Id
                $item.GpoStatusKey = $gpo.GpoStatus.ToString()
                $item.GpoStatus = switch ($gpo.GpoStatus) {
                    "AllSettingsEnabled"        { $L.allEnabled }
                    "AllSettingsDisabled"        { $L.allDisabled }
                    "UserSettingsDisabled"       { $L.userDisabled }
                    "ComputerSettingsDisabled"   { $L.computerDisabled }
                    default                      { $gpo.GpoStatus }
                }
                $item.LinkType = "---"
                $item.CreationTime = $gpo.CreationTime
                $item.ModificationTime = $gpo.ModificationTime
                $item.IsRecentlyModified = ($gpo.ModificationTime -gt (Get-Date).AddDays(-30))
                $item.DomainName = $gpo.DomainName
                $script:allGpoItems.Add($item)
            }
            $script:gpoSearchCache = @{}
            $script:gpoSearchCacheBuilt = $false
            Update-GpoFilter
            $msg = ($L.orphanedFound -f $orphaned.Count)
            [System.Windows.MessageBox]::Show($msg, $L.orphanedGpos, "OK", "Warning")
        }
    } catch {
        [System.Windows.MessageBox]::Show("$($L.loadError) $($_.Exception.Message)", $L.exportErrorTitle, "OK", "Error")
    } finally {
        $progressBar.Visibility = "Collapsed"
        Set-Status $L.statusReady
    }
})

# Änderungshistorie
$btnHistory.Add_Click({
    $L = $script:L
    Set-Status $L.historyBtn
    $progressBar.Visibility = "Visible"
    $progressBar.IsIndeterminate = $true
    $window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [Action]{})

    try {
        $historyMsg = Show-ChangeHistory

        # In neuem Fenster anzeigen
        $histWindow = New-Object System.Windows.Window
        $histWindow.Title = $L.historyTitle
        $histWindow.Width = 700
        $histWindow.Height = 500
        $histWindow.WindowStartupLocation = "CenterOwner"
        $histWindow.Owner = $window

        $textBox = New-Object System.Windows.Controls.TextBox
        $textBox.Text = $historyMsg
        $textBox.IsReadOnly = $true
        $textBox.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
        $textBox.FontSize = 12
        $textBox.VerticalScrollBarVisibility = "Auto"
        $textBox.HorizontalScrollBarVisibility = "Auto"
        $textBox.TextWrapping = "NoWrap"
        $textBox.Margin = New-Object System.Windows.Thickness(10)

        if ($script:isDarkMode) {
            $histWindow.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#1E1E1E")
            $textBox.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#2D2D2D")
            $textBox.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#DDD")
        }

        $histWindow.Content = $textBox
        $histWindow.ShowDialog() | Out-Null
    } catch {
        [System.Windows.MessageBox]::Show("$($L.loadError) $($_.Exception.Message)", $L.exportErrorTitle, "OK", "Error")
    } finally {
        $progressBar.Visibility = "Collapsed"
        Set-Status $L.statusReady
    }
})

# GPO-Vergleich
$btnDiff.Add_Click({
    $L = $script:L
    $selectedGPOs = @($gridGPO.ItemsSource | Where-Object { $_.Selected -eq $true })

    if ($selectedGPOs.Count -ne 2) {
        [System.Windows.MessageBox]::Show($L.diffSelectTwo, $L.diffTitle, "OK", "Warning")
        return
    }

    Set-Status "$($L.diffTitle)..."
    $progressBar.Visibility = "Visible"
    $progressBar.IsIndeterminate = $true
    $window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [Action]{})

    try {
        $diffs = Compare-TwoGPOs -GPO1 $selectedGPOs[0] -GPO2 $selectedGPOs[1]

        # Ergebnis in neuem Fenster anzeigen
        $diffWindow = New-Object System.Windows.Window
        $diffWindow.Title = "$($L.diffTitle): $($selectedGPOs[0].DisplayName) vs $($selectedGPOs[1].DisplayName)"
        $diffWindow.Width = 900
        $diffWindow.Height = 600
        $diffWindow.WindowStartupLocation = "CenterOwner"
        $diffWindow.Owner = $window

        $msg = "$($L.diffTitle)`n"
        $msg += "$($L.diffGpo1): $($selectedGPOs[0].DisplayName)`n"
        $msg += "$($L.diffGpo2): $($selectedGPOs[1].DisplayName)`n"
        $msg += ("=" * 80) + "`n`n"

        if ($diffs.Count -eq 0) {
            $msg += "Keine Unterschiede gefunden / No differences found.`n"
        } else {
            $msg += "$($diffs.Count) $($L.diffDifference)(e):`n`n"
            foreach ($d in $diffs) {
                $msg += "$($L.diffSetting): $($d.Setting)`n"
                $msg += "  $($selectedGPOs[0].DisplayName): $($d.Value1)`n"
                $msg += "  $($selectedGPOs[1].DisplayName): $($d.Value2)`n`n"
            }
        }

        $textBox = New-Object System.Windows.Controls.TextBox
        $textBox.Text = $msg
        $textBox.IsReadOnly = $true
        $textBox.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
        $textBox.FontSize = 12
        $textBox.VerticalScrollBarVisibility = "Auto"
        $textBox.HorizontalScrollBarVisibility = "Auto"
        $textBox.TextWrapping = "NoWrap"
        $textBox.Margin = New-Object System.Windows.Thickness(10)

        if ($script:isDarkMode) {
            $diffWindow.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#1E1E1E")
            $textBox.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#2D2D2D")
            $textBox.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#DDD")
        }

        $diffWindow.Content = $textBox
        $diffWindow.ShowDialog() | Out-Null
    } catch {
        [System.Windows.MessageBox]::Show("$($L.loadError) $($_.Exception.Message)", $L.exportErrorTitle, "OK", "Error")
    } finally {
        $progressBar.Visibility = "Collapsed"
        Set-Status $L.statusReady
    }
})

#endregion

# GUI anzeigen
$window.ShowDialog() | Out-Null
