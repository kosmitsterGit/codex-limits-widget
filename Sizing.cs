using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

public sealed class WidgetSizing {
    [StructLayout(LayoutKind.Sequential)]
    private struct Rect { public int Left, Top, Right, Bottom; }
    public double Ratio { get; set; }
    private readonly Window window;
    public WidgetSizing(Window window) {
        this.window = window;
        window.SourceInitialized += (s,e) => {
            var source = HwndSource.FromHwnd(new WindowInteropHelper(window).Handle);
            source.AddHook(Hook);
        };
    }
    private IntPtr Hook(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled) {
        if (message != 0x0214 || Ratio <= 0) return IntPtr.Zero; // WM_SIZING
        var rect = (Rect)Marshal.PtrToStructure(lParam, typeof(Rect));
        int edge = wParam.ToInt32();
        int width = rect.Right - rect.Left, height = rect.Bottom - rect.Top;
        if (edge == 3 || edge == 6) { // top / bottom
            width = (int)Math.Round(height * Ratio);
            rect.Right = rect.Left + width;
        } else {
            height = (int)Math.Round(width / Ratio);
            if (edge == 4 || edge == 5) rect.Top = rect.Bottom - height;
            else rect.Bottom = rect.Top + height;
        }
        Marshal.StructureToPtr(rect, lParam, false);
        handled = true;
        return new IntPtr(1);
    }
}
