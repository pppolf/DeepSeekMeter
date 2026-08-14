using System.Windows;
using System.Windows.Media;

namespace DeepSeekMeter;

/// <summary>
/// 本月按天 Token 用量柱状图（对齐 macOS 版 SparklineView.swift）。
/// 每天一根柱子 + 日期标签，空值日显示浅色占位。
/// </summary>
public sealed class SparklineControl : System.Windows.FrameworkElement
{
    /// <summary>每日用量条目。</summary>
    public sealed record Entry(DateTime Date, double Value);

    public static readonly DependencyProperty EntriesProperty =
        DependencyProperty.Register(
            nameof(Entries),
            typeof(IReadOnlyList<Entry>),
            typeof(SparklineControl),
            new FrameworkPropertyMetadata(Array.Empty<Entry>(), FrameworkPropertyMetadataOptions.AffectsRender));

    public IReadOnlyList<Entry> Entries
    {
        get => (IReadOnlyList<Entry>)GetValue(EntriesProperty);
        set => SetValue(EntriesProperty, value);
    }

    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        var entries = Entries;
        if (entries is null || entries.Count == 0) return;

        double width = ActualWidth;
        double height = ActualHeight;
        if (width <= 0 || height <= 0) return;

        var maxValue = Math.Max(entries.Max(e => e.Value), 1);
        const double labelHeight = 12;
        double chartHeight = height - labelHeight;
        double slot = width / entries.Count;
        double barWidth = Math.Max(2, Math.Min(8, slot - 2));

        var accent = (Color)System.Windows.Application.Current.Resources["AccentColor"];
        var emptyBrush = new SolidColorBrush(Color.FromArgb(20, 128, 128, 128));
        emptyBrush.Freeze();
        var accentBrush = new SolidColorBrush(accent);
        accentBrush.Freeze();

        for (int i = 0; i < entries.Count; i++)
        {
            var entry = entries[i];
            double x = i * slot + (slot - barWidth) / 2;
            double barHeight = Math.Max(2, entry.Value / maxValue * (chartHeight - 2));
            double y = chartHeight - barHeight;

            var rect = new Rect(x, y, barWidth, barHeight);
            dc.DrawRoundedRectangle(
                entry.Value > 0 ? accentBrush : emptyBrush,
                null,
                rect,
                radiusX: 1.5,
                radiusY: 1.5);

            // 日期标签（天）
            var text = new FormattedText(
                entry.Date.Day.ToString(),
                System.Globalization.CultureInfo.InvariantCulture,
                FlowDirection.LeftToRight,
                new Typeface("Segoe UI"),
                8,
                Brushes.Gray,
                1.0)
            {
                TextAlignment = TextAlignment.Center,
                MaxTextWidth = slot,
            };
            dc.DrawText(text, new Point(x - (slot - text.Width) / 2, chartHeight));
        }
    }
}
