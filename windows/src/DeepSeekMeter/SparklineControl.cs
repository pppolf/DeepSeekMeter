using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using DeepSeekMeter.Core;

namespace DeepSeekMeter;

/// <summary>
/// 本月按天 Token 用量柱状图（对齐 macOS 版 SparklineView.swift）。
/// 每天一根柱子 + 日期标签，空值日显示浅色占位；悬停显示完整千分位数值。
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
            new FrameworkPropertyMetadata(Array.Empty<Entry>(),
                FrameworkPropertyMetadataOptions.AffectsRender, OnHoverAffectingPropertyChanged));

    public IReadOnlyList<Entry> Entries
    {
        get => (IReadOnlyList<Entry>)GetValue(EntriesProperty);
        set => SetValue(EntriesProperty, value);
    }

    /// <summary>当前趋势指标名（输出/缓存命中/总量），用于悬停提示。</summary>
    public static readonly DependencyProperty MetricNameProperty =
        DependencyProperty.Register(
            nameof(MetricName),
            typeof(string),
            typeof(SparklineControl),
            new PropertyMetadata("Token", OnHoverAffectingPropertyChanged));

    public string MetricName
    {
        get => (string)GetValue(MetricNameProperty);
        set => SetValue(MetricNameProperty, value);
    }

    private int _lastHoverIndex = -1;

    /// <summary>指标或数据变化时重置悬停缓存，保证 ToolTip 立即反映最新指标/数据。</summary>
    private static void OnHoverAffectingPropertyChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var control = (SparklineControl)d;
        control._lastHoverIndex = -1;
        control.ToolTip = null;
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
        // 高 DPI 下文字/柱子保持清晰：pixelsPerDip 用当前视觉 DPI，而非固定 1.0
        double pixelsPerDip = VisualTreeHelper.GetDpi(this).PixelsPerDip;

        var accent = (Color)System.Windows.Application.Current.Resources["AccentColor"];
        var emptyBrush = new SolidColorBrush(Color.FromArgb(20, 128, 128, 128));
        emptyBrush.Freeze();
        var accentBrush = new SolidColorBrush(accent);
        accentBrush.Freeze();
        var labelBrush = new SolidColorBrush(Color.FromArgb(160, 128, 128, 128));
        labelBrush.Freeze();

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

            // 日期标签（天）：居中于对应柱子正下方
            var text = new FormattedText(
                entry.Date.Day.ToString(),
                System.Globalization.CultureInfo.InvariantCulture,
                FlowDirection.LeftToRight,
                new Typeface("Segoe UI"),
                8,
                labelBrush,
                pixelsPerDip)
            {
                TextAlignment = TextAlignment.Center,
                MaxTextWidth = slot,
            };
            double textX = x + barWidth / 2 - text.Width / 2; // 柱子中心对齐
            dc.DrawText(text, new Point(textX, chartHeight));
        }
    }

    // MARK: - 悬停详情（覆盖该日完整槽位，无需精确指向窄柱）

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var entries = Entries;
        if (entries is null || entries.Count == 0 || ActualWidth <= 0)
        {
            ClearHover();
            return;
        }
        double slot = ActualWidth / entries.Count;
        int index = (int)(e.GetPosition(this).X / slot);
        if (index < 0 || index >= entries.Count)
        {
            ClearHover();
            return;
        }
        if (index == _lastHoverIndex) return; // 槽位未变，不重复更新 ToolTip

        _lastHoverIndex = index;
        var entry = entries[index];
        ToolTip = $"{entry.Date.Month}月{entry.Date.Day}日\n{MetricName}\n{Formatting.TokenFullString(entry.Value)} Token";
    }

    protected override void OnMouseLeave(MouseEventArgs e)
    {
        base.OnMouseLeave(e);
        ClearHover();
    }

    private void ClearHover()
    {
        _lastHoverIndex = -1;
        ToolTip = null;
    }
}
