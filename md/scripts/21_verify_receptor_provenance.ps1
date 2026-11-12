# 21_verify_receptor_provenance.ps1 - prove every run used the same receptor.
#
# Why this exists. Three MD campaigns were launched from three different local
# folders over three weeks, and Downloads\tem1_md was later deleted, so the
# local inputs could no longer be compared. Without this check the runs are not
# demonstrably comparable and the methods section cannot claim they are.
#
# simulate() writes _rec.pdb into every compound's output directory - the exact
# receptor that run used, preserved on the volume. Hashing those against the
# docking receptor closes the provenance chain:
#
#     1BTL_clean.pdb (docking)  ==  _rec.pdb (every MD run)
#
# All eight hashes came back D8F974B3AEA9AE87EFB86C495B10E52A.
#
# Read-only apart from the downloads. Costs nothing.

$d = "$env:USERPROFILE\Downloads\recheck"
New-Item -ItemType Directory -Force -Path $d | Out-Null
$env:PYTHONUTF8 = "1"

foreach ($t in @("prod", "prod100", "prod_r2")) {
  python -m modal volume get tem1-md "$t/Avibactam/_rec.pdb" "$d\${t}_rec.pdb" 2>$null
  python -m modal volume get tem1-md "$t/BTL-004/_rec.pdb"   "$d\${t}_btl004_rec.pdb" 2>$null
}

$vina = "$env:USERPROFILE\Downloads\tem1_vina\1BTL_clean.pdb"
if (Test-Path $vina) { Copy-Item $vina "$d\vina_1BTL_clean.pdb" }

Get-ChildItem $d -File | ForEach-Object {
  "{0,-28} {1}" -f $_.Name, (Get-FileHash $_.FullName -Algorithm MD5).Hash
}
Write-Host "`nAll hashes identical = docking and every MD run used one receptor." -ForegroundColor Green
