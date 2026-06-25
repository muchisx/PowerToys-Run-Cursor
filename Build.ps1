$ErrorActionPreference = "Stop"

[xml]$xml = Get-Content -Path "$PSScriptRoot\Directory.Build.Props"
$version = $xml.Project.PropertyGroup.Version

# The PowerToys reference assemblies are not redistributed in this repo (see .gitignore).
# Bootstrap them from a local PowerToys installation for the host architecture so the build is self-contained.
function Initialize-Libs
{
    param([string]$Platform)

    $libsDir = "$PSScriptRoot\Community.PowerToys.Run.Plugin.VisualStudio\Libs\$Platform"
    $required = @(
        "PowerToys.Common.UI.dll",
        "PowerToys.ManagedCommon.dll",
        "PowerToys.Settings.UI.Lib.dll",
        "Wox.Infrastructure.dll",
        "Wox.Plugin.dll"
    )

    if (-not ($required | Where-Object { -not (Test-Path (Join-Path $libsDir $_)) }))
    {
        return $true
    }

    # Only the reference assemblies matching the host architecture can be sourced from a local install.
    $hostPlatform = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "ARM64" } else { "x64" }
    if ($Platform -ne $hostPlatform)
    {
        Write-Warning "Reference assemblies for $Platform are missing and the host ($hostPlatform) cannot supply them. Skipping $Platform."
        return $false
    }

    $ptDir = @("$env:LOCALAPPDATA\PowerToys", "$env:ProgramFiles\PowerToys", "${env:ProgramFiles(x86)}\PowerToys") |
        Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $ptDir)
    {
        Write-Warning "Reference assemblies for $Platform are missing and no PowerToys installation was found to copy them from. Skipping $Platform."
        return $false
    }

    New-Item -ItemType Directory -Force -Path $libsDir | Out-Null
    foreach ($dll in $required)
    {
        $src = Join-Path $ptDir $dll
        if (Test-Path $src)
        {
            Copy-Item -Path $src -Destination $libsDir -Force
        }
    }

    $stillMissing = $required | Where-Object { -not (Test-Path (Join-Path $libsDir $_)) }
    if ($stillMissing)
    {
        Write-Warning "Could not locate these reference assemblies in '$ptDir': $($stillMissing -join ', '). Skipping $Platform."
        return $false
    }

    Write-Host "Populated reference assemblies in '$libsDir' from '$ptDir'."
    return $true
}

foreach ($platform in "ARM64", "x64")
{
    if (-not (Initialize-Libs -Platform $platform))
    {
        continue
    }

    if (Test-Path -Path "$PSScriptRoot\Community.PowerToys.Run.Plugin.VisualStudio\bin")
    {
        Remove-Item -Path "$PSScriptRoot\Community.PowerToys.Run.Plugin.VisualStudio\bin\*" -Recurse
    }

    if (Test-Path -Path "$PSScriptRoot\Community.PowerToys.Run.Plugin.VisualStudio\obj")
    {
        Remove-Item -Path "$PSScriptRoot\Community.PowerToys.Run.Plugin.VisualStudio\obj\*" -Recurse
    }

    dotnet build $PSScriptRoot\Community.PowerToys.Run.Plugin.VisualStudio.sln -c Release /p:Platform=$platform

    Remove-Item -Path "$PSScriptRoot\Community.PowerToys.Run.Plugin.VisualStudio\bin\*" -Recurse -Include *.xml, *.pdb, PowerToys.*, Wox.*
    Rename-Item -Path "$PSScriptRoot\Community.PowerToys.Run.Plugin.VisualStudio\bin\$platform\Release" -NewName "Cursor"

    Compress-Archive -Path "$PSScriptRoot\Community.PowerToys.Run.Plugin.VisualStudio\bin\$platform\Cursor" -DestinationPath "$PSScriptRoot\Cursor-$version-$platform.zip" -Force
}
