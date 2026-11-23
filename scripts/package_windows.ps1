# 윈도우판 포장: 릴리스 빌드(콘솔 창 없는 실행 파일) + 실행에 필요한 DLL + 공개 캐릭터 → dist\DeskPet-windows.zip
#   사용: pwsh scripts/package_windows.ps1 [-OutDir dist]
#   필요: Swift 도구 모음(PATH), Visual Studio(dumpbin·VC 런타임). GitHub 윈도우 러너에는 모두 있음
#
# DLL은 DeskPet.exe의 가져오기 표를 따라가며 Swift 런타임 폴더와 VC 재배포 폴더에서 찾은 것만 넣음.
# 윈도우가 이미 가진 DLL(KERNEL32, api-ms-win-*, ucrtbase 등)은 넣지 않음.
# scripts/private-skins.txt의 캐릭터는 넣지 않음 (공개 배포).
param([string]$OutDir = "dist")
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

# 창 없는 GUI 실행 파일 (main은 그대로 쓰고 진입점만 콘솔용 CRT 시작 함수로)
swift build -c release -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup
if ($LASTEXITCODE -ne 0) { throw "release build failed" }
$bin = (swift build -c release --show-bin-path).Trim()

$stage = Join-Path $OutDir 'DeskPet'
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item (Join-Path $bin 'DeskPet.exe') $stage

# DLL을 찾을 폴더: 빌드 폴더, PATH의 Swift 런타임, VC 재배포(앱 옆에 두는 배포 허용)
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = (& $vswhere -latest -products * -property installationPath | Select-Object -First 1).Trim()
$dumpbin = Get-ChildItem (Join-Path $vs 'VC\Tools\MSVC') -Recurse -Filter dumpbin.exe |
    Where-Object { $_.FullName -like '*Hostx64\x64*' } | Select-Object -First 1
if (-not $dumpbin) { throw "dumpbin.exe not found under $vs" }
$redist = Get-ChildItem (Join-Path $vs 'VC\Redist\MSVC') -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    ForEach-Object { Get-ChildItem (Join-Path $_.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue } |
    Select-Object -First 1
$searchDirs = @($bin) + ($env:Path -split ';' | Where-Object { $_ -and (Test-Path (Join-Path $_ 'swiftCore.dll')) })
if ($redist) { $searchDirs += $redist.FullName }
Write-Host "DLL search: $($searchDirs -join '; ')"

# 가져오기 표를 따라가며 모음
$seen = @{}
$system = New-Object System.Collections.Generic.List[string]
$queue = New-Object System.Collections.Generic.Queue[string]
$queue.Enqueue((Join-Path $stage 'DeskPet.exe'))
while ($queue.Count -gt 0) {
    $file = $queue.Dequeue()
    $names = & $dumpbin.FullName /nologo /dependents $file | ForEach-Object {
        if ($_ -match '^\s+(\S+\.dll)\s*$') { $Matches[1] }
    }
    foreach ($name in $names) {
        $key = $name.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $found = $searchDirs | ForEach-Object { Join-Path $_ $name } | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($found) {
            Copy-Item $found $stage
            $queue.Enqueue((Join-Path $stage $name))
        } else {
            $system.Add($name)
        }
    }
}

# 공개 캐릭터만
$private = Get-Content 'scripts/private-skins.txt' | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object { $_.Trim() }
$skins = Join-Path $stage 'Assets\Skins'
New-Item -ItemType Directory -Force $skins | Out-Null
Get-ChildItem 'Assets/Skins' -Directory | Where-Object { $private -notcontains $_.Name } |
    ForEach-Object { Copy-Item -Recurse $_.FullName $skins }
Copy-Item 'LICENSE' $stage

$zip = Join-Path $OutDir 'DeskPet-windows.zip'
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path $stage -DestinationPath $zip
$bundled = Get-ChildItem $stage -Filter *.dll | ForEach-Object Name
Write-Host "bundled DLLs ($($bundled.Count)): $($bundled -join ', ')"
Write-Host "left to Windows: $(($system | Sort-Object -Unique) -join ', ')"
Write-Host "skins: $((Get-ChildItem $skins -Directory | ForEach-Object Name) -join ', ')"
Write-Host ("zip: {0} ({1:N1} MB)" -f $zip, ((Get-Item $zip).Length / 1MB))
