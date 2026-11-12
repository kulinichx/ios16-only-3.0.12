param([string]$Directory, [string]$PreviewImage)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
function Assert-Test([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Style-SecondaryButton($Button) { $Button.BackColor = [Drawing.ColorTranslator]::FromHtml('#2C3440'); $Button.ForeColor = [Drawing.Color]::White; $Button.FlatStyle = 'Flat' }
function Style-PrimaryButton($Button) { Style-SecondaryButton $Button; $Button.BackColor = [Drawing.ColorTranslator]::FromHtml('#2F67AD') }
$form = New-Object Windows.Forms.Form
$form.ClientSize = New-Object Drawing.Size(820, 950)
$form.BackColor = [Drawing.ColorTranslator]::FromHtml('#191C21')
$form.ForeColor = [Drawing.ColorTranslator]::FromHtml('#E7E9EC')
$form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9)
$panel = New-Object Windows.Forms.Panel
$panel.SetBounds(18, 520, 784, 128)
$panel.Anchor = 'Top, Left, Right'
$form.Controls.Add($panel)
$output = New-Object Windows.Forms.TextBox
$output.Multiline = $true
$output.SetBounds(18, 49, 746, 59)
$panel.Controls.Add($output)
$grid = New-Object Windows.Forms.DataGridView
$grid.SetBounds(18, 664, 784, 245)
$grid.AllowUserToAddRows = $false
$grid.RowHeadersVisible = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $false
$grid.AutoSizeColumnsMode = 'Fill'
$grid.BackgroundColor = [Drawing.ColorTranslator]::FromHtml('#23272E')
$grid.DefaultCellStyle.BackColor = $grid.BackgroundColor
$grid.DefaultCellStyle.ForeColor = $form.ForeColor
$grid.ColumnHeadersDefaultCellStyle.BackColor = [Drawing.ColorTranslator]::FromHtml('#252A31')
$grid.ColumnHeadersDefaultCellStyle.ForeColor = $form.ForeColor
foreach ($name in @('ID', '用户', '设备码', '最近签发', '联系方式 / 备注')) { [void]$grid.Columns.Add($name, $name) }
$previewPath = Join-Path $Directory 'preview.json'
$preview = [IO.File]::ReadAllText($previewPath) | ConvertFrom-Json
foreach ($row in $preview.records) { [void]$grid.Rows.Add($row.id, $row.displayName, $row.deviceCode, $row.lastIssuedAt, $row.note) }
$form.Controls.Add($grid)
$status = New-Object Windows.Forms.Label
$form.Controls.Add($status)
$proof = New-Object Windows.Forms.Button
$issueRH1 = New-Object Windows.Forms.Button
$form.Controls.Add($proof)
$form.Controls.Add($issueRH1)
$script:ProofEvents = 0
function Load-DeviceProofState { $script:ProofLoads++ }
$script:ProofLoads = 0
function Verify-RHP1Proof([string]$ProofText, [string]$ExpectedMode = '') {
    if ($ProofText -ne 'SYNTHETIC-PROOF-STDIN') { throw 'synthetic invalid proof' }
    return [pscustomobject]@{ Mode = 'NORMAL'; DeviceCode = '0029-4567-89AB-CDEF-0123-4567-89AB-CDEF'; Policy = 'REVIEW_KEY_MISMATCH' }
}
$proof.Add_Click({ $script:ProofEvents++ })
. (Join-Path $Directory 'SupporterBindingIntegration.ps1')
Initialize-RHBindingIntegration @{
    Directory = $Directory; Form = $form; Panel = $panel; Grid = $grid; Output = $output; Status = $status
    VerifyProofButton = $proof; RH1IssueButton = $issueRH1
}
$state = $script:RHIntegratedBinding
function Read-Commands { return @([IO.File]::ReadAllLines((Join-Path $Directory 'commands.jsonl')) | ForEach-Object { ,($_ | ConvertFrom-Json) }) }
function Count-Issues { return @((Read-Commands) | Where-Object { $_[0] -eq 'issue' -or $_[0] -eq 'issue-all' }).Count }
$form.Show()
[Windows.Forms.Application]::DoEvents()
try {
    Assert-Test ((Count-Issues) -eq 0) 'Startup must not sign.'
    Assert-Test $state.Batch.Enabled 'Batch must be available for reviewed historical proofs.'
    Assert-Test ($grid.Rows[0].Cells['RHBindingState'].Value -eq '已有设备证明') 'Bound row state missing.'
    Assert-Test ($grid.Rows[1].Cells['RHBindingState'].Value -eq '待设备证明') 'Legacy row state missing.'
    $grid.ClearSelection(); $grid.Rows[1].Selected = $true
    Assert-Test (-not $state.Single.Enabled) 'Unbound user must not be signed.'
    $grid.ClearSelection(); $grid.Rows[0].Selected = $true
    Assert-Test $state.Single.Enabled 'Bound selected user should be available.'
    $eligible = @($preview.records | Where-Object { $_.status -eq 'READY_FOR_REVIEW' })
    $review = New-RHIntegratedBindingReview $eligible
    try {
        $reviewGrid = @($review.Controls | Where-Object { $_ -is [Windows.Forms.DataGridView] })[0]
        Assert-Test ($reviewGrid.Rows.Count -eq 2) 'Batch review must include every eligible user.'
        Assert-Test ($reviewGrid.Rows[0].Cells['User'].Value -eq $preview.records[0].displayName) 'Review user name missing.'
        Assert-Test ($reviewGrid.Rows[0].Cells['Note'].ToolTipText -eq $preview.records[0].note) 'Review note missing.'
        $review.Show()
        [Windows.Forms.Application]::DoEvents()
        $bitmap = New-Object Drawing.Bitmap($review.Width, $review.Height)
        try {
            $review.DrawToBitmap($bitmap, (New-Object Drawing.Rectangle(0, 0, $review.Width, $review.Height)))
            $bitmap.Save($PreviewImage, [Drawing.Imaging.ImageFormat]::Png)
        } finally { $bitmap.Dispose(); $review.Hide() }
    } finally { $review.Dispose() }
    # Exercise cancel/confirm routes without dialogs or touching the real clipboard.
    function Confirm-RHIntegratedBindingReview($Records) { return $false }
    Start-RHIntegratedBindingIssue
    Assert-Test ((Count-Issues) -eq 0) 'Review cancellation must not sign.'
    function Confirm-RHIntegratedBindingReview($Records) { $script:ReviewedIds = @($Records | ForEach-Object { $_.id }); return $true }
    function Select-RHIntegratedBindingOutput($Id, $Batch) { return '' }
    Start-RHIntegratedBindingIssue
    Assert-Test ((Count-Issues) -eq 0) 'Output cancellation must not sign.'
    function Show-RHIntegratedBindingMessage($Message, $Failed = $false) { $script:LastMessage = $Message; $script:LastFailed = $Failed }
    function Select-RHIntegratedBindingOutput($Id, $Batch) { if ($Batch) { return $Directory }; return (Join-Path $Directory 'bound-test.txt') }
    function Set-RHIntegratedBindingClipboard($Text) { throw 'Test clipboard unavailable' }
    Start-RHIntegratedBindingIssue
    Assert-Test ((Count-Issues) -eq 1) 'Single signing missing.'
    Assert-Test (-not $script:LastFailed -and $script:LastMessage -match '请勿重复补发') 'Clipboard failure must not report signing failure.'
    Assert-Test ($output.Text -match 'RHB1.TEST-ONLY') 'Combined activation text missing.'
    Start-RHIntegratedBindingIssue $true
    Assert-Test ((Count-Issues) -eq 2) 'Batch signing missing.'
    Assert-Test (($script:ReviewedIds -join ',') -eq '0027,0029') 'Batch must review all eligible users, excluding legacy users.'
    $proof.PerformClick()
    Assert-Test ($script:ProofEvents -eq 1 -and (Count-Issues) -eq 2) 'Original proof handler must remain and must not auto-sign.'
    $form.ClientSize = New-Object Drawing.Size(790, 930)
    $form.PerformLayout()
    $strip = $state.Single.Parent
    Assert-Test ($strip.Right -le ($panel.Width - 158)) 'Binding toolbar overlaps original copy button.'
    Assert-Test ($state.Rekey.Right -le $strip.ClientSize.Width) 'Toolbar clipped at minimum width.'
    # An external change after review must be refused by the helper and clear the cached plan.
    [IO.File]::Delete((Join-Path $Directory 'bound-test.txt'))
    $preview.records[0].reviewSha256 = 'F' * 64
    [IO.File]::WriteAllText($previewPath, ($preview | ConvertTo-Json -Depth 10))
    Start-RHIntegratedBindingIssue
    Assert-Test $script:LastFailed 'Stale review must fail.'
    Assert-Test (-not (Test-Path -LiteralPath (Join-Path $Directory 'bound-test.txt'))) 'Stale review published an output.'
    Assert-Test (-not $state.Single.Enabled -and -not $state.Batch.Enabled) 'Stale review kept signing enabled.'
    Refresh-RHIntegratedBindingPlan
    Assert-Test $state.Single.Enabled 'Explicit refresh should restore a valid preview.'
    [IO.File]::WriteAllText((Join-Path $Directory 'plan-failure'), 'TEST ONLY')
    Refresh-RHIntegratedBindingPlan
    Assert-Test (-not $state.Single.Enabled -and -not $state.Batch.Enabled) 'Failed preview kept signing enabled.'
    Assert-Test ($grid.Rows[0].Cells['RHBindingState'].Value -eq '预检不可用') 'Failed preview reused old binding state.'
    [IO.File]::Delete((Join-Path $Directory 'plan-failure'))
    $null = Verify-RHP1Proof 'SYNTHETIC-PROOF-STDIN' 'NORMAL'
    Refresh-RHIntegratedBindingPlan
    $grid.ClearSelection(); $grid.Rows[2].Selected = $true
    Assert-Test (-not $state.Single.Enabled -and $state.Rekey.Enabled) 'Key mismatch did not disable supplement and enable explicit review.'
    $keyPlan = Invoke-RHIntegratedBinding @('rekey-plan', '--issuer-dir', $Directory, '--id', '0029')
    $keyDialog = New-RHIntegratedKeyReview $keyPlan
    try {
        $keyDialog.Show()
        [Windows.Forms.Application]::DoEvents()
        $bitmap = New-Object Drawing.Bitmap($keyDialog.Width, $keyDialog.Height)
        try {
            $keyDialog.DrawToBitmap($bitmap, (New-Object Drawing.Rectangle(0, 0, $keyDialog.Width, $keyDialog.Height)))
            $bitmap.Save(($PreviewImage + '.key-review.png'), [Drawing.Imaging.ImageFormat]::Png)
        } finally { $bitmap.Dispose(); $keyDialog.Hide() }
        Assert-Test (-not $keyDialog.Tag.Confirm.Enabled) 'Migration confirmation must start disabled.'
        $keyDialog.Tag.Input.Text = '29'
        Assert-Test (-not $keyDialog.Tag.Confirm.Enabled) 'Leading zeroes are required.'
        $keyDialog.Tag.Input.Text = '0029'
        Assert-Test $keyDialog.Tag.Confirm.Enabled 'Exact supporter ID must enable confirmation.'
    } finally { $keyDialog.Dispose() }
    function Confirm-RHIntegratedKeyReview($Plan) { return '' }
    Start-RHIntegratedKeyMigration
    Assert-Test (@((Read-Commands) | Where-Object { $_[0] -eq 'rekey' }).Count -eq 0) 'Cancelled review migrated a key.'
    function Confirm-RHIntegratedKeyReview($Plan) { return '0030' }
    Start-RHIntegratedKeyMigration
    Assert-Test (@((Read-Commands) | Where-Object { $_[0] -eq 'rekey' }).Count -eq 0) 'Wrong ID migrated a key.'
    function Confirm-RHIntegratedKeyReview($Plan) { return '0029' }
    Start-RHIntegratedKeyMigration
    Assert-Test (@((Read-Commands) | Where-Object { $_[0] -eq 'rekey' }).Count -eq 1) 'Confirmed key migration missing.'
    Assert-Test ($state.Single.Enabled -and -not $state.Rekey.Enabled) 'Migrated user did not return to supplement review.'
    Assert-Test ((Count-Issues) -eq 3) 'Key migration must not automatically sign.'
    [IO.File]::WriteAllText((Join-Path $Directory 'review-failure'), 'TEST ONLY')
    try { $null = Verify-RHP1Proof 'SYNTHETIC-PROOF-STDIN' 'NORMAL'; throw 'Expected receipt failure' }
    catch { Assert-Test ($_.Exception.Message -match '复核记录保存失败') 'Receipt failure was not explained.' }
    Refresh-RHIntegratedBindingPlan
    Assert-Test (-not $state.Single.Enabled -and -not $state.Batch.Enabled -and -not $state.Rekey.Enabled) 'Receipt failure must latch closed even after refresh.'
    Assert-Test ($state.ById['0029'].status -eq 'REVERIFY_REQUIRED') 'Receipt failure did not persist a reverify marker.'
    Assert-Test ($script:ProofLoads -ge 3) 'Proof guard and migration must reload original binding memory.'
    Assert-Test (@((Read-Commands) | Where-Object { ($_ -join ' ') -match 'SYNTHETIC-PROOF-STDIN' }).Count -eq 0) 'Proof must travel by stdin, not command arguments.'
    [pscustomobject]@{ Checked = $true; ReviewRows = 2; CanSignAfterFailure = $state.Single.Enabled
        OriginalProofEvents = $script:ProofEvents; RealClipboardTouched = $false } | ConvertTo-Json -Compress
} finally { $form.Close(); $form.Dispose() }
