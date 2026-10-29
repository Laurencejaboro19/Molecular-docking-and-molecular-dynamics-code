# =============================================================================
# BLOCK 3 - FETCH RESULTS AND SAVE THE CSVs TO DOWNLOADS
# =============================================================================
# Results live in the Modal volume until fetched, so this can be run any time
# after the job finishes - hours or days later, from any machine.
# =============================================================================

$dir = "$env:USERPROFILE\Downloads\tem1_vina"
$tag = "run1"
$dl  = "$env:USERPROFILE\Downloads"
Set-Location $dir
$env:PYTHONUTF8="1"; $env:PYTHONIOENCODING="utf-8"

python -m modal run vina_app.py::fetch --tag $tag --outdir "$dir\out"
tar -xzf "$dir\out\$tag.tar.gz" -C "$dir\out"

Copy-Item "$dir\out\$tag\vina_scores.csv"          "$dl\TEM1_AutoDock_Vina_Modal.csv" -Force
Copy-Item "$dir\out\$tag\per_conformer_scores.csv" "$dl\TEM1_AutoDock_Vina_Modal_per_conformer.csv" -Force
Copy-Item "$dir\out\$tag\ligand_verification.csv"  "$dl\TEM1_AutoDock_Vina_Modal_verification.csv" -Force
Copy-Item "$dir\out\$tag\run_metadata.json"        "$dl\TEM1_AutoDock_Vina_Modal_metadata.json" -Force

Write-Host "`nSaved to Downloads:" -ForegroundColor Green
Write-Host "  TEM1_AutoDock_Vina_Modal.csv                 (main results)"
Write-Host "  TEM1_AutoDock_Vina_Modal_per_conformer.csv   (all conformer scores)"
Write-Host "  TEM1_AutoDock_Vina_Modal_verification.csv    (identity checks)"
Write-Host "  TEM1_AutoDock_Vina_Modal_metadata.json       (methods section)`n"

Import-Csv "$dl\TEM1_AutoDock_Vina_Modal.csv" |
    Sort-Object {[double]$_.best_affinity_kcal_mol} |
    Format-Table compound, best_affinity_kcal_mol, ligand_efficiency, heavy_atoms, conformers_docked -AutoSize

Write-Host "For a molecular viewer:" -ForegroundColor Cyan
Write-Host "  receptor : $dir\out\$tag\1BTL_receptor_for_DS.pdb"
Get-ChildItem "$dir\out\$tag\poses_sdf\*_mode1.sdf" | ForEach-Object { Write-Host "  ligand   : $($_.FullName)" }
