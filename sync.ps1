# 공부 노트 동기화: 프로젝트 묶인 노트 재복사 -> manifest.json 생성 -> git push
# 사용법: notes 폴더에서  ./sync.ps1
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

# 1) 디자인패턴 레포에서 최신본 재복사 (원본이 있을 때만)
$dp = "C:\dev\react_design_pattern"
$copy = @{
  "docs\design-01-observer.md"        = "design-01-observer.md"
  "docs\design-02-singleton.md"       = "design-02-singleton.md"
  "src\patterns\observer\NOTES.md"    = "observer-NOTES.md"
  "src\patterns\observer\EXERCISE.md" = "observer-EXERCISE.md"
  "src\patterns\singleton\NOTES.md"   = "singleton-NOTES.md"
  "src\patterns\singleton\EXERCISE.md"= "singleton-EXERCISE.md"
}
foreach ($src in $copy.Keys) {
  $from = Join-Path $dp $src
  if (Test-Path $from) { Copy-Item $from (Join-Path "$root\design-pattern" $copy[$src]) -Force }
}

# 2) manifest.json 생성 (docs, design-pattern 하위 *.md 스캔)
$manifest = foreach ($f in Get-ChildItem "$root\docs","$root\design-pattern","$root\java" -Filter *.md -File -ErrorAction SilentlyContinue) {
  $head = (Get-Content $f.FullName -TotalCount 30 -Encoding UTF8 | Where-Object { $_ -match '^\#\s+' } | Select-Object -First 1)
  $title = if ($head) { ($head -replace '^\#\s+','').Trim() } else { $f.BaseName }
  [pscustomobject]@{
    title    = $title
    category = $f.Directory.Name
    path     = "$($f.Directory.Name)/$($f.Name)"
  }
}
$json = @($manifest) | ConvertTo-Json -Depth 3
if (@($manifest).Count -le 1) { $json = "[$json]" }   # 5.1은 단일 요소를 배열로 안 만듦
[System.IO.File]::WriteAllText("$root\manifest.json", $json, (New-Object System.Text.UTF8Encoding($false)))  # BOM 없이
Write-Host "manifest: $(@($manifest).Count)개 노트"

# 3) git push
git -C $root add -A
git -C $root commit -m "docs: 노트 동기화" 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "변경 없음 (커밋 스킵)" }
git -C $root push
