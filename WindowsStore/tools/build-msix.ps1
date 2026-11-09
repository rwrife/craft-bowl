param(
    [Parameter(Mandatory = $true)]
    [string]$PackageVersion,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9.-]{3,50}$')]
    [string]$IdentityName,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Publisher,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PublisherDisplayName,
    [string]$RepositoryRoot,
    [string]$WindowsSdkBin
)

$ErrorActionPreference = 'Stop'
if (-not $RepositoryRoot) {
    $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
if ($PackageVersion -cnotmatch '^[1-9][0-9]{0,4}\.(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})\.0$') {
    throw 'PackageVersion must use X.Y.Z.0, with X at least 1.'
}
foreach ($part in $PackageVersion.Split('.')) {
    if ([int]$part -gt 65535) { throw 'Package version components must not exceed 65535.' }
}
if ([string]::IsNullOrWhiteSpace($Publisher) -or [string]::IsNullOrWhiteSpace($PublisherDisplayName)) {
    throw 'Publisher and PublisherDisplayName must match the non-empty Partner Center identity values.'
}

if (-not $WindowsSdkBin) {
    $sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $sdk = Get-ChildItem $sdkRoot -Directory |
        Where-Object {
            $_.Name -match '^10\.0\.\d+\.\d+$' -and
            (Test-Path (Join-Path $_.FullName 'x64\makeappx.exe')) -and
            (Test-Path (Join-Path $_.FullName 'x64\makepri.exe'))
        } |
        Sort-Object { [version]$_.Name } -Descending |
        Select-Object -First 1
    if ($null -eq $sdk) { throw 'Install a Windows 10/11 SDK containing MakeAppx.exe and MakePri.exe.' }
    $WindowsSdkBin = Join-Path $sdk.FullName 'x64'
}
$makeAppx = Join-Path $WindowsSdkBin 'makeappx.exe'
$makePri = Join-Path $WindowsSdkBin 'makepri.exe'
foreach ($tool in @($makeAppx, $makePri)) {
    if (-not (Test-Path $tool)) { throw "Missing Windows SDK tool: $tool" }
}

$export = Join-Path $RepositoryRoot 'build\windows'
foreach ($file in @('BlockBowl.exe', 'BlockBowl.pck', 'App\BlockBowlLogo.obj')) {
    $path = Join-Path $export $file
    if (-not (Test-Path $path) -or (Get-Item $path).Length -eq 0) {
        throw "Export the Windows Store preset before packaging; missing $path."
    }
}
$output = Join-Path $RepositoryRoot 'build\store'
$staging = Join-Path $output 'package'
if (Test-Path $staging) {
    throw "Package staging directory already exists: $staging. Remove it before rebuilding."
}
$assets = Join-Path $staging 'Assets'
New-Item -ItemType Directory -Path $assets -Force | Out-Null
Copy-Item (Join-Path $export '*') -Destination $staging -Recurse

Add-Type -AssemblyName System.Drawing
$source = [System.Drawing.Image]::FromFile(
    (Join-Path $RepositoryRoot 'WindowsStore\icons\Square150x150Logo.png')
)
try {
    foreach ($asset in @(
        @{ Name = 'StoreLogo.png'; Size = 50 },
        @{ Name = 'Square44x44Logo.png'; Size = 44 },
        @{ Name = 'Square150x150Logo.png'; Size = 150 }
    )) {
        $bitmap = [System.Drawing.Bitmap]::new($asset.Size, $asset.Size)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.DrawImage($source, 0, 0, $asset.Size, $asset.Size)
            $bitmap.Save((Join-Path $assets $asset.Name), [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $graphics.Dispose()
            $bitmap.Dispose()
        }
    }
}
finally { $source.Dispose() }

$manifest = [System.Xml.XmlDocument]::new()
$manifest.Load((Join-Path $RepositoryRoot 'WindowsStore\AppxManifest.xml'))
$identity = $manifest.Package.Identity
$identity.SetAttribute('Name', $IdentityName)
$identity.SetAttribute('Publisher', $Publisher)
$identity.SetAttribute('Version', $PackageVersion)
$manifest.Package.Properties['PublisherDisplayName'].InnerText = $PublisherDisplayName
$manifestPath = Join-Path $staging 'AppxManifest.xml'
$manifest.Save($manifestPath)

$priConfig = Join-Path $output 'priconfig.xml'
& $makePri createconfig /cf $priConfig /dq en-US /o
if ($LASTEXITCODE -ne 0) { throw 'MakePri configuration failed.' }
& $makePri new /pr $staging /cf $priConfig /mn $manifestPath /of (Join-Path $staging 'resources.pri') /o
if ($LASTEXITCODE -ne 0) { throw 'MakePri resource indexing failed.' }

$package = Join-Path $output "BlockBowl_${PackageVersion}_x64.msix"
& $makeAppx pack /d $staging /p $package /h SHA256 /o
if ($LASTEXITCODE -ne 0) { throw 'MakeAppx packaging or manifest validation failed.' }
if (-not (Test-Path $package) -or (Get-Item $package).Length -eq 0) {
    throw 'MakeAppx did not produce a non-empty MSIX.'
}
Write-Output "Store submission package: $package"
