# If you drag a file onto "Video Cruncher.bat", its path arrives here.
param([string]$InputFile = "")

# =====================================================================================
#  VIDEO CRUNCHER
#  Makes videos, music and GIFs look (and sound) horribly compressed, for comedy.
#  Built by Claude (Anthropic's AI) in conversation with heccfluffin.
# =====================================================================================
#
#  HOW THIS FILE IS LAID OUT (top to bottom):
#
#   1. Finding / downloading ffmpeg ..... ffmpeg is the free program that does all the
#                                          real video and audio work. This app is just a
#                                          friendly window that builds ffmpeg commands.
#   2. Look and feel .................... draws the glossy "Frutiger Aero" style: sky
#                                          background, bubbles, shiny buttons, glass panels.
#   3. Control helpers .................. small shortcuts for making labels, checkboxes,
#                                          dropdowns, sliders, etc.
#   4. The window ....................... builds the Video / MP3 / GIF panels and buttons.
#   5. Downloading GIFs from links ...... for the GIF mode's "paste a link" feature.
#   6. Command builders ................. turn your chosen settings into ffmpeg commands.
#                                          (This is where all the "crunch" recipes live.)
#   7. Running ffmpeg ................... runs those commands while keeping the window
#                                          responsive, one step at a time.
#   8. Buttons .......................... what CRUNCH IT, Preview, Crunch a folder and
#                                          Random! actually do when clicked.
#
#  HOW A CRUNCH WORKS, IN SHORT:
#   You pick settings -> a "Build-..." function turns them into one or more ffmpeg
#   command lines ("steps") -> "Invoke-Job" runs the steps in order, each one feeding
#   its result into the next -> the last step saves  yourfile_crunched.mp4/.mp3/.gif
#
#  A NOTE ON FFMPEG "FILTERS":
#   Most of the magic is ffmpeg filters, written like  scale=160:-2,fps=6
#   Each filter does one thing to the picture or sound, and commas chain them together
#   in order. For example  scale=160:-2  means "shrink to 160 pixels wide, keep the shape",
#   and  fps=6  means "keep only 6 frames per second". The notes below explain each one.
# =====================================================================================

# Load Windows' built-in tools for making windows, buttons and drawing graphics.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# If anything goes badly wrong, say so instead of silently vanishing
trap {
    [System.Windows.Forms.MessageBox]::Show(
        "Video Cruncher hit an error:`n`n$($_.Exception.Message)`n`nLine $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())`n`nTip: run 'Debug (shows errors).bat' and send a screenshot.",
        "Video Cruncher", "OK", "Error") | Out-Null
    exit 1
}

# =====================================================================================
#  1. FINDING / DOWNLOADING FFMPEG
# =====================================================================================
#
# The folder this script lives in.
$AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Once ffmpeg is found, its location is remembered in this little text file,
# so the app doesn't have to search your whole PC every time.
$ConfigFile = Join-Path $AppDir "ffmpeg-path.txt"

# Remember where ffmpeg is (writes the path into ffmpeg-path.txt).
function Save-FFmpegPath($path) {
    try { Set-Content -LiteralPath $ConfigFile -Value $path -Encoding UTF8 } catch {}
}

# Look for ffmpeg.exe, trying the quickest places first. Returns its path, or nothing.
function Find-FFmpeg {
    # 1. Remembered from last time
    if (Test-Path -LiteralPath $ConfigFile) {
        $saved = (Get-Content -LiteralPath $ConfigFile -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($saved -and (Test-Path -LiteralPath $saved.Trim())) { return $saved.Trim() }
    }
    # 2. Next to this app
    $local = Join-Path $AppDir "ffmpeg.exe"
    if (Test-Path $local) { return $local }
    # 3. On the PATH
    $cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($cmd) { Save-FFmpegPath $cmd.Source; return $cmd.Source }

    # 4. Search the usual install spots
    $status.Text = "Looking for ffmpeg on your PC..."
    $progress.Style = "Marquee"
    $form.Refresh()
    try {
        $direct = @(
            "C:\ffmpeg\bin\ffmpeg.exe", "C:\ffmpeg\ffmpeg.exe",
            "$env:LOCALAPPDATA\Microsoft\WinGet\Links\ffmpeg.exe",
            "$env:USERPROFILE\scoop\shims\ffmpeg.exe",
            "$env:ProgramData\chocolatey\bin\ffmpeg.exe"
        )
        foreach ($p in $direct) { if (Test-Path -LiteralPath $p) { Save-FFmpegPath $p; return $p } }

        # Folders with "ffmpeg" in the name in common locations
        $roots = @("C:\", $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA,
                   "$env:LOCALAPPDATA\Programs", "$env:LOCALAPPDATA\Microsoft\WinGet\Packages",
                   $env:USERPROFILE, "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop",
                   "$env:USERPROFILE\Documents", "$env:USERPROFILE\OneDrive\Desktop",
                   "$env:USERPROFILE\OneDrive\Documents") | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
        foreach ($root in $roots) {
            [System.Windows.Forms.Application]::DoEvents()
            $dirs = Get-ChildItem -LiteralPath $root -Directory -Filter "*ffmpeg*" -ErrorAction SilentlyContinue
            foreach ($d in $dirs) {
                $hit = Get-ChildItem -LiteralPath $d.FullName -Recurse -Depth 4 -Filter "ffmpeg.exe" -ErrorAction SilentlyContinue |
                       Select-Object -First 1
                if ($hit) { Save-FFmpegPath $hit.FullName; return $hit.FullName }
            }
        }

        # Last resort: a loose ffmpeg.exe sitting in Downloads/Desktop (a few folders deep)
        foreach ($root in @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop") | Where-Object { Test-Path -LiteralPath $_ }) {
            [System.Windows.Forms.Application]::DoEvents()
            $hit = Get-ChildItem -LiteralPath $root -Recurse -Depth 3 -Filter "ffmpeg.exe" -ErrorAction SilentlyContinue |
                   Select-Object -First 1
            if ($hit) { Save-FFmpegPath $hit.FullName; return $hit.FullName }
        }
    } finally {
        $progress.Style = "Blocks"; $progress.Value = 0
        $status.Text = "Ready."
    }
    return $null
}

# Let you point to ffmpeg.exe yourself with a normal "Open file" window.
# (Used by the "ffmpeg location..." link and the "No" option in the popup.)
function Select-FFmpeg {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Find ffmpeg.exe"
    $dlg.Filter = "ffmpeg.exe|ffmpeg.exe|Programs (*.exe)|*.exe"
    if ($dlg.ShowDialog() -eq "OK") {
        Save-FFmpegPath $dlg.FileName
        $status.Text = "Using ffmpeg at $($dlg.FileName)"
        return $dlg.FileName
    }
    return $null
}

# Ask whether to download ffmpeg, then download and unzip it next to this app.
# The download runs as a background "job" so the window doesn't freeze while it happens.
function Install-FFmpeg($skipQuestion = $false) {
    $answer = if ($skipQuestion) { "Yes" } else { [System.Windows.Forms.MessageBox]::Show(
        "Couldn't find ffmpeg on your PC automatically.`n`n" +
        "YES  -  Download it now (free, ~100 MB, saved next to this app)`n" +
        "NO   -  I already have it, let me find ffmpeg.exe myself`n" +
        "CANCEL  -  Never mind",
        "ffmpeg needed", "YesNoCancel", "Question") }
    if ($answer -eq "No") { return Select-FFmpeg }
    if ($answer -ne "Yes") { return $null }

    $status.Text = "Downloading ffmpeg... (this can take a minute)"
    $progress.Style = "Marquee"
    $form.Refresh()

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        $zip = Join-Path $env:TEMP "ffmpeg-cruncher.zip"
        $extract = Join-Path $env:TEMP "ffmpeg-cruncher"
        # Everything inside this { } block runs in the background.
        $job = Start-Job -ScriptBlock {
            param($zip, $extract)
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" -OutFile $zip -UseBasicParsing
            if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
            Expand-Archive $zip -DestinationPath $extract -Force
        } -ArgumentList $zip, $extract
        $script:CurrentJob = $job
        while ($job.State -eq 'Running') {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }
        $script:CurrentJob = $null
        Receive-Job $job -ErrorAction Stop | Out-Null
        Remove-Job $job

        $exe = Get-ChildItem $extract -Recurse -Filter ffmpeg.exe | Select-Object -First 1
        if (-not $exe) { throw "ffmpeg.exe not found in the download." }
        $dest = Join-Path $AppDir "ffmpeg.exe"
        Copy-Item $exe.FullName $dest -Force
        Save-FFmpegPath $dest
        Remove-Item $zip, $extract -Recurse -Force -ErrorAction SilentlyContinue
        $status.Text = "ffmpeg installed. Ready to crunch."
        return $dest
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Couldn't download ffmpeg:`n$($_.Exception.Message)`n`nYou can download it manually from https://www.gyan.dev/ffmpeg/builds/ and put ffmpeg.exe next to VideoCruncher.ps1.",
            "Download failed", "OK", "Error") | Out-Null
        $status.Text = "ffmpeg missing."
        return $null
    } finally {
        $progress.Style = "Blocks"
        $progress.Value = 0
    }
}

# =====================================================================================
#  2. LOOK AND FEEL (glossy Frutiger Aero style)
#  Plus a few general settings used everywhere.
# =====================================================================================
# Which file types count as videos and as audio (used for drag-and-drop and batch mode).
$VideoExts = @(".mp4", ".mov", ".mkv", ".avi", ".webm", ".m4v", ".wmv", ".flv", ".3gp")
$AudioExts = @(".mp3", ".wav", ".m4a", ".aac", ".ogg", ".flac", ".wma", ".opus")
# A scratch folder for in-between files while a crunch has several steps. Wiped after each crunch.
$Work = Join-Path $env:TEMP "videocruncher-work"
# Some countries write decimals as "1,5" instead of "1.5". ffmpeg always needs "1.5",
# so numbers are always written the "invariant" (international) way using Num below.
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
function Num($x) { return ([double]$x).ToString($Inv) }   # always "1.5", never "1,5"

# Shortcut for making a colour from red, green, blue (0-255) and optional transparency.
function RGB($r, $g, $b, $a = 255) { return [System.Drawing.Color]::FromArgb($a, $r, $g, $b) }
# The app's main colours.
$Ink      = RGB 22 58 94        # dark navy text
$CardFill = RGB 238 248 255     # frosted glass panel colour
$UIFont   = "Segoe UI"

# Makes a window part draw off-screen first, then show it all at once.
# Stops flickering when the glossy graphics redraw.
function Set-DoubleBuffered($ctl) {
    $prop = $ctl.GetType().GetProperty("DoubleBuffered", [Reflection.BindingFlags]"Instance,NonPublic")
    if ($prop) { $prop.SetValue($ctl, $true, $null) }
}

# Builds the outline of a rectangle with rounded corners (used for buttons and panels).
# x, y = top-left corner, w/h = width/height, r = how round the corners are.
function New-RoundPath($x, $y, $w, $h, $r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

# Shiny "gel" button image: rounded gradient with a glassy highlight on the top half
# Paints a shiny "gel" button picture:
#   1. a rounded shape filled with a top-to-bottom colour fade
#   2. a see-through white shine over the top half (the glassy reflection)
#   3. a faint glow along the bottom
#   4. a thin darker outline
function New-GlossImage($w, $h, $top, $bottom, $border) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = "AntiAlias"
    $r = [math]::Min([int]($h / 2), 18)
    $path = New-RoundPath 0 0 ($w - 1) ($h - 1) $r
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $fill = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $top, $bottom, 90)
    $g.FillPath($fill, $path)
    # glassy shine
    $shineH = [int]($h * 0.5)
    $shinePath = New-RoundPath 3 2 ($w - 7) $shineH ([math]::Max(2, [math]::Min($r - 3, [int]($shineH / 2))))
    $shineRect = New-Object System.Drawing.Rectangle(0, 2, $w, ($shineH + 1))
    $shine = New-Object System.Drawing.Drawing2D.LinearGradientBrush($shineRect, (RGB 255 255 255 200), (RGB 255 255 255 35), 90)
    $g.FillPath($shine, $shinePath)
    # soft glow at the bottom
    $glowRect = New-Object System.Drawing.Rectangle(0, [int]($h * 0.55), $w, [int]($h * 0.45))
    $glow = New-Object System.Drawing.Drawing2D.LinearGradientBrush($glowRect, (RGB 255 255 255 0), (RGB 255 255 255 90), 90)
    $g.FillRectangle($glow, (New-Object System.Drawing.Rectangle(4, [int]($h * 0.6), ($w - 8), [int]($h * 0.35))))
    $pen = New-Object System.Drawing.Pen($border, 1.2)
    $g.DrawPath($pen, $path)
    $g.Dispose()
    return $bmp
}

# Colour sets for the shiny buttons: (top colour, bottom colour, outline colour).
$Gloss = @{
    Green  = @((RGB 140 230 90),  (RGB 40 150 30),  (RGB 30 110 25))
    Blue   = @((RGB 120 205 250), (RGB 20 120 210), (RGB 15 85 160))
    Aqua   = @((RGB 140 235 235), (RGB 20 160 180), (RGB 10 115 130))
    Orange = @((RGB 255 205 110), (RGB 240 120 20), (RGB 185 85 10))
    Glass  = @((RGB 255 255 255 230), (RGB 200 230 250 230), (RGB 120 170 210))
}

# A glossy button: normal / hover / pressed images, white bold text
# Makes a glossy button. It swaps between three pictures: normal, lighter when the
# mouse is over it, and darker while it's being clicked.
function New-GelButton($text, $x, $y, $w, $h, $colour, $parent, $fontSize = 11) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::Transparent
    $b.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::Transparent
    $b.BackColor = [System.Drawing.Color]::Transparent
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Font = New-Object System.Drawing.Font($UIFont, $fontSize, [System.Drawing.FontStyle]::Bold)
    Set-GelColour $b $colour
    $b.Add_MouseEnter({ $this.BackgroundImage = $this.Tag.Hover })
    $b.Add_MouseLeave({ $this.BackgroundImage = $this.Tag.Normal })
    $b.Add_MouseDown({ $this.BackgroundImage = $this.Tag.Down })
    $b.Add_MouseUp({ $this.BackgroundImage = $this.Tag.Hover })
    $parent.Controls.Add($b)
    return $b
}
# (Re)paints a glossy button in one of the colour sets above.
# Used when making a button, and to light up the selected Video / MP3 / GIF button.
function Set-GelColour($b, $colour) {
    $c = $Gloss[$colour]
    $w = $b.Width; $h = $b.Height
    $light = [System.Windows.Forms.ControlPaint]::Light($c[0], 0.4)
    $dark  = [System.Windows.Forms.ControlPaint]::Dark($c[1], 0.05)
    $b.Tag = @{
        Normal = (New-GlossImage $w $h $c[0] $c[1] $c[2])
        Hover  = (New-GlossImage $w $h $light $c[1] $c[2])
        Down   = (New-GlossImage $w $h $dark $c[0] $c[2])
    }
    $b.BackgroundImage = $b.Tag.Normal
    $b.ForeColor = if ($colour -eq "Glass") { $Ink } else { [System.Drawing.Color]::White }
}

# Sky background: blue-to-white gradient, green hills, floating bubbles, glowing title
# Paints the window background once, as a picture:
# blue sky fading to white, a sun glow, two green hills, see-through bubbles, and the title.
function New-SkyImage($w, $h) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = "AntiAlias"; $g.TextRenderingHint = "AntiAliasGridFit"
    $sky = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle(0, 0, $w, $h)),
            (RGB 35 140 225), (RGB 225 245 255), 90)
    $g.FillRectangle($sky, 0, 0, $w, $h)
    # sun glow top-right
    $sunPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $sunPath.AddEllipse(($w - 260), -160, 420, 360)
    $sun = New-Object System.Drawing.Drawing2D.PathGradientBrush($sunPath)
    $sun.CenterColor = RGB 255 255 255 170
    $sun.SurroundColors = @((RGB 255 255 255 0))
    $g.FillPath($sun, $sunPath)
    # rolling green hills
    $hill1 = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle(0, ($h - 140), $w, 140)),
              (RGB 150 225 90), (RGB 50 160 50), 90)
    $g.FillEllipse($hill1, -200, ($h - 95), ($w * 0.9), 260)
    $hill2 = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle(0, ($h - 140), $w, 140)),
              (RGB 170 235 110), (RGB 70 175 60), 90)
    $g.FillEllipse($hill2, ($w * 0.35), ($h - 75), ($w * 0.95), 240)
    # bubbles
    # The bubbles are "random", but always the same pattern (the 7 fixes the pattern).
    $rnd = New-Object System.Random(7)
    for ($i = 0; $i -lt 22; $i++) {
        $d = $rnd.Next(14, 70); $x = $rnd.Next(-20, $w); $y = $rnd.Next(-10, ($h - 60))
        $bp = New-Object System.Drawing.Drawing2D.GraphicsPath
        $bp.AddEllipse($x, $y, $d, $d)
        $bb = New-Object System.Drawing.Drawing2D.PathGradientBrush($bp)
        $bb.CenterColor = RGB 255 255 255 15
        $bb.SurroundColors = @((RGB 255 255 255 110))
        $g.FillPath($bb, $bp)
        $g.FillEllipse((New-Object System.Drawing.SolidBrush((RGB 255 255 255 170))),
                       ($x + $d * 0.22), ($y + $d * 0.15), ($d * 0.28), ($d * 0.18))
        $g.DrawEllipse((New-Object System.Drawing.Pen((RGB 255 255 255 120), 1)), $x, $y, $d, $d)
    }
    # title with a soft glow
    $tf = New-Object System.Drawing.Font("Segoe UI Light", 28)
    $sf = New-Object System.Drawing.Font($UIFont, 10, [System.Drawing.FontStyle]::Italic)
    foreach ($o in @(@(-2, 0), @(2, 0), @(0, -2), @(0, 2), @(-1, -1), @(1, 1), @(-1, 1), @(1, -1))) {
        $g.DrawString("Video Cruncher", $tf, (New-Object System.Drawing.SolidBrush((RGB 255 255 255 70))), (22 + $o[0]), (10 + $o[1]))
    }
    $g.DrawString("Video Cruncher", $tf, (New-Object System.Drawing.SolidBrush((RGB 10 70 140))), 22, 10)
    $g.DrawString("make it crunchy", $sf, (New-Object System.Drawing.SolidBrush((RGB 255 255 255 230))), 27, 58)
    $g.Dispose()
    return $bmp
}

# Frosted glass card: rounded panel with a soft white border
# Makes one of the frosted-glass panels that hold each mode's settings
# (rounded corners, white fade at the top, light blue border).
# Each mode (Video / MP3 / GIF) has its own card; only one is shown at a time.
function New-Card($x, $y, $w, $h) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($x, $y)
    $p.Size = New-Object System.Drawing.Size($w, $h)
    $p.BackColor = $CardFill
    $p.Region = New-Object System.Drawing.Region((New-RoundPath 0 0 $w $h 16))
    Set-DoubleBuffered $p
    $p.Add_Paint({
        $g = $_.Graphics; $g.SmoothingMode = "AntiAlias"
        $w = $this.Width; $h = $this.Height
        $top = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle(0, 0, $w, 60)),
                (RGB 255 255 255 255), $CardFill, 90)
        $g.FillRectangle($top, 0, 0, $w, 60)
        $g.DrawPath((New-Object System.Drawing.Pen((RGB 150 200 235), 2)), (New-RoundPath 1 1 ($w - 3) ($h - 3) 15))
    })
    $p.AllowDrop = $true
    $p.Visible = $false
    return $p
}

# =====================================================================================
#  3. CONTROL HELPERS
#  Shortcuts for making the bits you click on. All positions are measured from the
#  top-left of the panel, with a little padding added so nothing touches the edge.
# =====================================================================================
$PadX = 14; $PadY = 12
# Turns an (x, y) position into a screen point, adding the padding.
function P($x, $y) { return New-Object System.Drawing.Point(($x + $PadX), ($y + $PadY)) }
# Plain text.
function New-Label($text, $x, $y, $parent) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.AutoSize = $true; $l.Location = P $x $y
    $l.BackColor = [System.Drawing.Color]::Transparent; $l.ForeColor = $Ink
    $parent.Controls.Add($l); return $l
}
# A tick box.
function New-Check($text, $x, $y, $parent) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $text; $c.AutoSize = $true; $c.Location = P $x $y
    $c.BackColor = [System.Drawing.Color]::Transparent; $c.ForeColor = $Ink
    $c.Cursor = [System.Windows.Forms.Cursors]::Hand
    $parent.Controls.Add($c); return $c
}
# A drop-down list (you can only pick from the list, not type your own).
function New-Combo($items, $x, $y, $w, $parent) {
    $c = New-Object System.Windows.Forms.ComboBox
    $c.DropDownStyle = "DropDownList"; $c.Location = P $x $y
    $c.Size = New-Object System.Drawing.Size($w, 26)
    foreach ($i in $items) { [void]$c.Items.Add($i) }
    $c.SelectedIndex = 0
    $parent.Controls.Add($c); return $c
}
# Small grey italic text for tips.
function New-Hint($text, $x, $y, $parent) {
    $l = New-Label $text $x $y $parent
    $l.ForeColor = RGB 70 110 150
    $l.Font = New-Object System.Drawing.Font($UIFont, 8.5, [System.Drawing.FontStyle]::Italic)
    return $l
}
# A box you can type into.
function New-TextField($x, $y, $w, $parent) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = P $x $y; $t.Size = New-Object System.Drawing.Size($w, 26)
    $parent.Controls.Add($t); return $t
}
# A text box for a file path, plus a "Browse..." button that opens a file picker.
# $filter decides which file types the picker shows.
function New-FilePicker($parent, $filter) {
    $box = New-TextField 0 30 430 $parent
    $btn = New-GelButton "Browse..." ($PadX + 440) ($PadY + 27) 96 31 "Glass" $parent 10
    $btn.Tag.Box = $box; $btn.Tag.Filter = $filter
    $btn.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = $this.Tag.Filter
        if ($dlg.ShowDialog() -eq "OK") { $this.Tag.Box.Text = $dlg.FileName }
    })
    return $box
}
# The "Crunch level" slider (1-10), with a label above it that shows the level's funny name.
function New-Slider($parent, $names) {
    $lbl = New-Label "" 0 70 $parent
    $lbl.Font = New-Object System.Drawing.Font($UIFont, 10, [System.Drawing.FontStyle]::Bold)
    $sl = New-Object System.Windows.Forms.TrackBar
    $sl.Minimum = 1; $sl.Maximum = 10; $sl.Value = 7; $sl.TickFrequency = 1
    $sl.Location = P 0 94
    $sl.Size = New-Object System.Drawing.Size(536, 45)
    $sl.BackColor = $CardFill
    $sl.Tag = @{ Label = $lbl; Names = $names }
    $sl.Add_ValueChanged({ $this.Tag.Label.Text = "Crunch level: $($this.Value)  -  $($this.Tag.Names[$this.Value])" })
    $lbl.Text = "Crunch level: $($sl.Value)  -  $($names[$sl.Value])"
    $parent.Controls.Add($sl)
    return $sl
}

# =====================================================================================
#  4. THE WINDOW
#  Builds everything you see: the main window, the three mode panels and the buttons.
# =====================================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Video Cruncher"
$form.ClientSize = New-Object System.Drawing.Size(620, 668)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.AllowDrop = $true
$form.Font = New-Object System.Drawing.Font($UIFont, 10)
$form.BackgroundImage = New-SkyImage 620 668
$form.BackgroundImageLayout = "None"
Set-DoubleBuffered $form

# The small "ffmpeg location..." link in the top-right corner.
$ffLink = New-Object System.Windows.Forms.LinkLabel
$ffLink.Text = "ffmpeg location..."
$ffLink.AutoSize = $true
$ffLink.BackColor = [System.Drawing.Color]::Transparent
$ffLink.LinkColor = RGB 10 70 140
$ffLink.Font = New-Object System.Drawing.Font($UIFont, 8.5)
$ffLink.Location = New-Object System.Drawing.Point(500, 24)
$ffLink.Add_LinkClicked({ [void](Select-FFmpeg) })
$form.Controls.Add($ffLink)

# Mode "pills" instead of plain tabs
# One panel per mode. (They're called "tabs" in the code because they used to be tabs.)
$videoTab = New-Card 20 130 580 398
$audioTab = New-Card 20 130 580 398
$gifTab   = New-Card 20 130 580 398
$form.Controls.AddRange(@($videoTab, $audioTab, $gifTab))
# The three glossy buttons at the top that switch between modes.
$pillVideo = New-GelButton "Video" 24 86 104 36 "Blue" $form
$pillAudio = New-GelButton "MP3"   134 86 104 36 "Glass" $form
$pillGif   = New-GelButton "GIF"   244 86 104 36 "Glass" $form
$script:Sel = $null
# Show the chosen mode's panel, hide the others, and light up its button in blue.
# $script:Sel always remembers which mode is showing.
function Select-Tab($tab) {
    foreach ($pair in @(@($videoTab, $pillVideo), @($audioTab, $pillAudio), @($gifTab, $pillGif))) {
        $on = ($pair[0] -eq $tab)
        $pair[0].Visible = $on
        Set-GelColour $pair[1] $(if ($on) { "Blue" } else { "Glass" })
    }
    $script:Sel = $tab
}
$pillVideo.Add_Click({ Select-Tab $videoTab })
$pillAudio.Add_Click({ Select-Tab $audioTab })
$pillGif.Add_Click({ Select-Tab $gifTab })

# -------------------------------------------------------------------------------------
#  VIDEO panel - every setting here is read later by Build-Video
#  (The numbers after each label are its x and y position on the panel.)
# -------------------------------------------------------------------------------------
# --- Video card ---
[void](New-Label "Pick a video (or drag one onto this window)" 0 6 $videoTab)
$videoBox = New-FilePicker $videoTab "Videos|*.mp4;*.mov;*.mkv;*.avi;*.webm;*.m4v;*.wmv;*.flv;*.3gp|All files|*.*"
# The funny name shown for each crunch level (the empty "" is level 0, which isn't used).
$videoNames = @("", "Slightly potato", "Potato", "Old YouTube", "Sent over WhatsApp 5 times",
                "Dial-up", "Security camera", "Nokia 3310", "Cursed", "Deep fried", "ATOMIZED")
$videoSlider = New-Slider $videoTab $videoNames
$fry      = New-Check "Deep fry colours"       0 145 $videoTab
$vPixel   = New-Check "Pixelate only (clean)"  182 145 $videoTab
$vGlitch  = New-Check "Glitch / datamosh"      364 145 $videoTab
$earrape  = New-Check "Distorted audio (LOUD)" 0 173 $videoTab
$vBass    = New-Check "Bass boost"             182 173 $videoTab
$vAsGif   = New-Check "Save as GIF (no sound)" 364 173 $videoTab
# GIFs have no sound, so the sound options are greyed out while "Save as GIF" is ticked.
$vAsGif.Add_CheckedChanged({ $earrape.Enabled = -not $vAsGif.Checked; $vBass.Enabled = -not $vAsGif.Checked; $vPitch.Enabled = -not $vAsGif.Checked })

[void](New-Label "Speed:" 0 216 $videoTab)
$SpeedItems = @("1x (normal)", "0.25x", "0.5x", "0.75x", "1.5x", "2x", "3x")
$vSpeed = New-Combo $SpeedItems 95 212 120 $videoTab
$vPitch = New-Check "Change pitch too (chipmunk / deep voice)" 230 214 $videoTab
$vPitch.Checked = $true

[void](New-Label "Stretch:" 0 251 $videoTab)
$StretchItems = @("Normal", "Wide", "Super wide", "Tall", "Super tall")
$vStretch = New-Combo $StretchItems 95 247 120 $videoTab

[void](New-Label "Re-uploads:" 0 286 $videoTab)
$ReupItems = @("None", "5 times", "10 times", "25 times", "50 times")
$vReup = New-Combo $ReupItems 95 282 120 $videoTab
[void](New-Hint "Re-crunches it again and again, like a meme reposted forever" 230 279 $videoTab)
[void](New-Hint "(more re-uploads = slower)" 230 297 $videoTab)
$vSeek = New-Check "Random seeking (skips back and forth through the video)" 0 320 $videoTab
$vYtp  = New-Check "Auto YTP (random YouTube Poop edits everywhere)" 0 348 $videoTab
$tooltip0 = New-Object System.Windows.Forms.ToolTip
$tooltip0.SetToolTip($vYtp, "Stutters, reverses, chipmunk / slow-mo, pitch changes, inverted colours, mirroring, rainbow, zoom, loud bursts and echo - all at random. Set crunch level 1 for YTP with only a little crunch.")

# -------------------------------------------------------------------------------------
#  MP3 panel - every setting here is read later by Build-Audio
# -------------------------------------------------------------------------------------
# --- MP3 card ---
[void](New-Label "Pick an audio file (or a video to rip the sound from)" 0 6 $audioTab)
$audioBox = New-FilePicker $audioTab ("Audio and video|*.mp3;*.wav;*.m4a;*.aac;*.ogg;*.flac;*.wma;*.opus;" +
                                      "*.mp4;*.mov;*.mkv;*.avi;*.webm;*.m4v|All files|*.*")
$audioNames = @("", "Slightly crispy", "Old radio", "Bad Bluetooth", "Phone on speaker", "Walkie-talkie",
                "Discord on 1 bar", "Drive-thru speaker", "Cursed", "Deep fried", "ATOMIZED")
$audioSlider = New-Slider $audioTab $audioNames
$aDistort  = New-Check "Crunchy distortion"   0 145 $audioTab
$aBass     = New-Check "Bass boost"           182 145 $audioTab
$aPhone    = New-Check "Phone call (tinny)"   364 145 $audioTab
$aWater    = New-Check "Underwater / muffled" 0 173 $audioTab
$aSlowed   = New-Check "Slowed + reverb"      182 173 $audioTab
$aNight    = New-Check "Nightcore"            364 173 $audioTab
$aBathroom = New-Check "Phone in a bathroom"  0 201 $audioTab
$aVinyl    = New-Check "Vinyl crackle"        182 201 $audioTab
$aStatic   = New-Check "Radio static"         364 201 $audioTab
# Slowed and Nightcore cancel each other out, so only allow one
$aSlowed.Add_CheckedChanged({ if ($aSlowed.Checked) { $aNight.Checked = $false } })
$aNight.Add_CheckedChanged({ if ($aNight.Checked) { $aSlowed.Checked = $false } })
[void](New-Hint "Turn your volume down before playing anything with distortion or bass boost!" 0 245 $audioTab)

# -------------------------------------------------------------------------------------
#  GIF panel - every setting here is read later by Build-Gif
# -------------------------------------------------------------------------------------
# --- GIF card ---
[void](New-Label "Pick a video or GIF file (or paste a link - see tip below)" 0 6 $gifTab)
$gifBox = New-FilePicker $gifTab ("Videos and GIFs|*.gif;*.webp;*.mp4;*.mov;*.mkv;*.avi;*.webm;*.m4v;*.wmv;*.flv;*.3gp|" +
                                  "All files|*.*")
$gifNames = @("", "Tumblr 2012", "Forum signature", "Reaction GIF", "MySpace page", "Geocities",
              "Under construction", "16 colours", "Cursed", "Deep fried", "ATOMIZED")
$gifSlider  = New-Slider $gifTab $gifNames
$gFry       = New-Check "Deep fry colours"      0 145 $gifTab
$gDither    = New-Check "Grainy dither"         182 145 $gifTab
$gBoomerang = New-Check "Boomerang"             364 145 $gifTab
$gShort     = New-Check "Only first 10 seconds" 0 173 $gifTab
$gShort.Checked = $true
$gDither.Checked = $true

[void](New-Label "Top text:" 0 216 $gifTab)
$gTop = New-TextField 100 212 436 $gifTab
[void](New-Label "Bottom text:" 0 251 $gifTab)
$gBottom = New-TextField 100 247 436 $gifTab
[void](New-Hint "Meme captions in Impact font. Leave blank for none." 100 278 $gifTab)
[void](New-Hint "Tip: saving the GIF to your PC first works best - links often fail or grab the wrong GIF." 0 318 $gifTab)

# -------------------------------------------------------------------------------------
#  Bottom of the window: the four big buttons, the progress bar and the status line.
#  (What the buttons actually do is in section 8, near the end of the file.)
# -------------------------------------------------------------------------------------
# --- Bottom bar ---
$go       = New-GelButton "CRUNCH IT"          20 542 170 46 "Green"  $form 12
$previewB = New-GelButton "Preview (3 sec)"   198 542 140 46 "Blue"   $form 10
$batchB   = New-GelButton "Crunch a folder"   346 542 150 46 "Aqua"   $form 10
$randomB  = New-GelButton "Random!"           504 542  96 46 "Orange" $form 10

# Little help bubbles that pop up when you hover over a button.
$tooltip = New-Object System.Windows.Forms.ToolTip
$tooltip.SetToolTip($previewB, "Crunch just the first 3 seconds with the current settings and play it")
$tooltip.SetToolTip($batchB, "Crunch every file in a folder with the current settings")
$tooltip.SetToolTip($randomB, "Surprise settings for the current mode")

# The progress bar. It just animates while something is running
# (ffmpeg doesn't tell us how far through it is, so it can't show a percentage).
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(20, 600)
$progress.Size = New-Object System.Drawing.Size(580, 18)
$progress.MarqueeAnimationSpeed = 30
$form.Controls.Add($progress)

# The status line at the very bottom ("Ready.", "Crunching...", "Done!" etc).
$status = New-Object System.Windows.Forms.Label
$status.Text = "Ready."
$status.AutoSize = $false
$status.BackColor = [System.Drawing.Color]::Transparent
$status.ForeColor = RGB 255 255 255
$status.Font = New-Object System.Drawing.Font($UIFont, 10, [System.Drawing.FontStyle]::Bold)
$status.Size = New-Object System.Drawing.Size(580, 24)
$status.Location = New-Object System.Drawing.Point(20, 628)
$form.Controls.Add($status)

# While crunching: grey out the buttons (so you can't start two crunches at once)
# and animate the progress bar. Set-Busy $false turns it all back on.
function Set-Busy($busy) {
    foreach ($c in @($go, $previewB, $batchB, $randomB, $pillVideo, $pillAudio, $pillGif, $videoTab, $audioTab, $gifTab)) {
        $c.Enabled = -not $busy
    }
    if ($busy) { $progress.Style = "Marquee" } else { $progress.Style = "Blocks"; $progress.Value = 0 }
}

# Start on the Video panel.
Select-Tab $videoTab

#
# Put a file in the right mode: GIFs go to GIF, audio files go to MP3; videos go to
# whichever of Video / MP3 / GIF you're on.
function Set-InputFile($path) {
    if (-not $path) { return }
    $ext = [System.IO.Path]::GetExtension($path).ToLower()
    if ($ext -eq ".gif" -or $ext -eq ".webp" -or ($script:Sel -eq $gifTab -and $AudioExts -notcontains $ext)) {
        $gifBox.Text = $path; Select-Tab $gifTab
    } elseif ($AudioExts -contains $ext -or $script:Sel -eq $audioTab) {
        $audioBox.Text = $path; Select-Tab $audioTab
    } else {
        $videoBox.Text = $path; Select-Tab $videoTab
    }
}
# If a file was dragged onto the .bat file, load it now.
Set-InputFile $InputFile

# ---------------- Drag and drop ----------------
# Lets you drop a file (or a link from your browser) anywhere on the window.
# While something is being dragged over the window: show the "copy" mouse cursor if it's a file or text.
$onDragEnter = {
    if ($_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop) -or
        $_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::UnicodeText)) { $_.Effect = "Copy" }
}
# When it's dropped: send the file to the right mode.
$onDragDrop = {
    if ($_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
        $files = $_.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
        if ($files.Count -gt 0) { Set-InputFile $files[0] }
    } else {
        # A link dragged in from the browser goes to GIF mode
        $text = ([string]$_.Data.GetData([System.Windows.Forms.DataFormats]::UnicodeText)).Trim()
        if ($text -match '^https?://') { $gifBox.Text = $text; Select-Tab $gifTab }
    }
}
foreach ($c in @($form, $videoTab, $audioTab, $gifTab)) { $c.Add_DragEnter($onDragEnter); $c.Add_DragDrop($onDragDrop) }

# =====================================================================================
#  5. DOWNLOADING GIFS FROM LINKS (GIF mode)
#  Many sites block this, so it tries hard to look like a normal web browser.
#  Saving the GIF to your PC first is always more reliable.
# =====================================================================================
# Download a GIF from a link. Works with direct media links (.gif/.mp4/.webm) and with
# GIF site pages (Klipy, Tenor, Giphy, ...) by finding the animation inside the page.
function Get-WebGif($url) {
    $tempDir = Join-Path $env:TEMP "videocruncher-dl"
    Set-Busy $true
    $status.Text = "Grabbing the GIF from the link..."
    try {
        $job = Start-Job -ArgumentList $url, $tempDir -ScriptBlock {
            param($url, $tempDir)
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $ProgressPreference = 'SilentlyContinue'
            $ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
            $mediaRx = '\.(gif|mp4|webm|mov|webp)(\?|$)'
            $headers = @{
                "Accept"          = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8"
                "Accept-Language" = "en-US,en;q=0.9"
                "Sec-Fetch-Dest"  = "document"
                "Sec-Fetch-Mode"  = "navigate"
                "Sec-Fetch-Site"  = "none"
                "Upgrade-Insecure-Requests" = "1"
            }
            # Download $u to $outFile like a browser would. Tries PowerShell first,
            # then Windows' built-in curl.exe, which some sites block less.
            function Get-Url($u, $outFile, $referer) {
                $h = $headers.Clone()
                if ($referer) { $h["Referer"] = $referer; $h["Sec-Fetch-Site"] = "cross-site"; $h["Sec-Fetch-Dest"] = "image" }
                try {
                    Invoke-WebRequest $u -OutFile $outFile -UseBasicParsing -UserAgent $ua -Headers $h -ErrorAction Stop
                    return
                } catch { $firstError = $_.Exception.Message }
                $curl = Join-Path $env:SystemRoot "System32\curl.exe"
                if (Test-Path $curl) {
                    $cargs = @("-sS", "-L", "-f", "--compressed", "-A", $ua, "-o", $outFile)
                    foreach ($k in $h.Keys) { $cargs += "-H"; $cargs += "${k}: $($h[$k])" }
                    $cargs += $u
                    & $curl @cargs 2>$null
                    if ($LASTEXITCODE -eq 0 -and (Test-Path $outFile)) { return }
                }
                throw "The site refused the download ($firstError).`n`nWorkaround: right-click the GIF in your browser, choose 'Copy image address' and paste that link instead - or 'Save image as...' and pick the saved file."
            }

            # What did we actually get? Check the first bytes rather than trusting the link.
            function Get-Kind($f) {
                $b = New-Object byte[] 16
                $fs = [System.IO.File]::OpenRead($f)
                try { $n = $fs.Read($b, 0, 16) } finally { $fs.Close() }
                if ($n -lt 12) { return $null }
                $a = [Text.Encoding]::ASCII.GetString($b, 0, $n)
                if ($a.StartsWith("GIF8")) { return ".gif" }
                if ($a.Substring(4, 4) -eq "ftyp") { return ".mp4" }
                if ($b[0] -eq 0x1A -and $b[1] -eq 0x45 -and $b[2] -eq 0xDF -and $b[3] -eq 0xA3) { return ".webm" }
                if ($a.StartsWith("RIFF") -and $a.Substring(8, 4) -eq "WEBP") { return ".webp" }
                return $null
            }

            # Find likely animation links inside a web page, best first
            function Find-Media($html, $pageUrl) {
                $html = $html -replace '\\/', '/' -replace '\\u002[Ff]', '/' -replace '&amp;', '&'
                $found = @(); $mainTags = @()
                # Links inside the page's share tags (og:video, og:image, twitter:...)
                foreach ($m in [regex]::Matches($html, '<meta[^>]+>')) {
                    $tag = $m.Value
                    if ($tag -match '(og:video|og:image|twitter:image|twitter:player:stream)' -and
                        $tag -match 'content\s*=\s*["'']([^"'']+)["'']') { $found += $Matches[1]; $mainTags += $Matches[1] }
                }
                # Any other media links anywhere in the page
                foreach ($m in [regex]::Matches($html, 'https?://[^"''\s<>()]+?\.(gif|mp4|webm|mov|webp)(\?[^"''\s<>()]*)?(?=["''\s<>()])')) {
                    $found += $m.Value
                }
                # Score them: prefer video (sharper), bigger versions, skip thumbnails
                $found | Where-Object { $_ -match $mediaRx -and $_ -ne $pageUrl } | Select-Object -Unique | Sort-Object -Descending {
                    $u = $_.ToLower(); $score = 0
                    if ($mainTags -contains $_) { $score += 100 }   # the page's main GIF, not a related one
                    if ($u -match '\.mp4') { $score += 30 } elseif ($u -match '\.webm') { $score += 20 } elseif ($u -match '\.gif') { $score += 10 } elseif ($u -match '\.webp') { $score += 5 }
                    if ($u -match '(/hd/|hd\.|original|large|/full)') { $score += 5 }
                    if ($u -match '(/sm/|/xs/|tiny|thumb|preview|small|/nano)') { $score -= 8 }
                    $score
                }
            }

            if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
            New-Item -ItemType Directory -Path $tempDir | Out-Null

            # 1. Download whatever the link points at
            $first = Join-Path $tempDir "first.bin"
            Get-Url $url $first $null
            $kind = Get-Kind $first
            if ($kind) {
                $file = Join-Path $tempDir ("download" + $kind)
                Move-Item $first $file -Force
                return $file
            }

            # 2. It was a web page (even if the link ended in .gif, like Tenor's share links):
            #    look inside it for the real animation and try the best few candidates
            $html = [System.IO.File]::ReadAllText($first)
            $candidates = @(Find-Media $html $url) | Select-Object -First 6
            foreach ($media in $candidates) {
                $tmp = Join-Path $tempDir "candidate.bin"
                try { Get-Url $media $tmp $url }
                catch { try { Get-Url $media $tmp $null } catch { continue } }   # some CDNs dislike a Referer
                $kind = Get-Kind $tmp
                if ($kind) {
                    $file = Join-Path $tempDir ("download" + $kind)
                    Move-Item $tmp $file -Force
                    return $file
                }
            }
            throw "Couldn't find the GIF on that page.`n`nWorkaround: right-click the GIF in your browser, choose 'Copy image address' and paste that link instead - or 'Save image as...' and pick the saved file."
        }
        $script:CurrentJob = $job
        while ($job.State -eq 'Running') {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }
        $script:CurrentJob = $null
        $result = Receive-Job $job -ErrorAction Stop
        Remove-Job $job
        return ($result | Select-Object -Last 1)
    } catch {
        $status.Text = "Couldn't get the GIF from that link."
        [System.Windows.Forms.MessageBox]::Show("Couldn't get the GIF from that link:`n`n$($_.Exception.Message)",
            "Video Cruncher", "OK", "Error") | Out-Null
        return $null
    } finally {
        Set-Busy $false
    }
}

# Where to save a crunched GIF that came from a link: your Downloads folder,
# named after the link (e.g. geometry-dash-flamewall-1_crunched.gif)
function Get-LinkSavePath($url) {
    $dl = Join-Path $env:USERPROFILE "Downloads"
    if (-not (Test-Path $dl)) { $dl = [Environment]::GetFolderPath("Desktop") }
    $slug = (([Uri]$url).AbsolutePath.TrimEnd('/') -split '/')[-1]
    $slug = [System.IO.Path]::GetFileNameWithoutExtension($slug) -replace '[^A-Za-z0-9_\-]', '_'
    if (-not $slug) { $slug = "gif" }
    return Join-Path $dl "$slug.gif"
}

# =====================================================================================
#  6. COMMAND BUILDERS - the crunch recipes
#  These read your settings and write the ffmpeg commands that do the actual work.
# =====================================================================================
#
# Works out the save name: "myvideo.mp4" -> "myvideo_crunched.mp4".
# If that already exists, it uses _crunched2, _crunched3, ... so nothing gets overwritten.
function Get-OutputPath($in, $ext) {
    $dir  = Split-Path -Parent $in
    $base = [System.IO.Path]::GetFileNameWithoutExtension($in)
    $out  = Join-Path $dir "${base}_crunched$ext"
    $n = 2
    while (Test-Path -LiteralPath $out) { $out = Join-Path $dir "${base}_crunched$n$ext"; $n++ }
    return $out
}

# Empties the scratch folder before a new crunch.
function Reset-Work {
    if (Test-Path $Work) { Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $Work -Force | Out-Null
}

# Turn "0.25x" etc. into a number
function Get-Speed {
    $txt = [string]$vSpeed.SelectedItem
    if ($txt -like "1x*") { return 1.0 }
    return [double]::Parse($txt.TrimEnd('x'), $Inv)
}

# Path for use inside an ffmpeg filter: forward slashes, escaped colon and quotes
function FilterPath($p) { return ($p -replace '\\', '/' -replace ':', '\:' -replace "'", "'\''") }

# Each builder returns a list of ffmpeg "steps". A step is a command line with
# placeholders: {IN} = previous step's output, {SRC} = the original file, {OUT} = this step's output.
# The last step writes the real output file. $limit = only use the first N seconds (for preview).

function Build-Video($limit) {
    # --- Turn the crunch level (1-10) into numbers. ---
    # $t goes from 0 (level 1) to 1 (level 10), and each setting slides between its
    # "mild" and "destroyed" value as $t goes up.
    $level = $videoSlider.Value
    $t     = ($level - 1) / 9.0
    $width = [int]([math]::Round((480 - $t * 400) / 2) * 2)    # 480px -> 80px internal resolution
    $fps   = [int][math]::Round(24 - $t * 18)                  # 24 fps -> 6 fps
    $vbit  = [int][math]::Round(250 - $t * 240)                # 250 kbps -> 10 kbps
    $abit  = @(48, 40, 32, 24, 20, 16, 12, 10, 8, 8)[$level - 1]
    $arate = @(22050, 22050, 16000, 16000, 11025, 11025, 11025, 8000, 8000, 8000)[$level - 1]
    $speed = Get-Speed   # the Speed drop-down as a number, e.g. 0.5
    $asGif = $vAsGif.Checked   # true if "Save as GIF" is ticked
    $tIn   = if ($limit) { "-t $limit " } else { "" }   # "-t 3" tells ffmpeg to only read the first 3 seconds (for Preview)

    # ---- PICTURE filters, applied in this order ----
#   (Only filters that come with EVERY version of ffmpeg are used. Some cut-down ffmpeg
#    builds leave out a few, like "eq", which caused "No such filter" errors before.)
    #   setpts=PTS/2         speeds up (or slows down) the video
    #   hue=s + curves       deep fry: crazy colours (saturation) and harsh contrast
    #   unsharp=...          deep fry: over-sharpen
    #   noise=...            deep fry: add grain
    #   scale=WIDTH:-2       shrink it right down (the "-2" keeps the shape)
    #   scale=iw*2:ih        stretch (iw/ih = the current width/height)
    #   fps=N                throw away frames for that choppy look
    #   scale=...neighbor    blow it back up with big blocky pixels, to fit in 640x640
    #   format=yuv420p       a colour format every video player understands
    $vf = @()
    if ($speed -ne 1) { $vf += "setpts=PTS/$(Num $speed)" }
    if ($fry.Checked) { $vf += "hue=s=2.5", "curves=preset=strong_contrast", "unsharp=5:5:2.0", "noise=alls=20:allf=t" }
    $vf += "scale=${width}:-2:flags=area"
    switch ($vStretch.SelectedIndex) {
        1 { $vf += "scale=iw*2:ih" }   # Wide
        2 { $vf += "scale=iw*4:ih" }   # Super wide
        3 { $vf += "scale=iw:ih*2" }   # Tall
        4 { $vf += "scale=iw:ih*4" }   # Super tall
    }
    if (-not $vPixel.Checked) { $vf += "fps=$fps" }
    # blow back up with chunky pixels to fit inside 640x640
    $vf += "scale='trunc(min(640/iw,640/ih)*iw/2)*2':'trunc(min(640/iw,640/ih)*ih/2)*2':flags=neighbor", "format=yuv420p"
    $vfStr = $vf -join ","

    # ---- SOUND filters ----
    #   asetrate + aresample   changes speed AND pitch together (chipmunk / deep voice)
    #   atempo                 changes speed but keeps the pitch normal (only works in 0.5x-2x
    #                          jumps, so it's repeated for bigger changes like 0.25x)
    #   bass=g=18              bass boost (+18 dB around 100 Hz)
    #   volume=8 + acrusher    way too loud, then crushed into crunchy 8-bit sound
    $af = @()
    if ($speed -ne 1) {
        if ($vPitch.Checked) {
            $af += "aresample=44100", "asetrate=$(Num (44100 * $speed))", "aresample=44100"
        } else {
            $s = $speed
            while ($s -lt 0.5) { $af += "atempo=0.5"; $s = $s / 0.5 }
            while ($s -gt 2.0) { $af += "atempo=2.0"; $s = $s / 2.0 }
            $af += "atempo=$(Num $s)"
        }
    }
    if ($vBass.Checked)   { $af += "bass=g=18:f=100:w=0.6" }
    if ($earrape.Checked) { $af += "volume=8", "acrusher=bits=8:mix=1" }
    $afArgs = if ($af.Count -and -not $asGif) { "-af `"$($af -join ',')`" " } else { "" }

    # ---- ENCODER settings: how the result is compressed (this is where the "crunch" happens) ----
    #   libx264 -b:v 10k       compress the picture into a tiny number of kilobits per second
    #   no-deblock=1           turn off the smoothing that normally hides compression blocks,
    #                          so you see big ugly squares instead of blur
    #   aac -b:a 8k -ar 8000   squash the sound to a tiny bitrate and phone-call sample rate
    #   -ac 1                  mono
    # "Pixelate only" uses high quality instead (crf 18) so it's clean blocky pixels.
    if ($vPixel.Checked) {
        $venc = "-c:v libx264 -preset veryfast -crf 18 "
        $aenc = "-c:a aac -b:a 128k "
    } else {
        $venc = "-c:v libx264 -preset veryfast -b:v ${vbit}k -maxrate ${vbit}k -bufsize $($vbit * 2)k -x264-params no-deblock=1 "
        $aenc = "-c:a aac -b:a ${abit}k -ar $arate -ac 1 "
    }
    $audioMap = if ($asGif) { "-an " } else { "-map 0:a? $afArgs$aenc" }

    $steps = @()
    # --- Now list the steps, in order. ---
    # Random seeking: chop the video into short random jumps first (built when it runs, as it needs the video's length)
    if ($vYtp.Checked) { $steps += @{ Ext = ".mp4"; Ytp = $true; Limit = $limit } }
    elseif ($vSeek.Checked) { $steps += @{ Ext = ".mp4"; Seek = $true; Limit = $limit } }
    if ($vGlitch.Checked) {
        # GLITCH works in 2 steps:
        #   1. save it with an old video format (mpeg4), with only ONE full picture at the start
        #      (-g 9999), and randomly damage the data as it's saved (-bsf:v noise)
        #   2. read the damaged file back, ignoring errors (-err_detect ignore_err). The player
        #      tries to fill in the broken bits by smearing old pixels around - that's the glitch.
        # Glitch: encode with an old codec, corrupt the data, then decode the damage back
        $steps += @{ Ext = ".avi"; Cmd = "-y -hide_banner $tIn-i `"{SRC}`" -an -vf `"$vfStr`" -c:v mpeg4 -q:v 12 -g 9999 -bsf:v noise=amount=4000 `"{OUT}`"" }
        $audioMap2 = if ($asGif) { "-an " } else { "-map 1:a? $afArgs$aenc" }
        $steps += @{ Ext = ".mp4"; Cmd = "-y -hide_banner -err_detect ignore_err -i `"{IN}`" $tIn-i `"{SRC}`" -map 0:v:0 $audioMap2-vf format=yuv420p $venc-movflags +faststart `"{OUT}`"" }
    } else {
        $steps += @{ Ext = ".mp4"; Cmd = "-y -hide_banner $tIn-i `"{SRC}`" -map 0:v:0 $audioMap-vf `"$vfStr`" $venc-movflags +faststart `"{OUT}`"" }
    }

    # Each re-upload is one more step: re-compress the last result again with a tiny bit of
    # extra sharpening and colour boost, so the damage slowly builds up like a reposted meme.
    # Re-uploads: crunch the result again and again
    $reups = @(0, 5, 10, 25, 50)[$vReup.SelectedIndex]
    $reAudio = if ($asGif) { "-an " } else { "-map 0:a? $aenc" }
    for ($i = 0; $i -lt $reups; $i++) {
        $steps += @{ Ext = ".mp4"; Cmd = "-y -hide_banner -i `"{IN}`" -map 0:v:0 $reAudio-vf `"unsharp=3:3:0.3,hue=s=1.02,format=yuv420p`" $venc`"{OUT}`"" }
    }

    if ($asGif) {
        $colors = @(128, 64, 48, 32, 24, 16, 12, 8, 6, 4)[$level - 1]
        $gfps = [math]::Min($fps, 15)
        $graph = "fps=$gfps,scale='trunc(min(320/iw,320/ih)*iw/2)*2':'trunc(min(320/iw,320/ih)*ih/2)*2':flags=neighbor," +
                 "split[a][b];[a]palettegen=max_colors=${colors}:stats_mode=full[p];[b][p]paletteuse=dither=bayer:bayer_scale=3"
        $steps += @{ Ext = ".gif"; Cmd = "-y -hide_banner -i `"{IN}`" -an -lavfi `"$graph`" -loop 0 `"{OUT}`"" }
    }
    return @{ Steps = $steps; Ext = $(if ($asGif) { ".gif" } else { ".mp4" }); Name = $videoNames[$level] }
}

function Build-Audio($limit) {
    $level = $audioSlider.Value
    # How much to squash the sound at each level: bitrate in kbps, and sample rate in Hz
    # (44100 Hz is CD quality, 8000 Hz is a phone call).
    $abit  = @(64, 48, 40, 32, 24, 16, 16, 8, 8, 8)[$level - 1]
    $arate = @(22050, 22050, 16000, 16000, 11025, 11025, 8000, 8000, 8000, 8000)[$level - 1]
    $tIn   = if ($limit) { "-t $limit " } else { "" }

    # ---- SOUND filters, applied in this order ----
    #   aresample=44100            first, convert everything to the same sample rate
    #   asetrate=x0.85 / x1.25     slowed (lower + slower) / nightcore (higher + faster)
    #   highpass + lowpass         cut the deep and the high sounds = tinny phone speaker
    #   aecho                      echo (bathroom, and the "reverb" in slowed + reverb)
    #   lowpass=450 (twice)        cut almost everything but the low rumble = underwater
    #   bass=g=18                  bass boost
    #   volume=8 + acrusher        too loud, then crushed to 8-bit = distortion
    $chain = @("aresample=44100")
    if ($aSlowed.Checked)   { $chain += "asetrate=$(Num (44100 * 0.85))", "aresample=44100" }
    if ($aNight.Checked)    { $chain += "asetrate=$(Num (44100 * 1.25))", "aresample=44100" }
    if ($aPhone.Checked)    { $chain += "highpass=f=300", "lowpass=f=3400" }
    if ($aBathroom.Checked) { $chain += "highpass=f=300", "lowpass=f=3400", "aecho=0.8:0.9:40|75|110:0.5|0.35|0.2" }
    if ($aWater.Checked)    { $chain += "lowpass=f=450", "lowpass=f=450" }
    if ($aBass.Checked)     { $chain += "bass=g=18:f=100:w=0.6" }
    if ($aSlowed.Checked)   { $chain += "aecho=0.8:0.85:60|120|240:0.45|0.35|0.25" }   # the "reverb" part
    if ($aDistort.Checked)  { $chain += "volume=8", "acrusher=bits=8:mix=1" }

    # VINYL CRACKLE and RADIO STATIC are made from scratch and mixed in:
    #   anoisesrc   generates hiss (pink noise for vinyl, white noise for static)
    #   aevalsrc    generates random clicks/pops: "if a random number is tiny, make a pop"
    #   amix        mixes everything together. amix turns each input down (it divides by the
    #               number of inputs), so everything is turned up by the same amount first.
    # Background noise layers (mixed in; amix divides by the number of inputs, so pre-boost everything)
    $extras = @()
    if ($aVinyl.Checked)  { $extras += "vinyl" }
    if ($aStatic.Checked) { $extras += "static" }
    $n = 1 + $extras.Count
    if ($extras.Count -eq 0) {
        $graph = "[0:a:0]$($chain -join ',')[out]"
    } else {
        if ($aStatic.Checked) { $chain += "highpass=f=400", "lowpass=f=2800" }   # radio sound
        $chain += "volume=$n"
        $graph = "[0:a:0]$($chain -join ',')[m]"
        $labels = "[m]"
        if ($aVinyl.Checked) {
            $graph += ";anoisesrc=c=pink:a=$(Num (0.015 * $n)):r=44100[h]"
            $graph += ";aevalsrc='if(lt(random(0)\,0.0004)\,(random(1)*1.2-0.6)*$n\,0)':s=44100[c]"
            $labels += "[h][c]"
        }
        if ($aStatic.Checked) {
            $graph += ";anoisesrc=c=white:a=$(Num (0.06 * $n)):r=44100[s]"
            $labels += "[s]"
        }
        $mixCount = ([regex]::Matches($labels, '\[')).Count
        $graph += ";$labels" + "amix=inputs=${inputs}:duration=first[out]"
    }
    $cmd = "-y -hide_banner $tIn-i `"{SRC}`" -filter_complex `"$graph`" -map `"[out]`" " +
           "-c:a libmp3lame -b:a ${abit}k -ar $arate -ac 1 `"{OUT}`""
    return @{ Steps = @(@{ Ext = ".mp3"; Cmd = $cmd }); Ext = ".mp3"; Name = $audioNames[$level] }
}

# Saves a caption into a small text file (in capitals, meme style) for ffmpeg to read.
# Reading from a file avoids problems with quotes and symbols in what you typed.
function Write-CaptionFile($text, $name) {
    $path = Join-Path $Work $name
    [System.IO.File]::WriteAllText($path, $text.ToUpper(), (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

# GIF recipe. Same idea as video: shrink, drop frames, blow back up - but the main crunch
# is the number of COLOURS. A GIF can have up to 256 colours; level 10 uses just 4.
function Build-Gif($limit) {
    $level  = $gifSlider.Value
    $t      = ($level - 1) / 9.0
    $width  = [int]([math]::Round((320 - $t * 270) / 2) * 2)   # 320px -> 50px internal resolution
    $fps    = [int][math]::Round(15 - $t * 11)                 # 15 fps -> 4 fps
    $colors = @(128, 64, 48, 32, 24, 16, 12, 8, 6, 4)[$level - 1]
    if ($gShort.Checked -and (-not $limit -or $limit -gt 10)) { $limit = 10 }
    $tIn = if ($limit) { "-t $limit " } else { "" }

    $f = @()
    if ($gFry.Checked) { $f += "hue=s=2.5", "curves=preset=strong_contrast", "unsharp=5:5:2.0", "noise=alls=20:allf=t" }
    $f += "scale=${width}:-2:flags=area", "fps=$fps", "scale=320:-2:flags=neighbor"

    # drawtext writes text on the picture: white, black outline, centred, Impact font.
    # Long captions get a smaller font so they fit across the GIF.
    # Meme captions (drawn after the crunch so they stay readable)
    $font = Join-Path $env:WINDIR "Fonts\impact.ttf"
    if (-not (Test-Path $font)) { $font = Join-Path $env:WINDIR "Fonts\arialbd.ttf" }
    $caps = @(@{ Text = $gTop.Text.Trim(); Y = "h*0.04"; File = "top.txt" },
              @{ Text = $gBottom.Text.Trim(); Y = "h-text_h-h*0.04"; File = "bottom.txt" })
    foreach ($c in $caps) {
        if (-not $c.Text) { continue }
        $tf = Write-CaptionFile $c.Text $c.File
        # shrink long captions so they fit across the 320px width
        $size = [int][math]::Max(10, [math]::Min(36, [math]::Floor(320 * 0.95 / ($c.Text.Length * 0.55))))
        $f += "drawtext=fontfile='$(FilterPath $font)':textfile='$(FilterPath $tf)':expansion=none:" +
              "fontcolor=white:borderw=2:bordercolor=black:fontsize=${size}:x=(w-text_w)/2:y=$($c.Y)"
    }
    $graph = $f -join ","
    # BOOMERANG: make a copy, play it backwards (reverse), and stick it on the end (concat).
    if ($gBoomerang.Checked) { $graph += ",split[fw][bk];[bk]reverse[rv];[fw][rv]concat=n=2:v=1:a=0" }
    # PALETTE: palettegen looks at the whole clip and picks the best few colours,
    # then paletteuse redraws every frame with only those colours.
    # "Dither" mixes dots of colour together to fake the missing ones (the grainy retro look).
    $dither = if ($gDither.Checked) { "bayer:bayer_scale=3" } else { "none" }
    $graph += ",split[a][b];[a]palettegen=max_colors=${colors}:stats_mode=full[p];[b][p]paletteuse=dither=$dither"

    $cmd = "-y -hide_banner $tIn-i `"{SRC}`" -an -lavfi `"$graph`" -loop 0 `"{OUT}`""
    return @{ Steps = @(@{ Ext = ".gif"; Cmd = $cmd }); Ext = ".gif"; Name = $gifNames[$level] }
}

# Picks the right recipe for whichever mode is showing.
function Build-Current($limit) {
    if ($script:Sel -eq $audioTab) { return Build-Audio $limit }
    if ($script:Sel -eq $gifTab)   { return Build-Gif $limit }
    return Build-Video $limit
}

# (Used by Random seeking and Auto YTP. Asking ffmpeg to open a file without saving
#  anything makes it print details like "Duration: 00:01:23.45" and "1280x720", which
#  are read out of its text here.)
# Ask ffmpeg for a file's length and whether it has sound
function Get-MediaInfo($ffmpeg, $file) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ffmpeg
    $psi.Arguments = "-hide_banner -i `"$file`""
    $psi.UseShellExecute = $false; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $err = $p.StandardError.ReadToEnd(); $p.WaitForExit()
    $dur = 0.0
    if ($err -match 'Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)') {
        $dur = [int]$Matches[1] * 3600 + [int]$Matches[2] * 60 + [double]::Parse($Matches[3], $Inv)
    }
    # The picture size, e.g. 1280x720. Phone videos filmed sideways are marked as "rotated",
    # so in that case width and height are swapped.
    $w = 640; $h = 360
    if ($err -match 'Video:.*?\b(\d{2,5})x(\d{2,5})\b') { $w = [int]$Matches[1]; $h = [int]$Matches[2] }
    if ($err -match 'rotation of (-?\d+)' -and [math]::Abs([int]$Matches[1]) % 180 -eq 90) { $t = $w; $w = $h; $h = $t }  # sideways phone video
    return @{ Duration = $dur; HasAudio = ($err -match 'Stream #.*Audio:'); Width = $w; Height = $h }
}

# (Each jump is opened as its own separate "input" with -ss (start time) and -t (length),
#  then the concat filter joins them all into one video.)
# Random seeking: play a short bit, jump back or forward a few seconds (sometimes anywhere),
# repeat until the result is as long as the original. Each jump is its own input, joined with concat.
function Build-SeekCommand($ffmpeg, $src, $out, $limit) {
    $info = Get-MediaInfo $ffmpeg $src
    $dur = $info.Duration
    if ($dur -lt 1) { $script:LastError = "Couldn't read the video's length for random seeking."; return $null }
    $target = if ($limit) { [math]::Min($limit, $dur) } else { $dur }
    $rnd = New-Object System.Random
    $pos = 0.0; $total = 0.0; $ins = ""; $fc = ""; $n = 0
    while ($total -lt $target -and $n -lt 150 -and $ins.Length -lt 24000) {
        $len = [math]::Min(0.25 + $rnd.NextDouble() * 1.25, [math]::Max(0.1, $dur - 0.05))
        $pos = [math]::Max(0, [math]::Min($pos, $dur - $len))
        $ins += "-ss $(Num ([math]::Round($pos, 3))) -t $(Num ([math]::Round($len, 3))) -i `"$src`" "
        $fc += $(if ($info.HasAudio) { "[${n}:v:0][${n}:a:0]" } else { "[${n}:v:0]" })
        $total += $len; $n++
        if ($rnd.NextDouble() -lt 0.25) { $pos = $rnd.NextDouble() * $dur }        # big random jump
        else { $pos = $pos + $len + (-3 + $rnd.NextDouble() * 7) }               # skip back or forward a bit
    }
    if ($info.HasAudio) {
        return "-y -hide_banner $ins-filter_complex `"${fc}concat=n=${n}:v=1:a=1[v][a]`" -map `"[v]`" -map `"[a]`" " +
               "-c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -c:a aac -b:a 192k `"$out`""
    }
    return "-y -hide_banner $ins-filter_complex `"${fc}concat=n=${n}:v=1:a=0[v]`" -map `"[v]`" " +
           "-c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p `"$out`""
}

# (Same trick as random seeking - many short pieces joined with concat - but each piece
#  can get its own effect. Every piece is resized to exactly the same size and frame rate,
#  because concat can only join pieces that match.)
#
# The list of YTP effects. V = what happens to the picture, A = what happens to the sound.
#   reverse/areverse    play backwards
#   setpts=PTS/1.6      1.6x faster        setpts=PTS/0.6   slower
#   negate              inverted colours   hflip            mirrored
#   hue=H=2*PI*t*2      colours spin round the rainbow
#   crop=iw/2:ih/2      zoom into the middle
#   vibrato             wobbly voice       aecho            echo
#   asetrate + atempo   higher/lower pitch at normal speed
# Auto YTP: mostly plays forward in short stretches, but keeps throwing in random
# YouTube Poop edits - stutters, reverses, speed / pitch changes, colour effects, zooms, loud bursts.
$YtpFx = @(
    @{ V = "reverse";                     A = "areverse" },
    @{ V = "setpts=PTS/1.6";              A = "asetrate=70560,aresample=44100" },               # chipmunk fast
    @{ V = "setpts=PTS/0.6";              A = "asetrate=26460,aresample=44100" },               # slow-mo deep voice
    @{ V = "negate";                      A = "" },                                             # inverted colours
    @{ V = "hflip";                       A = "" },                                             # mirrored
    @{ V = "hue=H=2*PI*t*2:s=3";          A = "" },                                             # rainbow
    @{ V = "crop=iw/2:ih/2";              A = "" },                                             # zoom in
    @{ V = "hue=s=3,curves=preset=strong_contrast";  A = "volume=12,acrusher=bits=6:mix=1" },              # LOUD burst
    @{ V = "";                            A = "vibrato=f=8:d=1" },                              # wobbly voice
    @{ V = "";                            A = "aecho=0.8:0.9:120|240:0.6|0.4" },                # echo
    @{ V = "";                            A = "asetrate=66150,aresample=44100,atempo=0.6667" }, # pitch up
    @{ V = "";                            A = "asetrate=29106,aresample=44100,atempo=1.5" }     # pitch down
)
function Build-YtpCommand($ffmpeg, $src, $out, $limit) {
    $info = Get-MediaInfo $ffmpeg $src
    $dur = $info.Duration
    if ($dur -lt 1) { $script:LastError = "Couldn't read the video's length for Auto YTP."; return $null }
    $target = if ($limit) { [math]::Min($limit, $dur) } else { $dur }
    $tw = [int]([math]::Floor([math]::Min($info.Width, 854) / 2) * 2)
    $th = [int]([math]::Round($info.Height * $tw / $info.Width / 2) * 2)
    $audio = $info.HasAudio
    $rnd = New-Object System.Random
    $script:ytpIns = ""; $script:ytpFc = @(); $script:ytpLabels = ""; $script:ytpN = 0

    # Adds one piece: start time, length, picture effect, sound effect.
    function Add-Seg($start, $len, $v, $a) {
        $i = $script:ytpN
        $script:ytpIns += "-ss $(Num ([math]::Round($start, 3))) -t $(Num ([math]::Round($len, 3))) -i `"$src`" "
        $vc = if ($v) { "$v," } else { "" }
        $script:ytpFc += "[${i}:v:0]${vc}scale=${tw}:${th},setsar=1,fps=30,format=yuv420p[v$i]"
        if ($audio) {
            $ac = if ($a) { "$a," } else { "" }
            $script:ytpFc += "[${i}:a:0]aresample=44100,${ac}aformat=sample_rates=44100:channel_layouts=stereo[a$i]"
            $script:ytpLabels += "[v$i][a$i]"
        } else { $script:ytpLabels += "[v$i]" }
        $script:ytpN++
    }
    # Keeps a start time inside the video (so we never try to read past the end).
    function Clamp($p, $l) { return [math]::Max(0, [math]::Min($p, $dur - $l)) }

    $pos = 0.0; $total = 0.0
    while ($total -lt $target -and $script:ytpN -lt 140 -and $script:ytpIns.Length -lt 20000) {
        # Roll the dice each time: 45% normal bit, 17% stutter, 38% effect.
        $r = $rnd.NextDouble()
        if ($r -lt 0.45) {
            # a normal bit, carrying on forward
            $len = [math]::Min(0.6 + $rnd.NextDouble() * 1.4, $dur - 0.05); $pos = Clamp $pos $len
            Add-Seg $pos $len "" ""; $pos += $len; $total += $len
        } elseif ($r -lt 0.62) {
            # stutter: the same tiny bit over and over (sometimes flashing inverted)
            $len = 0.07 + $rnd.NextDouble() * 0.15; $pos = Clamp $pos $len
            $reps = $rnd.Next(3, 9)
            for ($k = 0; $k -lt $reps; $k++) {
                $v = if ($k % 2 -eq 1 -and $rnd.NextDouble() -lt 0.4) { "negate" } else { "" }
                Add-Seg $pos $len $v ""
            }
            $total += $len * $reps
        } else {
            # an effect (sometimes two at once)
            $len = [math]::Min(0.3 + $rnd.NextDouble() * 0.9, $dur - 0.05); $pos = Clamp $pos $len
            $picks = @($YtpFx | Get-Random -Count $(if ($rnd.NextDouble() -lt 0.25) { 2 } else { 1 }))
            $v = (@($picks | ForEach-Object { $_.V }) | Where-Object { $_ }) -join ","
            $a = (@($picks | ForEach-Object { $_.A }) | Where-Object { $_ }) -join ","
            Add-Seg $pos $len $v $a; $total += $len
            if ($rnd.NextDouble() -lt 0.2) { $pos = $rnd.NextDouble() * $dur }          # jump somewhere random
            elseif ($rnd.NextDouble() -lt 0.7) { $pos += $len }                        # carry on
            else { $pos -= 0.5 + $rnd.NextDouble() * 1.5 }                             # rewind a bit
        }
    }
    $n = $script:ytpN
    $graph = ($script:ytpFc -join ";") + ";" + $script:ytpLabels
    if ($audio) {
        return "-y -hide_banner $($script:ytpIns)-filter_complex `"${graph}concat=n=${n}:v=1:a=1[v][a]`" -map `"[v]`" -map `"[a]`" " +
               "-c:v libx264 -preset veryfast -crf 18 -c:a aac -b:a 192k `"$out`""
    }
    return "-y -hide_banner $($script:ytpIns)-filter_complex `"${graph}concat=n=${n}:v=1:a=0[v]`" -map `"[v]`" " +
           "-c:v libx264 -preset veryfast -crf 18 `"$out`""
}

# =====================================================================================
#  7. RUNNING FFMPEG
# =====================================================================================
# Run one ffmpeg command, keeping the window responsive. Returns $true if it worked.
function Invoke-FFmpeg($ffmpeg, $ffArgs, $out) {
    $errLog = Join-Path $env:TEMP "videocruncher-log.txt"
    # Start ffmpeg hidden, sending its messages to a log file (shown if something fails).
    $p = Start-Process -FilePath $ffmpeg -ArgumentList $ffArgs -NoNewWindow -PassThru -RedirectStandardError $errLog
    $null = $p.Handle   # PowerShell quirk: without this, ExitCode can come back empty
    $script:CurrentProc = $p
    $script:CurrentOut = $out
    # Wait for it to finish, but keep the window alive (DoEvents) so it doesn't freeze.
    while (-not $p.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
    }
    $p.WaitForExit()
    $script:CurrentProc = $null
    $exitCode = $p.ExitCode
    # It worked if ffmpeg says so (exit code 0) and the output file exists and isn't empty.
    $made = (Test-Path -LiteralPath $out) -and ((Get-Item -LiteralPath $out).Length -gt 0)
    if ($made -and ($exitCode -eq 0 -or $null -eq $exitCode)) { return $true }
    $script:LastError = (Get-Content $errLog -Tail 8 -ErrorAction SilentlyContinue) -join "`n"
    return $false
}

# Steps are chained: step 1 reads your file, step 2 reads step 1's result, and so on.
# In-between results go in the scratch folder; only the last step saves the real file.
# Run all the steps of a job from $src to $out. Returns $true if it worked.
function Invoke-Job($ffmpeg, $job, $src, $out, $label) {
    $steps = $job.Steps
    $prev = $src
    for ($i = 0; $i -lt $steps.Count; $i++) {
        $last = ($i -eq $steps.Count - 1)
        $stepOut = if ($last) { $out } else { Join-Path $Work "step$i$($steps[$i].Ext)" }
        $status.Text = if ($steps.Count -gt 1) { "$label (step $($i + 1) of $($steps.Count))" } else { $label }
        if ($steps[$i].Seek -or $steps[$i].Ytp) {
            $cmd = if ($steps[$i].Ytp) { Build-YtpCommand $ffmpeg $src $stepOut $steps[$i].Limit }
                   else { Build-SeekCommand $ffmpeg $src $stepOut $steps[$i].Limit }
            if (-not $cmd) { return $false }
        } else {
            $cmd = $steps[$i].Cmd.Replace("{SRC}", $src).Replace("{IN}", $prev).Replace("{OUT}", $stepOut)
        }
        if (-not (Invoke-FFmpeg $ffmpeg $cmd $stepOut)) { return $false }
        if ($steps[$i].Seek -or $steps[$i].Ytp) { $src = $stepOut }   # the rest of the steps work on the jumbled version
        if ($i -gt 0 -and $prev -ne $src) { Remove-Item -LiteralPath $prev -Force -ErrorAction SilentlyContinue }
        $prev = $stepOut
    }
    return $true
}

# Find ffmpeg, or offer to download it if it can't be found.
function Get-FFmpegOrInstall {
    $ffmpeg = Find-FFmpeg
    if (-not $ffmpeg) { $ffmpeg = Install-FFmpeg }
    return $ffmpeg
}

# (Returns the file to read, plus where to save the result. For GIF links, the result
#  goes in your Downloads folder because there's no original file to save next to.)
# Work out the input for the current tab (downloading a GIF link if needed)
function Get-CurrentInput {
    $isAudio = ($script:Sel -eq $audioTab)
    $isGif   = ($script:Sel -eq $gifTab)
    $box = if ($isAudio) { $audioBox } elseif ($isGif) { $gifBox } else { $videoBox }
    $in = $box.Text.Trim('"', ' ')
    if ($isGif -and $in -match '^https?://') {
        $file = Get-WebGif $in
        if (-not $file) { return $null }
        return @{ Src = $file; SavePath = (Get-LinkSavePath $in); FromLink = $true }
    }
    if (-not $in -or -not (Test-Path -LiteralPath $in)) {
        $what = if ($isAudio) { "an audio file" } elseif ($isGif) { "a video or GIF" } else { "a video" }
        [System.Windows.Forms.MessageBox]::Show("Pick $what first.", "Video Cruncher") | Out-Null
        return $null
    }
    return @{ Src = $in; SavePath = $in; FromLink = $false }
}

# Show ffmpeg's last few error lines in a popup.
function Show-Failure {
    $status.Text = "Something went wrong."
    # A cut-down ffmpeg that's missing a feature: offer to get the full version instead
    if ($script:LastError -match "No such filter|Filter not found|Unknown encoder|Encoder not found|not compiled|Unrecognized option") {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "The ffmpeg on your PC is a cut-down version that's missing a feature this needs:`n`n$script:LastError`n`n" +
            "Download the full ffmpeg for Video Cruncher now? (free, ~100 MB, saved next to this app - your other ffmpeg isn't touched)",
            "Video Cruncher", "YesNo", "Warning")
        if ($answer -eq "Yes" -and (Install-FFmpeg $true)) {
            [System.Windows.Forms.MessageBox]::Show("Done! Hit CRUNCH IT again.", "Video Cruncher") | Out-Null
        }
        return
    }
    [System.Windows.Forms.MessageBox]::Show("ffmpeg failed:`n`n$script:LastError", "Video Cruncher", "OK", "Error") | Out-Null
}

# =====================================================================================
#  8. BUTTONS - what happens when you click them
# =====================================================================================
# CRUNCH IT: crunch the whole file, then offer to play it.
$go.Add_Click({
    $ffmpeg = Get-FFmpegOrInstall; if (-not $ffmpeg) { return }
    Reset-Work
    $inp = Get-CurrentInput; if (-not $inp) { return }
    $job = Build-Current $null
    $out = Get-OutputPath $inp.SavePath $job.Ext
    Set-Busy $true
    try {
        if (Invoke-Job $ffmpeg $job $inp.Src $out "Crunching... ($($job.Name))") {
            $before = (Get-Item -LiteralPath $inp.Src).Length
            $after  = (Get-Item -LiteralPath $out).Length
            $status.Text = "Done! {0:N1} MB -> {1:N2} MB  ({2})" -f ($before / 1MB), ($after / 1MB), (Split-Path -Leaf $out)
            Set-Busy $false
            $open = [System.Windows.Forms.MessageBox]::Show(
                "Crunched!`n`nSaved as:`n$out`n`nPlay it now?", "Video Cruncher", "YesNo", "Information")
            if ($open -eq "Yes") { Invoke-Item -LiteralPath $out }
        } else { Set-Busy $false; Show-Failure }
    } finally {
        Set-Busy $false
        Remove-Item $Work, (Join-Path $env:TEMP "videocruncher-dl") -Recurse -Force -ErrorAction SilentlyContinue
    }
})

# PREVIEW: same recipe, but only the first 3 seconds, saved to a temporary folder,
# then played straight away.
$previewB.Add_Click({
    $ffmpeg = Get-FFmpegOrInstall; if (-not $ffmpeg) { return }
    Reset-Work
    $inp = Get-CurrentInput; if (-not $inp) { return }
    $job = Build-Current 3
    # Previews go in their own temp folder with a new name each time (the old one may still be open in a player)
    $pdir = Join-Path $env:TEMP "videocruncher-preview"
    New-Item -ItemType Directory -Path $pdir -Force | Out-Null
    Get-ChildItem $pdir -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $out = Join-Path $pdir ("preview_" + (Get-Date -Format "HHmmss") + $job.Ext)
    Set-Busy $true
    try {
        if (Invoke-Job $ffmpeg $job $inp.Src $out "Making a 3 second preview... ($($job.Name))") {
            $status.Text = "Preview ready - hit CRUNCH IT when you like it."
            Invoke-Item -LiteralPath $out
        } else { Set-Busy $false; Show-Failure }
    } finally { Set-Busy $false }
})

# CRUNCH A FOLDER: run the current recipe on every matching file in a folder,
# saving the results in a "crunched" folder inside it.
$batchB.Add_Click({
    $ffmpeg = Get-FFmpegOrInstall; if (-not $ffmpeg) { return }
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Pick a folder - every matching file in it gets crunched with the current settings"
    if ($dlg.ShowDialog() -ne "OK") { return }
    $folder = $dlg.SelectedPath

    $exts = if ($script:Sel -eq $audioTab) { $AudioExts }
            elseif ($script:Sel -eq $gifTab) { @(".gif") + $VideoExts }
            else { $VideoExts }
    $files = @(Get-ChildItem -LiteralPath $folder -File | Where-Object { $exts -contains $_.Extension.ToLower() })
    if ($files.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No matching files in that folder.`n`nLooking for: $($exts -join ' ')",
            "Video Cruncher") | Out-Null
        return
    }
    $outDir = Join-Path $folder "crunched"
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null

    $ok = 0; $failed = @()
    Set-Busy $true
    try {
        for ($i = 0; $i -lt $files.Count; $i++) {
            $f = $files[$i]
            Reset-Work
            $job = Build-Current $null
            $out = Get-OutputPath (Join-Path $outDir $f.Name) $job.Ext
            if (Invoke-Job $ffmpeg $job $f.FullName $out "Batch: file $($i + 1) of $($files.Count) - $($f.Name)") { $ok++ }
            else { $failed += $f.Name }
        }
    } finally { Set-Busy $false; Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue }

    $status.Text = "Batch done: $ok of $($files.Count) crunched."
    $msg = "Crunched $ok of $($files.Count) files.`n`nSaved in:`n$outDir"
    if ($failed.Count) { $msg += "`n`nThese didn't work:`n" + (($failed | Select-Object -First 10) -join "`n") }
    $open = [System.Windows.Forms.MessageBox]::Show("$msg`n`nOpen the folder?", "Video Cruncher", "YesNo", "Information")
    if ($open -eq "Yes") { Invoke-Item -LiteralPath $outDir }
})

# RANDOM!: shuffle the settings of the mode that's showing.
# Roll 0.4 means "a 40% chance of yes".
$rng = New-Object System.Random
function Roll($chance) { return ($rng.NextDouble() -lt $chance) }
$randomB.Add_Click({
    if ($script:Sel -eq $videoTab) {
        $videoSlider.Value = $rng.Next(4, 11)
        $fry.Checked = Roll 0.4; $vPixel.Checked = Roll 0.15; $vGlitch.Checked = Roll 0.3
        $earrape.Checked = Roll 0.3; $vBass.Checked = Roll 0.4; $vPitch.Checked = Roll 0.7
        $vSpeed.SelectedIndex   = if (Roll 0.5) { 0 } else { $rng.Next(1, $SpeedItems.Count) }
        $vStretch.SelectedIndex = if (Roll 0.6) { 0 } else { $rng.Next(1, $StretchItems.Count) }
        $vSeek.Checked = Roll 0.25; $vYtp.Checked = Roll 0.2
        $vReup.SelectedIndex    = if (Roll 0.7) { 0 } else { $rng.Next(1, 3) }   # keep random re-uploads quick
    } elseif ($script:Sel -eq $audioTab) {
        $audioSlider.Value = $rng.Next(4, 11)
        foreach ($c in @($aDistort, $aBass, $aPhone, $aWater, $aBathroom, $aVinyl, $aStatic)) { $c.Checked = Roll 0.3 }
        $aSlowed.Checked = $false; $aNight.Checked = $false
        $r = $rng.NextDouble()
        if ($r -lt 0.3) { $aSlowed.Checked = $true } elseif ($r -lt 0.6) { $aNight.Checked = $true }
    } else {
        $gifSlider.Value = $rng.Next(4, 11)
        $gFry.Checked = Roll 0.4; $gDither.Checked = Roll 0.6; $gBoomerang.Checked = Roll 0.4
    }
    $status.Text = "Randomised! Try Preview to see what you got."
})

# -------------------------------------------------------------------------------------
# Closing the window always works, even mid-download or mid-crunch:
# stop whatever is running, tidy up, and exit.
$script:CurrentJob = $null
$script:CurrentProc = $null
$script:CurrentOut = $null
$form.Add_FormClosing({
    $busy = $false
    if ($script:CurrentJob) {
        $busy = $true
        Stop-Job $script:CurrentJob -ErrorAction SilentlyContinue
        Remove-Job $script:CurrentJob -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $env:TEMP "videocruncher-dl") -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($script:CurrentProc -and -not $script:CurrentProc.HasExited) {
        $busy = $true
        try { $script:CurrentProc.Kill(); $script:CurrentProc.WaitForExit(3000) } catch {}
        if ($script:CurrentOut) { Remove-Item -LiteralPath $script:CurrentOut -Force -ErrorAction SilentlyContinue }
    }
    Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue
    if ($busy) { [Environment]::Exit(0) }
})

# Finally: show the window. The script waits here until the window is closed.
[void]$form.ShowDialog()
