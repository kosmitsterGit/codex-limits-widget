Add-Type -Path (Join-Path $PSScriptRoot 'Sizing.cs') -ReferencedAssemblies $refs
$script:sizing = New-Object WidgetSizing($window)
$chrome = New-Object Windows.Shell.WindowChrome
$chrome.CaptionHeight = 0
$chrome.ResizeBorderThickness = '6'
$chrome.GlassFrameThickness = '0'
$chrome.CornerRadius = '16'
$chrome.UseAeroCaptionButtons = $false
[Windows.Shell.WindowChrome]::SetWindowChrome($window, $chrome)
$script:layoutChanging = $false
$script:baseWidth = 0; $script:baseHeight = 0
$script:resizeDirty = $false; $script:lastResize = Get-Date
function Update-WidgetLayout {
    $design = $window.FindName('Design')
    $width = $design.Width
    $design.Measure([Windows.Size]::new($width,[double]::PositiveInfinity))
    $height = $design.DesiredSize.Height
    if ($height -le 0) { return }
    $script:sizing.Ratio = $width / $height
    if ([math]::Abs($width - $script:baseWidth) -lt 0.1 -and [math]::Abs($height - $script:baseHeight) -lt 0.1) { return }
    $script:baseWidth = $width; $script:baseHeight = $height
    $script:layoutChanging = $true
    try {
        $window.Width = $width * $script:preferences.Scale
        $window.Height = $height * $script:preferences.Scale
    } finally { $script:layoutChanging = $false }
}
function Save-WidgetPreferences {
    if ($UiTest) { return }
    try { $script:preferences | ConvertTo-Json | Set-Content -LiteralPath $preferencesFile -Encoding UTF8 } catch { }
}
$window.Add_SizeChanged({
    if (!$script:layoutChanging -and $script:baseWidth -gt 0 -and $window.IsLoaded) {
        $scale = $window.ActualWidth / $script:baseWidth
        $script:preferences.Scale = [math]::Max(0.4,[math]::Min(5,$scale))
        $script:lastResize = Get-Date; $script:resizeDirty = $true
    }
})
