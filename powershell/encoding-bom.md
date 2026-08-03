# PowerShell 5.1의 인코딩·BOM 함정

**한 문장**: Windows PowerShell 5.1은 BOM 없는 `.ps1`을 UTF-8이 아니라 시스템 ANSI 코드페이지로 읽어서, 한글 같은 비ASCII 문자가 깨지고 스크립트가 파싱 단계에서 죽는다.

## 왜 헷갈렸나

`publish.ps1`을 평범한 UTF-8(BOM 없음)로 저장했는데, 실행하니 엉뚱한 곳에서 이런 에러가 났다:

```
At publish.ps1:29 char:85
+ ... else { Write-Host "?먭꺽 ?놁쓬 (push ?ㅽ궢)" }
The string is missing the terminator: ".
```

코드 문법은 멀쩡한데 "문자열 종결자(`"`)가 없다"니 당황스러웠다. 원인은 문법이 아니라 **인코딩**이었다 — 파일을 잘못된 코드페이지로 읽으면서 한글 바이트가 깨졌고, 깨진 바이트열 안에서 따옴표 짝이 어긋나 파서가 문자열이 안 닫혔다고 판단한 것.

## 핵심

- **Windows PowerShell 5.1**(= `powershell.exe`, 대부분의 윈도우 기본)은 `.ps1`에 **BOM이 없으면 ANSI(로캘 코드페이지, 한국은 949)로 해석**한다. UTF-8로 안 읽는다.
- **PowerShell 7+**(`pwsh`)은 기본이 UTF-8이라 이 문제가 없다. 그래서 "내 PC(7)에선 되는데 배포하면(5.1) 깨진다"가 발생.
- 해결: 비ASCII가 든 `.ps1`은 **UTF-8 with BOM**으로 저장한다. BOM(`EF BB BF`)이 있으면 5.1도 UTF-8로 올바르게 읽는다.
- 많은 에디터/도구(Claude의 Write 포함)는 기본이 **BOM 없는** UTF-8이라, 저장 후 별도로 BOM을 붙여야 할 때가 있다.
- 증상 구분법: "string is missing the terminator", 깨진 글자(`?먭꺽`), 또는 파서 에러가 **한글이 든 줄**을 가리키면 인코딩부터 의심.

### 곁다리로 같이 겪는 것들
- `ConvertTo-Json`이 요소가 **1개면 배열로 안 감싼다** → `if (@($x).Count -le 1) { $json = "[$json]" }`로 보정.
- 파일을 **BOM 없이** 쓰려면 `[System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))`. 반대로 BOM 필요하면 `UTF8Encoding($true)`.

## 예시 코드

이미 저장된 파일(바이트는 정상, BOM만 없음)에 BOM을 덧붙여 재저장:

```powershell
$p = "C:\...\publish.ps1"
$text = [System.IO.File]::ReadAllText($p, [System.Text.UTF8Encoding]::new($false))  # UTF-8로 읽기
[System.IO.File]::WriteAllText($p, $text, [System.Text.UTF8Encoding]::new($true))    # BOM 붙여 쓰기
```

BOM 확인 (앞 3바이트가 `ef bb bf`면 BOM 있음):

```bash
head -c3 publish.ps1 | od -An -tx1
```

## 더 볼 것
- 근본 회피책: 스크립트의 사용자용 메시지를 ASCII로만 쓰면 인코딩에 안 물림. 단 git commit 메시지 등 한글이 꼭 필요한 값이 있으면 BOM이 정답.
- 관련: [[hooks-vs-skills]] — 이 함정은 그 `/note` 플러그인의 `publish.ps1`을 배포하다 실제로 터졌다.
