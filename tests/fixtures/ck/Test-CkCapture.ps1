[CmdletBinding()]param([Parameter(Mandatory)][string]$Plugin,[Parameter(Mandatory)][string]$XDump64)
$ErrorActionPreference='Stop'
$before=(Get-FileHash -Algorithm SHA256 -LiteralPath $Plugin).Hash
$output=& $XDump64 -check $Plugin 2>&1
if($LASTEXITCODE -ne 0){throw ($output -join "`n")}
$dump=& $XDump64 -dump $Plugin 2>&1
$text=$dump -join "`n"
foreach($record in @('QUST','ALST','PACK','NAVM')){if($text -notmatch $record){throw "missing required original record $record"}}
$after=(Get-FileHash -Algorithm SHA256 -LiteralPath $Plugin).Hash
if($before -ne $after){throw 'read-only capture modified plugin'}
"RESULT=PASS sha256=$after records=QUST,ALST,PACK,NAVM"
