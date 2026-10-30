# =============================================================================
# BLOCK 13 - ANALYSIS, GRAPHS AND PDF REPORT
# =============================================================================
# WHAT THIS DOES
#   Runs on CPU, not GPU. The trajectories stay in the Modal volume; only
#   figures, CSVs and the PDF come down in block 14.
#
#   Produces for all six compounds, on shared axes where comparable:
#     backbone RMSD            is the protein stable
#     ligand RMSD after
#       protein alignment      did the compound stay in the pocket  <- key plot
#     per-residue RMSF         which residues move, catalytic ones marked
#     radius of gyration       is the protein staying folded
#     SASA                     is the pocket closing around the ligand
#     H-bond count vs time     plus a per-residue occupancy table
#     ligand COM distance      from the catalytic centroid, recomputed every
#                              frame from the protein's own atoms
#
#   Then assembles MD_report.pdf with each figure and an explanation of what
#   it means and how to read it.
#
# THREE BUGS THAT HAD TO BE FIXED HERE - all of them silent
#
#   1. Function object is not callable.
#      A Modal @app.function is not directly callable from a local entrypoint.
#      Use analyse.remote(tag), not analyse(tag).
#
#   2. NoDataError: this Universe does not contain charge information.
#      MDAnalysis guesses hydrogen-bond donors and acceptors from partial
#      charges, which a PDB-derived Universe does not carry. Supply
#      donors_sel, hydrogens_sel and acceptors_sel explicitly; that also
#      removes the dependency on bond information.
#
#   3. EVERY LIGAND APPEARED TO LEAVE THE ACTIVE SITE.
#      The first run reported ligand RMSD of 21-49 A and COM distances of
#      24-46 A for all six - including avibactam and clavulanic acid, which
#      simultaneously showed persistent hydrogen bonds to Ser130. A ligand
#      30 A away cannot hydrogen-bond to Ser130, and that contradiction is
#      what exposed the bug.
#
#      Two causes. OpenMM re-centres the solute when it solvates, so the
#      crystal-frame catalytic centroid (8.972, 7.236, 39.252) no longer
#      points at the active site and put a constant offset into every
#      distance. And the trajectory is wrapped, so a ligand crossing the box
#      edge teleported and the RMSD jumped by roughly a box length.
#
#      Fixed by recomputing the centroid each frame from the protein's own
#      catalytic atoms - located by POSITION in the residue list, since
#      OpenMM's PDB writer can drop resid information - and applying the
#      minimum-image convention to every displacement.
#
#      LESSON: cross-check two independent measures before believing either.
# =============================================================================

$dir = "$env:USERPROFILE\Downloads\tem1_md"
Set-Location $dir
$env:PYTHONUTF8="1"; $env:PYTHONIOENCODING="utf-8"

python -m modal run md_app.py::run_analysis --tag prod

# WHAT YOU SHOULD SEE IF IT WORKED
#   analysed Avibactam: 5000 frames
#   ... six lines, 5000 frames each = the full 50 ns at one frame per 10 ps ...
#   wrote /cache/prod_report/MD_report.pdf
#   then one summary row per compound
#
#   SANITY CHECK THE NUMBERS BEFORE TRUSTING THEM:
#     backbone RMSD      0.8-1.5 A      protein stable
#     ligand RMSD        1-6 A          stayed bound
#                        20 A or more   left the site
#     COM distance       3-10 A         in the pocket
#
#   A compound with zero persistent hydrogen bonds AND a large RMSD has
#   genuinely left. A compound with persistent hydrogen bonds to active-site
#   residues AND a large RMSD means the geometry code is broken - the two
#   cannot both be true.
