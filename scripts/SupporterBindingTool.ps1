param([string]$IssuerDirectory = '', [switch]$SmokeTest, [switch]$VerifyVisible)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ($VerifyVisible -and -not $SmokeTest) { throw 'VerifyVisible requires SmokeTest.' }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$node = (Get-Command node -ErrorAction Stop).Source
$helper = Join-Path $PSScriptRoot 'supporter-binding.cjs'

function Invoke-BindingHelper([string[]]$Arguments) {
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $node
    $all = @($helper) + $Arguments
    $quoted = foreach ($argument in $all) {
        '"' + ($argument -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
    }
    $start.Arguments = $quoted -join ' '
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $output = $stdout.Result
        $failure = $stderr.Result
        if ($process.ExitCode -ne 0) {
            if ($failure -match 'review-stale-reload-plan') { throw '数据库已在预览后改变。请重新选择目录、复核绑定后再补发。' }
            throw $failure.Trim()
        }
        return $output | ConvertFrom-Json
    } finally { $process.Dispose() }
}

$form = New-Object Windows.Forms.Form
$form.Text = 'RootHide Supporter Binding - Migration Preview'
$form.ClientSize = New-Object Drawing.Size(760, 540)
$form.MinimumSize = New-Object Drawing.Size(680, 460)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10)

$pathBox = New-Object Windows.Forms.TextBox
$pathBox.SetBounds(16, 16, 565, 28)
$pathBox.Anchor = 'Top, Left, Right'
$pathBox.ReadOnly = $true
$form.Controls.Add($pathBox)

$choose = New-Object Windows.Forms.Button
$choose.Text = '选择签发工具目录'
$choose.SetBounds(594, 14, 150, 32)
$choose.Anchor = 'Top, Right'
$form.Controls.Add($choose)

$summary = New-Object Windows.Forms.Label
$summary.SetBounds(16, 56, 728, 48)
$summary.Anchor = 'Top, Left, Right'
$summary.Text = '请选择现有签发工具所在目录。'
$form.Controls.Add($summary)

$grid = New-Object Windows.Forms.DataGridView
$grid.SetBounds(16, 110, 728, 350)
$grid.Anchor = 'Top, Bottom, Left, Right'
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.MultiSelect = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.RowHeadersVisible = $false
$grid.AutoSizeColumnsMode = 'Fill'
$grid.BackgroundColor = [Drawing.Color]::White
[void]$grid.Columns.Add('id', 'Supporter ID')
[void]$grid.Columns.Add('note', '联系方式 / 备注')
[void]$grid.Columns.Add('state', '绑定状态')
$grid.Columns['id'].FillWeight = 14
$grid.Columns['id'].MinimumWidth = 80
$grid.Columns['note'].FillWeight = 40
$grid.Columns['note'].MinimumWidth = 160
$grid.Columns['state'].FillWeight = 46
$grid.Columns['state'].MinimumWidth = 240
$grid.ShowCellToolTips = $true
$form.Controls.Add($grid)

$issue = New-Object Windows.Forms.Button
$issue.Text = '补发选中用户'
$issue.SetBounds(16, 480, 160, 38)
$issue.Anchor = 'Bottom, Left'
$issue.Enabled = $false
$form.Controls.Add($issue)

$batch = New-Object Windows.Forms.Button
$batch.Text = '补发已有绑定用户'
$batch.SetBounds(188, 480, 190, 38)
$batch.Anchor = 'Bottom, Left'
$batch.Enabled = $false
$form.Controls.Add($batch)

$close = New-Object Windows.Forms.Button
$close.Text = '关闭'
$close.SetBounds(640, 480, 104, 38)
$close.Anchor = 'Bottom, Right'
$close.Add_Click({ $form.Close() })
$form.Controls.Add($close)

function Show-BindingError([object]$Failure) {
    [void][Windows.Forms.MessageBox]::Show($form, [string]$Failure, '绑定操作未完成', 'OK', 'Error')
}

function Load-BindingPlan([string]$Directory) {
    $issue.Enabled = $false
    $batch.Enabled = $false
    $batch.Tag = $null
    $pathBox.Clear()
    $grid.Rows.Clear()
    $summary.Text = '正在预检；若失败，请重新选择有效的签发工具目录。'
    $plan = Invoke-BindingHelper @('plan', '--issuer-dir', $Directory)
    foreach ($record in @($plan.records)) {
        $state = if ($record.status -eq 'READY_FOR_REVIEW') { '已有历史绑定 · 可复核后补发' } else { '旧授权 · 待补设备证明' }
        $note = [string]$record.note
        $index = $grid.Rows.Add([string]$record.id, ($note -replace '[\r\n]+', ' '), $state)
        $grid.Rows[$index].Cells['note'].ToolTipText = $note
        $grid.Rows[$index].Tag = $record
    }
    $pathBox.Text = [IO.Path]::GetFullPath($Directory)
    $summary.Text = "用户 $($plan.total) · 可补发 $($plan.eligible) · 待证明 $($plan.needsProof) · 未匹配绑定 $($plan.orphanBindings)`r`n原授权编号和数据库保持不变。"
    $batch.Enabled = $plan.eligible -gt 0
    $batch.Tag = [string]$plan.reviewSha256
    $issue.Enabled = $grid.SelectedRows.Count -gt 0 -and $null -ne $grid.SelectedRows[0].Tag -and $grid.SelectedRows[0].Tag.status -eq 'READY_FOR_REVIEW'
}

$grid.Add_SelectionChanged({
    $issue.Enabled = $grid.SelectedRows.Count -gt 0 -and $null -ne $grid.SelectedRows[0].Tag -and $grid.SelectedRows[0].Tag.status -eq 'READY_FOR_REVIEW'
})

$choose.Add_Click({
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    try {
        $dialog.Description = '选择包含 supporters.json 和历史设备绑定的签发工具目录'
        if ($dialog.ShowDialog($form) -eq 'OK') { Load-BindingPlan $dialog.SelectedPath }
    } catch { Show-BindingError $_.Exception.Message }
    finally { $dialog.Dispose() }
})

$issue.Add_Click({
    if ($grid.SelectedRows.Count -eq 0 -or $null -eq $grid.SelectedRows[0].Tag -or $grid.SelectedRows[0].Tag.status -ne 'READY_FOR_REVIEW') { return }
    $id = [string]$grid.SelectedRows[0].Cells['id'].Value
    $note = [string]$grid.SelectedRows[0].Tag.note
    if ([string]::IsNullOrWhiteSpace($note)) { $note = '未填写备注' }
    $review = [string]$grid.SelectedRows[0].Tag.reviewSha256
    $confirm = [Windows.Forms.MessageBox]::Show($form,
        "用户 #$id`r`n备注：$note`r`n`r`n确认已复核该用户的历史绑定？将使用现有签发私钥生成绑定凭证，不修改原数据库。", '确认补发', 'YesNo', 'Question')
    if ($confirm -ne 'Yes') { return }
    $dialog = New-Object Windows.Forms.SaveFileDialog
    try {
        $dialog.Filter = '授权文本 (*.txt)|*.txt'
        $dialog.FileName = "supporter-$id-bound.txt"
        $dialog.OverwritePrompt = $false
        if ($dialog.ShowDialog($form) -ne 'OK') { return }
        $result = Invoke-BindingHelper @('issue', '--issuer-dir', $pathBox.Text, '--id', $id, '--out', $dialog.FileName, '--review-sha256', $review)
        $message = "已生成：$($dialog.FileName)"
        try {
            [Windows.Forms.Clipboard]::SetText([IO.File]::ReadAllText($dialog.FileName))
            $message += "`r`n已复制。用户可在新版设置的授权入口一次粘贴。"
        } catch { $message += "`r`n剪贴板不可用，授权文件已生成，请勿重复补发。" }
        if (@($result.cleanupWarnings).Count -gt 0) { $message += "`r`n暂存清理未完成：$($result.cleanupWarnings -join ', ')" }
        [void][Windows.Forms.MessageBox]::Show($form, $message, '补发完成', 'OK', 'Information')
    } catch { Show-BindingError $_.Exception.Message }
    finally { $dialog.Dispose() }
})

$batch.Add_Click({
    $confirm = [Windows.Forms.MessageBox]::Show($form,
        '确认已复核全部历史绑定？仅补发已有绑定的用户；未绑定用户及未匹配记录不会自动签发。', '确认批量补发', 'YesNo', 'Question')
    if ($confirm -ne 'Yes') { return }
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    try {
        $dialog.Description = '选择空的输出目录；不会覆盖已有文件'
        if ($dialog.ShowDialog($form) -ne 'OK') { return }
        $result = Invoke-BindingHelper @('issue-all', '--issuer-dir', $pathBox.Text, '--out-dir', $dialog.SelectedPath, '--review-sha256', ([string]$batch.Tag))
        $message = "已补发 $($result.issued) 条，原数据库未改动。"
        if (@($result.cleanupWarnings).Count -gt 0) { $message += "`r`n暂存清理未完成：$($result.cleanupWarnings -join ', ')" }
        [void][Windows.Forms.MessageBox]::Show($form, $message, '补发完成', 'OK', 'Information')
    } catch { Show-BindingError $_.Exception.Message }
    finally { $dialog.Dispose() }
})

if ($IssuerDirectory) {
    if ($SmokeTest) { Load-BindingPlan $IssuerDirectory }
    else {
        try { Load-BindingPlan $IssuerDirectory }
        catch { Show-BindingError $_.Exception.Message }
    }
}
if ($SmokeTest) {
    $form.CreateControl()
    $form.PerformLayout()
    if ($VerifyVisible) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BindingStartupVisibility {
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr handle);
}
'@
        $script:startupVisible = $false
        $timer = New-Object Windows.Forms.Timer
        $timer.Interval = 250
        $timer.Add_Tick({
            $timer.Stop()
            $script:startupVisible = [BindingStartupVisibility]::IsWindowVisible($form.Handle)
            $form.Close()
        })
        try {
            $timer.Start()
            [void]$form.ShowDialog()
        } finally { $timer.Stop(); $timer.Dispose() }
        if (-not $script:startupVisible) { $form.Dispose(); throw 'Launcher created a hidden main window.' }
    }
    $previewRecords = @($grid.Rows | ForEach-Object {
        [pscustomobject]@{ Id = [string]$_.Cells['id'].Value; Note = [string]$_.Cells['note'].Value;
            NoteTooltip = [string]$_.Cells['note'].ToolTipText }
    })
    [pscustomobject]@{ Rows = $grid.Rows.Count; CanIssue = $issue.Enabled; CanBatch = $batch.Enabled;
        PreviewRecords = $previewRecords;
        Summary = $summary.Text; Width = $form.ClientSize.Width; Height = $form.ClientSize.Height } | ConvertTo-Json
    $form.Dispose()
    return
}
[void]$form.ShowDialog()
$form.Dispose()
