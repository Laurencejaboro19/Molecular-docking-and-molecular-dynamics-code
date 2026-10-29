"""AutoDock Vina on Modal (CPU), docking from supplied SDF files.

Entrypoints: setup, run, fetch.

Docks a set of ligand SDF files against a prepared receptor PDB using
AutoDock Vina, with multiple conformers per ligand to remove Vina's
rigid-ring artefact. Writes scores, per-conformer scores, identity
verification, run metadata, and bond-order-correct pose SDFs.
"""
import io, json, os, re, subprocess, tarfile
import modal

NCPU = 16

image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("ca-certificates", "openbabel")
    .pip_install("rdkit==2025.3.3", "meeko==0.8.0", "gemmi==0.7.1",
                 "numpy==2.2.6", "pandas==2.2.3", "scipy")
    .run_commands(
        # discover and install the latest linux x86_64 Vina binary
        "python -c \""
        "import json,urllib.request,os;"
        "d=json.load(urllib.request.urlopen('https://api.github.com/repos/ccsb-scripps/AutoDock-Vina/releases/latest'));"
        "a=[x for x in d['assets'] if 'linux_x86_64' in x['name'] and 'split' not in x['name']][0];"
        "print('downloading',a['browser_download_url']);"
        "urllib.request.urlretrieve(a['browser_download_url'],'/usr/local/bin/vina');"
        "os.chmod('/usr/local/bin/vina',0o755)\"",
        "vina --version",
    )
)
vol = modal.Volume.from_name("tem1-vina", create_if_missing=True)
app = modal.App("tem1-vina", image=image)

# Grid centre = centroid of the six catalytic functional atoms of TEM-1:
# Ser70 OG, Lys73 NZ, Ser130 OG, Asn132 ND2, Glu166 OE1, Lys234 NZ
CENTER = (8.972, 7.236, 39.252)
BOX = (22.0, 22.0, 22.0)

# expected heavy-atom counts, checked before any scoring is trusted
EXPECT = {"BTL-023": 19, "BTL-007": 16, "BTL-004": 14,
          "Avibactam": 17, "Clavulanic_acid": 14, "Sulbactam": 15}


def _confs_from_sdf(sdf_text, seed, nconf):
    """SDF -> list of PDBQT strings (one per conformer), preserving stereochemistry.

    Vina holds rings rigid, so the ring conformation of the input is frozen for
    the whole run. Docking several ETKDG conformers and keeping the best removes
    that dependence. Any conformer whose InChIKey no longer matches the input is
    discarded, so stereochemistry cannot silently flip.
    """
    from rdkit import Chem
    from rdkit.Chem import AllChem, inchi
    from rdkit.Chem.rdMolDescriptors import CalcMolFormula
    from meeko import MoleculePreparation, PDBQTWriterLegacy

    m = Chem.MolFromMolBlock(sdf_text, removeHs=False)
    Chem.AssignStereochemistryFrom3D(m)          # lock stereo from the 3D coords
    flat = Chem.RemoveHs(m)
    centres = Chem.FindMolChiralCenters(flat, useLegacyImplementation=False,
                                        includeUnassigned=True)
    info = {"formula": CalcMolFormula(flat), "heavy": flat.GetNumHeavyAtoms(),
            "charge": Chem.GetFormalCharge(flat),
            "inchikey": inchi.MolToInchiKey(flat),
            "stereocentres": len(centres),
            "unassigned": len([c for c in centres if c[1] == "?"])}
    mh = Chem.AddHs(m, addCoords=True)
    ps = AllChem.ETKDGv3(); ps.randomSeed = seed; ps.pruneRmsThresh = 0.5
    cids = AllChem.EmbedMultipleConfs(mh, numConfs=nconf, params=ps)
    AllChem.MMFFOptimizeMoleculeConfs(mh, maxIters=2000)
    out = []
    for cid in cids:
        one = Chem.Mol(mh); one.RemoveAllConformers()
        one.AddConformer(mh.GetConformer(int(cid)), assignId=True)
        Chem.AssignStereochemistryFrom3D(one)
        if inchi.MolToInchiKey(Chem.RemoveHs(one)) != info["inchikey"]:
            continue                              # drop any conformer that lost stereo
        s, ok, _ = PDBQTWriterLegacy.write_string(MoleculePreparation().prepare(one)[0])
        if ok:
            out.append(s)
    info["conformers_docked"] = len(out)
    return out, info


def _pdbqt_to_sdf(pdbqt_path, sdf_all, sdf_best, name):
    """Rebuild bond orders from the embedded SMILES -> SDF usable in a viewer.

    PDBQT loses bond orders and aromaticity. Meeko re-perceives them from the
    SMILES it wrote into the file, so the exported SDF is chemically correct.
    """
    from rdkit import Chem
    from meeko import PDBQTMolecule, RDKitMolCreate
    pm = PDBQTMolecule.from_file(pdbqt_path, skip_typing=True)
    m = RDKitMolCreate.from_pdbqt_mol(pm)[0]
    n = m.GetNumConformers()
    w = Chem.SDWriter(sdf_all)
    for i in range(n):
        m.SetProp("_Name", f"{name}_mode{i+1}"); w.write(m, confId=i)
    w.close()
    m.SetProp("_Name", f"{name}_mode1")
    w = Chem.SDWriter(sdf_best); w.write(m, confId=0); w.close()
    return n


@app.function(cpu=NCPU, volumes={"/cache": vol}, timeout=7200)
def dock(pdb_text: str, ligands: dict, tag: str = "run1", seed: int = 42,
         exhaustiveness: int = 16, n_poses: int = 9, nconf: int = 5):
    import pandas as pd
    d = f"/cache/{tag}"
    for sub in ("poses_pdbqt", "poses_sdf"):
        os.makedirs(f"{d}/{sub}", exist_ok=True)
    open(f"{d}/1BTL_receptor_for_DS.pdb", "w").write(pdb_text)

    # Vina has no electrostatic term, so receptor partial charges are irrelevant;
    # -xr writes a rigid receptor PDBQT, -p 7.4 sets protonation.
    subprocess.run(["obabel", f"{d}/1BTL_receptor_for_DS.pdb", "-O",
                    f"{d}/receptor.pdbqt", "-xr", "-p", "7.4"], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    nrec = sum(1 for L in open(f"{d}/receptor.pdbqt") if L.startswith("ATOM"))
    print(f"receptor PDBQT atoms: {nrec}\n", flush=True)

    rows, verify, perconf = [], [], []
    for name in sorted(ligands):
        confs, info = _confs_from_sdf(ligands[name], seed, nconf)
        exp = EXPECT.get(name)
        info.update({"compound": name, "expected_heavy": exp,
                     "match": (exp is None or info["heavy"] == exp)})
        verify.append(info)
        print(f"{name}: {info['formula']} heavy={info['heavy']}/{exp} "
              f"charge={info['charge']} stereo={info['stereocentres']}"
              f"(unassigned {info['unassigned']}) conformers={len(confs)}", flush=True)
        if not confs:
            print(f"  !! no usable conformers for {name}", flush=True); continue

        best = None
        for i, pq in enumerate(confs):
            lp = f"{d}/_l.pdbqt"; op = f"{d}/poses_pdbqt/{name}_c{i}.pdbqt"
            open(lp, "w").write(pq)
            r = subprocess.run(
                ["vina", "--receptor", f"{d}/receptor.pdbqt", "--ligand", lp,
                 "--center_x", str(CENTER[0]), "--center_y", str(CENTER[1]),
                 "--center_z", str(CENTER[2]), "--size_x", str(BOX[0]),
                 "--size_y", str(BOX[1]), "--size_z", str(BOX[2]),
                 "--exhaustiveness", str(exhaustiveness), "--num_modes", str(n_poses),
                 "--seed", str(seed), "--cpu", str(NCPU), "--out", op],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            aff = [float(x) for x in re.findall(r"^\s+\d+\s+(-?\d+\.\d+)", r.stdout, re.M)]
            if not aff:
                print(r.stdout[-1200:], flush=True); continue
            perconf.append({"compound": name, "conformer": i, "best": aff[0],
                            "n_poses": len(aff),
                            "all_affinities": ";".join(f"{a:.1f}" for a in aff)})
            print(f"   conformer {i}: {aff[0]:.1f}", flush=True)
            if best is None or aff[0] < best[0]:
                best = (aff[0], aff, i, op)

        bestE, aff, ci, op = best
        nmod = _pdbqt_to_sdf(op, f"{d}/poses_sdf/{name}_all_poses.sdf",
                             f"{d}/poses_sdf/{name}_mode1.sdf", name)
        rows.append({"compound": name, "best_affinity_kcal_mol": bestE,
                     "worst_affinity_kcal_mol": aff[-1], "n_poses": len(aff),
                     "all_affinities": ";".join(f"{a:.1f}" for a in aff),
                     "heavy_atoms": info["heavy"],
                     "ligand_efficiency": round(abs(bestE) / info["heavy"], 3),
                     "conformers_docked": len(confs), "best_conformer": ci,
                     "inchikey": info["inchikey"], "formula": info["formula"]})
        print(f"   -> BEST {bestE:.1f} (conformer {ci}); {nmod} modes written to SDF\n",
              flush=True)

    df = pd.DataFrame(rows).sort_values("best_affinity_kcal_mol")
    df.to_csv(f"{d}/vina_scores.csv", index=False)
    pd.DataFrame(verify).to_csv(f"{d}/ligand_verification.csv", index=False)
    pd.DataFrame(perconf).to_csv(f"{d}/per_conformer_scores.csv", index=False)
    r = df["best_affinity_kcal_mol"].corr(df["heavy_atoms"])
    open(f"{d}/run_metadata.json", "w").write(json.dumps(
        {"tag": tag, "seed": seed, "exhaustiveness": exhaustiveness,
         "n_poses": n_poses, "conformers_requested": nconf,
         "grid_center": CENTER, "grid_size": BOX, "receptor_pdbqt_atoms": nrec,
         "ligand_protonation": "neutral, as supplied in the SDF files",
         "vina_version": subprocess.run(["vina", "--version"], text=True,
                                        capture_output=True).stdout.strip(),
         "pearson_affinity_vs_heavy_atoms": round(float(r), 3)}, indent=2))
    vol.commit()
    print(df.to_string(index=False), flush=True)
    print(f"\nPearson r (affinity vs heavy atoms): {r:.3f}", flush=True)
    return {"rows": rows, "pearson": round(float(r), 3)}


@app.function(volumes={"/cache": vol}, timeout=1800)
def pack(tag: str) -> bytes:
    vol.reload()
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as t:
        t.add(f"/cache/{tag}", arcname=tag)
    return buf.getvalue()


@app.local_entrypoint()
def setup():
    print("image built; vina binary installed")


@app.local_entrypoint()
def run(pdb: str, ligdir: str, tag: str = "run1", seed: int = 42,
        exhaustiveness: int = 16, n_poses: int = 9, nconf: int = 5):
    ligs = {}
    for f in sorted(os.listdir(ligdir)):
        if f.lower().endswith(".sdf"):
            ligs[os.path.splitext(f)[0]] = open(os.path.join(ligdir, f)).read()
    print("uploading", len(ligs), "ligands:", ", ".join(ligs))
    print(dock.remote(open(pdb).read(), ligs, tag, seed, exhaustiveness, n_poses, nconf))


@app.local_entrypoint()
def fetch(tag: str = "run1", outdir: str = "."):
    data = pack.remote(tag)
    os.makedirs(outdir, exist_ok=True)
    p = os.path.join(outdir, f"{tag}.tar.gz")
    open(p, "wb").write(data)
    print("saved", p, len(data), "bytes")
