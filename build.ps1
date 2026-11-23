<#
.SYNOPSIS
    Build, test, and publish script for xDPsApiExplorer utilizing PoshCode ModuleBuilder and Pester 6.x.

.DESCRIPTION
    Designed for local development and CI/CD release pipelines:
    - Clean   : Removes the ./output directory.
    - Build   : Compiles the module using PoshCode ModuleBuilder (Build-Module) from ./xDPsApiExplorer/build.psd1.
    - Sign    : Digitally signs the compiled .psm1 and .psd1 files with the xDlabs Certum Code Signing certificate.
    - Test    : Runs Pester 6.x unit tests (including Authenticode signature verification) against ./output/xDPsApiExplorer/<Version>.
    - Publish : Publishes the signed compiled module to PowerShell Gallery using -ApiKey (or $env:PSGALLERY_API_KEY).

.EXAMPLE
    ./build.ps1 -Task Clean, Build, Sign, Test

.EXAMPLE
    ./build.ps1 -Task Clean, Build, Sign, Test, Publish -SemVer 1.0.3
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Clean', 'Build', 'Sign', 'Test', 'Publish')]
    [string[]]$Task = @('Build', 'Sign', 'Test'),

    [Parameter(Mandatory = $false)]
    [string]$SemVer,

    [Parameter(Mandatory = $false)]
    [string]$CertThumbprint = '36B7A51BCAE481C66ACECF4F7CF7BADAEA7D8D81',

    [Parameter(Mandatory = $false)]
    [string]$TimestampServer = 'http://time.certum.pl',

    [Parameter(Mandatory = $false)]
    [string]$ApiKey = $(
        if (-not [string]::IsNullOrWhiteSpace($env:PSGALLERY_API_KEY)) {
            $env:PSGALLERY_API_KEY
        } elseif (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('PSGALLERY_API_KEY', 'User'))) {
            [Environment]::GetEnvironmentVariable('PSGALLERY_API_KEY', 'User')
        } else {
            [Environment]::GetEnvironmentVariable('PSGALLERY_API_KEY', 'Machine')
        }
    ),

    [Parameter(Mandatory = $false)]
    [string]$TestResultPath = (Join-Path $PSScriptRoot 'output\TestResults.xml')
)

$ErrorActionPreference = 'Stop'

$sourceBuildFile = Join-Path $PSScriptRoot 'xDPsApiExplorer\build.psd1'
$outputRoot      = Join-Path $PSScriptRoot 'output'
$testsPath       = Join-Path $PSScriptRoot 'Tests\xDPsApiExplorer.Tests.ps1'
$builtModuleInfo = $null

function Get-LatestBuiltModuleDirectory {
    $modBase = Join-Path $outputRoot 'xDPsApiExplorer'
    if (-not (Test-Path -LiteralPath $modBase)) {
        return $null
    }
    $latestManifest = Get-ChildItem -Path $modBase -Filter 'xDPsApiExplorer.psd1' -Recurse |
        Sort-Object { [version](Split-Path $_.DirectoryName -Leaf) } -Descending |
        Select-Object -First 1
    if ($null -ne $latestManifest) {
        return $latestManifest.DirectoryName
    }
    return $null
}

if ($Task -contains 'Clean') {
    Write-Host '==> [Clean] Removing output directory...' -ForegroundColor Cyan
    if (Test-Path -LiteralPath $outputRoot) {
        Remove-Item -LiteralPath $outputRoot -Recurse -Force
    }
}

if ($Task -contains 'Build') {
    Write-Host '==> [Build] Building xDPsApiExplorer with PoshCode ModuleBuilder...' -ForegroundColor Cyan
    if (-not (Get-Module -ListAvailable -Name ModuleBuilder)) {
        Write-Host 'Installing ModuleBuilder from PSGallery...' -ForegroundColor Yellow
        Install-Module -Name ModuleBuilder -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module ModuleBuilder -Force

    $buildParams = @{
        SourcePath = $sourceBuildFile
        Passthru   = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($SemVer)) {
        $buildParams['SemVer'] = $SemVer
        $sourceManifest = Join-Path $PSScriptRoot 'xDPsApiExplorer\xDPsApiExplorer.psd1'
        if (Test-Path -LiteralPath $sourceManifest) {
            $baseVer = ($SemVer -split '-')[0]
            $rawPsd1 = [System.IO.File]::ReadAllText($sourceManifest, [System.Text.Encoding]::UTF8)
            $updatedPsd1 = $rawPsd1 -replace "(ModuleVersion\s*=\s*')[^']+(')", "`${1}$baseVer`${2}"
            [System.IO.File]::WriteAllText($sourceManifest, $updatedPsd1, [System.Text.Encoding]::UTF8)
        }
    }

    $builtModuleInfo = Build-Module @buildParams
    Write-Host "    Built module: $($builtModuleInfo.Name) v$($builtModuleInfo.Version) -> $($builtModuleInfo.ModuleBase)" -ForegroundColor Green
}

if ($Task -contains 'Sign') {
    Write-Host '==> [Sign] Signing compiled module with xDlabs Code Signing Certificate...' -ForegroundColor Cyan
    $targetDir = if ($null -ne $builtModuleInfo) {
        $builtModuleInfo.ModuleBase
    } else {
        Get-LatestBuiltModuleDirectory
    }

    if ([string]::IsNullOrWhiteSpace($targetDir) -or -not (Test-Path -LiteralPath $targetDir)) {
        throw 'Built module directory not found in ./output. Run with -Task Build first.'
    }

    $cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue |
        Where-Object { $_.Thumbprint -eq $CertThumbprint -or $_.Subject -like '*xDlabs Grzegorz Kulikowski*' } |
        Select-Object -First 1

    if ($null -eq $cert) {
        throw "Code Signing Certificate ($CertThumbprint / xDlabs Grzegorz Kulikowski) was not found in Cert:\CurrentUser\My. Ensure SimplySign Desktop is running and connected."
    }
    if (-not $cert.HasPrivateKey) {
        throw "Code Signing Certificate '$($cert.Subject)' does not have an active private key handle. Ensure SimplySign Desktop is logged in."
    }

    $filesToSign = Get-ChildItem -Path $targetDir -Include '*.psm1', '*.psd1', '*.ps1' -Recurse -File
    foreach ($file in $filesToSign) {
        Write-Host "    Signing $($file.Name) [Thumbprint: $($cert.Thumbprint)]..." -ForegroundColor Cyan
        $sigResult = Set-AuthenticodeSignature `
            -FilePath $file.FullName `
            -Certificate $cert `
            -TimestampServer $TimestampServer `
            -HashAlgorithm SHA256 `
            -IncludeChain All

        if ($sigResult.Status -ne 'Valid') {
            throw "Authenticode signing failed for '$($file.FullName)': $($sigResult.Status) - $($sigResult.StatusMessage)"
        }
        Write-Host "    Verified signature on $($file.Name): $($sigResult.Status) ($($sigResult.SignerCertificate.Subject))" -ForegroundColor Green
    }
}

if ($Task -contains 'Test') {
    Write-Host '==> [Test] Running Pester 6.x unit tests...' -ForegroundColor Cyan
    $pesterMod = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -ge 6 } | Select-Object -First 1
    if ($null -eq $pesterMod) {
        Write-Host 'Installing Pester 6.x from PSGallery...' -ForegroundColor Yellow
        Install-Module -Name Pester -MinimumVersion 6.0.0 -Scope CurrentUser -Force -SkipPublisherCheck
    }
    Import-Module Pester -MinimumVersion 6.0.0 -Force

    $pesterConfig = New-PesterConfiguration
    $pesterConfig.Run.Path = $testsPath
    $pesterConfig.Run.PassThru = $true
    $pesterConfig.Run.Exit = $false
    $pesterConfig.Output.Verbosity = 'Detailed'

    if (-not [string]::IsNullOrWhiteSpace($TestResultPath)) {
        $testResultDir = Split-Path -Path $TestResultPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($testResultDir) -and -not (Test-Path -LiteralPath $testResultDir)) {
            New-Item -ItemType Directory -Path $testResultDir -Force | Out-Null
        }
        $pesterConfig.TestResult.Enabled = $true
        $pesterConfig.TestResult.OutputFormat = 'JUnitXml'
        $pesterConfig.TestResult.OutputPath = $TestResultPath
    }

    $testResult = Invoke-Pester -Configuration $pesterConfig
    if ($testResult.FailedCount -gt 0 -or $testResult.Result -ne 'Passed') {
        throw "Pester unit tests failed ($($testResult.FailedCount) failed)."
    }
    Write-Host "    All $($testResult.PassedCount) Pester 6.x unit tests passed!" -ForegroundColor Green
}

if ($Task -contains 'Publish') {
    Write-Host '==> [Publish] Publishing built module to PowerShell Gallery...' -ForegroundColor Cyan
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        throw 'Cannot publish: NuGet API key was not provided via -ApiKey or $env:PSGALLERY_API_KEY.'
    }

    $targetDir = if ($null -ne $builtModuleInfo) {
        $builtModuleInfo.ModuleBase
    } else {
        Get-LatestBuiltModuleDirectory
    }

    if ([string]::IsNullOrWhiteSpace($targetDir) -or -not (Test-Path -LiteralPath $targetDir)) {
        throw 'Built module directory not found in ./output. Run with -Task Build first.'
    }

    Write-Host "    Publishing from: $targetDir" -ForegroundColor Cyan
    Publish-Module -Path $targetDir -NuGetApiKey $ApiKey -Verbose
    Write-Host '    Successfully published xDPsApiExplorer to PowerShell Gallery!' -ForegroundColor Green
}
