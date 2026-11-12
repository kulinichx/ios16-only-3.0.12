# RootHide supporter binding integration v1. Dot-source from the original issuer.

function Invoke-RHIntegratedBinding([string[]]$Arguments) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $script:RHIntegratedBinding.Node
    $all = @($script:RHIntegratedBinding.Helper) + $Arguments
    $start.Arguments = (@($all | ForEach-Object {
        '"' + ($_ -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
    }) -join ' ')
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            $failure = $stderr.Result.Trim()
            if ($failure -match 'review-stale-reload-plan') {
                throw '预检后用户或设备绑定已改变，请刷新并重新复核。没有补发授权。'
            }
            throw $failure
        }
        return $stdout.Result | ConvertFrom-Json
    } finally { $process.Dispose() }
}

function Update-RHIntegratedBindingControls {
    $state = $script:RHIntegratedBinding
    if (-not $state.Grid.Columns.Contains('RHBindingState')) {
        $column = New-Object Windows.Forms.DataGridViewTextBoxColumn
        $column.Name = 'RHBindingState'
        $column.HeaderText = '设备证明'
        $column.ReadOnly = $true
        $column.SortMode = 'NotSortable'
        $column.FillWeight = 100
        $column.MinimumWidth = 105
        [void]$state.Grid.Columns.Add($column)
    }
    $state.Grid.Columns['RHBindingState'].DisplayIndex = $state.Grid.Columns.Count - 1
    foreach ($row in $state.Grid.Rows) {
        $id = [string]$row.Cells['ID'].Value
        $record = $state.ById[$id]
        $text = if ($null -eq $state.Plan) { '预检不可用' }
            elseif ($null -eq $record) { '请刷新预检' }
            elseif ($record.status -eq 'READY_FOR_REVIEW') { '已有设备证明' }
            else { '待设备证明' }
        $row.Cells['RHBindingState'].Value = $text
        $row.Cells['RHBindingState'].ToolTipText = $(if ($state.Error) { $state.Error } else { $text })
    }
    $selected = $null
    if ($state.Grid.SelectedRows.Count -eq 1) {
        $selected = $state.ById[[string]$state.Grid.SelectedRows[0].Cells['ID'].Value]
    }
    $state.Single.Enabled = -not $state.Busy -and $null -ne $selected -and $selected.status -eq 'READY_FOR_REVIEW'
    $state.Batch.Enabled = -not $state.Busy -and $null -ne $state.Plan -and $state.Plan.eligible -gt 0
    $state.Refresh.Enabled = -not $state.Busy
}

function Refresh-RHIntegratedBindingPlan([switch]$Quiet) {
    $state = $script:RHIntegratedBinding
    $state.Plan = $null
    $state.ById = @{}
    $state.Error = ''
    Update-RHIntegratedBindingControls
    try {
        $state.Node = (Get-Command node -ErrorAction Stop).Source
        $plan = Invoke-RHIntegratedBinding @('plan', '--issuer-dir', $state.Directory)
        foreach ($record in @($plan.records)) { $state.ById[[string]$record.id] = $record }
        $state.Plan = $plan
        if (-not $Quiet) {
            $state.Status.Text = "绑定预检：可补发 $($plan.eligible) · 待证明 $($plan.needsProof) · 未匹配绑定 $($plan.orphanBindings)"
        }
    } catch {
        $state.Plan = $null
        $state.ById = @{}
        $state.Error = $_.Exception.Message
        if (-not $Quiet) { $state.Status.Text = '绑定预检未完成：' + $state.Error }
    }
    Update-RHIntegratedBindingControls
}

function New-RHIntegratedBindingReview([object[]]$Records) {
    $state = $script:RHIntegratedBinding
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = '复核绑定授权'
    $dialog.ClientSize = New-Object Drawing.Size(1080, 410)
    $dialog.MinimumSize = New-Object Drawing.Size(980, 400)
    $dialog.StartPosition = 'CenterParent'
    $dialog.Font = $state.Form.Font
    $dialog.BackColor = $state.Form.BackColor
    $dialog.ForeColor = $state.Form.ForeColor
    $review = New-Object Windows.Forms.DataGridView
    $review.SetBounds(16, 16, 1048, 308)
    $review.Anchor = 'Top, Bottom, Left, Right'
    $review.ReadOnly = $true
    $review.AllowUserToAddRows = $false
    $review.AllowUserToDeleteRows = $false
    $review.RowHeadersVisible = $false
    $review.AutoSizeColumnsMode = 'Fill'
    $review.SelectionMode = 'FullRowSelect'
    $review.MultiSelect = $false
    $review.EnableHeadersVisualStyles = $false
    $review.BackgroundColor = $state.Grid.BackgroundColor
    $review.GridColor = $state.Grid.GridColor
    $review.DefaultCellStyle = $state.Grid.DefaultCellStyle.Clone()
    $review.AlternatingRowsDefaultCellStyle = $state.Grid.AlternatingRowsDefaultCellStyle.Clone()
    $review.ColumnHeadersDefaultCellStyle = $state.Grid.ColumnHeadersDefaultCellStyle.Clone()
    $review.ColumnHeadersHeight = 33
    $review.RowTemplate.Height = 29
    foreach ($spec in @(@('ID', 'ID', 55), @('User', '用户', 130), @('Device', '设备码', 230),
        @('Issued', '最近签发', 150), @('Note', '联系方式 / 备注', 200))) {
        [void]$review.Columns.Add($spec[0], $spec[1])
        $review.Columns[$spec[0]].FillWeight = $spec[2]
    }
    foreach ($record in $Records) {
        $index = $review.Rows.Add([string]$record.id, ([string]$record.displayName -replace '[\r\n]+', ' '),
            [string]$record.deviceCode, [string]$record.lastIssuedAt, ([string]$record.note -replace '[\r\n]+', ' '))
        $review.Rows[$index].Cells['User'].ToolTipText = [string]$record.displayName
        $review.Rows[$index].Cells['Note'].ToolTipText = [string]$record.note
    }
    $dialog.Controls.Add($review)
    $count = New-Object Windows.Forms.Label
    $count.Text = "待补发：$($Records.Count) 位用户 · 原 RH1 与数据库保持不变"
    $count.SetBounds(16, 335, 1048, 24)
    $count.Anchor = 'Bottom, Left, Right'
    $dialog.Controls.Add($count)
    $confirm = New-Object Windows.Forms.Button
    $confirm.Text = '确认并选择输出位置'
    $confirm.SetBounds(670, 367, 230, 32)
    $confirm.Anchor = 'Bottom, Right'
    $confirm.DialogResult = 'OK'
    Style-PrimaryButton $confirm
    $dialog.Controls.Add($confirm)
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = '取消'
    $cancel.SetBounds(916, 367, 148, 32)
    $cancel.Anchor = 'Bottom, Right'
    $cancel.DialogResult = 'Cancel'
    Style-SecondaryButton $cancel
    $dialog.Controls.Add($cancel)
    $dialog.CancelButton = $cancel
    return $dialog
}

function Confirm-RHIntegratedBindingReview([object[]]$Records) {
    $dialog = New-RHIntegratedBindingReview $Records
    try { return $dialog.ShowDialog($script:RHIntegratedBinding.Form) -eq 'OK' }
    finally { $dialog.Dispose() }
}

function Set-RHIntegratedBindingClipboard([string]$Text) {
    [Windows.Forms.Clipboard]::SetText($Text)
}

function Select-RHIntegratedBindingOutput([string]$Id, [bool]$Batch) {
    $dialog = if ($Batch) { New-Object Windows.Forms.FolderBrowserDialog }
        else { New-Object Windows.Forms.SaveFileDialog }
    try {
        if ($Batch) {
            $dialog.Description = '选择绑定授权的输出目录；不会覆盖已有文件'
            $dialog.SelectedPath = $script:RHIntegratedBinding.Directory
        } else {
            $dialog.Filter = '授权文本 (*.txt)|*.txt'
            $dialog.InitialDirectory = $script:RHIntegratedBinding.Directory
            $dialog.FileName = "supporter-$Id-bound.txt"
            $dialog.OverwritePrompt = $false
        }
        if ($dialog.ShowDialog($script:RHIntegratedBinding.Form) -ne 'OK') { return '' }
        if ($Batch) { return $dialog.SelectedPath }
        return $dialog.FileName
    } finally { $dialog.Dispose() }
}

function Show-RHIntegratedBindingMessage([string]$Message, [bool]$Failed = $false) {
    [void][Windows.Forms.MessageBox]::Show($script:RHIntegratedBinding.Form, $Message,
        $(if ($Failed) { '绑定操作未完成' } else { '绑定授权' }), 'OK', $(if ($Failed) { 'Error' } else { 'Information' }))
}

function Start-RHIntegratedBindingIssue([bool]$Batch = $false) {
    $state = $script:RHIntegratedBinding
    if ($state.Busy -or $null -eq $state.Plan) { return }
    $state.Busy = $true
    Update-RHIntegratedBindingControls
    try {
        $rows = @()
        $review = ''
        $id = ''
        if ($Batch) {
            $rows = @($state.Plan.records | Where-Object { $_.status -eq 'READY_FOR_REVIEW' })
            $review = [string]$state.Plan.reviewSha256
        } elseif ($state.Grid.SelectedRows.Count -eq 1) {
            $id = [string]$state.Grid.SelectedRows[0].Cells['ID'].Value
            $record = $state.ById[$id]
            if ($null -ne $record -and $record.status -eq 'READY_FOR_REVIEW') {
                $rows = @($record)
                $review = [string]$record.reviewSha256
            }
        }
        if ($rows.Count -eq 0) { return }
        if (-not (Confirm-RHIntegratedBindingReview $rows)) { return }
        $output = Select-RHIntegratedBindingOutput $id $Batch
        if (-not $output) { return }
        $arguments = if ($Batch) { @('issue-all', '--issuer-dir', $state.Directory, '--out-dir', $output) }
            else { @('issue', '--issuer-dir', $state.Directory, '--id', $id, '--out', $output) }
        $arguments += @('--review-sha256', $review)
        $result = Invoke-RHIntegratedBinding $arguments
        $message = "已补发 $($result.issued) 条绑定授权。`r`n输出：$output"
        if (-not $Batch) {
            try {
                $state.Output.Text = [IO.File]::ReadAllText($output)
                Set-RHIntegratedBindingClipboard $state.Output.Text
                $message += "`r`nSupporter #$id · RH1 + RHB1 已复制。"
            } catch { $message += "`r`n文件已生成，但读取或复制未完成，请勿重复补发。" }
        }
        if (@($result.cleanupWarnings).Count -gt 0) { $message += "`r`n暂存清理未完成：$($result.cleanupWarnings -join ', ')" }
        $state.Status.Text = "绑定补发完成 · $($result.issued) 条 · 原数据库未改动"
        Show-RHIntegratedBindingMessage $message
    } catch {
        $message = $_.Exception.Message
        $state.Plan = $null
        $state.ById = @{}
        $state.Error = $message
        $state.Status.Text = '绑定补发未完成，请刷新并重新复核'
        Show-RHIntegratedBindingMessage $message $true
    } finally {
        $state.Busy = $false
        Update-RHIntegratedBindingControls
    }
}

function Initialize-RHBindingIntegration([hashtable]$Context) {
    if (Get-Variable RHIntegratedBinding -Scope Script -ErrorAction SilentlyContinue) {
        throw 'Binding integration is already initialized.'
    }
    $script:RHIntegratedBinding = $Context.Clone()
    $state = $script:RHIntegratedBinding
    $state.Helper = Join-Path $PSScriptRoot 'supporter-binding.cjs'
    $state.Node = ''
    $state.Plan = $null
    $state.ById = @{}
    $state.Busy = $false
    $state.Error = ''
    $strip = New-Object Windows.Forms.FlowLayoutPanel
    $strip.SetBounds(116, 9, 510, 34)
    $strip.Anchor = 'Top, Left, Right'
    $strip.WrapContents = $false
    $strip.Margin = New-Object Windows.Forms.Padding(0)
    foreach ($spec in @(@('Single', '补发选中绑定', 155), @('Batch', '批量补发', 140), @('Refresh', '刷新绑定', 130))) {
        $button = New-Object Windows.Forms.Button
        $button.Text = $spec[1]
        $button.Size = New-Object Drawing.Size($spec[2], 32)
        $button.Margin = New-Object Windows.Forms.Padding(0, 0, 8, 0)
        Style-SecondaryButton $button
        $state[$spec[0]] = $button
        $strip.Controls.Add($button)
    }
    $state.Panel.Controls.Add($strip)
    $state.Single.Add_Click({ Start-RHIntegratedBindingIssue })
    $state.Batch.Add_Click({ Start-RHIntegratedBindingIssue $true })
    $state.Refresh.Add_Click({ Refresh-RHIntegratedBindingPlan })
    $state.Grid.Add_DataBindingComplete({ Update-RHIntegratedBindingControls })
    $state.Grid.Add_SelectionChanged({ Update-RHIntegratedBindingControls })
    $state.VerifyProofButton.Add_Click({ Refresh-RHIntegratedBindingPlan -Quiet })
    $state.RH1IssueButton.Add_Click({ Refresh-RHIntegratedBindingPlan -Quiet })
    Refresh-RHIntegratedBindingPlan -Quiet
}
