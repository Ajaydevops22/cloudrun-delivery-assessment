$pattern = '^(?<pre>\s*-?\s*uses:\s*)(?<repo>[\w.-]+/[\w.-]+)(?<path>/[\w./-]+)?@(?<tag>v\d[\w.]*)\s*(#.*)?$'
foreach ($f in Get-ChildItem .github\workflows -Filter *.yml) {
  $new = foreach ($line in Get-Content $f.FullName) {
    $m = [regex]::Match($line, $pattern)
    if (-not $m.Success) { $line; continue }
    $repo = $m.Groups['repo'].Value
    $tag  = $m.Groups['tag'].Value
    $refs = @(git ls-remote "https://github.com/$repo" "refs/tags/$tag" "refs/tags/$tag^{}")
    $hit  = $refs | Where-Object { $_ -match '\^\{\}$' } | Select-Object -First 1
    if (-not $hit) { $hit = $refs | Select-Object -First 1 }
    $sha = if ($hit) { ($hit -split '\s+')[0] } else { '' }
    if ($sha -match '^[0-9a-f]{40}$') {
      "$($m.Groups['pre'].Value)$repo$($m.Groups['path'].Value)@$sha # $tag"
    } else {
      Write-Warning "Could not resolve $repo@$tag"
      $line
    }
  }
  $new | Set-Content -Encoding ascii $f.FullName
}
