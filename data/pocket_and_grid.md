# TEM-1 (PDB 1BTL) binding site and docking grid

## Receptor preparation

`data/1BTL_clean.pdb` — chain A only, 2,030 ATOM records, 263 residues,
**zero HETATM**. The single sulfate ion (residue 291) and all crystallographic
waters were removed; alternate conformations resolved by keeping altloc A and
blanking the column.

1BTL is an apo structure: there is no co-crystallised ligand to centre a box on.

## Catalytic residues

Class A serine beta-lactamase catalytic machinery:

| Residue | Atom used | x | y | z |
|---|---|---|---|---|
| Ser70  | OG  |  9.468 | 6.772 | 37.805 |
| Lys73  | NZ  |  8.398 | 6.538 | 40.489 |
| Ser130 | OG  |  6.908 | 9.212 | 37.660 |
| Asn132 | ND2 | 10.672 | 7.752 | 41.955 |
| Glu166 | OE1 | 13.166 | 5.553 | 41.654 |
| Lys234 | NZ  |  5.222 | 7.590 | 35.947 |

Ser70 is the nucleophile, Glu166 the general base, and Ser130/Lys234 form part
of the anion-binding pocket that recognises the C3/C4 carboxylate of
beta-lactam substrates.

## Grid

```
Centre   x = 8.972   y = 7.236   z = 39.252
Size     22 x 22 x 22 A
Spacing  0.375 A (AutoDock default)
```

The centre is the **centroid of the six catalytic functional atoms above**.
The furthest of them lies 5.12 A from that centre and the mean distance is
3.29 A, so a 22 A box reaching +/-11 A covers the whole active site with about
6 A of margin on every side.

### Why not centre on the sulfate?

The sulfate ion in 1BTL sits at (8.958, 10.722, 35.256). It is 4.73 A from
Ser70 OG, which looks promising, but it is 6.11 A mean and 9.24 A maximum from
the six catalytic atoms — it occupies one sub-pocket rather than the centre of
the site. Centring there biases every pose toward that corner.

### Sequence indexing

The mature TEM-1 sequence used for generative design is 263 residues. PDB
numbering follows the Ambler scheme, so:

```
zero-based index = PDB residue number - 26
```

Ser70 -> 44, Lys73 -> 47, Ser130 -> 104, Asn132 -> 106, Glu166 -> 140,
Lys234 -> 208.
