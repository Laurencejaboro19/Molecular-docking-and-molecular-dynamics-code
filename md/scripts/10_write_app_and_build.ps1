# =============================================================================
# BLOCK 10 - WRITE THE MD APP AND BUILD THE GPU IMAGE
# =============================================================================
# Downloads md_app.py from the repo into Downloads\tem1_md and builds the cloud
# image: OpenMM 8.2, OpenFF Toolkit, openmmforcefields, AmberTools (for AM1-BCC
# charges), PDBFixer, RDKit, MDAnalysis, MDTraj, matplotlib and ReportLab.
#
# No GROMACS. OpenMM runs natively on CUDA, so the system is built and
# simulated by the same program - no topology conversion, nothing to validate.
#
# The image is large (conda packages). First build is 8-15 minutes. Modal
# caches it afterwards.
# =============================================================================

$dir = "$env:USERPROFILE\Downloads\tem1_md"
New-Item -ItemType Directory -Force -Path $dir           | Out-Null
New-Item -ItemType Directory -Force -Path "$dir\ligands" | Out-Null
Set-Location $dir
$env:PYTHONUTF8="1"; $env:PYTHONIOENCODING="utf-8"

$url = "https://raw.githubusercontent.com/Laurencejaboro19/Molecular-docking-and-molecular-dynamics-code/main/md/modal/md_app.py"
Invoke-WebRequest -Uri $url -OutFile "$dir\md_app.py"
Write-Host "md_app.py downloaded ($(((Get-Item "$dir\md_app.py").Length)/1kb) kB)" -ForegroundColor Green

# WHAT HAPPENS NEXT
#   Nothing is built until Block 11 runs the self-test, which builds the image
#   and one system. That is deliberate: do not build a GPU image you have not
#   proved works.
