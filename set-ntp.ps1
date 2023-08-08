If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    $regex = ".ps1\s(.*)$"
    if ($MyInvocation.Line -match $regex)
    {
        $arguments = "-executionpolicy bypass -command powershell.exe -file '" + $myinvocation.mycommand.definition + "' $($matches[1])"
    }
    else
    {
        $arguments = "-executionpolicy bypass -command powershell.exe -file '" + $myinvocation.mycommand.definition + "'"
    }
    Start-Process powershell -Verb runAs -ArgumentList $arguments
    Break
}

Function Get-NtpTime {

<#
.Synopsis
Gets (Simple) Network Time Protocol time (SNTP/NTP, rfc-1305, rfc-2030) from a specified server
.DESCRIPTION
This function connects to an NTP server on UDP port 123 and retrieves the current NTP time.
Selected components of the returned time information are decoded and returned in a PSObject.
.PARAMETER Server
The NTP Server to contact.  Uses pool.ntp.org by default.
.EXAMPLE
Get-NtpTime uk.pool.ntp.org
Gets time from the specified server.
.EXAMPLE
Get-NtpTime | fl *
Get time from default server (pool.ntp.org) and displays all output object attributes.
.OUTPUTS
A PSObject containing decoded values from the NTP server.  Pipe to fl * to see all attributes.
.FUNCTIONALITY
Gets NTP time from a specified server.
#>

    [CmdletBinding()]
Param (
[String]$Server = ‘time.google.com’
)
    # Construct a 48-byte client NTP time packet to send to the specified server
# (Request Header: [00=No Leap Warning; 011=Version 3; 011=Client Mode]; 00011011 = 0x1B)

    [Byte[]]$NtpData = ,0 * 48
$NtpData[0] = 0x1B   
    $Socket = New-Object Net.Sockets.Socket([Net.Sockets.AddressFamily]::InterNetwork,
[Net.Sockets.SocketType]::Dgram,
[Net.Sockets.ProtocolType]::Udp)

    $LocalTime = Get-Date

    Try {
$Socket.Connect($Server,123)
[Void]$Socket.Send($NtpData)
[Void]$Socket.Receive($NtpData)
}
Catch {
Write-Error “Failed to communicate with server $Server”
Throw $_
}

    $Socket.Close()

    # Decode the received NTP time packet

    # Extract the flags from the first byte by masking and shifting (dividing)

    $LI = ($NtpData[0] -band 0xC0)/64    # Leap Second indicator
$LI_text = Switch ($LI) {
0    {‘no warning’}
1    {‘last minute has 61 seconds’}
2    {‘last minute has 59 seconds’}
3    {‘alarm condition (clock not synchronized)’}
}
$VN = ($NtpData[0] -band 0x38)/8     # Server versions number
$Mode = ($NtpData[0] -band 0x07)     # Server mode (probably ‘server’!)
$Mode_text = Switch ($Mode) {
0    {‘reserved’}
1    {‘symmetric active’}
2    {‘symmetric passive’}
3    {‘client’}
4    {‘server’}
5    {‘broadcast’}
6    {‘reserved for NTP control message’}
7    {‘reserved for private use’}
}

    $Stratum = [UInt16]$NtpData[1]   # Actually [UInt8] but we don’t have one of those…
$Stratum_text = Switch ($Stratum) {
0                            {‘unspecified or unavailable’}
1                            {‘primary reference (e.g., radio clock)’}
{$_ -ge 2 -and $_ -le 15}    {‘secondary reference (via NTP or SNTP)’}
{$_ -ge 16}                  {‘reserved’}
}

    $PollInterval = $NtpData[2]              # Poll interval – to neareast power of 2
$PollIntervalSeconds = [Math]::Pow(2, $PollInterval)

    $PrecisionBits = $NtpData[3]      # Precision in seconds to nearest power of 2
# …this is a signed 8-bit int
If ($PrecisionBits -band 0x80) {    # ? negative (top bit set)
[Int]$Precision = $PrecisionBits -bor 0xFFFFFFE0    # Sign extend
} else {
# ..this is unlikely – indicates a precision of less than 1 second
[Int]$Precision = $PrecisionBits   # top bit clear – just use positive value
}
$PrecisionSeconds = [Math]::Pow(2, $Precision)

    # We now have the 64-bit NTP time in the last 8 bytes of the received data.
# The NTP time is the number of seconds since 1/1/1900 and is split into an
# integer part (top 32 bits) and a fractional part, multipled by 2^32, in the
# bottom 32 bits.

    # Convert Integer and Fractional parts of 64-bit NTP time from byte array
$IntPart=0;  Foreach ($Byte in $NtpData[40..43]) {$IntPart  = $IntPart  * 256 + $Byte}
$FracPart=0; Foreach ($Byte in $NtpData[44..47]) {$FracPart = $FracPart * 256 + $Byte}

    # Convert to Millseconds (convert fractional part by dividing value by 2^32)
[UInt64]$Milliseconds = $IntPart * 1000 + ($FracPart * 1000 / 0x100000000)

    # Create UTC date of 1 Jan 1900, add the NTP offset and convert the result from utc to local time
$NtpTime=(New-Object DateTime(1900,1,1,0,0,0,[DateTimeKind]::Utc)).AddMilliseconds($Milliseconds).ToLocalTime()
    # Create Output object and return

    $NtpTimeObj = [PSCustomObject]@{
NtpTime = $NtpTime
LI = $LI
LI_text = $LI_text
NtpVersionNumber = $VN
Mode = $Mode
Mode_text = $Mode_text
Stratum = $Stratum
Stratum_text = $Stratum_text
PollIntervalRaw = $PollInterval
PollInterval = New-Object TimeSpan(0,0,$PollIntervalSeconds)
Precision = $Precision
PrecisionSeconds = $PrecisionSeconds
LocalDifference = [TimeSpan]($NtpTime – $LocalTime)
Raw = $NtpData   # The undecoded bytes returned from the NTP server
}

    # Set default display properties for object

    [String[]]$DefaultProperties =  ‘NtpTime’, ‘NtpVersionNumber’,’Mode_text’,’Stratum’, ‘PollInterval’,
‘PrecisionSeconds’, ‘LocalDifference’

    # Add the PSStandardMembers.DefaultDisplayPropertySet member
$ddps = New-Object Management.Automation.PSPropertySet(‘DefaultDisplayPropertySet’, $DefaultProperties)
$PSStandardMembers = [Management.Automation.PSMemberInfo[]]$ddps

    # Attach default display property set and output object
$NtpTimeObj | Add-Member -MemberType MemberSet -Name PSStandardMembers -Value $PSStandardMembers -PassThru
}

# Retry until NTP data can be pulled
do {
    try {
        $failed = $false
        Get-NtpTime -ea SilentlyContinue
        }
    catch {
        $failed = $true
        Start-Sleep -s 5
        }
    } until ($failed -eq $false)

# Pulls time from time.google.com, assigns it to PC
Set-Date (Get-NtpTime).ntptime

# Enables "set time automatically"
if ((Get-ItemProperty hklm:\SYSTEM\CurrentControlSet\Services\tzautoupdate\ -name "Start") -ne 3){
    Set-ItemProperty hklm:\SYSTEM\CurrentControlSet\Services\tzautoupdate\ -name "Start" -Value 3 -Type DWord
    }

# Enables "set time zone automatically"
if ((Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\w32time\Parameters).type -ne "NTP"){
    Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\w32time\Parameters -name "Type" -Value "NTP" -Type String
    }