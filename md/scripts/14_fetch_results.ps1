# =============================================================================
# BLOCK 14 - DOWNLOAD EVERYTHING
# =============================================================================
# WHAT THIS DOES
#   Pulls the report folder and the per-system run logs out of the Modal volume
#   and unpacks both into Downloads\TEM1_MD_results.
#
#   You get:
#     MD_report.pdf     every figure with an explanation of what it means
#     figures\*.png     300 dpi, publication ready, drop into the manuscript
#     data\*.csv        time in column 1, one column per compound - replot in
#                       your own style without re-running anything
#     tables\*.csv      summary table and hydrogen-bond occupancy per compound
#     <compound>\       build.json (every parameter used, for the methods
#                       section), equil.csv, prod.csv
#
#   Trajectories (.dcd) are deliberately NOT downloaded - they are large and
#   stay in the Modal volume. Everything needed for the paper is in the files
#   above.
#
#   This can be run at any time after the production run finishes, from any
#   machine logged into the same Modal account.
# =============================================================================

$dir = "$env:USERPROFILE\Downloads\tem1_md"
$out = "$env:USERPROFILE\Downloads\TEM1_MD_results"
Set-Location $dir
$env:PYTHONUTF8="1"; $env:PYTHONIOENCODING="utf-8"

python -m modal run md_app.py::fetch_report --tag prod --outdir "$dir\out"
New-Item -ItemType Directory -Force -Path $out | Out-Null
tar -xzf "$dir\out\prod_report.tar.gz" -C $out

python -m modal run md_app.py::fetch --tag prod --outdir "$dir\out"
tar -xzf "$dir\out\prod.tar.gz" -C $out

Write-Host "`nResults in: $out" -ForegroundColor Green
Get-ChildItem $out -Recurse -File | Select-Object FullName, Length | Format-Table -AutoSize
Write-Host "`nReport: $out\MD_report.pdf" -ForegroundColor Cyan
