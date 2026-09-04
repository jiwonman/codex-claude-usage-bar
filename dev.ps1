[CmdletBinding()]
param(
    # Leave empty to use the Windows account that starts this app.
    [string]$UserDataRoot = $env:USERPROFILE,
    [switch]$Setup
)

if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$PSCommandPath`"", '-UserDataRoot', ('"{0}"' -f $UserDataRoot))
    if ($Setup) { $arguments += '-Setup' }
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList $arguments
    exit
}

$createdNew = $false
$script:instanceMutex = [Threading.Mutex]::new($true, 'Local\AIUsageDashboard.SingleInstance', [ref]$createdNew)
$script:setupSignal = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::AutoReset, 'Local\AIUsageDashboard.ShowSetup')
if (-not $createdNew) {
    if ($Setup) { $null = $script:setupSignal.Set() }
    $script:setupSignal.Dispose()
    $script:instanceMutex.Dispose()
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies @('System.Windows.Forms', 'System.Drawing') -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class UsageAppIdentity
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern IntPtr FindWindow(string className, string windowName);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr childAfter, string className, string windowName);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SetParent(IntPtr child, IntPtr newParent);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowLong(IntPtr window, int index);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int SetWindowLong(IntPtr window, int index, int newStyle);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool GetWindowRect(IntPtr window, out RECT rectangle);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool MoveWindow(IntPtr window, int x, int y, int width, int height, bool repaint);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr", SetLastError = true)]
    private static extern IntPtr SetWindowLongPtr64(IntPtr window, int index, IntPtr newValue);

    [DllImport("user32.dll", EntryPoint = "SetWindowLong", SetLastError = true)]
    private static extern IntPtr SetWindowLongPtr32(IntPtr window, int index, IntPtr newValue);

    public static IntPtr SetWindowOwner(IntPtr window, IntPtr owner)
    {
        if (IntPtr.Size == 8) return SetWindowLongPtr64(window, -8, owner);
        return SetWindowLongPtr32(window, -8, owner);
    }

}

public sealed class UsageLayeredForm : Form
{
    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeSize { public int Width; public int Height; }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct BlendFunction
    {
        public byte BlendOp;
        public byte BlendFlags;
        public byte SourceConstantAlpha;
        public byte AlphaFormat;
    }

    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr window, IntPtr dc);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] private static extern IntPtr SelectObject(IntPtr dc, IntPtr value);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr value);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(IntPtr dc);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UpdateLayeredWindow(IntPtr window, IntPtr destinationDc,
        ref NativePoint destination, ref NativeSize size, IntPtr sourceDc,
        ref NativePoint source, int colorKey, ref BlendFunction blend, int flags);

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams parameters = base.CreateParams;
            parameters.ExStyle |= 0x00080000 | 0x00000080;
            return parameters;
        }
    }

    public void SetBitmap(Bitmap bitmap, int x, int y)
    {
        IntPtr screenDc = GetDC(IntPtr.Zero);
        IntPtr memoryDc = CreateCompatibleDC(screenDc);
        IntPtr bitmapHandle = bitmap.GetHbitmap(Color.FromArgb(0));
        IntPtr oldBitmap = SelectObject(memoryDc, bitmapHandle);
        try
        {
            NativePoint destination = new NativePoint { X = x, Y = y };
            NativePoint source = new NativePoint { X = 0, Y = 0 };
            NativeSize size = new NativeSize { Width = bitmap.Width, Height = bitmap.Height };
            BlendFunction blend = new BlendFunction
            {
                BlendOp = 0,
                BlendFlags = 0,
                SourceConstantAlpha = 255,
                AlphaFormat = 1
            };
            if (!UpdateLayeredWindow(Handle, screenDc, ref destination, ref size,
                memoryDc, ref source, 0, ref blend, 2))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
        finally
        {
            SelectObject(memoryDc, oldBitmap);
            DeleteObject(bitmapHandle);
            DeleteDC(memoryDc);
            ReleaseDC(IntPtr.Zero, screenDc);
        }
    }
}

public sealed class UsageMenuColorTable : ProfessionalColorTable
{
    public override Color ToolStripDropDownBackground { get { return Color.White; } }
    public override Color MenuBorder { get { return Color.FromArgb(203, 213, 225); } }
    public override Color SeparatorDark { get { return Color.FromArgb(226, 232, 240); } }
    public override Color SeparatorLight { get { return Color.FromArgb(226, 232, 240); } }
    public override Color ImageMarginGradientBegin { get { return Color.White; } }
    public override Color ImageMarginGradientMiddle { get { return Color.White; } }
    public override Color ImageMarginGradientEnd { get { return Color.White; } }
}

public sealed class UsageMenuRenderer : ToolStripProfessionalRenderer
{
    public UsageMenuRenderer() : base(new UsageMenuColorTable()) { }

    private static GraphicsPath RoundedPath(Rectangle bounds, int radius)
    {
        int diameter = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }

    protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using (var path = RoundedPath(new Rectangle(0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1), 12))
        using (var brush = new SolidBrush(Color.White))
            e.Graphics.FillPath(brush, path);
    }

    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using (var path = RoundedPath(new Rectangle(0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1), 12))
        using (var pen = new Pen(Color.FromArgb(203, 213, 225)))
            e.Graphics.DrawPath(pen, path);
    }

    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
    {
        if (!e.Item.Selected) return;
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        var bounds = new Rectangle(0, 1, e.Item.Width - 1, e.Item.Height - 2);
        using (var path = RoundedPath(bounds, 6))
        using (var brush = new SolidBrush(Color.FromArgb(243, 244, 246)))
            e.Graphics.FillPath(brush, path);
    }

    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    {
        if (e.Item is ToolStripMenuItem)
        {
            var bounds = new Rectangle(8, 0, e.Item.Width - 16, e.Item.Height);
            TextRenderer.DrawText(e.Graphics, e.Text, e.TextFont, bounds, e.TextColor,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter |
                TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix);
            return;
        }
        base.OnRenderItemText(e);
    }

    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
    {
        int y = e.Item.Height / 2;
        using (var pen = new Pen(Color.FromArgb(226, 232, 240)))
            e.Graphics.DrawLine(pen, 12, y, e.Item.Width - 12, y);
    }
}
'@
$script:usageCache = @{}
$script:pollSeconds = 300

function Get-JsonFile($path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { Get-Content -Raw -LiteralPath $path -ErrorAction Stop | ConvertFrom-Json } catch { $null }
}

$script:settingsDir = Join-Path $env:LOCALAPPDATA 'AIUsageDashboard'
$script:settingsFile = Join-Path $script:settingsDir 'settings.json'
$script:settings = Get-JsonFile $script:settingsFile

function Test-ProviderLogin($provider) {
    if ($provider -eq 'Codex') {
        $auth = Get-JsonFile (Join-Path $UserDataRoot '.codex\auth.json')
        return [bool]$auth.tokens.access_token
    }
    $auth = Get-JsonFile (Join-Path $UserDataRoot '.claude\.credentials.json')
    return [bool]$auth.claudeAiOauth.accessToken
}

function Get-ProviderSetupMessage($provider) {
    if ($provider -eq 'Codex') {
        return 'Setup required: run codex login with your ChatGPT account.'
    }
    return 'Setup required: open Claude Code and sign in to Claude.ai.'
}

function Save-ProviderSettings($codexEnabled, $claudeEnabled, $taskbarEnabled) {
    New-Item -ItemType Directory -Force -Path $script:settingsDir | Out-Null
    [pscustomobject]@{ showCodex = [bool]$codexEnabled; showClaude = [bool]$claudeEnabled; showTaskbar = [bool]$taskbarEnabled } | ConvertTo-Json | Set-Content -LiteralPath $script:settingsFile -Encoding UTF8
    $script:settings = Get-JsonFile $script:settingsFile
}

function Test-TaskbarWidgetEnabled {
    if (-not $script:settings) { return $true }
    if ($null -eq $script:settings.PSObject.Properties['showTaskbar']) { return $true }
    return [bool]$script:settings.showTaskbar
}

function Show-ProviderSetup {
    if ($script:setupDialogOpen) { return }
    $script:setupDialogOpen = $true
    try {
    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'Codex Claude Usage Bar - Setup'
    $form.ClientSize = [System.Drawing.Size]::new(400, 312)
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $form.StartPosition = 'CenterScreen'; $form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(247, 249, 252)
    $form.Font = [System.Drawing.Font]::new('Segoe UI', 9)

    $title = [System.Windows.Forms.Label]::new(); $title.Text = 'Choose what to track'; $title.Location = [System.Drawing.Point]::new(20, 20); $title.AutoSize = $true; $title.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 14); $title.ForeColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
    $intro = [System.Windows.Forms.Label]::new(); $intro.Text = 'Select the providers you want to see from the tray icon.'; $intro.Location = [System.Drawing.Point]::new(22, 54); $intro.Size = [System.Drawing.Size]::new(350, 38); $intro.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)

    $providerPanel = [System.Windows.Forms.Panel]::new(); $providerPanel.Location = [System.Drawing.Point]::new(20, 101); $providerPanel.Size = [System.Drawing.Size]::new(360, 92); $providerPanel.BackColor = $form.BackColor
    $providerPanel.Add_Paint({ param($sender, $e) $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias; Draw-RoundedRectangle $e.Graphics ([System.Drawing.Color]::White) ([System.Drawing.Rectangle]::new(1, 1, $sender.Width - 2, $sender.Height - 2)) 12 })

    $codexBox = [System.Windows.Forms.CheckBox]::new(); $codexBox.Text = 'Codex'; $codexBox.Location = [System.Drawing.Point]::new(16, 16); $codexBox.AutoSize = $true; $codexBox.BackColor = [System.Drawing.Color]::White
    $claudeBox = [System.Windows.Forms.CheckBox]::new(); $claudeBox.Text = 'Claude'; $claudeBox.Location = [System.Drawing.Point]::new(16, 51); $claudeBox.AutoSize = $true; $claudeBox.BackColor = [System.Drawing.Color]::White
    $codexBox.Checked = if ($script:settings) { [bool]$script:settings.showCodex } else { Test-ProviderLogin 'Codex' }
    $claudeBox.Checked = if ($script:settings) { [bool]$script:settings.showClaude } else { Test-ProviderLogin 'Claude' }
    $codexStatus = [System.Windows.Forms.Label]::new(); $codexStatus.Text = if (Test-ProviderLogin 'Codex') { 'Ready' } else { 'Not signed in - run codex login' }; $codexStatus.Location = [System.Drawing.Point]::new(118, 17); $codexStatus.Size = [System.Drawing.Size]::new(222, 20); $codexStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight; $codexStatus.BackColor = [System.Drawing.Color]::White; $codexStatus.ForeColor = if (Test-ProviderLogin 'Codex') { [System.Drawing.Color]::FromArgb(5, 150, 105) } else { [System.Drawing.Color]::FromArgb(217, 119, 6) }
    $claudeStatus = [System.Windows.Forms.Label]::new(); $claudeStatus.Text = if (Test-ProviderLogin 'Claude') { 'Ready' } else { 'Not signed in - sign in to Claude Code' }; $claudeStatus.Location = [System.Drawing.Point]::new(118, 52); $claudeStatus.Size = [System.Drawing.Size]::new(222, 20); $claudeStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight; $claudeStatus.BackColor = [System.Drawing.Color]::White; $claudeStatus.ForeColor = if (Test-ProviderLogin 'Claude') { [System.Drawing.Color]::FromArgb(5, 150, 105) } else { [System.Drawing.Color]::FromArgb(217, 119, 6) }
    foreach ($control in @($codexBox, $claudeBox, $codexStatus, $claudeStatus)) { $providerPanel.Controls.Add($control) }

    $taskbarBox = [System.Windows.Forms.CheckBox]::new(); $taskbarBox.Text = 'Show usage in taskbar'; $taskbarBox.Location = [System.Drawing.Point]::new(22, 204); $taskbarBox.AutoSize = $true; $taskbarBox.Checked = Test-TaskbarWidgetEnabled
    $hint = [System.Windows.Forms.Label]::new(); $hint.Text = 'You can change this later from the tray menu.'; $hint.Location = [System.Drawing.Point]::new(22, 231); $hint.Size = [System.Drawing.Size]::new(350, 22); $hint.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
    $save = [System.Windows.Forms.Button]::new(); $save.Text = 'Save'; $save.Location = [System.Drawing.Point]::new(214, 265); $save.Size = [System.Drawing.Size]::new(80, 34); $save.UseVisualStyleBackColor = $true
    $cancel = [System.Windows.Forms.Button]::new(); $cancel.Text = 'Cancel'; $cancel.Location = [System.Drawing.Point]::new(302, 265); $cancel.Size = [System.Drawing.Size]::new(78, 34); $cancel.UseVisualStyleBackColor = $true
    foreach ($control in @($title, $intro, $providerPanel, $taskbarBox, $hint, $save, $cancel)) { $form.Controls.Add($control) }
    $form.AcceptButton = $save; $form.CancelButton = $cancel
    $save.Add_Click({ Save-ProviderSettings $codexBox.Checked $claudeBox.Checked $taskbarBox.Checked; $form.DialogResult = [System.Windows.Forms.DialogResult]::OK; $form.Close() })
    $cancel.Add_Click({ $form.Close() })
    $null = $form.ShowDialog()
    if (-not $script:settings) { Save-ProviderSettings $codexBox.Checked $claudeBox.Checked $taskbarBox.Checked }
    } finally {
        $script:setupDialogOpen = $false
    }
}

function Get-Usage($provider) {
    $cached = $script:usageCache[$provider]
    if ($cached -and (((Get-Date) - $cached.fetchedAt).TotalSeconds -lt $script:pollSeconds)) {
        return $cached.value
    }
    if ($provider -eq 'Claude') {
        $auth = (Get-JsonFile (Join-Path $UserDataRoot '.claude\.credentials.json')).claudeAiOauth
        if (-not $auth.accessToken) { return @{ error = Get-ProviderSetupMessage 'Claude' } }
        $uri = 'https://api.anthropic.com/api/oauth/usage'
        $headers = @{ Authorization = "Bearer $($auth.accessToken)"; 'anthropic-version' = '2023-06-01'; 'User-Agent' = 'usage-dashboard-local' }
    } else {
        $auth = Get-JsonFile (Join-Path $UserDataRoot '.codex\auth.json')
        $token = $auth.tokens.access_token
        if (-not $token) { return @{ error = Get-ProviderSetupMessage 'Codex' } }
        $uri = 'https://chatgpt.com/backend-api/wham/usage'
        $headers = @{ Authorization = "Bearer $token"; 'User-Agent' = 'codex-cli' }
        if ($auth.tokens.account_id) { $headers['ChatGPT-Account-Id'] = $auth.tokens.account_id }
    }
    try {
        $raw = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 15
        if ($provider -eq 'Codex') {
            $windows = @($raw.rate_limit.primary_window, $raw.rate_limit.secondary_window) | Where-Object { $_ }
            $five = $windows | Where-Object { $null -eq $_.limit_window_seconds -or [int64]$_.limit_window_seconds -lt 86400 } | Select-Object -First 1
            $seven = $windows | Where-Object { $null -ne $_.limit_window_seconds -and [int64]$_.limit_window_seconds -ge 86400 } | Select-Object -First 1
            if (-not $five) { $five = $raw.rate_limit.primary_window }
            if (-not $seven) { $seven = $raw.rate_limit.secondary_window }
            $result = @{ five = $five; seven = $seven }
        }
        else { $result = @{ five = $raw.five_hour; seven = $raw.seven_day } }
        $script:usageCache[$provider] = @{ value = $result; fetchedAt = Get-Date }
        return $result
    } catch {
        # Keep showing the last successful value instead of repeatedly retrying after a rate limit.
        if ($cached) { return $cached.value }
        return @{ error = "request failed: $($_.Exception.Message)" }
    }
}

function Format-Usage($data) {
    if (-not $data) { return '--' }
    $used = Get-UsagePercent $data
    if ($null -ne $data.used_percent) {
        $reset = if ($data.reset_at) { [DateTimeOffset]::FromUnixTimeSeconds([int64]$data.reset_at).ToLocalTime().ToString('HH:mm') } else { '--:--' }
        return "$used% used, reset $reset"
    }
    $reset = if ($data.resets_at) { ([datetime]$data.resets_at).ToLocalTime().ToString('HH:mm') } else { '--:--' }
    return "$used% used, reset $reset"
}

function Get-UsagePercent($data) {
    if ($null -ne $data.used_percent) { return [Math]::Round([double]$data.used_percent) }
    $ratio = if ($null -ne $data.utilization) { [double]$data.utilization } else { 0 }
    if ($ratio -le 1) { return [Math]::Round($ratio * 100) }
    return [Math]::Round($ratio)
}

function Get-ResetText($data, [switch]$Weekly) {
    $format = if ($Weekly) { 'MM/dd HH:mm' } else { 'HH:mm' }
    if ($null -ne $data.used_percent) {
        if ($data.reset_at) { return "Resets " + [DateTimeOffset]::FromUnixTimeSeconds([int64]$data.reset_at).ToLocalTime().ToString($format) }
    } elseif ($data.resets_at) {
        return "Resets " + ([datetime]$data.resets_at).ToLocalTime().ToString($format)
    }
    return 'Reset time unavailable'
}

function Get-GaugeColor($percent) {
    if ($percent -ge 80) { return [System.Drawing.Color]::FromArgb(220, 38, 38) }
    if ($percent -ge 60) { return [System.Drawing.Color]::FromArgb(217, 119, 6) }
    return [System.Drawing.Color]::FromArgb(34, 197, 94)
}

function New-RoundedPath($rectangle, $radius) {
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $diameter = $radius * 2
    $path.AddArc($rectangle.X, $rectangle.Y, $diameter, $diameter, 180, 90)
    $path.AddArc($rectangle.Right - $diameter, $rectangle.Y, $diameter, $diameter, 270, 90)
    $path.AddArc($rectangle.Right - $diameter, $rectangle.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($rectangle.X, $rectangle.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function Draw-RoundedRectangle($graphics, $color, $rectangle, $radius) {
    if ($rectangle.Width -le 0 -or $rectangle.Height -le 0) { return }
    $path = New-RoundedPath $rectangle $radius
    $brush = [System.Drawing.SolidBrush]::new($color)
    $graphics.FillPath($brush, $path)
    $brush.Dispose(); $path.Dispose()
}

function New-ProviderGlyph($provider) {
    $bitmap = [System.Drawing.Bitmap]::new(32, 32)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)
    if ($provider -eq 'Claude') {
        $brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(196, 106, 70))
        $graphics.FillEllipse($brush, 1, 1, 30, 30); $brush.Dispose()
        $font = [System.Drawing.Font]::new('Segoe UI Semibold', 14)
        $textBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
        $format = [System.Drawing.StringFormat]::new(); $format.Alignment = [System.Drawing.StringAlignment]::Center; $format.LineAlignment = [System.Drawing.StringAlignment]::Center
        $graphics.DrawString('A', $font, $textBrush, [System.Drawing.RectangleF]::new(0, 0, 32, 31), $format)
        $format.Dispose(); $textBrush.Dispose(); $font.Dispose()
    } else {
        $baseBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(15, 23, 42))
        $graphics.FillEllipse($baseBrush, 1, 1, 30, 30); $baseBrush.Dispose()
        $ringPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(45, 212, 191), 3)
        $graphics.DrawArc($ringPen, 6, 6, 20, 20, -70, 285); $ringPen.Dispose()
    }
    $graphics.Dispose()
    return $bitmap
}

function Get-TaskbarWidgetWidth {
    $providerCount = [int][bool]$script:settings.showClaude + [int][bool]$script:settings.showCodex
    if ($providerCount -le 0) { return 0 }
    $providerGap = if ($providerCount -gt 1) { 8 } else { 0 }
    return 8 + ($providerCount * 120) + $providerGap
}

function Get-InstalledProviderIcon($provider) {
    try {
        if ($provider -eq 'Claude') {
            $package = Get-AppxPackage Claude -ErrorAction Stop
            $path = Join-Path $package.InstallLocation 'assets\Square44x44Logo.targetsize-24_altform-unplated.png'
        } else {
            $package = Get-AppxPackage OpenAI.Codex -ErrorAction Stop
            $path = Join-Path $package.InstallLocation 'assets\Square44x44Logo.targetsize-60_altform-lightunplated.png'
        }
        if (-not (Test-Path -LiteralPath $path)) { return $null }
        $source = [System.Drawing.Image]::FromFile($path)
        try {
            return [System.Drawing.Bitmap]::new($source)
        } finally { $source.Dispose() }
    } catch {
        return $null
    }
}

function Draw-ProviderMark($graphics, $provider, $x) {
    $image = if ($provider -eq 'Claude') { $script:claudeTaskbarIcon } else { $script:codexTaskbarIcon }
    if ($image) {
        $graphics.DrawImage($image, [System.Drawing.Rectangle]::new($x, 11, 24, 24))
        return
    }
    $isClaude = $provider -eq 'Claude'
    $color = if ($isClaude) { [System.Drawing.Color]::FromArgb(224, 137, 95) } else { [System.Drawing.Color]::FromArgb(45, 212, 191) }
    $pen = [System.Drawing.Pen]::new($color, 2.2)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    if ($isClaude) {
        $centerX = $x + 11; $centerY = 23
        foreach ($angle in @(0, 60, 120, 180, 240, 300)) {
            $radians = $angle * [Math]::PI / 180
            $innerX = $centerX + ([Math]::Cos($radians) * 3)
            $innerY = $centerY + ([Math]::Sin($radians) * 3)
            $outerX = $centerX + ([Math]::Cos($radians) * 9)
            $outerY = $centerY + ([Math]::Sin($radians) * 9)
            $graphics.DrawLine($pen, [single]$innerX, [single]$innerY, [single]$outerX, [single]$outerY)
        }
    } else {
        foreach ($angle in @(0, 60, 120, 180, 240, 300)) {
            $graphics.DrawArc($pen, $x + 2, 14, 18, 18, $angle + 8, 128)
        }
    }
    $pen.Dispose()
}

function Draw-TaskbarProvider($graphics, $provider, $result, $x) {
    $isClaude = $provider -eq 'Claude'
    $values = @($null, $null)
    if ($result -and -not $result.error) {
        $values = @(
            (Get-UsagePercent $result.five)
            (Get-UsagePercent $result.seven)
        )
    }

    $labelFont = [System.Drawing.Font]::new('Segoe UI Semibold', 7.5)
    $valueFont = [System.Drawing.Font]::new('Segoe UI', 7.5)
    $primaryColor = if ($script:taskbarUsesLightTheme) { [System.Drawing.Color]::FromArgb(31, 31, 31) } else { [System.Drawing.Color]::FromArgb(248, 250, 252) }
    $mutedColor = if ($script:taskbarUsesLightTheme) { [System.Drawing.Color]::FromArgb(92, 92, 92) } else { [System.Drawing.Color]::FromArgb(203, 213, 225) }
    $trackColor = if ($script:taskbarUsesLightTheme) { [System.Drawing.Color]::FromArgb(190, 190, 190) } else { [System.Drawing.Color]::FromArgb(71, 85, 105) }
    $primaryBrush = [System.Drawing.SolidBrush]::new($primaryColor)
    $mutedBrush = [System.Drawing.SolidBrush]::new($mutedColor)
    $trackBrush = [System.Drawing.SolidBrush]::new($trackColor)
    $valueFormat = [System.Drawing.StringFormat]::new(); $valueFormat.Alignment = [System.Drawing.StringAlignment]::Far; $valueFormat.LineAlignment = [System.Drawing.StringAlignment]::Near

    Draw-ProviderMark $graphics $provider $x
    for ($index = 0; $index -lt 2; $index++) {
        $rowY = 4 + ($index * 20)
        $label = if ($index -eq 0) { '5h' } else { '7d' }
        $value = if ($null -eq $values[$index]) { '--' } else { "$($values[$index])%" }
        $graphics.DrawString($label, $labelFont, $mutedBrush, $x + 30, $rowY)
        $graphics.DrawString($value, $valueFont, $primaryBrush, [System.Drawing.RectangleF]::new($x + 48, $rowY, 34, 17), $valueFormat)
        $track = [System.Drawing.Rectangle]::new($x + 87, $rowY + 6, 27, 6)
        Draw-RoundedRectangle $graphics $trackBrush.Color $track 3
        if ($null -ne $values[$index]) {
            $percent = [Math]::Min(100, [Math]::Max(0, [double]$values[$index]))
            $fillWidth = [Math]::Max(1, [Math]::Round($track.Width * $percent / 100))
            Draw-RoundedRectangle $graphics (Get-GaugeColor $percent) ([System.Drawing.Rectangle]::new($track.X, $track.Y, $fillWidth, $track.Height)) 3
        }
    }

    $valueFormat.Dispose(); $trackBrush.Dispose(); $mutedBrush.Dispose(); $primaryBrush.Dispose(); $valueFont.Dispose(); $labelFont.Dispose()
}

function Update-TaskbarWidgetBitmap($x, $y, $width, $height) {
    $bitmap = [System.Drawing.Bitmap]::new($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        # A nearly transparent hit surface keeps empty pixels clickable without adding a visible panel.
        $graphics.Clear([System.Drawing.Color]::FromArgb(1, 0, 0, 0))
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $providerX = 5
        if ($script:settings.showClaude) { Draw-TaskbarProvider $graphics 'Claude' $script:lastClaudeResult $providerX; $providerX += 128 }
        if ($script:settings.showCodex) { Draw-TaskbarProvider $graphics 'Codex' $script:lastCodexResult $providerX }
        $taskbarWidget.SetBitmap($bitmap, $x, $y)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Set-TaskbarWidgetPosition {
    if (-not $taskbarWidget -or $taskbarWidget.IsDisposed) { return }
    if (-not (Test-TaskbarWidgetEnabled)) {
        $taskbarWidget.Hide()
        $script:lastTaskbarBounds = $null
        return
    }
    $width = Get-TaskbarWidgetWidth
    if ($width -le 0) {
        $taskbarWidget.Hide()
        $taskbarWidget.ClientSize = [System.Drawing.Size]::Empty
        $script:lastTaskbarBounds = $null
        $script:underForegroundOverlay = $false
        $script:foregroundOverlayHandle = [IntPtr]::Zero
        return
    }

    $taskbar = [UsageAppIdentity]::FindWindow('Shell_TrayWnd', $null)
    if ($taskbar -eq [IntPtr]::Zero) { $taskbarWidget.Hide(); return }
    $trayArea = [UsageAppIdentity]::FindWindowEx($taskbar, [IntPtr]::Zero, 'TrayNotifyWnd', $null)
    $taskbarRect = [UsageAppIdentity+RECT]::new()
    if (-not [UsageAppIdentity]::GetWindowRect($taskbar, [ref]$taskbarRect)) { $taskbarWidget.Hide(); return }

    $taskbarWidth = $taskbarRect.Right - $taskbarRect.Left
    $taskbarHeight = $taskbarRect.Bottom - $taskbarRect.Top
    $height = [Math]::Min(46, [Math]::Max(38, $taskbarHeight - 2))
    $rightEdge = $taskbarWidth - 168
    if ($trayArea -ne [IntPtr]::Zero) {
        $trayRect = [UsageAppIdentity+RECT]::new()
        if ([UsageAppIdentity]::GetWindowRect($trayArea, [ref]$trayRect)) { $rightEdge = $trayRect.Left - $taskbarRect.Left }
    }
    $x = $taskbarRect.Left + [Math]::Max(4, $rightEdge - $width - 6)
    $y = $taskbarRect.Top + [Math]::Max(0, [Math]::Floor(($taskbarHeight - $height) / 2))

    $foregroundWindow = [UsageAppIdentity]::GetForegroundWindow()
    $foregroundOverlay = $false
    if ($foregroundWindow -ne [IntPtr]::Zero -and $foregroundWindow -ne $taskbarWidget.Handle) {
        $foregroundRect = [UsageAppIdentity+RECT]::new()
        $foregroundStyle = [UsageAppIdentity]::GetWindowLong($foregroundWindow, -20)
        if (($foregroundStyle -band 0x00000008) -ne 0 -and [UsageAppIdentity]::GetWindowRect($foregroundWindow, [ref]$foregroundRect)) {
            $foregroundOverlay = $foregroundRect.Left -le $taskbarRect.Left -and
                $foregroundRect.Top -le $taskbarRect.Top -and
                $foregroundRect.Right -ge $taskbarRect.Right -and
                $foregroundRect.Bottom -ge $taskbarRect.Bottom
        }
    }

    if ($script:taskbarOwner -ne $taskbar) {
        $style = [UsageAppIdentity]::GetWindowLong($taskbarWidget.Handle, -16)
        $style = ($style -band (-bnot 0x40000000) -band (-bnot 0x04000000)) -bor (-2147483648)
        $null = [UsageAppIdentity]::SetWindowLong($taskbarWidget.Handle, -16, [int]$style)
        $extendedStyle = [UsageAppIdentity]::GetWindowLong($taskbarWidget.Handle, -20)
        $extendedStyle = $extendedStyle -band (-bnot 0x00000020) -band (-bnot 0x08000000) -bor 0x00000080 -bor 0x00000008
        $null = [UsageAppIdentity]::SetWindowLong($taskbarWidget.Handle, -20, [int]$extendedStyle)
        $null = [UsageAppIdentity]::SetParent($taskbarWidget.Handle, [IntPtr]::Zero)
        $null = [UsageAppIdentity]::SetWindowOwner($taskbarWidget.Handle, $taskbar)
        $null = [UsageAppIdentity]::SetWindowPos($taskbarWidget.Handle, [IntPtr](-1), 0, 0, 0, 0, 0x0037)
        $script:taskbarOwner = $taskbar
    }
    $sizeChanged = $taskbarWidget.ClientSize.Width -ne $width -or $taskbarWidget.ClientSize.Height -ne $height
    $positionChanged = -not $script:lastTaskbarBounds -or
        $script:lastTaskbarBounds.X -ne $x -or
        $script:lastTaskbarBounds.Y -ne $y -or
        $script:lastTaskbarBounds.Width -ne $width -or
        $script:lastTaskbarBounds.Height -ne $height
    $wasVisible = $taskbarWidget.Visible
    if ($sizeChanged) { $taskbarWidget.ClientSize = [System.Drawing.Size]::new($width, $height) }
    if (-not $wasVisible) { $taskbarWidget.Show() }
    if ($script:taskbarBitmapDirty -or $sizeChanged) {
        Update-TaskbarWidgetBitmap $x $y $width $height
        $script:taskbarBitmapDirty = $false
    } elseif ($positionChanged) {
        $null = [UsageAppIdentity]::MoveWindow($taskbarWidget.Handle, $x, $y, $width, $height, $false)
    }
    if (-not $wasVisible -or $positionChanged) {
        $null = [UsageAppIdentity]::SetWindowPos($taskbarWidget.Handle, [IntPtr](-1), $x, $y, $width, $height, 0x0010)
    }
    if ($foregroundOverlay) {
        if (-not $script:underForegroundOverlay -or $script:foregroundOverlayHandle -ne $foregroundWindow -or $positionChanged) {
            # Keep the widget visible in captures, but below the full-screen capture overlay.
            $null = [UsageAppIdentity]::SetWindowPos($taskbarWidget.Handle, $foregroundWindow, 0, 0, 0, 0, 0x041B)
        }
        $script:underForegroundOverlay = $true
        $script:foregroundOverlayHandle = $foregroundWindow
    } elseif ($script:underForegroundOverlay) {
        $null = [UsageAppIdentity]::SetWindowPos($taskbarWidget.Handle, [IntPtr](-1), 0, 0, 0, 0, 0x041B)
        $script:underForegroundOverlay = $false
        $script:foregroundOverlayHandle = [IntPtr]::Zero
    }
    $script:lastTaskbarBounds = [System.Drawing.Rectangle]::new($x, $y, $width, $height)
}

function New-DashboardTrayIcon {
    $bitmap = [System.Drawing.Bitmap]::new(32, 32)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $baseBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(15, 23, 42))
    $graphics.FillEllipse($baseBrush, 1, 1, 30, 30); $baseBrush.Dispose()
    $ringPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(45, 212, 191), 3)
    $graphics.DrawArc($ringPen, 5, 5, 22, 22, -90, 265); $ringPen.Dispose()
    $barBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
    $graphics.FillRectangle($barBrush, 11, 10, 10, 3)
    $graphics.FillRectangle($barBrush, 11, 15, 7, 3)
    $graphics.FillRectangle($barBrush, 11, 20, 4, 3)
    $barBrush.Dispose(); $graphics.Dispose()
    $script:trayBitmap = $bitmap
    $script:trayIcon = [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
    return $script:trayIcon
}

function New-UsageCard($title) {
    $panel = [System.Windows.Forms.Panel]::new()
    $panel.Size = [System.Drawing.Size]::new(276, 116)
    $panel.BackColor = [System.Drawing.Color]::White
    $panel.Padding = [System.Windows.Forms.Padding]::new(12)
    $cardBackground = [System.Drawing.Color]::White
    $titleLabel = [System.Windows.Forms.Label]::new()
    $titleLabel.Text = $title; $titleLabel.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 8.5)
    $titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(31, 41, 55); $titleLabel.Location = [System.Drawing.Point]::new(12, 7); $titleLabel.AutoSize = $true; $titleLabel.BackColor = $cardBackground
    $session = [System.Windows.Forms.Label]::new(); $session.Text = '5h session'; $session.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 8); $session.Location = [System.Drawing.Point]::new(12, 29); $session.AutoSize = $true; $session.BackColor = $cardBackground; $session.ForeColor = [System.Drawing.Color]::FromArgb(55, 65, 81)
    $week = [System.Windows.Forms.Label]::new(); $week.Text = '7d weekly'; $week.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 8); $week.Location = [System.Drawing.Point]::new(12, 72); $week.AutoSize = $true; $week.BackColor = $cardBackground; $week.ForeColor = [System.Drawing.Color]::FromArgb(55, 65, 81)
    $sessionInfo = [System.Windows.Forms.Label]::new(); $sessionInfo.Location = [System.Drawing.Point]::new(12, 51); $sessionInfo.Size = [System.Drawing.Size]::new(116, 15); $sessionInfo.Font = [System.Drawing.Font]::new('Segoe UI', 7.5); $sessionInfo.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139); $sessionInfo.BackColor = $cardBackground
    $sessionReset = [System.Windows.Forms.Label]::new(); $sessionReset.Location = [System.Drawing.Point]::new(128, 51); $sessionReset.Size = [System.Drawing.Size]::new(136, 15); $sessionReset.Font = [System.Drawing.Font]::new('Segoe UI', 7.5); $sessionReset.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139); $sessionReset.BackColor = $cardBackground; $sessionReset.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $weekInfo = [System.Windows.Forms.Label]::new(); $weekInfo.Location = [System.Drawing.Point]::new(12, 94); $weekInfo.Size = [System.Drawing.Size]::new(116, 15); $weekInfo.Font = [System.Drawing.Font]::new('Segoe UI', 7.5); $weekInfo.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139); $weekInfo.BackColor = $cardBackground
    $weekReset = [System.Windows.Forms.Label]::new(); $weekReset.Location = [System.Drawing.Point]::new(128, 94); $weekReset.Size = [System.Drawing.Size]::new(136, 15); $weekReset.Font = [System.Drawing.Font]::new('Segoe UI', 7.5); $weekReset.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139); $weekReset.BackColor = $cardBackground; $weekReset.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    foreach ($control in @($titleLabel, $session, $week, $sessionInfo, $sessionReset, $weekInfo, $weekReset)) { $panel.Controls.Add($control) }
    $panel.Add_Paint({
        param($sender, $e)
        foreach ($gauge in @(@{ Y = 42; Data = $sender.Tag.five }, @{ Y = 85; Data = $sender.Tag.seven })) {
            $track = [System.Drawing.Rectangle]::new(12, $gauge.Y, $sender.Width - 24, 6)
            Draw-RoundedRectangle $e.Graphics ([System.Drawing.Color]::FromArgb(229, 233, 239)) $track 3
            if ($gauge.Data) {
                $width = [Math]::Round($track.Width * [Math]::Min(100, [Math]::Max(0, [double]$gauge.Data.Percent)) / 100)
                if ($width -gt 0) {
                    Draw-RoundedRectangle $e.Graphics $gauge.Data.Color ([System.Drawing.Rectangle]::new($track.X, $track.Y, $width, $track.Height)) 3
                }
            }
        }
    })
    return [pscustomobject]@{ Panel = $panel; SessionInfo = $sessionInfo; SessionReset = $sessionReset; WeekInfo = $weekInfo; WeekReset = $weekReset }
}

function Set-UsageCard($card, $result) {
    if ($result.error) {
        $card.SessionInfo.Text = 'Unavailable'; $card.SessionReset.Text = $result.error
        $card.WeekInfo.Text = 'Unavailable'; $card.WeekReset.Text = $result.error
        $card.Panel.Tag = [pscustomobject]@{ five = $null; seven = $null }; $card.Panel.Invalidate(); return
    }
    $fivePercent = Get-UsagePercent $result.five; $sevenPercent = Get-UsagePercent $result.seven
    $card.SessionInfo.Text = "$(100 - $fivePercent)% remaining"; $card.SessionReset.Text = Get-ResetText $result.five
    $card.WeekInfo.Text = "$(100 - $sevenPercent)% remaining"; $card.WeekReset.Text = Get-ResetText $result.seven -Weekly
    $card.Panel.Tag = [pscustomobject]@{
        five = [pscustomobject]@{ Percent = $fivePercent; Color = Get-GaugeColor $fivePercent }
        seven = [pscustomobject]@{ Percent = $sevenPercent; Color = Get-GaugeColor $sevenPercent }
    }
    $card.Panel.Invalidate()
}

[System.Windows.Forms.Application]::EnableVisualStyles()
if (-not $script:settings -or $Setup) { Show-ProviderSetup }
$menu = [System.Windows.Forms.ContextMenuStrip]::new()
$menu.BackColor = [System.Drawing.Color]::White
$menu.Padding = [System.Windows.Forms.Padding]::new(6)
$menu.MinimumSize = [System.Drawing.Size]::new(288, 0)
$menu.ShowImageMargin = $false
$menu.ShowCheckMargin = $false
$menu.DropShadowEnabled = $true
$menu.Renderer = [UsageMenuRenderer]::new()
$codexCard = New-UsageCard 'Codex'
$claudeCard = New-UsageCard 'Claude'
$codexHost = [System.Windows.Forms.ToolStripControlHost]::new($codexCard.Panel)
$claudeHost = [System.Windows.Forms.ToolStripControlHost]::new($claudeCard.Panel)
$codexHost.Margin = [System.Windows.Forms.Padding]::new(0)
$claudeHost.Margin = [System.Windows.Forms.Padding]::new(0)
$providerSeparator = [System.Windows.Forms.ToolStripSeparator]::new()
$providerSeparator.Margin = [System.Windows.Forms.Padding]::new(0, 2, 0, 2)
$actionsSeparator = [System.Windows.Forms.ToolStripSeparator]::new()
$actionsSeparator.Margin = [System.Windows.Forms.Padding]::new(0, 3, 0, 3)
$null = $menu.Items.Add($codexHost)
$null = $menu.Items.Add($providerSeparator)
$null = $menu.Items.Add($claudeHost)
$null = $menu.Items.Add($actionsSeparator)
$configure = [System.Windows.Forms.ToolStripMenuItem]::new('Configure providers...')
$exit = [System.Windows.Forms.ToolStripMenuItem]::new('Exit')
$configure.Padding = [System.Windows.Forms.Padding]::new(6, 4, 6, 4)
$exit.Padding = [System.Windows.Forms.Padding]::new(6, 4, 6, 4)
$configure.Margin = [System.Windows.Forms.Padding]::new(6, 1, 6, 1)
$exit.Margin = [System.Windows.Forms.Padding]::new(6, 1, 6, 1)
$configure.Font = [System.Drawing.Font]::new('Segoe UI', 9)
$exit.Font = [System.Drawing.Font]::new('Segoe UI', 9)
$configure.ForeColor = [System.Drawing.Color]::FromArgb(31, 41, 55)
$exit.ForeColor = [System.Drawing.Color]::FromArgb(31, 41, 55)
$null = $menu.Items.Add($configure)
$null = $menu.Items.Add($exit)

function Update-MenuRegion {
    if ($menu.Width -le 0 -or $menu.Height -le 0) { return }
    $path = New-RoundedPath ([System.Drawing.Rectangle]::new(0, 0, $menu.Width, $menu.Height)) 12
    $oldRegion = $menu.Region
    $menu.Region = [System.Drawing.Region]::new($path)
    $path.Dispose()
    if ($oldRegion) { $oldRegion.Dispose() }
}

$menu.Add_Opening({ $menu.PerformLayout(); Update-MenuRegion })
$menu.Add_SizeChanged({ Update-MenuRegion })

$tray = [System.Windows.Forms.NotifyIcon]::new()
$tray.Icon = New-DashboardTrayIcon
$tray.Text = 'Codex Claude Usage Bar'
$tray.ContextMenuStrip = $menu
$tray.Visible = $true

$themeSettings = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue
$script:taskbarUsesLightTheme = $themeSettings.SystemUsesLightTheme -eq 1
$script:claudeTaskbarIcon = Get-InstalledProviderIcon 'Claude'
$script:codexTaskbarIcon = Get-InstalledProviderIcon 'Codex'
$script:taskbarOwner = [IntPtr]::Zero
$script:lastTaskbarBounds = $null
$script:underForegroundOverlay = $false
$script:foregroundOverlayHandle = [IntPtr]::Zero
$script:taskbarBitmapDirty = $true
$taskbarWidget = [UsageLayeredForm]::new()
$taskbarWidget.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$taskbarWidget.ShowInTaskbar = $false
$taskbarWidget.TopMost = $true
$taskbarWidget.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$taskbarWidget.ContextMenuStrip = $menu
$taskbarWidget.ClientSize = [System.Drawing.Size]::new((Get-TaskbarWidgetWidth), 42)
$tray.Add_DoubleClick({ if ($taskbarWidget.Visible) { $taskbarWidget.Hide() } else { Set-TaskbarWidgetPosition } })

function Update-UsageMenu {
    $script:lastCodexResult = $null
    $script:lastClaudeResult = $null
    if ($script:settings.showCodex) { $script:lastCodexResult = Get-Usage 'Codex'; Set-UsageCard $codexCard $script:lastCodexResult }
    if ($script:settings.showClaude) { $script:lastClaudeResult = Get-Usage 'Claude'; Set-UsageCard $claudeCard $script:lastClaudeResult }
    $script:taskbarBitmapDirty = $true
    Set-TaskbarWidgetPosition
}

function Apply-ProviderSelection {
    $showCodex = [bool]$script:settings.showCodex
    $showClaude = [bool]$script:settings.showClaude
    $hasProvider = $showCodex -or $showClaude
    $menu.Items.Clear()
    if ($showCodex) { $null = $menu.Items.Add($codexHost) }
    if ($showCodex -and $showClaude) { $null = $menu.Items.Add($providerSeparator) }
    if ($showClaude) { $null = $menu.Items.Add($claudeHost) }
    if ($hasProvider) { $null = $menu.Items.Add($actionsSeparator) }
    $null = $menu.Items.Add($configure)
    $null = $menu.Items.Add($exit)

    $menu.AutoSize = $true
    if ($hasProvider) {
        $configure.AutoSize = $false
        $exit.AutoSize = $false
        $configure.Size = [System.Drawing.Size]::new(264, 28)
        $exit.Size = [System.Drawing.Size]::new(264, 28)
        $menu.MinimumSize = [System.Drawing.Size]::new(288, 0)
    } else {
        $configure.AutoSize = $true
        $exit.AutoSize = $true
        $menu.MinimumSize = [System.Drawing.Size]::Empty
    }
    $menu.PerformLayout()
    if ($menu.Region) {
        $oldRegion = $menu.Region
        $menu.Region = $null
        $oldRegion.Dispose()
    }
    if ($menu.Visible) { Update-MenuRegion }
    $script:taskbarBitmapDirty = $true
    Set-TaskbarWidgetPosition
}

$taskbarWidget.Add_MouseClick({
    param($sender, $eventArgs)
    if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        Show-ProviderSetup
        Apply-ProviderSelection
        Update-UsageMenu
    }
})
$configure.Add_Click({ Show-ProviderSetup; Apply-ProviderSelection; Update-UsageMenu })
$exit.Add_Click({
    $timer.Stop()
    $positionTimer.Stop()
    $taskbarWidget.Close()
    $tray.Visible = $false
    $tray.Dispose()
    if ($script:claudeTaskbarIcon) { $script:claudeTaskbarIcon.Dispose() }
    if ($script:codexTaskbarIcon) { $script:codexTaskbarIcon.Dispose() }
    $script:trayIcon.Dispose()
    $script:trayBitmap.Dispose()
    [System.Windows.Forms.Application]::ExitThread()
})
$timer = [System.Windows.Forms.Timer]::new()
$timer.Interval = $script:pollSeconds * 1000
$timer.Add_Tick({ Update-UsageMenu })
$timer.Start()
$positionTimer = [System.Windows.Forms.Timer]::new()
$positionTimer.Interval = 500
$positionTimer.Add_Tick({
    if ($script:setupSignal.WaitOne(0)) {
        Show-ProviderSetup
        Apply-ProviderSelection
        Update-UsageMenu
    }
    Set-TaskbarWidgetPosition
})
$positionTimer.Start()
Apply-ProviderSelection
Update-UsageMenu
Set-TaskbarWidgetPosition
try {
    [System.Windows.Forms.Application]::Run()
} finally {
    $script:setupSignal.Dispose()
    try { $script:instanceMutex.ReleaseMutex() } catch {}
    $script:instanceMutex.Dispose()
}
