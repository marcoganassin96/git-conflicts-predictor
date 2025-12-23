# PowerShell wrapper that prepends a bundled win32 binaries folder to PATH (session-only)
# and then invokes the POSIX shell script using available bash (Git Bash).
param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [String[]]$Args
)

function Find-Bash {
    # Prefer bash available in PATH
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if ($bash) { return $bash.Path }

    # Common Git for Windows locations
    $possible = @(
        "$Env:ProgramFiles\Git\bin\bash.exe",
        "$Env:ProgramFiles(x86)\Git\bin\bash.exe",
        "$Env:LocalAppData\Programs\Git\bin\bash.exe"
    )
    foreach ($p in $possible) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$bundleBin = Join-Path $scriptDir "bin\win32"

if (Test-Path $bundleBin) {
    # Prepend bundled bin to PATH for this session only
    $env:PATH = "$bundleBin;$env:PATH"
    Write-Verbose "Added bundled binaries to PATH: $bundleBin"
}

$bashPath = Find-Bash
if (-not $bashPath) {
    Write-Error "bash not found. Please install Git for Windows (Git Bash) and ensure bash is available in PATH." -ErrorAction Stop
}

$scriptPath = Join-Path $scriptDir "bin\conflicts_relevator.sh"

# Execute the POSIX shell script under bash with forwarded arguments
& $bashPath $scriptPath @Args
