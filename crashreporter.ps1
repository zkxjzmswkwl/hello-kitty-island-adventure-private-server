param(
	[switch]$debug,
    [string]$game = "OWL"
)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore

$errorreportingfolder = "C:\$game\tools\errorreporting"
$loggoblin = Join-Path -Path $errorreportingfolder -ChildPath "LogGoblin.exe"
$playernamefile = (Join-Path -Path ([Environment]::GetFolderPath("MyDocuments")) -ChildPath "Blizzard\name.txt")
if (Test-Path -Path $playernamefile)
{
    $playername = (Get-Content $playernamefile -Raw).Trim()
}
else
{
    $playername = ""
}



#create window
#$xaml = Join-Path -Path $PSScriptRoot -ChildPath "telegraf.xaml"
#$inputXML = Get-Content $xaml -Raw
$inputXML = @"
<Window x:Name="crashreporterwindow" x:Class="Powershell_WPF_Templates.CrashReporter"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        xmlns:local="clr-namespace:Powershell_WPF_Templates"
        mc:Ignorable="d"
        Title="Crash Reporter" Height="520" Width="800" ResizeMode="CanMinimize">
    <DockPanel x:Name="mainwindowpanel" LastChildFill="false" AllowDrop="True">
        <StatusBar DockPanel.Dock="Bottom" Height="30" >
            <StatusBarItem>
                <TextBlock Name="lblStatus" Text="Error reporting tool"/>
            </StatusBarItem>
        </StatusBar>
        <Menu DockPanel.Dock="Top" Margin="0">
            <MenuItem Header="_File">
                <MenuItem Header="Manually run">
                    <MenuItem x:Name="menu_dxdiag" Header="_dxdiag" />
                    <MenuItem x:Name="menu_msinfo" Header="_msinfo" />
                </MenuItem>
                <Separator></Separator>
                <MenuItem x:Name="menu_exit" Header="_Exit" />
            </MenuItem>
            <MenuItem x:Name="menu_refresh"  Header="_Refresh"/>
        </Menu>
        <Canvas x:Name="canvas_main">
            <Grid Width="790" Height="467" Canvas.Top="5" Panel.ZIndex="1">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="auto" />
                    <ColumnDefinition Width="*" />
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="auto" />
                    <RowDefinition Height="auto" />
                    <RowDefinition Height="auto" />
                    <RowDefinition />
                </Grid.RowDefinitions>
                <StackPanel Grid.Row="0" Grid.ColumnSpan="2" VerticalAlignment="Top" HorizontalAlignment="Left" Orientation="Horizontal" Margin="4,0">
                    <TextBox x:Name="txtbx_errorpath" Width="720" HorizontalAlignment="Left" Margin="0,0,15,0" Text="Batman" IsEnabled="False" />
                    <Button x:Name="btn_openfolder" Content="Open" Margin="0,0,8,0" />
                </StackPanel>
                <GroupBox x:Name="grpbx_crashinfo" Header="Things to gather" Width="300" Height="408" VerticalAlignment="Top" Grid.Row="1" Grid.RowSpan="3" Margin="5,0" Grid.Column="0">
                    <StackPanel Orientation="Vertical">
                        <TextBlock x:Name="lbl_sysinfo" TextWrapping="WrapWithOverflow" Width="280" Text="Placeholder" HorizontalAlignment="Left" VerticalAlignment="Top" MaxHeight="170" Height="170"/>
                        <Label x:Name="lbl_notes" Content="Notes" />
                        <TextBox x:Name="txtbx_notes" Height="185" TextWrapping="Wrap" AcceptsTab="True" AcceptsReturn="True" VerticalScrollBarVisibility="Visible" Text="TextBox"/>
                    </StackPanel>
                </GroupBox>
                <GroupBox x:Name="grpbx_crashdata" Header="Crash Data" Width="470" Height="375" VerticalAlignment="Top" Grid.Row="1" Margin="5,0" Grid.Column="1">
                    <TreeView x:Name="treeview_folder" ></TreeView>
                </GroupBox>
                <StackPanel Grid.Row="2" Grid.ColumnSpan="2" VerticalAlignment="Bottom" HorizontalAlignment="Right" Orientation="Horizontal" Margin="12,0">
                    <Button x:Name="btn_reportcodbug" Content="Run Call of Duty Bug Reporter >" Margin="0,0,10,0" />
                    <Button x:Name="btn_loggoblin" Content="Run Battle.net LogGoblin >" Margin="0,0,10,0" />
                    <Button x:Name="btn_senderrors" Content="Submit Error Log" />
                </StackPanel>
            </Grid>
        </Canvas>
    </DockPanel>
</Window>
"@

$inputXML = $inputXML -replace 'mc:Ignorable="d"', '' -replace "x:N", 'N' -replace '^<Win.*', '<Window'
if ($debug)
{
	$inputXML = $inputXML -replace 'Visibility="Hidden"', ''
}
[XML]$XAML = $inputXML

#Read XAML
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
try {
    $window = [Windows.Markup.XamlReader]::Load( $reader )
} catch {
    Write-Warning $_.Exception
    throw
}
# Create variables based on form control names.
# Variable will be named as 'var_<control name>'

$xaml.SelectNodes("//*[@Name]") | ForEach-Object {
    #"trying item $($_.Name)"
    try {
        Set-Variable -Name "var_$($_.Name)" -Value $window.FindName($_.Name) -ErrorAction Stop
    } catch {
        throw
    }
}

if($debug)
{
	Get-Variable var_*
}

function Get-TreeviewItems {
    param(
        [string]$folder
    )
    #Snagged some code from https://github.com/dev4sys/PsTreeFolderBrowser since treeview hurts my head when I start recursively doing stuff
    $errortempfolders = [IO.Directory]::GetDirectories($folder)
    $errortempfiles = [IO.Directory]::GetFiles($folder)
    $var_treeview_folder.Items.Clear()

    foreach ($folder in $errortempfolders){
        $treeViewItem = New-Object System.Windows.Controls.TreeViewItem
        $treeViewItem.Header = $folder.Substring($folder.LastIndexOf("\") + 1)
        $treeViewItem.Tag = @("folder",$folder)
        $treeViewItem.Items.Add($null) | Out-Null
        $treeViewItem.Add_Expanded({
            TreeExpanded($_.OriginalSource)
        })
        $var_treeview_folder.Items.Add($treeViewItem) | Out-Null
    }

    foreach ($file in $errortempfiles){
        $treeViewItem = [Windows.Controls.TreeViewItem]::new()
        $treeViewItem.Header = $file.Substring($file.LastIndexOf("\") + 1)
        $treeViewItem.Tag = @("file",$file) 
        $var_treeview_folder.Items.Add($treeViewItem) | Out-Null
        $treeViewItem.Add_PreviewMouseLeftButtonDown({
            [System.Windows.Controls.TreeViewItem]$sender = $args[0]
            [System.Windows.RoutedEventArgs]$e = $args[1]
            if ($sender.Tag[1] -match ".jpg$|.jpeg$|.bmp$|.txt$|.log$|.zip$")
            {
                $var_lblStatus.Text = "Selected $($sender.Tag[1].Substring($sender.Tag[1].LastIndexOf("\") + 1)). Right-click the file to open."
            }
            else {
                $var_lblStatus.Text = "Selected $($sender.Tag[1].Substring($sender.Tag[1].LastIndexOf("\") + 1))."
            }
        })
        $treeViewItem.Add_PreviewMouseRightButtonDown({
            [System.Windows.Controls.TreeViewItem]$sender = $args[0]
            [System.Windows.RoutedEventArgs]$e = $args[1]
            if ($sender.Tag[1] -match ".jpg$|.jpeg$|.bmp$|.txt$|.log$|.zip$")
            {
                $var_lblStatus.Text = "Opened $($sender.Tag[1].Substring($sender.Tag[1].LastIndexOf("\") + 1)) in your native viewer"
                Invoke-Item -Path $sender.Tag[1]
            }
            else {
                $var_lblStatus.Text = "Did not open file of type $($sender.Tag[1].Substring($sender.Tag[1].LastIndexOf("\") + 1)) - blocked by this tool"
            }
        })
    }
}

function TreeExpanded($sender){
    $item = [Windows.Controls.TreeViewItem]$sender
    If ($item.Items.Count -eq 1 -and $null -eq $item.Items[0])
    {
        $item.Items.Clear();
        Try
        {
            foreach ($string in [IO.Directory]::GetDirectories($item.Tag[1].ToString()))
            {
                $subitem = [Windows.Controls.TreeViewItem]::new();
                $subitem.Header = $string.Substring($string.LastIndexOf("\") + 1)
                $subitem.Tag = @("folder",$string)
                $subitem.Items.Add($null)
                $subitem.Add_Expanded({
                    TreeExpanded($_.OriginalSource)
                })
                $item.Items.Add($subitem) | Out-Null
            }
            foreach ($file in [IO.Directory]::GetFiles($item.Tag[1].ToString())){
                $subitem = [Windows.Controls.TreeViewItem]::new()
                $subitem.Header = $file.Substring($file.LastIndexOf("\") + 1)
                $subitem.Tag = @("file",$file) 
                $item.Items.Add($subitem)| Out-Null
                $subitem.Add_PreviewMouseLeftButtonDown({
		            [System.Windows.Controls.TreeViewItem]$sender = $args[0]
                    [System.Windows.RoutedEventArgs]$e = $args[1]
                    if ($sender.Tag[1] -match ".jpg$|.jpeg$|.bmp$|.txt$|.log$|.zip$")
                    {
                        $var_lblStatus.Text = "Selected $($sender.Tag[1].Substring($sender.Tag[1].LastIndexOf("\") + 1)). Right-click the file to open."
                    }
                    else {
                        $var_lblStatus.Text = "Selected $($sender.Tag[1].Substring($sender.Tag[1].LastIndexOf("\") + 1))."
                    }
	            })
	            $subitem.Add_PreviewMouseRightButtonDown({
		            [System.Windows.Controls.TreeViewItem]$sender = $args[0]
                    [System.Windows.RoutedEventArgs]$e = $args[1]
                    if ($sender.Tag[1] -match ".jpg$|.jpeg$|.bmp$|.txt$|.log$|.zip$")
                    {
                        $var_lblStatus.Text = "Opened $($sender.Tag[1]) in your native viewer"
                        Invoke-Item -Path $sender.Tag[1]
                    }
                    else {
                        $var_lblStatus.Text = "Did not open file of type $($sender.Tag[1].Substring($sender.Tag[1].LastIndexOf("\") + 1)) - blocked by this tool"
                    }
                    
                })
            }
        }   
        Catch [Exception] { }
    }    
}

$var_mainwindowpanel.Add_DragOver({
    $_.Effects = [System.Windows.DragDropEffects]::Copy
    $_.Handled = $true
})

$var_mainwindowpanel.Add_Drop({

    [System.Object]$script:sender = $args[0]
    [System.Windows.DragEventArgs]$e = $args[1]

    If($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)){

        $thingsdropped =  $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
        Write-Host "User dropped files into the app. Processing $($thingsdropped.Count) items" 
        Foreach($thing in $thingsdropped){
            if ((Get-Item -Path $thing).PSIsContainer)
            {
                Copy-Item -Path $thing -Destination $var_txtbx_errorpath.Text -Recurse -Verbose
                $var_lblStatus.Text = "All files dragged into the app have been copied to $($var_txtbx_errorpath.Text)"
                Write-Host "All files copied."
            }
            else 
            {
                Copy-Item -Path $thing -Destination $var_txtbx_errorpath.Text -Verbose
                $var_lblStatus.Text = "Copied $thing to $($var_txtbx_errorpath.Text)"
            }
        }
        Get-TreeviewItems -folder $var_txtbx_errorpath.Text
    }
})


#-----------------------------------------------------------------------------------------------#
# Gonna separate the GUI stuff to the top and the rest of the functions and work to the bottom. #
#-----------------------------------------------------------------------------------------------#

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

$var_menu_exit.Add_Click({
    $window.Close()
})

$var_btn_openfolder.Add_Click({
    Invoke-Item -Path $var_txtbx_errorpath.Text
})

$var_menu_dxdiag.Add_Click({
    Write-Host "Starting DXDiag"
    $var_lblStatus.Text = "Started dxdiag. It may take a while to appear. Tool is idle."
    Start-Process "dxdiag.exe"
})

$var_menu_msinfo.Add_Click({
    Write-Host "Starting MSInfo32"
    $var_lblStatus.Text = "Started Microsoft System Information . It may take a while to appear. Tool is idle"
    Start-Process "msinfo32.exe"
})

$var_menu_refresh.Add_Click({
    Get-TreeviewItems -folder $var_txtbx_errorpath.Text
})

$var_btn_loggoblin.Add_Click({
    Get-LogGoblin -loggoblinexe $loggoblin -errorlogfolder $var_txtbx_errorpath.Text
})

$var_btn_senderrors.Add_Click({
    Set-Content -Path (Join-Path -Path $var_txtbx_errorpath.Text -ChildPath "crashnotes.txt") -Value $var_txtbx_notes.Text
    $zipfile = New-ErrorZipFile -source $var_txtbx_errorpath.Text
    if (Test-Path -Path $zipfile)
    {
        Import-Module "AWSPowerShell" -Verbose
        if (Get-AWSCredential "CRASHDUMP")
        {
            Write-S3Object -BucketName itevents-crashdump -File $zipfile -Region "us-west-2" -Credential (Get-AWSCredential "CRASHDUMP")
            Remove-Item $zipfile -Verbose
            Remove-Item $var_txtbx_errorpath.Text -Recurse -Force -Verbose
            $var_menu_refresh.IsEnabled = $false
            $var_treeview_folder.IsEnabled = $false
            $var_btn_senderrors.Content = "Error log sent!"
            $var_lblStatus.Text = "$zipfile sent to Blizzard AWS. You may now close this tool."
            [System.Windows.MessageBox]::Show("Error log sent!",'Submit ZIP file','OK','Information')
        }
        else {
            [System.Windows.MessageBox]::Show("Unable to retrieve AWS Credentials",'Submit ZIP file','OK','Error')    
        }        
    }
    else {
        [System.Windows.MessageBox]::Show("Unable to find zip file `r`n$zipfile",'Submit ZIP file','OK','Error')
    }
    $var_btn_senderrors.IsEnabled = $false
})



function New-ErrorZipFile
{
    param(
        [string]$source = $var_txtbx_errorpath.Text
    )
    $var_lblStatus.Text = "Attempting to create $source.zip"
    try{
        Add-Type -AssemblyName "System.IO.Compression.FileSystem"
        [IO.Compression.Zipfile]::CreateFromDirectory($source,"$source.zip")
        $var_lblStatus.Text = "Created $source.zip. Submitting to AWS may take a while...please wait"
        $var_btn_senderrors.IsEnabled = $false
        return "$source.zip"
    }
    catch{
        [System.Windows.MessageBox]::Show($_.Exception.Message,'Generate ZIP file','OK','Error')
        return $null
    }
    
}



function Get-LogGoblin
{
    param(
        [string]$loggoblinexe = $loggoblin,
        [string]$errorlogfolder
    )
    $var_lblStatus.Text = "Starting LogGoblin. This may take a while and it requires you to press a key when it is done."
    Start-Process -FilePath $loggoblinexe -WorkingDirectory $errorlogfolder -Wait
    Get-TreeviewItems -folder $errorlogfolder
    $var_lblStatus.Text = "LogGoblin gathering is complete."
    $var_btn_loggoblin.Content = "Battle.net LogGoblin complete >"
    $var_btn_loggoblin.IsEnabled = $false
}

$var_lbl_sysinfo.Text = @"
1. Save any in-game error messages in the folder
2. Run the Battle.net "LogGoblin.exe" tool to capture Battle.net logs using the button below.
3. Take note of player Battle.net Battle Tag, Timestamp and information on the last few seconds of gameplay before the crash.
4. Hit the submit button on the bottom right.
"@

$var_txtbx_notes.Text = @"
Battle.net Battle Tag: 
Time of crash: 

Additional Information: 
"@

#build UI according to environment
$window.Title = $window.Title + " -  [> Env: $($game) <][> Hostname: $($env:TELEGRAF_HOSTNAME) <][> Player: $($playername) <][> Team: $($env:TELEGRAF_TEAMNAME) <]"

if (!([Environment]::GetEnvironmentVariable("AWS_CRASHDUMP_REGION", "User")) -or !([Environment]::GetEnvironmentVariable("AWS_CRASHDUMP_NAME", "User")))
{
    $var_lblStatus.Text = "Environment not set up properly. Please contact IT for help"
    $var_btn_senderrors.IsEnabled = $false
    $var_btn_senderrors.Content = "Missing info to send"
}

#clean up old folders
$oldfolders = Get-ChildItem -Directory $errorreportingfolder
foreach ($folder in $oldfolders)
{
    Remove-Item $folder.FullName -Recurse -Verbose
}
$oldzips = Get-ChildItem -Filter "*.zip" -Path $errorreportingfolder
foreach ($zip in $oldzips)
{
    Remove-Item $zip.FullName -Verbose
}

#create temp folder
$basefolder = "$($game)-$($env:TELEGRAF_TEAMNAME)-$playername-$(Get-Date -format "yyyyMMddhhmmss")"
$tempfolder = Join-Path -Path $errorreportingfolder -ChildPath $basefolder
New-FolderStructure $tempfolder
$var_txtbx_errorpath.Text = $tempfolder

Get-TreeviewItems -folder $tempfolder

#UI stuff
$var_btn_reportcodbug.IsEnabled = $false
$var_btn_reportcodbug.Visibility="Hidden"

$Null = $window.ShowDialog()