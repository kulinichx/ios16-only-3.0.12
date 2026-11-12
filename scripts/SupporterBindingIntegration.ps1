# RootHide supporter binding integration v1. Dot-source from the original issuer.

function Invoke-RHIntegratedBinding([string[]]$Arguments, [string]$InputText = '') {
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
    $start.RedirectStandardInput = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if ($InputText) {
            $bytes = [Text.Encoding]::UTF8.GetBytes($InputText)
            $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        }
        $process.StandardInput.Close()
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
            elseif ($record.status -eq 'REVIEW_KEY_MISMATCH') { '同设备 · 密钥待复核' }
            elseif ($record.status -eq 'HARDWARE_MISMATCH') { '硬件不符 · 禁止补发' }
            elseif ($record.status -eq 'REVERIFY_REQUIRED') { '需重新验证设备证明' }
            else { '待设备证明' }
        $row.Cells['RHBindingState'].Value = $text
        $row.Cells['RHBindingState'].ToolTipText = $(if ($state.Error) { $state.Error } else { $text })
    }
    $selected = $null
    if ($state.Grid.SelectedRows.Count -eq 1) {
        $selected = $state.ById[[string]$state.Grid.SelectedRows[0].Cells['ID'].Value]
    }
    $allowed = -not $state.Busy -and -not $state.GuardFailure
    $state.Single.Enabled = $allowed -and $null -ne $selected -and $selected.status -eq 'READY_FOR_REVIEW'
    $state.Batch.Enabled = $allowed -and $null -ne $state.Plan -and $state.Plan.eligible -gt 0
    $state.Rekey.Enabled = $allowed -and $null -ne $selected -and $selected.status -eq 'REVIEW_KEY_MISMATCH'
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
    if ($state.GuardFailure) { $state.Status.Text = '设备复核记录未保存，绑定补发已暂停；请重新生成并验证刚才设备的证明。' }
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
    if ($state.Busy -or $state.GuardFailure -or $null -eq $state.Plan) { return }
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

function New-RHIntegratedKeyReview($Plan) {
    $state = $script:RHIntegratedBinding
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = '确认同设备换密钥'
    $dialog.ClientSize = New-Object Drawing.Size(710, 390)
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.StartPosition = 'CenterParent'
    $dialog.Font = $state.Form.Font
    $dialog.BackColor = $state.Form.BackColor
    $dialog.ForeColor = $state.Form.ForeColor
    $details = New-Object Windows.Forms.TextBox
    $details.SetBounds(18, 18, 674, 235)
    $details.Multiline = $true
    $details.ReadOnly = $true
    $details.TabStop = $false
    $details.ScrollBars = 'Vertical'
    $details.BackColor = $state.Grid.BackgroundColor
    $details.ForeColor = $state.Form.ForeColor
    $details.Text = "用户：#$($Plan.id) · $($Plan.displayName)`r`n设备码：$($Plan.deviceCode)`r`n硬件摘要：$($Plan.hardwareHash)`r`n旧密钥：$($Plan.oldKeyFingerprint)`r`n新密钥：$($Plan.newKeyFingerprint)`r`n备注：$($Plan.note)`r`n`r`n仅替换这台设备的绑定密钥，并备份旧记录。原 RH1 不变；不会自动签发授权。"
    $dialog.Controls.Add($details)
    $label = New-Object Windows.Forms.Label
    $label.Text = "核对设备属于本人后，输入用户编号 $($Plan.id) 确认："
    $label.SetBounds(18, 266, 674, 24)
    $dialog.Controls.Add($label)
    $input = New-Object Windows.Forms.TextBox
    $input.Name = 'SupporterIdConfirmation'
    $input.SetBounds(18, 297, 230, 28)
    $input.BackColor = $state.Grid.BackgroundColor
    $input.ForeColor = $state.Form.ForeColor
    $dialog.Controls.Add($input)
    $dialog.ActiveControl = $input
    $confirm = New-Object Windows.Forms.Button
    $confirm.Text = '确认迁移'
    $confirm.SetBounds(430, 341, 126, 32)
    $confirm.DialogResult = 'OK'
    $confirm.Enabled = $false
    Style-PrimaryButton $confirm
    $dialog.Controls.Add($confirm)
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = '取消'
    $cancel.SetBounds(566, 341, 126, 32)
    $cancel.DialogResult = 'Cancel'
    Style-SecondaryButton $cancel
    $dialog.Controls.Add($cancel)
    $dialog.CancelButton = $cancel
    $dialog.Tag = [pscustomobject]@{ Input = $input; Confirm = $confirm; Id = [string]$Plan.id }
    $input.Add_TextChanged({
        $review = $this.FindForm().Tag
        $review.Confirm.Enabled = [string]::Equals($review.Input.Text, $review.Id, [StringComparison]::Ordinal)
    })
    return $dialog
}

function Confirm-RHIntegratedKeyReview($Plan) {
    $dialog = New-RHIntegratedKeyReview $Plan
    try {
        if ($dialog.ShowDialog($script:RHIntegratedBinding.Form) -eq 'OK') { return $dialog.Tag.Input.Text }
        return ''
    } finally { $dialog.Dispose() }
}

function Start-RHIntegratedKeyMigration {
    $state = $script:RHIntegratedBinding
    if ($state.Busy -or $state.GuardFailure -or $state.Grid.SelectedRows.Count -ne 1) { return }
    $id = [string]$state.Grid.SelectedRows[0].Cells['ID'].Value
    $record = $state.ById[$id]
    if ($null -eq $record -or $record.status -ne 'REVIEW_KEY_MISMATCH') { return }
    $state.Busy = $true
    Update-RHIntegratedBindingControls
    try {
        $plan = Invoke-RHIntegratedBinding @('rekey-plan', '--issuer-dir', $state.Directory, '--id', $id)
        $confirmation = Confirm-RHIntegratedKeyReview $plan
        if (-not [string]::Equals($confirmation, $id, [StringComparison]::Ordinal)) { return }
        $result = Invoke-RHIntegratedBinding @('rekey', '--issuer-dir', $state.Directory, '--id', $id,
            '--review-sha256', ([string]$plan.reviewSha256), '--confirm-id', $confirmation)
        Load-DeviceProofState
        Refresh-RHIntegratedBindingPlan -Quiet
        $state.Output.Clear()
        $state.Status.Text = "#$id 已迁移设备密钥 · 尚未补发授权"
        Show-RHIntegratedBindingMessage "#$id 的绑定密钥已迁移，原 RH1 没有改变。`r`n备份：$($result.backup)`r`n请再点补发选中绑定，使用新的文件名输出，将 RH1 + RHB1 一起粘贴到 iPad 激活。"
    } catch {
        Refresh-RHIntegratedBindingPlan -Quiet
        Show-RHIntegratedBindingMessage $_.Exception.Message $true
    } finally {
        $state.Busy = $false
        Update-RHIntegratedBindingControls
    }
}

function Install-RHIntegratedProofGuard {
    $script:RHOriginalVerifyProof = (Get-Command Verify-RHP1Proof -CommandType Function -ErrorAction Stop).ScriptBlock
    function script:Verify-RHP1Proof([string]$ProofText, [string]$ExpectedMode = '') {
        Load-DeviceProofState
        $result = & $script:RHOriginalVerifyProof $ProofText $ExpectedMode
        if ($result.Mode -eq 'NORMAL') {
            try {
                $null = Invoke-RHIntegratedBinding @('review-proof', '--issuer-dir', $script:RHIntegratedBinding.Directory) $ProofText
                $script:RHIntegratedBinding.FailedProofDevices.Remove([string]$result.DeviceCode)
                $script:RHIntegratedBinding.GuardFailure = $script:RHIntegratedBinding.FailedProofDevices.Count -gt 0
            } catch {
                $script:RHIntegratedBinding.FailedProofDevices[[string]$result.DeviceCode] = $true
                $script:RHIntegratedBinding.GuardFailure = $true
                try {
                    $null = Invoke-RHIntegratedBinding @('block-key-review', '--issuer-dir', $script:RHIntegratedBinding.Directory,
                        '--device-code', ([string]$result.DeviceCode))
                } catch { }
                Update-RHIntegratedBindingControls
                throw '设备证明已验证，但复核记录保存失败。已暂停绑定补发；请检查磁盘后重新生成并验证设备证明，不要使用历史补发文件。'
            }
        }
        return $result
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
    $state.GuardFailure = $false
    $state.FailedProofDevices = @{}
    $strip = New-Object Windows.Forms.FlowLayoutPanel
    $strip.SetBounds(116, 9, 510, 34)
    $strip.Anchor = 'Top, Left, Right'
    $strip.WrapContents = $false
    $strip.Margin = New-Object Windows.Forms.Padding(0)
    foreach ($spec in @(@('Single', '补发选中绑定', 132), @('Batch', '批量补发', 90), @('Refresh', '刷新绑定', 90),
        @('Rekey', '同设备换密钥', 128))) {
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
    $state.Rekey.Add_Click({ Start-RHIntegratedKeyMigration })
    $state.Grid.Add_DataBindingComplete({ Update-RHIntegratedBindingControls })
    $state.Grid.Add_SelectionChanged({ Update-RHIntegratedBindingControls })
    $state.VerifyProofButton.Add_Click({ Refresh-RHIntegratedBindingPlan -Quiet })
    $state.RH1IssueButton.Add_Click({ Refresh-RHIntegratedBindingPlan -Quiet })
    Install-RHIntegratedProofGuard
    Refresh-RHIntegratedBindingPlan -Quiet
}
