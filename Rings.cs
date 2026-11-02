using System;
using System.Windows;
using System.Windows.Media;

public sealed class QuotaRing : FrameworkElement {
    public double Remaining { get; set; }
    public Brush Accent { get; set; }
    public QuotaRing() { Width = 76; Height = 76; }
    protected override void OnRender(DrawingContext dc) {
        base.OnRender(dc);
        var center = new Point(38, 38);
        const double radius = 31;
        var track = new Pen(new SolidColorBrush(Color.FromRgb(60,60,60)), 6);
        var pen = new Pen(Accent ?? Brushes.MediumAquamarine, 6);
        pen.StartLineCap = PenLineCap.Round; pen.EndLineCap = PenLineCap.Round;
        dc.DrawEllipse(null, track, center, radius, radius);
        double remaining = Math.Max(0, Math.Min(100, Remaining));
        if (remaining >= 100) dc.DrawEllipse(null, pen, center, radius, radius);
        else if (remaining > 0) {
            // The consumed gap grows clockwise from twelve o'clock.
            double angle = (100 - remaining) * Math.PI / 50 - Math.PI / 2;
            var start = new Point(38 + radius * Math.Cos(angle), 38 + radius * Math.Sin(angle));
            var geometry = new StreamGeometry();
            using (var ctx = geometry.Open()) {
                ctx.BeginFigure(start, false, false);
                ctx.ArcTo(new Point(38,7), new Size(radius,radius), 0, remaining > 50,
                    SweepDirection.Clockwise, true, false);
            }
            dc.DrawGeometry(null, pen, geometry);
        }
    }
}
