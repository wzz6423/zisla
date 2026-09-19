[CmdletBinding()]
param(
    [ValidateSet("x64", "ARM64")]
    [string]$Architecture = "x64",

    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",

    [string]$BuildRoot = "",

    [switch]$Clean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    throw "CMake is required to build the vendored QPDF dependencies."
}

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($BuildRoot)) {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw "LOCALAPPDATA is required when BuildRoot is not provided."
    }
    $BuildRoot = Join-Path $env:LOCALAPPDATA (
        Join-Path "zisla\build\qpdf" "$Architecture\$Configuration")
}
$BuildRoot = [System.IO.Path]::GetFullPath($BuildRoot)
$prefix = Join-Path $BuildRoot "prefix"

if ($Clean -and (Test-Path -LiteralPath $BuildRoot)) {
    Remove-Item -LiteralPath $BuildRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null

function Invoke-CMake {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & cmake @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "CMake failed: cmake $($Arguments -join ' ')"
    }
}

function Configure-And-Install {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string[]]$Options
    )

    $build = Join-Path $BuildRoot $Name
    Invoke-CMake -Arguments (@(
        "-S", $Source,
        "-B", $build,
        "-A", $Architecture,
        "-DCMAKE_INSTALL_PREFIX=$prefix",
        "-DCMAKE_INSTALL_LIBDIR=lib"
    ) + $Options)
    Invoke-CMake -Arguments @(
        "--build", $build,
        "--config", $Configuration,
        "--target", "install",
        "--parallel"
    )
}

$vendorRoot = Join-Path $repositoryRoot "Vendor"
Configure-And-Install -Name "zlib" -Source (Join-Path $vendorRoot "zlib\1.3.2") -Options @(
    "-DZLIB_BUILD_SHARED=OFF",
    "-DZLIB_BUILD_STATIC=ON",
    "-DZLIB_BUILD_TESTING=OFF",
    "-DZLIB_INSTALL=ON"
)
Configure-And-Install -Name "libjpeg-turbo" -Source (Join-Path $vendorRoot "libjpeg-turbo\3.2.0") -Options @(
    "-DENABLE_SHARED=OFF",
    "-DENABLE_STATIC=ON",
    "-DWITH_TURBOJPEG=OFF",
    "-DWITH_TESTS=OFF",
    "-DWITH_TOOLS=OFF",
    "-DWITH_JPEG8=ON",
    "-DWITH_CRT_DLL=ON",
    "-DCMAKE_PREFIX_PATH=$prefix"
)
Configure-And-Install -Name "qpdf" -Source (Join-Path $vendorRoot "qpdf\12.3.2") -Options @(
    "-DBUILD_SHARED_LIBS=OFF",
    "-DBUILD_STATIC_LIBS=ON",
    "-DBUILD_DOC=OFF",
    "-DINSTALL_MANUAL=OFF",
    "-DINSTALL_EXAMPLES=OFF",
    "-DUSE_IMPLICIT_CRYPTO=OFF",
    "-DREQUIRE_CRYPTO_NATIVE=ON",
    "-DCMAKE_PREFIX_PATH=$prefix",
    "-DZLIB_H_PATH=$(Join-Path $prefix 'include')",
    "-DZLIB_LIB_PATH=$(Join-Path $prefix ('lib\' + $(if ($Configuration -eq 'Debug') { 'zsd.lib' } else { 'zs.lib' })))",
    "-DLIBJPEG_H_PATH=$(Join-Path $prefix 'include')",
    "-DLIBJPEG_LIB_PATH=$(Join-Path $prefix 'lib\jpeg-static.lib')"
)

$packageDirectory = Join-Path $prefix "lib\cmake\qpdf"
if (-not (Test-Path -LiteralPath (Join-Path $packageDirectory "qpdfConfig.cmake"))) {
    throw "The fixed QPDF package was not installed to $packageDirectory."
}

Write-Host "QPDF package directory: $packageDirectory"
