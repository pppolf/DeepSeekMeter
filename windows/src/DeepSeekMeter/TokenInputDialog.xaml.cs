using System.Windows;

namespace DeepSeekMeter;

/// <summary>
/// 手动粘贴 Token 兜底对话框：WebView2 不可用或自动提取失败时，用户可手动粘贴。
/// 仅负责收集输入，Token 校验由调用方完成；输入默认隐藏，可临时查看。
/// </summary>
public partial class TokenInputDialog : Window
{
    private readonly Action<string> _onToken;

    public TokenInputDialog(Action<string> onToken)
    {
        InitializeComponent();
        _onToken = onToken;
        Loaded += (_, _) => TokenBox.Focus();
    }

    private void OnShowTokenChanged(object sender, RoutedEventArgs e)
    {
        if (ShowTokenBox.IsChecked == true)
        {
            TokenVisibleBox.Text = TokenBox.Password;
            TokenBox.Visibility = Visibility.Collapsed;
            TokenVisibleBox.Visibility = Visibility.Visible;
            TokenVisibleBox.Focus();
        }
        else
        {
            TokenBox.Password = TokenVisibleBox.Text;
            TokenVisibleBox.Visibility = Visibility.Collapsed;
            TokenBox.Visibility = Visibility.Visible;
            TokenBox.Focus();
        }
    }

    private void OnSaveClick(object sender, RoutedEventArgs e)
    {
        var token = (ShowTokenBox.IsChecked == true ? TokenVisibleBox.Text : TokenBox.Password).Trim();
        if (token.Length == 0)
        {
            HintText.Text = "Token 不能为空";
            return;
        }
        _onToken(token);
        Close();
    }
}
