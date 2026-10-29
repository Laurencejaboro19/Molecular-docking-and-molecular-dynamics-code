# =============================================================================
# BLOCK 13 - ANALYSIS, GRAPHS AND PDF REPORT
# =============================================================================
# WHAT THIS DOES
#   Runs on CPU, not GPU - trajectories stay in the cloud and only figures,
#   CSVs and the PDF come down.
#
#   Produces for all six compounds, on shared axes where comparable:
#     backbone RMSD            is the protein stable
#     ligand RMSD after
#       protein alignment      did the compound stay in the pocket  <- key plot
#     per-residue RMSF         which residues move, catalytic ones marked
#     radius of gyration       is the protein staying folded
#     SASA                     is the pocket closing around the ligand
#     H-bond count vs time     plus a per-residue occupancy table
#     ligand COM distance      from the catalytic centroid - bluntest test of
#                              whether the pose survived
#
#   Then assembles everything into MD_report.pdf with a written explanation of
#   what each figure means and how to read it.
#
#   It also answers one specific question: does BTL-004 form persistent
#   hydrogen bonds with Ser130 and Lys234 (the anion-binding pocket), or does
#   it stay on Ser70 only as the docking suggested?
# =============================================================================

$dir = "$env:USERPROFILE\Downloads\tem1_md"
Set-Location $dir
$env:PYTHONUTF8="1"; $env:PYTHONIOENCODING="utf-8"

python -m modal run md_app.py::run_analysis --tag prod

# WHAT YOU SHOULD SEE IF IT WORKED
#   analysed Avibactam: 5000 frames
#   analysed BTL-004: 5000 frames
#   ... six lines ...
#   wrote /cache/prod_report/MD_report.pdf
#   then one summary row per compound
#
#   5000 frames = 50 ns at one frame per 10 ps. A much lower number means the
#   run did not finish.
