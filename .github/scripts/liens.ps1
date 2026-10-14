# Liens de developpement : chaque dossier d addon du depot (CorpUI et
# CorpUI_Xxx) apparait dans AddOns par une jonction Windows (pas de copie,
# pas de droits d administrateur). Un vrai dossier du meme nom n est jamais
# touche : le script le signale (ancienne installation a deplacer d abord).
# Usage (PowerShell, depuis le depot) :
#   .github\scripts\liens.ps1                 (AddOns de _classic_beta_)
#   .github\scripts\liens.ps1 -AddOns <chemin du dossier AddOns>
# (PowerShell ne distingue pas les majuscules : $AddOns est le chemin, $dossiers la liste)
param([string]$AddOns = (Join-Path $PSScriptRoot "..\..\..\Interface\AddOns"))

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$AddOns = (Resolve-Path $AddOns).Path

$dossiers = Get-ChildItem $repo -Directory | Where-Object {
    $_.Name -match '^CorpUI(_[A-Za-z]+)?$' -and (Test-Path (Join-Path $_.FullName ($_.Name + ".toc")))
}
$made = 0
$kept = 0
foreach ($a in $dossiers) {
    $link = Join-Path $AddOns $a.Name
    if (Test-Path $link) {
        $item = Get-Item $link -Force
        if ($item.LinkType -ne "Junction") {
            Write-Warning "$link est un vrai dossier : deplace-le hors de AddOns, puis relance ce script."
            continue
        }
        if (@($item.Target)[0] -eq $a.FullName) { $kept++; continue }
        # jonction vers un autre endroit : refaite
        [System.IO.Directory]::Delete($link)
    }
    New-Item -ItemType Junction -Path $link -Target $a.FullName -ErrorAction Stop | Out-Null
    $made++
}
# jonctions CorpUI_Xxx dont l addon n existe plus dans le depot : retirees
Get-ChildItem $AddOns -Directory -Force | Where-Object {
    $_.Name -match '^CorpUI(_[A-Za-z]+)?$' -and $_.LinkType -eq "Junction" -and -not (Test-Path (Join-Path $repo $_.Name))
} | ForEach-Object {
    [System.IO.Directory]::Delete($_.FullName)
    Write-Host "lien retire : $($_.Name)"
}
Write-Host "liens crees : $made, deja en place : $kept, addons : $($dossiers.Count)"
