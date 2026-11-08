# =============================================================================
# 17 - Pull the 100 ns report, figures, data and tables into Downloads
# =============================================================================
# Run only once `modal volume ls tem1-md prod100_report` shows figures, data
# and tables. A 45-byte tarball means the analysis never wrote anything - go
# back to script 16.
#
# OUTPUT      Downloads\TEM1_100ns\  MD_report.pdf, figures\, data\, tables\
#             Downloads\TEM1_100ns_MD_report.pdf  (loose copy)
# =============================================================================
$dir = "$env:USERPROFILE\Downloads\tem1_md"
$out = "$env:USERPROFILE\Downloads\TEM1_100ns"
$dl  = "$env:USERPROFILE\Downloads"
New-Item -ItemType Directory -Force -Path $out | Out-Null

modal run "$dir\md_app.py::fetch_report" --tag prod100 --outdir "$dir"
$tar = "$dir\prod100_report.tar.gz"
if ((Get-Item $tar).Length -lt 10000) {
    Write-Error "tarball is $((Get-Item $tar).Length) bytes - analysis produced nothing"
    return
}
tar -xzf $tar -C "$out"
Remove-Item $tar -ErrorAction SilentlyContinue
Copy-Item "$out\MD_report.pdf" "$dl\TEM1_100ns_MD_report.pdf" -Force

Get-ChildItem "$out" -Recurse -File |
  Group-Object { Split-Path $_.DirectoryName -Leaf } |
  ForEach-Object { "{0,-12} {1} files" -f $_.Name, $_.Count }
Write-Host "`n--- summary ---" -ForegroundColor Cyan
Get-Content "$out\tables\summary.csv"
Write-Host "`n--- hbond occupancy ---" -ForegroundColor Cyan
Get-Content "$out\tables\hbond_occupancy.csv"
Start-Process $out
