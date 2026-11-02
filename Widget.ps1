param([switch]$UiTest)
$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'Backend.cs')
if ($UiTest) { $testOutput = Join-Path $PSScriptRoot 'work'; [void](New-Item -ItemType Directory -Path $testOutput -Force) }
$codex = Get-Command codex.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
if (!$codex) {
    $codex = Get-ChildItem "$env:LOCALAPPDATA\OpenAI\Codex\bin\*\codex.exe" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (!$codex -and !$UiTest) {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show('Codex was not found. Install Codex for Windows and sign in to your own ChatGPT account.', 'Codex Limits')
    exit 1
}
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
if ($UiTest -and !$codex) { $codex = 'codex.exe' }
$backend = New-Object LimitsBackend($codex, $codexHome)
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing
if (!$UiTest) {
$mutex = New-Object Threading.Mutex($false, 'Local\CodexLimitsWidget')
$showSignal = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::AutoReset, 'Local\CodexLimitsWidgetShow')
if (!$mutex.WaitOne(0)) { [void]$showSignal.Set(); $showSignal.Dispose(); exit }
}
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Codex Limits" Width="312" Height="240" MinWidth="110" MinHeight="65" SizeToContent="Manual" WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="CanResize" Topmost="True" ShowInTaskbar="False" FontFamily="Segoe UI" Foreground="#ECECEC">
 <Viewbox x:Name="Scaler" Stretch="Uniform"><Border x:Name="Design" Width="312" Background="#212121" BorderBrush="#424242" BorderThickness="1" CornerRadius="16" Padding="18,14,18,16">
  <StackPanel>
   <Grid x:Name="Header" Background="Transparent" Margin="0,0,0,14">
    <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <StackPanel><TextBlock Text="Codex" FontSize="17" FontWeight="SemiBold"/><TextBlock x:Name="Subtitle" Text="Remaining limits" Foreground="#A6A6A6" FontSize="11" Margin="0,2,0,0"/></StackPanel>
    <Button x:Name="Settings" Grid.Column="1" Content="&#xE713;" FontFamily="Segoe MDL2 Assets" ToolTip="Settings" FontSize="16" Width="26" Height="28" Foreground="#CFCFCF" Background="Transparent" BorderThickness="0" Cursor="Hand"/>
    <Button x:Name="Refresh" Grid.Column="2" Content="↻" ToolTip="Refresh" FontSize="19" Width="28" Height="28" Foreground="#CFCFCF" Background="Transparent" BorderThickness="0" Cursor="Hand"/>
    <Button x:Name="Hide" Grid.Column="3" Content="−" ToolTip="Hide to tray" FontSize="19" Width="28" Height="28" Foreground="#CFCFCF" Background="Transparent" BorderThickness="0" Cursor="Hand"/>
   </Grid>
   <StackPanel x:Name="Rows"/>
   <TextBlock x:Name="Status" Text="Connecting to Codex…" Foreground="#A6A6A6" FontSize="10" TextWrapping="Wrap" Margin="0,8,0,0"/>
  </StackPanel>
 </Border></Viewbox>
</Window>
'@
$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$rows = $window.FindName('Rows'); $status = $window.FindName('Status')
$settingsFile = Join-Path $PSScriptRoot 'position.json'
$area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$window.Left = $area.Right - 336; $window.Top = $area.Top + 24
try {
    if (Test-Path $settingsFile) {
        $position = Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json
        $window.Left = [double]$position.Left; $window.Top = [double]$position.Top
    }
} catch { }
$script:pending = $null; $script:lastAttempt = [datetime]::MinValue; $script:lastSuccess = $null; $script:windows = @(); $script:failed = $false
function Start-Refresh {
    if ($script:pending) { return }
    $script:lastAttempt = Get-Date
    $script:pending = $backend.FetchAsync()
    $status.Text = 'Refreshing…'
}
function Format-Duration($minutes) {
    if ($minutes -ge 1440) { return ('{0:0.#}d' -f ($minutes / 1440)) }
    if ($minutes -ge 60) { return ('{0:0.#}h' -f ($minutes / 60)) }
    return "$minutes min"
}
function Draw-Rows {
    $rows.Children.Clear()
    foreach ($entry in $script:windows) {
        $item = $entry.Window
        $remaining = [math]::Max(0, [math]::Min(100, 100 - [double]$item.usedPercent))
        $panel = New-Object Windows.Controls.StackPanel
        $panel.Margin = '0,0,0,12'
        $grid = New-Object Windows.Controls.Grid
        $label = New-Object Windows.Controls.TextBlock
        $label.Text = $entry.Label; $label.FontSize = 12; $label.Foreground = '#CDCDCD'
        $number = New-Object Windows.Controls.TextBlock
        $number.Text = ('{0:0.#}%' -f $remaining); $number.FontSize = 14; $number.FontWeight = 'SemiBold'; $number.HorizontalAlignment = 'Right'
        [void]$grid.Children.Add($label); [void]$grid.Children.Add($number); [void]$panel.Children.Add($grid)
        $bar = New-Object Windows.Controls.ProgressBar
        $bar.Minimum = 0; $bar.Maximum = 100; $bar.Value = $remaining; $bar.Height = 5; $bar.Margin = '0,7,0,5'; $bar.BorderThickness = 0; $bar.Background = '#3B3B3B'
        $bar.Foreground = if ($remaining -le 10) { '#F08080' } elseif ($remaining -le 25) { '#E7B86A' } else { '#9AD7C3' }
        [void]$panel.Children.Add($bar)
        $reset = New-Object Windows.Controls.TextBlock
        $reset.FontSize = 10; $reset.Foreground = '#999999'
        if ($null -ne $item.resetsAt) {
            $date = [DateTimeOffset]::FromUnixTimeSeconds([long]$item.resetsAt).LocalDateTime
            $delta = $date - (Get-Date)
            if ($delta.TotalSeconds -le 0) { $reset.Text = 'Reset is due · waiting for fresh data' }
            else {
                $hours = [math]::Floor($delta.TotalHours)
                $reset.Text = ('Resets in {0}h {1:00}m · {2}' -f $hours, $delta.Minutes, $date.ToString('dd.MM HH:mm'))
            }
        } else { $reset.Text = 'Reset time unavailable' }
        [void]$panel.Children.Add($reset); [void]$rows.Children.Add($panel)
    }
}
function Read-Limits($result) {
    $script:windows = @()
    $buckets = @()
    if ($result.rateLimitsByLimitId) {
        $buckets = @($result.rateLimitsByLimitId.PSObject.Properties | ForEach-Object { $_.Value })
    } elseif ($result.rateLimits) { $buckets = @($result.rateLimits) }
    foreach ($bucket in $buckets) {
        foreach ($name in @('primary','secondary')) {
            $item = $bucket.$name
            if ($null -eq $item -or $null -eq $item.usedPercent) { continue }
            $label = if ($null -ne $item.windowDurationMins) { Format-Duration $item.windowDurationMins } else { if ($name -eq 'primary') { 'Primary limit' } else { 'Secondary limit' } }
            if ($buckets.Count -gt 1) { $label = "$($bucket.limitId) · $label" }
            $script:windows += @{ Window = $item; Label = $label }
        }
    }
    if (!$script:windows.Count) { throw 'No limits returned. Check that Codex is signed in with ChatGPT.' }
    Draw-Rows
}
. (Join-Path $PSScriptRoot 'Views.ps1')
. (Join-Path $PSScriptRoot 'Resize.ps1')
if ($UiTest) {
    $resetAt = [DateTimeOffset]::UtcNow.AddHours(3).ToUnixTimeSeconds()
    $script:windows = @(
        @{Window=@{usedPercent=25;windowDurationMins=300;resetsAt=$resetAt};Label='5h'},
        @{Window=@{usedPercent=60;windowDurationMins=10080;resetsAt=$resetAt};Label='7d'}
    )
    $script:lastSuccess = Get-Date
    foreach ($mode in @('standard','compact')) {
        foreach ($limits in @('both','five','week')) {
            $script:preferences.View = $mode; $script:preferences.Limits = $limits
            Draw-Rows
            $expected = if ($limits -eq 'both') { 2 } else { 1 }
            if ($rows.Children.Count -ne $expected) { throw "Unexpected limit count: $mode $limits" }
            $root = $window.Content
            $root.Measure([Windows.Size]::new($window.Width,[double]::PositiveInfinity))
            $root.Arrange([Windows.Rect]::new(0,0,$window.Width,$root.DesiredSize.Height))
            $root.UpdateLayout()
            $image = [Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.Width,[int][math]::Ceiling($root.ActualHeight),96,96,[Windows.Media.PixelFormats]::Pbgra32)
            $image.Render($root)
            $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
            $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
            $path = Join-Path $testOutput "preview-$mode-$limits.png"
            $stream = [IO.File]::Create($path)
            try { $encoder.Save($stream) } finally { $stream.Dispose() }
        }
    }
    foreach ($seconds in @(5,10,30,60,120)) {
        $script:preferences.Interval = $seconds; Update-Status
        if (!$status.Text.EndsWith("$seconds s")) { throw 'Invalid refresh interval' }
    }
    foreach ($remaining in @(0,25,50,75,100)) {
        $ring = New-Object QuotaRing; $ring.Remaining = $remaining
        $ring.Measure([Windows.Size]::new(76,76)); $ring.Arrange([Windows.Rect]::new(0,0,76,76))
        $image = [Windows.Media.Imaging.RenderTargetBitmap]::new(76,76,96,96,[Windows.Media.PixelFormats]::Pbgra32)
        $image.Render($ring)
    }
    . (Join-Path $PSScriptRoot 'tests/Check-WidgetLayout.ps1')
    'UI checks passed: six layouts, five intervals, ring boundaries.'
    $backend.Dispose()
    exit
}
Draw-Rows
$tray = New-Object System.Windows.Forms.NotifyIcon
$iconPath = Join-Path $PSScriptRoot 'codex-limits.ico'
$tray.Icon = New-Object System.Drawing.Icon($iconPath, 32, 32)
$window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]$iconPath)
$tray.Text = 'Codex · remaining limits'; $tray.Visible = $true
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$toggle = $menu.Items.Add('Show / hide')
$update = $menu.Items.Add('Refresh')
$settingsItem = $menu.Items.Add('Settings')
$exit = $menu.Items.Add('Exit')
$tray.ContextMenuStrip = $menu
$showHide = { if ($window.IsVisible) { $window.Hide() } else { $window.Show(); $window.Activate() } }
$toggle.Add_Click($showHide); $tray.Add_DoubleClick($showHide)
$settingsItem.Add_Click({ Open-Settings }); $window.FindName('Settings').Add_Click({ Open-Settings })
$update.Add_Click({ Start-Refresh }); $exit.Add_Click({ $window.Close() })
$window.FindName('Hide').Add_Click({ $window.Hide() })
$window.FindName('Refresh').Add_Click({ Start-Refresh })
$window.FindName('Header').Add_MouseLeftButtonDown({
    $node = $_.OriginalSource
    while ($node -and $node -isnot [Windows.Controls.Button]) { $node = [Windows.Media.VisualTreeHelper]::GetParent($node) }
    if (!$node) { $window.DragMove() }
})
$window.Add_Closing({
    Save-WidgetPreferences
    try { @{ Left = $window.Left; Top = $window.Top } | ConvertTo-Json | Set-Content -LiteralPath $settingsFile -Encoding UTF8 } catch { }
    $timer.Stop(); $tray.Visible = $false; $tray.Dispose(); $backend.Dispose(); $showSignal.Dispose(); $mutex.ReleaseMutex(); $mutex.Dispose()
})
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
    if ($script:resizeDirty -and ((Get-Date) - $script:lastResize).TotalSeconds -ge 1) { Save-WidgetPreferences; $script:resizeDirty = $false }
    if ($showSignal.WaitOne(0)) { $window.Show(); [void]$window.Activate() }
    if ($script:pending -and $script:pending.IsCompleted) {
        try {
            if ($script:pending.IsFaulted) { throw $script:pending.Exception.GetBaseException().Message }
            $response = $script:pending.Result | ConvertFrom-Json
            if ($response.error) { throw $response.error.message }
            Read-Limits $response.result
            $script:lastSuccess = Get-Date; $script:failed = $false
            Update-Status
        } catch {
            $script:failed = $true
            $status.Text = 'No fresh data. ' + $_.Exception.Message
            if ($script:lastSuccess) { $status.Text += ' · Last update: ' + $script:lastSuccess.ToString('HH:mm') }
        } finally { $script:pending = $null }
    }
    if (((Get-Date) - $script:lastAttempt).TotalSeconds -ge $script:preferences.Interval) { Start-Refresh }
})
$timer.Start()
$window.Add_ContentRendered({ Start-Refresh })
try { [void]$window.ShowDialog() } finally { $backend.Dispose() }
