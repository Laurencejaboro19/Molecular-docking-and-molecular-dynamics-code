"""OpenMM molecular dynamics on Modal GPU, starting from AutoDock Vina poses.

Entrypoints: selftest, build, simulate, analyse, fetch.

Design notes
------------
* OpenMM runs natively on CUDA, so no GROMACS conversion is needed.
* Ligands are protonated for pH 7.4: carboxylic acids, sulfate esters and
  tetrazoles are deprotonated; everything else stays neutral. Heavy-atom
  coordinates from the docked pose are never changed.
* Every system uses identical force field, water model, salt, box padding and
  simulation length, so the designed compounds and the clinical inhibitors are
  compared like for like.
"""
import io, json, os, tarfile, time
import modal

GPU = os.environ.get("MD_GPU", "L40S")

# ---- BUDGET CAP -----------------------------------------------------------
# Modal has no dollar cap in code; the only lever is wall-clock timeout. The
# ceiling below is derived from a budget so there is one number to change.
# This is ARITHMETIC, not an enforced limit - set a spending limit in the
# Modal workspace settings as well, which is billing-level and real.
BUDGET_USD = 70.0            # total spend ceiling for the whole run
USD_PER_GPU_HOUR = 2.10      # L40S rate - check Modal pricing and correct it
N_SYSTEMS = 6                # containers running in parallel
MAX_SECONDS = int(BUDGET_USD / (USD_PER_GPU_HOUR * N_SYSTEMS) * 3600)   # ~5.5 h

image = (
    modal.Image.micromamba(python_version="3.11")
    .micromamba_install(
        # version set proven to build these systems together; openff-interchange
        # must be >=0.5 because 0.4.x predates pydantic 2 and fails on import
        "openmm", "openff-toolkit=0.18", "openff-interchange=0.5",
        "openmmforcefields=0.16", "ambertools", "pdbfixer", "rdkit",
        "mdanalysis", "mdtraj", "parmed", "matplotlib", "pandas", "scipy",
        "reportlab", "importlib_resources", "importlib_metadata",
        # CUDA 12.9 is the LOWEST that openmm >= 8.5.1 accepts on py3.11
        # (openmmforcefields 0.16 forces that openmm floor). Left unpinned the
        # solver takes CUDA 13, whose PTX the L40S driver refuses with
        # CUDA_ERROR_UNSUPPORTED_PTX_VERSION. nvcc is kept so OpenMM can also
        # compile kernels at runtime for the GPU actually present.
        "cuda-version=12.9", "cuda-nvcc",
        channels=["conda-forge"])
    .env({"OPENMM_CUDA_COMPILER": "/opt/conda/bin/nvcc"})
)
vol = modal.Volume.from_name("tem1-md", create_if_missing=True)
app = modal.App("tem1-md", image=image)

CATALYTIC = {70: "SER", 73: "LYS", 130: "SER", 132: "ASN", 166: "GLU", 234: "LYS"}
CENTROID = (8.972, 7.236, 39.252)          # catalytic centroid, Angstrom
PAD_NM, SALT_M, TEMP_K, PRESS_BAR = 1.0, 0.15, 300.0, 1.0


# --------------------------------------------------------------------------
# pH 7.4 protonation
# --------------------------------------------------------------------------
ACIDS = [("carboxylate",       "[CX3](=[OX1])[OX2;H1]",              2),
         ("sulfate/sulfonate", "[SX4](=[OX1])(=[OX1])[OX2;H1]",      3),
         ("phosphate",         "[PX4](=[OX1])[OX2;H1]",              2)]


def deprotonate_ph74(mol):
    """Return (mol, label). Heavy atoms and stereochemistry are preserved."""
    from rdkit import Chem
    m = Chem.RWMol(mol); hit = None
    for label, sma, idx in ACIDS:
        for match in m.GetSubstructMatches(Chem.MolFromSmarts(sma)):
            a = m.GetAtomWithIdx(match[idx])
            if a.GetTotalNumHs() == 0:
                continue
            a.SetNumExplicitHs(0); a.SetNoImplicit(True); a.SetFormalCharge(-1)
            hit = label; break
        if hit:
            break
    if hit is None:                      # tetrazole (pKa ~4.9); triazole is NOT touched
        for ring in m.GetRingInfo().AtomRings():
            if len(ring) != 5:
                continue
            ats = [m.GetAtomWithIdx(i) for i in ring]
            if not all(a.GetIsAromatic() for a in ats):
                continue
            ns = [a for a in ats if a.GetSymbol() == "N"]
            if len(ns) != 4:
                continue
            nh = [a for a in ns if a.GetTotalNumHs() == 1]
            if not nh:
                continue
            nh[0].SetNumExplicitHs(0); nh[0].SetNoImplicit(True)
            nh[0].SetFormalCharge(-1)
            hit = "tetrazolate"; break
    out = m.GetMol(); Chem.SanitizeMol(out)
    return out, (hit or "neutral")


# --------------------------------------------------------------------------
# system construction
# --------------------------------------------------------------------------
def _build(name, sdf_text, pdb_text, workdir):
    from rdkit import Chem
    from rdkit.Chem import inchi
    from openff.toolkit import Molecule
    from openmmforcefields.generators import SMIRNOFFTemplateGenerator
    from openmm import app, unit, LangevinMiddleIntegrator
    import openmm
    from pdbfixer import PDBFixer

    os.makedirs(workdir, exist_ok=True)

    # --- ligand: docked pose -> pH 7.4 form -------------------------------
    rd = Chem.MolFromMolBlock(sdf_text, removeHs=False)
    Chem.AssignStereochemistryFrom3D(rd)
    key_in = inchi.MolToInchiKey(Chem.RemoveHs(rd))
    heavy_in = Chem.RemoveHs(rd).GetNumHeavyAtoms()
    rd_h, state = deprotonate_ph74(Chem.RemoveHs(rd))
    charge = Chem.GetFormalCharge(rd_h)
    heavy_out = rd_h.GetNumHeavyAtoms()
    assert heavy_out == heavy_in, f"{name}: heavy atom count changed on protonation"
    rd_h = Chem.AddHs(rd_h, addCoords=True)

    off = Molecule.from_rdkit(rd_h, allow_undefined_stereo=False)
    off.assign_partial_charges(partial_charge_method="am1bcc")   # AmberTools sqm

    # --- receptor ---------------------------------------------------------
    rec_path = os.path.join(workdir, "_rec.pdb")
    open(rec_path, "w").write(pdb_text)
    fixer = PDBFixer(filename=rec_path)
    fixer.findMissingResidues(); fixer.missingResidues = {}
    fixer.findMissingAtoms(); fixer.addMissingAtoms()
    fixer.addMissingHydrogens(7.4)

    # --- combine, solvate -------------------------------------------------
    gen = SMIRNOFFTemplateGenerator(molecules=[off], forcefield="openff-2.1.0")
    ff = app.ForceField("amber14-all.xml", "amber14/tip3p.xml")
    ff.registerTemplateGenerator(gen.generator)

    lig_top = off.to_topology().to_openmm()
    lig_pos = off.conformers[0].to_openmm()

    mod = app.Modeller(fixer.topology, fixer.positions)
    mod.add(lig_top, lig_pos)
    n_solute = mod.topology.getNumAtoms()
    mod.addSolvent(ff, model="tip3p", padding=PAD_NM * unit.nanometer,
                   ionicStrength=SALT_M * unit.molar, neutralize=True)

    system = ff.createSystem(mod.topology, nonbondedMethod=app.PME,
                             nonbondedCutoff=1.0 * unit.nanometer,
                             constraints=app.HBonds, rigidWater=True,
                             hydrogenMass=1.5 * unit.amu)

    with open(os.path.join(workdir, "system.xml"), "w") as fh:
        fh.write(openmm.XmlSerializer.serialize(system))
    app.PDBFile.writeFile(mod.topology, mod.positions,
                          open(os.path.join(workdir, "start.pdb"), "w"), keepIds=True)

    box = mod.topology.getUnitCellDimensions().value_in_unit(unit.nanometer)
    nwat = sum(1 for r in mod.topology.residues() if r.name in ("HOH", "WAT"))
    nion = sum(1 for r in mod.topology.residues() if r.name in ("NA", "CL"))
    meta = {"compound": name, "protonation_state": state, "net_charge": charge,
            "heavy_atoms": heavy_out, "inchikey_input": key_in,
            "total_atoms": mod.topology.getNumAtoms(), "solute_atoms": n_solute,
            "waters": nwat, "ions": nion,
            "box_nm": [round(float(b), 4) for b in box],
            "forcefield": "amber14SB + OpenFF Sage 2.1.0, AM1-BCC, TIP3P",
            "salt_M": SALT_M, "hydrogen_mass_amu": 1.5}
    json.dump(meta, open(os.path.join(workdir, "build.json"), "w"), indent=2)
    return meta


@app.function(gpu=GPU, volumes={"/cache": vol}, timeout=3600)
def selftest(pdb_text: str, sdf_text: str, name: str = "selftest"):
    """Build ONE system and run 2000 steps. Catches install and chemistry
    problems for a few cents before any production GPU time is spent."""
    import openmm
    from openmm import app, unit, LangevinMiddleIntegrator
    import subprocess as _sp
    print("openmm", openmm.version.version, flush=True)
    print("platforms:", [openmm.Platform.getPlatform(i).getName()
                         for i in range(openmm.Platform.getNumPlatforms())], flush=True)
    try:
        print(_sp.run(["nvidia-smi",
                       "--query-gpu=name,driver_version,compute_cap",
                       "--format=csv,noheader"],
                      text=True, capture_output=True).stdout.strip(), flush=True)
    except Exception as _e:
        print("nvidia-smi unavailable:", _e, flush=True)
    print("OPENMM_CUDA_COMPILER =", os.environ.get("OPENMM_CUDA_COMPILER"), flush=True)
    print("nvcc present:", os.path.exists("/opt/conda/bin/nvcc"), flush=True)
    wd = f"/cache/_selftest/{name}"
    t0 = time.time()
    meta = _build(name, sdf_text, pdb_text, wd)
    print("built in %.0f s" % (time.time() - t0), flush=True)
    print(json.dumps(meta, indent=2), flush=True)

    system = openmm.XmlSerializer.deserialize(open(f"{wd}/system.xml").read())
    pdb = app.PDBFile(f"{wd}/start.pdb")
    integ = LangevinMiddleIntegrator(TEMP_K * unit.kelvin, 1 / unit.picosecond,
                                     0.004 * unit.picoseconds)
    try:
        sim = app.Simulation(pdb.topology, system, integ,
                             openmm.Platform.getPlatformByName("CUDA"),
                             {"Precision": "mixed"})
        plat = "CUDA"
    except Exception as e:
        print("!! CUDA platform unavailable:", e, flush=True)
        print("!! falling back to CPU for the self-test only - do NOT run "
              "production until CUDA works", flush=True)
        sim = app.Simulation(pdb.topology, system, integ,
                             openmm.Platform.getPlatformByName("CPU"))
        plat = "CPU"
    sim.context.setPositions(pdb.positions)
    sim.minimizeEnergy(maxIterations=500)
    sim.context.setVelocitiesToTemperature(TEMP_K * unit.kelvin)
    t0 = time.time(); sim.step(2000); dt = time.time() - t0
    ns_per_day = (2000 * 0.004 / 1000) / (dt / 86400)
    st = sim.context.getState(getEnergy=True)
    print(f"\n2000 steps in {dt:.1f} s  ->  {ns_per_day:.0f} ns/day on {GPU} ({plat})", flush=True)
    print("potential energy:", st.getPotentialEnergy(), flush=True)
    vol.commit()
    return {"meta": meta, "ns_per_day": round(ns_per_day), "gpu": GPU, "platform": plat}


@app.function(gpu=GPU, volumes={"/cache": vol}, timeout=MAX_SECONDS)
def simulate(name: str, sdf_text: str, pdb_text: str, tag: str = "prod",
             ns: float = 50.0, equil_ns: float = 1.1):
    """Build, minimise, equilibrate (NVT then staged-restraint NPT), produce."""
    import numpy as np, openmm
    from openmm import app, unit, LangevinMiddleIntegrator, MonteCarloBarostat
    from openmm import CustomExternalForce

    wd = f"/cache/{tag}/{name}"
    meta = _build(name, sdf_text, pdb_text, wd)
    print(f"[{name}] {meta['total_atoms']} atoms, charge {meta['net_charge']}, "
          f"{meta['protonation_state']}", flush=True)

    system = openmm.XmlSerializer.deserialize(open(f"{wd}/system.xml").read())
    pdb = app.PDBFile(f"{wd}/start.pdb")
    top, pos = pdb.topology, pdb.positions

    # positional restraints on solute heavy atoms, released in stages
    rest = CustomExternalForce("k*periodicdistance(x,y,z,x0,y0,z0)^2")
    rest.addGlobalParameter("k", 1000.0 * unit.kilojoules_per_mole / unit.nanometer**2)
    for p in ("x0", "y0", "z0"):
        rest.addPerParticleParameter(p)
    solute = []
    for a in top.atoms():
        if a.residue.name in ("HOH", "WAT", "NA", "CL"):
            continue
        if a.element is not None and a.element.symbol != "H":
            rest.addParticle(a.index, pos[a.index].value_in_unit(unit.nanometer))
            solute.append(a.index)
    ri = system.addForce(rest)
    print(f"[{name}] restrained solute heavy atoms: {len(solute)}", flush=True)

    integ = LangevinMiddleIntegrator(TEMP_K * unit.kelvin, 1 / unit.picosecond,
                                     0.004 * unit.picoseconds)
    sim = app.Simulation(top, system, integ,
                         openmm.Platform.getPlatformByName("CUDA"),
                         {"Precision": "mixed"})
    sim.context.setPositions(pos)

    print(f"[{name}] minimising", flush=True)
    sim.minimizeEnergy()
    sim.reporters.append(app.StateDataReporter(
        f"{wd}/equil.csv", 500, step=True, time=True, temperature=True,
        potentialEnergy=True, density=True, volume=True, speed=True))

    # NVT 100 ps, fully restrained
    sim.context.setVelocitiesToTemperature(TEMP_K * unit.kelvin)
    sim.step(int(100 / 0.004))
    print(f"[{name}] NVT done", flush=True)

    # NPT 5 x 200 ps, restraints 1000 -> 0
    system.addForce(MonteCarloBarostat(PRESS_BAR * unit.bar, TEMP_K * unit.kelvin, 25))
    sim.context.reinitialize(preserveState=True)
    for k in (500.0, 200.0, 100.0, 50.0, 0.0):
        sim.context.setParameter("k", k * unit.kilojoules_per_mole / unit.nanometer**2)
        sim.step(int(200 / 0.004))
        print(f"[{name}] NPT stage k={k:.0f} done", flush=True)
    sim.reporters.clear()

    # production
    nsteps = int(ns * 1000 / 0.004)
    sim.reporters.append(app.DCDReporter(f"{wd}/traj.dcd", 2500))        # 10 ps
    sim.reporters.append(app.StateDataReporter(
        f"{wd}/prod.csv", 2500, step=True, time=True, temperature=True,
        potentialEnergy=True, totalEnergy=True, density=True, volume=True,
        speed=True, remainingTime=True, totalSteps=nsteps))
    sim.reporters.append(app.CheckpointReporter(f"{wd}/state.chk", 25000))
    print(f"[{name}] production {ns} ns ({nsteps} steps)", flush=True)
    t0 = time.time()
    # step in 1 ns chunks so the run can stop itself before the container is
    # killed. A killed container loses its trajectory entirely, because the
    # volume is only committed at the end.
    chunk = int(1000 / 0.004)
    done = 0
    while done < nsteps:
        this = min(chunk, nsteps - done)
        sim.step(this)
        done += this
        if time.time() - t0 > MAX_SECONDS - 600:
            print(f"[{name}] BUDGET STOP at {done * 0.004 / 1000:.1f} ns "
                  f"of {ns} ns requested", flush=True)
            break
    wall = time.time() - t0
    ns = round(done * 0.004 / 1000, 2)
    meta.update({"production_ns": ns, "wall_seconds": round(wall),
                 "ns_per_day": round(ns / (wall / 86400), 1),
                 "frame_interval_ps": 10})
    json.dump(meta, open(f"{wd}/build.json", "w"), indent=2)
    vol.commit()
    print(f"[{name}] done in {wall/3600:.2f} h", flush=True)
    return meta


@app.function(volumes={"/cache": vol}, timeout=1800)
def pack(tag: str) -> bytes:
    vol.reload()
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as t:
        for root, _, files in os.walk(f"/cache/{tag}"):
            for f in files:
                if f.endswith((".dcd", ".chk", ".xml")):
                    continue                   # trajectories stay in the cloud
                p = os.path.join(root, f)
                t.add(p, arcname=os.path.relpath(p, f"/cache/{tag}"))
    return buf.getvalue()


import numpy as np


CAT_LABEL = {70: "Ser70", 73: "Lys73", 130: "Ser130",
             132: "Asn132", 166: "Glu166", 234: "Lys234"}
CENT = (8.972, 7.236, 39.252)
COLORS = {"BTL-023": "#d1495b", "BTL-007": "#edae49", "BTL-004": "#00798c",
          "Avibactam": "#2e4057", "Clavulanic_acid": "#8d96a3",
          "Sulbactam": "#66a182"}

EXPLAIN = {
 "backbone_rmsd": (
   "Protein backbone RMSD",
   "How far the protein backbone has moved from its starting structure at each "
   "point in the run. It should rise over the first few nanoseconds and then "
   "flatten. A plateau around 1-3 A means the enzyme is stable and everything "
   "downstream can be trusted. A line still climbing at the end means the "
   "system never equilibrated."),
 "ligand_rmsd": (
   "Ligand RMSD after alignment on the protein",
   "The most important plot here. The protein is superposed frame by frame, so "
   "this measures how far the compound moved RELATIVE TO THE POCKET. Low and "
   "flat means it stayed where it was docked. A step change means it slid or "
   "flipped into a different pose. A steady climb means it left the site. "
   "Backbone RMSD alone cannot tell you any of this."),
 "rmsf": (
   "Per-residue RMSF",
   "Average fluctuation of each residue over the run. Loops are flexible and "
   "spike; the core is rigid and low. The six catalytic residues are marked. "
   "If a catalytic residue is less mobile with one compound bound than with "
   "another, that compound is holding the site more rigidly."),
 "rgyr": (
   "Radius of gyration",
   "How compact the protein is. It should be an essentially flat line. A rising "
   "trend would indicate unfolding, which for a 50 ns run at 300 K would point "
   "to a setup problem rather than real biology."),
 "sasa": (
   "Solvent-accessible surface area",
   "How much of the protein surface is exposed to water. Also expected to be "
   "flat. A modest drop can reflect the pocket closing around the ligand."),
 "hbonds": (
   "Protein-ligand hydrogen bonds over time",
   "The number of hydrogen bonds between the compound and the enzyme at each "
   "frame. The running count is noisy by nature; the occupancy table that "
   "follows is the quantitative version and is what belongs in a manuscript."),
 "com_dist": (
   "Ligand distance from the catalytic centroid",
   "Straight-line distance from the compound's centre of mass to the centroid "
   "of the six catalytic atoms (Ser70 OG, Lys73 NZ, Ser130 OG, Asn132 ND2, "
   "Glu166 OE1, Lys234 NZ), recomputed every frame from the protein itself and "
   "measured with the minimum-image convention so a ligand crossing the "
   "periodic boundary is not counted as having left. Flat and small means "
   "bound; a rise means the compound is leaving. This is the bluntest and "
   "hardest-to-misread measure of whether a pose survived."),
}


def _plot(ax, title, xlabel, ylabel):
    ax.set_title(title, fontsize=11, fontweight="bold")
    ax.set_xlabel(xlabel, fontsize=9); ax.set_ylabel(ylabel, fontsize=9)
    ax.tick_params(labelsize=8); ax.grid(alpha=.25, linewidth=.5)
    ax.legend(fontsize=7, frameon=False)



def _catalytic_atoms(prot):
    """The six catalytic functional atoms, found by POSITION in the residue
    list rather than by resid, because OpenMM's PDB writer can lose resid
    information. Index = Ambler number - 26 for the 263-residue mature TEM-1.
    """
    want = [(44, "OG"), (47, "NZ"), (104, "OG"),
            (106, "ND2"), (140, "OE1"), (208, "NZ")]
    res = prot.residues
    idx = []
    for i, nm in want:
        if i < len(res):
            a = res[i].atoms.select_atoms(f"name {nm}")
            if len(a):
                idx.append(a[0].index)
    return prot.universe.atoms[idx] if len(idx) >= 4 else None


def _minimum_image(d, box):
    """Shortest periodic displacement, orthorhombic box."""
    return d - box * np.round(d / box)


def analyse_all(root, outdir):
    """root: /cache/<tag> holding one subdirectory per compound."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import pandas as pd
    import MDAnalysis as mda
    from MDAnalysis.analysis import rms, align
    from MDAnalysis.analysis.hydrogenbonds import HydrogenBondAnalysis
    import mdtraj as md

    for sub in ("figures", "data", "tables"):
        os.makedirs(os.path.join(outdir, sub), exist_ok=True)

    names = sorted(d for d in os.listdir(root)
                   if os.path.isdir(os.path.join(root, d))
                   and os.path.exists(os.path.join(root, d, "traj.dcd")))
    series, summary, occupancy = {}, [], {}

    for name in names:
        d = os.path.join(root, name)
        meta = json.load(open(os.path.join(d, "build.json")))
        u = mda.Universe(os.path.join(d, "start.pdb"), os.path.join(d, "traj.dcd"))
        prot = u.select_atoms("protein")
        lig = u.select_atoms("resname UNK UNL LIG MOL and not name H*")
        if len(lig) == 0:                       # fall back: non-protein, non-solvent
            lig = u.select_atoms("not protein and not resname HOH WAT NA CL and not name H*")
        t_ns = np.array([ts.time / 1000.0 for ts in u.trajectory])

        # ------------------------------------------------------------------
        # Geometry pass, periodic-aware.
        #
        # Two things make a naive calculation wrong here. OpenMM re-centres the
        # solute when it solvates, so the crystal-frame catalytic centroid no
        # longer points at the active site - it must be recomputed per frame
        # from the protein's own atoms. And the trajectory is wrapped, so a
        # ligand crossing the box edge teleports; every displacement therefore
        # needs the minimum-image convention applied.
        # ------------------------------------------------------------------
        bb = prot.select_atoms("backbone")
        cat = _catalytic_atoms(prot)
        if cat is None:
            print(f"  !! {name}: catalytic atoms not found, "
                  f"falling back to protein centre", flush=True)

        u.trajectory[0]
        box0 = u.dimensions[:3].copy()
        bb_com0 = bb.center_of_mass()
        bb_ref = bb.positions - bb_com0
        pocket0 = cat.positions.mean(axis=0) if cat is not None else prot.center_of_mass()
        d0 = _minimum_image(lig.positions - pocket0, box0)
        lig_ref = (pocket0 + d0) - bb_com0

        bb_rmsd, lig_rmsd, com_d = [], [], []
        for ts in u.trajectory:
            box = u.dimensions[:3]
            bb_com = bb.center_of_mass()
            cur = bb.positions - bb_com
            Rm, _ = align.rotation_matrix(cur, bb_ref)
            bb_rmsd.append(float(np.sqrt(((cur @ Rm.T - bb_ref) ** 2).sum(axis=1).mean())))

            pocket = cat.positions.mean(axis=0) if cat is not None else prot.center_of_mass()
            dl = _minimum_image(lig.positions - pocket, box)
            lig_local = (pocket + dl) - bb_com
            lig_now = lig_local @ Rm.T
            lig_rmsd.append(float(np.sqrt(((lig_now - lig_ref) ** 2).sum(axis=1).mean())))

            dcom = _minimum_image(lig.center_of_mass() - pocket, box)
            com_d.append(float(np.linalg.norm(dcom)))

        bb_rmsd = np.array(bb_rmsd)
        lig_rmsd = np.array(lig_rmsd)
        com_d = np.array(com_d)

        align.AlignTraj(u, u, select="backbone", in_memory=True).run()
        rmsf = rms.RMSF(prot.select_atoms("name CA")).run().results.rmsf
        resids = prot.select_atoms("name CA").resids
        if len(set(resids)) < 50:          # PDB lost resid info; restore Ambler numbering
            resids = np.arange(len(resids)) + 26

        t = md.load(os.path.join(d, "traj.dcd"), top=os.path.join(d, "start.pdb"))
        pi = t.topology.select("protein")
        tp = t.atom_slice(pi)
        rg = md.compute_rg(tp) * 10.0
        sasa = md.shrake_rupley(tp, mode="residue").sum(axis=1) * 100.0

        # Donors/acceptors must be given explicitly: a PDB-derived Universe has
        # no partial charges, so MDAnalysis cannot guess them, and giving the
        # selections also removes the need for bond information.
        nonsolv = "not resname HOH WAT SOL NA CL NA+ CL-"
        hba = HydrogenBondAnalysis(
            universe=u,
            donors_sel=f"({nonsolv}) and (name N* or name O*)",
            hydrogens_sel=f"({nonsolv}) and name H*",
            acceptors_sel=f"({nonsolv}) and (name N* or name O*)",
            between=["protein", f"not protein and {nonsolv}"],
            d_a_cutoff=3.5, d_h_a_angle_cutoff=150)
        hba.run()
        hb_count = hba.count_by_time()
        occ = {}
        nframes = len(u.trajectory)
        for a_ix, d_ix, h_ix, cnt in _hb_pairs(hba, u):
            occ[a_ix] = occ.get(a_ix, 0) + cnt
        occupancy[name] = sorted(
            [(k, 100.0 * v / nframes) for k, v in occ.items()],
            key=lambda x: -x[1])[:12]

        series[name] = {"t": t_ns, "backbone_rmsd": bb_rmsd, "ligand_rmsd": lig_rmsd,
                        "rmsf": (resids, rmsf), "rgyr": rg, "sasa": sasa,
                        "hbonds": hb_count, "com_dist": com_d}
        persistent = [r for r, o in occupancy[name] if o >= 30]
        summary.append({
            "compound": name, "protonation": meta.get("protonation_state"),
            "net_charge": meta.get("net_charge"),
            "production_ns": meta.get("production_ns"),
            "total_atoms": meta.get("total_atoms"),
            "mean_backbone_rmsd_A": round(float(bb_rmsd[len(bb_rmsd)//2:].mean()), 2),
            "mean_ligand_rmsd_A": round(float(lig_rmsd[len(lig_rmsd)//2:].mean()), 2),
            "mean_com_distance_A": round(float(com_d[len(com_d)//2:].mean()), 2),
            "hbonds_above_30pc": len(persistent),
            "persistent_residues": "; ".join(persistent)})
        print(f"analysed {name}: {len(u.trajectory)} frames", flush=True)

    _write_outputs(series, summary, occupancy, outdir, plt, pd)
    return summary


def _hb_pairs(hba, u):
    """Yield (residue label, donor ix, hydrogen ix, count) per protein residue."""
    res = hba.results.hbonds
    if len(res) == 0:
        return []
    out = {}
    for row in res:
        for ix in (int(row[1]), int(row[3])):
            at = u.atoms[ix]
            if at.segid and at.resname not in ("HOH", "WAT", "NA", "CL"):
                if at.resname in ("UNK", "UNL", "LIG", "MOL"):
                    continue
                lab = f"{at.resname}{at.resid}"
                out[lab] = out.get(lab, 0) + 1
    return [(k, None, None, v) for k, v in out.items()]


def _write_outputs(series, summary, occupancy, outdir, plt, pd):
    import matplotlib.pyplot as _p
    figs = []
    panels = [("backbone_rmsd", "Time (ns)", "RMSD (A)"),
              ("ligand_rmsd",   "Time (ns)", "Ligand RMSD (A)"),
              ("rgyr",          "Time (ns)", "Rg (A)"),
              ("sasa",          "Time (ns)", "SASA (A^2)"),
              ("hbonds",        "Time (ns)", "H-bonds"),
              ("com_dist",      "Time (ns)", "Distance (A)")]
    for key, xl, yl in panels:
        fig, ax = plt.subplots(figsize=(7.2, 4.0), dpi=300)
        rows = {}
        for name, s in series.items():
            y = s[key]; t = s["t"][:len(y)]
            ax.plot(t, y, lw=1.0, label=name, color=COLORS.get(name))
            rows[name] = pd.Series(y, index=np.round(t, 3))
        _plot(ax, EXPLAIN[key][0], xl, yl)
        p = os.path.join(outdir, "figures", f"{key}.png")
        fig.tight_layout(); fig.savefig(p); plt.close(fig); figs.append((key, p))
        df = pd.DataFrame(rows); df.index.name = "time_ns"
        df.to_csv(os.path.join(outdir, "data", f"{key}.csv"))

    fig, ax = plt.subplots(figsize=(7.2, 4.0), dpi=300)
    for name, s in series.items():
        resids, rmsf = s["rmsf"]
        ax.plot(resids, rmsf, lw=.9, label=name, color=COLORS.get(name))
    for rid, lab in CAT_LABEL.items():
        ax.axvline(rid, color="k", lw=.5, ls=":", alpha=.6)
        ax.annotate(lab, (rid, ax.get_ylim()[1]), rotation=90, fontsize=6,
                    va="top", ha="right")
    _plot(ax, EXPLAIN["rmsf"][0], "Residue number", "RMSF (A)")
    p = os.path.join(outdir, "figures", "rmsf.png")
    fig.tight_layout(); fig.savefig(p); plt.close(fig)
    figs.insert(2, ("rmsf", p))
    pd.DataFrame({n: pd.Series(s["rmsf"][1], index=s["rmsf"][0])
                  for n, s in series.items()}).to_csv(
        os.path.join(outdir, "data", "rmsf.csv"), index_label="resid")

    sm = pd.DataFrame(summary)
    sm.to_csv(os.path.join(outdir, "tables", "summary.csv"), index=False)
    occ_rows = [{"compound": n, "residue": r, "occupancy_pc": round(o, 1)}
                for n, lst in occupancy.items() for r, o in lst]
    pd.DataFrame(occ_rows).to_csv(
        os.path.join(outdir, "tables", "hbond_occupancy.csv"), index=False)
    _pdf(figs, sm, occupancy, outdir)


def _pdf(figs, summary_df, occupancy, outdir):
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.units import mm
    from reportlab.lib import colors
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Image,
                                    Table, TableStyle, PageBreak)
    ss = getSampleStyleSheet()
    body = ParagraphStyle("b", parent=ss["BodyText"], fontSize=9.5, leading=13)
    cap = ParagraphStyle("c", parent=ss["BodyText"], fontSize=8, leading=10.5,
                         textColor=colors.HexColor("#555555"))
    doc = SimpleDocTemplate(os.path.join(outdir, "MD_report.pdf"), pagesize=A4,
                            leftMargin=18*mm, rightMargin=18*mm,
                            topMargin=16*mm, bottomMargin=16*mm)
    F = [Paragraph("Molecular dynamics of TEM-1 &beta;-lactamase with six ligands",
                   ss["Title"]),
         Paragraph("OpenMM, Amber ff14SB + OpenFF Sage 2.1.0, AM1-BCC charges, "
                   "TIP3P water, 0.15 M NaCl, 300 K, 1 bar, 4 fs timestep with "
                   "hydrogen mass repartitioning. Ligands protonated for pH 7.4. "
                   "Starting poses are the top-scoring AutoDock Vina poses, "
                   "unchanged.", body),
         Spacer(1, 6*mm), Paragraph("Run summary", ss["Heading2"])]

    cols = ["compound", "protonation", "net_charge", "production_ns",
            "mean_backbone_rmsd_A", "mean_ligand_rmsd_A",
            "mean_com_distance_A", "hbonds_above_30pc"]
    data = [["Compound", "Protonation", "Charge", "ns",
             "BB RMSD", "Lig RMSD", "COM dist", "H-bonds >30%"]]
    for _, r in summary_df.iterrows():
        data.append([str(r[c]) for c in cols])
    t = Table(data, hAlign="LEFT")
    t.setStyle(TableStyle([
        ("FONTSIZE", (0, 0), (-1, -1), 7.5),
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e8e8e8")),
        ("GRID", (0, 0), (-1, -1), .4, colors.HexColor("#999999")),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ("TOPPADDING", (0, 0), (-1, -1), 3)]))
    F += [t, Spacer(1, 4*mm),
          Paragraph("Mean values are taken over the second half of each run, "
                    "after equilibration. 'COM dist' is the ligand centre of "
                    "mass to the catalytic centroid.", cap), PageBreak()]

    for i, (key, path) in enumerate(figs, start=1):
        title, text = EXPLAIN[key]
        F += [Paragraph(f"Figure {i}. {title}", ss["Heading2"]),
              Image(path, width=165*mm, height=92*mm),
              Paragraph(f"File: figures/{os.path.basename(path)}", cap),
              Spacer(1, 3*mm), Paragraph(text, body), PageBreak()]

    F.append(Paragraph("Hydrogen-bond occupancy", ss["Heading2"]))
    F.append(Paragraph(
        "Percentage of production frames in which each protein residue formed a "
        "hydrogen bond with the compound (donor-acceptor &le; 3.5 &Aring;, "
        "D-H&middot;&middot;&middot;A angle &ge; 150&deg;). A bond above about "
        "30% is a persistent interaction worth describing; a few per cent is "
        "noise.", body))
    F.append(Spacer(1, 4*mm))
    for name, lst in occupancy.items():
        rows = [["Residue", "Occupancy (%)"]] + [[r, f"{o:.1f}"] for r, o in lst]
        tt = Table(rows, hAlign="LEFT", colWidths=[40*mm, 30*mm])
        tt.setStyle(TableStyle([
            ("FONTSIZE", (0, 0), (-1, -1), 7.5),
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e8e8e8")),
            ("GRID", (0, 0), (-1, -1), .4, colors.HexColor("#999999"))]))
        F += [Paragraph(f"<b>{name}</b>", body), tt, Spacer(1, 4*mm)]

    F += [PageBreak(), Paragraph("Limitations", ss["Heading2"]),
          Paragraph(
            "<b>Non-covalent treatment of the clinical inhibitors.</b> Avibactam, "
            "clavulanic acid and sulbactam inhibit TEM-1 by covalent acylation of "
            "Ser70. Classical MD cannot form or break that bond, so their "
            "simulated residence times understate reality. They are included as "
            "non-covalent binders so that the comparison with the designed "
            "compounds is like for like.<br/><br/>"
            "<b>Single replicate.</b> One trajectory per compound. Differences "
            "between compounds that are small relative to the fluctuation within "
            "a single run should not be over-interpreted.<br/><br/>"
            "<b>Protonation.</b> States were assigned for pH 7.4 by functional "
            "group: carboxylic acids, sulfate esters and tetrazoles deprotonated, "
            "everything else neutral. No constant-pH simulation was performed.<br/><br/>"
            "<b>Binding free energy.</b> MM-PBSA / MM-GBSA was not computed in "
            "this run.", body)]
    doc.build(F)
    print("wrote", os.path.join(outdir, "MD_report.pdf"), flush=True)


# ==========================================================================
# analysis and report  (runs on CPU - no GPU needed)
# ==========================================================================
@app.function(cpu=8, volumes={"/cache": vol}, timeout=7200)
def analyse(tag: str = "prod"):
    import numpy as np
    root = f"/cache/{tag}"
    out = f"/cache/{tag}_report"
    os.makedirs(out, exist_ok=True)
    s = analyse_all(root, out)
    vol.commit()
    return s


@app.local_entrypoint()
def run_analysis(tag: str = "prod"):
    for row in analyse.remote(tag):
        print(row)


@app.local_entrypoint()
def fetch_report(tag: str = "prod", outdir: str = "."):
    data = pack.remote(f"{tag}_report")
    os.makedirs(outdir, exist_ok=True)
    p = os.path.join(outdir, f"{tag}_report.tar.gz")
    open(p, "wb").write(data)
    print("saved", p, len(data), "bytes")


@app.local_entrypoint()
def run_selftest(pdb: str, sdf: str):
    print(selftest.remote(open(pdb).read(), open(sdf).read()))


@app.local_entrypoint()
def run(pdb: str, ligdir: str, tag: str = "prod", ns: float = 50.0):
    pdb_text = open(pdb).read()
    jobs = []
    for f in sorted(os.listdir(ligdir)):
        if f.lower().endswith(".sdf"):
            name = os.path.splitext(f)[0].replace("_mode1", "")
            jobs.append((name, open(os.path.join(ligdir, f)).read(), pdb_text, tag, ns))
    print(f"launching {len(jobs)} simulations at {ns} ns each")
    for r in simulate.starmap(jobs):
        print(r)


@app.local_entrypoint()
def run_spawn(pdb: str, ligdir: str, tag: str = "prod", ns: float = 50.0):
    """Launch all six server-side and return immediately.

    USE THIS, NOT `run`. A local entrypoint driving `.starmap()` dies with the
    client: if the laptop loses its connection the whole map is cancelled, even
    with --detach. `.spawn()` queues each call server-side instead, so the
    simulations are genuinely independent of the machine that started them.
    """
    print(f"budget ${BUDGET_USD} -> {MAX_SECONDS / 3600:.2f} h per container")
    pdb_text = open(pdb).read()
    n = 0
    for fn in sorted(os.listdir(ligdir)):
        if fn.lower().endswith(".sdf"):
            name = os.path.splitext(fn)[0].replace("_mode1", "")
            call = simulate.spawn(name, open(os.path.join(ligdir, fn)).read(),
                                  pdb_text, tag, ns)
            print("spawned", name, call.object_id)
            n += 1
    print(n, "simulations spawned - safe to close PowerShell now")


@app.local_entrypoint()
def fetch(tag: str = "prod", outdir: str = "."):
    data = pack.remote(tag)
    os.makedirs(outdir, exist_ok=True)
    p = os.path.join(outdir, f"{tag}.tar.gz")
    open(p, "wb").write(data)
    print("saved", p, len(data), "bytes")
