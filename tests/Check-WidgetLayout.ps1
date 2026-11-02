function Export-Preview($visual, $width, $path) {
    $visual.Measure([Windows.Size]::new($width,[double]::PositiveInfinity))
    $visual.Arrange([Windows.Rect]::new(0,0,$width,$visual.DesiredSize.Height))
    $visual.UpdateLayout()
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new([int]$width,[int][math]::Ceiling($visual.ActualHeight),96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Create($path)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}
$dialog = Open-Settings -Preview
if ($dialog.FindName('IntervalChoice').Items.Count -ne 5) { throw 'Missing interval options' }
Export-Preview $dialog.Content 330 (Join-Path $testOutput 'settings-dark.png')
$choice = $dialog.FindName('LimitChoice')
$choice.ApplyTemplate() | Out-Null
$popup = $choice.Template.FindName('PART_Popup',$choice)
Export-Preview $popup.Child 286 (Join-Path $testOutput 'settings-dropdown-dark.png')
$script:preferences.View='compact'; $script:preferences.Limits='both'
foreach ($scale in @(0.65,1.0,1.6)) {
    $script:preferences.Scale = $scale; $script:baseWidth = 0
    Draw-Rows
    if ([math]::Abs($window.Width - 228*$scale) -gt 1) { throw 'Invalid scaled width' }
    if ([math]::Abs($window.Width / $window.Height - $script:sizing.Ratio) -gt 0.01) { throw 'Invalid aspect ratio' }
    Export-Preview $window.Content $window.Width (Join-Path $testOutput "scaled-$scale.png")
}
# Exercise the native aspect-ratio constraint for all eight resize edges.
$hook = [WidgetSizing].GetMethod('Hook',[Reflection.BindingFlags]'Instance,NonPublic')
$rectMemory = [Runtime.InteropServices.Marshal]::AllocHGlobal(16)
try {
    for ($edge=1; $edge -le 8; $edge++) {
        [Runtime.InteropServices.Marshal]::Copy([int[]]@(10,20,410,320),0,$rectMemory,4)
        $arguments = [object[]]@([IntPtr]::Zero,0x0214,[IntPtr]$edge,$rectMemory,$false)
        [void]$hook.Invoke($script:sizing,$arguments)
        $rect = New-Object int[] 4
        [Runtime.InteropServices.Marshal]::Copy($rectMemory,$rect,0,4)
        if ([math]::Abs(($rect[2]-$rect[0]) / ($rect[3]-$rect[1]) - $script:sizing.Ratio) -gt 0.01) { throw "Resize edge $edge broke aspect ratio" }
    }
} finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($rectMemory) }
'Dark settings, three scales and eight resize edges passed.'
