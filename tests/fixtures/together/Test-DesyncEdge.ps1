[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Executable, original-only model of TiltedEvolution commit
# 9d81ef07d68e4bb2bd94fca246e798a564b7fb92:
#   client InventoryService::OnInventoryChangeEvent
#   server InventoryService::OnInventoryChanges
#   client InventoryService::OnNotifyInventoryChanges

function Assert-Equal {
    param(
        [Parameter(Mandatory)] $Actual,
        [Parameter(Mandatory)] $Expected,
        [Parameter(Mandatory)] [string] $Label
    )

    if ($Actual -ne $Expected) {
        throw "ASSERT FAILED: $Label expected=$Expected actual=$Actual"
    }

    Write-Host "ASSERT $Label=$Actual"
}

function New-Simulation {
    [pscustomobject]@{
        Owner = 'owner-a'
        InRangePlayers = @('owner-a', 'remote-b')
        ServerCount = 0
        RemoteCounts = @{ 'remote-b' = 0 }
        Trace = [System.Collections.Generic.List[string]]::new()
    }
}

function Invoke-OwnerCapture {
    param(
        [Parameter(Mandatory)] $Simulation,
        [Parameter(Mandatory)] [bool] $UpdateClients
    )

    $Simulation.Trace.Add('owner:capture')
    $Simulation.Trace.Add('owner->server:RequestInventoryChanges')

    [pscustomobject]@{
        ServerId = 42
        Item = [pscustomobject]@{
            ModId = 7
            BaseId = 0xABC
            Count = 1
        }
        Drop = $false
        UpdateClients = $UpdateClients
    }
}

function Invoke-ServerInventoryChanges {
    param(
        [Parameter(Mandatory)] $Simulation,
        [Parameter(Mandatory)] $Request
    )

    # The source mutates InventoryComponent before testing UpdateClients.
    $Simulation.ServerCount += $Request.Item.Count
    $Simulation.Trace.Add('server:InventoryComponent-applied')

    if (-not $Request.UpdateClients) {
        $Simulation.Trace.Add('server->remote:NotifyInventoryChanges-suppressed')
        return @()
    }

    # SendToPlayersInRange excludes acMessage.GetSender().
    $recipients = @($Simulation.InRangePlayers | Where-Object { $_ -ne $Simulation.Owner })
    $Simulation.Trace.Add('server->remote:NotifyInventoryChanges')

    @($recipients | ForEach-Object {
        [pscustomobject]@{
            Recipient = $_
            ServerId = $Request.ServerId
            Item = $Request.Item
            Drop = $false
        }
    })
}

function Invoke-RemoteApply {
    param(
        [Parameter(Mandatory)] $Simulation,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Notifications
    )

    if ($Notifications.Count -eq 0) {
        $Simulation.Trace.Add('remote:no-notification-to-apply')
        return
    }

    foreach ($notification in $Notifications) {
        $Simulation.RemoteCounts[$notification.Recipient] += $notification.Item.Count
        $Simulation.Trace.Add("remote:$($notification.Recipient):AddOrRemoveItem")
    }
}

function Invoke-Case {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [bool] $UpdateClients
    )

    $simulation = New-Simulation
    $request = Invoke-OwnerCapture -Simulation $simulation -UpdateClients $UpdateClients
    $notifications = @(Invoke-ServerInventoryChanges -Simulation $simulation -Request $request)
    Invoke-RemoteApply -Simulation $simulation -Notifications $notifications

    Write-Host "CASE $Name"
    $simulation.Trace | ForEach-Object { Write-Host "TRACE $_" }
    Assert-Equal -Actual $simulation.ServerCount -Expected 1 -Label "$Name.server-count"
    Assert-Equal -Actual $simulation.RemoteCounts['remote-b'] -Expected ([int]$UpdateClients) -Label "$Name.remote-count"
    Assert-Equal -Actual $notifications.Count -Expected ([int]$UpdateClients) -Label "$Name.notification-count"
    Assert-Equal -Actual (@($notifications | Where-Object Recipient -eq $simulation.Owner).Count) -Expected 0 -Label "$Name.sender-notified"

    [pscustomobject]@{
        Simulation = $simulation
        Notifications = $notifications
    }
}

try {
    $suppressed = Invoke-Case -Name 'update-clients-false' -UpdateClients $false
    Assert-Equal -Actual $suppressed.Simulation.Trace[2] -Expected 'server:InventoryComponent-applied' -Label 'suppressed.server-applies-before-gate'
    Assert-Equal -Actual $suppressed.Simulation.Trace[3] -Expected 'server->remote:NotifyInventoryChanges-suppressed' -Label 'suppressed.modeled-gate'
    'MODELED_SUPPRESSED_EDGE=server->remote NotifyInventoryChanges (UpdateClients=false early return)'

    $broadcast = Invoke-Case -Name 'update-clients-true' -UpdateClients $true
    Assert-Equal -Actual $broadcast.Notifications[0].Recipient -Expected 'remote-b' -Label 'broadcast.recipient'
    Assert-Equal -Actual $broadcast.Simulation.Trace[3] -Expected 'server->remote:NotifyInventoryChanges' -Label 'broadcast.edge-restored'
    Assert-Equal -Actual $broadcast.Simulation.Trace[4] -Expected 'remote:remote-b:AddOrRemoveItem' -Label 'broadcast.remote-apply'

    'RESULT=PASS cases=2 boundary=independently-authored-model-not-production'
    exit 0
}
catch {
    "RESULT=FAIL $($_.Exception.Message)"
    exit 1
}
