# Verlinkt jedes Addon aus .\AddOns per Junction in den AddOns-Ordner des Forever-Beta-Clients.
# Danach wirken Aenderungen hier sofort im Spiel (nach /reload). Braucht keine Admin-Rechte.
#
# Aufruf:  pwsh tools/link-addons.ps1 [-WowAddOns <Pfad>]

param(
    [string]$WowAddOns = "X:\Spielplatz\BattleNet\World of Warcraft\_classic_beta_\Interface\AddOns"
)

$source = Join-Path (Split-Path $PSScriptRoot -Parent) "AddOns"

if (-not (Test-Path $WowAddOns)) {
    throw "WoW-AddOns-Ordner nicht gefunden: $WowAddOns"
}

foreach ($addon in Get-ChildItem $source -Directory) {
    $target = Join-Path $WowAddOns $addon.Name
    if (Test-Path $target) {
        $item = Get-Item $target -Force
        if ($item.LinkType -eq "Junction" -and $item.Target -contains $addon.FullName) {
            Write-Host "ok        $($addon.Name)"
        } else {
            Write-Warning "uebersprungen $($addon.Name): im Spiel existiert bereits ein Ordner/Link mit diesem Namen."
        }
        continue
    }
    New-Item -ItemType Junction -Path $target -Target $addon.FullName | Out-Null
    Write-Host "verlinkt  $($addon.Name)"
}
