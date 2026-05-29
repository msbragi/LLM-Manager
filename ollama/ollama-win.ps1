# Ollama Windows launcher — called by ollama_execute in ollama-api.sh via WSL/PowerShell
param(
    [Parameter(Mandatory)][string]   $Action,
    [Parameter(Mandatory)][string]   $BinPath,
    [Parameter(Mandatory)][string]   $OllamaHost,
    [Parameter(Mandatory)][string]   $ModelsDir,
    [string]                         $KeepAlive = "30m",
    [string]                         $Params = ""
)

$env:OLLAMA_HOST       = $OllamaHost
$env:OLLAMA_MODELS     = $ModelsDir
$env:OLLAMA_KEEP_ALIVE = $KeepAlive
$env:OLLAMA_ORIGINS    = "*"

if ($Params) {
    # Split into tokens, respecting double-quoted strings (e.g. paths with spaces)
    $argList = [regex]::Matches($Params, '"[^"]*"|[^\s]+') |
               ForEach-Object { $_.Value.Trim('"') }
    & $BinPath $Action @argList
} else {
    & $BinPath $Action
}
exit $LASTEXITCODE
