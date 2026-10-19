# Windows version of restore.sh: re-enable every package listed in a debloat file, restore the
# stock launcher as home and reset animation scales. Pass the same list you used with disable.ps1.
#
# Usage: tools\restore.ps1 -TvHost 192.168.1.50 examples\xiaomi-mi-tv-4a\debloat.txt [-Stock stock.launcher.package]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$List,
    [string]$Stock = 'com.google.android.tvlauncher',
    [string]$TvHost = $env:TV_HOST
)
$ErrorActionPreference = 'Stop'
# Pipe plain UTF-8 to native commands; the default here prepends a BOM that corrupts the first command.
$OutputEncoding = New-Object System.Text.UTF8Encoding $false
$repo = Split-Path -Parent $PSScriptRoot
$List = (Resolve-Path $List).Path
$py = Join-Path $repo 'tools\venv\Scripts\python.exe'
if (-not (Test-Path $py)) { throw 'run: python -m venv tools\venv; tools\venv\Scripts\python.exe -m pip install -r tools\requirements.txt' }
if (-not $TvHost) { throw 'pass -TvHost <tv ip> or set $env:TV_HOST' }
$env:TV_HOST = $TvHost

$pkgs = Get-Content $List | ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ }
# Each name ends up inside a shell command on the TV, so refuse the whole list unless every line is a package name.
$bad = @($pkgs | Where-Object { $_ -notmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$' })
if ($bad.Count) { throw "not package names, nothing was sent to the TV: $($bad -join ', ')" }
if (-not $pkgs) { throw "$List lists no packages (every line is a comment or blank)" }
if (-not $PSBoundParameters.ContainsKey('Stock')) {
    # Google TV's stock launcher is not the Android TV one; guessing wrong leaves it disabled.
    $disabled = @(& $py -I (Join-Path $repo 'tools\tv.py') 'pm list packages -d') | ForEach-Object { "$_".Trim() }
    foreach ($c in 'com.google.android.apps.tv.launcherx', 'com.google.android.tvlauncher', 'com.google.android.leanbacklauncher') {
        if ($disabled -contains "package:$c") { $Stock = $c; break }   # whole-line match, not a substring
    }
    Write-Host "Stock launcher: $Stock (pass -Stock to choose another)"
}
if ($Stock -notmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$') { throw "'$Stock' is not a package name" }
# The stock launcher goes first: enabling the setup wizard (often in the list) while no stock launcher is
# enabled lets the wizard take over Home. It is enabled and set as Home again at the end, because Android
# drops the Home preference whenever the set of Home apps changes.
$cmds = @("pm enable --user 0 $Stock") + @($pkgs | ForEach-Object { "pm enable --user 0 $_" }) + @(
    "pm enable --user 0 $Stock",
    # resolve the stock HOME component on the TV (Android 9 needs pkg/activity, not just pkg)
    ('c=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME ' + $Stock + ' | tail -n 1); case "$c" in */*) cmd package set-home-activity --user 0 "$c" ;; *) echo "could not resolve a Home activity for ' + $Stock + '" ;; esac'),
    'settings put global window_animation_scale 1.0',
    'settings put global transition_animation_scale 1.0',
    'settings put global animator_duration_scale 1.0',
    'pm list packages -d'
)
$cmds | & $py -I (Join-Path $repo 'tools\tv.py') --batch
