# =============================================================================
# BLOCK 4 - MERGE RECEPTOR + BEST POSE INTO ONE PDB PER COMPOUND
# =============================================================================
# Produces a single complex file per compound for a viewer such as BIOVIA
# Discovery Studio, which is easier than inserting the ligand by hand.
#
# Pure PowerShell - no Python, no RDKit, no Open Babel needed locally.
#
# CAVEAT: PDB stores connectivity (CONECT) but NOT bond order. A viewer
# re-perceives aromatic and double bonds from geometry. Check the 2D diagram
# against the real structure. If it looks wrong, load the receptor PDB and
# insert the _mode1.sdf separately instead - SDF carries true bond orders.
# =============================================================================

$dir  = "$env:USERPROFILE\Downloads\tem1_vina"
$tag  = "run1"
$src  = "$dir\out\$tag"
$out  = "$env:USERPROFILE\Downloads\TEM1_complexes_for_DS"
New-Item -ItemType Directory -Force -Path $out | Out-Null

$rec = Get-Content "$src\1BTL_receptor_for_DS.pdb" | Where-Object { $_ -match '^(ATOM|TER)' }
$maxSer = ($rec | Where-Object { $_ -match '^ATOM' } |
           ForEach-Object { [int]$_.Substring(6,5).Trim() } |
           Measure-Object -Maximum).Maximum

foreach ($f in Get-ChildItem "$src\poses_sdf\*_mode1.sdf") {
    $name = $f.BaseName -replace '_mode1$',''
    $L    = Get-Content $f.FullName
    $na   = [int]$L[3].Substring(0,3).Trim()
    $nb   = [int]$L[3].Substring(3,3).Trim()

    $het = New-Object System.Collections.Generic.List[string]
    $con = New-Object System.Collections.Generic.List[string]
    $cnt = @{}

    for ($i = 0; $i -lt $na; $i++) {
        $a  = $L[4 + $i]
        $x  = [double]$a.Substring(0,10);  $y = [double]$a.Substring(10,10)
        $z  = [double]$a.Substring(20,10); $el = $a.Substring(31,3).Trim()
        if (-not $cnt.ContainsKey($el)) { $cnt[$el] = 0 }
        $cnt[$el]++
        $nm = ($el + $cnt[$el])
        if ($nm.Length -gt 4) { $nm = $nm.Substring(0,4) }
        if ($el.Length -eq 1 -and $nm.Length -lt 4) { $nm = " $nm" }
        $ser = $maxSer + 1 + $i
        $het.Add(('HETATM{0,5} {1,-4} LIG A 900    {2,8:F3}{3,8:F3}{4,8:F3}  1.00  0.00          {5,2}' `
                  -f $ser, $nm, $x, $y, $z, $el))
    }
    for ($j = 0; $j -lt $nb; $j++) {
        $b  = $L[4 + $na + $j]
        $a1 = [int]$b.Substring(0,3).Trim(); $a2 = [int]$b.Substring(3,3).Trim()
        $con.Add(('CONECT{0,5}{1,5}' -f ($maxSer + $a1), ($maxSer + $a2)))
    }

    $path = "$out\1BTL_$name`_complex.pdb"
    ($rec + $het + $con + 'END') | Set-Content $path -Encoding ASCII
    Write-Host ("{0,-18} {1,3} ligand atoms, {2,3} bonds -> {3}" -f $name, $na, $nb, (Split-Path $path -Leaf)) -ForegroundColor Green
}

Write-Host "`nComplexes written to: $out" -ForegroundColor Cyan
Copy-Item "$src\poses_sdf\*_mode1.sdf"     $out -Force
Copy-Item "$src\1BTL_receptor_for_DS.pdb"  $out -Force
Get-ChildItem $out | Select-Object Name, Length | Format-Table -AutoSize

# WHAT YOU SHOULD SEE IF IT WORKED
#   Each complex file is larger than the receptor by roughly 75 bytes per
#   ligand atom. A 33-atom ligand adds about 2.5 kB, a 21-atom ligand ~1.3 kB.
#   If a complex is the same size as the receptor, no HETATM lines were added.
