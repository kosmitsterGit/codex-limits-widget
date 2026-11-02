# UI preferences and compact rendering. No account data is stored here.
Add-Type -AssemblyName System.Xaml
$refs = @([System.Xaml.XamlReader].Assembly.Location, [Windows.FrameworkElement].Assembly.Location, [Windows.Media.DrawingContext].Assembly.Location, [Windows.Point].Assembly.Location)
Add-Type -Path (Join-Path $PSScriptRoot 'Rings.cs') -ReferencedAssemblies $refs
$script:preferences = @{ Limits = 'both'; View = 'standard'; Interval = 60; Scale = 1.0 }
$preferencesFile = Join-Path $PSScriptRoot 'settings.json'
if (!$UiTest -and (Test-Path $preferencesFile)) {
    try {
        $saved = Get-Content -LiteralPath $preferencesFile -Raw | ConvertFrom-Json
        if ($saved.Limits -in @('both','five','week')) { $script:preferences.Limits = $saved.Limits }
        if ($saved.View -in @('standard','compact')) { $script:preferences.View = $saved.View }
        if ($saved.Scale -ge 0.4 -and $saved.Scale -le 5) { $script:preferences.Scale = [double]$saved.Scale }
        if ($saved.Interval -in @(5,10,30,60,120)) { $script:preferences.Interval = [int]$saved.Interval }
    } catch { }
}
function Update-Status {
    if ($script:failed -or !$script:lastSuccess) { return }
    $status.Text = if ($script:preferences.View -eq 'compact') { $script:lastSuccess.ToString('HH:mm:ss') + ' · ' + $script:preferences.Interval + ' s' } else { 'Updated ' + $script:lastSuccess.ToString('HH:mm:ss') + ' · every ' + $script:preferences.Interval + ' s' }
}
function Get-VisibleEntries {
    @($script:windows | Where-Object {
        $duration = $_.Window.windowDurationMins
        $script:preferences.Limits -eq 'both' -or
        ($script:preferences.Limits -eq 'five' -and $duration -eq 300) -or
        ($script:preferences.Limits -eq 'week' -and $duration -eq 10080)
    })
}
function Get-ResetText($item) {
    if ($null -eq $item.resetsAt) { return 'Reset time unavailable' }
    $date = [DateTimeOffset]::FromUnixTimeSeconds([long]$item.resetsAt).LocalDateTime
    $delta = $date - (Get-Date)
    if ($delta.TotalSeconds -le 0) { return 'Reset is due · waiting for fresh data' }
    return ('Resets in {0}h {1:00}m · {2}' -f [math]::Floor($delta.TotalHours), $delta.Minutes, $date.ToString('dd.MM HH:mm'))
}
# Retain the standard row renderer and run it on the selected entries.
$script:StandardRows = ${function:Draw-Rows}
function Draw-Rows {
    $allEntries = $script:windows
    $entries = @(Get-VisibleEntries)
    $compact = $script:preferences.View -eq 'compact'
    $window.FindName('Design').Width = if ($compact) { if ($entries.Count -gt 1) { 228 } else { 182 } } else { 312 }
    $window.FindName('Subtitle').Visibility = if ($compact) { 'Collapsed' } else { 'Visible' }
    $rows.Orientation = if ($compact) { 'Horizontal' } else { 'Vertical' }
    $rows.HorizontalAlignment = if ($compact) { 'Center' } else { 'Stretch' }
    $rows.Children.Clear()
    if (!$compact) {
        try { $script:windows = $entries; & $script:StandardRows } finally { $script:windows = $allEntries }
    } else {
        foreach ($entry in $entries) {
            $remaining = [math]::Max(0, [math]::Min(100, 100 - [double]$entry.Window.usedPercent))
            $accent = if ($remaining -le 10) { '#F08080' } elseif ($remaining -le 25) { '#E7B86A' } else { '#9AD7C3' }
            $panel = New-Object Windows.Controls.StackPanel
            $panel.Width = 88; $panel.Margin = '2,0,2,0'; $panel.ToolTip = Get-ResetText $entry.Window
            $grid = New-Object Windows.Controls.Grid
            $grid.Width = 76; $grid.Height = 76
            $ring = New-Object QuotaRing
            $ring.Remaining = $remaining; $ring.Accent = [Windows.Media.BrushConverter]::new().ConvertFromString($accent)
            $number = New-Object Windows.Controls.TextBlock
            $number.Text = ('{0:0.#}%' -f $remaining); $number.FontSize = 17; $number.FontWeight = 'SemiBold'
            $number.HorizontalAlignment = 'Center'; $number.VerticalAlignment = 'Center'
            [void]$grid.Children.Add($ring); [void]$grid.Children.Add($number); [void]$panel.Children.Add($grid)
            $label = New-Object Windows.Controls.TextBlock
            $label.Text = $entry.Label; $label.FontSize = 10; $label.Foreground = '#B8B8B8'; $label.HorizontalAlignment = 'Center'; $label.Margin = '0,4,0,0'
            [void]$panel.Children.Add($label); [void]$rows.Children.Add($panel)
        }
    }
    if (!$entries.Count) {
        $empty = New-Object Windows.Controls.TextBlock
        $empty.Text = if ($allEntries.Count) { 'No data for the selected limit' } else { 'Waiting for data…' }
        $empty.TextWrapping = 'Wrap'; $empty.Foreground = '#A6A6A6'; $empty.FontSize = 11
        [void]$rows.Children.Add($empty)
    }
    Update-Status
    Update-WidgetLayout
}
function Open-Settings {
    param([switch]$Preview)
    [xml]$settingsXaml = '<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Codex Limits Settings" Width="330" SizeToContent="Height" ResizeMode="NoResize" WindowStartupLocation="CenterOwner" Background="#212121" Foreground="#ECECEC" FontFamily="Segoe UI" Topmost="True" ShowInTaskbar="False">
 <Window.Resources>
  <Style TargetType="ComboBoxItem">
   <Setter Property="Foreground" Value="#ECECEC"/><Setter Property="Background" Value="#2B2B2B"/><Setter Property="Padding" Value="10,8"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBoxItem">
    <Border x:Name="ItemBorder" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}" CornerRadius="4"><ContentPresenter/></Border>
    <ControlTemplate.Triggers>
     <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="ItemBorder" Property="Background" Value="#454545"/></Trigger>
     <Trigger Property="IsSelected" Value="True"><Setter TargetName="ItemBorder" Property="Background" Value="#37574C"/></Trigger>
    </ControlTemplate.Triggers>
   </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType="ComboBox">
   <Setter Property="Foreground" Value="#ECECEC"/><Setter Property="Background" Value="#303030"/><Setter Property="BorderBrush" Value="#505050"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBox">
    <Grid>
     <ToggleButton x:Name="Toggle" Focusable="False" IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}" Background="{TemplateBinding Background}" Foreground="{TemplateBinding Foreground}">
      <ToggleButton.Template><ControlTemplate TargetType="ToggleButton">
       <Border x:Name="ToggleBorder" Background="{TemplateBinding Background}" BorderBrush="#505050" BorderThickness="1" CornerRadius="6">
        <Path Data="M 0,0 L 4,4 L 8,0" Stroke="#BEBEBE" StrokeThickness="1.5" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,12,0"/>
       </Border>
       <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ToggleBorder" Property="BorderBrush" Value="#9AD7C3"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></ToggleButton.Template>
     </ToggleButton>
     <ContentPresenter Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" Margin="10,0,30,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
     <Popup x:Name="PART_Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Fade">
      <Border Background="#2B2B2B" BorderBrush="#505050" BorderThickness="1" CornerRadius="6" Padding="4" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}">
       <ScrollViewer MaxHeight="240" CanContentScroll="True"><ItemsPresenter/></ScrollViewer>
      </Border>
     </Popup>
    </Grid>
   </ControlTemplate></Setter.Value></Setter>
  </Style>
 </Window.Resources>

 <StackPanel Margin="22">
  <TextBlock Text="Widget settings" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,20"/>
  <TextBlock Text="Limits to display" Margin="0,0,0,7"/>
  <ComboBox x:Name="LimitChoice" Height="30"><ComboBoxItem Content="Both limits"/><ComboBoxItem Content="5-hour limit only"/><ComboBoxItem Content="7-day limit only"/></ComboBox>
  <TextBlock Text="Appearance" Margin="0,16,0,7"/>
  <ComboBox x:Name="ViewChoice" Height="30"><ComboBoxItem Content="Standard — progress bars"/><ComboBoxItem Content="Compact — percentage rings"/></ComboBox>
  <TextBlock Text="Refresh interval" Margin="0,16,0,7"/>
  <ComboBox x:Name="IntervalChoice" Height="30"><ComboBoxItem Content="5 seconds"/><ComboBoxItem Content="10 seconds"/><ComboBoxItem Content="30 seconds"/><ComboBoxItem Content="60 seconds"/><ComboBoxItem Content="120 seconds"/></ComboBox>
  <TextBlock Text="Hover over a ring to see its reset time." FontSize="11" Foreground="#A6A6A6" TextWrapping="Wrap" Margin="0,16,0,14"/>
  <Button x:Name="Apply" Content="Save" Height="34" Background="#9AD7C3" Foreground="#18241F" BorderThickness="0" Cursor="Hand"/>
 </StackPanel>
</Window>'
    $dialog = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $settingsXaml))
    if (!$Preview) { $dialog.Owner = $window }
    $limitChoice = $dialog.FindName('LimitChoice'); $viewChoice = $dialog.FindName('ViewChoice'); $intervalChoice = $dialog.FindName('IntervalChoice')
    $limitChoice.SelectedIndex = [array]::IndexOf(@('both','five','week'), $script:preferences.Limits)
    $viewChoice.SelectedIndex = [array]::IndexOf(@('standard','compact'), $script:preferences.View)
    $intervalChoice.SelectedIndex = [array]::IndexOf(@(5,10,30,60,120), [int]$script:preferences.Interval)
    if ($Preview) { return $dialog }
    $dialog.FindName('Apply').Add_Click({
        $script:preferences.Limits = @('both','five','week')[$limitChoice.SelectedIndex]
        $script:preferences.View = @('standard','compact')[$viewChoice.SelectedIndex]
        $script:preferences.Interval = @(5,10,30,60,120)[$intervalChoice.SelectedIndex]
        try { $script:preferences | ConvertTo-Json | Set-Content -LiteralPath $preferencesFile -Encoding UTF8 } catch { [void][Windows.MessageBox]::Show('Could not save settings: ' + $_.Exception.Message) }
        Draw-Rows; $dialog.Close(); Start-Refresh
    })
    [void]$dialog.ShowDialog()
}
