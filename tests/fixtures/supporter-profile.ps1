param([string]$Directory, [string]$Source)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
. $Source
$script:RecordsPath = Join-Path $Directory 'supporters.json'
$parsed = Get-Content -LiteralPath $script:RecordsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$script:Records = @($parsed)
$original = [IO.File]::ReadAllBytes($script:RecordsPath)
$memory = $script:Records | ConvertTo-Json -Depth 32
$snapshot = Get-RHProfileSnapshot $script:Records[0]
if ((Get-RHProfileHash $original) -ne $snapshot.Hash) { throw 'Loading edited storage' }
if ([IO.Directory]::Exists((Join-Path $Directory 'profile-backups'))) { throw 'Loading created backup' }
try { $null = Save-RHProfile $snapshot ' ' 'contact' 'note'; throw 'Blank name accepted' } catch { if ($_.Exception.Message -notlike '*用户名不能为空*') { throw } }
function Write-RHProfileDatabase { throw 'Injected write failure' }
try { $null = Save-RHProfile $snapshot 'New name' 'contact' 'note'; throw 'Write failure ignored' } catch { if ($_.Exception.Message -ne 'Injected write failure') { throw } }
if ((Get-RHProfileHash ([IO.File]::ReadAllBytes($script:RecordsPath))) -ne $snapshot.Hash) { throw 'Failure changed file' }
if (($script:Records | ConvertTo-Json -Depth 32) -cne $memory) { throw 'Failure changed memory' }
if (@(Get-ChildItem -LiteralPath $Directory -Filter '*.tmp' -Force).Count -ne 0) { throw 'Temporary files left after failure' }
. $Source
$saved = Save-RHProfile $snapshot '新用户名' '微信：new-contact' "新备注`r`n第二行"
if ((Get-RHProfileHash ([IO.File]::ReadAllBytes($saved.Backup))) -ne (Get-RHProfileHash $original)) { throw 'Backup differs from original' }
$updated = $saved.Record
foreach ($query in @('旧用户名', '新用户名', 'new-contact', '第二行', '0027', 'CDEF')) {
    if (-not (Test-RHProfileSearch $updated $query)) { throw ('Cannot search ' + $query) }
}
if ((Get-RHProfileSummary $updated) -notlike '*new-contact*新备注*') { throw 'History summary lost contact or note' }
$count = @(Get-ChildItem -LiteralPath (Join-Path $Directory 'profile-backups')).Count
try { $null = Save-RHProfile $snapshot 'STALE' '' ''; throw 'Stale editor overwrote changes' } catch { if ($_.Exception.Message -notlike '*记录文件已变化*') { throw } }
if (@(Get-ChildItem -LiteralPath (Join-Path $Directory 'profile-backups')).Count -ne $count) { throw 'Rejected update created backup' }
$next = Get-RHProfileSnapshot $updated
$null = Save-RHProfile $next '新用户名' '' '备注再次修改'
if (@($script:Records[0].PreviousDisplayNames).Count -ne 1) { throw 'Unchanged name duplicated aliases' }
[pscustomobject]@{ Saved=$true; FailurePreserved=$true; StaleRejected=$true } | ConvertTo-Json -Compress
