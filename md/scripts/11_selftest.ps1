# =============================================================================
# BLOCK 11 - SELF-TEST: BUILD ONE SYSTEM AND MEASURE GPU SPEED
# =============================================================================
# Builds the image, then builds ONE solvated system from a real docked pose and
# runs 2,000 steps on the GPU. Costs a few cents and takes about 15 minutes
# including the image build.
#
# RUN THIS BEFORE PRODUCTION. It catches missing packages, bad protonation,
# charge errors and CUDA problems before any long run is paid for, and it tells
# you the measured ns/day so the production length is chosen from data.
# =============================================================================

$dir = "$env:USERPROFILE\Downloads\tem1_md"
Set-Location $dir
$env:PYTHONUTF8="1"; $env:PYTHONIOENCODING="utf-8"

# stage the receptor and the six docked poses from the Vina run
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
#   openmm 8.2.x
#   platforms: ['Reference', 'CPU', 'CUDA', 'OpenCL']       <- CUDA must be there
#   built in NNN s
#   {
#     "compound": "selftest",
#     "protonation_state": "tetrazolate",      <- BTL-004 is anionic at pH 7.4
#     "net_charge": -1,
#     "heavy_atoms": 14,
#     "total_atoms": ~31000,
#     "waters": ~9000,
#     ...
#   }
#   2000 steps in NN s  ->  NNN ns/day on L40S
#
#   CHECK protonation_state AND net_charge. Expected at pH 7.4:
#     BTL-004          tetrazolate        -1
#     Avibactam        sulfate/sulfonate  -1
#     Clavulanic_acid  carboxylate        -1
#     Sulbactam        carboxylate        -1
#     BTL-007          neutral             0
#     BTL-023          neutral             0
#
#   Use the measured ns/day to choose the production length:
#     hours for six runs = 6 x (ns wanted) / (ns/day) x 24
#   At roughly $2/hour for an L40S, 300 ns total inside $50 needs ~290 ns/day.
#
# IF IT FAILS
#   CUDA not in the platform list
#       The function did not get a GPU. Check the gpu= setting at the top of
#       md_app.py (MD_GPU, default L40S).
#
#   "Unable to generate parameters for ..." / charge assignment error
#       AmberTools sqm could not run AM1-BCC. Confirm ambertools installed in
#       the image build log.
#
#   heavy atom count changed on protonation
#       The assertion fired - a deprotonation removed a heavy atom. Stop and
#       report it; do not work around it.
