<#
    Daily pipeline run: pull today's prices from TCGCSV, then rebuild the warehouse.

    Run by Windows Task Scheduler. Writes a dated log to logs/ and exits non-zero
    on failure so Task Scheduler's "Last Run Result" shows the problem.

    Manual invocation:
        .\daily_run.ps1

    Note: this runs a full `dbt build` with no selector. Staging is materialized
    as a table, so a narrower selector would leave the fact model reading stale
    staging and silently inserting nothing. See DECISIONS 006.
#>

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir      = Join-Path $ProjectRoot "logs"
$LogFile     = Join-Path $LogDir ("run_{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-Log {
    param([string]$Message)
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

$exitCode = 0

try {
    Set-Location $ProjectRoot
    Write-Log "=== run start ==="

    # --- activate the virtual environment -------------------------------
    $activate = Join-Path $ProjectRoot ".venv\Scripts\Activate.ps1"
    if (-not (Test-Path $activate)) {
        throw "Virtual environment not found at $activate"
    }
    & $activate
    Write-Log "venv activated"

    # --- extract --------------------------------------------------------
    # TCGCSV publishes on a lag, so pull the last three days rather than just
    # today. The script skips partitions that already exist, making this cheap
    # and self-healing after a missed run.
    $start = (Get-Date).AddDays(-3).ToString("yyyy-MM-dd")
    $end   = (Get-Date).ToString("yyyy-MM-dd")

    Write-Log "extract: $start to $end"
    $extract = & python "extract\fetch_tcgcsv.py" prices --start $start --end $end 2>&1
    $extract | ForEach-Object { Add-Content -Path $LogFile -Value "    $_" }
    if ($LASTEXITCODE -ne 0) { throw "extract failed with exit code $LASTEXITCODE" }
    Write-Log "extract complete"

    # --- transform ------------------------------------------------------
    Set-Location (Join-Path $ProjectRoot "analytics")

    Write-Log "dbt build"
    $build = & dbt build 2>&1
    $build | ForEach-Object { Add-Content -Path $LogFile -Value "    $_" }
    $buildExit = $LASTEXITCODE

    # dbt exit codes: 0 = success, 1 = error, 2 = warnings only.
    # Warnings are expected here (the pct_change bounds tests fire on a small
    # genuine tail), so 2 is not a failure.
    if ($buildExit -eq 1) { throw "dbt build failed" }
    if ($buildExit -eq 2) { Write-Log "dbt build completed with warnings" }
    else                  { Write-Log "dbt build complete" }

    # --- freshness ------------------------------------------------------
    # Reports rather than throws: a stale source means TCGCSV stopped publishing,
    # which is worth knowing but is not a failure of this run.
    Write-Log "source freshness"
    $fresh = & dbt source freshness 2>&1
    $fresh | ForEach-Object { Add-Content -Path $LogFile -Value "    $_" }
    if ($LASTEXITCODE -ne 0) { Write-Log "WARNING: source freshness reported a problem" }

    Write-Log "=== run complete ==="
}
catch {
    Write-Log "FAILED: $_"
    $exitCode = 1
}
finally {
    # Keep 30 days of logs.
    Get-ChildItem $LogDir -Filter "run_*.log" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip 30 |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

exit $exitCode