# =============================================================================
# BLOCK 2 - STAGE THE FILES AND LAUNCH THE DOCKING
# =============================================================================
# Finds the receptor and the six ligand SDFs anywhere under Downloads, stages
# them, and launches DETACHED so the job survives the PC being switched off.
#
# Ampicillin is deliberately excluded: it is a beta-lactamase SUBSTRATE, not an
# inhibitor, so it does not belong in an inhibitor comparison.
# =============================================================================

$dir = "$env:USERPROFILE\Downloads\tem1_vina"
Set-Location $dir
$env:PYTHONUTF8="1"; $env:PYTHONIOENCODING="utf-8"
New-Item -ItemType Directory -Force -Path "$dir\ligands" | Out-Null
Get-ChildItem "$dir\ligands\*.sdf" -ErrorAction SilentlyContinue | Remove-Item -Force

$need = "BTL-023","BTL-007","BTL-004","Avibactam","Clavulanic_acid","Sulbactam"
$missing = @()

foreach ($n in $need) {
    $hit = Get-ChildItem "$env:USERPROFILE\Downloads" -Recurse -Filter "$n.sdf" `
             -File -ErrorAction SilentlyContinue |
           Where-Object { $_.DirectoryName -ne "$dir\ligands" } |
           Select-Object -First 1
    if ($hit) {
        Copy-Item $hit.FullName "$dir\ligands\$n.sdf" -Force
        Write-Host ("  found {0,-18} <- {1}" -f $n, $hit.DirectoryName) -ForegroundColor Green
    } else {
        $missing += $n
        Write-Host ("  MISSING {0}" -f $n) -ForegroundColor Red
    }
}

$rec = Get-ChildItem "$env:USERPROFILE\Downloads" -Recurse -Filter "1BTL_clean.pdb" `
         -File -ErrorAction SilentlyContinue | Select-Object -First 1
if ($rec) {
    Copy-Item $rec.FullName "$dir\1BTL_clean.pdb" -Force
    Write-Host "  found 1BTL_clean.pdb   <- $($rec.DirectoryName)" -ForegroundColor Green
} else {
    $missing += "1BTL_clean.pdb"
    Write-Host "  MISSING 1BTL_clean.pdb" -ForegroundColor Red
}

if ($missing.Count -gt 0) {
    Write-Host "`nSTOPPING - not launching. Missing: $($missing -join ', ')" -ForegroundColor Red
    return
}

$n = (Get-ChildItem "$dir\ligands\*.sdf").Count
Write-Host "`n$n ligands staged. Launching on Modal (detached)...`n" -ForegroundColor Cyan

python -m modal run --detach vina_app.py::run `
    --pdb "$dir\1BTL_clean.pdb" --ligdir "$dir\ligands" `
    --tag run1 --seed 42 --exhaustiveness 16 --n-poses 9 --nconf 5

# WHAT YOU SHOULD SEE IF IT WORKED
#   uploading 6 ligands: Avibactam, BTL-004, BTL-007, BTL-023, Clavulanic_acid, Sulbactam
#   receptor PDBQT atoms: 2480
#
#   Avibactam: C7H11N3O6S heavy=17/17 charge=0 stereo=2(unassigned 0) conformers=5
#      conformer 0: -7.1
#      ...
#      -> BEST -7.6 (conformer 4); 9 modes written to SDF
#
#   CHECK THE VERIFICATION LINE BEFORE THE SCORES. If heavy= does not match, or
#   unassigned is not 0 on the three clinical inhibitors, stop and investigate -
#   a wrong stereoisomer scores differently from the real drug.
#
#   Rigid bicyclics give fewer than 5 conformers (clavulanate 2, sulbactam 3).
#   That is correct, not a failure - they do not have 5 distinct shapes.
#
# IF IT FAILS
#   "uploading 0 ligands" then KeyError: 'best_affinity_kcal_mol'
#       No SDFs were found, so the results table was empty. Check the staging
#       output above - every compound must print a green "found" line.
