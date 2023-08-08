<#
.SYNOPSIS
    This script is a set of tools that can help both players and employees operate tools we need to support Overwatch League and other non-Battle.net Overwatch events.
    Note that this is intended for Overwatch and not Overwatch 2. Overwatch 2 has additional arguments that can make our lives a little easier to automate but it may also change/remove arguments we currently use in Overwatch
.DESCRIPTION
    Script provides many functions.
    Tools installation and update through Chocolatey
    Quick system summary
    Updates a game's lobby file so that it can find servers
    Launcher mode that emulates the operation of our old Tournament Launcher that we used for World Cup and Overwatch League
.PARAMETER debug
    Type: Switch
    Starts the Player Tools with the debug window remaining open
.PARAMETER game
    Type: string
    Currently supports both OWL and CDL. CDL has a smaller subset of available tools and you'll want to use the CDL version of the Player Tools and not this one.
    This sets the path of the tools for auxillary usage such as configuring telemetry and monitoring
.PARAMETER preferredgamesource
    Type: string
    This will take either battlenet or a specific path found in the arenaenvironment class under $TournamentGamePaths. It'll "prefer" the highest build of Overwatch it finds over all others for the first pick. It'll also auto-update the lobby json file of this result. If you intend to use a Bitlocker volume and vhdx file, set this to O:\Games
    If it can't determine any builds because preferredgamesource is null or there's no game builds in preferreddgamesource, Player Tools will pick the highest build out of everything it finds
.PARAMETER launchermode
    Type: switch
    Starts Player Tools in Launcher mode. Note that the menu and Chocolatey scan will still happen unless $launchernoplayertoolsmenus is also used. This is basically a shortcut to Tools > Launcher Mode
.PARAMETER launchernoplayertoolsmenus
    Type: switch
    Hides unnecessary troubleshooting and OpenVPN menus and disables the Chocolatey scan. Use this with $launchermode to put the Player Tools in a strictly-Launcher mode
.PARAMETER adminmode
    Type: switch
    Intended to help the game admins launch their version of Overwatch similar to the old Overwatch Tournament Launcher. Note that the admins will need to switch to Launcher Mode through the Tools menu or you can use $launchermode to help them along.\
.PARAMETER skipchococheck
    Type: switch
    It is for me to skip the Chocolatey check when I'm trying to write features so it doesn't spam my chocolatey.log file...
.PARAMETER safemode
    Type: switch
    Intended to rename Overwatch.exe to something else and run that. Gets around strange driver profiles forcing things upon the game.
.PARAMETER safemodepath
    Type: string
    Tells safe mode the parent path of the Overwatch folder that you want to run in Safe Mode. This only kicks in if safemode is active. This is intended to be in an elevated PS session from within the parent playertools script itself with all necessary arguments passed.
.PARAMETER updatejson
    Runs the Player Tools script to only update the lobby json file and nothing else. You'll need to provide $jsongamepath and $jsonsourcepath. This is intended to be in an elevated PS session from within the parent playertools script itself with all necessary arguments passed.
.PARAMETER jsongamepath
    Full Path of Overwatch where you wish to place the json file
.PARAMETER jsonsourcepath
    URI of the lobby file you wish to pull down
.PARAMETER mountvhdx
    Runs the Player Tools script to only mount a vhdx file. You'll need vhdxpath and vhdxpassword. This is intended to be in an elevated PS session from within the parent playertools script itself with all necessary arguments gathered and passed.
.PARAMETER vhdxpath
    Full Path of the VHDX file
.PARAMETER vhdxpassword
    Type: string
    Password for the VHDX file from a secure string ran thru ConvertFrom-SecureString because I can't figure out how to pass the thing as a param thru Start-Process...
.INPUTS
    None
.OUTPUTS
    Console
  
.EXAMPLE
    ./playertools.ps1
    ./playertools.ps1 -launchermode
    ./playertools.ps1 -launchermode -launchernoplayertools
    ./playertools.ps1 -adminmode -launchermode
#>
param(
	[switch]$debug,
    [string]$game = "OWL",
    [string]$preferredgamesource = "battlenet",
    [switch]$launchermode,
    [switch]$launchernoplayertoolsmenus,
    [switch]$adminmode,
    [switch]$safemode,
    [switch]$skipchococheck,

    [string]$safemodepath,

    [switch]$updatejson,
    [string]$jsongamepath,
    [string]$jsonsourcepath,

    [switch]$mountvhdx,
    [string]$vhdxpath,
    [string]$vhdxpassword
)

#######################
## Elevated stuff    ##
#######################

function Update-JsonFile
{
    param(
        $jsonpath = $jsongamepath,
        $jsonuri = $jsonsourcepath
    )
    try{
        Write-Host "     Writing updating lobby file to $jsonpath" -ForegroundColor Yellow
        $todayaffix = (Get-Date).ToString('yyyyMMdd-HHmmss')
        if (Test-Path -path $jsonpath)
        {
            Rename-Item -Path $jsonpath -NewName "showmodeLobbyLocations.$todayaffix.json" -Force -ErrorAction Stop
        }
        Invoke-WebRequest -Uri $jsonuri -UseBasicParsing -OutFile $jsonpath -Verbose -ErrorAction Stop
        Write-Host "     $jsonpath written successfully" -ForegroundColor Green
    }
    catch
    {
        Write-Host $_.Exception.Message -ForegroundColor Red
        throw $_
    }
}

if($updatejson)
{
    Update-JsonFile -jsonpath $jsongamepath -jsonuri $jsonsourcepath
    exit
}

if($mountvhdx)
{
    if ($vhdxpassword)
    {
        try 
        {
            $vhdxmountpw = $vhdxpassword | ConvertTo-SecureString
            $vhddriveltr = "O"
            $diskpartscript = "SELECT VDISK FILE=`"$vhdxpath`"`r`nATTACH VDISK`r`nSELECT PARTITION 1`r`nASSIGN LETTER=$vhddriveltr"
            $diskpartscript | diskpart
            Write-Output "Waiting for diskpart to finish..."
            #Mount-DiskImage does not work right for classic games. They'll constantly load into a black screen. FML
            #Mount-DiskImage -ImagePath $vhdpath -StorageType VHDX
            #$driveletter = (get-volume | Where-Object {$_.OperationalStatus -eq 'Unknown' -and $_.DriveType -eq 'Fixed'}).DriveLetter
            Start-Sleep -seconds 5
            Unlock-Bitlocker -MountPoint $vhddriveltr -Password $vhdxmountpw
            Start-Sleep -seconds 5
            ie4uinit.exe -ClearIconCache
            ie4uinit.exe -show
        }
        catch {
            throw $_
        }
    }
    else 
    {
        throw "No credentials supplied. Unable to mount $vhdxpath"    
    }
    exit
}

function Rename-Safemode
{
    param(
        [string]$path,
        [switch]$admin
    )
    try 
    {
        if ($admin)
        {
            Copy-Item -Path (Join-Path -Path $path -ChildPath "OverwatchGM.exe") -Destination (Join-Path -Path $path -ChildPath "OWGMSafe.exe") -Force -Verbose
        }
        else
        {
            Copy-Item -Path (Join-Path -Path $path -ChildPath "Overwatch.exe") -Destination (Join-Path -Path $path -ChildPath "OWSafe.exe") -Force -Verbose
        }
    }
    catch
    {
        throw $_
    }
}

if ($safemode -and $safemodepath)
{
    if ($adminmode)
    {
        Rename-Safemode -path $safemodepath -admin
    }
    else 
    {
        Rename-Safemode -path $safemodepath
    }
    exit
}

#############################
## Global vars and classes ##
#############################

$scriptpath = $MyInvocation.MyCommand.Definition
$launcherbasefolder = (Join-Path -Path ([Environment]::GetFolderPath("MyDocuments")) -ChildPath "Blizzard")
$playernamefile = Join-Path -Path $launcherbasefolder -ChildPath "name.txt" 
$playerlocaleselectionjsonfile = Join-Path -Path $launcherbasefolder -ChildPath "tournLocale.txt"

$realmlist = "https://owl-deploy.s3-us-west-2.amazonaws.com/showmodeLobbyLocations.json"
$script:windowlaunchermode = $launchermode

#credential window control rig because maybe the user will want to open more than 1 per session and PowerShell hates that...
#tracks if we hit the OK button. Gotta make sure to set it back to false after we're done reading creds.
$script:credwindowok = $false

Add-Type -AssemblyName PresentationFramework, System.Drawing
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();

[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'

class LocaleSettings
{
    [string]$AudioLocale
    [string]$Locale
}

class OpenVPNCreds
{
    [string]$realm
    [string]$chocoinstallpw
}

class OverwatchClient
{
    [string]$build
    [string]$FriendlyName
    [string]$FullPath
    [string]$scansource
    [string]$bnetaudiolocale
    [string]$bnetlocale
}

class ArenaEnvironment
{
    [string]$Launcher = $scriptpath
    [string[]]$TournamentGamePaths = "C:\Games", "C:\Blizzcon\Games", "C:\OWL", "D:\Games", "D:\OWL", "C:\Events\Games", "D:\Events\Games", "O:\Games", "T:\Games", (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
    [string]$BuildPreference = $preferredgamesource
    [string]$LocaleFolder = (Join-Path -Path ([Environment]::GetFolderPath("MyDocuments")) -ChildPath "Blizzard")
    [string]$PlayerLocaleSettings = (Join-Path -Path (Join-Path -Path ([Environment]::GetFolderPath("MyDocuments")) -ChildPath "Blizzard") -ChildPath "tournLocale.txt")
    [string[]]$Locale = "deDE", "enUS", "esES", "esMX", "frFR", "itIT", "jaJP", "koKR", "plPL", "ptBR", "ruRU", "zhCN", "zhTW"
    [string[]]$AudioLocale = "deDE", "enUS", "esES", "esMX", "frFR", "itIT", "jaJP", "koKR", "plPL", "ptBR", "ruRU", "zhCN", "zhTW"
    [string]$BaseArgumentsFile = "Launch_OW_Tournamentmode.bat"
    [string]$BaseArgumentsAdminFile = "Launch_OW_TournamentmodeAdmin.bat"
    [string]$CustomizationBGInfoPath = "C:\OWL\tools\bginfo"
    [string]$CustomizationBGInfoBackgroundPath = "C:\OWL\tools\bginfo\bg"
    [bool]$OptimizationChanged = $false
    [string]$EncryptedPath = "O:\"
    [string]$EncryptedVHDName = "Overwatch.vhdx"
    [string]$RealmlistURL = $realmlist
    [string]$TelegrafComputerName = $env:TELEGRAF_HOSTNAME
    [string]$TelegrafTeamName = $env:TELEGRAF_TEAMNAME
    [string[]]$OpenVPNProfiles = "CN-Beijing", "EU-Frankfurt", "JP-Tokyo", "KR-Seoul", "US-North California", "US-North Virginia", "US-Ohio", "US-Iowa"
    [string[]]$LegacyOpenVPNProfiles = "california", "uscentral", "useast", "seoul", "china", "tokyo"
    $gamebuilds = [System.Collections.ArrayList]@()

    AddClient([OverwatchClient]$client)
    {
        $this.gamebuilds.Add($client)
    }

    ClearClientList()
    {
        if ($this.gamebuilds.Length -gt 0)
        {
            $this.gamebuilds.Clear()
        }
    }

    [OverwatchClient] GetClientByBuild([string]$build)
    {
        foreach ($gamebuild in $this.gamebuilds)
        {
            if ($gamebuild.build -eq $build)
            {
                return $gamebuild
            }
        }
        return $null
    }

    [OverwatchClient] GetClientByFriendlyName([string]$friendlyname)
    {
        foreach ($gamebuild in $this.gamebuilds)
        {
            if ($gamebuild.FriendlyName -eq $friendlyname)
            {
                return $gamebuild
            }
        }
        return $null
    }
}

$script:arenaenv = New-Object ArenaEnvironment
$script:currentgame

if (Test-Path -Path $playerlocaleselectionjsonfile -ErrorAction Ignore)
{
    $script:localesettings = Get-Content $playerlocaleselectionjsonfile -Raw | ConvertFrom-Json
}


########################
## create main window ##
########################

#$xamlMainWindowfile = Join-Path -Path $PSScriptRoot -ChildPath "telegraf.xaml"
#$inputXMLMainWindow = Get-Content $xamlMainWindowfile -Raw
$inputXMLMainWindow = @"
<Window x:Class="Powershell_WPF_Templates.PlayerTools"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        xmlns:local="clr-namespace:Powershell_WPF_Templates"
        mc:Ignorable="d"
        Title="PlayerTools" Height="500" Width="800" ResizeMode="CanMinimize">
    <Window.TaskbarItemInfo>
        <TaskbarItemInfo/>
    </Window.TaskbarItemInfo>
    <DockPanel LastChildFill="false">
        <StatusBar DockPanel.Dock="Bottom" Height="30" >
            <StatusBarItem>
                <TextBlock Name="lblStatus" Text="Batman"/>
            </StatusBarItem>
        </StatusBar>
        <Menu DockPanel.Dock="Top" Margin="0">
            <Menu.ItemsPanel>
                <ItemsPanelTemplate>
                    <DockPanel HorizontalAlignment="Stretch"/>
                </ItemsPanelTemplate>
            </Menu.ItemsPanel>
            <MenuItem  x:Name="menu_mainplayertools_file" Header="_File">
                <MenuItem x:Name="menu_exit" Header="_Exit" />
            </MenuItem>
            <MenuItem x:Name="menu_mainplayertools_openvpn" Header="_OpenVPN">
                <MenuItem x:Name="menu_openvpn_opengui" Header="Open GUI">
                    <MenuItem.Icon>
                        <Image x:Name="img_ovpn_opengui"></Image>
                    </MenuItem.Icon>
                </MenuItem>
                <MenuItem x:Name="menu_openvpn_openlogs" Header="Open Logs folder">
                    <MenuItem.Icon>
                        <Image x:Name="img_exp_openvpn_openlogs"></Image>
                    </MenuItem.Icon>
                </MenuItem>
                <Separator x:Name="menu_mainplayeropenvpn_separatorone" HorizontalAlignment="Left" Height="10"/>
                <MenuItem x:Name="menu_openvpn_switch" Header="_Update and switch OpenVPN Realm">
                    <MenuItem.Icon>
                        <Image x:Name="img_cmd_openvpn_switch"></Image>
                    </MenuItem.Icon>
                </MenuItem>
                <Separator x:Name="menu_mainplayeropenvpn_separatortwo" HorizontalAlignment="Left" Height="10"/>
                <MenuItem x:Name="menu_openvpn_addtap" Header="_Add TAP Adapter">
                    <MenuItem.Icon>
                        <Image x:Name="img_cmd_openvpn_addtap"></Image>
                    </MenuItem.Icon>
                </MenuItem>
                <MenuItem x:Name="menu_openvpn_removetap" Header="_Remove all TAP Adapters">
                    <MenuItem.Icon>
                        <Image x:Name="img_cmd_openvpn_removetap"></Image>
                    </MenuItem.Icon>
                </MenuItem>
            </MenuItem>
            <MenuItem x:Name="menu_mainplayertools_tools" Header="_Tools">
                <MenuItem x:Name="menu_mainplayertools_chocoexpand" Header="_Chocolatey">
                    <MenuItem x:Name="menu_chocoupdateall" Header="_Update All">
                        <MenuItem.Icon>
                            <Image x:Name="img_cmd_chocoupdateall"></Image>
                        </MenuItem.Icon>                       
                    </MenuItem>
                    <Separator />
                    <MenuItem x:Name="menu_chocofixcreds" Header="_Fix Credentials" IsEnabled="False">
                        <MenuItem.Icon>
                            <Image x:Name="img_cmd_chocofixcreds"></Image>
                        </MenuItem.Icon>
                    </MenuItem>
                </MenuItem>
                <MenuItem x:Name="menu_mainplayertools_troubleshootexpand" Header="_Troubleshooting">
                    <MenuItem x:Name="menu_openchocologpath" Header="_Open Chocolatey Logs Folder">
                        <MenuItem.Icon>
                            <Image x:Name="img_exp_openchocologpath"></Image>
                        </MenuItem.Icon>
                    </MenuItem>
                    <MenuItem x:Name="menu_openopenvpnlogpath" Header="_Open OpenVPN Logs Folder">
                        <MenuItem.Icon>
                            <Image x:Name="img_exp_openopenvpnlogpath"></Image>
                        </MenuItem.Icon>
                    </MenuItem>
                </MenuItem>
                <Separator x:Name="menu_mainplayertools_separatorone" />
                <MenuItem x:Name="menu_mainplayertools_telegrafexpand" Header="T_elegraf">
                    <MenuItem x:Name="menu_configmonitoring" Header="Configure _Monitoring (Telegraf)">
                        <MenuItem.Icon>
                            <Image x:Name="img_ps_configmonitoring"></Image>
                        </MenuItem.Icon>
                    </MenuItem>
                    <MenuItem x:Name="menu_stopmonitoring" Header="_Stop Monitoring (Telegraf)">
                        <MenuItem.Icon>
                            <Image x:Name="img_ps_stopmonitoring"></Image>
                        </MenuItem.Icon>
                    </MenuItem>
                    <MenuItem x:Name="menu_startmonitoring" Header="_Start Monitoring (Telegraf)">
                        <MenuItem.Icon>
                            <Image x:Name="img_ps_startmonitoring"></Image>
                        </MenuItem.Icon>
                    </MenuItem>
                </MenuItem>
                <Separator x:Name="menu_mainplayertools_separatortwo" />
                <MenuItem x:Name="menu_debug" Header="Player Tools Debug Mode">
                    <MenuItem.Icon>
                        <Image x:Name="img_ps_debugmode"></Image>
                    </MenuItem.Icon>
                </MenuItem>
                <MenuItem x:Name="menu_launchermode" Header="Switch Player Tools to Launcher Mode"></MenuItem>
                <Separator x:Name="menu_mainplayertools_separatorthree" />
                <MenuItem x:Name="menu_reinstalleverythihng" Header="Reinstall entire environment">
                    <MenuItem.Icon>
                        <Image x:Name="img_ew_reinstalleverything"></Image>
                    </MenuItem.Icon>
                </MenuItem>
            </MenuItem>
            <MenuItem x:Name="menu_isadmin" Header="Role: Admin" Background="#FF00FF17" HorizontalAlignment="Right" Visibility="Collapsed" />
            <MenuItem x:Name="menu_uimode" Header="Current UI Mode: Tools" Background="#FF00FF17" HorizontalAlignment="Right"/>
        </Menu>
        <Canvas x:Name="canvas_mainwindow" >
            <Grid x:Name="grid_main" Margin="0,5,0,0" Width="790">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="auto" />
                    <ColumnDefinition Width="*" />
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="auto" />
                    <RowDefinition Height="auto" />
                    <RowDefinition Height="auto" />
                    <RowDefinition Height="*" />
                </Grid.RowDefinitions>
                <GroupBox x:Name="grpbx_info" Header="System Info" Width="300" Height="375" VerticalAlignment="Top" Grid.Row="0" Margin="5,0" Grid.Column="0" Grid.ColumnSpan="1">
                    <ScrollViewer MaxHeight="350">
                        <TextBlock x:Name="lbl_sysinfo" TextWrapping="WrapWithOverflow" Width="270" Text="Placeholder" HorizontalAlignment="Left" VerticalAlignment="Top" />
                    </ScrollViewer>
                </GroupBox>
                <GroupBox x:Name="grpbx_software" Header="Chocolatey Software Installed" Width="auto" Height="375" VerticalAlignment="Top" Grid.Row="0" Margin="5,0" Grid.Column="1" Grid.ColumnSpan="1">
                    <DataGrid x:Name="dg_software" Height="350" AlternationCount="2" AlternatingRowBackground="#FFA7F7FF">
                        <DataGrid.Columns>
                            <DataGridTextColumn Header="Software Name" Binding="{Binding packagename}" IsReadOnly="True" CanUserResize="False" Width="*"></DataGridTextColumn>
                            <DataGridTextColumn Header="Version" Binding="{Binding version}" CanUserResize="False" IsReadOnly="True"></DataGridTextColumn>
                            <DataGridTextColumn Header="Update Available" Binding="{Binding updatedversion}" CanUserResize="False" IsReadOnly="True"></DataGridTextColumn>
                        </DataGrid.Columns>
                    </DataGrid>
                </GroupBox>
                <StackPanel Grid.Row="1" Grid.ColumnSpan="2" VerticalAlignment="Bottom" HorizontalAlignment="Right" Orientation="Horizontal" Margin="12,0">
                    <Button x:Name="btn_updatelobbyjson" Content="Update Lobby Data" Margin="0,0,8,0" IsEnabled="False" />
                    <Button x:Name="btn_refresh" Content="Refresh Software" Margin="0,0,8,0" />
                    <Button x:Name="btn_updatechoco" Content="Update Software" />
                </StackPanel>
            </Grid>
        </Canvas>
        <Canvas Name="canvas_launcher" >
            <Grid x:Name="grid_launcher" Margin="0,5,0,0" Width="570">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition x:Name="launcher_UIColumnLeft" Width="460" />
                    <ColumnDefinition x:Name="launcher_UIColumnRight" Width="*" />
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition x:Name="launcher_UIRowBuild" Height="36" />
                    <RowDefinition x:Name="launcher_UIRowLocale" Height="36" />
                    <RowDefinition x:Name="launcher_UIRowNameandTeam" Height="36" />
                </Grid.RowDefinitions>
                <Button x:Name="btn_launcher_startgame" Content="Start" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Width="88" Height="90" Grid.Column="1" Grid.Row="0" Grid.RowSpan="3" Visibility="Visible" />
                <Button x:Name="btn_launcher_startadmingame" Content="Start Admin" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Width="88" Grid.Column="1" Grid.Row="0" Grid.RowSpan="2" Visibility="Collapsed" Margin="0,0,0,2" />
                <Button x:Name="btn_launcher_startnormalgame" Content="Start Normal" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Width="88" Grid.Column="1" Grid.Row="2" Visibility="Collapsed" Margin="0,2" />
                <StackPanel Grid.Row="0" Orientation="Vertical" Margin="0,0,0,0">
                    <WrapPanel Orientation="Horizontal" VerticalAlignment="Top" Width="auto" Margin="10,5,0,5">
                        <WrapPanel Orientation="Horizontal" Margin="0,0,10,0">
                            <Label x:Name="lbl_launcher_build" Content="Build: " HorizontalAlignment="Left" VerticalAlignment="Center" Width="87" MinWidth="87"/>
                        </WrapPanel>
                        <WrapPanel Orientation="Horizontal" HorizontalAlignment="Right" Width="auto">
                            <Label x:Name="lbl_launcher_diff" Content="Start This Build:" HorizontalAlignment="Left" VerticalAlignment="Center"/>
                            <ComboBox x:Name="dropdown_launcher_BuildSelector" HorizontalAlignment="Right" VerticalAlignment="Center" Width="220" />
                        </WrapPanel>
                    </WrapPanel>
                </StackPanel>
                <StackPanel Grid.Row="1" Orientation="Vertical" Margin="0,0,0,0">
                    <WrapPanel Orientation="Horizontal" VerticalAlignment="Top" Width="auto" Margin="10,5,0,5">
                        <Label x:Name="lbl_launcher_Locale" Content="Locale:" VerticalAlignment="Center" />
                        <ComboBox x:Name="dropdown_launcher_Locale"  VerticalAlignment="Center" Width="59" />
                        <Label x:Name="lbl_launcher_Audio" Content="Audio:" VerticalAlignment="Center" Margin="5,0,0,0" />
                        <ComboBox x:Name="dropdown_launcher_Audio" Width="59" VerticalAlignment="Center" />
                        <CheckBox x:Name="chkbx_launcher_applybackground" Content="Set Wallpaper" VerticalAlignment="Center" HorizontalAlignment="Left" Margin="5,0,0,0" IsEnabled="False" />
                        <CheckBox x:Name="chkbx_launcher_updaterealmlist" Content="Update Pods" VerticalAlignment="Center" HorizontalAlignment="Left" Margin="5,0,0,0" IsChecked="True" IsEnabled="False"></CheckBox>
                    </WrapPanel>
                </StackPanel>
                <StackPanel Grid.Row="2" Orientation="Vertical" Margin="0,0,0,0">
                    <WrapPanel Orientation="Horizontal" VerticalAlignment="Top" Width="auto" Margin="10,5,0,5">
                        <Label x:Name="lbl_launcher_Name" Content="Name:" IsEnabled="False"/>
                        <TextBox x:Name="txtbx_launcher_playername" HorizontalAlignment="Left" Height="23" TextWrapping="Wrap" Width="114" IsEnabled="False" />
                        <Label x:Name="lbl_launcher_team" Content="Team:" HorizontalAlignment="Left" VerticalAlignment="Top" IsEnabled="False"/>
                        <ComboBox x:Name="dropdown_launcher_Team" HorizontalAlignment="Left" VerticalAlignment="Top" Width="210" IsEnabled="False" />
                    </WrapPanel>
                </StackPanel>
            </Grid>
        </Canvas>
    </DockPanel>
</Window>
"@

$inputXMLMainWindow = $inputXMLMainWindow -replace 'mc:Ignorable="d"', '' -replace "x:N", 'N' -replace '^<Win.*', '<Window'
[XML]$xamlMainWindow = $inputXMLMainWindow

#Read XAML
$reader = (New-Object System.Xml.XmlNodeReader $xamlMainWindow)
try {
    $window = [Windows.Markup.XamlReader]::Load( $reader )
} catch {
    Write-Warning $_.Exception
    throw
}
# Create variables based on form control names.
# Variable will be named as 'var_<control name>'

$xamlMainWindow.SelectNodes("//*[@Name]") | ForEach-Object {
    #"trying item $($_.Name)"
    try {
        Set-Variable -Name "var_$($_.Name)" -Value $window.FindName($_.Name) -ErrorAction Stop
    } catch {
        throw
    }
}

#######################
## create VPN window ##
#######################

$inputXMLOpenVPNWindow = @"
<Window x:Class="Powershell_WPF_Templates.OpenVPN"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        xmlns:local="clr-namespace:Powershell_WPF_Templates"
        mc:Ignorable="d"
        Title="OpenVPN Profile Installer/Updater" Height="135" Width="340" ResizeMode="NoResize" WindowStartupLocation="CenterOwner">
    <Window.Background>
        <ImageBrush Stretch="UniformToFill"/>
    </Window.Background>
    <Grid Margin="0">
        <Grid.ColumnDefinitions>
            <ColumnDefinition x:Name="UIColumnLeft" Width="50" />
            <ColumnDefinition x:Name="UIColumnMiddle" Width="100" />
            <ColumnDefinition x:Name="UIColumnRight" Width="*" />
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition x:Name="UITopPad" Height="10" />
            <RowDefinition x:Name="UIUserName" Height="30" />
            <RowDefinition x:Name="UIPassword" Height="30"/>
            <RowDefinition x:Name="UIButtons" Height="*"/>
        </Grid.RowDefinitions>
        <DockPanel Grid.Column="0" Grid.RowSpan="4"/>
        <DockPanel Grid.Column="1" Grid.Row="1" VerticalAlignment="Center">
            <Label x:Name="lbl_username" Content="VPN Endpoint" Height="30" VerticalAlignment="Top" Foreground="White"/>
        </DockPanel>
        <DockPanel x:Name="auth_dock_vpn" Grid.Column="2" Grid.Row="1" VerticalAlignment="Center">
            <ComboBox x:Name="auth_comboboxname" Height="24" Margin="0,0,5,0" TabIndex="1" Opacity="0.7"/>
        </DockPanel>
        <DockPanel x:Name="auth_dock_user" Grid.Column="2" Grid.Row="1" VerticalAlignment="Center" Visibility="Collapsed">
            <TextBox x:Name="auth_txtbx_user" Height="24" Margin="0,0,5,0" TabIndex="1" Opacity="0.7" />
        </DockPanel>
        <DockPanel Grid.Column="1" Grid.Row="2" VerticalAlignment="Center">
            <Label x:Name="lbl_password" Content="Password" Height="30" VerticalAlignment="Top" Foreground="White"/>
        </DockPanel>
        <DockPanel Grid.Column="2" Grid.Row="2" VerticalAlignment="Center" Opacity="0.95">
            <PasswordBox x:Name="auth_txtbxpasswd" Height="24" DockPanel.Dock="Left" Margin="0,0,5,0" TabIndex="2" Opacity="0.7"/>
        </DockPanel>
        <DockPanel Grid.ColumnSpan="2" Grid.Column="1" Grid.Row="3" VerticalAlignment="Center" HorizontalAlignment="Right">
            <Button x:Name="btn_Cancel" Content="Cancel" Width="75" Margin="5,0" TabIndex="4" IsCancel="True" />
            <Button x:Name="btn_OK" Content="Ok" Width="75" Margin="5,0" TabIndex="3" IsDefault="True" />
        </DockPanel>
    </Grid>
</Window>

"@

$inputXMLOpenVPNWindow = $inputXMLOpenVPNWindow -replace 'mc:Ignorable="d"', '' -replace "x:N", 'N' -replace '^<Win.*', '<Window'
[XML]$xamlOpenVPNWindow = $inputXMLOpenVPNWindow

#Read XAML
$openvpnreader = (New-Object System.Xml.XmlNodeReader $xamlOpenVPNWindow)
try {
    $openvpnwindow = [Windows.Markup.XamlReader]::Load( $openvpnreader )
} catch {
    Write-Warning $_.Exception
    throw
}
# Create variables based on form control names.
# Variable will be named as 'var_ovpn_<control name>'

$xamlOpenVPNWindow.SelectNodes("//*[@Name]") | ForEach-Object {
    try {
        Set-Variable -Name "var_ovpn_$($_.Name)" -Value $openvpnwindow.FindName($_.Name) -ErrorAction Stop
    } catch {
        throw
    }
}



#######################################
## Images to make things look pretty ##
#######################################

$bmp_sombrawindow = New-Object System.Windows.Media.Imaging.BitmapImage
$bmp_sombrawindow.BeginInit()
$bmp_sombrawindow.StreamSource = [System.IO.MemoryStream][System.Convert]::FromBase64String("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")
$bmp_sombrawindow.EndInit()
$bmp_sombrawindow.Freeze()

$bmp_owicon = New-Object System.Windows.Media.Imaging.BitmapImage
$bmp_owicon.BeginInit()
$bmp_owicon.StreamSource = [System.IO.MemoryStream][System.Convert]::FromBase64String("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")
$bmp_owicon.EndInit()
$bmp_owicon.Freeze()

$bmp_cmdicon = New-Object System.Windows.Media.Imaging.BitmapImage
$bmp_cmdicon.BeginInit()
$bmp_cmdicon.StreamSource = [System.IO.MemoryStream][System.Convert]::FromBase64String("iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAACUSURBVDhPYxhwwNg/afp/KJsswAIiXNw9wRx8YOqCjQzZCf4otLokG8QF1lZmUGWkgaPHTjEwQL1AFgbpZQIyKAIoBvz//x+M0QE2MRiAGwBSxMjICMYwDfg0wgBWL4AMQaZBAJdhWA1AdwGyQegAbgDM6SCMzQUwAFMDAyguAGnAZRuyochqsHqBFEBxXqAQMDAAAOm8Tp13gs3IAAAAAElFTkSuQmCC")
$bmp_cmdicon.EndInit()
$bmp_cmdicon.Freeze()


$bmp_expicon = New-Object System.Windows.Media.Imaging.BitmapImage
$bmp_expicon.BeginInit()
$bmp_expicon.StreamSource = [System.IO.MemoryStream][System.Convert]::FromBase64String("iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsIAAA7CARUoSoAAAAF3SURBVDhPxVI9SwNBEH2bCyd+NAYtUhgIFiFBUUsLCwvFWrCysxAbG3+IjSBokT8gWFkppLRWUmihBLQQjVwQE1Z3c7vO7B6BxBPLPHi7t/Nm3s3sHYYOwUujipoQKLpIAmsRSYXtyh7uk1AqnMHDCaw7DWA8v/A2UVi5To59yGbDxujc4YEzeL1Y/mUQhGPIFUqgzv6EKB172d7tpnbwH0T5VGTck9WeRsP+Q87p5RO8genCxBpKK0j5hXZHppI1zuFcrmFkebHkppXBVXMRR89bUCZw4iDCTIz9mTOsTd8gDP273WrJTZNzrVlBW2egYptK1mrNssvt68DPHlMnxh1nRxrYzF0iCPwniKn4PFrH43cRhn4QLrbG33tyieRGY5guU2FSvGN16hYb+bojP3OMNUv0l+g78AYqkkK3KN6GUZL2DoK4RYwSstbpaaBcruFSN4KSrSVhbP7pM7cTWjVPe13EH1XR9SMIGmFQU1K8OHHIAH4ASy4KTbhPsksAAAAASUVORK5CYII=")
$bmp_expicon.EndInit()
$bmp_expicon.Freeze()

$bmp_psicon = New-Object System.Windows.Media.Imaging.BitmapImage
$bmp_psicon.BeginInit()
$bmp_psicon.StreamSource = [System.IO.MemoryStream][System.Convert]::FromBase64String("iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAH5SURBVDhPpVJNSFRRFP7ufX/z46SVM4NghAMlSosWEq6MDJIIpZ2riqBWkREtWjTUpoXuolUboUW0SVpJ20Q3QhttEYaos4icDF2MmM7Pm9s55715k7qbDhzOOffe852f+yljDP5HdGhblqiDyxNzxmtLi68U4SrFXuQriXVgJSbfcpoAI/kVk8r04lIOMHUfi6sVGL+Ger0qsfGr5NfIpzM6Z2t7bcEIXN12k5RpcOMi8HTMxpV+FSZQMieJPaxK240dKDjxDjmc/lzGXtng7pDG2VNcnZODikf9qAPLiYny5Xqximfvd6EtF5O30+hJa3rc6KLZEc9v2V4A4CZOHkJeK5bx8sMOkjGNyTsZVP7shImkMr8PGZkWqYefLBquHj0g5ar3r51gbHxb38R+afPYGJYTx8fHrtJKWRQkosvRAQ+v751GLutg6u08Hr76gkR7twA3tSZds9jadmWehOPj0c0UBs97WCn8xvM3c8h29eDBeB99Tp3/VuzC8hY2tmj7NL8AWDQLI44NxCT53aclTM+uwunow+iFLG5dDcjVkF/FAn7sZsOI1nD9xYax3DjSKYPK9lcUtjWS7WcElPVcZwl+7UA4Uto7wNrPfWRyQ5jNdzE1oUby341Q8ihV+YP+oS05pAFrmfIzE5LQpHKrEjKxVQH+ArjOHQCLt+PVAAAAAElFTkSuQmCC")
$bmp_psicon.EndInit()
$bmp_psicon.Freeze()

$bmp_openvpnicon = New-Object System.Windows.Media.Imaging.BitmapImage
$bmp_openvpnicon.BeginInit()
$bmp_openvpnicon.StreamSource = [System.IO.MemoryStream][System.Convert]::FromBase64String("iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAACaSURBVDhPxZLRDYAgDESLOzmFQ6nLsIFTuIHLYA8EC1og8cOXkJ6hraetoZuJzxgk7Xy2IOvEBr7YOTfjwRizInZgr0gLFztEqRFrICc6QPIc3yy1RswZWMN+RlHsXRUnQ7WKu5DyIH0mHHzi/waYglygbvgXPCbVnHsJarRVTnBebTutbCBJ43tpgPU9gtTp3o2mA4XWfS9EJ+MmuZ/g0nQwAAAAAElFTkSuQmCC")
$bmp_openvpnicon.EndInit()
$bmp_openvpnicon.Freeze()

$bmp_ewicon = New-Object System.Windows.Media.Imaging.BitmapImage
$bmp_ewicon.BeginInit()
$bmp_ewicon.StreamSource = [System.IO.MemoryStream][System.Convert]::FromBase64String("iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsIAAA7CARUoSoAAAAOXSURBVDhPLVNNaBtHGH2zo93qb1XJlirZkWxZtSojV05QcCGyHbtpKQFXBFzS3BpCoKSQEENCwOm10EsOvfbUcw7uxTSQ0ECDWztqE6l1IgeskCJLsSXZlvWzlna12t2OTAfeZfje+9437xuC/08gECDj4+PeeDz+RWh4eGGgvz/ssFg9hqGjKcv7uwcHW2/y+Z/T6fRyNpstFwoFo8c7FvD7/VwymUzMJhLfR32+j/qqVZO6sUG0SgWq2oXucICERw1paKj7ulb/c/Xp+tLKyspasVjUaa8zI0/Nnzv3U5znJ6xPnlB9dZUYb3eg1+vQmg1oe2XIm6+Ims1Sz7uOgO/UqTlqNj8vlcsFOpVI+C7Mz/940jAm6MOHhJOaoCf8kHbeoqNqULoqFFWFKRSC1m6jls6QPpfT6YjFIkzgAf3y4sXLs9HoVeHRI0pYR9/duxCTSbR3dlDL5aB0OhDicVi/uQbhwxgO1/5AfXOTDE5ODkqCsM2FgsEFaz5v6vz7Bq1WC4okATYb3NevwzYzAxMjW65cAcwWQOuitr+PZrEI9dkzGhoaWqBff3X5O2sq5VDZpcwE9tfWYQoGobndMMbGoEej0AUBRj6P9OIi1O1t6IrCxHRin5riObvAe1qFbbTZnDJDo1jAPzduYDeVQkOWIes6+MNDbNy5A1IowGQYx2izOiulHk5naXZYkax2cMTsNVgRCQSgiCLkngBDhcEV+QDiOA/XJIWFMyAcLwEBJ3WUPbhcaFWraLDczYkEXLdvg3c6Yd7bg5TJsPnN8CxeRejbEYwu+eHwE4gDA2h1u3tc6bCag8sJ6aAK4vWi7+bNY3LP7satW2jeuwe8fME6PkV/xAF31A/n53Y456aN/dZRjsZiE2I4MvZZbX2dazXY0lAKG7P/YmkJlInwLHvk/kLf2V08znSwvFLG3AXm2HtWS2VLP3CZTGa5KAipE5cuGQbHYff+fWSYC4OlwrExeRiwnzyC+30LZIU9ck2Be8QFRV7efv3q8S9UUZQjs822FThzZtbr8bjqWzmis13ovbTAYPMSDFzrg2fEDjOnIjhIEfLz4PQD06BY/JU2mO1SqVRku53uP306Mnr+/IDL6+M4yoEYGnF8omP4YytMSgO//V7F878lTMeYODXe0dSuSHtpMBGjzD7GbqXyQKK0gHDYIk5P8+KnM2Z7aIND95BIdRmiWcOIj+WuddA6UqDq5L3/AIYcsEgytfqaAAAAAElFTkSuQmCC")
$bmp_ewicon.EndInit()
$bmp_ewicon.Freeze()

#attach sombra window...
$openvpnwindow.Background.ImageSource = $bmp_sombrawindow

#attach the icons
$window.Icon = $bmp_owicon
$window.TaskbarItemInfo.Overlay = $bmp_owicon
#note. window.TaskbarItemInfo.ProgressState -> 0 is no indicators, 1 is the scrolly green, 2 is normal, 3 is red, 4 is paused

$iconitems = Get-Variable var_img_cmd_* -ValueOnly
foreach ($item in $iconitems)
{
    $item.Source = $bmp_cmdicon
}

$iconitems = Get-Variable var_img_exp_* -ValueOnly
foreach ($item in $iconitems)
{
    $item.Source = $bmp_expicon
}

$iconitems = Get-Variable var_img_ps_* -ValueOnly
foreach ($item in $iconitems)
{
    $item.Source = $bmp_psicon
}

$iconitems = Get-Variable var_img_ovpn_* -ValueOnly
foreach ($item in $iconitems)
{
    $item.Source = $bmp_openvpnicon
}

$iconitems = Get-Variable var_img_ew_* -ValueOnly
foreach ($item in $iconitems)
{
    $item.Source = $bmp_ewicon
}



###################
## Other UI junk ##
###################

if($debug)
{
	Get-Variable var_*
}



function Show-Console
{
    # Thanks Stack Overflow. This is useful. Now I don't have to figure out how to make a splash screen
    $consolePtr = [Console.Window]::GetConsoleWindow()

    # Hide = 0,
    # ShowNormal = 1,
    # ShowMinimized = 2,
    # ShowMaximized = 3,
    # Maximize = 3,
    # ShowNormalNoActivate = 4,
    # Show = 5,
    # Minimize = 6,
    # ShowMinNoActivate = 7,
    # ShowNoActivate = 8,
    # Restore = 9,
    # ShowDefault = 10,
    # ForceMinimized = 11

    [Console.Window]::ShowWindow($consolePtr, 4)
}

function Hide-Console
{
    $consolePtr = [Console.Window]::GetConsoleWindow()
    #0 hide
    [Console.Window]::ShowWindow($consolePtr, 0)
}

function Start-LauncherMode
{
    if ($script:windowlaunchermode)
    {
        Write-Host "Setting window to Launcher Mode" -ForegroundColor Gray
        $var_menu_uimode.Header = "Current UI Mode: Launcher"
        $var_menu_launchermode.Header = "Switch Player Tools to Normal Mode"
        $var_canvas_mainwindow.Visibility = "Hidden"
        $var_canvas_launcher.Visibility = "Visible"
        $window.Height = "200"
        $window.Width = "580"
        $script:windowlaunchermode = $false
    }
    else 
    {
        Write-Host "Setting window to Player Tools Mode" -ForegroundColor Gray
        $var_menu_uimode.Header = "Current UI Mode: Player Tools"
        $var_menu_launchermode.Header = "Switch Player Tools to Launcher Mode"  
        $var_canvas_mainwindow.Visibility = "Visible"
        $var_canvas_launcher.Visibility = "Hidden"
        $window.Height = "500"
        $window.Width = "800"
        $script:windowlaunchermode = $true
    }
}

# Gonna separate the GUI stuff to the top and the rest to the bottom.

function Get-AllOverwatchBuilds
{
    param(
        [string[]]$paths
    )

    $script:arenaenv.ClearClientList()
    Write-Host "  Scanning for Overwatch builds"
    [bool]$battlenetclientfound = $false

    #Check encrypted game volumes
    if (!(Test-Path -Path "O:\"))
    {
        Write-Host "    Checking for to see if a Overwatch.vhdx exists..." -ForegroundColor Gray
        foreach ($item in $paths)
        {
            if (Test-Path -Path $item -ErrorAction Ignore)
            {
                $vhdxpath = (Join-Path -Path $item -ChildPath "Overwatch.vhdx")
                if (Test-Path -Path $vhdxpath -ErrorAction Ignore)
                {
                    Write-Host "      Found Overwatch.vhdx. Please enter credentials to mount it." -ForegroundColor Yellow
                    Set-CredentialWindowMode
                    Write-Host "        Presenting Auth UI. Waiting for user input."
                    $openvpnwindow.ShowDialog()

                    #$creds = Get-Credential -Message "Overwatch encrypted build mount for $vhdxpath" -UserName "Bitlocker Key Below"
                    if ($script:credwindowok)
                    {
                        Write-Host "        Credentials entered. Attempting to mount VHDX"
                        $passwdthing = $var_ovpn_auth_txtbxpasswd.Password | ConvertTo-SecureString -AsPlainText -Force
                        try
                        {
                            Write-Host "      Attempting to mount $vhdxpath" -ForegroundColor Yellow
                            Start-Process powershell.exe -ArgumentList "-NoProfile -file `"$pscommandpath`" -mountvhdx -vhdxpath `"$vhdxpath`" -vhdxpassword $($passwdthing | ConvertFrom-SecureString)" -Verb RunAs -WindowStyle Hidden -Wait
                            Write-Host "      Mounted $vhdxpath as O:\" -ForegroundColor Green
                        }
                        catch
                        {
                            Write-Host $_.Exception.Message -ForegroundColor Red
                        }
                    }
                    else{
                        Write-Host "      No credentials were received. Skipping..." -ForegroundColor Yellow
                    }
                    $script:credwindowok = $false
                    break
                }
            }
        }
    }

    #Check for actual games
    foreach ($item in $paths)
    {
        if (Test-Path -Path $item -ErrorAction Ignore)
        {
            Write-Host "    Scanning $item for Overwatch builds" -ForegroundColor Gray
            $overwatches = Get-ChildItem -Path $item -Recurse -Filter "Overwatch.exe"
            if ($overwatches)
            {
                foreach ($overwatch in $overwatches)
                {
                    Write-Host "      Found a build in $($overwatch.FullName)" -ForegroundColor Green
                    $clientinfo = New-Object OverwatchClient
                    switch -regex ($overwatch.FullName) 
                    {
                        "_esports2_"
                        {
                            Write-Host "        This build is a Battle.net build. Converting to a Battle.net scan to get product information..." -ForegroundColor Green
                            $battlenetclientfound = $true
                            $thing = Get-OverwatchBattlenetPath
                            if ($overwatch.FullName -like ($thing.path + "*"))
                            {
                                Write-Host "          This build is linked to Battle.net and is valid." -ForegroundColor Green
                                $clientinfo.build = ($thing.version).Substring($thing.version.LastIndexOf(".") + 1)
                                $clientinfo.FullPath = Join-Path -Path ($thing.path) -ChildPath "Overwatch.exe"
                                $clientinfo.scansource = "battlenet"
                                $clientinfo.FriendlyName = "Overwatch esports2 from Battle.net"
                                $clientinfo.bnetaudiolocale = $thing.audiolocale
                                $clientinfo.bnetlocale = $thing.locale
                                #$clients += $clientinfo
                                $script:arenaenv.AddClient($clientinfo)
                            }
                            else 
                            {
                                Write-Host "          This build is not linked to Battle.net Please check this build. Skipping as it may be out of date..." -ForegroundColor Red
                            }
                            break
                        }
                        "_retail_"
                        {
                            Write-Host "        This build is a Battle.net retail build. Skipping this one." -ForegroundColor Yellow
                            break
                        }
                        default
                        {
                            if ($overwatch.FullName -match "\d{6}|\d{5}")
                            {
                                $clientinfo.build = $Matches[0]
                                $clientinfo.FullPath = $overwatch.FullName
                                $clientinfo.scansource = $item
                                $clientinfo.FriendlyName = "$($clientinfo.build) from $item"
                                #$clients += $clientinfo
                                $script:arenaenv.AddClient($clientinfo)
                            }
                            else 
                            {
                                Write-Host "        Unknown build of Overwatch found. Ignoring this build as it is probably an internal or Professional Realm build." -ForegroundColor Yellow   
                            }
                            
                            break
                        }
                    }                
                }
            }
            else 
            {
                Write-Host "      No builds found." -ForegroundColor DarkGray
            }
        }
        else 
        {
            Write-Host "    Path $item not found. Skipping." -ForegroundColor DarkGray
        }
    }

    if ($battlenetclientfound -eq $false)
    {
        Write-Host "          Scanning for Battle.net installations." -ForegroundColor Yellow
        $thing = Get-OverwatchBattlenetPath
        if ($thing)
        {
            $clientinfo = New-Object OverwatchClient
            $clientinfo.build = ($thing.version).Substring($thing.version.LastIndexOf(".") + 1)
            $clientinfo.FullPath = Join-Path -Path ($thing.path) -ChildPath "Overwatch.exe"
            $clientinfo.scansource = "battlenet"
            $clientinfo.FriendlyName = "Overwatch esports2 from Battle.net"
            $clientinfo.bnetaudiolocale = $thing.audiolocale
            $clientinfo.bnetlocale = $thing.locale
            $script:arenaenv.AddClient($clientinfo)
        }
    }
    #we're now shoving this in arenaenvironment
    #return $script:arenaenv.gamebuilds
}

function Get-PlayerToolsPreferredGameClient
{
    param(
        $gameclients,
        $preferredgamesource
    )
    $gameclientcandidates = @()
    if ($gameclients.Count -eq 0)
    {
        throw "No game clients were found on this computer."
    }
    if ($preferredgamesource)
    {
        Write-Host "  Filtering through available game clients matching $preferredgamesource" -ForegroundColor Gray
        foreach ($gameclient in $gameclients)
        {
            if ($gameclient.scansource -eq $preferredgamesource)
            {
                Write-Host "    Match candidate: $($gameclient.FullPath) build $($gameclient.build)" -ForegroundColor White
                $gameclientcandidates += $gameclient
            }
        }
        $game = $gameclientcandidates | Sort-Object -Property build -Descending | Select-Object -First 1
        if ($game)
        {
            Write-Host "    Selecting: $($game.FullPath) build $($game.build)" -ForegroundColor Green
            return $game
        }
        else
        {
            $game = $gameclients | Sort-Object -Property build -Descending | Select-Object -First 1
            Write-Host "    No clients matching $preferredgamesource. Selecting from entire game scan instead: $($game.FullPath) build $($game.build)" -ForegroundColor Yellow
            return $game
        }
    }
    else 
    {
        $game = $gameclients | Sort-Object -Property build -Descending | Select-Object -First 1
        Write-Host "    Selecting from entire game scan: $($game.FullPath) build $($game.build)" -ForegroundColor Green
        return $game
    }
}

function Get-ChocolateyExe
{
    $manypaths = ($env:Path).split(";")
    foreach ($path in $manypaths)
    {
        if (Test-Path -Path $path)
        {
            if (Get-ChildItem -Path $path -Filter "choco.exe")
            {
                Write-Host "  Found Chocolatey installation at $path" -ForegroundColor green 
                return $true
            }
        }
        else
        {
            Write-Host "  Operational Note: Environmental Variable path has an invalid path. It doesn't exist - $path" -ForegroundColor DarkGray 
        }
    }
    Write-Host "  Unable to find a Chocolatey installation on this computer. Part of this tool is now disabled" -ForegroundColor green
    return $false
}

function New-FolderStructure
{
    param(
        $path
    )
    If (!(Test-Path $path))
    {
        New-FolderStructure (Split-Path $path)
        mkdir $path > $null
    }
}

function Get-AvailableUpdates 
{
    class ChocoPackage {
        [string]$packagename
        [string]$version
    }

    class ChocoDGV {
        [string]$packagename
        [string]$version
        [string]$updatedversion
    }

    [int]$updatesavailable = 0
    $packages = @()
    $packagesoutdated = @()
    Write-Host "  Checking Chocolatey access"
    $access = choco search "blz-battlenet"
    foreach ($line in $access)
    {
        if ($line -match "Invalid credentials specified.")
        {
            Write-Host "  Invalid credentials specified. Password for chocolatey repo is incorrect." -ForegroundColor Red
            throw "Incorrect password specified for Chocolatey"
        }
    }
    Write-Host "  Checking Chocolatey for updates. This may take a minute..."
    $chocooutdated = choco outdated
    Write-Host "  Chocolatey check done. Processing list"
    foreach ($line in $chocooutdated)
    {
        if ($line -match "\|false$")
        {
            $thing = $line.split("|")
            $updatedpackage = New-Object ChocoPackage
            $updatedpackage.packagename = $thing[0]
            $updatedpackage.version = $thing[2]
            $packagesoutdated += $updatedpackage
        }
        if ($line -match "Chocolatey has determined (\d+) package")
        {
            $updatesavailable = $matches[1]
        }
    } 
    #$chocopackagelist = choco upgrade all --except owl-vpn-profile --noop
    $chocopackagelist = choco list --local-only
    foreach ($line in $chocopackagelist)
    {
        if ($line -match "^(\S+)\s(\d.*)")
        {
            $package = New-Object ChocoDGV
            $package.packagename = $matches[1]
            $package.version = $matches[2]
            foreach ($software in $packagesoutdated)
            {
                if ($software.packagename -eq $matches[1])
                {
                    $package.updatedversion = $software.version
                }
            }
            $packages += $package
        }
    }
    
    $var_dg_software.Items.Clear();
    foreach ($item in $packages)
    {
        $var_dg_software.AddChild($item)
    }
    $var_dg_software.Items.Refresh();

    switch ($updatesavailable)
    {
        0 {
            $var_lblStatus.Text="There are no updates available at this time."
        }
        1 {
            $var_lblStatus.Text="There is $($updatesavailable.ToString()) update available. Please click the Update button to install it."
        }
        default {
            $var_lblStatus.Text="There are $($updatesavailable.ToString()) updates available. Please click the Update button to install them."
        }
    }
    return $updatesavailable
}

function Get-SystemInfo 
{
    param(
        $gamebuild = $script:currentgame
    )

    $text = New-Object Collections.Generic.List[String]
    if ($gamebuild.FullPath)
    {
        $text.Add("Overwatch Build: " + $gamebuild.build)
        $text.Add("  " + (Split-Path -path $gamebuild.FullPath) + [Environment]::NewLine)
    }
    else
    {
        $text.Add("Overwatch Build: not installed or found" + [System.Environment]::NewLine)
    }
    $os = Get-CimInstance Win32_OperatingSystem -Property BuildNumber, Caption, OSArchitecture
    if ($os)
    {
        $text.Add("$($os.Caption) $($os.OSArchitecture)")
        $text.Add("  Build $($os.BuildNumber)")
        #I don't know why Get-WmiObject is returning LastBootUpTime as a string and Get-CimInstance is returning it as a datetime but I need datettime...
        $uptime = (get-date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        $text.Add("  Uptime $($uptime.Days) days $($uptime.Hours.ToString("00")):$($uptime.Minutes.ToString("00")):$($uptime.Seconds.ToString("00"))")
    }   
    $processor = Get-CimInstance Win32_Processor -Property Name, NumberOfCores, NumberOfLogicalProcessors
    if ($processor)
    {
        $text.Add("$($processor.Name)")
        $text.Add("  Cores: $($processor.NumberofCores) | Threads: $($processor.NumberOfLogicalProcessors)")
    }
    $ram = (Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property capacity -Sum).sum /1gb
    if ($ram)
    {
        $text.Add("RAM: $($ram) GB")
    }
    $battery = Get-CimInstance Win32_Battery -Property Description, EstimatedChargeRemaining
    if ($battery)
    {
        $text.Add("Battery detected. $($battery.EstimatedChargeRemaining)% remaining")
        #$text.Add("  $($battery.Description) | $($battery.EstimatedChargeRemaining)% remaining")
    }
    $video = Get-CimInstance Win32_VideoController -Property Name, DriverVersion, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate
    foreach ($item in $video)
    {
        $text.Add("Video card: $($item.Name)")
        $text.Add("  Driver: $($item.DriverVersion)")
        $text.Add("  Resolution: $($item.CurrentHorizontalResolution)x$($item.CurrentVerticalResolution) $($item.CurrentRefreshRate) Hz")
    }
    $disk = Get-CimInstance -Class Win32_logicaldisk -Property DeviceID, FileSystem, FreeSpace, Size | Where-Object {$_.DeviceID -eq "C:"}
    if ($disk)
    {
        $text.Add("Hard drive: $($disk.DeviceID) | $($disk.FileSystem)")
        $diskstringbecausereasons = "  {0:n2} GB Free / {1:n2} GB Total" -f ($disk.FreeSpace / 1gb), ($disk.Size / 1gb)
        $text.Add($diskstringbecausereasons)
    }
    $text.Add("Chocolatey Repositories installed:")
    $chocorepos = choco source list
    foreach ($line in $chocorepos)
    {
        if ($line -match "https:\/\/(.*?)[\/\s]")
        {
            $text.Add("  " + $matches[1])
        }
    }
    return ($text -join "`r`n")
}

function Get-TelegrafMonitoringService
{
    param(
        $sysinfo
    )
    $telegraf = Get-Service telegraf -ErrorAction Ignore
    $nxlog = Get-Service nxlog -ErrorAction Ignore
    $libre = Get-Service LibreHardwareMonitor -ErrorAction Ignore
    $string = @()
    $string += $sysinfo
    $string += "Monitoring Service:"
    if ($libre)
    {
        $string += "  {0} - {1}" -f  $libre.Name, $libre.Status
    }
    else 
    {
        $string += "  - LibreHardwareMonitor not installed"    
    }
    if ($telegraf)
    {
        $string += "  {0} - {1}" -f  $telegraf.Name, $telegraf.Status
    }
    else 
    {
        $string += "  - Telegraf not installed"   
    }
    if ($nxlog)
    {
        $string += "  {0} - {1}" -f  $nxlog.Name, $nxlog.Status
    }
    else 
    {
        $string += "  - NXLog not installed"  
    }
    return ($string -join "`r`n")
}

function Install-ChocoUpdates
{
    $var_lblStatus.Text="Checking for updated software..."
    $thing = Start-Process choco.exe -ArgumentList "upgrade all" -verb RunAs -Wait -PassThru 
    Get-AvailableUpdates
    $var_lbl_sysinfo.Text = Get-TelegrafMonitoringService -sysinfo (Get-SystemInfo)
    if ($thing.ExitCode -eq 0)
    {
        $var_lblStatus.Text="Chocolatey Update command completed successfully. Please check the logs for any details"
    }
    else 
    {
        $var_lblStatus.Text="Attempted to update Chocolatey software but ran into issues. Please check the logs for any details"    
    }
}

function Get-OverwatchBattlenetPath
{
    class OverwatchInfo
    {
        [string]$path
        [string]$version
        [string]$audiolocale
        [string]$locale
    }
    $overwatchinfo = New-Object OverwatchInfo
    $bnetdbfile = "C:\ProgramData\Battle.net\Agent\product.db"
    if(Test-Path $bnetdbfile)
    {
        #I have no clue. I'mma brute force this db file since I don't know how this thing does it.
        $bnetdb = Get-Content $bnetdbfile -Encoding utf8
        $linecounter = 0
        $linefound = $false
        foreach ($line in $bnetdb)
        {
            $linecounter ++
            if ($line -like "*prometheus_tournament5*")
            {
                $linefound = $true
                break;
            }
        }
        if ($linefound)
        {
            #the f is this thing...
            #$thefuck = $bnetdb[$linecounter].Substring(1, $bnetdb[$linecounter].Length - 1)
            #$pathofinterest = $thefuck.Substring(0, $thefuck.LastIndexOf("/"))
            $pathofinterest = $bnetdb[$linecounter].Substring(1,$bnetdb[$linecounter].LastIndexOf("/") - 1)
            $overwatchinfo.path = "$pathofinterest/Overwatch/_esports2_".Replace("/","\")

            #extracting version. it used to be the line after the path on a clean install. adding languages adds a ton of lines... WTF
            for ($i = ($linecounter + 2); $i -lt $bnetdb.Length - 1; $i++)
            {
                #i'mma just brute force it to find the first version it finds after the Overwatch path. should be the first version string before another product comes by...
                if ($bnetdb[$i] -match "(\d{1}\.\d{2}\.\d{1}\.\d{1}\.\d{5,6})")
                {
                    $overwatchinfo.version = $matches[1]
                    break
                }
            }

            #now we try to extract the locale. same line as the path but is a pain
            if ($bnetdb[$linecounter] -match "\(.*?(\w{4}):.(\w{4})")
            {
                $overwatchinfo.locale = $matches[1]
                $overwatchinfo.audiolocale = $matches[2]
            }

            return $overwatchinfo
        }
        else 
        {
            return $null
        }
    }
    else 
    {
        return $null
    }
}

function Set-UpdatedLobbyJson
{
    param(
        $path
    )
    if (Test-Path -Path $path)
    {
        $path = $path.Replace("Overwatch.exe","")
        $showmodejsonpath = Join-Path -Path $path -ChildPath "showmodeLobbyLocations.json"
        try 
        {   
            try{
                Write-Host "  -> Attempting to write $showmodejsonpath" -ForegroundColor Yellow
                Update-JsonFile -jsonpath $showmodejsonpath -jsonuri $realmlist
            }
            catch{
                Write-Host "      Running elevated script to write to game path in case it is in a UAC protected path" -ForegroundColor Yellow
                Start-Process powershell.exe -ArgumentList "-NoProfile -file `"$pscommandpath`" -updatejson -jsongamepath `"$showmodejsonpath`" -jsonsourcepath `"$realmlist`"" -Verb RunAs -WindowStyle Hidden -Wait
                if (Test-Path -Path $showmodejsonpath)
                {
                    Write-Host "      File $showmodejsonpath was written successfully." -ForegroundColor Green
                }
                else
                {
                    throw $_
                }
            }
            $var_btn_updatelobbyjson.IsEnabled = $false
            $var_btn_updatelobbyjson.Content = "Updated Lobby Data"
            Write-Host "  -> Update complete" -ForegroundColor Green
        }
        catch 
        {
            [System.Windows.MessageBox]::Show($_.Exception.Message,'Unable to save lobby data','Ok','Error')
            Write-Host "  -> Unable to update showmodeLobbyLocations. $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else 
    {
        Write-Host "  -> Unable to update showmodeLobbyLocations - $path does not exist" -ForegroundColor Red
    }
}

function Get-UpdatedLobbyJson
{
    param(
        $path,
        [switch]$auto
    )
    if ($path)
    {
        if (Test-Path -Path $path -ErrorAction Ignore)
        {
            if ($auto)
            {
                Write-Host "Attempting to check lobby data for $path. Currently set to auto-update"
            }
            else 
            {
                Write-Host "Attempting to check lobby data for $path. Currently set to manual update"
            }
            $gamepath = Split-Path -Path $path
            if (Test-Path -Path $gamepath)
            {
                Write-Host "  Overwatch installation found at $gamepath" -ForegroundColor green
                try
                {
                    $onlinelobbyjson = Invoke-WebRequest -Uri $realmlist -UseBasicParsing
                    if ($onlinelobbyjson.StatusCode -eq 200)
                    {
                        $showmodejsonpath = Join-Path -Path $gamepath -ChildPath "showmodeLobbyLocations.json"
                        if (Test-Path -Path $showmodejsonpath)
                        {
                            #note - get-content drops each line in an array of object[] unless it is -raw. -raw makes it a string until you split it and then it becomes an array of strings OR an array of objects. Powershell gets to decide randomly. invoke-webrequest is a giant string. Splitting it makes a string[] array...wtf. yay... can I have an hour of my life back?
                            #$offlinelobbyjson = Get-Content (Join-Path -Path $gamepath -ChildPath "showmodeLobbyLocations.json")
                            $offlinelobbyjson = [System.IO.File]::ReadAllText($showmodejsonpath)
                            $diff = Compare-Object -ReferenceObject $offlinelobbyjson.Split([Environment]::NewLine) -DifferenceObject ($onlinelobbyjson.Content).Split([Environment]::NewLine)
                            if ($null -ne $diff)
                            {
                                #$diff is null if both the contents match. If any are different, we want to replace it with a source of truth
                                if ($auto)
                                {
                                    Write-Host "  Overwatch lobby list is different than the master list. Attempting to overwrite it." -ForegroundColor yellow
                                    Set-UpdatedLobbyJson -path $gamepath
                                }
                                else 
                                {
                                    Write-Host "  Overwatch lobby list is different than the master list. Use the Update Lobby button to update it." -ForegroundColor yellow
                                    $var_btn_updatelobbyjson.IsEnabled = $true    
                                }
                            }
                            else 
                            {
                                Write-Host "  Overwatch lobby list is current." -ForegroundColor green
                                $var_btn_updatelobbyjson.Content = "Lobby data is current"
                            }
                        }
                        else
                        {
                            if ($auto)
                            {
                                Write-Host "  Overwatch lobby list does not exist at $gamepath. Attempting to create a new one." -ForegroundColor yellow
                                Set-UpdatedLobbyJson -path $gamepath
                            }
                            else 
                            {
                                Write-Host "  Overwatch lobby list is different than the master list. Use the Lobby button to create one." -ForegroundColor yellow
                                $var_btn_updatelobbyjson.IsEnabled = $true
                                $var_btn_updatelobbyjson.Content = "Lobby file doesn't exist. Create file"    
                            }
                        }
                    }
                    else
                    {
                        Write-Host "  Unable to pull Lobby data from $realmlist." -ForegroundColor red
                        Write-Host "  $($onlinelobbyjson.StatusCode)" -ForegroundColor red
                        $var_btn_updatelobbyjson.Content = "Unable to retrieve Lobby data - AWS error $($onlinelobbyjson.StatusCode)"
                    }
                }
                catch
                {
                    Write-Host "  Unable to update Overwatch lobby json file" -ForegroundColor red
                    Write-Host "  $($_.Exception.Message)" -ForegroundColor red
                    [System.Windows.MessageBox]::Show($_.Exception.Message,'Unable to get lobby data','Ok','Error')
                }
            }
            else 
            {
                Write-Host "  Overwatch is not installed on this computer." -ForegroundColor red
                $var_btn_updatelobbyjson.Content ="Overwatch Tournament not installed"
                [System.Windows.MessageBox]::Show("Unable to find Overwatch Tournament install path at $gamepath. Please use the Battle.net app to install the Overwatch Esports game from the Overwatch dropdown menu and then relaunch the Player Tools. Unable to write lobby data",'Unable to find Overwatch Tournament client installation','Ok','Error')
            }
        }
        else 
        {
            Write-Host "No path was provided. Unable to update lobby json file." -ForegroundColor red
        }
    }
    else 
    {
        Write-Host "No path was provided. Unable to update lobby json file." -ForegroundColor red
    }
}

function Start-Overwatch{
    param(
        [OverwatchClient]$game,
        [switch]$admin
    )
    $window.TaskbarItemInfo.ProgressState = 4
    $temp = $var_btn_launcher_startgame.Content
    $var_btn_launcher_startgame.Content = "Overwatch is `r`nrunning..."
    $var_btn_launcher_startgame.IsEnabled = $false

    $localestuff = New-Object LocaleSettings
    $localestuff.Locale = $var_dropdown_launcher_Locale.SelectedValue
    $localestuff.AudioLocale = $var_dropdown_launcher_Audio.SelectedValue
    #write json file with audio and locale settings
    $localestuff | ConvertTo-Json | Out-File -FilePath $playerlocaleselectionjsonfile -Force

    #don't need this here atm...
    #Get-UpdatedLobbyJson -path $game.FullPath -auto

    $owparentpath = Split-Path ($game.FullPath)
    $startmsg = "Attempting to start Overwatch at $(Get-Date)"
    Write-Host $startmsg -ForegroundColor Green
    $var_lblStatus.Text = "Attempting to start Overwatch at $(Get-Date)"
    $launchme = $true
    if ($admin)
    {
        $owargs = "--tank_tournamentmodeadmin --tank_AllowRemoteDesktop --tank_disablestreaming 1 --tank_disabledevdata 1 --tank_locale " + $localestuff.Locale
        $owexe = $game.FullPath.Replace("Overwatch.exe", "OverwatchGM.exe")
        if (Test-Path -Path $owexe -ErrorAction Ignore)
        {
            #hackery - assuming OW.exe and OWGM.exe are built at the same time, they'll be the same version. Time to check...
            $ow_version = (Get-Item -Path $game.FullPath).VersionInfo.FileVersionRaw.ToString()
            $owgm_version = (Get-Item -Path $owexe).VersionInfo.FileVersionRaw.ToString()
            $issameversion = $false
            

            Write-Host "  Admin: Version check of Overwatch internal build number:   $ow_version" -ForegroundColor Yellow
            Write-Host "  Admin: Version check of OverwatchGM internal build number: $owgm_version" -ForegroundColor Yellow
            if ($ow_version -eq $owgm_version)
            {
                Write-Host "  Admin: Versions match." -ForegroundColor Green
                $issameversion = $true
            }
            else 
            {
                Write-Host "  Admin: Versions do not match." -ForegroundColor Red    
            }
            
            if ($issameversion -eq $false)
            {
                $mismatchprompt = [System.Windows.MessageBox]::Show("The version of OverwatchGM.exe ($owgm_version) is different than Overwatch.exe($ow_version) in $owparentpath. It is a mismatch and may cause a crash. Are you sure you want to run this OverwatchGM.exe file?`r`n`r`nIf you don't, hit no and replace OverwatchGM.exe`r`nYES -> Just run it    |    NO -> Don't start",'Version Mismatch','YesNo','Warning')
                if ($mismatchprompt -eq "Yes")
                {
                    Write-Host "  Warning: Running mismatched OverwatchGM.exe" -ForegroundColor Yellow
                }
                else 
                {
                    Write-Host "  Warning: User skipped running mismatched OverwatchGM.exe" -ForegroundColor Yellow
                    $launchme = $false
                }
            }
           
            if ($safemode -and $launchme)
            {
                $owexe = $game.FullPath.Replace("Overwatch.exe", "OWGMSafe.exe")
                try
                {
                    Rename-Safemode -path $owparentpath -admin
                }
                catch
                {
                    Write-Host "  Safe Mode - Running elevated script to copy OverwatchGM.exe in case it is in a UAC protected path" -ForegroundColor Yellow
                    Start-Process powershell.exe -ArgumentList "-NoProfile -file `"$pscommandpath`" -safemode -safemodepath `"$owparentpath`" -admin" -Verb RunAs -WindowStyle Hidden -Wait
                    if (Test-Path -Path $owexe -ErrorAction Ignore)
                    {
                        "  Safe Mode - OverwatchGM.exe copied to $owexe."
                    }
                    else 
                    {
                        $var_btn_launcher_startgame.Content = $temp
                        $var_btn_launcher_startgame.IsEnabled = $true
                        $launchme = $false
                        throw $_
                    }
                }
            }
        }
        else 
        {
            [System.Windows.MessageBox]::Show("$owexe cannot be found",'Missing OverwatchGM.exe','Ok','Error')
            Write-Host "  Launcher is in Admin mode - unable to find $owexe" -ForegroundColor Red
            $launchme = $false
        }
    }
    else
    {
        $owexe = $game.FullPath
        $owargs = "--tank_tournamentmode --tank_locale " + $localestuff.Locale + " --tank_audiolocale " + $localestuff.AudioLocale + " --tank_disablestreaming 1 --tank_disabledevdata 1";
        if ($safemode)
        {
            $owexe = $game.FullPath.Replace("Overwatch.exe", "OWSafe.exe")

            try
            {
                Rename-Safemode -path $owparentpath
            }
            catch
            {
                Write-Host "  Safe Mode - Running elevated script to copy Overwatch.exe in case it is in a UAC protected path" -ForegroundColor Yellow
                Start-Process powershell.exe -ArgumentList "-NoProfile -file `"$pscommandpath`" -safemode -safemodepath `"$owparentpath`"" -Verb RunAs -WindowStyle Hidden -Wait
                if (Test-Path -Path $owexe -ErrorAction Ignore)
                {
                    "  Safe Mode - Overwatch.exe copied to $owexe."
                }
                else 
                {
                    $var_btn_launcher_startgame.IsEnabled = $true
                    $launchme = $false
                    throw $_
                }
            }
        }
    }
    if ($launchme)
    {
        Write-Host "  Running: $owexe"
        Write-Host "  Arguments: $owargs"
        $processid = Start-Process -FilePath $owexe -ArgumentList $owargs -WorkingDirectory $owparentpath -PassThru -Wait
        Write-Host "  Process ID of the Overwatch task was: $($processid.Id)" 
        
        #was experimenting with Start-Job to see if we can get it more responsive but totally nope...
        #I guess if we really want a responsive UI, someone after me will have to deep dive into https://foxdeploy.com/2016/05/17/part-v-powershell-guis-responsive-apps-with-progress-bars/ and toss the UI onto another thread and get the synchash working. My last experiment failed so I didn't carry over to the playertools...
        #Start-Job -ScriptBlock {Start-Process -FilePath $args[0] -ArgumentList $args[1] -WorkingDirectory $args[2] -PassThru -Wait} -ArgumentList $owexe, $owargs, $owparentpath
        #do{
        #    Start-Sleep -Seconds 1 
        #    Write-Host "eez running" -ForegroundColor Green
        #}while(Get-Job -State Running)
        $stopmsg = "Overwatch was closed at $(Get-Date)"
        Write-Host $stopmsg -ForegroundColor Green
    }
    else
    {
        $stopmsg = "Overwatch was unable to start at $(Get-Date)"
        Write-Host $stopmsg -ForegroundColor Red
    }

    $var_lblStatus.Text = $stopmsg
    $var_btn_launcher_startgame.Content = $temp
    $var_btn_launcher_startgame.IsEnabled = $true
    $window.TaskbarItemInfo.ProgressState = 0
}

function Set-CredentialWindowMode{
    param(
        [switch]$ovpn,
        [switch]$choco
    )
    #PowerShell 7 does not have a Get-Credential prompt so it made me getting credentials useless since I hid the console window....
    #so now we have this thing. Making it convertible so that we can 
    $var_ovpn_auth_comboboxname.Items.Clear()
    $var_ovpn_auth_txtbxpasswd.Password = ""
    if ($ovpn)
    {
        $openvpnwindow.Title = "OpenVPN Profile Installer/Updater"
        $var_ovpn_auth_dock_vpn.Visibility = "Visible"
        $var_ovpn_auth_dock_user.Visibility = "Collapsed"
        $var_ovpn_lbl_username.Content = "VPN Endpoint"
        $var_ovpn_auth_comboboxname.IsEnabled = $true
        $var_ovpn_lbl_password.Visibility = "Collapsed"
        $var_ovpn_auth_txtbxpasswd.Visibility = "Collapsed"
    }elseif ($choco)
    {
        $openvpnwindow.Title = "Chocolatey Credentials"
        $var_ovpn_auth_dock_vpn.Visibility = "Collapsed"
        $var_ovpn_auth_dock_user.Visibility = "Visible"
        $var_ovpn_lbl_password.Visibility = "Visible"
        $var_ovpn_auth_txtbxpasswd.Visibility = "Visible"
        $var_ovpn_lbl_username.Content = "Chocolatey User"
    }
    else 
    {
        $var_ovpn_auth_comboboxname.Items.Add("Overwatch VHDX Bitlocker File")
        $var_ovpn_auth_comboboxname.SelectedValue = "Overwatch VHDX Bitlocker File"
        $var_ovpn_auth_dock_vpn.Visibility = "Visible"
        $var_ovpn_auth_dock_user.Visibility = "Collapsed"
        $var_ovpn_lbl_username.Content = "VHDX"
        $var_ovpn_auth_comboboxname.IsEnabled = $false
        $var_ovpn_lbl_password.Visibility = "Visible"
        $var_ovpn_auth_txtbxpasswd.Visibility = "Visible"
    }
}

################################
## Attaching stuff to OVPN UI ##
################################

#random notes:
#darn thing doesn't like to be open more than once since close() kills it
#powershell isn't like C# XAML classes where you can make new instances of the class... you can probably enclose the entire functionality of reading the auth window into a new class and go to town overloading it so you can make a new-object OpenVPNWindow but that is not this time

$openvpnwindow.Add_Closing({
    #these 2 lines kills the data return functionality... so now we just disable the menu and make the user re-open the tools if they wanna switch
    $_.Cancel = $true
    $openvpnwindow.Visibility = "Hidden"

    #$var_menu_openvpn_switch.IsEnabled = $false
    #$var_menu_openvpn_switch.Header = "OpenVPN Switch was closed. Please close and reopen Player Tools to use it again"
})

$var_ovpn_btn_ok.Add_Click({
    #$ovpncreds = New-Object OpenVPNCreds
    #$ovpncreds.realm = $var_ovpn_auth_comboboxname.SelectedValue.ToString()
    #$ovpncreds.chocoinstallpw = $var_ovpn_auth_txtbxpasswd.Password
    $script:credwindowok = $true
    $openvpnwindow.DialogResult = $true
    #return $ovpncreds
})

$var_ovpn_btn_Cancel.Add_Click({
    $openvpnwindow.Close()
})

$var_ovpn_auth_comboboxname.Add_SelectionChanged({
    <#
    if ($var_ovpn_auth_comboboxname.SelectedValue -eq "all")
    {
        if (Test-Path -Path (Join-Path -Path (Split-Path -Path $script:currentgame.FullPath) -ChildPath "OverwatchGM.exe"))
        {
            Write-Host "Unable to find $(Join-Path -Path (Split-Path -Path $script:currentgame.FullPath) -ChildPath "OverwatchGM.exe")" -ForegroundColor Red
            [System.Windows.MessageBox]::Show("Chocolatey log path ($chocologpath) cannot be found",'Open Chocolatey Log folder','OK','Error')
        }
    }
    else 
    {
        $var_ovpn_lbl_password.Visibility = "Collapsed"
        $var_ovpn_auth_txtbxpasswd.Visibility = "Collapsed"
    }
    #>
})

#Main UI function is here because I'm lazy and want to have minimal scrolling

$var_ovpn_auth_comboboxname.Add_SelectionChanged({
    if ($var_ovpn_auth_comboboxname.SelectedValue -match "^Legacy - ")
    {
        $var_ovpn_lbl_password.Visibility = "Visible"
        $var_ovpn_auth_txtbxpasswd.Visibility = "Visible"
    }
    else
    {
        $var_ovpn_lbl_password.Visibility = "Hidden"
        $var_ovpn_auth_txtbxpasswd.Visibility = "Hidden"
    }
})

$var_menu_openvpn_switch.Add_Click({
    <#
    $creds = Get-Credential -Message "Enter the realm name and the password"
    if ($creds)
    {
        Start-Process "choco.exe" -ArgumentList "upgrade owl-vpn-profile --params `"'/Site:$($creds.UserName) /Password:$($creds.GetNetworkCredential().password)'`" -force" -Verb RunAs -Wait
        Start-Process -FilePath "C:\Program Files\OpenVPN\bin\openvpn-gui.exe"
        $var_lblStatus.Text = "Attempting to install and switch OpenVPN profiles. When this is done, OpenVPN will have the option to connect"    
    }
    else 
    {
        $var_lblStatus.Text = "VPN profile switch cancelled - user closed or hit cancel on the credentials window."
    }
    #>
    Write-Host "  Building Auth UI" -ForegroundColor DarkGray
    Set-CredentialWindowMode -ovpn
    <# Remove this comment if you want to look for profiles that are not Legacy.
    foreach ($item in $script:arenaenv.OpenVPNProfiles)
    {
        $var_ovpn_auth_comboboxname.Items.Add($item)
    }
    #>
    foreach ($item in $script:arenaenv.LegacyOpenVPNProfiles)
    {
        $var_ovpn_auth_comboboxname.Items.Add("Legacy - $item")
    }
    $gmpath = (Join-Path -Path (Split-Path -Path $script:currentgame.FullPath) -ChildPath "OverwatchGM.exe")
    if ((Test-Path -Path $gmpath -ErrorAction Ignore) -and $adminmode)
    {
        Write-Host "    -> Admin mode is running and you have OverwatchGM, adding the all option to OpenVPN Switcher" -ForegroundColor Yellow
        $var_ovpn_auth_comboboxname.Items.Add("all")
    }
    else
    {
        if ($adminmode)
        {
            Write-Host "    -> Admin mode is running but you don't have $gmpath" -ForegroundColor Red
        }
    }

    $currentfiles = Get-ChildItem -Path "C:\Program Files\OpenVPN\config" -Filter "*.ovpn"
    if ($currentfiles.Count -gt 1)
    {
        $var_ovpn_auth_comboboxname.SelectedValue = "all"
    }
    if ($currentfiles.Count -eq 1)
    {
        $var_ovpn_auth_comboboxname.SelectedValue = $currentfiles.BaseName.ToLower()
    }

    Write-Host "  Presenting Auth UI. Waiting for user input."
    $openvpnwindow.ShowDialog()

    if ($script:credwindowok)
    {
        if ($var_ovpn_auth_comboboxname.SelectedValue -match "^Legacy - " -and [string]::IsNullOrEmpty($var_ovpn_auth_txtbxpasswd.Password))
        {
            [System.Windows.MessageBox]::Show("Legacy realms require a password",'OpenVPN Credentials','OK','Error')
            return
        }
        $ovpncreds = New-Object OpenVPNCreds
        $ovpncreds.realm = $var_ovpn_auth_comboboxname.SelectedValue.ToString()
        $ovpncreds.chocoinstallpw = $var_ovpn_auth_txtbxpasswd.Password

        Write-Host "  Credentials entered for $($ovpncreds.realm). Running Chocolatey to set it..." -ForegroundColor Green
        try{
            Start-Process "choco.exe" -ArgumentList "upgrade owl-vpn-profile --params `"'/Site:$($ovpncreds.realm) /Password:$($ovpncreds.chocoinstallpw)'`" -force" -Verb RunAs -Wait
            $var_lblStatus.Text = "Installed the $($ovpncreds.realm) profile. Use OpenVPN itself to connect." 
        }
        catch {
            $var_lblStatus.Text = "Unable to install the OpenVPN realm $($ovpncreds.realm)" 
            Write-Host "Unable to install OpenVPN realm $($ovpncreds.realm)" -ForegroundColor Red
            Write-Host $_ -ForegroundColor Red
            $script:credwindowok = $false
        }
        
        Start-Process -FilePath "C:\Program Files\OpenVPN\bin\openvpn-gui.exe"
        
    }
    else
    {
        Write-Host "  No credentials supplied. Closing credential window." -ForegroundColor Yellow
    }
    $script:credwindowok = $false
})

################################
## Attaching stuff to main UI ##
################################

$window.Add_Closing({
    Write-Host "Closing PowerShell window" -ForegroundColor Yellow
})

$var_btn_refresh.Add_Click({
    Get-AvailableUpdates
})

$var_menu_exit.Add_Click({
    $window.Close()
})

$var_menu_launchermode.Add_Click({
    Start-LauncherMode
})

$var_menu_reinstalleverythihng.Add_Click({
    $msgbxinput = [System.Windows.MessageBox]::Show("This command will reinstall all software. It is extremely destructive as it will overwrite most of the things in C:\OWL. You'll probably also need to get IT Support to reset some variables. Are you sure you want to do this?",'Reinstall all the things','YesNo','Warning')
    switch ($msgbxinput){
        'Yes' {
            Start-Process choco.exe -ArgumentList "upgrade owl-nxlog-player owl-teamspeak-player owl-beyondtrustsupport owl-integritychecktools openvpn blz-battlenetclient --force" -Verb RunAs
        }
        default {
            #nothin here...
        }
    }
})

$var_menu_openchocologpath.Add_Click({
    $chocologpath = "C:\ProgramData\chocolatey\logs"
    if (Test-Path -Path $chocologpath)
    {
        Invoke-Item -Path $chocologpath
    }
    else
    {
        [System.Windows.MessageBox]::Show("Chocolatey log path ($chocologpath) cannot be found",'Open Chocolatey Log folder','OK','Error')
    }
})

function Get-OpenVPNLogsFolder
{
    $openvpnlogpath = Join-Path -Path $env:USERPROFILE -ChildPath "OpenVPN\log"
    if (Test-Path -Path $openvpnlogpath)
    {
        Invoke-Item -Path $openvpnlogpath
    }
    else
    {
        [System.Windows.MessageBox]::Show("OpenVPN log path ($openvpnlogpath) cannot be found",'Open OpenVPN Log folder','OK','Error')
    }
}

$var_menu_openvpn_openlogs.Add_Click({
    Get-OpenVPNLogsFolder
})

$var_menu_openopenvpnlogpath.Add_Click({
    Get-OpenVPNLogsFolder
})

$var_menu_configmonitoring.Add_Click({
    $telegrafconfigscript = "C:\$game\tools\telegraf\Set-EnvironmentalVariables.ps1"
    if (Test-Path -Path $telegrafconfigscript)
    {
        Start-Process powershell.exe -ArgumentList "-File `"$telegrafconfigscript`" -NoProfile" -WindowStyle Hidden
    }
})

$var_menu_stopmonitoring.Add_Click({
    $scriptblock = {
        Get-Service telegraf | Stop-Service -Force -Verbose
        Get-Service nxlog | Stop-Service -Force -Verbose
        Get-Service librehardwaremonitor | Stop-Service -Force -Verbose
    }
    try
    {
        Start-Process powershell.exe -ArgumentList "-NoProfile -command $scriptblock" -Verb RunAs -Wait -WindowStyle Hidden
        $var_lbl_sysinfo.Text = Get-TelegrafMonitoringService -sysinfo (Get-SystemInfo)
        $var_lblStatus.Text="Stopped Telegraf, NXLog, and LibreHardwareMonitor. Note that the programs will run again on the next reboot."   
    }
    catch
    {
        $var_lblStatus.Text="Unable to stop Telegraf, NXLog, and LibreHardwareMonitor."   
    }
})

$var_menu_startmonitoring.Add_Click({
    #libre is a dependency of telegraf so starting/restarting telegraf will also start up libre
    $scriptblock = {
        Restart-Service telegraf -Verbose
        Restart-Service nxlog -Verbose
    }
    try
    {
        Start-Process powershell.exe -ArgumentList "-NoProfile -command $scriptblock" -Verb RunAs -Wait -WindowStyle Hidden
        $var_lbl_sysinfo.Text = Get-TelegrafMonitoringService -sysinfo $sysinfo
        $var_lblStatus.Text="Started Telegraf, NXLog, and LibreHardwareMonitor."   
    }
    catch
    {
        $var_lblStatus.Text="Unable to start Telegraf, NXLog, and LibreHardwareMonitor."   
    }

})

$var_menu_openvpn_opengui.Add_Click({
    Start-Process -FilePath "C:\Program Files\OpenVPN\bin\openvpn-gui.exe"
    $var_lblStatus.Text = "Attempting to open OpenVPN. It may appear as an icon on the system tray."
})



$var_menu_openvpn_addtap.Add_Click({
    try
    {
        Start-Process "C:\Program Files\OpenVPN\bin\tapctl.exe" -ArgumentList  "create --hwid root\tap0901" -WorkingDirectory "C:\Program Files\OpenVPN\bin" -verb RunAs
        $var_lblStatus.Text = "Running the OpenVPN batch file to add a TAP adapter."
    }
    catch
    {
        $var_lblStatus.Text = "User cancelled TAP adapter installation or tapctl does not have permissions."
    }
    
})

$var_menu_openvpn_removetap.Add_Click({
    Start-Process devmgmt.msc
    #Start-Process "C:\Program Files\TAP-Windows\bin\deltapall.bat" -WorkingDirectory "C:\Program Files\TAP-Windows\bin"
    #$var_lblStatus.Text = "Running the OpenVPN batch file to remove all TAP adapters. You'll need to reinstall at least 1 TAP adapters to connect"
})

$var_menu_chocoupdateall.Add_Click({
    Install-ChocoUpdates
})

$var_btn_updatechoco.Add_Click({
    Install-ChocoUpdates
})

$var_btn_updatelobbyjson.Add_Click({
    Set-UpdatedLobbyJson -path $script:currentgame.FullPath
})

$var_menu_debug.Add_Click({
    Show-Console
    $var_lblStatus.Text = "Debug mode turned on. Showing console."
})

$var_dropdown_launcher_BuildSelector.Add_SelectionChanged({
    $game = $script:arenaenv.GetClientByFriendlyName($var_dropdown_launcher_BuildSelector.SelectedValue)
    $var_lbl_launcher_build.Content = "Build: " +  $game.build
    $var_lblStatus.Text = "Selected game: " + $game.FullPath
    if ($game.scansource -eq 'battlenet')
    {
        $var_dropdown_launcher_Locale.SelectedValue = $game.bnetlocale
        $var_dropdown_launcher_Audio.SelectedValue = $game.bnetaudiolocale
        $var_dropdown_launcher_Locale.IsEnabled = $false
        $var_dropdown_launcher_Audio.IsEnabled = $false
    }
    else
    {
        $var_dropdown_launcher_Locale.IsEnabled = $true
        $var_dropdown_launcher_Audio.IsEnabled = $true
    }
})

$var_btn_launcher_startgame.Add_Click({
    $game = ($script:arenaenv.GetClientByFriendlyName($var_dropdown_launcher_BuildSelector.SelectedValue))
    Start-Overwatch -game $game
})

$var_btn_launcher_startadmingame.Add_Click({
    $game = ($script:arenaenv.GetClientByFriendlyName($var_dropdown_launcher_BuildSelector.SelectedValue))
    Start-Overwatch -game $game -admin
})

$var_btn_launcher_startnormalgame.Add_Click({
    $game = ($script:arenaenv.GetClientByFriendlyName($var_dropdown_launcher_BuildSelector.SelectedValue))
    Start-Overwatch -game $game
})

$var_menu_chocofixcreds.Add_Click({

    Set-CredentialWindowMode -choco
    Write-Host "  Chocolatey Auth - Presenting Auth UI. Waiting for user input."
    $openvpnwindow.ShowDialog()
    #$creds = Get-Credential -Message "Overwatch encrypted build mount for $vhdxpath" -UserName "Bitlocker Key Below"
    if ($script:credwindowok)
    {
        Write-Host "  Credentials entered. Attempting to register Chocolatey repo with new credentials"
        $chocouser = $var_ovpn_auth_txtbx_user.Text
        $chocoauth = $var_ovpn_auth_txtbxpasswd.Password
        $chococredargs = "source add -n=`"Blizzard IT Events Chocolatey`" -s=`"https://choco.itevents.blizzard.com/chocolatey`" -u=`"$chocouser`" -p=`"$chocoauth`""
        #Write-Host "  Attempting to write: $chococredargs" -ForegroundColor Yellow 
        Start-Process choco.exe -ArgumentList $chococredargs -Verb RunAs -WindowStyle Normal -Wait
        try{
            Get-AvailableUpdates
            $script:credwindowok = $false
            $var_grpbx_software.Header = "Chocolatey Software Installed"
            $var_menu_chocofixcreds.IsEnabled = $false
            $var_btn_updatechoco.IsEnabled = $true
            $var_btn_updatechoco.Content = "Update Software"
        }
        catch{
            $script:credwindowok = $false
            [System.Windows.MessageBox]::Show($_.Exception.Message,'Chocolatey Error','Ok','Error')
        }
    }
    else{
        Write-Host "  No credentials were received. Skipping..." -ForegroundColor Yellow
    }
})

#############################
## Starting up the main UI ##
#############################

Write-Host "Starting up the Player Tools."
Write-Host "  Player Tools is running from $($script:arenaenv.Launcher)" -ForegroundColor Gray
Write-Host "WARNING - The script will pause if this window is in select mode. Hit ESC if you clicked somewhere." -ForegroundColor Yellow
Write-Host "  This window is in select mode if the upper-left Window name says select, or if your cursor stops blinking." -ForegroundColor Yellow
#Shoving all the games in the arenaenv class
try{
    Get-AllOverwatchBuilds -paths $script:arenaenv.TournamentGamePaths
    $script:currentgame = Get-PlayerToolsPreferredGameClient -gameclients $script:arenaenv.gamebuilds -preferredgamesource $preferredgamesource
}
catch
{
    Write-Host "  $($_.Exception.message)" -ForegroundColor Red
    [System.Windows.MessageBox]::Show($_.Exception.Message,'Game client searcher','Ok','Error')
}
Write-Host "Game check complete."
# Building dropdown menu on Launcher and various stuff, and a mix of lobby json writing
Write-Host "Building Launcher UI."
foreach ($locale in $script:arenaenv.Locale)
{
    $var_dropdown_launcher_Locale.Items.Add($locale) | Out-Null
}
foreach ($audiolocale in $script:arenaenv.AudioLocale)
{
    $var_dropdown_launcher_Audio.Items.Add($audiolocale) | Out-Null
}
foreach ($client in $script:arenaenv.gamebuilds)
{
    $var_dropdown_launcher_BuildSelector.Items.Add($client.FriendlyName) | Out-Null
}

#we're gonna set this first. if Battle.net overrides, it'll be right below and change the dropdown again. 
if ($script:localesettings)
{
    $var_dropdown_launcher_Locale.SelectedValue = $script:localesettings.Locale
    $var_dropdown_launcher_Audio.SelectedValue = $script:localesettings.AudioLocale
}
else 
{
    #default to enUS
    $var_dropdown_launcher_Locale.SelectedValue = "enUS"
    $var_dropdown_launcher_Audio.SelectedValue = "enUS"
}

if ($script:currentgame)
{
    $var_dropdown_launcher_BuildSelector.SelectedValue = $script:currentgame.FriendlyName
    $var_lbl_launcher_build.Content = "Build: " +  $script:currentgame.build
    if ($adminmode)
    {
        Get-UpdatedLobbyJson -path $script:currentgame.FullPath
    }
    else
    {
        Get-UpdatedLobbyJson -auto -path $script:currentgame.FullPath
    }
    
    $var_lblStatus.Text = "Selected game: " + $script:currentgame.FullPath
    if ($script:currentgame.scansource -eq 'battlenet')
    {
        $var_dropdown_launcher_Locale.SelectedValue = $script:currentgame.bnetlocale
        $var_dropdown_launcher_Audio.SelectedValue = $script:currentgame.bnetaudiolocale
        $var_dropdown_launcher_Locale.IsEnabled = $false
        $var_dropdown_launcher_Audio.IsEnabled = $false
    }
}

if (Test-Path -Path $playernamefile -ErrorAction Ignore)
{
    $var_txtbx_launcher_playername.Text = (Get-Content $playernamefile -Raw).Trim()
}
if ($env:TELEGRAF_TEAMNAME)
{
    #don't have bginfo hooked up yet for scannings, but teamname.txt is the file and the dropdown is based off of bginfo's bgi files' basename
    $var_dropdown_launcher_Team.Items.Add($env:TELEGRAF_TEAMNAME) | Out-Null
    $var_dropdown_launcher_Team.SelectedValue = $env:TELEGRAF_TEAMNAME
}

if ($safemode)
{
    $var_btn_launcher_startgame.Content = "Start`r`nSafe Mode"
    $var_btn_launcher_startadmingame.Content = "Start Admin`r`nSafe Mode"
    $var_btn_launcher_startnormalgame.Content = "Start Normal Safe"
}
if ($adminmode)
{
    
    #$var_btn_launcher_startgame.Grid.RowSpan = 2
    $var_btn_launcher_startgame.Visibility = "Collapsed"
    $var_btn_launcher_startadmingame.Visibility = "Visible"
    $var_btn_launcher_startnormalgame.Visibility = "Visible"
    $var_menu_isadmin.Visibility = "Visible"
}

#Check to see if we're in launcher mode with the menus set to Launcher only. We don't need Player Tools functionality if this is on
if ($launchernoplayertoolsmenus)
{
    $var_menu_mainplayertools_chocoexpand.Visibility = "Collapsed"
    $var_menu_mainplayertools_troubleshootexpand.Visibility = "Collapsed"
    $var_menu_mainplayertools_telegrafexpand.Visibility = "Collapsed"
    $var_menu_mainplayertools_separatorone.Visibility = "Collapsed"
    $var_menu_mainplayertools_separatortwo.Visibility = "Collapsed"
    $var_menu_mainplayertools_separatorthree.Visibility = "Collapsed"
    $var_menu_mainplayertools_openvpn.Visibility = "Collapsed"
    $var_menu_reinstalleverythihng.Visibility = "Collapsed"
}
else 
{
    #Player Tools stuff
    #Get system info
    Write-Host "Getting system information summary."
    $var_lbl_sysinfo.Text = Get-TelegrafMonitoringService -sysinfo (Get-SystemInfo)
    #build UI according to environment
    $window.Title = $window.Title + " -  [> Env: $($game) <]"
    if ($env:TELEGRAF_HOSTNAME)
    {
        $window.Title = $window.Title + "[> Hostname: $($env:TELEGRAF_HOSTNAME) <]"
    }
    else 
    {
        $window.Title = $window.Title + "[> Hostname: Not Defined <]"
    }
    if ($env:TELEGRAF_TEAMNAME)
    {
        $window.Title = $window.Title + "[> Team: $($env:TELEGRAF_TEAMNAME) <]"
    }
    else 
    {
        $window.Title = $window.Title + "[> Team: Not Defined <]"
    }

    Write-Host "Player Tools title set."
    if (!(Test-Path -Path "C:\$game\tools\telegraf\Set-EnvironmentalVariables.ps1"))
    {
        #can't run a script if it isn't there. for custom installs
        $var_menu_configmonitoring.IsEnabled = $false
    }

    if (!(Test-Path -Path "C:\Program Files\OpenVPN\bin\openvpn-gui.exe"))
    {
        $var_menu_mainplayertools_openvpn.IsEnabled = $false
        $var_menu_mainplayertools_openvpn.Header = "OpenVPN not installed"
    }

    #note - remove this when we figure out how openvpn 2.5 removes tap adapters
    #screw it. Device Manager time...
    #$var_menu_openvpn_removetap.IsEnabled = $false
    Write-Host "Player Tools UI configuration complete."

    if (!($skipchococheck))
    {
        if (Get-ChocolateyExe)
        {
            try
            {
                Get-AvailableUpdates
            }
            catch
            {
                $var_grpbx_software.Header = "Unable to list Chocolatey software - incorrect password"
                $var_menu_chocofixcreds.IsEnabled = $true
                $var_btn_updatechoco.IsEnabled = $false
                $var_btn_updatechoco.Content = "Chocolatey bad password"
                [System.Windows.MessageBox]::Show($_.Exception.Message,'Chocolatey Error','Ok','Error')
            }
        }
        else 
        {
            $var_btn_refresh.IsEnabled = $false
            $var_btn_updatechoco.IsEnabled = $false
            $var_btn_updatechoco.Content = "Chocolatey is not installed"
            $var_grpbx_software.Header = "Unable to list Chocolatey software - not installed"
        }
    }
}

if (!$debug)
{
    Hide-Console
}
#figure out if we should start in Player Tools mode or Launcher mode
Start-LauncherMode

Write-Host "Player Tools is now ready to be used"
$Null = $window.ShowDialog()