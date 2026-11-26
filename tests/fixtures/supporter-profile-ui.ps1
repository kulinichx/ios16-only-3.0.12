$form.Show()
[Windows.Forms.Application]::DoEvents()
function Show-Error([string]$Message) { throw $Message }
$script:ProfileTestFailure = ''
$script:ProfileTestMode = 'Cancel'
$script:ProfileTestName = 'Synthetic renamed user'
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 100
$timer.Add_Tick({
    $timer.Stop()
    $editor = @([Windows.Forms.Application]::OpenForms | Where-Object { $_.Text -like '修改用户资料*' })[0]
    try {
        $boxes = @($editor.Controls | Where-Object { $_ -is [Windows.Forms.TextBox] } | Sort-Object Top)
        if ($boxes.Count -ne 3) { throw 'Profile fields missing' }
        $boxes[0].Text = $script:ProfileTestName
        $boxes[1].Text = '微信：synthetic-contact'
        $boxes[2].Text = 'Synthetic updated note'
        if ($env:DORH_ISSUER_PROFILE_IMAGE -and $script:ProfileTestMode -eq 'Save') {
            $bitmap = New-Object Drawing.Bitmap($editor.Width, $editor.Height)
            try { $editor.DrawToBitmap($bitmap, (New-Object Drawing.Rectangle(0, 0, $editor.Width, $editor.Height))); $bitmap.Save($env:DORH_ISSUER_PROFILE_IMAGE) }
            finally { $bitmap.Dispose() }
        }
        $caption = if ($script:ProfileTestMode -eq 'Save') { '保存资料' } else { '取消' }
        @($editor.Controls | Where-Object { $_.Text -eq $caption })[0].PerformClick()
    } catch {
        $script:ProfileTestFailure = $_.Exception.Message + ' ' + $_.ScriptStackTrace
        if ($null -ne $editor) { $editor.Close() }
    }
})
try {
    $grid.ClearSelection()
    $grid.Rows[0].Selected = $true
    $btnLoad.PerformClick()
    $loadedId = [string]$script:LoadedRecord.SupporterId
    $before = [IO.File]::ReadAllBytes($script:RecordsPath)
    $profileButton = @($historyPanel.Controls | Where-Object { $_.Text -eq '修改资料' })[0]
    $timer.Start()
    $profileButton.PerformClick()
    if ($script:ProfileTestFailure) { throw $script:ProfileTestFailure }
    if ((Get-RHProfileHash ([IO.File]::ReadAllBytes($script:RecordsPath))) -ne (Get-RHProfileHash $before)) { throw 'Cancel wrote profile' }
    $script:ProfileTestMode = 'Save'
    $timer.Start()
    $profileButton.PerformClick()
    if ($script:ProfileTestFailure) { throw $script:ProfileTestFailure }
    if ($script:LoadedRecord.DisplayName -ne $script:ProfileTestName -or $txtName.Text -ne $script:ProfileTestName -or $txtNote.Text -ne 'Synthetic updated note') { throw 'Saved loaded fields stale' }
    $txtSearch.Text = 'synthetic-contact'
    if ($grid.Rows.Count -ne 1 -or $grid.Rows[0].Cells['ID'].Value -ne $loadedId) { throw 'Contact search failed' }
    $txtSearch.Text = 'Original user ' + $loadedId
    if ($grid.Rows.Count -ne 1 -or $grid.Rows[0].Cells['用户'].Value -ne $script:ProfileTestName) { throw 'Previous name search failed' }
    $txtSearch.Text = ''
    $btnCloseLoaded.PerformClick()
    $grid.ClearSelection(); $grid.Rows[0].Selected = $true
    $btnLoad.PerformClick()
    if ($txtName.Text -ne $script:ProfileTestName) { throw 'Reload lost saved profile' }
    [pscustomobject]@{Saved=$true; CancelledWithoutWrite=$true; LoadedId=$loadedId; Rows=$grid.Rows.Count} | ConvertTo-Json -Compress
} finally { $timer.Stop(); $timer.Dispose(); $form.Close(); $form.Dispose() }
