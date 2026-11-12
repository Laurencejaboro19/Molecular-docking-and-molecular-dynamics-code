# 20_fetch_all_reports.ps1 - pull every tag's PDF, figures and tables into its
# own folder under Downloads.
#
# The size guard matters. When the analysis has not finished, fetch_report still
# succeeds and writes a ~45-byte tarball; extracting it silently produces an
# empty folder that looks like a completed download. Anything under 10,000 bytes
# is treated as a failure and reported rather than extracted.
#
# fetch_report is a local entrypoint, so md_app.py must exist locally. It is
# re-downloaded here because Downloads\tem1_md has been deleted once already.
#
# Needs the PC online; takes a couple of minutes.

$dir = "$env:USERPROFILE\Downloads\tem1_md"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Set-Location $dir
$env:PYTHONUTF8 = "1"

$raw = "https://raw.githubusercontent.com/Laurencejaboro19/" +
       "Molecular-docking-and-molecular-dynamics-code/main/md/modal/md_app.py"
Invoke-WebRequest -Uri "$raw`?cb=$(Get-Random)" -OutFile "$dir\md_app.py"

foreach ($tag in @("prod", "prod_r2", "prod100")) {
  $out = "$env:USERPROFILE\Downloads\TEM1_$tag"
  New-Item -ItemType Directory -Force -Path $out | Out-Null
  python -m modal run "$dir\md_app.py::fetch_report" --tag $tag --outdir "$dir"
  $tar = "$dir\$($tag)_report.tar.gz"
  if (-not (Test-Path $tar) -or (Get-Item $tar).Length -lt 10000) {
    Write-Warning "$tag : tarball empty - analysis did not finish, re-run script 19"
    continue
  }
  tar -xzf $tar -C "$out"
  Remove-Item $tar -EA SilentlyContinue
  Write-Host "`n===== $tag =====" -ForegroundColor Cyan
  Get-ChildItem $out -Recurse -Filter *.pdf | Select-Object FullName
  Get-Content "$out\tables\summary.csv" -EA SilentlyContinue
}
Start-Process "$env:USERPROFILE\Downloads"
