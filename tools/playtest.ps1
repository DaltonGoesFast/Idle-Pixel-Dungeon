# Called by tools\playtest.bat. Run that, not this file.
# Starts one Godot suite, copies stdout and stderr to the console and the log
# as they arrive, and exits with Godot's exit code.
# A pipeline into Tee-Object is not used: Windows PowerShell writes that log as
# UTF-16, and the pipeline can drop the native exit code.
param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Log,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Scene,
    [switch]$Header,
    [int]$Run = 0
)

$ErrorActionPreference = "Stop"
$script:ExitCode = 1

function Write-Both([string]$Line) {
    [Console]::Out.WriteLine($Line)
    if ($null -ne $script:Writer) {
        $script:Writer.WriteLine($Line)
    }
}

function Close-Log {
    if ($null -eq $script:Writer) { return }
    $script:Writer.Flush()
    $script:Writer.Dispose()
    $script:Writer = $null
}

# Read one of Godot's redirected streams on its own thread so a full stderr
# pipe cannot stall the process. The reader is the one .NET already attached;
# a second StreamReader on the same base stream would drop buffered bytes.
function Start-Reader($Reader, $Queue) {
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        param($reader, $queue)
        while ($true) {
            $line = $reader.ReadLine()
            if ($null -eq $line) { break }
            [void]$queue.Enqueue($line)
        }
    }).AddArgument($Reader).AddArgument($Queue)
    return @{ Ps = $ps; Handle = $ps.BeginInvoke(); Rs = $rs }
}

function Stop-Reader($Reader) {
    if ($null -eq $Reader) { return }
    try { [void]$Reader.Ps.EndInvoke($Reader.Handle) } catch {}
    try { $Reader.Ps.Dispose() } catch {}
    try { $Reader.Rs.Close() } catch {}
    try { $Reader.Rs.Dispose() } catch {}
}

function Invoke-Suite([string]$SuiteName, [string]$SuiteScene) {
    Write-Both ("=== " + $SuiteName + " " + $SuiteScene + " ===")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Godot
    # Same command the bat header shows. The scene path has no spaces, so it
    # needs no quotes (Windows PowerShell 5.1 only has this Arguments string).
    $psi.Arguments = "--headless --path . " + $SuiteScene
    $psi.WorkingDirectory = $Root
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    try {
        $utf8 = New-Object System.Text.UTF8Encoding $false
        $psi.StandardOutputEncoding = $utf8
        $psi.StandardErrorEncoding = $utf8
    } catch {
        # Windows PowerShell 5.1 / .NET Framework has no Standard*Encoding.
        # ASCII suite output is unchanged either way.
    }

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $queue = New-Object System.Collections.Concurrent.ConcurrentQueue[string]
    $outReader = $null
    $errReader = $null
    try {
        if (-not $proc.Start()) {
            Write-Both "Failed to start Godot."
            Write-Both ("=== " + $SuiteName + " exit 1 ===")
            Write-Both ""
            return 1
        }
        $outReader = Start-Reader $proc.StandardOutput $queue
        $errReader = Start-Reader $proc.StandardError $queue
        $line = $null
        do {
            while ($queue.TryDequeue([ref]$line)) {
                Write-Both ([string]$line)
            }
            $done = $proc.HasExited -and $outReader.Handle.IsCompleted -and $errReader.Handle.IsCompleted
            if (-not $done) { Start-Sleep -Milliseconds 20 }
        } while (-not $done)
        while ($queue.TryDequeue([ref]$line)) {
            Write-Both ([string]$line)
        }
        [void]$proc.WaitForExit()
        $code = $proc.ExitCode
        if ($null -eq $code) { $code = 1 }
        Write-Both ("=== " + $SuiteName + " exit " + $code + " ===")
        Write-Both ""
        return [int]$code
    } catch {
        $ex = $_.Exception
        while ($null -ne $ex.InnerException) { $ex = $ex.InnerException }
        Write-Both ("Failed to start Godot: " + $Godot)
        Write-Both $ex.Message
        Write-Both ("=== " + $SuiteName + " exit 1 ===")
        Write-Both ""
        return 1
    } finally {
        # Kill before joining the readers. A reader blocked on ReadLine only
        # wakes up once Godot's pipes close.
        if ($null -ne $proc) {
            try {
                if (-not $proc.HasExited) { $proc.Kill() }
            } catch {}
        }
        Stop-Reader $outReader
        Stop-Reader $errReader
        if ($null -ne $proc) { $proc.Dispose() }
    }
}

$utf8File = New-Object System.Text.UTF8Encoding $false
$logDir = Split-Path -Parent $Log
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$script:Writer = New-Object System.IO.StreamWriter($Log, $true, $utf8File)
$script:Writer.NewLine = "`r`n"
$script:Writer.AutoFlush = $true

try {
    if ($Header) {
        if ($Run -gt 0) {
            Write-Both ("Run #" + $Run)
        }
        Write-Both "Idle PD playtest"
        Write-Both ("started: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
        Write-Both ("root: " + $Root)
        Write-Both ("godot: " + $Godot)
        Write-Both ""
    }
    $code = Invoke-Suite $Name $Scene
    $script:ExitCode = [int]@($code)[-1]
} catch {
    Write-Both ("playtest.ps1: " + $_.Exception.Message)
    $script:ExitCode = 1
} finally {
    Close-Log
}

exit $script:ExitCode
