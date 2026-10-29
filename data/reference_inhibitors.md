# Clinically approved beta-lactamase inhibitors used as benchmarks

Isomeric SMILES, verified against PubChem by InChIKey. Stereochemistry matters:
each carries two defined stereocentres, and clavulanic acid additionally has a
defined exocyclic double-bond geometry. Docking a flat SMILES lets the
conformer generator pick an arbitrary stereoisomer, which scores differently
from the real drug.

| Name | Isomeric SMILES | Formula | Heavy atoms | InChIKey |
|---|---|---|---|---|
| Avibactam | `C1C[C@H](N2C[C@@H]1N(C2=O)OS(=O)(=O)O)C(=O)N` | C7H11N3O6S | 17 | NDCUAPJVLWFHHB-UHNVWZDZSA-N |
| Clavulanic acid | `C1[C@@H]2N(C1=O)[C@H](/C(=C/CO)/O2)C(=O)O` | C8H9NO5 | 14 | HZZVJAQRINQKSD-PBFISZAISA-N |
| Sulbactam | `CC1([C@@H](N2[C@H](S1(=O)=O)CC2=O)C(=O)O)C` | C8H11NO5S | 15 | FKENQMMABCRJMK-RITPCOANSA-N |

## Not included, and why

**Ampicillin** and **amoxicillin** are beta-lactamase *substrates*, not
inhibitors. They were docked in an early run and then dropped: a substrate has
no place in an inhibitor benchmark, and including them inflates the apparent
size-score correlation because they are the two largest molecules in the set.

## Important limitation

All three inhibit TEM-1 by **covalent acylation of Ser70**. Conventional
docking and classical MD model them as non-covalent binders, which understates
their true residence time. Every run here is non-covalent so that the
comparison is like-for-like, and that limitation belongs in any write-up.
