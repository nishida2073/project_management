Add-Type -AssemblyName System.Windows.Forms
if (-not ("E" -as [type])) {
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class E {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hgt, bool repaint);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static IntPtr Found = IntPtr.Zero;
  public static bool Cb(IntPtr h, IntPtr l) { StringBuilder sb = new StringBuilder(256); GetWindowText(h, sb, 256); if (sb.ToString().StartsWith("Android Emulator")) { Found = h; } return true; }
}
"@
}
Start-Sleep -Seconds 5
$proc = [E+EnumProc]{ param($h, $l) [E]::Cb($h, $l) }
[void][E]::EnumWindows($proc, [IntPtr]::Zero)
$h = [E]::Found
if ($h -eq [IntPtr]::Zero) { Write-Host "emulator window not found"; exit 1 }
$r = New-Object E+RECT
[void][E]::GetWindowRect($h, [ref]$r)
$w = $r.R - $r.L
$ht = $r.B - $r.T
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$x = [int](($wa.Width - $w) / 2)
$y = [int](($wa.Height - $ht) / 2)
if ($y -lt 0) { $y = 0 }
[void][E]::MoveWindow($h, $x, $y, $w, $ht, $true)
Write-Host "moved to $x,$y"
