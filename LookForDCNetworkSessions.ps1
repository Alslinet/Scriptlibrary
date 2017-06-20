#Script for looking for connections to any domain controller on a specific machine.
#Also includes logic for parsing netstat -ano output.
[CmdletBinding()]
Param(
   [Parameter(Position=1)]
   [string]$computerName = $env:COMPUTERNAME,
	
   [Parameter()]
   [string]$logFile
)

$Computername = "COMPUTERNAME"
$TranscriptFile = $logFile



$domain = [System.Directoryservices.Activedirectory.Domain]::GetCurrentDomain()
$DCIPs = $domain.DomainControllers | Select-Object IPAddress

if ($TranscriptFile -eq ""){"There will be no transcript"}
else { Start-Transcript -Path $TranscriptFile -Force}
$TimeStart = Get-Date
$TimeEnd = $TimeStart.addHours(8)

"Time start: $TimeStart"
"Time end  : $Timeend"
Do {
"Running netstat"
$NetworkStatistics = Invoke-Command -ComputerName $Computername {
function Parse-Netstat {
    [CmdletBinding(ConfirmImpact='Low')] 
    Param()

    $Connections = netstat -ano
    Write-Verbose 'Connections (output of netstat -ano):' 
    Write-Verbose ($Connections | Out-String)
    $NetStatRecords = @()
    $Connections[4..$Connections.count] | % {
        Write-Verbose "Parsing line: $_ "
        $Fragments = ($_ -replace '\s+', ' ').Split(' ')
        if ($Fragments[2].Contains('[')) { 
            $Version       = 'IPv6'
            $LocalAddress  = $Fragments[2].Split(']')[0].Split('[')[1]
            $LocalPort     = $Fragments[2].Split(']')[1].Split(':')[1]            
        } else { 
            $Version       = 'IPv4'
            $LocalAddress  = $Fragments[2].Split(':')[0] 
            $LocalPort     = $Fragments[2].Split(':')[1]
        }
        if ($Fragments[3].Contains('[')) { 
            $RemoteAddress = $Fragments[3].Split(']')[0].Split('[')[1]
            $RemotePort    = $Fragments[3].Split(']')[1].Split(':')[1]
        } else { 
            $RemoteAddress = $Fragments[3].Split(':')[0] 
            $RemotePort    = $Fragments[3].Split(':')[1]
        }
        $ProcessID = $(if ($RemoteAddress -eq '*') {$Fragments[4]} else {$Fragments[5]})
        $Props = [ordered]@{
            Protocol      = $Fragments[1]
            Version       = $Version
            LocalAddress  = $LocalAddress
            LocalPort     = $LocalPort
            RemoteAddress = $RemoteAddress
            RemotePort    = $RemotePort
            State         = $(if ($RemoteAddress -eq '*') {''} else {$Fragments[4]}) 
            ProcessID     = $ProcessID
            ProcessName   = $((Get-Process -Id $ProcessID).Name)
            ProcessPath   = $((Get-Process -Id $ProcessID).Path)
        }
        $Record = New-Object -TypeName PSObject -Property $Props
        Write-Verbose 'Parsed into record:'
        Write-Verbose ($Record | Out-String)
        $NetStatRecords += $Record
    }
    $NetStatRecords
}
Parse-Netstat
}
$DateTime = Get-Date
"Netstat results $DateTime"
$NetworkStatistics | Where {$_.RemoteAddress -in $($DCIPs.IPAddress)} | Format-Table

} Until ($TimeNow -ge $TimeEnd)
$TimeEnd

if ($TranscriptFile -eq ""){}
else {Stop-Transcript}
$NetworkStatistics = $Null