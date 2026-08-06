# Edge 헤드리스로 HTML→PDF 변환

**한 문장**: `msedge --headless --print-to-pdf`로 HTML을 PDF로 뽑을 수 있는데, **이미 실행 중인 Edge에 요청이 물리면 렌더가 중간에 끊겨 깨진 PDF**가 나오므로 `--user-data-dir`로 격리 인스턴스를 띄우고 프로세스 종료까지 기다려야 한다.

## 왜 헷갈렸나

pandoc·LibreOffice 없이 Windows에서 md/HTML을 PDF로 만들려다, 이미 깔려 있는 Edge의 `--print-to-pdf`를 썼다. 문서 대부분은 잘 나왔는데 유독 한 파일만 70KB짜리 "깨진" PDF가 나왔다. 같은 스크립트, 같은 방식인데 왜 하나만 깨지지? 가 안 잡혔다.

원인은 **그때 사용자가 Edge 브라우저를 켜 두고 있었다는 것**. `msedge --headless ...`를 그냥 실행하면 이미 떠 있는 Edge 프로세스가 그 요청을 가로채는데, 헤드리스 인쇄 작업이 제대로 완료되지 않아 파일이 중간에 잘린다.

## 핵심

- **`--user-data-dir`로 격리**: 임시 프로필 경로를 주면 실행 중인 Edge와 별개의 인스턴스가 떠서 인쇄가 온전히 끝난다. 이게 깨짐 방지의 핵심.
- **`--headless --disable-gpu`**: 화면 없이 렌더. GPU 끄면 헤드리스에서 안정적.
- **`--no-pdf-header-footer`**: 날짜·URL 머리글/바닥글 제거(깔끔한 인쇄).
- **완료를 기다려라**: Edge는 렌더를 백그라운드 자식 프로세스에서 하므로 `Start-Sleep`으로 대충 기다리면 파일이 아직 안 써졌을 수 있다. `Start-Process ... -Wait`로 종료를 기다린 뒤 파일 존재를 확인한다.
- **폰트는 시스템에 설치돼 있어야** PDF에 임베드된다. `font-family`로 지정한 폰트(예: Pretendard)가 사용자 폰트로 깔려 있으면 Edge가 그걸로 렌더하고 서브셋을 PDF에 넣는다.
- **경로 주의**: `--print-to-pdf=<경로>`와 입력은 `file:///C:/...` 형식. 한글 경로도 됨.

## 예시 코드

이 세션에서 발표 슬라이드(HTML 10장)를 PDF로 뽑을 때 실제로 쓴 방식:

```powershell
$edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
$html = 'C:\...\deck.html'
$pdf  = 'C:\...\발표.pdf'
$tmp  = "$env:TEMP\edge_$(Get-Random)"   # 격리 프로필

Start-Process $edge -ArgumentList `
  '--headless','--disable-gpu',"--user-data-dir=$tmp",`
  '--no-pdf-header-footer',"--print-to-pdf=$pdf",`
  ("file:///$html".Replace('\','/')) -Wait

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path $pdf) { "OK: $((Get-Item $pdf).Length) bytes" } else { "MISSING" }
```

깨졌던 버전은 `--user-data-dir` 없이 그냥 `& $edge --headless ...`를 실행하고 `Start-Sleep 500`으로 기다린 것이었다 → 실행 중인 Edge에 물려 70KB 잘린 PDF.

## 확인 문제

1. 동일한 스크립트로 여러 HTML을 PDF로 뽑는데 유독 하나만 깨져 나온다. 가장 먼저 의심할 원인과 해결책은?
2. `Start-Sleep`로 기다리는 방식이 불안정한 이유는?

<details><summary>답</summary>

1. **실행 중인 Edge 인스턴스에 인쇄 요청이 물린 것**이 원인일 가능성이 크다(사용자가 브라우저를 켠 순간에만 재현). `--user-data-dir=<임시경로>`로 **격리된 Edge 인스턴스**를 띄우면 해결된다.
2. Edge는 `--print-to-pdf`를 **백그라운드 자식 프로세스**에서 처리하므로, 부모 프로세스가 리턴한 뒤에도 파일이 아직 안 써졌을 수 있다. 고정 시간 `Start-Sleep`은 렌더가 그 안에 끝난다는 보장이 없다 → `Start-Process -Wait`로 종료를 기다리고 `Test-Path`로 확인해야 한다.

</details>

## 더 볼 것
- 관련: [[encoding-bom]] (같은 "Windows에서 문서 자동화" 삽질 계열)
- pandoc/LibreOffice가 있으면 그쪽이 더 정석이지만, 없을 때 Edge가 무설치 대안.
