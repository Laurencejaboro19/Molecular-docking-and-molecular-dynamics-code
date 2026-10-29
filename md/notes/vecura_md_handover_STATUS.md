# Status at handover
- Six truncated-octahedron systems built and parameterised (identical box/salt/force fields).
- BTL-004: minimised (converged, 9,127 steps, Fmax 79.99 kJ/mol/nm) and 100 ps NVT done (mean T 298.4 K). NPT (1 ns), production NOT run.
- Other five: minimisation was running sequentially when this package was made; their zips contain em_minimised.gro only if it had finished.
- No production has been run. Measured CPU throughput (4 cores): 32.8 ns/day at 2 fs (BTL-004 NVT, 31.6k atoms).
