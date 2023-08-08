
#Below code make script run PowerShell as admin
$currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
$testadmin = $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if ($testadmin -eq $false) {
Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}" -elevated' -f ($myinvocation.MyCommand.Definition))
exit #$LASTEXITCODE
}

#dynamically get versions
try {
    $softwarelist = Invoke-WebRequest -Uri "https://owl-deploy.s3.amazonaws.com/owl_softwareversion.json" -UseBasicParsing
    $requiredsoftware = $softwarelist.Content | ConvertFrom-Json
    $software = @{}
    foreach ($item in $requiredsoftware)
    {
        $software.Add($item.packagename,$item.version)
    }
}
catch
{
    throw "Unable to get list of software. `r`n$_"
}

#set powershell to use english for that session
function Set-CultureWin([System.Globalization.CultureInfo] $culture) { [System.Threading.Thread]::CurrentThread.CurrentUICulture = $culture ; [System.Threading.Thread]::CurrentThread.CurrentCulture = $culture } ; Set-CultureWin en-US ; [system.threading.thread]::currentthread.currentculture


#region Pre Req for code GUI
[reflection.assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

#Variables - Can be change for any type of update that is needed. 

    #Ndivia Driver Version.
    $approvedNvidiaNew = $software.'nvidia'
    #OWL Tournament Building Version  -  Accelerated Build link need to be adjusted speartely. 
    $OWLBuild = $software.'OWLBuild' 
    #TeamSpeak Version
    $TSPlayerBaseVer = "owl-teamspeak-player-base.{0}" -f $software.'owl-teamspeak-player-base'
    $TSPlayerVer = "owl-teamspeak-player.{0}" -f $software.'owl-teamspeak-player'
    #CPU Version
    $LeagueCPU = $software.'LeagueCPU'
    #GPU Version
    $LeagueGPU = $software.'LeagueGPU'
        
# Hide PowerShell Console Code
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
$consolePtr = [Console.Window]::GetConsoleWindow()
[Console.Window]::ShowWindow($consolePtr, 0)     #using 1 will show Console windows and 0 to hide

# Class used for Battle.net Overwatch client build info
class OverwatchClient
{
    [string]$build
    [string]$FriendlyName
    [string]$FullPath
    [string]$scansource
    [string]$bnetaudiolocale
    [string]$bnetlocale
}

# Function used to pull battle.net information on Overwatch client. 
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
        $bnetdb = Get-Content $bnetdbfile
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
            return $overwatchinfo.version
        }
        else 
        {
            $overwatchinfo.version = "Build Not Found"
            return $overwatchinfo.version
        }
    }
    else 
    {
        $overwatchinfo.version = "Bnet Not Found"
        return $overwatchinfo.version
    }
}

# Function being used so that Refresh button and close and re-open GUI
Function NewBaseForm {
    $folderForm.Close()
    $folderForm.Dispose()
    MakeBaseForm
}

Function MakeBaseForm{

#BEGIN GUI SECTION ------------------------------------------------------------------------------------------------------------
#Grab name of script and trunkcate the last 4 strings 
#$Scriptname = @(Get-PSCallStack)[1].InvocationInfo.MyCommand.Name
#$Scriptname1 = $Scriptname -replace ".{4}$"

#Basic GUI layout form
$folderForm = New-Object System.Windows.Forms.Form
$folderForm.StartPosition = "manual"
$folderForm.Location = "0,0"
$folderform.ClientSize = '430, 410'
$folderform.FormBorderStyle = 'FixedDialog'
$folderform.MaximizeBox = $False
$folderform.MinimizeBox = $False
$folderform.Name = "OWL Integrity Check 23.0"
$folderform.Text = "OWL Integrity Check 23.0"
$folderform.AutoSize = $true
$folderform.BackColor = 'black'

#Check to see if Icon and Wallpaper exist
$WallpaperToCheck = "C:\OWL\tools\scripts\Overwatch.png"
if (Test-Path $WallpaperToCheck -PathType leaf)
{
    #GUI Icon and Background Image
    $objImage = [system.drawing.image]::FromFile("C:\OWL\tools\scripts\Overwatch.png")
    $folderform.BackgroundImage = $objImage
    $folderform.BackgroundImageLayout = 'Center'
}
else{
#do nothing
}
$IconToCheck = "C:\OWL\tools\scripts\Overwatch.ico"
if (Test-Path $IconToCheck -PathType leaf)
{
    #GUI Icon and Background Image
    $objIcon = New-Object system.drawing.icon ("C:\OWL\tools\scripts\Overwatch.ico")
    $folderform.Icon = $objIcon
}
else{
#do nothing
}

#IC Choco Upgrade Check
$upgrades = choco upgrade all --except owl-vpn-profile --whatif
if(($upgrades | Out-String) -match "Chocolatey can upgrade (\d+)/\d+ packages.")
{
    $thingstoupgrade = $Matches[1]
    if ($thingstoupgrade -gt 0)
    {
        $ChocoUpgrade = New-Object System.Windows.Forms.Button        
        $ChocoUpgrade.Location = '50,10'            #location of Text Box
        $ChocoUpgrade.Size = '190,25'               #Size of textbox
        $ChocoUpgrade.Name = "ChocoUpgradeButton"
        $ChocoUpgrade.Text = 'RUN UPDATE ALL'
        $ChocoUpgrade.BackColor = 'red'
        $ChocoUpgrade.ForeColor = 'HighlightText'
        $ChocoUpgrade.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
        $folderForm.controls.Add($ChocoUpgrade)     #Add the input texbox to GUI
        
        $ChocoUpgrade.Add_Click({
        Write-Host "Running Chocolatey Update....."
        Start-Process cmd -verb runas -ArgumentList '/k choco upgrade all --except "owl-vpn-profile" --force'
        Write-Host "Update Completed"
        })
    }
    else
    {
        #IC Choco Upgrade Check
        $ChocoUpgrade = New-Object System.Windows.Forms.Button
        $ChocoUpgrade.Location = '50,10'            #location of Text Box
        $ChocoUpgrade.Size = '190,25'               #Size of textbox
        $ChocoUpgrade.Text = 'No Upgrade found'
        $ChocoUpgrade.Name = "ChocoUpgradeButton"
        $ChocoUpgrade.BackColor = 'green'
        $ChocoUpgrade.ForeColor = 'HighlightText'
        $ChocoUpgrade.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
        $folderForm.controls.Add($ChocoUpgrade)     #Add the input texbox to GUI
    }
}

#PC Name
$PCName = New-Object System.Windows.Forms.TextBox
$PCName.Location = '280,10'            #location of Text Box
$PCName.Size = '140,25'                #Size of textbox
$PCName.ReadOnly = $true               #Set Texbox to read only
$PCName.Text = "$env:computername"     #Get PC name and put it into the text box
$PCName.ForeColor = 'HighlightText'
$PCName.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
$PCName.TextAlign = 'Center'
$folderForm.controls.Add($PCName)      #Add the input texbox to GUI

#Nvidia Text Box
$NvidiaTextBox0 = New-Object System.Windows.Forms.TextBox
$NvidiaTextBox0.Location = '20,50'            #location of Text Box
$NvidiaTextBox0.Size = '120,20'               #Size of textbox
$NvidiaTextBox0.Height = 30
$NvidiaTextBox0.ReadOnly = $true              #Set Texbox to read only
$NvidiaTextBox0.Text = 'Nvidia Version'
$NvidiaTextBox0.ForeColor = 'HighlightText'
$NvidiaTextBox0.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
$NvidiaTextBox0.TextAlign = 'Center'
$folderForm.controls.Add($NvidiaTextBox0)     #Add the input texbox to GUI

#NVidia Check Box
$NvidiaTextBox = New-Object System.Windows.Forms.TextBox
$NvidiaTextBox.Location = '150,50'           #location of Text Box
$NvidiaTextBox.Size = '120,20'               #Size of textbox to GUI
$NvidiaTextBox.ReadOnly = $true              #Set Texbox to read only
$folderForm.controls.Add($NvidiaTextBox)     #Add the input texbox

#Falcon Text Box
$FalconTextBox0 = New-Object System.Windows.Forms.TextBox
$FalconTextBox0.Location = '20,80'            #location of Text Box
$FalconTextBox0.Size = '120,20'               #Size of textbox
$FalconTextBox0.ReadOnly = $true              #Set Texbox to read only
$FalconTextBox0.Text = 'Falcon Check'
$FalconTextBox0.ForeColor = 'HighlightText'
$FalconTextBox0.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
$FalconTextBox0.TextAlign = 'Center'
$folderForm.controls.Add($FalconTextBox0)     #Add the input texbox to GUI

#Falcon Check Box
$FalconTextBox = New-Object System.Windows.Forms.TextBox
$FalconTextBox.Location = '150,80'           #location of Text Box
$FalconTextBox.Size = '120,20'               #Size of textbox to GUI
$FalconTextBox.ReadOnly = $true              #Set Texbox to read only
$folderForm.controls.Add($FalconTextBox)     #Add the input texbox

#Falcon Connection Text Box
$FalconConnectTextBox0 = New-Object System.Windows.Forms.TextBox
$FalconConnectTextBox0.Location = '20,110'            #location of Text Box
$FalconConnectTextBox0.Size = '120,20'               #Size of textbox
$FalconConnectTextBox0.ReadOnly = $true              #Set Texbox to read only
$FalconConnectTextBox0.Text = 'Falcon Connection'
$FalconConnectTextBox0.ForeColor = 'HighlightText'
$FalconConnectTextBox0.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
$FalconConnectTextBox0.TextAlign = 'Center'
$folderForm.controls.Add($FalconConnectTextBox0)     #Add the input texbox to GUI

#Falcon Connection Check Box
$FalconConnectTextBox = New-Object System.Windows.Forms.TextBox
$FalconConnectTextBox.Location = '150,110'           #location of Text Box
$FalconConnectTextBox.Size = '120,20'               #Size of textbox to GUI
$FalconConnectTextBox.ReadOnly = $true              #Set Texbox to read only
$folderForm.controls.Add($FalconConnectTextBox)     #Add the input texbox

#OWL Build Text Box
$OWLBuildTextBox0 = New-Object System.Windows.Forms.TextBox
$OWLBuildTextBox0.Location = '20,140'            #location of Text Box
$OWLBuildTextBox0.Size = '120,20'               #Size of textbox
$OWLBuildTextBox0.ReadOnly = $true              #Set Texbox to read only
$OWLBuildTextBox0.Text = 'OWL Build Check'
$OWLBuildTextBox0.ForeColor = 'HighlightText'
$OWLBuildTextBox0.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
$OWLBuildTextBox0.TextAlign = 'Center'
$folderForm.controls.Add($OWLBuildTextBox0)     #Add the input texbox to GUI

#OWL Build Check Box
$OWLBuildTextBox = New-Object System.Windows.Forms.TextBox
$OWLBuildTextBox.Location = '150,140'           #location of Text Box
$OWLBuildTextBox.Size = '120,20'               #Size of textbox to GUI
$OWLBuildTextBox.ReadOnly = $true              #Set Texbox to read only
$folderForm.controls.Add($OWLBuildTextBox)     #Add the input texbox

#TeamSpeak Base Text Box
$TeamSpeakTextBox0 = New-Object System.Windows.Forms.TextBox
$TeamSpeakTextBox0.Location = '20,170'            #location of Text Box
$TeamSpeakTextBox0.Size = '120,20'               #Size of textbox
$TeamSpeakTextBox0.ReadOnly = $true              #Set Texbox to read only
$TeamSpeakTextBox0.Text = 'TeamSpeak Base'
$TeamSpeakTextBox0.ForeColor = 'HighlightText'
$TeamSpeakTextBox0.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
$TeamSpeakTextBox0.TextAlign = 'Center'
$folderForm.controls.Add($TeamSpeakTextBox0)     #Add the input texbox to GUI

#TeamSpeak Base Check Box
$TeamSpeakTextBox = New-Object System.Windows.Forms.TextBox
$TeamSpeakTextBox.Location = '150,170'           #location of Text Box
$TeamSpeakTextBox.Size = '120,20'               #Size of textbox to GUI
$TeamSpeakTextBox.ReadOnly = $true              #Set Texbox to read only
$folderForm.controls.Add($TeamSpeakTextBox)     #Add the input texbox

#TeamSpeak Player Text Box
$TeamSpeakPTextBox0 = New-Object System.Windows.Forms.TextBox
$TeamSpeakPTextBox0.Location = '20,200'            #location of Text Box
$TeamSpeakPTextBox0.Size = '120,20'               #Size of textbox
$TeamSpeakPTextBox0.ReadOnly = $true              #Set Texbox to read only
$TeamSpeakPTextBox0.Text = 'TeamSpeak Player'
$TeamSpeakPTextBox0.ForeColor = 'HighlightText'
$TeamSpeakPTextBox0.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
$TeamSpeakPTextBox0.TextAlign = 'Center'
$folderForm.controls.Add($TeamSpeakPTextBox0)     #Add the input texbox to GUI

#TeamSpeak Player Check Box
$TeamSpeakPTextBox = New-Object System.Windows.Forms.TextBox
$TeamSpeakPTextBox.Location = '150,200'           #location of Text Box
$TeamSpeakPTextBox.Size = '120,20'               #Size of textbox to GUI
$TeamSpeakPTextBox.ReadOnly = $true              #Set Texbox to read only
$folderForm.controls.Add($TeamSpeakPTextBox)     #Add the input texbox

#PC Text Box
$PCTextBox0 = New-Object System.Windows.Forms.TextBox
$PCTextBox0.Location = '20,290'            #location of Text Box
$PCTextBox0.Size = '120,20'               #Size of textbox
$PCTextBox0.Height = 30
$PCTextBox0.ReadOnly = $true              #Set Texbox to read only
$PCTextBox0.Text = 'League PC'
$PCTextBox0.ForeColor = 'HighlightText'
$PCTextBox0.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
$PCTextBox0.TextAlign = 'Center'
$folderForm.controls.Add($PCTextBox0)     #Add the input texbox to GUI

#PC Check Box
$PCTextBox = New-Object System.Windows.Forms.TextBox
$PCTextBox.Location = '150,290'           #location of Text Box
$PCTextBox.Size = '120,20'               #Size of textbox to GUI
$PCTextBox.ReadOnly = $true              #Set Texbox to read only
$folderForm.controls.Add($PCTextBox)     #Add the input texbox

#Process Button
$ProcessButton = New-Object System.Windows.Forms.Button
$ProcessButton.Location = '50, 330'
$ProcessButton.Name = "ProcessButton"
$ProcessButton.Size = '190,25'
$ProcessButton.Text = "Open All Processes Checks"
$ProcessButton.Font = "Microsoft Sans Serif, 8.25pt"
$folderForm.Controls.Add($ProcessButton)
$ProcessButton.BackColor = 'orange'

    #Open All Application and Process for check when button clicked
    $ProcessButton.Add_Click({

    #Run in admin Powershell for choco install to work
    #Launch OWL Tournament Launcher, Device Manager, Task Manager, Registry
    #Start-Process devmgmt.msc #Opens up Device Manager
    Start-Process taskmgr     #Opens up Task Manager
    Start-Process appwiz.cpl  #Opens up Add/Remove Programs from ControlPanel
    $ProcessButton.BackColor = 'green'

    #Launch Registry and open it to the correct path to check software
        function jumpReg ($registryPath)
        {
            New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit" `
                            -Name "LastKey" `
                            -Value $registryPath `
                            -PropertyType String `
                            -Force
            regedit
        }
        #jumpReg ("Computer\HKEY_LOCAL_MACHINE\Software") | Out-Null
    })

#Refresh IC Button
$RefreshICButton = New-Object System.Windows.Forms.Button
$RefreshICButton.Location = '50, 370'
$RefreshICButton.Name = "Refresh IC"
$RefreshICButton.Size = '190,25'
$RefreshICButton.Text = "Refresh Integrity Check"
$RefreshICButton.Font = "Microsoft Sans Serif, 8.25pt"
$folderForm.Controls.Add($RefreshICButton)
$RefreshICButton.BackColor = 'White'
$RefreshICButton.Add_Click({NewBaseForm})

#OK Button
$OKbutton = New-Object System.Windows.Forms.Button
$OKbutton.Anchor = 'Bottom, Right'
$OKbutton.DialogResult = 'OK'
$OKbutton.Location = '320, 350'
$OKbutton.Name = "OKbutton"
$OKbutton.Size = '80, 33'
$OKbutton.TabIndex = 0
$OKbutton.Text = "IC DONE (EXIT)"
$OKbutton.BackColor = 'orange'
#$OKbutton.UseVisualStyleBackColor = $True
$folderForm.Controls.Add($OKbutton)
    
    #Clicking OK button will close form and process
    $OKbutton.Add_Click({       
        $ICDone = "C:\OWL\tools\scripts"
        if (Test-Path -Path $ICDone)
        {
        #IC Check Done Image
        Start-Process "https://owl-deploy.s3.amazonaws.com/OWLICDone.png" | Out-Null
        Get-Date | Out-File -FilePath "C:\OWL\tools\scripts\Done.txt"
        }
        else{
        #do nothing
        }

        $folderForm.Close()
        stop-process -Id $PID
        #Remove-Item -LiteralPath $MyInvocation.MyCommand.Source
    })

<#
#VPN and Game Client Button
$VPNTournamentButton = New-Object System.Windows.Forms.Button
$VPNTournamentButton.Location = '20, 263'
$VPNTournamentButton.Name = "VPN and Game Launcher"
$VPNTournamentButton.Size = '190,25'
$VPNTournamentButton.Text = "VPN"
$VPNTournamentButton.Font = "Microsoft Sans Serif, 8.25pt"
$folderForm.Controls.Add($VPNTournamentButton)
$VPNTournamentButton.BackColor = 'orange'
    #Check for input value before launching VPN, Client, and TeamSpeak
    $VPNTournamentButton.Add_Click({
        Start-Process 'c:\Program Files\OpenVPN\bin\openvpn-gui.exe' -ArgumentList "--command disconnect_all" -Wait
        #close out all VPN informaton first
        Stop-Process -Name "openvpn-gui" -Force        
        #Run VPN update process
        $vpnfilename = Get-ChildItem 'C:\Program Files\OpenVPN\config'
            & 'C:\Program Files\OpenVPN\bin\openvpn-gui.exe' --connect "$($vpnfilename)"
        $VPNTournamentButton.BackColor = 'green'
    })
#>

#BEGIN CHECKS SECTION ------------------------------------------------------------------------------------------------------------
#Looking for Nvidia driver version
$driver = Get-WmiObject win32_VideoController | Where-Object {$_.Name.contains("NVIDIA")}
if ($driver -is [system.array]){ # if we have 2+ gpus, we get an array
	$currentNvidia = $driver[0].DriverVersion 
}
else{ 
	$currentNvidia = $driver.DriverVersion 
}

# Now want last 5 digits of $driver_version in the form XXX.XX
# Regex: 6 matches of digit or . starting from the back
# Replace: remove existing .
# Insert: place . after 3rd character
$currentNvidia = ([regex]".{6}$").match($currentNvidia).value.Replace(".","").Insert(3,'.')

if ($currentNvidia -eq $approvedNvidiaNew) {
    $NvidiaTextBox.Text = $currentNvidia #Text box input with driver version
    $NvidiaTextBox.BackColor = 'green'
    $NvidiaTextBox.ForeColor = 'HighlightText'
    $NvidiaTextBox.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
    $NvidiaTextBox.TextAlign = 'Center'
}
else {
    ##Write-Host This PC has the wrong driver version: $currentNvidia
    $NvidiaTextBox.Text = $currentNvidia #Text box input with driver version
    $NvidiaTextBox.BackColor = 'red'
    $NvidiaTextBox.ForeColor = 'HighlightText'
    $NvidiaTextBox.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
    $NvidiaTextBox.TextAlign = 'Center'

    #Nvidia driver Button
    $DriverUpdateButton = New-Object 'System.Windows.Forms.Button'
    $DriverUpdateButton.Location = '300,50'
    $DriverUpdateButton.Size = '120,20'
    $DriverUpdateButton.Text = "Download Drivers"
    $DriverUpdateButton.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
    $DriverUpdateButton.BackColor = 'yellow'
    $folderForm.Controls.Add($DriverUpdateButton)   

    #Download drivers when button had been clicked
    $DriverUpdateButton.Add_Click({
    Start-Process "http://us.download.nvidia.com/Windows/$approvedNvidiaNew/$($approvedNvidiaNew)-desktop-win10-win11-64bit-international-dch-whql.exe"
    })
}


#Below check for falcon install.  If it is not instaslled it will ask for input to install it. 
if($null -eq (Get-Service "csagent" -ea SilentlyContinue)){   #If not installed run below
        #Falcon Text Box
        $FalconTextBox.Text = 'NOT INSTALLED'
        $FalconTextBox.BackColor = 'red'
        $FalconTextBox.ForeColor = 'HighlightText'
        $FalconTextBox.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
        $FalconTextBox.TextAlign = 'Center'

        #Falcon Install Button
        $FalconInstallButton = New-Object 'System.Windows.Forms.Button'
        $FalconInstallButton.Location = '300,80'
        $FalconInstallButton.Size = '120,20'
        $FalconInstallButton.Text = "Install Falcon"
        $FalconInstallButton.BackColor = 'yellow'
        $FalconInstallButton.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
        $folderForm.Controls.Add($FalconInstallButton)

        $FalconInstallButton.Add_Click({
            #create a additional popup for confirmation install of Falcon
            Add-Type -AssemblyName PresentationCore,PresentationFramework
            $ButtonType = [System.Windows.MessageBoxButton]::YesNo
            $MessageIcon = [System.Windows.MessageBoxImage]::Warning
            $MessageBody = "Are you sure you want to install Falcon?"
            $MessageTitle = "Confirm Installation"

            #Popup contdition for Falcon install
            $Result = [System.Windows.MessageBox]::Show($MessageBody,$MessageTitle,$ButtonType,$MessageIcon)
            if($Result -eq "No"){
                Write-Host "NO Falcon Install"
            }
            elseif($Result -eq "Yes"){
                Write-Host "Installing Falcon..."
                Start-Process cmd -verb runas -ArgumentList {/k choco install falconsensor}
                Write-Host "Falcon Install Completed"
            }
            else{
                #Ment for Cancel button
            }
        })

}
else {
        #Falcon Text Box
        $FalconTextBox.Text = 'Running'
        $FalconTextBox.BackColor = 'green'
        $FalconTextBox.ForeColor = 'HighlightText'
        $FalconTextBox.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
        $FalconTextBox.TextAlign = 'Center'
}

#Below check for falcon Connection.
$FalconConnection = Get-NetTCPConnection | Select-Object remote*,state,@{Name="Process";Expression={(Get-Process -Id $_.OwningProcess).id}} | Where-Object{$_.state -match "established" -and $_.process -eq 4 -and $_.RemotePort -eq 443} 
if($FalconConnection){
        #Falcon Text Box
        $FalconConnectTextBox.Text = 'Established'
        $FalconConnectTextBox.BackColor = 'green'
        $FalconConnectTextBox.ForeColor = 'HighlightText'
        $FalconConnectTextBox.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
        $FalconConnectTextBox.TextAlign = 'Center'
}
else {
        #Falcon Text Box
        $FalconConnectTextBox.Text = 'NO CONNECTION'
        $FalconConnectTextBox.BackColor = 'red'
        $FalconConnectTextBox.ForeColor = 'HighlightText'
        $FalconConnectTextBox.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
        $FalconConnectTextBox.TextAlign = 'Center'
}

#Get Esport version of client build from function and assign to value
$OWLEsportVersion = Get-OverwatchBattlenetPath

if($OWLEsportVersion -eq $OWLBuild){
        #OWL Build Tex Box
        $OWLBuildTextBox.Text = $OWLEsportVersion
        $OWLBuildTextBox.BackColor = 'green'
        $OWLBuildTextBox.ForeColor = 'HighlightText'
        $OWLBuildTextBox.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
        $OWLBuildTextBox.TextAlign = 'Center'
}
else {
        #OWL Build Text Box
        $OWLBuildTextBox.Text = $OWLEsportVersion
        $OWLBuildTextBox.BackColor = 'red'
        $OWLBuildTextBox.ForeColor = 'HighlightText'
        $OWLBuildTextBox.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
        $OWLBuildTextBox.TextAlign = 'Center'
}

#Check to see if teamspeak version folder exist. 
$TSPlayerBaseCheck = Test-Path "C:\ProgramData\chocolatey\.chocolatey\$TSPlayerBaseVer"
$TSPlayerCheck = Test-Path "C:\ProgramData\chocolatey\.chocolatey\$TSPlayerVer"

if ($TSPlayerBaseCheck -eq 'True'){
    #TeamSpeak Player Base Box
    $TeamSpeakTextBox.Text = $TSPlayerBaseVer |  ForEach-Object {$_.substring($_.length-10)}
    $TeamSpeakTextBox.BackColor = 'green'
    $TeamSpeakTextBox.ForeColor = 'HighlightText'
    $TeamSpeakTextBox.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
    $TeamSpeakTextBox.TextAlign = 'Center'
}
else{
    #TeamSpeak Base Text Box
    $TeamSpeakTextBox.Text = "NO MATCH"
    $TeamSpeakTextBox.BackColor = 'red'
    $TeamSpeakTextBox.ForeColor = 'HighlightText'
    $TeamSpeakTextBox.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
    $TeamSpeakTextBox.TextAlign = 'Center'

    #TeamSpeak Base install Button
    $TeamSpeakInstallButton = New-Object 'System.Windows.Forms.Button'
    $TeamSpeakInstallButton.Location = '300,170'
    $TeamSpeakInstallButton.Size = '120,20'
    $TeamSpeakInstallButton.Text = "Install TS Base"
    $TeamSpeakInstallButton.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
    $TeamSpeakInstallButton.BackColor = 'yellow'
    $folderForm.Controls.Add($TeamSpeakInstallButton)   

    #Run Chocolatey install for TeamSpeak Player Base
    $TeamSpeakInstallButton.Add_Click({
        Write-Host "Installing TeamSpeak Player Base....."
        Start-Process cmd -verb runas -ArgumentList {/k choco install owl-teamspeak-player-base --force}
        Write-Host "Done!" -ForegroundColor Green
    })
}

if ($TSPlayerCheck -eq 'True'){
        #TeamSpeak Player Box
        $TeamSpeakPTextBox.Text = $TSPlayerVer | ForEach-Object {$_.substring($_.length-10)}
        $TeamSpeakPTextBox.BackColor = 'green'
        $TeamSpeakPTextBox.ForeColor = 'HighlightText'
        $TeamSpeakPTextBox.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
        $TeamSpeakPTextBox.TextAlign = 'Center'
 }
 else{
        #TeamSpeak Player Text Box
        $TeamSpeakPTextBox.Text = "NO MATCH"
        $TeamSpeakPTextBox.BackColor = 'red'
        $TeamSpeakPTextBox.ForeColor = 'HighlightText'
        $TeamSpeakPTextBox.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
        $TeamSpeakPTextBox.TextAlign = 'Center'

        #TeamSpeak Player install Button
        $TeamSpeakPInstallButton = New-Object 'System.Windows.Forms.Button'
        $TeamSpeakPInstallButton.Location = '300,200'
        $TeamSpeakPInstallButton.Size = '120,20'
        $TeamSpeakPInstallButton.Text = "Install TS Player"
        $TeamSpeakPInstallButton.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
        $TeamSpeakPInstallButton.BackColor = 'yellow'
        $folderForm.Controls.Add($TeamSpeakPInstallButton)   

        #Run Chocolatey install for TeamSpeak Player
        $TeamSpeakPInstallButton.Add_Click({
            Write-Host "Installing TeamSpeak Player......"
            Start-Process cmd -verb runas -ArgumentList {/k choco install owl-teamspeak-player --force}
            Write-Host "Done!" -ForegroundColor Green
        })
 }

#Check PC Specs
$processor = Get-CimInstance Win32_Processor -Property Name, NumberOfCores, NumberOfLogicalProcessors
$video = Get-CimInstance Win32_VideoController -Property Name, DriverVersion, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate

if (($processor.Name -eq $LeagueCPU) -and ($video.Name -eq $LeagueGPU)){
        #PC Check Box
        $PCTextBox.Text = "MATCH"
        $PCTextBox.BackColor = 'green'
        $PCTextBox.ForeColor = 'HighlightText'
        $PCTextBox.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
        $PCTextBox.TextAlign = 'Center'
 }
 else{
        #PC Check Box
        $PCTextBox.Text = "NO MATCH"
        $PCTextBox.BackColor = 'red'
        $PCTextBox.ForeColor = 'HighlightText'
        $PCTextBox.Font = "Microsoft Sans Serif, 8.25pt, style=Bold"
        $PCTextBox.TextAlign = 'Center'
 }

#Closes the window 
$folderForm.ShowDialog()

    #If user click on the X button on from it will close process as well.
    if($folderForm.DialogResult -eq 'Cancel')
    {
		stop-process -Id $PID
	}	

}

MakeBaseForm

#pause