# Profile editing is independent of license issuance and device binding.

function Get-RHProfileField($Record, [string]$Name) {
    $property = $Record.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
}

function Get-RHProfileSummary($Record) {
    return (@([string](Get-RHProfileField $Record 'Contact'), [string]$Record.Note) | Where-Object { $_ }) -join ' / '
}

function Test-RHProfileSearch($Record, [string]$Query) {
    $values = @($Record.SupporterId, $Record.DisplayName, $Record.DeviceCode, $Record.Note,
        (Get-RHProfileField $Record 'Contact')) + @(Get-RHProfileField $Record 'PreviousDisplayNames')
    foreach ($value in $values) {
        $text = [string]$value
        if (-not [string]::IsNullOrEmpty($text) -and $text.IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    return $false
}

function Get-RHProfileHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)) } finally { $sha.Dispose() }
}

function Get-RHProfileSnapshot($Record) {
    $bytes = [IO.File]::ReadAllBytes($script:RecordsPath)
    $parsed = [Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
    $rows = @($parsed)
    $matches = @($rows | Where-Object { [string]$_.SupporterId -ceq [string]$Record.SupporterId -and [string]$_.DeviceCode -ceq [string]$Record.DeviceCode })
    if ($matches.Count -ne 1) { throw '原用户记录已变化或存在重复，请重启工具并重新载入。' }
    if (($matches[0] | ConvertTo-Json -Depth 32 -Compress) -cne ($Record | ConvertTo-Json -Depth 32 -Compress)) {
        throw '用户资料已被其他操作更新，请重启工具并重新载入。'
    }
    return @{ Hash = Get-RHProfileHash $bytes; Record = $matches[0] }
}

function Write-RHProfileDatabase([string]$Temporary, [string]$Destination, [string]$Backup) {
    [IO.File]::Replace($Temporary, $Destination, $Backup)
}

function Save-RHProfile($Snapshot, [string]$DisplayName, [string]$Contact, [string]$Note) {
    $name = $DisplayName.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { throw '用户名不能为空。' }
    if ($name.Length -gt 200 -or $Contact.Length -gt 2000 -or $Note.Length -gt 10000) { throw '资料过长：用户名最多 200 字、联系方式 2000 字、备注 10000 字。' }
    $bytes = [IO.File]::ReadAllBytes($script:RecordsPath)
    if ((Get-RHProfileHash $bytes) -cne $Snapshot.Hash) { throw '记录文件已变化，请关闭编辑窗口，重启工具后重新载入。' }
    $parsed = [Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
    $rows = @($parsed)
    $matches = @($rows | Where-Object { [string]$_.SupporterId -ceq [string]$Snapshot.Record.SupporterId -and [string]$_.DeviceCode -ceq [string]$Snapshot.Record.DeviceCode })
    if ($matches.Count -ne 1) { throw '找不到唯一的原用户记录。' }
    $record = $matches[0]
    $aliases = @(Get-RHProfileField $record 'PreviousDisplayNames')
    if ([string]$record.DisplayName -cne $name -and -not [string]::IsNullOrWhiteSpace([string]$record.DisplayName)) {
        $aliases = @($aliases + [string]$record.DisplayName | Select-Object -Unique)
    }
    $record.DisplayName = $name
    $record.Note = $Note
    $record | Add-Member -NotePropertyName Contact -NotePropertyValue $Contact.Trim() -Force
    $record | Add-Member -NotePropertyName PreviousDisplayNames -NotePropertyValue @($aliases) -Force
    $directory = Split-Path -Parent $script:RecordsPath
    $backupDirectory = Join-Path $directory 'profile-backups'
    [void][IO.Directory]::CreateDirectory($backupDirectory)
    $token = [Guid]::NewGuid().ToString('N')
    $temporary = Join-Path $directory ('.profile-' + $token + '.tmp')
    $backup = Join-Path $backupDirectory ('supporters-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $token + '.json')
    try {
        $json = ConvertTo-Json -InputObject @($rows) -Depth 32
        [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false)))
        if ((Get-RHProfileHash ([IO.File]::ReadAllBytes($script:RecordsPath))) -cne $Snapshot.Hash) { throw '保存前记录文件已变化，请重新载入。' }
        Write-RHProfileDatabase $temporary $script:RecordsPath $backup
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
    $script:Records = @($rows)
    return @{ Record = $record; Backup = $backup }
}

function Show-RHProfileEditor($Record) {
    try { $snapshot = Get-RHProfileSnapshot $Record } catch { Show-Error $_.Exception.Message; return }
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = '修改用户资料 · #' + [string]$Record.SupporterId
    $dialog.StartPosition = 'CenterParent'
    $dialog.ClientSize = New-Object Drawing.Size(620, 510)
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.BackColor = $colorSurface
    $dialog.ForeColor = $colorText
    $dialog.Font = $form.Font
    $identity = New-Object Windows.Forms.Label
    $identity.SetBounds(20, 15, 580, 66)
    $identity.Text = 'Supporter #' + [string]$Record.SupporterId + ' · ' + [string]$Record.DeviceCode + "`r`n旧资料中的联系方式仍保留在备注，可手动整理到联系方式。"
    $dialog.Controls.Add($identity)
    $fields = @{}
    foreach ($item in @(@('Name', '用户名', 85, 30, [string]$Record.DisplayName),
        @('Contact', '联系方式', 152, 62, [string](Get-RHProfileField $Record 'Contact')),
        @('Note', '备注', 251, 110, [string]$Record.Note))) {
        $label = New-Object Windows.Forms.Label
        $label.Text = $item[1]
        $label.SetBounds(20, ([int]$item[2]), 580, 23)
        $dialog.Controls.Add($label)
        $box = New-Object Windows.Forms.TextBox
        $box.Multiline = $item[0] -ne 'Name'
        $box.SetBounds(20, ([int]$item[2] + 25), 580, ([int]$item[3]))
        Style-TextBox $box
        $box.Text = $item[4]
        $fields[$item[0]] = $box
        $dialog.Controls.Add($box)
    }
    $previous = New-Object Windows.Forms.Label
    $previous.SetBounds(20, 393, 580, 49)
    $previous.Text = '历史用户名：' + (@(Get-RHProfileField $Record 'PreviousDisplayNames') -join '、') + "`r`n保存后可搜索新名、旧名、联系方式、ID 或设备码。"
    $dialog.Controls.Add($previous)
    $save = New-Object Windows.Forms.Button
    $save.Text = '保存资料'
    $save.SetBounds(360, 458, 116, 32)
    Style-PrimaryButton $save
    $dialog.Controls.Add($save)
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = '取消'
    $cancel.SetBounds(488, 458, 112, 32)
    Style-SecondaryButton $cancel
    $cancel.DialogResult = 'Cancel'
    $dialog.CancelButton = $cancel
    $dialog.Controls.Add($cancel)
    $save.Add_Click({
        try {
            $result = Save-RHProfile $snapshot $fields.Name.Text $fields.Contact.Text $fields.Note.Text
            $updated = $result.Record
            if ($null -ne $script:LoadedRecord -and [string]$script:LoadedRecord.DeviceCode -ceq [string]$updated.DeviceCode) {
                $script:LoadedRecord = $updated
            }
            if ((Normalize-DeviceCode $txtDevice.Text) -ceq [string]$updated.DeviceCode) {
                $txtName.Text = [string]$updated.DisplayName
                $txtNote.Text = [string]$updated.Note
            }
            Refresh-Grid
            Refresh-RHIntegratedBindingPlan -Quiet
            $grid.ClearSelection()
            foreach ($row in $grid.Rows) {
                if ([string]$row.Cells['设备码'].Value -ceq [string]$updated.DeviceCode) { $row.Selected = $true; break }
            }
            $status.Text = '资料已保存 · #' + [string]$updated.SupporterId + ' · 已自动备份'
            $dialog.DialogResult = 'OK'
            $dialog.Close()
        } catch { Show-Error $_.Exception.Message }
    })
    try { [void]$dialog.ShowDialog($form) } finally { $dialog.Dispose() }
}

function Initialize-RHProfileIntegration {
    $txtSearch.Width = 245
    $txtSearch.Anchor = 'Top,Left,Right'
    $button = New-Object Windows.Forms.Button
    $button.Text = '修改资料'
    $button.SetBounds(400, 9, 90, 32)
    $button.Anchor = 'Top,Right'
    Style-SecondaryButton $button
    $historyPanel.Controls.Add($button)
    $button.Add_Click({
        $record = $script:LoadedRecord
        if ($null -eq $record) { $record = Get-SelectedRecord }
        if ($null -eq $record) { Show-Info '请先选择或载入一条历史记录。'; return }
        Show-RHProfileEditor $record
    })
}
