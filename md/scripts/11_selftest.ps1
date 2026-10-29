# =============================================================================
# BLOCK 11 - SELF-TEST: STAGE FILES, BUILD ONE SYSTEM, MEASURE GPU SPEED
# =============================================================================
# WHAT THIS DOES
#   1. Copies the receptor and the six docked poses out of the docking output
#      folder into Downloads\tem1_md.
#   2. Builds the cloud image (first time only, a few minutes).
#   3. Builds ONE solvated system from a real docked pose and runs 2,000 steps
#      on the GPU.
#
# WHY IT EXISTS
#   Production is six GPU containers running for hours. This costs cents and
#   catches missing packages, charge-assignment failures, wrong protonation and
#   CUDA problems before any of that money is spent. Every failure during
#   development was caught here, not in production.
#
#   It also measures ns/day, which is how the production length gets chosen
#   from data rather than from hope.
# =============================================================================

$dir = "$env:USERPROFILE\Downloads\tem1_md"
Set-Location $dir
$env:PYTHONUTF8="1"; $env:PYTHONIOENCODING="utf-8"

$src = "$env:USERPROFILE\Downloads\TEM1_complexes_for_DS"
Copy-Item "$src\1BTL_receptor_for_DS.pdb" "$dir\receptor.pdb" -Force -ErrorAction Stop
Get-ChildItem "$dir\ligands\*.sdf" -ErrorAction SilentlyContinue | Remove-Item -Force
foreach ($n in "BTL-023","BTL-007","BTL-004","Avibactam","Clavulanic_acid","Sulbactam") {
    Copy-Item "$src\$n`_mode1.sdf" "$dir\ligands\$n.sdf" -Force -ErrorAction Stop
}
Write-Host "staged $((Get-ChildItem "$dir\ligands\*.sdf").Count) ligands" -ForegroundColor Green

python -m modal run md_app.py::run_selftest `
    --pdb "$dir\receptor.pdb" --sdf "$dir\ligands\BTL-004.sdf"

# WHAT YOU SHOULD SEE IF IT WORKED
#   openmm 8.6.1...
#   platforms: ['Reference', 'CPU', 'CUDA']        <- CUDA must be present
#   built in ~25 s
#   {
#     "protonation_state": "tetrazolate",          <- BTL-004 is anionic at pH 7.4
#     "net_charge": -1,
#     "heavy_atoms": 14,
#     "total_atoms": ~41900,
#     "waters": ~12500,
#     "ions": 76,
#     "box_nm": [7.63, 7.63, 7.63],
#     ...
#   }
#   2000 steps in 0.5 s  ->  1271 ns/day on L40S (CUDA)
#   potential energy: -560347 kJ/mol
#
#   CHECK protonation_state AND net_charge. Expected at pH 7.4:
#     BTL-004          tetrazolate        -1
#     Avibactam        sulfate/sulfonate  -1
#     Clavulanic_acid  carboxylate        -1
#     Sulbactam        carboxylate        -1
#     BTL-007          neutral             0
#     BTL-023          neutral             0
#
#   The ns/day figure is a SHORT BURST and is optimistic. Sustained production
#   typically lands at a third to two thirds of it.
#
#   If it prints "!! CUDA platform unavailable" and falls back to CPU, STOP.
#   CPU runs at about 12 ns/day for this system - six 50 ns runs would take
#   about 25 days. Fix CUDA before going further.
