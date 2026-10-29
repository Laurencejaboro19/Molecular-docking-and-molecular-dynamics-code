# =============================================================================
# BLOCK 13 - ANALYSIS, GRAPHS AND PDF REPORT
# =============================================================================
# Runs on CPU, not GPU - the trajectories stay in the cloud and only the
# figures, CSVs and PDF come down.
#
# Produces, for all six on shared axes:
#   backbone RMSD, ligand RMSD after protein alignment, per-residue RMSF with
#   the six catalytic residues marked, radius of gyration, SASA, hydrogen-bond
#   count, and ligand centre-of-mass distance from the catalytic centroid.
# Plus a hydrogen-bond occupancy table per compound and a summary table.
# =============================================================================

$dir = "$env:USERPROFILE\Downloads\tem1_md"
Set-Location $dir
$env:PYTHONUTF8="1"; $env:PYTHONIOENCODING="utf-8"

python -m modal run md_app.py::run_analysis --tag prod

# WHAT YOU SHOULD SEE IF IT WORKED
#   analysed Avibactam: 5000 frames
#   analysed BTL-004: 5000 frames
#   ...
#   wrote /cache/prod_report/MD_report.pdf
#   followed by one summary row per compound
