# =============================================================================
# BLOCK 14 - DOWNLOAD THE REPORT FOLDER
# =============================================================================
# Everything lands in Downloads\TEM1_MD_results:
#   MD_report.pdf      every figure with an explanation of what it means
#   figures\*.png      300 dpi, publication ready, drop straight into the paper
#   data\*.csv         time in column 1, one column per compound - replot freely
#   tables\*.csv       summary and hydrogen-bond occupancy
#   <compound>\        build.json, equil.csv, prod.csv per system
# =============================================================================

$dir = "$env:USERPROFILE\Downloads\tem1_md"
$out = "$env:USERPROFILE\Downloads\TEM1_MD_results"
Set-Location $dir
$env:PYTHONUTF8="1"; $env:PYTHONIOENCODING="utf-8"

python -m modal run md_app.py::fetch_report --tag prod --outdir "$dir\out"
New-Item -ItemType Directory -Force -Path $out | Out-Null
tar -xzf "$dir\out\prod_report.tar.gz" -C $out

# also bring down the per-system run logs
python -m modal run md_app.py::fetch --tag prod --outdir "$dir\out"
tar -xzf "$dir\out\prod.tar.gz" -C $out

Write-Host "`nResults in: $out" -ForegroundColor Green
Get-ChildItem $out -Recurse -File | Select-Object FullName, Length | Format-Table -AutoSize
Write-Host "`nReport: $out\MD_report.pdf" -ForegroundColor Cyan
