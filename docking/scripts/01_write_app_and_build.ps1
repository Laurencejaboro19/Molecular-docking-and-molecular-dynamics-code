# =============================================================================
# BLOCK 1 - WRITE THE MODAL APP AND BUILD THE IMAGE
# =============================================================================
# Copy vina_app.py from this repo into Downloads\tem1_vina, then build the
# cloud image: Debian + Open Babel + RDKit + Meeko + SciPy + the AutoDock Vina
# binary (discovered from the GitHub releases API, so it is never a dead link).
#
# CPU ONLY. AutoDock Vina has no GPU build - AutoDock-GPU and Vina-GPU are
# different programs. Asking Modal for a GPU here would waste money.
# =============================================================================

$dir = "$env:USERPROFILE\Downloads\tem1_vina"
New-Item -ItemType Directory -Force -Path $dir           | Out-Null
New-Item -ItemType Directory -Force -Path "$dir\ligands" | Out-Null

# copy vina_app.py from your clone of this repo into $dir, then:
Set-Location $dir
python -m modal run vina_app.py::setup

# WHAT YOU SHOULD SEE IF IT WORKED
#   => Step 1: RUN python -m pip install gemmi meeko numpy pandas rdkit scipy
#   ...
#   => Step 1: RUN python -c "... AutoDock-Vina/releases/latest ..."
#   downloading https://github.com/forlilab/AutoDock-Vina/releases/download/v1.2.7/vina_1.2.7_linux_x86_64
#   => Step 2: RUN vina --version
#   AutoDock Vina v1.2.7
#   image built; vina binary installed
#
# First build takes 3-6 minutes. Modal caches it, so later runs start in ~20 s.
#
# IF IT FAILS
#   ModuleNotFoundError: No module named 'scipy'
#       Meeko imports scipy. It is in the pip_install list above - if you are
#       adapting an older copy of the app, add it.
