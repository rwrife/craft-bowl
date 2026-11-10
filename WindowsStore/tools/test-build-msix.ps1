$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) "block-bowl-msix-test-$([guid]::NewGuid())"
$parameters = @{
    RepositoryRoot = $fixture
    PackageVersion = '1.2.3.0'
    IdentityName = 'Infinityball.BlockBowl'
    Publisher = 'CN=874CA4CF-90B8-4C53-AFBC-CCAC42030583'
    PublisherDisplayName = 'Infinityball'
}

function Assert-PackagingRejected {
    param([string]$ExpectedMessage)
    try {
        & "$PSScriptRoot\build-msix.ps1" @parameters -Architecture arm64
    }
    catch {
        if ($_.Exception.Message -notlike $ExpectedMessage) { throw }
        return
    }
    throw "Packaging should have failed: $ExpectedMessage"
}

try {
    $icons = Join-Path $fixture 'WindowsStore\icons'
    New-Item -ItemType Directory -Path $icons -Force | Out-Null
    Copy-Item (Join-Path $repository 'WindowsStore\AppxManifest.xml') (Join-Path $fixture 'WindowsStore')
    Copy-Item (Join-Path $repository 'WindowsStore\icons\Square150x150Logo.png') $icons
    foreach ($architecture in @('x64', 'arm64')) {
        $suffix = if ($architecture -eq 'x64') { '' } else { '-arm64' }
        $export = Join-Path $fixture "build\windows$suffix"
        New-Item -ItemType Directory -Path (Join-Path $export 'App') -Force | Out-Null
        # A synthetic PE header tests packaging metadata without running a game.
        $header = [byte[]]::new(128)
        [BitConverter]::GetBytes([uint16]0x5A4D).CopyTo($header, 0)
        [BitConverter]::GetBytes([uint32]64).CopyTo($header, 0x3C)
        [BitConverter]::GetBytes([uint32]0x00004550).CopyTo($header, 64)
        $machine = if ($architecture -eq 'x64') { 0x8664 } else { 0xAA64 }
        [BitConverter]::GetBytes([uint16]$machine).CopyTo($header, 68)
        [System.IO.File]::WriteAllBytes((Join-Path $export 'BlockBowl.exe'), $header)
        Set-Content (Join-Path $export 'BlockBowl.pck') "fixture-$architecture"
        Set-Content (Join-Path $export 'App\BlockBowlLogo.obj') 'fixture-logo'
    }

    $armExecutable = Join-Path $fixture 'build\windows-arm64\BlockBowl.exe'
    $armHeader = [System.IO.File]::ReadAllBytes($armExecutable)
    Copy-Item (Join-Path $fixture 'build\windows\BlockBowl.exe') $armExecutable -Force
    Assert-PackagingRejected '*architecture does not match arm64*'
    [System.IO.File]::WriteAllBytes($armExecutable, [byte[]]::new(4))
    Assert-PackagingRejected '*valid DOS header*'
    $invalidOffset = $armHeader.Clone()
    [BitConverter]::GetBytes([uint32]4096).CopyTo($invalidOffset, 0x3C)
    [System.IO.File]::WriteAllBytes($armExecutable, $invalidOffset)
    Assert-PackagingRejected '*invalid PE header offset*'
    $invalidSignature = $armHeader.Clone()
    $invalidSignature[64] = 0
    [System.IO.File]::WriteAllBytes($armExecutable, $invalidSignature)
    Assert-PackagingRejected '*valid PE signature*'
    [System.IO.File]::WriteAllBytes($armExecutable, $armHeader)

    # Omitting Architecture must retain the existing x64 paths and package name.
    & "$PSScriptRoot\build-msix.ps1" @parameters
    & "$PSScriptRoot\build-msix.ps1" @parameters -Architecture arm64
    Assert-PackagingRejected '*staging directory already exists*'

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    foreach ($architecture in @('x64', 'arm64')) {
        $package = Join-Path $fixture "build\store\BlockBowl_1.2.3.0_$architecture.msix"
        $archive = [System.IO.Compression.ZipFile]::OpenRead($package)
        try {
            $reader = [System.IO.StreamReader]::new($archive.GetEntry('AppxManifest.xml').Open())
            try { [xml]$manifest = $reader.ReadToEnd() }
            finally { $reader.Dispose() }
            if ($manifest.Package.Identity.ProcessorArchitecture -cne $architecture -or
                $manifest.Package.Identity.Version -ne '1.2.3.0') {
                throw "Incorrect package identity for $architecture."
            }
            $reader = [System.IO.StreamReader]::new($archive.GetEntry('BlockBowl.pck').Open())
            try { $content = $reader.ReadToEnd().Trim() }
            finally { $reader.Dispose() }
            if ($content -ne "fixture-$architecture") {
                throw "Package used the wrong export directory for $architecture."
            }
            foreach ($file in @('BlockBowl.exe', 'App/BlockBowlLogo.obj', 'resources.pri',
                'Assets/StoreLogo.png', 'Assets/Square44x44Logo.png', 'Assets/Square150x150Logo.png')) {
                if ($null -eq $archive.GetEntry($file)) {
                    throw "Package is missing $file for $architecture."
                }
            }
        }
        finally { $archive.Dispose() }
    }
    Write-Output 'MSIX packaging tests passed for x64 and ARM64, including architecture mismatch and invalid PE rejection.'
}
finally {
    if (Test-Path $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
