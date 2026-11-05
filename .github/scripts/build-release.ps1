param(
    [Parameter(Mandatory)]
    [ValidatePattern('^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')]
    [string]$Version
)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '../..')
$root = (Get-Location).Path
$publish = Join-Path $root 'artifacts/publish'
$packages = Join-Path $root 'artifacts/packages'
$msiOutput = Join-Path $root 'artifacts/msi'
$project = 'LotCoMPrinter/LotCoMPrinter.csproj'
if (!(Test-Path '../LotCom-libraries/LotCom/LotCom.csproj')) {
    throw 'Check out LotCom-libraries alongside LotCom-printer before building.'
}
if (Test-Path 'artifacts') { Remove-Item 'artifacts' -Recurse -Force }
New-Item $publish, $packages, $msiOutput -ItemType Directory -Force | Out-Null

# Keep the existing MAUI/WinUI requirements and Windows RID override. Publish performs
# restore with the same properties, avoiding different RIDs between restore and publish.
$properties = @(
    '-p:RuntimeIdentifierOverride=win10-x64',
    '-p:WindowsPackageType=None',
    '-p:WindowsAppSDKSelfContained=true',
    '-p:PublishSingleFile=false',
    "-p:Version=$Version",
    "-p:ApplicationDisplayVersion=$Version.0",
    '-p:ContinuousIntegrationBuild=true'
)
dotnet publish $project --configuration Release --framework net9.0-windows10.0.19041.0 `
    --self-contained true @properties --output $publish
if ($LASTEXITCODE -ne 0) { throw 'MAUI Windows application publish failed.' }
if (!(Test-Path (Join-Path $publish 'LotCoMPrinter.exe'))) {
    throw 'The published application executable is missing.'
}
# Both native runtimes must ship beside this unpackaged MAUI application.
foreach ($native in @('coreclr.dll', 'Microsoft.ui.xaml.dll')) {
    $found = Get-ChildItem $publish -Filter $native -File -Recurse
    if (!$found) { throw "The self-contained publish is missing $native." }
}

# The setup is built outside the payload, with explicit source/output directories.
dotnet build 'installer/LotComPrinter.Setup.csproj' --configuration Release -p:ContinuousIntegrationBuild=true
if ($LASTEXITCODE -ne 0) { throw 'Setup project build failed.' }
& './installer/bin/Release/net472/LotComPrinter.Setup.exe' $Version $publish $msiOutput
if ($LASTEXITCODE -ne 0) { throw 'MSI build failed.' }
$msi = Join-Path $msiOutput "LotComPrinter_$Version.msi"
if (!(Test-Path $msi)) { throw "Expected MSI was not generated: $msi" }
Copy-Item $msi $packages
[IO.Compression.ZipFile]::CreateFromDirectory($publish, (Join-Path $packages "LotComPrinter_${Version}_win-x64.zip"))
$checksums = Get-ChildItem $packages -File | Sort-Object Name | ForEach-Object {
    "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $_.Name
}
$checksums | Set-Content (Join-Path $packages 'SHA256SUMS.txt') -Encoding utf8
