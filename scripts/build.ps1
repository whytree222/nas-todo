[CmdletBinding()]
param(
    [ValidateSet('Check', 'Android', 'Windows', 'All')]
    [string] $Target = 'Check'
)

$ErrorActionPreference = 'Stop'
$projectDirectory = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$clientDirectory = Join-Path $projectDirectory 'client'

if (-not (Test-Path -LiteralPath (Join-Path $clientDirectory 'pubspec.yaml'))) {
    throw "Cannot find client/pubspec.yaml under $projectDirectory."
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter is not on PATH. Install Flutter stable and run flutter doctor -v.'
}
$testPythonCommand = if ([string]::IsNullOrWhiteSpace($env:NAS_TODO_TEST_PYTHON)) { 'python' } else { $env:NAS_TODO_TEST_PYTHON }
if (-not (Get-Command -Name $testPythonCommand -ErrorAction SilentlyContinue)) {
    throw 'Python is required for the integration tests. Install Python 3.12+ or set NAS_TODO_TEST_PYTHON.'
}
& $testPythonCommand -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)'
if ($LASTEXITCODE -ne 0) {
    throw 'The integration tests require Python 3.12 or newer.'
}
if (($Target -eq 'Windows' -or $Target -eq 'All') -and $env:OS -ne 'Windows_NT') {
    throw 'Build Windows on a Windows host with Visual Studio C++ tools.'
}

function Invoke-Flutter {
    param([Parameter(Mandatory)][string[]] $Arguments)
    & flutter @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter failed with exit code ${LASTEXITCODE}: flutter $($Arguments -join ' ')"
    }
}

Push-Location -LiteralPath $clientDirectory
try {
    if ($Target -eq 'Android' -or $Target -eq 'All') {
        if (-not (Test-Path -LiteralPath 'android')) {
            throw 'Android platform files are missing. Read docs/BUILD.md before generating platforms.'
        }
    }
    if ($Target -eq 'Windows' -or $Target -eq 'All') {
        if (-not (Test-Path -LiteralPath 'windows')) {
            throw 'Windows platform files are missing. Read docs/BUILD.md before generating platforms.'
        }
    }

    Invoke-Flutter -Arguments @('pub', 'get')
    Invoke-Flutter -Arguments @('analyze')
    Invoke-Flutter -Arguments @('test')

    if ($Target -eq 'Android' -or $Target -eq 'All') {
        Invoke-Flutter -Arguments @('build', 'apk', '--debug')
        Write-Host "Test APK: $(Join-Path $clientDirectory 'build/app/outputs/flutter-apk/app-debug.apk')"
    }
    if ($Target -eq 'Windows' -or $Target -eq 'All') {
        Invoke-Flutter -Arguments @('build', 'windows', '--release')
        Copy-Item -LiteralPath 'windows/desktop-widget.cmd' -Destination 'build/windows/x64/runner/Release/desktop-widget.cmd'
        Write-Host "Copy this entire directory: $(Join-Path $clientDirectory 'build/windows/x64/runner/Release')"
    }
    Write-Host 'Checks completed successfully.'
}
finally {
    Pop-Location
}
