#-------------------------------------------------------------------------------------------------------------------
# [Project]
# HTTP Listerner for Home Desktop Control
# [Author & Date]
# Zachary McHone 02.15.2020
# [Other Considerations]
# A TCP exception was created for the local firewall for port 8090.
# Port forwarding and IFTTT was used to bridge the connection to Google Assistance.
#-------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------
# Console Appearance

$Host.UI.RawUI.BackgroundColor = ($bckgrnd = 'Gray')
$Host.UI.RawUI.ForegroundColor = 'White'
$Host.PrivateData.ErrorForegroundColor = 'Red'
$Host.PrivateData.ErrorBackgroundColor = $bckgrnd
$Host.PrivateData.WarningForegroundColor = 'Magenta'
$Host.PrivateData.WarningBackgroundColor = $bckgrnd
$Host.PrivateData.DebugForegroundColor = 'Yellow'
$Host.PrivateData.DebugBackgroundColor = $bckgrnd
$Host.PrivateData.VerboseForegroundColor = 'Green'
$Host.PrivateData.VerboseBackgroundColor = $bckgrnd
$Host.PrivateData.ProgressForegroundColor = 'Cyan'
$Host.PrivateData.ProgressBackgroundColor = $bckgrnd

$pswin = (Get-Host).UI.RawUI
$buffsize = $pswin.BufferSize
$winsize = $pswin.windowsize
$buffsize.width = 75
$winsize.width = 75
$pswin.buffersize = $buffsize
$pswin.windowsize = $winsize

Clear-Host

#-------------------------------------------------------------------------------------------------------------------
# Variables/Functions

$global:scriptConfig = @{}
$global:launchableApps = @{}
$global:localServices = @{}

[xml]$XMLconfig= Get-Content "c:\PS\HTTPListener.xml"
[String]$LogPath = $XMLconfig.configuration.scriptConfig.logpath
[String]$TodayDate = (Get-Date).toString("yyyyMMdd")
[String]$FileName = "HTTPListener-$($TodayDate).log"
[String]$TodayLogPath = $LogPath + $FileName

If (!(Test-Path $LogPath))
    {
    New-Item -itemtype Directory -path $LogPath | Out-Null
    }
If (!(Test-Path $TodayLogPath))
    {
    New-Item "$($TodayLogPath)" | Out-Null
    }

# Start Listener
$http = [System.Net.HttpListener]::new()
$http.Prefixes.Add("http://*:8090/")
$http.Start()
# $http.IsListening #Returns true or false

$stop = $False

function Log-It($mssg)
    {
    $dtevent = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss,fff")
    $newline = "$($dtevent)`t$($mssg)"
    Add-Content -Path $TodayLogPath -Value $newline
    Write-Host $newline
    }

function GetHTML
    {
    param([string]$body, [string]$backgroundcolor)
    return "<html><head><title>Nothing</title><body style=`"background-color: $($backgroundcolor); font-size: 24pt`">$($body)</body></html>" 
    }


#-------------------------------------------------------------------------------------------------------------------
# Begin

while ($http.IsListening)  
{

# Listen/Wait for request

$hcontext = $http.GetContext()

# Load Script Switch LAUNCH/KILL Keywords

foreach ($addNode in $XMLconfig.configuration.launchableApps.add) 
    {
    $global:launchableApps[$addNode.Key] = $addNode.Value
    Log-It "$($addNode.Key) is set to $($launchableApps[$addNode.Key])."
    }

# Load Script Switch SERVICE Keywords

foreach ($addNode in $XMLconfig.configuration.localServices.add) 
    {
    $global:localServices[$addNode.Key] = $addNode.Value
    Log-It "$($addNode.Key) is set to $($localServices[$addNode.Key])."
    }

$actionFlag = ""

#capture request and remove forward slash
$req = $hcontext.Request.RawUrl
$curated_req = $req.Replace("/","")

#remove "the" and replace %20 with a space
$curated_req = $curated_req.Replace("%20"," ")
$curated_req = $curated_req.Replace("the ","")

if (($curated_req -like "launch*" -or $curated_req -like "open*" -or $curated_req -like "start*") -and $curated_req -notlike "start*service")
    {
    $curated_req = $curated_req.Replace(" ","")
    $curated_req = $curated_req.Replace("launch","")
    $curated_req = $curated_req.Replace("open","")
    $curated_req = $curated_req.Replace("start","")
    $actionFlag = "launch"
    }
elseif ($curated_req -like "*stop*service*")
    {
    $curated_req = $($($curated_req.Replace("stop","")).Replace("service","")).Replace(" ","")
    Write-Host $curated_req
    $actionFlag = "stopserv"
    }
elseif ($curated_req -like "*start*service*")
    {
    $curated_req = $($($curated_req.Replace("start","")).Replace("service","")).Replace(" ","")
    Write-Host $curated_req
    $actionFlag = "startserv"
    }
elseif ($curated_req -like "kill*")
    {
    $curated_req = $curated_req.Replace("kill ","")
    $actionFlag = "kill"
    }

Log-It "$($req) => $($curated_req)"

Switch ($curated_req)
{    
    {$_ -match "display.{0,6}off" -or $_ -match "off.{0,6}the.{0,6}display"} 
        {
        Log-It "display turned off ($($hcontext.Request.HttpMethod), $($hcontext.Request.Url))" -f 'black'
        (Add-Type '[DllImport("user32.dll")]public static extern IntPtr PostMessage(int hWnd, int hMsg, int wParam, int lParam);' -Name a -Pas)::PostMessage(-1,0x0112,0xF170,2)
        $stop = $False

        $homehtml = GetHTML "display turned off" "#606060"
        Log-It $homehtml
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($homehtml)
        }

    {$XMLconfig.configuration.launchableApps.add.Key -contains $_ -and $actionFlag -eq "launch"}
        {
        Log-It "$($_) launched ($($hcontext.Request.HttpMethod), $($hcontext.Request.Url))" -f 'black'
        Start $launchableApps[$_]
        $stop = $False

        $homehtml = GetHTML "requested to launch $($_)" "#20C040"
        Log-It $homehtml
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($homehtml)
        }

    {$XMLconfig.configuration.launchableApps.add.Key -contains $_ -and $actionFlag -eq "kill"}
        {
        $tempArr = $launchableApps[$_].Split("\")
        $processKillName = $tempArr[$tempArr.Length-1].Split(".")[0]
        
        if ($processKillName -in $(Get-Process).ProcessName)
            {
            Log-It "$($processKillName) killed ($($hcontext.Request.HttpMethod), $($hcontext.Request.Url))" -f 'black'
            Stop-Process -Force -Name $processKillName
            }
            else
            {
            Log-It "$($processKillName) not running ($($hcontext.Request.HttpMethod), $($hcontext.Request.Url))" -f 'black'
            }

        $stop = $False

        $homehtml = GetHTML "requested to kill $($processKillName)" "#20C040"
        Log-It $homehtml
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($homehtml)
        }

    {$XMLconfig.configuration.localServices.add.Key -contains $_ -and ($actionFlag -eq "startserv" -or $actionFlag -eq "stopserv")}
        {
        $tempTargSvc = $localServices[$_]

        if ($tempTargSvc -in $(Get-Service).Name)
            {
            Switch ($actionFlag) 
                {
                "startserv"
                    {
                    Log-It "$($tempTargSvc) service started ($($hcontext.Request.HttpMethod), $($hcontext.Request.Url))" -f 'black'
                    Start-Service -Name $tempTargSvc
                    }
                "stopserv"
                    {
                    Log-It "$($tempTargSvc) service started ($($hcontext.Request.HttpMethod), $($hcontext.Request.Url))" -f 'black'
                    Stop-Service -Name $tempTargSvc
                    }
                }
            }
        else
            {
            Log-It "no services were harmed in the production of this listener ($($hcontext.Request.HttpMethod), $($hcontext.Request.Url))" -f 'black'
            }

        $stop = $False

        $homehtml = GetHTML "requested to $($actionflag.Replace('serv','')) $($processKillName)" "#20C040"
        Log-It $homehtml
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($homehtml)
        }

    {$_ -match "stop.{0,3}listen" } 
        {
        Log-It "listener stopped ($($hcontext.Request.HttpMethod), $($hcontext.Request.Url))" -f 'black'
        $stop = $True

        $homehtml = GetHTML "listener stopped" "#C04040"
        Log-It $homehtml
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($homehtml)
        }

    default
        {
        Log-It "Default message loaded ($($hcontext.Request.HttpMethod), $($hcontext.Request.Url))" -f 'black'

        $homehtml = GetHTML "... nothing here ... <br /><br />... move along." "#606060"
        Log-It $homehtml
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($homehtml)
        $stop = $False
        }

}

#$buffer.Length
$hcontext.Response.ContentLength64 = $buffer.Length
$hcontext.Response.OutputStream.Write($buffer, 0, $buffer.Length)
$hcontext.Response.OutputStream.Close() # close the response
If ($Stop) { $http.Stop() }

}

