[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:MissingRequired = 0
$script:PythonExecutable = $null

function Write-Status {
    param(
        [string]$Name,
        [bool]$Found,
        [string]$Details,
        [bool]$Required = $true
    )

    if ($Found) {
        Write-Host ("[OK]      {0}: {1}" -f $Name, $Details) -ForegroundColor Green
        return
    }

    if ($Required) {
        $script:MissingRequired++
        Write-Host ("[MISSING] {0}: {1}" -f $Name, $Details) -ForegroundColor Red
    }
    else {
        Write-Host ("[INFO]    {0}: {1}" -f $Name, $Details) -ForegroundColor Yellow
    }
}

function Test-CommandVersion {
    param(
        [string]$Name,
        [string[]]$Commands,
        [string[]]$Arguments = @('--version'),
        [bool]$Required = $true
    )

    foreach ($commandName in $Commands) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $version = ''
            try {
                $version = (& $command.Source @Arguments 2>&1 | Select-Object -First 1 | Out-String).Trim()
            }
            catch {
                $version = 'found, version command failed'
            }
            if ([string]::IsNullOrWhiteSpace($version)) {
                $version = 'found'
            }
            Write-Status -Name $Name -Found $true -Details $version -Required $Required
            return $true
        }
    }

    Write-Status -Name $Name -Found $false -Details ('not found; tried ' + ($Commands -join ', ')) -Required $Required
    return $false
}

function Test-PythonModule {
    param(
        [string]$Name,
        [string]$Module,
        [bool]$Required = $true
    )

    $python = $null
    if ($null -ne $script:PythonExecutable) {
        $python = Get-Command $script:PythonExecutable -ErrorAction SilentlyContinue
    }
    if ($null -eq $python) {
        $python = Get-Command python -ErrorAction SilentlyContinue
    }
    if ($null -eq $python) {
        $python = Get-Command py -ErrorAction SilentlyContinue
    }
    if ($null -eq $python) {
        Write-Status -Name $Name -Found $false -Details 'Python is not available' -Required $Required
        return
    }

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath $python.Source `
            -ArgumentList @('-c', "import $Module") `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath
        Write-Status -Name $Name -Found ($process.ExitCode -eq 0) -Details ('Python module ' + $Module) -Required $Required
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-PythonVersion {
    $minimumVersion = [version]'3.11'
    $belowMinimum = @()

    foreach ($commandName in @('python', 'py')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($null -eq $command) {
            continue
        }

        $versionOutput = (& $command.Source --version 2>&1 | Out-String).Trim()
        $match = [regex]::Match($versionOutput, 'Python\s+(\d+)\.(\d+)(?:\.(\d+))?')
        if (-not $match.Success) {
            $belowMinimum += ($commandName + ': version unavailable')
            continue
        }

        $patch = 0
        if ($match.Groups[3].Success) {
            $patch = [int]$match.Groups[3].Value
        }
        $version = [version]::new([int]$match.Groups[1].Value, [int]$match.Groups[2].Value, $patch)
        if ($version -ge $minimumVersion) {
            $script:PythonExecutable = $command.Source
            Write-Status -Name 'Python' -Found $true -Details ($version.ToString() + ' (minimum 3.11)')
            return $true
        }

        $belowMinimum += ($commandName + ': ' + $version.ToString())
    }

    $details = 'Python 3.11+ required'
    if ($belowMinimum.Count -gt 0) {
        $details += '; found ' + ($belowMinimum -join ', ')
    }
    else {
        $details += '; command not found'
    }
    Write-Status -Name 'Python' -Found $false -Details $details
    return $false
}

Write-Host 'Tang Nano 9K development prerequisites' -ForegroundColor Cyan
Write-Host ('PowerShell: ' + $PSVersionTable.PSVersion)
Write-Host ''

Test-CommandVersion -Name 'Git' -Commands @('git') | Out-Null
Test-PythonVersion | Out-Null
Test-CommandVersion -Name 'Node.js' -Commands @('node') | Out-Null
Test-CommandVersion -Name 'RISC-V GCC' -Commands @('riscv-none-elf-gcc', 'riscv32-unknown-elf-gcc', 'riscv-none-embed-gcc', 'riscv64-elf-gcc') | Out-Null
Test-CommandVersion -Name 'RISC-V objcopy' -Commands @('riscv-none-elf-objcopy', 'riscv32-unknown-elf-objcopy', 'riscv-none-embed-objcopy', 'riscv64-elf-objcopy') | Out-Null
Test-CommandVersion -Name 'Make' -Commands @('make', 'mingw32-make') | Out-Null
Test-CommandVersion -Name 'Verilator' -Commands @('verilator') | Out-Null
Test-CommandVersion -Name 'Icarus Verilog' -Commands @('iverilog') -Arguments @('-V') | Out-Null
Test-CommandVersion -Name 'GTKWave' -Commands @('gtkwave') | Out-Null
Test-CommandVersion -Name 'clang-format' -Commands @('clang-format') -Required $false | Out-Null

Test-PythonModule -Name 'pytest' -Module 'pytest'
Test-PythonModule -Name 'Pillow' -Module 'PIL'

$gowinFound = $false
$gowinDetails = ''
$gowinCandidates = @()
if ($env:GOWIN_EDA_HOME) {
    $gowinCandidates += (Join-Path $env:GOWIN_EDA_HOME 'IDE/bin/gw_sh.exe')
    $gowinCandidates += (Join-Path $env:GOWIN_EDA_HOME 'IDE/bin/programmer.exe')
}
$gowinCandidates += @('gw_sh.exe', 'programmer.exe')
foreach ($candidate in $gowinCandidates) {
    if (Get-Command $candidate -ErrorAction SilentlyContinue) {
        $gowinFound = $true
        $gowinDetails = $candidate
        break
    }
    if (Test-Path -LiteralPath $candidate) {
        $gowinFound = $true
        $gowinDetails = $candidate
        break
    }
}
$gowinStatus = 'manual installation or GOWIN_EDA_HOME required'
if ($gowinFound) {
    $gowinStatus = $gowinDetails
}
Write-Status -Name 'Gowin EDA/Programmer' -Found $gowinFound -Details $gowinStatus

Write-Host ''
if ($script:MissingRequired -eq 0) {
    Write-Host 'All required checks passed.' -ForegroundColor Green
    exit 0
}

Write-Host ("Missing required checks: {0}" -f $script:MissingRequired) -ForegroundColor Red
exit 1
