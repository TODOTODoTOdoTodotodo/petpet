# DeskPet installer for Windows 10/11 (64-bit). This file is ASCII only on purpose: Windows PowerShell 5.1 reads
# scripts without a BOM in the system code page, where non-ASCII text can break parsing.
#
#   Install:   irm https://github.com/TODOTODoTOdoTodotodo/petpet/releases/latest/download/install.ps1 | iex
#   Uninstall: $env:DESKPET_UNINSTALL = 1; irm https://github.com/TODOTODoTOdoTodotodo/petpet/releases/latest/download/install.ps1 | iex
#              (or, from a downloaded copy: .\install.ps1 -Uninstall)
#
# What it does: downloads the latest DeskPet-windows.zip from GitHub Releases, unpacks it to
# %LOCALAPPDATA%\Programs\DeskPet, adds a Start menu shortcut and starts DeskPet. No administrator rights.
# Settings: DESKPET_URL (download address, or the path of a zip already downloaded), DESKPET_DIR (install folder),
#           DESKPET_NO_LAUNCH=1 (do not start after installing), DESKPET_AUTOSTART=1 (start at sign-in)

function Invoke-DeskPetSetup {
    param([switch]$Uninstall)
    $ErrorActionPreference = 'Stop'
    $repo = 'TODOTODoTOdoTodotodo/petpet'
    $url = if ($env:DESKPET_URL) { $env:DESKPET_URL } else { "https://github.com/$repo/releases/latest/download/DeskPet-windows.zip" }
    $dir = if ($env:DESKPET_DIR) { $env:DESKPET_DIR } else { Join-Path $env:LOCALAPPDATA 'Programs\DeskPet' }
    $startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'DeskPet.lnk'
    $startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'DeskPet.lnk'

    function Stop-DeskPet {
        $running = Get-Process -Name DeskPet -ErrorAction SilentlyContinue
        if ($running) {
            $running | Stop-Process -Force
            Start-Sleep -Seconds 1
        }
    }

    # Deletes the install folder only when it holds DeskPet or is empty, so a mistyped DESKPET_DIR is safe
    function Remove-InstallDir {
        if (-not (Test-Path $dir)) { return $false }
        $empty = -not (Get-ChildItem $dir -Force | Select-Object -First 1)
        if (-not $empty -and -not (Test-Path (Join-Path $dir 'DeskPet.exe'))) {
            throw "$dir holds files other than DeskPet; not deleting it. Check DESKPET_DIR."
        }
        Remove-Item -Recurse -Force $dir
        return $true
    }

    if ($Uninstall) {
        Stop-DeskPet
        if (Remove-InstallDir) { Write-Host "Removed $dir" } else { Write-Host "DeskPet is not installed in $dir" }
        foreach ($link in $startMenu, $startup) {
            if (Test-Path $link) {
                Remove-Item -Force $link
                Write-Host "Removed shortcut $link"
            }
        }
        Write-Host "Settings, collection and log stay. To remove them too:"
        Write-Host "  Remove-Item -Recurse `"$env:APPDATA\DeskPet`", `"$env:LOCALAPPDATA\DeskPet`""
        return
    }

    if (-not [Environment]::Is64BitOperatingSystem) { throw "DeskPet needs 64-bit Windows." }
    if ([Environment]::OSVersion.Version.Major -lt 10) { throw "DeskPet needs Windows 10 or later." }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("deskpet-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $tmp | Out-Null
    try {
        $zip = Join-Path $tmp 'DeskPet-windows.zip'
        if (Test-Path $url) {
            Copy-Item $url $zip
        } else {
            Write-Host "Downloading $url"
            # Windows PowerShell 5.1 may default to an old TLS version
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            $progress = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip
            $ProgressPreference = $progress
        }
        Expand-Archive -Path $zip -DestinationPath (Join-Path $tmp 'unpacked') -Force
        $source = Join-Path $tmp 'unpacked\DeskPet'
        if (-not (Test-Path (Join-Path $source 'DeskPet.exe'))) { throw "The zip has no DeskPet\DeskPet.exe." }

        Stop-DeskPet
        Remove-InstallDir | Out-Null
        New-Item -ItemType Directory -Force (Split-Path $dir -Parent) | Out-Null
        Move-Item $source $dir
        Write-Host "Installed to $dir"
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }

    $exe = Join-Path $dir 'DeskPet.exe'
    $shell = New-Object -ComObject WScript.Shell
    $links = @($startMenu)
    if ($env:DESKPET_AUTOSTART -eq '1') { $links += $startup }
    foreach ($path in $links) {
        $link = $shell.CreateShortcut($path)
        $link.TargetPath = $exe
        $link.WorkingDirectory = $dir
        $link.Description = 'DeskPet'
        $link.Save()
        Write-Host "Shortcut: $path"
    }

    if ($env:DESKPET_NO_LAUNCH -ne '1') {
        Start-Process -FilePath $exe -WorkingDirectory $dir
        Write-Host "Started. Look for the pet icon in the notification area."
    }
}

Invoke-DeskPetSetup -Uninstall:($env:DESKPET_UNINSTALL -eq '1' -or $args -contains '-Uninstall')
