# =============================================================================
# BLOCK 10 - GET THE MD APP ONTO YOUR PC
# =============================================================================
# WHAT THIS DOES
#   Creates Downloads\tem1_md, makes a ligands subfolder, and downloads
#   md_app.py from this repository. Nothing is built or run yet.
#
#   A cache-busting query string is used because raw.githubusercontent.com
#   serves a cached copy for several minutes after a push, and a stale file
#   will silently rebuild the wrong image.
# =============================================================================

$dir = "$env:USERPROFILE\Downloads\tem1_md"
New-Item -ItemType Directory -Force -Path $dir           | Out-Null
New-Item -ItemType Directory -Force -Path "$dir\ligands" | Out-Null
Set-Location $dir
$env:PYTHONUTF8="1"; $env:PYTHONIOENCODING="utf-8"

$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$url = "https://raw.githubusercontent.com/Laurencejaboro19/Molecular-docking-and-molecular-dynamics-code/main/md/modal/md_app.py?nocache=$stamp"
Invoke-WebRequest -Uri $url -OutFile "$dir\md_app.py"

Select-String -Path "$dir\md_app.py" -Pattern 'cuda-version|"openmm"' |
    ForEach-Object { Write-Host "  $($_.Line.Trim())" -ForegroundColor Cyan }

# WHAT YOU SHOULD SEE
#   "openmm", "openff-toolkit=0.18", "openff-interchange=0.5",
#   "cuda-version=12.9", "cuda-nvcc",
#
#   If cuda-version is missing or is not 12.9, the CDN served an old copy.
#   Wait two minutes and run this block again.
