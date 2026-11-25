// Wowhead Forever Link — companion app for Windows.
//
// Watches the clipboard and, when a Wowhead link is copied from World of
// Warcraft, opens it in Chrome or in a floating window on top of the game.
// It never touches the game process: it is a normal Windows window.
// Clipboard text is only checked to see whether it is a wowhead.com link;
// anything else is ignored and never stored.
// Besides the Wowhead pages it opens, its only network access is asking
// GitHub for the latest release number (can be turned off in the tray menu).

using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using Microsoft.Win32;

namespace WowheadForeverLink.Companion;

static class Program
{
    const string MUTEX_NAME = "WowheadForeverLink.Companion.SingleInstance"; // same name in every version
    static Mutex? mutex;

    [STAThread]
    static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        if (!AcquireSingleInstance())
        {
            MessageBox.Show(Strings.AlreadyRunning, AppInfo.Name);
            return;
        }
        Updater.CleanUpLeftovers();
        var overlay = new OverlayForm(justUpdated: args.Contains("--updated"), updateNow: args.Contains("--update-now"));
        Application.Run(new ApplicationContext());
        GC.KeepAlive(overlay);
        ReleaseSingleInstance();
    }

    // Only one copy runs at a time. If an older version is already running (for
    // example the .exe downloaded before this one), it is closed and this one
    // takes its place, so nobody has to find and close the old one.
    static bool AcquireSingleInstance()
    {
        mutex = new Mutex(false, MUTEX_NAME);
        // A few seconds of patience: right after an update the previous copy is still closing.
        if (TryWait(3000)) return true;

        var mine = AppInfo.FileVersion(Application.ExecutablePath);
        var older = OtherCopies().Where(p => AppInfo.FileVersion(p.path) is Version v && mine != null && v < mine).ToList();
        if (older.Count == 0) return false; // the same or a newer version is running: leave it

        foreach (var (process, _) in older)
        {
            try { process.Kill(); process.WaitForExit(5000); } catch { }
        }
        return TryWait(5000);
    }

    static bool TryWait(int ms)
    {
        try { return mutex!.WaitOne(ms); }
        catch (AbandonedMutexException) { return true; } // the owner was closed: the mutex is now ours
    }

    public static void ReleaseSingleInstance()
    {
        try { mutex?.ReleaseMutex(); } catch { }
        mutex?.Dispose();
        mutex = null;
    }

    // Other running copies of this app, whatever their file name ("WowheadForeverLink-Companion (1).exe"...).
    static IEnumerable<(Process process, string path)> OtherCopies()
    {
        int self = Environment.ProcessId;
        foreach (var p in Process.GetProcesses())
        {
            string? path = null;
            try
            {
                if (p.Id != self && p.ProcessName.StartsWith("Wowhead", StringComparison.OrdinalIgnoreCase))
                    path = p.MainModule?.FileName;
            }
            catch { }
            if (path != null && FileVersionInfo.GetVersionInfo(path).ProductName == AppInfo.Name) yield return (p, path);
            else p.Dispose();
        }
    }
}

static class AppInfo
{
    public const string Name = "Wowhead Forever Link";
    public static readonly string Version =
        typeof(AppInfo).Assembly.GetName().Version?.ToString(3) ?? "?";
    public static readonly string DataFolder = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WowheadForeverLink");
    public const string ReleasesUrl = "https://github.com/AlexDXC2026/WowheadForeverLink/releases/latest";
    public const string LatestReleaseApi = "https://api.github.com/repos/AlexDXC2026/WowheadForeverLink/releases/latest";
    public const string DownloadBase = "https://github.com/AlexDXC2026/WowheadForeverLink/releases/download/";
    public const string ReleaseExeName = "WowheadForeverLink-Companion.exe";

    /// <summary>Version of an .exe of this app (1.3.2), or null if it cannot be read.</summary>
    public static Version? FileVersion(string path)
    {
        try
        {
            var info = FileVersionInfo.GetVersionInfo(path);
            return info.ProductName == Name ? new Version(info.FileMajorPart, info.FileMinorPart, info.FileBuildPart) : null;
        }
        catch { return null; }
    }
}

/// <summary>
/// Replaces the running .exe with the one published on GitHub, in the same
/// folder and with the same file name, then restarts it. Windows lets a running
/// .exe be renamed, so the old file is renamed to .old and deleted on next start.
/// </summary>
static class Updater
{
    static string ExePath => Application.ExecutablePath;
    static string NewPath => ExePath + ".new";
    static string OldPath => ExePath + ".old";

    public static void CleanUpLeftovers()
    {
        foreach (var p in new[] { NewPath, OldPath })
            try { if (File.Exists(p)) File.Delete(p); } catch { }
    }

    /// <summary>Downloads and checks the new .exe. Throws on any problem; the running .exe is untouched until the end.</summary>
    public static async Task DownloadAndReplace(HttpClient http, string tag)
    {
        if (!Regex.IsMatch(tag, @"^v\d+\.\d+\.\d+$")) throw new InvalidDataException("tag " + tag);
        string baseUrl = AppInfo.DownloadBase + tag + "/";

        using var shortWait = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        string sums = await http.GetStringAsync(baseUrl + "SHA256SUMS.txt", shortWait.Token);
        // sha256sum format: "<hash> *<file name>"
        var expected = sums.Split('\n')
            .Select(l => Regex.Match(l.Trim(), @"^([0-9a-fA-F]{64})\s+\*?(.+)$"))
            .FirstOrDefault(m => m.Success && m.Groups[2].Value == AppInfo.ReleaseExeName)
            ?.Groups[1].Value ?? throw new InvalidDataException("no checksum for " + AppInfo.ReleaseExeName);

        using var longWait = new CancellationTokenSource(TimeSpan.FromMinutes(10));
        using (var response = await http.GetAsync(baseUrl + AppInfo.ReleaseExeName, HttpCompletionOption.ResponseHeadersRead, longWait.Token))
        {
            response.EnsureSuccessStatusCode();
            await using var file = File.Create(NewPath);
            await response.Content.CopyToAsync(file, longWait.Token);
        }

        string actual;
        await using (var file = File.OpenRead(NewPath))
            actual = Convert.ToHexString(await System.Security.Cryptography.SHA256.HashDataAsync(file));
        if (!actual.Equals(expected, StringComparison.OrdinalIgnoreCase))
        {
            File.Delete(NewPath);
            throw new InvalidDataException("checksum mismatch");
        }

        if (File.Exists(OldPath)) File.Delete(OldPath);
        File.Move(ExePath, OldPath);
        try { File.Move(NewPath, ExePath); }
        catch { File.Move(OldPath, ExePath); throw; } // put the running one back
    }

    public static void Restart()
    {
        Program.ReleaseSingleInstance(); // free it before the new copy starts
        var psi = new ProcessStartInfo(ExePath) { UseShellExecute = false };
        psi.ArgumentList.Add("--updated");
        Process.Start(psi);
    }
}

/// <summary>UI strings: Spanish when Windows is in Spanish, English otherwise.</summary>
static class Strings
{
    static readonly bool Es = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "es";
    static string T(string en, string es) => Es ? es : en;

    public static string AlreadyRunning => T("Wowhead Forever Link is already running: look for its icon next to the clock.",
                                              "Wowhead Forever Link ya está abierto: busca su icono junto al reloj.");
    public static string OpenLinksIn => T("Open Wowhead links in:", "Abrir enlaces de Wowhead en:");
    public static string Floating => T("Floating window", "Ventana flotante");
    public static string Paused => T("Nothing (paused)", "Nada (pausado)");
    public static string ToggleWindow => T("Show or hide window", "Mostrar u ocultar ventana");
    public static string AlwaysOnTop => T("Always on top of the game", "Siempre encima del juego");
    public static string Opacity => T("Opacity", "Opacidad");
    public static string OnlyFromWow => T("Only links copied from WoW", "Solo enlaces copiados desde WoW");
    public static string StartWithWindows => T("Start with Windows", "Iniciar con Windows");
    public static string DiagnosticLog => T("Diagnostic log", "Registro de diagnóstico");
    public static string OpenLogFolder => T("Open log folder", "Abrir carpeta del registro");
    public static string Exit => T("Exit", "Salir");
    public static string Back => T("Back", "Atrás");
    public static string Forward => T("Forward", "Adelante");
    public static string Reload => T("Reload", "Recargar");
    public static string OpenInChrome => T("Open this page in Chrome", "Abrir esta página en Chrome");
    public static string Hide => T("Hide", "Ocultar");
    public static string Minimize => T("Minimize", "Minimizar");
    public static string Maximize => T("Maximize", "Maximizar");
    public static string Restore => T("Restore down", "Restaurar");
    public static string Mode => T("Mode", "Modo");
    public static string ModeFloating => T("floating window", "ventana flotante");
    public static string ModePaused => T("paused", "pausado");
    public static string Listening => T("Listening for Wowhead links. Mode: {0}. Right-click this icon to change it.",
                                        "Escuchando enlaces de Wowhead. Modo: {0}. Clic derecho en este icono para cambiarlo.");
    public static string ChromeFailed => T("Could not open Chrome: {0}", "No se pudo abrir Chrome: {0}");
    public static string NeedsWebView2 => T("The floating window needs Microsoft Edge WebView2. Opening in your browser instead. ({0})",
                                            "La ventana flotante necesita Microsoft Edge WebView2. Se abre en el navegador. ({0})");
    public static string HotkeyBusy => T("Could not use the shortcut {0} (another program uses it). Change it in config.json.",
                                         "No se pudo usar el atajo {0} (otro programa lo usa). Cámbialo en config.json.");
    public static string CheckUpdates => T("Notify me of new versions", "Avisarme de versiones nuevas");
    public static string UpdateAvailable => T("Version {0} is available (you have {1}). Click here to update.",
                                              "Hay una versión nueva: {0} (tienes la {1}). Haz clic aquí para actualizar.");
    public static string UpdateTo => T("Update to version {0}", "Actualizar a la versión {0}");
    public static string Updating => T("Updating to version {0}…", "Actualizando a la versión {0}…");
    public static string UpdateFailed => T("Could not update ({0}). Opening the download page.",
                                           "No se pudo actualizar ({0}). Se abre la página de descarga.");
    public static string Updated => T("Updated to version {0}.", "Actualizado a la versión {0}.");
    public static string WowheadHome => "https://www.wowhead.com/forever/" + (Es ? "es/" : "");
}

sealed class Config
{
    public string Mode { get; set; } = "floating"; // floating | chrome | paused
    public bool AlwaysOnTop { get; set; } = true;
    public bool OnlyFromWow { get; set; } = true;
    public bool DiagnosticLog { get; set; } = false;
    public bool CheckUpdates { get; set; } = true;
    public double Opacity { get; set; } = 1.0;
    public string Hotkey { get; set; } = "Ctrl+Shift+W";
    public int X { get; set; } = -1;
    public int Y { get; set; } = -1;
    public int Width { get; set; } = 900;
    public int Height { get; set; } = 720;
    public bool Maximized { get; set; } = false;

    static readonly string FilePath = Path.Combine(AppInfo.DataFolder, "config.json");

    public static Config Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<Config>(File.ReadAllText(FilePath)) ?? new Config();
        }
        catch { }
        return new Config();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(AppInfo.DataFolder);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }
}

sealed class OverlayForm : Form
{
    const int WM_CLIPBOARDUPDATE = 0x031D;
    const int WM_HOTKEY = 0x0312;
    const int HOTKEY_ID = 1;
    const string RUN_KEY = @"Software\Microsoft\Windows\CurrentVersion\Run";
    const string RUN_VALUE = "WowheadForeverLink";

    static readonly Regex WowheadUrl = new(@"^https://(www\.)?wowhead\.com/\S+$", RegexOptions.IgnoreCase);
    static readonly string LogPath = Path.Combine(AppInfo.DataFolder, "diagnostic.log");

    [DllImport("user32.dll", SetLastError = true)] static extern bool AddClipboardFormatListener(IntPtr hwnd);
    [DllImport("user32.dll", SetLastError = true)] static extern bool RemoveClipboardFormatListener(IntPtr hwnd);
    [DllImport("user32.dll", SetLastError = true)] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
    [DllImport("user32.dll", SetLastError = true)] static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int cmd);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hWnd, int index);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool attach);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);
    const int SW_SHOWNOACTIVATE = 4, SW_MINIMIZE = 6, GWL_EXSTYLE = -20, WS_EX_TOPMOST = 0x8;
    static readonly IntPtr HWND_TOPMOST = new(-1);
    static readonly IntPtr HWND_NOTOPMOST = new(-2);
    const uint SWP_NOSIZE = 0x1, SWP_NOMOVE = 0x2, SWP_NOACTIVATE = 0x10, SWP_SHOWWINDOW = 0x40;

    readonly Config cfg = Config.Load();
    readonly WebView2 web = new() { Dock = DockStyle.Fill, DefaultBackgroundColor = Color.FromArgb(24, 24, 24) };
    readonly Label pageTitle = new();
    readonly ToolTip maximizeTip = new();
    Button? maximizeButton;
    bool maximized;
    Rectangle normalBounds;
    readonly NotifyIcon tray = new();
    readonly ContextMenuStrip menu = new();
    ToolStripMenuItem? itemFloating, itemChrome, itemPaused, itemOnTop, itemOnlyWow, itemStartup, itemLog, itemCheckUpdates;
    readonly ToolStripMenuItem itemUpdate = new() { Visible = false, Font = new Font(SystemFonts.MenuFont ?? Control.DefaultFont, FontStyle.Bold) };
    readonly System.Windows.Forms.Timer updateTimer = new();
    string? newerVersion, newerTag;
    bool updateBalloonShown;
    bool balloonIsUpdate;
    bool updating;
    bool updateNowRequested; // --update-now: update without asking (used to test the updater)
    readonly bool justUpdated;

    Task? webInit;
    bool webReady;
    bool navigated;
    string? pendingUrl;
    string lastText = "";
    DateTime lastTime = DateTime.MinValue;
    bool exiting;

    public OverlayForm(bool justUpdated, bool updateNow = false)
    {
        this.justUpdated = justUpdated;
        updateNowRequested = updateNow;
        Text = "Wowhead";
        // Borderless, with our own title bar (navigation + minimize, maximize and
        // close in one row). WS_EX_TOOLWINDOW (CreateParams) keeps it out of the
        // taskbar. ShowInTaskbar = false must not be used: WinForms then gives the
        // form a hidden owner window and Windows refuses to make it topmost.
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        BackColor = Color.FromArgb(62, 62, 62); // visible as the resize frame
        Padding = new Padding(RESIZE_FRAME);
        MinimumSize = new Size(420, 300);
        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
        PlaceInitially();
        Opacity = Math.Clamp(cfg.Opacity, 0.3, 1.0);
        // Created topmost from the start. Later SetWindowPos(HWND_TOPMOST) calls
        // are refused by Windows' foreground lock once the app has been running
        // for a while (ForegroundLockTimeout) and the game has the focus.
        TopMost = cfg.AlwaysOnTop;

        Controls.Add(web);
        Controls.Add(CreateToolbar());
        web.BringToFront();
        RestoreMaximizedState();

        CreateTray();
        _ = Handle; // creates the (hidden) window that receives clipboard and hotkey messages

        ResizeEnd += (_, _) => SaveBounds();
        VisibleChanged += (_, _) =>
        {
            if (!cfg.DiagnosticLog) return;
            var caller = new StackTrace().GetFrames()
                .Select(f => f.GetMethod())
                .Where(m => m?.DeclaringType?.Namespace?.StartsWith("WowheadForeverLink") == true)
                .Select(m => m!.DeclaringType!.Name + "." + m.Name)
                .Skip(1).Take(4);
            Log($"visible = {Visible} (from {string.Join(" < ", caller)})");
        };
        FormClosing += (_, e) =>
        {
            if (!exiting && e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                HideOverlay();
            }
        };
    }

    // The window appears without taking focus from the game: the mouse wheel
    // still scrolls it, and a click is only needed to interact with the page.
    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= WS_EX_TOOLWINDOW; // no taskbar button, not in Alt+Tab
            return cp;
        }
    }

    // Resize from the thin frame around the window (it has no native border).
    const int RESIZE_FRAME = 4;
    const int WS_EX_TOOLWINDOW = 0x80, WM_NCHITTEST = 0x84, WM_NCLBUTTONDOWN = 0xA1;
    const int HTCLIENT = 1, HTCAPTION = 2, HTLEFT = 10, HTRIGHT = 11, HTTOP = 12, HTTOPLEFT = 13,
        HTTOPRIGHT = 14, HTBOTTOM = 15, HTBOTTOMLEFT = 16, HTBOTTOMRIGHT = 17;
    [DllImport("user32.dll")] static extern bool ReleaseCapture();
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

    int ResizeHitTest(Point screen)
    {
        var p = PointToClient(screen);
        int grip = RESIZE_FRAME + 2;
        bool left = p.X < grip, right = p.X >= ClientSize.Width - grip;
        bool top = p.Y < grip, bottom = p.Y >= ClientSize.Height - grip;
        if (top && left) return HTTOPLEFT;
        if (top && right) return HTTOPRIGHT;
        if (bottom && left) return HTBOTTOMLEFT;
        if (bottom && right) return HTBOTTOMRIGHT;
        if (left) return HTLEFT;
        if (right) return HTRIGHT;
        if (top) return HTTOP;
        if (bottom) return HTBOTTOM;
        return HTCLIENT;
    }

    // Dragging the title bar moves the window; double-click maximizes or restores.
    void TitleMouseDown(object? sender, MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Left) return;
        if (e.Clicks == 2) { ToggleMaximize(); return; }
        if (maximized) return;
        ReleaseCapture();
        SendMessage(Handle, WM_NCLBUTTONDOWN, new IntPtr(HTCAPTION), IntPtr.Zero);
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        bool listening = AddClipboardFormatListener(Handle);
        Log($"start v{AppInfo.Version} · clipboard listener = {listening} · mode = {cfg.Mode} · only WoW = {cfg.OnlyFromWow}");
        RegisterConfiguredHotkey();
        RepointStartup();
        StartUpdateChecks();
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_CLIPBOARDUPDATE) OnClipboardChanged();
        else if (m.Msg == WM_HOTKEY && m.WParam.ToInt32() == HOTKEY_ID) ToggleOverlay();
        else if (m.Msg == WM_NCHITTEST && !maximized)
        {
            base.WndProc(ref m);
            if (m.Result.ToInt32() == HTCLIENT)
            {
                long lp = m.LParam.ToInt64();
                var cursor = new Point((short)(lp & 0xFFFF), (short)((lp >> 16) & 0xFFFF));
                m.Result = new IntPtr(ResizeHitTest(cursor));
            }
            return;
        }
        base.WndProc(ref m);
    }

    // ------------------------------------------------------------------ log
    // Off by default. Never writes clipboard text other than Wowhead links.
    void Log(string text)
    {
        if (!cfg.DiagnosticLog) return;
        try
        {
            Directory.CreateDirectory(AppInfo.DataFolder);
            var info = new FileInfo(LogPath);
            if (info.Exists && info.Length > 200_000) info.Delete();
            File.AppendAllText(LogPath, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + " " + text + Environment.NewLine);
        }
        catch { }
    }

    // -------------------------------------------------------------------- UI
    Control CreateToolbar()
    {
        var bar = new Panel { Dock = DockStyle.Top, Height = TITLE_BAR_HEIGHT, BackColor = Color.FromArgb(36, 36, 36) };
        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Left, AutoSize = true, WrapContents = false,
            Padding = new Padding(2, 2, 0, 0), BackColor = bar.BackColor,
        };
        buttons.Controls.Add(ToolbarButton("◀", Strings.Back, () => { if (webReady && web.CoreWebView2.CanGoBack) web.CoreWebView2.GoBack(); }));
        buttons.Controls.Add(ToolbarButton("▶", Strings.Forward, () => { if (webReady && web.CoreWebView2.CanGoForward) web.CoreWebView2.GoForward(); }));
        buttons.Controls.Add(ToolbarButton("⟳", Strings.Reload, () => { if (webReady) web.CoreWebView2.Reload(); }));
        buttons.Controls.Add(ToolbarButton("Chrome", Strings.OpenInChrome, () => OpenInChrome(CurrentUrl() ?? Strings.WowheadHome), 64));
        buttons.Controls.Add(ToolbarButton(Strings.Hide, Strings.Hide + " (" + cfg.Hotkey + ")", HideOverlay, 72));

        pageTitle.Dock = DockStyle.Fill;
        pageTitle.ForeColor = Color.Gainsboro;
        pageTitle.TextAlign = ContentAlignment.MiddleLeft;
        pageTitle.AutoEllipsis = true;
        pageTitle.Padding = new Padding(8, 0, 4, 0);
        pageTitle.Text = "Wowhead";
        pageTitle.MouseDown += TitleMouseDown;
        bar.MouseDown += TitleMouseDown;

        // Caption buttons on the right, like any Windows title bar: minimize,
        // maximize/restore and close (close hides, like the Hide button).
        var windowButtons = new FlowLayoutPanel
        {
            Dock = DockStyle.Right, AutoSize = true, WrapContents = false,
            Padding = Padding.Empty, Margin = Padding.Empty, BackColor = bar.BackColor,
        };
        var minimize = CaptionButton(Glyph(GLYPH_MINIMIZE, "—"), Strings.Minimize, MinimizeOverlay, false);
        maximizeButton = CaptionButton(Glyph(GLYPH_MAXIMIZE, "□"), "", ToggleMaximize, false); // tooltip set below
        var close = CaptionButton(Glyph(GLYPH_CLOSE, "✕"), Strings.Hide + " (" + cfg.Hotkey + ")", HideOverlay, true);
        UpdateMaximizeButton();
        windowButtons.Controls.Add(minimize);
        windowButtons.Controls.Add(maximizeButton);
        windowButtons.Controls.Add(close);

        bar.Controls.Add(pageTitle);
        bar.Controls.Add(buttons);
        bar.Controls.Add(windowButtons);
        pageTitle.BringToFront();
        return bar;
    }

    // Windows' own caption glyphs (Segoe MDL2 Assets, Windows 10+), with plain-text fallbacks.
    const string GLYPH_MINIMIZE = "", GLYPH_MAXIMIZE = "", GLYPH_RESTORE = "", GLYPH_CLOSE = "";
    static readonly Font? captionFont = FontFamily.Families.Any(f => f.Name == "Segoe MDL2 Assets")
        ? new Font("Segoe MDL2 Assets", 8f) : null;
    static string Glyph(string glyph, string fallback) => captionFont != null ? glyph : fallback;

    void UpdateMaximizeButton()
    {
        if (maximizeButton == null) return;
        maximizeButton.Text = maximized ? Glyph(GLYPH_RESTORE, "❐") : Glyph(GLYPH_MAXIMIZE, "□");
        maximizeTip.SetToolTip(maximizeButton, maximized ? Strings.Restore : Strings.Maximize);
    }

    void MinimizeOverlay()
    {
        Log("minimize requested");
        SaveBounds();
        ShowWindow(Handle, SW_MINIMIZE); // focus goes back to the game
    }

    void ToggleMaximize()
    {
        SetMaximized(!maximized);
        cfg.Maximized = maximized;
        cfg.Save();
    }

    // Maximize by filling the screen's working area ourselves: the native maximize
    // (SW_MAXIMIZE) activates the window and would steal focus from the game.
    void SetMaximized(bool on)
    {
        if (on == maximized) return;
        if (on)
        {
            normalBounds = Bounds;
            Bounds = Screen.FromRectangle(Bounds).WorkingArea;
        }
        else if (!normalBounds.IsEmpty)
        {
            Bounds = normalBounds;
        }
        maximized = on;
        UpdateMaximizeButton();
    }

    // Flat caption button the full height of the title bar; close turns red on hover.
    static Button CaptionButton(string text, string tooltip, Action action, bool isClose)
    {
        var b = new Button
        {
            Text = text, Width = 46, Height = TITLE_BAR_HEIGHT, FlatStyle = FlatStyle.Flat,
            ForeColor = Color.White, BackColor = Color.FromArgb(36, 36, 36), Margin = Padding.Empty,
            TabStop = false,
        };
        if (captionFont != null) b.Font = captionFont;
        b.FlatAppearance.BorderSize = 0;
        b.FlatAppearance.MouseOverBackColor = isClose ? Color.FromArgb(196, 43, 28) : Color.FromArgb(62, 62, 62);
        b.FlatAppearance.MouseDownBackColor = isClose ? Color.FromArgb(160, 30, 20) : Color.FromArgb(80, 80, 80);
        b.Click += (_, _) => action();
        if (tooltip != "") new ToolTip().SetToolTip(b, tooltip);
        return b;
    }

    const int TITLE_BAR_HEIGHT = 32;

    static Button ToolbarButton(string text, string tooltip, Action action, int width = 32)
    {
        var b = new Button
        {
            Text = text, Width = width, Height = 26, FlatStyle = FlatStyle.Flat,
            ForeColor = Color.White, BackColor = Color.FromArgb(52, 52, 52), Margin = new Padding(2, 1, 2, 1),
            TabStop = false,
        };
        b.FlatAppearance.BorderColor = Color.FromArgb(70, 70, 70);
        b.Click += (_, _) => action();
        new ToolTip().SetToolTip(b, tooltip);
        return b;
    }

    void CreateTray()
    {
        menu.Items.Add(new ToolStripMenuItem($"{AppInfo.Name} v{AppInfo.Version}") { Enabled = false });
        itemUpdate.Click += (_, _) => _ = UpdateNow();
        menu.Items.Add(itemUpdate); // shown only when GitHub has a newer version
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem(Strings.OpenLinksIn) { Enabled = false });
        itemFloating = new ToolStripMenuItem(Strings.Floating, null, (_, _) => SetMode("floating"));
        itemChrome = new ToolStripMenuItem("Chrome", null, (_, _) => SetMode("chrome"));
        itemPaused = new ToolStripMenuItem(Strings.Paused, null, (_, _) => SetMode("paused"));
        menu.Items.AddRange(new ToolStripItem[] { itemFloating, itemChrome, itemPaused, new ToolStripSeparator() });

        menu.Items.Add(new ToolStripMenuItem($"{Strings.ToggleWindow} ({cfg.Hotkey})", null, (_, _) => ToggleOverlay()));
        itemOnTop = new ToolStripMenuItem(Strings.AlwaysOnTop, null, (_, _) =>
        {
            cfg.AlwaysOnTop = !cfg.AlwaysOnTop; cfg.Save(); ApplyTopMost(); RefreshMenu();
        });
        menu.Items.Add(itemOnTop);

        var opacity = new ToolStripMenuItem(Strings.Opacity);
        foreach (var v in new[] { 1.0, 0.9, 0.8, 0.7, 0.6 })
        {
            opacity.DropDownItems.Add(new ToolStripMenuItem((int)(v * 100) + " %", null, (_, _) =>
            {
                cfg.Opacity = v; cfg.Save(); Opacity = v;
            }) { Tag = v });
        }
        opacity.DropDownOpening += (_, _) =>
        {
            foreach (ToolStripMenuItem i in opacity.DropDownItems)
                i.Checked = Math.Abs((double)i.Tag! - cfg.Opacity) < 0.01;
        };
        menu.Items.Add(opacity);

        itemOnlyWow = new ToolStripMenuItem(Strings.OnlyFromWow, null, (_, _) =>
        {
            cfg.OnlyFromWow = !cfg.OnlyFromWow; cfg.Save(); RefreshMenu();
        });
        menu.Items.Add(itemOnlyWow);
        itemStartup = new ToolStripMenuItem(Strings.StartWithWindows, null, (_, _) => { ToggleStartup(); RefreshMenu(); });
        menu.Items.Add(itemStartup);
        itemCheckUpdates = new ToolStripMenuItem(Strings.CheckUpdates, null, (_, _) =>
        {
            cfg.CheckUpdates = !cfg.CheckUpdates; cfg.Save(); RefreshMenu();
            if (cfg.CheckUpdates) _ = CheckForUpdate();
        });
        menu.Items.Add(itemCheckUpdates);

        var diagnostics = new ToolStripMenuItem(Strings.DiagnosticLog);
        itemLog = new ToolStripMenuItem(Strings.DiagnosticLog, null, (_, _) =>
        {
            cfg.DiagnosticLog = !cfg.DiagnosticLog; cfg.Save(); RefreshMenu();
            Log($"diagnostic log enabled v{AppInfo.Version} · mode = {cfg.Mode} · only WoW = {cfg.OnlyFromWow}");
        });
        diagnostics.DropDownItems.Add(itemLog);
        diagnostics.DropDownItems.Add(new ToolStripMenuItem(Strings.OpenLogFolder, null, (_, _) =>
        {
            Directory.CreateDirectory(AppInfo.DataFolder);
            Process.Start(new ProcessStartInfo(AppInfo.DataFolder) { UseShellExecute = true });
        }));
        menu.Items.Add(diagnostics);

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem(Strings.Exit, null, (_, _) => ExitApp()));
        menu.Opening += (_, _) => RefreshMenu();

        tray.Icon = Icon ?? SystemIcons.Application;
        tray.Text = AppInfo.Name;
        tray.ContextMenuStrip = menu;
        tray.DoubleClick += (_, _) => ToggleOverlay();
        // Clicking the "new version" balloon opens the download page; other balloons do nothing.
        tray.BalloonTipClicked += (_, _) => { if (balloonIsUpdate) _ = UpdateNow(); balloonIsUpdate = false; };
        tray.BalloonTipClosed += (_, _) => balloonIsUpdate = false;
        tray.Visible = true;
        RefreshMenu();
        tray.ShowBalloonTip(3000, AppInfo.Name,
            justUpdated ? string.Format(Strings.Updated, AppInfo.Version) : string.Format(Strings.Listening, ModeName()),
            ToolTipIcon.Info);
    }

    void RefreshMenu()
    {
        if (itemFloating == null) return;
        itemFloating.Checked = cfg.Mode == "floating";
        itemChrome!.Checked = cfg.Mode == "chrome";
        itemPaused!.Checked = cfg.Mode == "paused";
        itemOnTop!.Checked = cfg.AlwaysOnTop;
        itemOnlyWow!.Checked = cfg.OnlyFromWow;
        itemStartup!.Checked = StartupEnabled();
        itemLog!.Checked = cfg.DiagnosticLog;
        itemCheckUpdates!.Checked = cfg.CheckUpdates;
        itemUpdate.Visible = (cfg.CheckUpdates && newerVersion != null) || updating;
        itemUpdate.Enabled = !updating;
        if (newerVersion != null)
            itemUpdate.Text = string.Format(updating ? Strings.Updating : Strings.UpdateTo, newerVersion);
        var title = AppInfo.Name + " · " + ModeName();
        tray.Text = title.Length > 63 ? title[..63] : title; // NotifyIcon text limit
    }

    string ModeName() => cfg.Mode switch { "chrome" => "Chrome", "paused" => Strings.ModePaused, _ => Strings.ModeFloating };

    void SetMode(string mode)
    {
        cfg.Mode = mode;
        cfg.Save();
        RefreshMenu();
        tray.ShowBalloonTip(1500, AppInfo.Name, Strings.Mode + ": " + ModeName(), ToolTipIcon.None);
    }

    // ------------------------------------------------------------ clipboard
    void OnClipboardChanged()
    {
        if (cfg.Mode == "paused") { Log("copy ignored: paused"); return; }
        var foreground = ForegroundProcessName();
        bool fromWow = foreground.StartsWith("Wow", StringComparison.OrdinalIgnoreCase);
        if (cfg.OnlyFromWow && !fromWow) { Log("copy ignored: foreground = " + foreground); return; }
        ReadClipboard(foreground, 0);
    }

    // WoW may keep the clipboard open for a moment: retry a few times.
    void ReadClipboard(string foreground, int attempt)
    {
        string text;
        try
        {
            if (!Clipboard.ContainsText()) { Log("copy without text (foreground = " + foreground + ")"); return; }
            text = Clipboard.GetText().Trim();
        }
        catch (Exception ex)
        {
            if (attempt < 8)
            {
                var timer = new System.Windows.Forms.Timer { Interval = 80 };
                timer.Tick += (_, _) => { timer.Stop(); timer.Dispose(); ReadClipboard(foreground, attempt + 1); };
                timer.Start();
            }
            else Log("clipboard busy after 8 attempts: " + ex.GetType().Name);
            return;
        }

        if (text.Length > 600 || !WowheadUrl.IsMatch(text))
        {
            Log($"copy without a Wowhead link (foreground = {foreground}, {text.Length} characters)");
            return;
        }
        // Windows may notify the same copy twice.
        if (text == lastText && (DateTime.Now - lastTime).TotalSeconds < 1.5) return;
        lastText = text;
        lastTime = DateTime.Now;

        Log($"link ({cfg.Mode}, attempt {attempt}): {text}");
        if (cfg.Mode == "chrome") OpenInChrome(text);
        else ShowInOverlay(text);
    }

    static string ForegroundProcessName()
    {
        try
        {
            GetWindowThreadProcessId(GetForegroundWindow(), out uint pid);
            using var p = Process.GetProcessById((int)pid);
            return p.ProcessName;
        }
        catch (Exception ex) { return "unknown (" + ex.GetType().Name + ")"; }
    }

    // --------------------------------------------------------------- chrome
    static string? ChromePath()
    {
        foreach (var root in new[] { Registry.CurrentUser, Registry.LocalMachine })
        {
            try
            {
                using var k = root.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe");
                if (k?.GetValue(null) is string p && File.Exists(p)) return p;
            }
            catch { }
        }
        foreach (var p in new[]
        {
            @"C:\Program Files\Google\Chrome\Application\chrome.exe",
            @"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Google\Chrome\Application\chrome.exe"),
        })
            if (File.Exists(p)) return p;
        return null;
    }

    void OpenInChrome(string url)
    {
        try
        {
            var chrome = ChromePath();
            var psi = chrome != null
                ? new ProcessStartInfo(chrome) { UseShellExecute = false }
                : new ProcessStartInfo(url) { UseShellExecute = true }; // default browser
            if (chrome != null) psi.ArgumentList.Add(url);
            Process.Start(psi);
        }
        catch (Exception ex)
        {
            tray.ShowBalloonTip(3000, AppInfo.Name, string.Format(Strings.ChromeFailed, ex.Message), ToolTipIcon.Error);
        }
    }

    // ------------------------------------------------------ floating window
    void ShowInOverlay(string url)
    {
        ShowOverlay();
        Navigate(url);
    }

    void Navigate(string url)
    {
        navigated = true;
        if (webReady) web.CoreWebView2.Navigate(url);
        else pendingUrl = url;
    }

    void ShowOverlay()
    {
        if (!Visible) Visible = true;
        // Show and raise through Win32 as well: WinForms alone left the window
        // hidden or behind the game in some cases. SW_SHOWNOACTIVATE also restores
        // a minimized window without taking focus from the game.
        ShowWindow(Handle, SW_SHOWNOACTIVATE);
        ApplyTopMost();
        Log($"window shown at {Bounds} · visible = {IsWindowVisible(Handle)} · topmost = {IsTopMost()}");
        webInit ??= InitWebView();
    }

    void HideOverlay()
    {
        Log("hide requested");
        SaveBounds();
        Hide();
    }

    void ToggleOverlay()
    {
        Log("hotkey pressed (visible = " + Visible + ")");
        if (Visible && !IsIconic(Handle)) { HideOverlay(); return; } // a minimized window is restored instead
        ShowOverlay();
        if (!navigated) Navigate(Strings.WowheadHome);
    }

    bool IsTopMost() => (GetWindowLong(Handle, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;

    void ApplyTopMost()
    {
        TopMost = cfg.AlwaysOnTop;
        // Re-assert above the (borderless) game window without stealing focus.
        uint flags = SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | (Visible ? SWP_SHOWWINDOW : 0);
        SetWindowPos(Handle, cfg.AlwaysOnTop ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0, flags);
        if (!cfg.AlwaysOnTop || IsTopMost()) return;

        // Still refused: share the input state of the foreground (game) thread
        // for this one call, which lifts the foreground lock. Focus does not move.
        uint gameThread = GetWindowThreadProcessId(GetForegroundWindow(), out _);
        uint ownThread = GetCurrentThreadId();
        bool attached = gameThread != 0 && gameThread != ownThread && AttachThreadInput(ownThread, gameThread, true);
        try { SetWindowPos(Handle, HWND_TOPMOST, 0, 0, 0, 0, flags); }
        finally { if (attached) AttachThreadInput(ownThread, gameThread, false); }
        Log($"topmost refused, retried with AttachThreadInput (attached = {attached}) · topmost = {IsTopMost()}");
    }

    async Task InitWebView()
    {
        try
        {
            var env = await CoreWebView2Environment.CreateAsync(null, Path.Combine(AppInfo.DataFolder, "WebView2"));
            await web.EnsureCoreWebView2Async(env);
            var core = web.CoreWebView2;
            // Links that would open a new window stay in this one.
            core.NewWindowRequested += (_, e) => { e.Handled = true; core.Navigate(e.Uri); };
            core.DocumentTitleChanged += (_, _) => pageTitle.Text = core.DocumentTitle;
            webReady = true;
            if (pendingUrl != null) { core.Navigate(pendingUrl); pendingUrl = null; }
        }
        catch (Exception ex)
        {
            webInit = null;
            Log("WebView2 failed: " + ex.Message);
            tray.ShowBalloonTip(5000, AppInfo.Name, string.Format(Strings.NeedsWebView2, ex.Message), ToolTipIcon.Warning);
            if (pendingUrl != null) { OpenInChrome(pendingUrl); pendingUrl = null; }
            Hide();
        }
    }

    string? CurrentUrl() => webReady ? web.CoreWebView2.Source : null;

    // ------------------------------------------------------------- position
    void PlaceInitially()
    {
        var area = Screen.PrimaryScreen?.WorkingArea ?? new Rectangle(0, 0, 1280, 720);
        var r = new Rectangle(cfg.X, cfg.Y, Math.Max(cfg.Width, 420), Math.Max(cfg.Height, 300));
        bool onScreen = cfg.X >= 0 && Screen.AllScreens.Any(s => s.WorkingArea.IntersectsWith(r));
        if (!onScreen)
        {
            r.X = area.Right - r.Width - 40;
            r.Y = area.Top + (area.Height - r.Height) / 2;
        }
        Bounds = r;
    }

    void RestoreMaximizedState()
    {
        if (cfg.Maximized) SetMaximized(true);
    }

    void SaveBounds()
    {
        // While maximized, the saved bounds stay the normal ones.
        if (!Visible || maximized || IsIconic(Handle) || WindowState != FormWindowState.Normal) return;
        cfg.X = Left; cfg.Y = Top; cfg.Width = Width; cfg.Height = Height;
        cfg.Save();
    }

    // --------------------------------------------------------------- hotkey
    void RegisterConfiguredHotkey()
    {
        uint mods = 0x4000; // MOD_NOREPEAT
        Keys key = Keys.None;
        foreach (var part in cfg.Hotkey.Split('+', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
        {
            switch (part.ToLowerInvariant())
            {
                case "ctrl": case "control": mods |= 0x2; break;
                case "shift": mods |= 0x4; break;
                case "alt": mods |= 0x1; break;
                case "win": mods |= 0x8; break;
                default: Enum.TryParse(part, true, out key); break;
            }
        }
        bool ok = key != Keys.None && RegisterHotKey(Handle, HOTKEY_ID, mods, (uint)key);
        Log($"hotkey {cfg.Hotkey} = {ok}");
        if (!ok)
            tray.ShowBalloonTip(4000, AppInfo.Name, string.Format(Strings.HotkeyBusy, cfg.Hotkey), ToolTipIcon.Warning);
    }

    // -------------------------------------------------------------- startup
    static bool StartupEnabled()
    {
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(RUN_KEY);
            return k?.GetValue(RUN_VALUE) is string v && v.Contains(Application.ExecutablePath, StringComparison.OrdinalIgnoreCase);
        }
        catch { return false; }
    }

    // "Start with Windows" stores the path of the .exe. If it points to an older
    // copy (or to one that no longer exists), point it to this one instead, so
    // Windows does not keep starting the old version.
    void RepointStartup()
    {
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(RUN_KEY, true);
            if (k?.GetValue(RUN_VALUE) is not string value) return; // not enabled
            var target = value.Trim().Trim('"');
            if (target.Equals(Application.ExecutablePath, StringComparison.OrdinalIgnoreCase)) return;
            var mine = AppInfo.FileVersion(Application.ExecutablePath);
            var theirs = File.Exists(target) ? AppInfo.FileVersion(target) : null;
            if (mine == null || (theirs != null && theirs >= mine)) return;
            k.SetValue(RUN_VALUE, "\"" + Application.ExecutablePath + "\"");
            Log($"start with Windows moved from {target} (v{theirs?.ToString(3) ?? "?"})");
        }
        catch { }
    }

    static void ToggleStartup()
    {
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(RUN_KEY, true);
            if (k == null) return;
            if (StartupEnabled()) k.DeleteValue(RUN_VALUE, false);
            else k.SetValue(RUN_VALUE, "\"" + Application.ExecutablePath + "\"");
        }
        catch { }
    }

    // -------------------------------------------------------------- updates
    // Asks GitHub for the latest release 20 s after start and then every 6 hours
    // (well under GitHub's 60 requests per hour). Only the version number is read;
    // nothing is downloaded or installed. Any network error is ignored.
    static readonly HttpClient http = CreateHttpClient();

    static HttpClient CreateHttpClient()
    {
        // No global timeout: each request sets its own (the .exe is ~70 MB).
        var client = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("WowheadForeverLink-Companion/" + AppInfo.Version);
        client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        return client;
    }

    void StartUpdateChecks()
    {
        updateTimer.Interval = 20_000;
        updateTimer.Tick += (_, _) =>
        {
            updateTimer.Interval = 6 * 60 * 60 * 1000;
            if (cfg.CheckUpdates) _ = CheckForUpdate();
        };
        updateTimer.Start();
    }

    async Task CheckForUpdate()
    {
        try
        {
            using var wait = new CancellationTokenSource(TimeSpan.FromSeconds(15));
            using var doc = JsonDocument.Parse(await http.GetStringAsync(AppInfo.LatestReleaseApi, wait.Token));
            var tag = doc.RootElement.GetProperty("tag_name").GetString() ?? "";
            var latest = ParseVersion(tag);
            var current = ParseVersion(AppInfo.Version);
            Log($"update check: latest = {tag}, current = {AppInfo.Version}");
            if (latest == null || current == null || latest <= current) return;

            newerVersion = latest.ToString(3);
            newerTag = tag;
            RefreshMenu();
            if (updateNowRequested) { updateNowRequested = false; _ = UpdateNow(); return; }
            if (updateBalloonShown) return; // the balloon once per run; the menu item stays
            updateBalloonShown = true;
            balloonIsUpdate = true;
            tray.ShowBalloonTip(10000, AppInfo.Name,
                string.Format(Strings.UpdateAvailable, newerVersion, AppInfo.Version), ToolTipIcon.Info);
        }
        catch (Exception ex) { Log("update check failed: " + ex.GetType().Name); }
    }

    // "v1.3.2" or "1.3.2" -> 1.3.2 (missing parts count as 0).
    static Version? ParseVersion(string text)
    {
        var m = Regex.Match(text, @"^v?(\d+)\.(\d+)(?:\.(\d+))?");
        if (!m.Success) return null;
        return new Version(int.Parse(m.Groups[1].Value), int.Parse(m.Groups[2].Value),
            m.Groups[3].Success ? int.Parse(m.Groups[3].Value) : 0);
    }

    static void OpenReleasesPage()
    {
        try { Process.Start(new ProcessStartInfo(AppInfo.ReleasesUrl) { UseShellExecute = true }); } catch { }
    }

    // Downloads the new .exe, checks it against SHA256SUMS.txt of the same release,
    // puts it in place of this one and restarts. If anything fails, this copy keeps
    // running unchanged and the download page opens instead.
    async Task UpdateNow()
    {
        if (updating || newerTag == null) return;
        updating = true;
        RefreshMenu();
        tray.ShowBalloonTip(3000, AppInfo.Name, string.Format(Strings.Updating, newerVersion), ToolTipIcon.None);
        try
        {
            Log($"update: downloading {newerTag}");
            await Updater.DownloadAndReplace(http, newerTag);
            Log("update: replaced, restarting");
            Updater.Restart();
            ExitApp();
        }
        catch (Exception ex)
        {
            Log($"update failed: {ex.GetType().Name}: {ex.Message}");
            updating = false;
            RefreshMenu();
            tray.ShowBalloonTip(5000, AppInfo.Name, string.Format(Strings.UpdateFailed, ex.Message), ToolTipIcon.Warning);
            OpenReleasesPage();
        }
    }

    // ----------------------------------------------------------------- exit
    void ExitApp()
    {
        exiting = true;
        updateTimer.Stop();
        SaveBounds();
        cfg.Save();
        try { RemoveClipboardFormatListener(Handle); UnregisterHotKey(Handle, HOTKEY_ID); } catch { }
        tray.Visible = false;
        tray.Dispose();
        web.Dispose();
        Close();
        Application.Exit();
    }
}
