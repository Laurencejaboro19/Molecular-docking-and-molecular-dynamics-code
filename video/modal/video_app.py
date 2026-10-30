"""
TEM-1 MD movie renderer - the version that produced the first six 20 s films.

WHAT IT DOES
------------
Reads the production trajectories already sitting in the `tem1-md` Modal
volume (written by md/modal/md_app.py) and renders one vertical, ray-traced
1080x1920 film per compound, 24 fps, with a heads-up display showing the
simulation clock and whether the ligand is still in the active site.

    /cache/<tag>/<compound>/start.pdb   solvated system, topology for the DCD
    /cache/<tag>/<compound>/traj.dcd    50 ns, one frame every 10 ps (5000)
            |
            v
    /cache/<tag>_video/<compound>/<compound>.mp4

WHY IT IS SHAPED THIS WAY
-------------------------
PyMOL's `ray` is a CPU ray tracer. It has no GPU code path at all - the
graphics card is only used for the interactive viewport, which does not
exist in a headless container. Attaching a GPU to this app would cost money
and change the render time by zero. Speed therefore comes from two places:

  1. `max_threads` set explicitly. In a container PyMOL mis-reads the cgroup
     CPU limit and frequently falls back to one or two threads. Setting it to
     the container's real core count took this run from ~25 s/frame to
     2.2 s/frame - the single largest change in the whole pipeline.

  2. Sharding across containers. Nothing in frame 200 depends on frame 199,
     so the frame range is cut into SHARDS slices rendered in parallel. Same
     total core-seconds, roughly an eightfold reduction in wall time.

Three stages, in order:

  prep    one container per compound: drop water and ions, bring the ligand
          back next to the protein by the minimum-image convention, superpose
          every frame on frame 0, write a reduced mov.pdb + mov.dcd
  shard   SHARDS containers per compound, in parallel: ray-trace a slice
  stitch  one container per compound: draw the HUD with Pillow, run ffmpeg

See video/README.md for the failures that shaped this file.
"""
import modal, os, io, json, tarfile

# conda-forge carries an open-source PyMOL that needs no licence, plus
# MDAnalysis and ffmpeg, so the whole pipeline is one micromamba environment.
image = (modal.Image.micromamba(python_version="3.11")
    .micromamba_install(
        "pymol-open-source", "mdanalysis", "numpy", "pillow",
        "matplotlib", "ffmpeg", channels=["conda-forge"]))

# Same volume the MD run wrote to. Not created here - if it is missing,
# something is wrong and failing loudly is better than rendering nothing.
vol = modal.Volume.from_name("tem1-md")
app = modal.App("tem1-video", image=image)

W, H, FPS = 1080, 1920, 24      # 9:16, the aspect ratio phones and reels use
CORES  = 16                     # cores per shard container
SHARDS = 8                      # parallel slices per film
POCKET = "70+73+130+132+166+234+235+244"   # Ambler numbering
FRAME_PS = 10.0                 # DCD stride from the production run
SPIN = 55.0                     # degrees of camera rotation over a whole film

SUB = "50 ns molecular dynamics - TEM-1 beta-lactamase (1BTL)"
KICKER = "LAURENCE JABORO"
NOTE = {   # one-line caption per compound, from md/results/tables/
 "BTL-004":         "Ser130 H-bond held 64% of frames",
 "BTL-023":         "left the active site at 12.3 ns",
 "BTL-007":         "left the active site at 4.5 ns",
 "Avibactam":       "clinical inhibitor - reference",
 "Sulbactam":       "clinical inhibitor - reference",
 "Clavulanic_acid": "clinical inhibitor - reference",
}


# --------------------------------------------------------------- stage 1
@app.function(cpu=8, memory=16384, volumes={"/cache": vol}, timeout=3600)
def prep(name: str, tag: str = "prod", seconds: int = 20):
    """Turn a 2.5 GB solvated trajectory into a few MB of protein + ligand.

    Three corrections happen here, and all three were bugs before they were
    corrections:

      * MINIMUM IMAGE. OpenMM wraps each molecule into the primary box
        separately, so the ligand can be a whole box-length away from the
        protein in the raw coordinates even while it is bound. Every frame
        shifts the ligand by the integer box vector that brings its centre
        closest to the protein's. Without this the ligand teleports across
        the screen whenever it crosses a periodic boundary.

      * SUPERPOSITION. Each frame is rotated onto frame 0 by protein CA, so
        the protein is stationary and only the ligand moves. Without it the
        whole system tumbles and nothing is legible.

      * AMBLER NUMBERING. `resi 130` must mean Ser130. 1BTL already carries
        Ambler numbering (26-290, with the standard gaps at 239 and 253), so
        the numbering is verified rather than assumed. An earlier version
        rebuilt it unconditionally as position + 26, which ignores those two
        gaps and silently relabelled Arg244 as Lys245 - the one residue the
        BTL-004 result depends on.
    """
    import MDAnalysis as mda, numpy as np
    from MDAnalysis.analysis import align

    nframes = seconds * FPS
    wd = f"/cache/{tag}_video/{name}"
    os.makedirs(wd, exist_ok=True)
    src = f"/cache/{tag}/{name}"

    u = mda.Universe(f"{src}/start.pdb", f"{src}/traj.dcd")
    prot = u.select_atoms("protein")
    lig = u.select_atoms("resname UNK")          # OpenFF names the ligand UNK
    if lig.n_atoms == 0:
        lig = u.select_atoms(
            "not protein and not resname HOH WAT SOL NA CL NA+ CL-")
    ca = prot.select_atoms("name CA")

    AMBLER = [n for n in range(26, 291) if n not in (239, 253)]
    want = {70: "SER", 73: "LYS", 130: "SER", 132: "ASN",
            166: "GLU", 234: "LYS", 235: "SER", 244: "ARG"}
    have = {int(r.resid): r.resname for r in prot.residues}
    if not all(have.get(k) == v for k, v in want.items()):
        print(f"[{name}] rebuilding Ambler numbering", flush=True)
        assert len(prot.residues) == len(AMBLER), \
            f"{len(prot.residues)} residues, expected {len(AMBLER)}"
        for res, n in zip(prot.residues, AMBLER):
            res.resid = n
        have = {int(r.resid): r.resname for r in prot.residues}
    for k, v in want.items():
        assert have.get(k) == v, f"resi {k} is {have.get(k)}, expected {v}"
    print(f"[{name}] pocket residues verified", flush=True)

    lig.residues.resids = 900
    lig.residues.resnames = "LIG"

    # the six catalytic functional atoms, the same set used to centre the
    # Vina grid box and to measure COM distance in the analysis
    cat = prot.select_atoms(
        "(resid 70 and name OG) or (resid 73 and name NZ) or "
        "(resid 130 and name OG) or (resid 132 and name ND2) or "
        "(resid 166 and name OE1) or (resid 234 and name NZ)")

    n = len(u.trajectory)
    idx = [round(k * (n - 1) / (nframes - 1)) for k in range(nframes)]
    ref = ca.positions.copy() - ca.center_of_mass()

    merged = mda.Merge(prot, lig)
    coords, times, dists = [], [], []
    for k in idx:
        ts = u.trajectory[k]
        box = ts.dimensions[:3]
        pp, lp = prot.positions.copy(), lig.positions.copy()
        lp -= box * np.round((lp.mean(0) - prot.center_of_mass()) / box)
        cen = ca.center_of_mass()
        R, _ = align.rotation_matrix(ca.positions - cen, ref)
        pp = (pp - cen) @ R.T
        lp = (lp - cen) @ R.T
        cp = (cat.positions - cen) @ R.T
        coords.append(np.vstack([pp, lp]).astype(np.float32))
        times.append(k * FRAME_PS / 1000.0)
        # per-frame catalytic centroid, not the crystal-frame one: addSolvent
        # re-centres the solute, so a fixed centroid puts a constant ~30 A
        # offset into every distance. Same bug that once made all six ligands
        # look like they had left the site.
        dists.append(float(np.linalg.norm(lp.mean(0) - cp.mean(0))))

    merged.atoms.positions = coords[0]
    merged.atoms.write(f"{wd}/mov.pdb", bonds="conect")
    with mda.Writer(f"{wd}/mov.dcd", n_atoms=merged.atoms.n_atoms) as Wtr:
        for c in coords:
            merged.atoms.positions = c
            Wtr.write(merged.atoms)
    json.dump({"times_ns": times, "com_dist_A": dists, "n": nframes},
              open(f"{wd}/track.json", "w"))
    os.makedirs(f"{wd}/fr", exist_ok=True)
    vol.commit()
    print(f"[{name}] {nframes} frames from {n}, "
          f"{merged.atoms.n_atoms} atoms", flush=True)
    return nframes


# --------------------------------------------------------------- stage 2
@app.function(cpu=CORES, memory=16384, volumes={"/cache": vol}, timeout=7200)
def shard(name: str, tag: str, nframes: int, i0: int, i1: int):
    """Ray-trace frames [i0, i1) into <wd>/fr/.

    Every shard builds the camera from frame 1 and then rotates it by
    step * frame_index. That is deterministic, so eight containers that never
    talk to each other produce one continuous camera move. An earlier version
    used a cumulative cmd.turn() per frame, which only works when a single
    process renders every frame in order.
    """
    import pymol2, time
    vol.reload()
    wd = f"/cache/{tag}_video/{name}"
    with pymol2.PyMOL() as p:
        cmd = p.cmd
        cmd.set("max_threads", CORES)       # containers mis-detect this
        cmd.set("ray_opaque_background", 1)
        cmd.set("bg_rgb", [0.047, 0.078, 0.137])
        cmd.load(f"{wd}/mov.pdb", "sys")
        cmd.load_traj(f"{wd}/mov.dcd", "sys", state=1)

        cmd.hide("everything")
        cmd.show("cartoon", "polymer")
        cmd.set("cartoon_transparency", 0.62)   # see the pocket through it
        cmd.color("grey60", "polymer")
        cmd.show("sticks", f"byres (polymer and resi {POCKET}) and sidechain")
        cmd.show("sticks", "resn LIG")
        # keep only the hydrogens that can make a hydrogen bond
        cmd.hide("sticks", "hydro and not (neighbor (elem N+O))")
        for e, c in (("N", "skyblue"), ("O", "salmon"),
                     ("S", "yellow"), ("H", "grey90")):
            cmd.color(c, f"elem {e}")
        cmd.color("palecyan", "polymer and elem C")
        cmd.color("orange", "resn LIG and elem C")   # ligand reads instantly

        cmd.set("stick_radius", 0.17)
        cmd.set("cartoon_fancy_helices", 1)
        cmd.set("ray_shadows", 1)
        cmd.set("antialias", 1)             # 2 costs ~2x for little gain here
        cmd.set("ambient", 0.22)
        cmd.set("specular", 0.28)
        cmd.set("depth_cue", 1)
        cmd.set("fog_start", 0.42)
        # 20 collided into an unreadable pile across the pocket; 13 with a
        # black outline reads against both the protein and the background
        cmd.set("label_size", 13)
        cmd.set("label_color", "white")
        cmd.set("label_outline_color", "black")
        cmd.set("label_shadow_mode", 2)
        cmd.set("label_position", (0, 0, 3.0))
        cmd.set("dash_color", "yellow")
        cmd.set("dash_gap", 0.35)
        # five labels, not eight - enough to orient the viewer without
        # burying the molecule they annotate
        cmd.label("polymer and resi 70+130+166+234+244 and name CA",
                  'f"{resn.capitalize()}{resi}"')

        # camera locked on the pocket, NOT following the ligand - so a
        # compound that leaves visibly walks out of frame
        cmd.set("state", 1)
        cmd.orient(f"polymer and resi {POCKET}")
        cmd.zoom(f"polymer and resi {POCKET}", 7.5)
        base = cmd.get_view()

        step = SPIN / nframes
        t0 = time.time()
        for i in range(i0, i1):
            cmd.set("state", i + 1)
            # polar contacts recomputed from the real coordinates every
            # frame, so a bond breaking and reforming is the actual event
            cmd.delete("hb")
            cmd.distance("hb", "resn LIG", f"polymer and resi {POCKET}",
                         mode=2)
            # the dashes carry the message; the numeric distances just
            # stacked on top of the residue labels
            cmd.hide("labels", "hb")
            cmd.set_view(base)
            cmd.turn("y", step * i)
            cmd.ray(W, H)
            cmd.png(f"{wd}/fr/f{i:04d}.png", dpi=150)
            if (i - i0) % 10 == 0:
                done = i - i0 + 1
                print(f"[{name}] {i0}-{i1}: {done}/{i1-i0} "
                      f"({(time.time()-t0)/done:.1f} s/frame)", flush=True)
    vol.commit()
    return i1 - i0


# --------------------------------------------------------------- stage 3
@app.function(cpu=8, memory=8192, volumes={"/cache": vol}, timeout=3600)
def stitch(name: str, tag: str = "prod"):
    """Draw the HUD onto each frame, encode, delete the frames.

    The HUD is Pillow rather than PyMOL text because PyMOL screen text does
    not survive ray tracing cleanly at this resolution. The IN ACTIVE SITE /
    LEFT THE SITE badge is driven by the per-frame COM distance computed in
    prep, so it is a measurement, not an annotation.
    """
    from PIL import Image, ImageDraw, ImageFont
    import matplotlib, subprocess
    vol.reload()
    wd = f"/cache/{tag}_video/{name}"
    tr = json.load(open(f"{wd}/track.json"))
    times, dists, nframes = tr["times_ns"], tr["com_dist_A"], tr["n"]

    # refuse to encode a film with holes in it
    missing = [i for i in range(nframes)
               if not os.path.exists(f"{wd}/fr/f{i:04d}.png")]
    assert not missing, f"{len(missing)} frames missing, first {missing[:5]}"

    fp = matplotlib.get_data_path() + "/fonts/ttf/"   # always present
    F = lambda s, b=False: ImageFont.truetype(
        fp + ("DejaVuSans-Bold.ttf" if b else "DejaVuSans.ttf"), s)
    f_kick, f_big, f_sub = F(30), F(78, True), F(30)
    f_clk, f_badge, f_note = F(40, True), F(30, True), F(28)
    title = name.replace("_", " ")

    for i in range(nframes):
        im = Image.open(f"{wd}/fr/f{i:04d}.png").convert("RGB")
        d = ImageDraw.Draw(im, "RGBA")
        d.rectangle([0, 0, W, 300], fill=(12, 20, 35, 215))
        d.rectangle([0, H - 230, W, H], fill=(12, 20, 35, 215))
        d.text((60, 56), KICKER, font=f_kick, fill=(122, 134, 156))
        d.text((60, 104), title, font=f_big, fill=(236, 243, 255))
        d.text((62, 206), SUB, font=f_sub, fill=(122, 134, 156))

        inside = dists[i] < 10.0
        col = (28, 190, 140) if inside else (226, 80, 80)
        txt = "IN ACTIVE SITE" if inside else "LEFT THE SITE"
        d.text((60, H - 196), f"t = {times[i]:5.1f} ns",
               font=f_clk, fill=(236, 243, 255))
        bw = d.textlength(txt, font=f_badge)
        d.rounded_rectangle([W - 80 - bw - 44, H - 196,
                             W - 60, H - 196 + 54], 27, fill=col)
        d.text((W - 80 - bw - 22, H - 182), txt, font=f_badge,
               fill=(255, 255, 255))
        d.text((60, H - 120), NOTE.get(name, ""), font=f_note,
               fill=(150, 163, 186))
        d.rectangle([0, H - 8, int(W * i / (nframes - 1)), H],
                    fill=(25, 182, 166))
        im.save(f"{wd}/fr/f{i:04d}.png")

    out = f"{wd}/{name}.mp4"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error",
                    "-framerate", str(FPS), "-i", f"{wd}/fr/f%04d.png",
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18",
                    "-movflags", "+faststart", out], check=True)
    for f in os.listdir(f"{wd}/fr"):
        os.remove(f"{wd}/fr/{f}")
    vol.commit()
    mb = os.path.getsize(out) / 1e6
    print(f"[{name}] {out}  {mb:.1f} MB", flush=True)
    return {"compound": name, "MB": round(mb, 1),
            "left_site": bool(max(dists) > 10)}


# --------------------------------------------------------------- one film
@app.function(volumes={"/cache": vol}, timeout=14400)
def film(name: str, tag: str = "prod", seconds: int = 20):
    """prep -> SHARDS parallel shards -> stitch, orchestrated in the cloud.

    This runs as a Modal function rather than a local entrypoint so that the
    whole sequence is server-side and nothing depends on the laptop staying
    connected. Spawn THIS, not the three stages individually.
    """
    nframes = prep.remote(name, tag, seconds)
    cuts = [round(k * nframes / SHARDS) for k in range(SHARDS + 1)]
    jobs = [(name, tag, nframes, cuts[k], cuts[k + 1])
            for k in range(SHARDS) if cuts[k + 1] > cuts[k]]
    total = sum(shard.starmap(jobs))
    print(f"[{name}] {total} frames rendered", flush=True)
    return stitch.remote(name, tag)


@app.function(cpu=8, volumes={"/cache": vol}, timeout=3600)
def pack_videos(tag: str = "prod") -> bytes:
    """Tar up every finished mp4 so one call pulls the whole set down."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as t:
        for root, _, files in os.walk(f"/cache/{tag}_video"):
            for f in files:
                if f.endswith(".mp4"):
                    t.add(os.path.join(root, f), arcname=f)
    return buf.getvalue()


# --------------------------------------------------------------- entrypoints
@app.local_entrypoint()
def preview(name: str = "BTL-004", tag: str = "prod"):
    """3 s clip - check framing, labels and spin before paying for six."""
    print(film.remote(name, tag, 3))


@app.local_entrypoint()
def render_all(tag: str = "prod", seconds: int = 20):
    """Six films. MUST be run with `modal run --detach`, or better, use
    scripts/23_deploy_and_launch.ps1 - see README for why."""
    for n in ["BTL-004", "BTL-023", "BTL-007",
              "Avibactam", "Sulbactam", "Clavulanic_acid"]:
        print("spawned", n, film.spawn(n, tag, seconds).object_id)
    print("\nQueued. Verify with: modal app list")


@app.local_entrypoint()
def fetch(tag: str = "prod", outdir: str = "."):
    data = pack_videos.remote(tag)
    p = os.path.join(outdir, "tem1_videos.tar.gz")
    open(p, "wb").write(data)
    print("wrote", p, round(len(data) / 1e6, 1), "MB")
