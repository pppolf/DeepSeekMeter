using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using DeepSeekMeter.Core;

namespace DeepSeekMeter;

/// <summary>
/// 托盘图标 + 悬浮窗宿主（对齐 macOS 版 StatusItemController.swift）。
/// 托盘图标颜色随余额状态：正常绿、低于 10 橙、低于 1 红、异常红、未登录灰。
/// </summary>
public sealed class TrayIconController : IDisposable
{
    private readonly MainViewModel _model;
    private readonly System.Windows.Forms.NotifyIcon _notifyIcon;
    private readonly System.Windows.Forms.ContextMenuStrip _menu;
    private Icon? _icon;
    private IntPtr _iconHandle;
    private PopoverWindow? _popover;
    private bool _disposed;

    public TrayIconController(MainViewModel model)
    {
        _model = model;

        _menu = new System.Windows.Forms.ContextMenuStrip();
        var openItem = new System.Windows.Forms.ToolStripMenuItem("打开悬浮窗", null, (_, _) => ShowPopover());
        var refreshItem = new System.Windows.Forms.ToolStripMenuItem("立即刷新", null, async (_, _) => await _model.RefreshAsync());
        var quitItem = new System.Windows.Forms.ToolStripMenuItem("退出", null, (_, _) => System.Windows.Application.Current.Shutdown());
        _menu.Items.Add(openItem);
        _menu.Items.Add(refreshItem);
        _menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        _menu.Items.Add(quitItem);

        _notifyIcon = new System.Windows.Forms.NotifyIcon
        {
            Text = "DeepSeek Meter",
            Visible = true,
            ContextMenuStrip = _menu,
        };
        _notifyIcon.MouseClick += OnMouseClick;

        // 状态变化时刷新托盘文字/图标
        _model.PropertyChanged += (_, _) => Render();
        Render();
    }

    // MARK: - 悬浮窗

    public void ShowPopover(System.Drawing.Point? anchor = null)
    {
        if (_disposed) return;
        if (_popover is null)
        {
            _popover = new PopoverWindow(_model);
            _popover.Closed += (_, _) => _popover = null;
        }
        if (!_popover.IsVisible)
        {
            // 先 Show 完成布局（SizeToContent 此时才算得尺寸），再基于点击点定位
            _popover.Show();
            _popover.PositionNear(anchor ?? System.Windows.Forms.Cursor.Position);
        }
        _popover.Activate();
    }

    private void TogglePopover(System.Drawing.Point anchor)
    {
        if (_popover is { IsVisible: true })
            _popover.Hide();
        else
            ShowPopover(anchor);
    }

    private void OnMouseClick(object? sender, System.Windows.Forms.MouseEventArgs e)
    {
        if (e.Button == System.Windows.Forms.MouseButtons.Left)
            TogglePopover(System.Windows.Forms.Cursor.Position);
    }

    // MARK: - 渲染

    public void Render()
    {
        if (_disposed) return;
        var model = _model;
        var color = StatusColor(model);
        SetIcon(RenderIcon(color));
        _notifyIcon.Text = Tooltip(model);
    }

    private static Color StatusColor(MainViewModel model)
    {
        switch (model.Status)
        {
            case DataStatus.Fresh:
                if (model.LastBalance is { } balance)
                {
                    if (balance.Total < 1) return Color.FromArgb(229, 72, 77);   // 红
                    if (balance.Total < 10) return Color.FromArgb(240, 158, 36); // 橙
                }
                return Color.FromArgb(46, 160, 67);                              // 绿
            case DataStatus.Stale:
                return Color.FromArgb(240, 158, 36);                             // 橙：旧数据
            case DataStatus.Error:
            case DataStatus.TokenExpired:
                return Color.FromArgb(229, 72, 77);                              // 红
            default: // Loading / NotLoggedIn
                return Color.FromArgb(128, 128, 128);                            // 灰
        }
    }

    private static string Tooltip(MainViewModel model)
    {
        switch (model.Status)
        {
            case DataStatus.TokenExpired:
                return "登录已过期，点击重新登录";
            case DataStatus.Error:
                return model.LastError ?? "获取失败";
            case DataStatus.Stale:
            {
                var stale = model.LastError ?? "数据可能已过期";
                if (model.LastUpdate is { } t)
                    stale += $" · 最后成功 {t:HH:mm:ss}";
                return stale.Length > 63 ? stale[..63] : stale;
            }
        }
        if (model.LastBalance is { } balance)
        {
            var line = $"余额 {Formatting.CurrencySymbol(balance.Currency)}{Formatting.Format(balance.Total)}";
            if (model.LastUpdate is { } t)
                line += $" · 最后更新 {t:HH:mm:ss}";
            return line.Length > 63 ? line[..63] : line;
        }
        return "DeepSeek Meter · 未登录";
    }

    /// <summary>运行时绘制仪表盘图标（外环 + 指针），颜色随状态。</summary>
    private static Icon RenderIcon(Color color)
    {
        using var bmp = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);
            using var ring = new Pen(color, 3f);
            g.DrawEllipse(ring, 4.5f, 4.5f, 23, 23);
            using var pointer = new Pen(color, 3f) { StartCap = LineCap.Round, EndCap = LineCap.Round };
            g.DrawLine(pointer, 16f, 16f, 24f, 8f);
            using var dot = new SolidBrush(color);
            g.FillEllipse(dot, 13.5f, 13.5f, 5f, 5f);
        }
        return Icon.FromHandle(bmp.GetHicon());
    }

    private void SetIcon(Icon icon)
    {
        if (ReferenceEquals(_icon, icon)) return;
        if (_icon is not null)
        {
            // 释放上一次的图标句柄与对象
            if (_iconHandle != IntPtr.Zero) DestroyIcon(_iconHandle);
            _icon.Dispose();
        }
        _icon = icon;
        _iconHandle = icon.Handle;
        _notifyIcon.Icon = icon;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _popover?.Close();
        _popover = null;
        if (_icon is not null)
        {
            if (_iconHandle != IntPtr.Zero) DestroyIcon(_iconHandle);
            _icon.Dispose();
            _icon = null;
        }
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _menu.Dispose();
    }
}
