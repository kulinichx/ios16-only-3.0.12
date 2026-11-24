# RootHide supporter binding integration v1. Dot-source from the original issuer.

function Get-RHProofResultText([string]$Code, [bool]$Migration = $false) {
    switch ($Code) {
        'BOUND' { $meaning = '首次设备绑定成功'; $next = '如果尚未签发 RH1，先完成首次签发。然后选中对应记录，点击「补发选中绑定」。' }
        'MATCH' { $meaning = '硬件和设备密钥均与历史记录一致'; $next = '如需恢复授权，选中原记录后点击「补发选中绑定」。' }
        'SAME_DEVICE' { $meaning = '硬件和设备密钥均与原设备一致'; $next = '如需恢复绑定授权，关闭窗口，选中原记录后点击「补发选中绑定」。设备码变更验证仅用于比对。' }
        'REVIEW_KEY_MISMATCH' {
            $meaning = '硬件一致，设备密钥已变化'
            $next = if ($Migration) {
                '关闭窗口，在原记录上生成普通 RHC1，让用户重新生成证明。主界面显示「同设备 · 密钥待复核」后，点击「同设备换密钥」。'
            } else {
                '「补发选中绑定」暂不可用。关闭提示，选中原记录，先点击「同设备换密钥」并核对用户编号；确认迁移后，补发按钮才会启用。'
            }
        }
        'HARDWARE_MISMATCH' { $meaning = '硬件与历史记录不符'; $next = '停止按原机补发，核实用户身份和设备归属。' }
        'LEGACY_UNBOUND' { $meaning = '历史记录缺少可比对的设备证明'; $next = '人工核实用户和原设备归属，确认后再处理首次绑定。' }
        'TARGET_CODE_CONFLICT' { $meaning = '新设备码已属于其他用户'; $next = '核对录入的设备码和对应的历史记录。' }
        default { $meaning = '未知验证结果'; $next = '暂停补发，记录返回码并核对工具版本。' }
    }
    return "$meaning（$Code）`r`n`r`n下一步 · $next"
}

function Get-RHProofErrorText([string]$Message, [bool]$Migration = $false) {
    $generate = if ($Migration) { '生成 Migration RHC1' } else { '生成 RHC1' }
    $next = switch -Regex ($Message) {
        '^challenge-(expired|consumed)' { "点击「$generate」，发给用户生成一份新的证明。"; break }
        '^challenge-mode-mismatch' { '回到生成这条验证文本的入口，再验证对应的证明。'; break }
        '^challenge-(not-found|mismatch)' { "核对当前签发工具和用户记录，点击「$generate」并让用户重新生成证明。"; break }
        '^NO_CHANGE' { '在原记录上用普通 RHC1/RHP1 验证。'; break }
        '^TARGET_CODE_CONFLICT' { '检查新设备码对应的历史记录，暂停变更。'; break }
        '^migration-source-' { '重新载入原用户，核对历史记录后再试。'; break }
        '^请输入有效的 NEW Device Code' { '从手机授权页复制完整的设备码，填入「新设备码」。'; break }
        '^设备证明已验证，但复核记录保存失败' { '检查签发目录能否写入。恢复后重新生成普通 RHC1 并验证。'; break }
        'Git Bash|OpenSSL' { '检查 Git Bash 和 OpenSSL 是否可用，再重新验证。'; break }
        default { '核对剪贴板里是否为完整的 RHP1，按下方详情排查后再试。' }
    }
    return "下一步 · $next`r`n`r`n详情 · $Message"
}

function Format-RHReportedDevice([string]$Model, [string]$Version) {
    if (-not $Model -or -not $Version) { return '未上报' }
    if ($Model -in @('iOS', 'iPadOS')) { return "型号未上报 · $Model $Version" }
    $system = if ($Model.StartsWith('iPad', [StringComparison]::OrdinalIgnoreCase)) { 'iPadOS' } else { 'iOS' }
    return "$Model · $system $Version"
}

function Get-RHDeviceInfoRow([string]$DeviceCode) {
    if (-not $DeviceCode) { return $null }
    return $script:RHDeviceInfo.Rows[$DeviceCode]
}

function Update-RHDeviceInfoDisplay {
    $state = $script:RHDeviceInfo
    $device = Normalize-DeviceCode $state.Device.Text
    $row = Get-RHDeviceInfoRow $device
    $pending = $state.Pending[$device]
    $state.Info.Text = if ($null -ne $pending) {
        (Format-RHReportedDevice $pending.DeviceModel $pending.OSVersion) + '（密钥待复核）'
    } elseif ($null -ne $row) {
        Format-RHReportedDevice $row.DeviceModel $row.OSVersion
    } elseif ($state.ReadError) { '设备信息记录无法载入' } else { '未上报' }
}

function Save-RHConfirmedDeviceInfo([string]$DeviceCode, [string]$Model, [string]$Version) {
    $state = $script:RHDeviceInfo
    if (-not (Test-RHProofDeviceInfo $Model $Version)) { return }
    if ($state.ReadError) { throw '设备信息记录无法读取，已保留原文件。' }
    $row = [pscustomobject]@{ DeviceCode = $DeviceCode; DeviceModel = $Model; OSVersion = $Version }
    $rows = @($state.Rows.Values | Where-Object { $_.DeviceCode -ne $DeviceCode }) + $row
    Save-JsonArrayAtomic $state.Path $rows
    $state.Rows[$DeviceCode] = $row
    $state.Pending.Remove($DeviceCode)
    Update-RHDeviceInfoDisplay
}

function Show-RHProofDeviceInfo($Result, [string]$OriginalDeviceCode) {
    $state = $script:RHDeviceInfo
    $previous = Get-RHDeviceInfoRow $OriginalDeviceCode
    $previousText = if ($null -ne $previous) {
        Format-RHReportedDevice $previous.DeviceModel $previous.OSVersion
    } else { '未上报' }
    $currentText = Format-RHReportedDevice $Result.DeviceModel $Result.OSVersion
    $lines = @("上次确认 · $previousText", "本次上报 · $currentText")
    $state.Pending.Remove($OriginalDeviceCode)
    if ((Test-RHProofDeviceInfo $Result.DeviceModel $Result.OSVersion) -and $Result.Policy -eq 'REVIEW_KEY_MISMATCH') {
        $state.Pending[$OriginalDeviceCode] = [pscustomobject]@{
            DeviceModel = $Result.DeviceModel; OSVersion = $Result.OSVersion
        }
    }
    Update-RHDeviceInfoDisplay
    if ((Test-RHProofDeviceInfo $Result.DeviceModel $Result.OSVersion) -and $Result.Policy -in @('BOUND', 'MATCH', 'SAME_DEVICE')) {
        if ($state.ReadError) { return $lines + '设备信息记录无法读取，已保留原文件。' }
        try {
            Save-RHConfirmedDeviceInfo $OriginalDeviceCode $Result.DeviceModel $Result.OSVersion
        } catch {
            $lines += '设备信息未保存，请检查签发目录。'
        }
    }
    return $lines
}

function Initialize-RHDeviceInfo($Panel, $Device, $Name) {
    $state = @{
        Device = $Device
        Path = Join-Path $script:BaseDir 'supporter-device-info.json'
        Rows = @{}
        Pending = @{}
        ReadError = $false
    }
    $script:RHDeviceInfo = $state
    if (Test-Path -LiteralPath $state.Path) {
        try {
            $stored = Get-Content -LiteralPath $state.Path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($row in @($stored)) {
                if ($null -eq $row -or -not (Test-DeviceCodeFormat $row.DeviceCode) -or
                    -not (Test-RHProofDeviceInfo $row.DeviceModel $row.OSVersion) -or $state.Rows.ContainsKey($row.DeviceCode)) {
                    throw 'invalid-device-info-store'
                }
                $state.Rows[$row.DeviceCode] = $row
            }
        } catch {
            $state.Rows.Clear()
            $state.ReadError = $true
        }
    }
    $label = New-Object Windows.Forms.Label
    $label.Text = '设备型号 / 系统版本'
    $label.AutoSize = $true
    $label.ForeColor = $colorMuted
    $label.Location = New-Object Drawing.Point(396, 113)
    $Panel.Controls.Add($label)
    $Name.Anchor = 'Top, Left'
    $Name.Width = 362
    $info = New-Object Windows.Forms.TextBox
    $info.SetBounds(396, 135, ($Device.Right - 396), 28)
    $info.Anchor = 'Top, Left, Right'
    Style-TextBox $info $true
    $Panel.Controls.Add($info)
    $state.Info = $info
    $Device.Add_TextChanged({ Update-RHDeviceInfoDisplay })
    Update-RHDeviceInfoDisplay
}

function Test-RHProofDeviceInfo($Model, $Version) {
    return $Model -is [string] -and $Model -cmatch '\A[A-Za-z0-9][A-Za-z0-9 ,().+\-]{0,63}\z' -and
        $Version -is [string] -and $Version -cmatch '\A[1-9][0-9]{0,2}(?:\.(?:0|[1-9][0-9]{0,2})){1,2}\z'
}

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
        $message = "#$id 的绑定密钥已迁移，原 RH1 没有改变。`r`n备份：$($result.backup)`r`n请再点补发选中绑定，使用新的文件名输出，将 RH1 + RHB1 一起粘贴到设备激活。"
        if ((Get-Variable RHDeviceInfo -Scope Script -ErrorAction SilentlyContinue) -and
            $null -ne $result.PSObject.Properties['deviceModel'] -and
            (Test-RHProofDeviceInfo $result.deviceModel $result.osVersion)) {
            try { Save-RHConfirmedDeviceInfo $record.deviceCode $result.deviceModel $result.osVersion }
            catch { $message += "`r`n设备密钥迁移已完成，但设备信息未保存，请检查签发目录。" }
        }
        Show-RHIntegratedBindingMessage $message
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
            Refresh-RHIntegratedBindingPlan -Quiet
            foreach ($row in $script:RHIntegratedBinding.Grid.Rows) {
                $record = $script:RHIntegratedBinding.ById[[string]$row.Cells['ID'].Value]
                if ($null -ne $record -and $record.deviceCode -eq $result.DeviceCode) {
                    $script:RHIntegratedBinding.Grid.ClearSelection()
                    $row.Selected = $true
                    break
                }
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
