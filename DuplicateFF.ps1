# DuplicateFF v1.1.0 - Professional Duplicate File Finder
# PowerShell WPF | Catppuccin Mocha | Progressive Hashing Pipeline
# MIT License - github.com/SysAdminDoc/DuplicateFF

# --- CLI Parameters ---
param(
    [string[]]$Scan,
    [string[]]$Reference,
    [ValidateSet('All','Images','Videos','Audio','Documents')]
    [string]$Filter = 'All',
    [ValidateSet('KeepNewest','KeepOldest','KeepReference','KeepLargest','KeepShortestPath')]
    [string]$AutoSelect,
    [ValidateSet('RecycleBin','Permanent','Hardlink')]
    [string]$Delete,
    [switch]$Json,
    [switch]$DryRun,
    [switch]$Silent,
    [string]$ReportPath,
    [string]$MinSize = 'No Minimum',
    [string]$MaxSize = 'No Maximum',
    [string[]]$Exclude,
    [string]$IncludePattern,
    [string]$ExcludePattern,
    [datetime]$MinDate,
    [datetime]$MaxDate,
    [switch]$NoSubfolders,
    [switch]$IncludeZeroByte
)

$script:CLIMode = $Scan.Count -gt 0

$script:DefaultExcludePatterns = @(
    '$RECYCLE.BIN', 'System Volume Information', '.git', '.svn', '.hg',
    'node_modules', '__pycache__', '.vs', '.idea', 'bin', 'obj'
)

if (-not $script:CLIMode) {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, Microsoft.VisualBasic
    Add-Type -AssemblyName System.Drawing
} else {
    Add-Type -AssemblyName Microsoft.VisualBasic
}

# --- P/Invoke ---
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct BY_HANDLE_FILE_INFORMATION {
    public uint FileAttributes;
    public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
    public uint VolumeSerialNumber;
    public uint FileSizeHigh;
    public uint FileSizeLow;
    public uint NumberOfLinks;
    public uint FileIndexHigh;
    public uint FileIndexLow;
}

public class Win32 {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern bool CreateHardLink(string lpFileName, string lpExistingFileName, IntPtr lpSecurityAttributes);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetFileInformationByHandle(IntPtr hFile, out BY_HANDLE_FILE_INFORMATION lpFileInformation);
}
"@
if (-not $script:CLIMode) {
    [Win32]::ShowWindow([Win32]::GetConsoleWindow(), 0) | Out-Null
}

# --- Shared Helper Functions (used by both GUI and CLI) ---
function Format-FileSize([long]$bytes) {
    if ($bytes -lt 1KB) { return "$bytes B" }
    if ($bytes -lt 1MB) { return "{0:N1} KB" -f ($bytes / 1KB) }
    if ($bytes -lt 1GB) { return "{0:N1} MB" -f ($bytes / 1MB) }
    return "{0:N2} GB" -f ($bytes / 1GB)
}

function Get-MinSizeBytes([string]$label) {
    switch ($label) {
        "1 KB"    { return 1KB }
        "10 KB"   { return 10KB }
        "100 KB"  { return 100KB }
        "1 MB"    { return 1MB }
        "10 MB"   { return 10MB }
        "100 MB"  { return 100MB }
        default   { return 0 }
    }
}

function Get-MaxSizeBytes([string]$label) {
    switch ($label) {
        "10 MB"   { return 10MB }
        "100 MB"  { return 100MB }
        "500 MB"  { return 500MB }
        "1 GB"    { return 1GB }
        "5 GB"    { return 5GB }
        "10 GB"   { return 10GB }
        default   { return [long]::MaxValue }
    }
}

function Get-PartialHash([string]$path, [long]$offset, [long]$count) {
    try {
        $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        try {
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $buf = [byte[]]::new([Math]::Min($count, $fs.Length - $offset))
                $fs.Position = $offset
                $read = $fs.Read($buf, 0, $buf.Length)
                if ($read -gt 0) {
                    return [BitConverter]::ToString($sha.ComputeHash($buf, 0, $read)).Replace('-','')
                }
            } finally { $sha.Dispose() }
        } finally { $fs.Dispose() }
    } catch { return $null }
    return $null
}

function Get-FileHashValue([string]$path) {
    try {
        $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        try {
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $bufSize = 262144
                $buf = [byte[]]::new($bufSize)
                while ($true) {
                    $read = $fs.Read($buf, 0, $bufSize)
                    if ($read -eq 0) { break }
                    if ($fs.Position -eq $fs.Length) {
                        $sha.TransformFinalBlock($buf, 0, $read) | Out-Null
                    } else {
                        $sha.TransformBlock($buf, 0, $read, $buf, 0) | Out-Null
                    }
                }
                if ($fs.Length -eq 0) { $sha.TransformFinalBlock([byte[]]::new(0), 0, 0) | Out-Null }
                return [BitConverter]::ToString($sha.Hash).Replace('-','')
            } finally { $sha.Dispose() }
        } finally { $fs.Dispose() }
    } catch { return $null }
}

function Test-ByteIdentical([string]$pathA, [string]$pathB) {
    try {
        $fsA = [System.IO.File]::Open($pathA, 'Open', 'Read', 'ReadWrite')
        try {
            $fsB = [System.IO.File]::Open($pathB, 'Open', 'Read', 'ReadWrite')
            try {
                if ($fsA.Length -ne $fsB.Length) { return $false }
                $bufSize = 65536
                $bufA = [byte[]]::new($bufSize)
                $bufB = [byte[]]::new($bufSize)
                while ($true) {
                    $readA = $fsA.Read($bufA, 0, $bufSize)
                    $readB = $fsB.Read($bufB, 0, $bufSize)
                    if ($readA -ne $readB) { return $false }
                    if ($readA -eq 0) { return $true }
                    for ($i = 0; $i -lt $readA; $i++) {
                        if ($bufA[$i] -ne $bufB[$i]) { return $false }
                    }
                }
            } finally { $fsB.Dispose() }
        } finally { $fsA.Dispose() }
    } catch { return $false }
}

function Remove-ToRecycleBin([string]$path) {
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
        $path,
        [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
        [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
    )
}

function Get-NtfsFileId([string]$path) {
    try {
        $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        try {
            $info = [BY_HANDLE_FILE_INFORMATION]::new()
            if ([Win32]::GetFileInformationByHandle($fs.SafeFileHandle.DangerousGetHandle(), [ref]$info)) {
                return "$($info.VolumeSerialNumber):$($info.FileIndexHigh):$($info.FileIndexLow)"
            }
        } finally { $fs.Dispose() }
    } catch { }
    return $null
}

function Get-VolumeRoot([string]$path) {
    [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($path))
}

function Test-FileLocked([string]$path) {
    try {
        $fs = [System.IO.File]::Open($path, 'Open', 'ReadWrite', 'None')
        $fs.Dispose()
        return $false
    } catch {
        return $true
    }
}

function Test-FileFilter([string]$ext, [string]$filter) {
    switch ($filter) {
        "Images Only"  { return $ext -in $script:ImageExts }
        "Videos Only"  { return $ext -in $script:VideoExts }
        "Audio Only"   { return $ext -in $script:AudioExts }
        "Documents"    { return $ext -in $script:DocExts }
        default        { return $true }
    }
}

$script:ImageExts = @('.jpg','.jpeg','.png','.gif','.bmp','.tiff','.tif','.webp','.ico','.svg','.heic','.heif','.avif')
$script:VideoExts = @('.mp4','.mkv','.avi','.mov','.wmv','.flv','.webm','.m4v','.mpg','.mpeg','.3gp','.ts')
$script:AudioExts = @('.mp3','.flac','.wav','.aac','.ogg','.wma','.m4a','.opus','.aiff','.alac')
$script:DocExts = @('.pdf','.doc','.docx','.xls','.xlsx','.ppt','.pptx','.txt','.rtf','.odt','.ods','.csv')

# ===================================================================
# GUI MODE
# ===================================================================
if (-not $script:CLIMode) {

# --- Catppuccin Mocha Palette ---
$script:Colors = @{
    Base     = "#1E1E2E"; Mantle   = "#181825"; Crust    = "#11111B"
    Surface0 = "#313244"; Surface1 = "#45475A"; Surface2 = "#585B70"
    Text     = "#CDD6F4"; Subtext1 = "#BAC2DE"; Subtext0 = "#A6ADC8"
    Overlay0 = "#6C7086"; Blue     = "#89B4FA"; Lavender = "#B4BEFE"
    Green    = "#A6E3A1"; Red      = "#F38BA8"; Peach    = "#FAB387"
    Yellow   = "#F9E2AF"; Mauve    = "#CBA6F7"; Teal     = "#94E2D5"
    Sky      = "#89DCEB"; Pink     = "#F5C2E7"
}

# --- XAML UI ---
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DuplicateFF v1.1.0" Width="1280" Height="820" MinWidth="900" MinHeight="650"
        WindowStartupLocation="CenterScreen" Background="$($Colors.Base)"
        AllowDrop="True">
    <Window.Resources>
        <Style x:Key="BtnStyle" TargetType="Button">
            <Setter Property="Background" Value="$($Colors.Surface0)"/>
            <Setter Property="Foreground" Value="$($Colors.Text)"/>
            <Setter Property="BorderBrush" Value="$($Colors.Surface1)"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="14,7"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="$($Colors.Surface1)"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="$($Colors.Surface2)"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="AccentBtn" TargetType="Button" BasedOn="{StaticResource BtnStyle}">
            <Setter Property="Background" Value="$($Colors.Blue)"/>
            <Setter Property="Foreground" Value="$($Colors.Crust)"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}"
                                BorderThickness="0" CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="$($Colors.Lavender)"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="$($Colors.Mauve)"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="DangerBtn" TargetType="Button" BasedOn="{StaticResource BtnStyle}">
            <Setter Property="Background" Value="$($Colors.Red)"/>
            <Setter Property="Foreground" Value="$($Colors.Crust)"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}"
                                BorderThickness="0" CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#E06C85"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="$($Colors.Text)"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="$($Colors.Text)"/>
        </Style>
        <Style x:Key="ComboStyle" TargetType="ComboBox">
            <Setter Property="Background" Value="$($Colors.Surface0)"/>
            <Setter Property="Foreground" Value="$($Colors.Text)"/>
            <Setter Property="BorderBrush" Value="$($Colors.Surface1)"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Height" Value="30"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton x:Name="ToggleButton" Focusable="False"
                                          IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"
                                          ClickMode="Press">
                                <ToggleButton.Template>
                                    <ControlTemplate TargetType="ToggleButton">
                                        <Border x:Name="Border" Background="$($Colors.Surface0)"
                                                BorderBrush="$($Colors.Surface1)" BorderThickness="1" CornerRadius="6">
                                            <Grid>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition/>
                                                    <ColumnDefinition Width="20"/>
                                                </Grid.ColumnDefinitions>
                                                <Path Grid.Column="1" Data="M0,0 L4,4 8,0" Stroke="$($Colors.Subtext0)"
                                                      StrokeThickness="1.5" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                            </Grid>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter TargetName="Border" Property="Background" Value="$($Colors.Surface1)"/>
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </ToggleButton.Template>
                            </ToggleButton>
                            <ContentPresenter x:Name="ContentSite" IsHitTestVisible="False"
                                              Content="{TemplateBinding SelectionBoxItem}"
                                              Margin="8,0,24,0" VerticalAlignment="Center" HorizontalAlignment="Left">
                                <ContentPresenter.Resources>
                                    <Style TargetType="TextBlock">
                                        <Setter Property="Foreground" Value="$($Colors.Text)"/>
                                    </Style>
                                </ContentPresenter.Resources>
                            </ContentPresenter>
                            <Popup x:Name="Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}"
                                   AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">
                                <Grid x:Name="DropDown" SnapsToDevicePixels="True"
                                      MinWidth="{TemplateBinding ActualWidth}" MaxHeight="200">
                                    <Border x:Name="DropDownBorder" Background="$($Colors.Surface0)"
                                            BorderBrush="$($Colors.Surface1)" BorderThickness="1" CornerRadius="6"
                                            Margin="0,2,0,0"/>
                                    <ScrollViewer Margin="4,6" SnapsToDevicePixels="True">
                                        <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained"/>
                                    </ScrollViewer>
                                </Grid>
                            </Popup>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ComboBoxItem">
            <Setter Property="Foreground" Value="$($Colors.Text)"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Padding" Value="8,4"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBoxItem">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}" CornerRadius="4">
                            <ContentPresenter/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="$($Colors.Surface1)"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ListBoxItem">
            <Setter Property="Foreground" Value="$($Colors.Text)"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Padding" Value="8,4"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ListBoxItem">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}" CornerRadius="4">
                            <ContentPresenter/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="$($Colors.Surface1)"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="$($Colors.Surface0)"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Top Bar -->
        <Border Grid.Row="0" Background="$($Colors.Mantle)" Padding="12,10">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Folder Controls -->
                <Grid Grid.Row="0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="Scan Folders" FontSize="13" FontWeight="SemiBold"
                               Foreground="$($Colors.Blue)" VerticalAlignment="Center" Margin="0,0,10,0"/>
                    <ListBox x:Name="lstFolders" Grid.Column="1" Height="60" Background="$($Colors.Surface0)"
                             BorderBrush="$($Colors.Surface1)" BorderThickness="1"
                             ScrollViewer.HorizontalScrollBarVisibility="Auto"/>
                    <Button x:Name="btnAddFolder" Grid.Column="2" Content="Add Folder" Style="{StaticResource BtnStyle}" Margin="8,0,0,0"
                            AutomationProperties.Name="Add scan folder"/>
                    <Button x:Name="btnAddRef" Grid.Column="3" Content="Add Reference" Style="{StaticResource BtnStyle}" Margin="4,0,0,0"
                            ToolTip="Reference folders are protected - duplicates will never be selected from these"
                            AutomationProperties.Name="Add reference folder"/>
                    <Button x:Name="btnRemoveFolder" Grid.Column="4" Content="Remove" Style="{StaticResource BtnStyle}" Margin="4,0,0,0"
                            AutomationProperties.Name="Remove selected folder"/>
                </Grid>

                <!-- Scan Options -->
                <Grid Grid.Row="1" Margin="0,8,0,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="Min Size:" VerticalAlignment="Center" Margin="0,0,6,0" FontSize="13"/>
                    <ComboBox x:Name="cmbMinSize" Grid.Column="1" Width="110" Style="{StaticResource ComboStyle}">
                        <ComboBoxItem Content="No Minimum" IsSelected="True"/>
                        <ComboBoxItem Content="1 KB"/>
                        <ComboBoxItem Content="10 KB"/>
                        <ComboBoxItem Content="100 KB"/>
                        <ComboBoxItem Content="1 MB"/>
                        <ComboBoxItem Content="10 MB"/>
                        <ComboBoxItem Content="100 MB"/>
                    </ComboBox>
                    <TextBlock Grid.Column="2" Text="Max:" VerticalAlignment="Center" Margin="10,0,6,0" FontSize="13"/>
                    <ComboBox x:Name="cmbMaxSize" Grid.Column="3" Width="110" Style="{StaticResource ComboStyle}">
                        <ComboBoxItem Content="No Maximum" IsSelected="True"/>
                        <ComboBoxItem Content="10 MB"/>
                        <ComboBoxItem Content="100 MB"/>
                        <ComboBoxItem Content="500 MB"/>
                        <ComboBoxItem Content="1 GB"/>
                        <ComboBoxItem Content="5 GB"/>
                        <ComboBoxItem Content="10 GB"/>
                    </ComboBox>
                    <TextBlock Grid.Column="4" Text="  Filter:" VerticalAlignment="Center" Margin="10,0,6,0" FontSize="13"/>
                    <ComboBox x:Name="cmbFilter" Grid.Column="5" Width="130" Style="{StaticResource ComboStyle}">
                        <ComboBoxItem Content="All Files" IsSelected="True"/>
                        <ComboBoxItem Content="Images Only"/>
                        <ComboBoxItem Content="Videos Only"/>
                        <ComboBoxItem Content="Audio Only"/>
                        <ComboBoxItem Content="Documents"/>
                    </ComboBox>
                    <CheckBox x:Name="chkSubfolders" Grid.Column="6" Content="Include Subfolders" IsChecked="True"
                              Margin="16,0,0,0" VerticalAlignment="Center" FontSize="13"/>
                    <CheckBox x:Name="chkZeroByte" Grid.Column="7" Content="Skip 0-byte" IsChecked="True"
                              Margin="16,0,0,0" VerticalAlignment="Center" FontSize="13"/>
                    <Button x:Name="btnScan" Grid.Column="9" Content="Scan for Duplicates" Style="{StaticResource AccentBtn}"
                            Padding="20,7" FontSize="14" AutomationProperties.Name="Scan for duplicate files"
                            IsDefault="True"/>
                    <Button x:Name="btnCancel" Grid.Column="10" Content="Cancel" Style="{StaticResource BtnStyle}"
                            Margin="6,0,0,0" IsEnabled="False" AutomationProperties.Name="Cancel scan"
                            IsCancel="True"/>
                </Grid>
            </Grid>
        </Border>

        <!-- Main Content -->
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*" MinWidth="400"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="300" MinWidth="200"/>
            </Grid.ColumnDefinitions>

            <!-- Results DataGrid -->
            <Border Grid.Column="0" Margin="8" Background="$($Colors.Mantle)" CornerRadius="8" Padding="1">
              <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Grid Grid.Row="0" Margin="8,6,8,4">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="Filter:" FontSize="12" Foreground="$($Colors.Subtext1)"
                               VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBox x:Name="txtFilter" Grid.Column="1" Background="$($Colors.Surface0)"
                             Foreground="$($Colors.Text)" BorderBrush="$($Colors.Surface1)"
                             Padding="6,4" FontSize="12" VerticalContentAlignment="Center"/>
                    <Button x:Name="btnClearFilter" Grid.Column="2" Content="Clear" Style="{StaticResource BtnStyle}"
                            Margin="4,0,0,0" Padding="8,4" FontSize="11"/>
                    <TextBlock x:Name="txtFilterCount" Grid.Column="3" FontSize="11"
                               Foreground="$($Colors.Overlay0)" VerticalAlignment="Center" Margin="8,0,0,0"/>
                </Grid>
                <DataGrid Grid.Row="1" x:Name="dgResults" AutoGenerateColumns="False" IsReadOnly="False"
                          Background="$($Colors.Mantle)" Foreground="$($Colors.Text)"
                          BorderThickness="0" GridLinesVisibility="Horizontal"
                          HorizontalGridLinesBrush="$($Colors.Surface0)"
                          RowBackground="$($Colors.Mantle)" AlternatingRowBackground="$($Colors.Base)"
                          HeadersVisibility="Column" CanUserSortColumns="True"
                          SelectionMode="Extended" SelectionUnit="FullRow"
                          CanUserResizeColumns="True" FontSize="12.5"
                          VirtualizingStackPanel.IsVirtualizing="True"
                          VirtualizingStackPanel.VirtualizationMode="Recycling"
                          EnableRowVirtualization="True"
                          EnableColumnVirtualization="True"
                          ScrollViewer.IsDeferredScrollingEnabled="True">
                    <DataGrid.ColumnHeaderStyle>
                        <Style TargetType="DataGridColumnHeader">
                            <Setter Property="Background" Value="$($Colors.Surface0)"/>
                            <Setter Property="Foreground" Value="$($Colors.Subtext1)"/>
                            <Setter Property="Padding" Value="10,6"/>
                            <Setter Property="FontWeight" Value="SemiBold"/>
                            <Setter Property="FontSize" Value="12"/>
                            <Setter Property="BorderBrush" Value="$($Colors.Surface1)"/>
                            <Setter Property="BorderThickness" Value="0,0,1,1"/>
                        </Style>
                    </DataGrid.ColumnHeaderStyle>
                    <DataGrid.CellStyle>
                        <Style TargetType="DataGridCell">
                            <Setter Property="BorderThickness" Value="0"/>
                            <Setter Property="Padding" Value="6,4"/>
                            <Setter Property="Template">
                                <Setter.Value>
                                    <ControlTemplate TargetType="DataGridCell">
                                        <Border Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
                                            <ContentPresenter VerticalAlignment="Center"/>
                                        </Border>
                                    </ControlTemplate>
                                </Setter.Value>
                            </Setter>
                            <Style.Triggers>
                                <Trigger Property="IsSelected" Value="True">
                                    <Setter Property="Background" Value="$($Colors.Surface1)"/>
                                    <Setter Property="Foreground" Value="$($Colors.Text)"/>
                                </Trigger>
                            </Style.Triggers>
                        </Style>
                    </DataGrid.CellStyle>
                    <DataGrid.RowStyle>
                        <Style TargetType="DataGridRow">
                            <Style.Triggers>
                                <Trigger Property="IsSelected" Value="True">
                                    <Setter Property="Background" Value="$($Colors.Surface1)"/>
                                </Trigger>
                            </Style.Triggers>
                        </Style>
                    </DataGrid.RowStyle>
                    <DataGrid.ContextMenu>
                        <ContextMenu Background="$($Colors.Surface0)" BorderBrush="$($Colors.Surface1)">
                            <MenuItem x:Name="ctxOpenFile" Header="Open File" Foreground="$($Colors.Text)"/>
                            <MenuItem x:Name="ctxOpenFolder" Header="Open Containing Folder" Foreground="$($Colors.Text)"/>
                            <Separator/>
                            <MenuItem x:Name="ctxCopyPath" Header="Copy Full Path" Foreground="$($Colors.Text)"/>
                            <MenuItem x:Name="ctxCopyHash" Header="Copy Hash" Foreground="$($Colors.Text)"/>
                            <Separator/>
                            <MenuItem x:Name="ctxSelectGroup" Header="Select Entire Group" Foreground="$($Colors.Text)"/>
                            <MenuItem x:Name="ctxDeselectGroup" Header="Deselect Entire Group" Foreground="$($Colors.Text)"/>
                            <Separator/>
                            <MenuItem x:Name="ctxSelectFolder" Header="Select All from This Folder" Foreground="$($Colors.Text)"/>
                        </ContextMenu>
                    </DataGrid.ContextMenu>
                    <DataGrid.Columns>
                        <DataGridCheckBoxColumn Binding="{Binding Selected, UpdateSourceTrigger=PropertyChanged}" Width="35"
                                                Header="" ElementStyle="{x:Null}"/>
                        <DataGridTextColumn Binding="{Binding Group}" Header="Group" Width="55"/>
                        <DataGridTextColumn Binding="{Binding GroupInfo}" Header="Group Info" Width="120"/>
                        <DataGridTextColumn Binding="{Binding FileName}" Header="File Name" Width="*" MinWidth="150"/>
                        <DataGridTextColumn Binding="{Binding SizeDisplay}" Header="Size" Width="85"/>
                        <DataGridTextColumn Binding="{Binding Modified}" Header="Modified" Width="130"/>
                        <DataGridTextColumn Binding="{Binding FolderPath}" Header="Folder" Width="250"/>
                        <DataGridTextColumn Binding="{Binding Status}" Header="Status" Width="75"/>
                    </DataGrid.Columns>
                </DataGrid>
              </Grid>
            </Border>

            <GridSplitter Grid.Column="1" Width="4" Background="$($Colors.Surface0)"
                          HorizontalAlignment="Center" VerticalAlignment="Stretch"/>

            <!-- Preview + Actions Panel -->
            <Grid Grid.Column="2">
                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Preview -->
                <Border Grid.Row="0" Margin="4,8,8,4" Background="$($Colors.Mantle)" CornerRadius="8" Padding="10">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <TextBlock Grid.Row="0" Text="Preview" FontSize="13" FontWeight="SemiBold"
                                   Foreground="$($Colors.Blue)" Margin="0,0,0,8"/>
                        <Border Grid.Row="1" Background="$($Colors.Surface0)" CornerRadius="6">
                            <Image x:Name="imgPreview" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality"/>
                        </Border>
                        <StackPanel Grid.Row="2" Margin="0,8,0,0">
                            <TextBlock x:Name="txtPreviewName" FontSize="12" TextTrimming="CharacterEllipsis"
                                       Foreground="$($Colors.Subtext1)"/>
                            <TextBlock x:Name="txtPreviewInfo" FontSize="11" Foreground="$($Colors.Overlay0)" Margin="0,2,0,0"/>
                        </StackPanel>
                    </Grid>
                </Border>

                <!-- Actions -->
                <Border Grid.Row="1" Margin="4,4,8,8" Background="$($Colors.Mantle)" CornerRadius="8" Padding="10">
                    <StackPanel>
                        <TextBlock Text="Actions" FontSize="13" FontWeight="SemiBold"
                                   Foreground="$($Colors.Blue)" Margin="0,0,0,8"/>

                        <TextBlock Text="Auto-Select:" FontSize="12" Foreground="$($Colors.Subtext1)" Margin="0,0,0,4"/>
                        <ComboBox x:Name="cmbAutoSelect" Style="{StaticResource ComboStyle}" Margin="0,0,0,6">
                            <ComboBoxItem Content="Keep Newest" IsSelected="True"/>
                            <ComboBoxItem Content="Keep Oldest"/>
                            <ComboBoxItem Content="Keep from Reference Folders"/>
                            <ComboBoxItem Content="Keep Largest"/>
                            <ComboBoxItem Content="Keep Shortest Path"/>
                        </ComboBox>
                        <Button x:Name="btnAutoSelect" Content="Apply Auto-Select" Style="{StaticResource BtnStyle}"
                                HorizontalAlignment="Stretch" Margin="0,0,0,4"/>
                        <Button x:Name="btnSelectAll" Content="Select All Duplicates" Style="{StaticResource BtnStyle}"
                                HorizontalAlignment="Stretch" Margin="0,0,0,4"/>
                        <Button x:Name="btnDeselectAll" Content="Deselect All" Style="{StaticResource BtnStyle}"
                                HorizontalAlignment="Stretch" Margin="0,0,0,4"/>
                        <Button x:Name="btnInvertSel" Content="Invert Selection" Style="{StaticResource BtnStyle}"
                                HorizontalAlignment="Stretch" Margin="0,0,0,10"/>

                        <TextBlock Text="Delete Mode:" FontSize="12" Foreground="$($Colors.Subtext1)" Margin="0,0,0,4"/>
                        <ComboBox x:Name="cmbDeleteMode" Style="{StaticResource ComboStyle}" Margin="0,0,0,6">
                            <ComboBoxItem Content="Move to Recycle Bin" IsSelected="True"/>
                            <ComboBoxItem Content="Permanent Delete"/>
                            <ComboBoxItem Content="Replace with Hardlinks"/>
                        </ComboBox>
                        <Button x:Name="btnRehearse" Content="Rehearse Delete (Preview)" Style="{StaticResource BtnStyle}"
                                HorizontalAlignment="Stretch" Margin="0,0,0,4"
                                ToolTip="Preview exactly what would be deleted without actually deleting anything"/>
                        <Button x:Name="btnDeleteSelected" Content="Delete Selected" Style="{StaticResource DangerBtn}"
                                HorizontalAlignment="Stretch" Margin="0,0,0,4"
                                AutomationProperties.Name="Delete selected duplicate files"/>
                        <Button x:Name="btnExport" Content="Export Results (CSV)" Style="{StaticResource BtnStyle}"
                                HorizontalAlignment="Stretch" Margin="0,0,0,0"/>
                    </StackPanel>
                </Border>
            </Grid>
        </Grid>

        <!-- Status Bar -->
        <Border Grid.Row="2" Background="$($Colors.Mantle)" Padding="12,6">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="txtStatus" Grid.Column="0" Text="Ready - Add folders to begin scanning"
                           FontSize="12" Foreground="$($Colors.Subtext0)" VerticalAlignment="Center"
                           AutomationProperties.LiveSetting="Polite"/>
                <TextBlock x:Name="txtStats" Grid.Column="1" Text="" FontSize="12"
                           Foreground="$($Colors.Overlay0)" VerticalAlignment="Center" Margin="0,0,16,0"/>
                <ProgressBar x:Name="prgScan" Grid.Column="2" Width="200" Height="14"
                             Background="$($Colors.Surface0)" Foreground="$($Colors.Blue)"
                             BorderThickness="0" Visibility="Collapsed"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

# --- Create Window ---
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# --- Get Controls ---
$controls = @{}
@('lstFolders','btnAddFolder','btnAddRef','btnRemoveFolder','cmbMinSize','cmbMaxSize','cmbFilter',
  'chkSubfolders','chkZeroByte','btnScan','btnCancel','dgResults','imgPreview',
  'txtPreviewName','txtPreviewInfo','cmbAutoSelect','btnAutoSelect','btnSelectAll',
  'btnDeselectAll','btnInvertSel','cmbDeleteMode','btnRehearse','btnDeleteSelected','btnExport',
  'txtStatus','txtStats','prgScan',
  'ctxOpenFile','ctxOpenFolder','ctxCopyPath','ctxCopyHash','ctxSelectGroup','ctxDeselectGroup','ctxSelectFolder',
  'txtFilter','btnClearFilter','txtFilterCount') | ForEach-Object {
    $controls[$_] = $window.FindName($_)
}

# --- State ---
$script:ScanFolders = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:Results = [System.Collections.ObjectModel.ObservableCollection[PSCustomObject]]::new()
$script:CancelSource = $null
$script:IsScanning = $false

$controls.dgResults.ItemsSource = $script:Results

# --- Add Folder ---
$controls.btnAddFolder.Add_Click({
    $dlg = [System.Windows.Forms.FolderBrowserDialog]@{
        Description = "Select folder to scan"
        ShowNewFolderButton = $false
    }
    if ($dlg.ShowDialog() -eq 'OK') {
        $existing = $script:ScanFolders | Where-Object { $_.Path -eq $dlg.SelectedPath }
        if (-not $existing) {
            $entry = [PSCustomObject]@{ Path = $dlg.SelectedPath; IsReference = $false }
            $script:ScanFolders.Add($entry)
            $controls.lstFolders.Items.Add($dlg.SelectedPath) | Out-Null
        }
    }
})

# --- Add Reference Folder ---
$controls.btnAddRef.Add_Click({
    $dlg = [System.Windows.Forms.FolderBrowserDialog]@{
        Description = "Select REFERENCE folder (protected from deletion)"
        ShowNewFolderButton = $false
    }
    if ($dlg.ShowDialog() -eq 'OK') {
        $existing = $script:ScanFolders | Where-Object { $_.Path -eq $dlg.SelectedPath }
        if (-not $existing) {
            $entry = [PSCustomObject]@{ Path = $dlg.SelectedPath; IsReference = $true }
            $script:ScanFolders.Add($entry)
            $controls.lstFolders.Items.Add("[REF] $($dlg.SelectedPath)") | Out-Null
        }
    }
})

# --- Remove Folder ---
$controls.btnRemoveFolder.Add_Click({
    $idx = $controls.lstFolders.SelectedIndex
    if ($idx -ge 0) {
        $script:ScanFolders.RemoveAt($idx)
        $controls.lstFolders.Items.RemoveAt($idx)
    }
})

# --- Drag-and-Drop Folders ---
$window.Add_Drop({
    param($sender, $e)
    if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $paths = $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
        foreach ($p in $paths) {
            if ([System.IO.Directory]::Exists($p)) {
                $existing = $script:ScanFolders | Where-Object { $_.Path -eq $p }
                if (-not $existing) {
                    $entry = [PSCustomObject]@{ Path = $p; IsReference = $false }
                    $script:ScanFolders.Add($entry)
                    $controls.lstFolders.Items.Add($p) | Out-Null
                }
            }
        }
        $controls.txtStatus.Text = "$($script:ScanFolders.Count) folders ready to scan"
    }
})
# --- Keyboard: Escape cancels scan ---
$window.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq 'Escape' -and $script:IsScanning -and $null -ne $script:CancelSource) {
        $script:CancelSource.Cancel()
        $controls.txtStatus.Text = "Cancelling..."
        $controls.btnCancel.IsEnabled = $false
        $e.Handled = $true
    }
})

$window.Add_DragOver({
    param($sender, $e)
    if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $e.Effects = [System.Windows.DragDropEffects]::Link
    } else {
        $e.Effects = [System.Windows.DragDropEffects]::None
    }
    $e.Handled = $true
})

# --- Preview on Selection ---
$controls.dgResults.Add_SelectionChanged({
    $item = $controls.dgResults.SelectedItem
    if ($null -eq $item) {
        $controls.imgPreview.Source = $null
        $controls.txtPreviewName.Text = ""
        $controls.txtPreviewInfo.Text = ""
        return
    }
    $controls.txtPreviewName.Text = $item.FileName
    $controls.txtPreviewInfo.Text = "$($item.SizeDisplay) | $($item.Modified)"

    $ext = [System.IO.Path]::GetExtension($item.FullPath).ToLowerInvariant()
    if ($ext -in $script:ImageExts -and $ext -notin @('.svg','.heic','.heif','.avif')) {
        try {
            $uri = [Uri]::new($item.FullPath)
            $bmp = [System.Windows.Media.Imaging.BitmapImage]::new()
            $bmp.BeginInit()
            $bmp.UriSource = $uri
            $bmp.CacheOption = 'OnLoad'
            $bmp.DecodePixelWidth = 400
            $bmp.EndInit()
            $bmp.Freeze()
            $controls.imgPreview.Source = $bmp
        } catch {
            $controls.imgPreview.Source = $null
        }
    } else {
        $controls.imgPreview.Source = $null
    }
})

# --- Open file on double-click ---
$controls.dgResults.Add_MouseDoubleClick({
    $item = $controls.dgResults.SelectedItem
    if ($null -ne $item -and [System.IO.File]::Exists($item.FullPath)) {
        Start-Process explorer.exe -ArgumentList "/select,`"$($item.FullPath)`""
    }
})

# --- Context Menu Handlers ---
$controls.ctxOpenFile.Add_Click({
    $item = $controls.dgResults.SelectedItem
    if ($null -ne $item -and [System.IO.File]::Exists($item.FullPath)) {
        Start-Process $item.FullPath
    }
})
$controls.ctxOpenFolder.Add_Click({
    $item = $controls.dgResults.SelectedItem
    if ($null -ne $item -and [System.IO.File]::Exists($item.FullPath)) {
        Start-Process explorer.exe -ArgumentList "/select,`"$($item.FullPath)`""
    }
})
$controls.ctxCopyPath.Add_Click({
    $item = $controls.dgResults.SelectedItem
    if ($null -ne $item) {
        [System.Windows.Clipboard]::SetText($item.FullPath)
        $controls.txtStatus.Text = "Copied path to clipboard"
    }
})
$controls.ctxCopyHash.Add_Click({
    $item = $controls.dgResults.SelectedItem
    if ($null -ne $item) {
        [System.Windows.Clipboard]::SetText($item.Hash)
        $controls.txtStatus.Text = "Copied hash to clipboard"
    }
})
$controls.ctxSelectGroup.Add_Click({
    $item = $controls.dgResults.SelectedItem
    if ($null -ne $item) {
        foreach ($r in $script:Results) {
            if ($r.Group -eq $item.Group -and -not $r.IsRef) { $r.Selected = $true }
        }
        $controls.dgResults.Items.Refresh()
        $selectedCount = ($script:Results | Where-Object { $_.Selected }).Count
        $controls.txtStatus.Text = "$selectedCount files selected"
    }
})
$controls.ctxDeselectGroup.Add_Click({
    $item = $controls.dgResults.SelectedItem
    if ($null -ne $item) {
        foreach ($r in $script:Results) {
            if ($r.Group -eq $item.Group) { $r.Selected = $false }
        }
        $controls.dgResults.Items.Refresh()
        $selectedCount = ($script:Results | Where-Object { $_.Selected }).Count
        $controls.txtStatus.Text = "$selectedCount files selected"
    }
})
$controls.ctxSelectFolder.Add_Click({
    $item = $controls.dgResults.SelectedItem
    if ($null -ne $item) {
        $folderPath = $item.FolderPath
        foreach ($r in $script:Results) {
            if ($r.FolderPath -eq $folderPath -and -not $r.IsRef) { $r.Selected = $true }
        }
        $controls.dgResults.Items.Refresh()
        $selectedCount = ($script:Results | Where-Object { $_.Selected }).Count
        $controls.txtStatus.Text = "$selectedCount files selected (from $folderPath)"
    }
})

# --- Filter Results ---
$script:AllResults = $null
$controls.txtFilter.Add_TextChanged({
    $filterText = $controls.txtFilter.Text.Trim()
    if ($script:Results.Count -eq 0) { return }
    if (-not $script:AllResults) {
        $script:AllResults = [System.Collections.Generic.List[PSCustomObject]]::new($script:Results)
    }
    $script:Results.Clear()
    foreach ($r in $script:AllResults) {
        if ([string]::IsNullOrEmpty($filterText) -or
            $r.FileName.IndexOf($filterText, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $r.FolderPath.IndexOf($filterText, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $script:Results.Add($r)
        }
    }
    $controls.txtFilterCount.Text = "$($script:Results.Count) / $($script:AllResults.Count)"
})
$controls.btnClearFilter.Add_Click({
    $controls.txtFilter.Text = ""
    if ($script:AllResults) {
        $script:Results.Clear()
        foreach ($r in $script:AllResults) { $script:Results.Add($r) }
        $controls.txtFilterCount.Text = ""
        $script:AllResults = $null
    }
})

# --- SCAN ---
$controls.btnScan.Add_Click({
    if ($script:ScanFolders.Count -eq 0) {
        $controls.txtStatus.Text = "Add at least one folder to scan"
        return
    }
    if ($script:IsScanning) { return }

    $script:IsScanning = $true
    $script:Results.Clear()
    $script:AllResults = $null
    $controls.txtFilter.Text = ""
    $controls.txtFilterCount.Text = ""
    $controls.btnScan.IsEnabled = $false
    $controls.btnCancel.IsEnabled = $true
    $controls.prgScan.Visibility = 'Visible'
    $controls.prgScan.IsIndeterminate = $true
    $controls.txtStatus.Text = "Scanning..."
    $controls.txtStats.Text = ""

    $script:CancelSource = [System.Threading.CancellationTokenSource]::new()
    $script:ScanStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $token = $script:CancelSource.Token

    $folders = $script:ScanFolders | ForEach-Object { [PSCustomObject]@{ Path = $_.Path; IsReference = $_.IsReference } }
    $recurse = $controls.chkSubfolders.IsChecked
    $skipZero = $controls.chkZeroByte.IsChecked
    $minSizeLabel = ($controls.cmbMinSize.SelectedItem).Content
    $maxSizeLabel = ($controls.cmbMaxSize.SelectedItem).Content
    $filterLabel = ($controls.cmbFilter.SelectedItem).Content

    # Shared sync hashtable for progress reporting
    $sync = [hashtable]::Synchronized(@{
        Status = "Enumerating files..."
        Phase = "enum"
        TotalFiles = 0
        ProcessedFiles = 0
        DuplicateGroups = 0
        DuplicateFiles = 0
        WastedSpace = 0L
        Results = [System.Collections.ArrayList]::new()
        Errors = [System.Collections.ArrayList]::new()
        HardlinkExcluded = 0
        Done = $false
        Error = $null
    })

    # Background worker
    $ps = [PowerShell]::Create()
    $ps.AddScript({
        param($folders, $recurse, $skipZero, $minSizeLabel, $maxSizeLabel, $filterLabel, $token, $sync,
              $imageExts, $videoExts, $audioExts, $docExts, $excludePatterns)

        function Get-MinSizeBytes([string]$label) {
            switch ($label) {
                "1 KB"    { return 1024 }
                "10 KB"   { return 10240 }
                "100 KB"  { return 102400 }
                "1 MB"    { return 1048576 }
                "10 MB"   { return 10485760 }
                "100 MB"  { return 104857600 }
                default   { return 0 }
            }
        }
        function Get-MaxSizeBytes([string]$label) {
            switch ($label) {
                "10 MB"   { return 10485760 }
                "100 MB"  { return 104857600 }
                "500 MB"  { return 524288000 }
                "1 GB"    { return 1073741824 }
                "5 GB"    { return 5368709120 }
                "10 GB"   { return 10737418240 }
                default   { return [long]::MaxValue }
            }
        }
        function Test-FileFilter([string]$ext, [string]$filter) {
            switch ($filter) {
                "Images Only"  { return $ext -in $imageExts }
                "Videos Only"  { return $ext -in $videoExts }
                "Audio Only"   { return $ext -in $audioExts }
                "Documents"    { return $ext -in $docExts }
                default        { return $true }
            }
        }
        function Format-FileSize([long]$bytes) {
            if ($bytes -lt 1024) { return "$bytes B" }
            if ($bytes -lt 1048576) { return "{0:N1} KB" -f ($bytes / 1024) }
            if ($bytes -lt 1073741824) { return "{0:N1} MB" -f ($bytes / 1048576) }
            return "{0:N2} GB" -f ($bytes / 1073741824)
        }
        function Get-PartialHash([string]$path, [long]$offset, [long]$count) {
            try {
                $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
                try {
                    $sha = [System.Security.Cryptography.SHA256]::Create()
                    try {
                        $len = [Math]::Min($count, $fs.Length - $offset)
                        if ($len -le 0) { return "" }
                        $buf = [byte[]]::new($len)
                        $fs.Position = $offset
                        $read = $fs.Read($buf, 0, $buf.Length)
                        if ($read -gt 0) {
                            return [BitConverter]::ToString($sha.ComputeHash($buf, 0, $read)).Replace('-','')
                        }
                    } finally { $sha.Dispose() }
                } finally { $fs.Dispose() }
            } catch { return $null }
            return $null
        }
        function Get-FileHashValue([string]$path) {
            try {
                $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
                try {
                    $sha = [System.Security.Cryptography.SHA256]::Create()
                    try {
                        $bufSize = 262144
                        $buf = [byte[]]::new($bufSize)
                        while ($true) {
                            $read = $fs.Read($buf, 0, $bufSize)
                            if ($read -eq 0) { break }
                            if ($fs.Position -eq $fs.Length) {
                                $sha.TransformFinalBlock($buf, 0, $read) | Out-Null
                            } else {
                                $sha.TransformBlock($buf, 0, $read, $buf, 0) | Out-Null
                            }
                        }
                        if ($fs.Length -eq 0) { $sha.TransformFinalBlock([byte[]]::new(0), 0, 0) | Out-Null }
                        return [BitConverter]::ToString($sha.Hash).Replace('-','')
                    } finally { $sha.Dispose() }
                } finally { $fs.Dispose() }
            } catch { return $null }
        }

        # Byte-compare fallback: streams both files and exits on first mismatch
        function Test-ByteIdentical([string]$pathA, [string]$pathB) {
            try {
                $fsA = [System.IO.File]::Open($pathA, 'Open', 'Read', 'ReadWrite')
                try {
                    $fsB = [System.IO.File]::Open($pathB, 'Open', 'Read', 'ReadWrite')
                    try {
                        if ($fsA.Length -ne $fsB.Length) { return $false }
                        $bufSize = 65536
                        $bufA = [byte[]]::new($bufSize)
                        $bufB = [byte[]]::new($bufSize)
                        while ($true) {
                            $readA = $fsA.Read($bufA, 0, $bufSize)
                            $readB = $fsB.Read($bufB, 0, $bufSize)
                            if ($readA -ne $readB) { return $false }
                            if ($readA -eq 0) { return $true }
                            for ($i = 0; $i -lt $readA; $i++) {
                                if ($bufA[$i] -ne $bufB[$i]) { return $false }
                            }
                        }
                    } finally { $fsB.Dispose() }
                } finally { $fsA.Dispose() }
            } catch { return $false }
        }

        function Get-NtfsFileId([string]$path) {
            try {
                $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
                try {
                    $info = [BY_HANDLE_FILE_INFORMATION]::new()
                    if ([Win32]::GetFileInformationByHandle($fs.SafeFileHandle.DangerousGetHandle(), [ref]$info)) {
                        return "$($info.VolumeSerialNumber):$($info.FileIndexHigh):$($info.FileIndexLow)"
                    }
                } finally { $fs.Dispose() }
            } catch { }
            return $null
        }

        try {
            $minSize = Get-MinSizeBytes $minSizeLabel
            $maxSize = Get-MaxSizeBytes $maxSizeLabel

            # Phase 1: Enumerate files
            $sync.Status = "Enumerating files..."
            $sync.Phase = "enum"
            $allFiles = [System.Collections.Generic.List[PSCustomObject]]::new()

            # Build reference path set
            $refPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($f in $folders) {
                if ($f.IsReference) { $refPaths.Add($f.Path) | Out-Null }
            }

            # Reference-folder integrity guard: abort if any reference folder is inaccessible
            foreach ($rp in $refPaths) {
                if (-not [System.IO.Directory]::Exists($rp)) {
                    $sync.Error = "Reference folder inaccessible: $rp"
                    $sync.Status = "Aborted - reference folder inaccessible: $rp"
                    $sync.Done = $true
                    return
                }
            }

            foreach ($folder in $folders) {
                if ($token.IsCancellationRequested) { return }
                try {
                    $enumOpts = [System.IO.EnumerationOptions]@{
                        RecurseSubdirectories = $recurse
                        IgnoreInaccessible = $true
                        AttributesToSkip = 'ReparsePoint'
                    }
                    $di = [System.IO.DirectoryInfo]::new($folder.Path)
                    foreach ($fi in $di.EnumerateFiles('*', $enumOpts)) {
                        if ($token.IsCancellationRequested) { return }
                        if ($skipZero -and $fi.Length -eq 0) { continue }
                        if ($fi.Length -lt $minSize) { continue }
                        if ($fi.Length -gt $maxSize) { continue }
                        $ext = $fi.Extension.ToLowerInvariant()
                        if (-not (Test-FileFilter $ext $filterLabel)) { continue }
                        $skipFile = $false
                        foreach ($ep in $excludePatterns) {
                            if ($fi.FullName.IndexOf("\$ep\", [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                                $skipFile = $true; break
                            }
                        }
                        if ($skipFile) { continue }

                        # Determine if this file is under a reference folder
                        $isRef = $false
                        foreach ($rp in $refPaths) {
                            if ($fi.FullName.StartsWith($rp, [System.StringComparison]::OrdinalIgnoreCase)) {
                                $isRef = $true; break
                            }
                        }
                        $allFiles.Add([PSCustomObject]@{
                            FullPath = $fi.FullName
                            FileName = $fi.Name
                            Size = $fi.Length
                            Modified = $fi.LastWriteTime
                            IsRef = $isRef
                        })
                        $sync.TotalFiles = $allFiles.Count
                        if ($allFiles.Count % 500 -eq 0) {
                            $sync.Status = "Enumerating... $($allFiles.Count) files found"
                        }
                    }
                } catch {
                    $sync.Errors.Add("Enumerate $($folder.Path): $($_.Exception.Message)") | Out-Null
                    continue
                }
            }

            if ($token.IsCancellationRequested) { return }

            # Phase 1b: Exclude existing NTFS hardlinks (same file ID = same data)
            $sync.Status = "Checking for hardlinks..."
            $fileIdMap = @{}
            $hardlinkExcluded = 0
            $dedupedFiles = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($f in $allFiles) {
                $fid = Get-NtfsFileId $f.FullPath
                if ($null -ne $fid) {
                    if ($fileIdMap.ContainsKey($fid)) {
                        $hardlinkExcluded++
                        continue
                    }
                    $fileIdMap[$fid] = $true
                }
                $dedupedFiles.Add($f)
            }
            if ($hardlinkExcluded -gt 0) {
                $sync.Status = "Excluded $hardlinkExcluded hardlinked files"
            }
            $allFiles = $dedupedFiles
            $fileIdMap = $null
            $sync.HardlinkExcluded = $hardlinkExcluded

            $sync.Status = "Grouping by size... ($($allFiles.Count) files)"
            $sync.Phase = "size"

            # Phase 2: Group by size (unique sizes cannot be duplicates)
            $sizeGroups = @{}
            foreach ($f in $allFiles) {
                if (-not $sizeGroups.ContainsKey($f.Size)) {
                    $sizeGroups[$f.Size] = [System.Collections.Generic.List[PSCustomObject]]::new()
                }
                $sizeGroups[$f.Size].Add($f)
            }
            # Remove unique sizes
            $candidates = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($kv in $sizeGroups.GetEnumerator()) {
                if ($kv.Value.Count -gt 1) {
                    foreach ($f in $kv.Value) { $candidates.Add($f) }
                }
            }
            $sizeGroups = $null

            $sync.Status = "$($candidates.Count) files in size-matched groups (eliminated $($allFiles.Count - $candidates.Count))"
            if ($candidates.Count -eq 0) { $sync.Done = $true; return }

            # Phase 3: Prefix hash (first 4KB)
            $sync.Phase = "prefix"
            $sync.ProcessedFiles = 0
            $sync.Status = "Prefix hashing ($($candidates.Count) candidates)..."
            $prefixGroups = @{}
            $processed = 0
            foreach ($f in $candidates) {
                if ($token.IsCancellationRequested) { return }
                $key = "$($f.Size)|$(Get-PartialHash $f.FullPath 0 4096)"
                if ($null -eq $key -or $key -match '\|$') { continue }
                if (-not $prefixGroups.ContainsKey($key)) {
                    $prefixGroups[$key] = [System.Collections.Generic.List[PSCustomObject]]::new()
                }
                $prefixGroups[$key].Add($f)
                $processed++
                $sync.ProcessedFiles = $processed
                if ($processed % 200 -eq 0) {
                    $sync.Status = "Prefix hashing... $processed / $($candidates.Count)"
                }
            }
            # Filter to groups with >1
            $prefixCandidates = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($kv in $prefixGroups.GetEnumerator()) {
                if ($kv.Value.Count -gt 1) {
                    foreach ($f in $kv.Value) { $prefixCandidates.Add($f) }
                }
            }
            $prefixGroups = $null

            $sync.Status = "$($prefixCandidates.Count) files after prefix hash (eliminated $($candidates.Count - $prefixCandidates.Count) more)"
            if ($prefixCandidates.Count -eq 0) { $sync.Done = $true; return }

            # Phase 4: Suffix hash (last 4KB)
            $sync.Phase = "suffix"
            $sync.ProcessedFiles = 0
            $suffixGroups = @{}
            $processed = 0
            foreach ($f in $prefixCandidates) {
                if ($token.IsCancellationRequested) { return }
                $suffixOffset = [Math]::Max(0, $f.Size - 4096)
                $key = "$($f.Size)|$(Get-PartialHash $f.FullPath $suffixOffset 4096)"
                if ($null -eq $key -or $key -match '\|$') { continue }
                if (-not $suffixGroups.ContainsKey($key)) {
                    $suffixGroups[$key] = [System.Collections.Generic.List[PSCustomObject]]::new()
                }
                $suffixGroups[$key].Add($f)
                $processed++
                $sync.ProcessedFiles = $processed
                if ($processed % 200 -eq 0) {
                    $sync.Status = "Suffix hashing... $processed / $($prefixCandidates.Count)"
                }
            }
            $suffixCandidates = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($kv in $suffixGroups.GetEnumerator()) {
                if ($kv.Value.Count -gt 1) {
                    foreach ($f in $kv.Value) { $suffixCandidates.Add($f) }
                }
            }
            $suffixGroups = $null

            $sync.Status = "$($suffixCandidates.Count) files after suffix hash"
            if ($suffixCandidates.Count -eq 0) { $sync.Done = $true; return }

            # Phase 5: Full hash (only remaining candidates)
            $sync.Phase = "full"
            $sync.ProcessedFiles = 0
            $fullGroups = @{}
            $processed = 0
            foreach ($f in $suffixCandidates) {
                if ($token.IsCancellationRequested) { return }
                $hash = Get-FileHashValue $f.FullPath
                if ($null -eq $hash) { continue }
                if (-not $fullGroups.ContainsKey($hash)) {
                    $fullGroups[$hash] = [System.Collections.Generic.List[PSCustomObject]]::new()
                }
                $fullGroups[$hash].Add($f)
                $processed++
                $sync.ProcessedFiles = $processed
                if ($processed % 50 -eq 0) {
                    $sync.Status = "Full hashing... $processed / $($suffixCandidates.Count)"
                }
            }

            # Reference-folder integrity guard: re-check mid-scan
            foreach ($rp in $refPaths) {
                if (-not [System.IO.Directory]::Exists($rp)) {
                    $sync.Error = "Reference folder became inaccessible mid-scan: $rp"
                    $sync.Status = "Aborted - reference folder inaccessible: $rp"
                    $sync.Done = $true
                    return
                }
            }

            # Phase 6: Byte-compare verification (handles hash collision paranoia)
            $sync.Phase = "verify"
            $sync.Status = "Verifying with byte comparison..."
            $verifiedGroups = @{}
            foreach ($kv in $fullGroups.GetEnumerator()) {
                if ($token.IsCancellationRequested) { return }
                if ($kv.Value.Count -lt 2) { continue }
                # For each hash group, verify all files are byte-identical to the first
                $anchor = $kv.Value[0]
                $verified = [System.Collections.Generic.List[PSCustomObject]]::new()
                $verified.Add($anchor)
                for ($vi = 1; $vi -lt $kv.Value.Count; $vi++) {
                    if ($token.IsCancellationRequested) { return }
                    $candidate = $kv.Value[$vi]
                    if (Test-ByteIdentical $anchor.FullPath $candidate.FullPath) {
                        $verified.Add($candidate)
                    }
                }
                if ($verified.Count -ge 2) {
                    $verifiedGroups[$kv.Key] = $verified
                }
            }

            # Build results
            $sync.Phase = "results"
            $groupNum = 0
            $dupFiles = 0
            $wastedBytes = 0L
            foreach ($kv in $verifiedGroups.GetEnumerator()) {
                $groupNum++
                $groupCount = $kv.Value.Count
                $groupReclaimable = ($groupCount - 1) * $kv.Value[0].Size
                $groupInfo = "$groupCount files, $(Format-FileSize $groupReclaimable) reclaimable"
                $first = $true
                foreach ($f in ($kv.Value | Sort-Object Modified -Descending)) {
                    $status = if ($f.IsRef) { "REF" } elseif ($first) { "Original" } else { "Duplicate" }
                    $sync.Results.Add([PSCustomObject]@{
                        Group     = $groupNum
                        GroupInfo = $groupInfo
                        FileName  = $f.FileName
                        FullPath  = $f.FullPath
                        FolderPath = [System.IO.Path]::GetDirectoryName($f.FullPath)
                        Size      = $f.Size
                        SizeDisplay = Format-FileSize $f.Size
                        Modified  = $f.Modified.ToString("yyyy-MM-dd HH:mm")
                        ModifiedDt = $f.Modified
                        IsRef     = $f.IsRef
                        Status    = $status
                        Selected  = $false
                        Hash      = $kv.Key
                    }) | Out-Null
                    if (-not $first) {
                        $dupFiles++
                        $wastedBytes += $f.Size
                    }
                    $first = $false
                }
            }
            $sync.DuplicateGroups = $groupNum
            $sync.DuplicateFiles = $dupFiles
            $sync.WastedSpace = $wastedBytes
            $sync.Status = "Complete - $groupNum duplicate groups found ($dupFiles duplicate files, $(Format-FileSize $wastedBytes) wasted)"

        } catch {
            $sync.Error = $_.Exception.Message
            $sync.Status = "Error: $($_.Exception.Message)"
        } finally {
            $sync.Done = $true
        }
    }).AddArgument($folders).AddArgument($recurse).AddArgument($skipZero).AddArgument($minSizeLabel
    ).AddArgument($maxSizeLabel).AddArgument($filterLabel).AddArgument($token).AddArgument($sync
    ).AddArgument($script:ImageExts).AddArgument($script:VideoExts).AddArgument($script:AudioExts).AddArgument($script:DocExts
    ).AddArgument($script:DefaultExcludePatterns)

    $handle = $ps.BeginInvoke()

    # Poll timer
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Tag = @{ PS = $ps; Handle = $handle; Sync = $sync }
    $timer.Add_Tick({
        $ctx = $this.Tag
        $s = $ctx.Sync

        $controls.txtStatus.Text = $s.Status
        if ($s.TotalFiles -gt 0) {
            $controls.txtStats.Text = "Files: $($s.TotalFiles)"
        }

        if ($s.Done) {
            $this.Stop()
            $ctx.PS.EndInvoke($ctx.Handle)
            $ctx.PS.Dispose()

            # Load results into observable collection
            foreach ($r in $s.Results) {
                $script:Results.Add($r)
            }

            $controls.prgScan.Visibility = 'Collapsed'
            $controls.prgScan.IsIndeterminate = $false
            $controls.btnScan.IsEnabled = $true
            $controls.btnCancel.IsEnabled = $false
            $script:IsScanning = $false

            $script:ScanStopwatch.Stop()
            $elapsed = $script:ScanStopwatch.Elapsed
            $elapsedStr = if ($elapsed.TotalMinutes -ge 1) { "{0}m {1:D2}s" -f [int]$elapsed.TotalMinutes, $elapsed.Seconds } else { "{0:N1}s" -f $elapsed.TotalSeconds }

            if ($s.Error) {
                $controls.txtStatus.Text = "Error: $($s.Error)"
            } else {
                $statsText = "$($s.DuplicateGroups) groups | $($s.DuplicateFiles) duplicates | $(Format-FileSize $s.WastedSpace) wasted | $elapsedStr"
                if ($s.HardlinkExcluded -gt 0) { $statsText += " | $($s.HardlinkExcluded) hardlinks excluded" }
                if ($s.Errors.Count -gt 0) { $statsText += " | $($s.Errors.Count) errors" }
                $controls.txtStats.Text = $statsText

                # Toast notification when window is not active
                if (-not $window.IsActive) {
                    try {
                        $notifyIcon = [System.Windows.Forms.NotifyIcon]::new()
                        $notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
                        $notifyIcon.Visible = $true
                        $toastMsg = "$($s.DuplicateGroups) duplicate groups found - $(Format-FileSize $s.WastedSpace) reclaimable"
                        $notifyIcon.ShowBalloonTip(5000, "DuplicateFF - Scan Complete", $toastMsg, 'Info')
                        # Clean up after a delay
                        $cleanTimer = [System.Windows.Threading.DispatcherTimer]::new()
                        $cleanTimer.Interval = [TimeSpan]::FromSeconds(6)
                        $cleanTimer.Tag = $notifyIcon
                        $cleanTimer.Add_Tick({
                            $this.Tag.Visible = $false
                            $this.Tag.Dispose()
                            $this.Stop()
                        })
                        $cleanTimer.Start()
                    } catch { }
                }
            }
        }
    })
    $timer.Start()
})

# --- Cancel ---
$controls.btnCancel.Add_Click({
    if ($null -ne $script:CancelSource) {
        $script:CancelSource.Cancel()
        $controls.txtStatus.Text = "Cancelling..."
        $controls.btnCancel.IsEnabled = $false
    }
})

# --- Auto-Select ---
$controls.btnAutoSelect.Add_Click({
    if ($script:Results.Count -eq 0) { return }
    $mode = ($controls.cmbAutoSelect.SelectedItem).Content

    # Group results
    $groups = @{}
    foreach ($r in $script:Results) {
        if (-not $groups.ContainsKey($r.Group)) {
            $groups[$r.Group] = [System.Collections.Generic.List[PSCustomObject]]::new()
        }
        $groups[$r.Group].Add($r)
    }

    foreach ($kv in $groups.GetEnumerator()) {
        $items = $kv.Value
        # First deselect all, then figure out which to keep
        foreach ($i in $items) { $i.Selected = $false }

        $keepIdx = 0
        switch ($mode) {
            "Keep Newest" {
                $sorted = $items | Sort-Object ModifiedDt -Descending
                $keepIdx = $script:Results.IndexOf($sorted[0])
            }
            "Keep Oldest" {
                $sorted = $items | Sort-Object ModifiedDt
                $keepIdx = $script:Results.IndexOf($sorted[0])
            }
            "Keep from Reference Folders" {
                $refItem = $items | Where-Object { $_.IsRef } | Select-Object -First 1
                if ($refItem) { $keepIdx = $script:Results.IndexOf($refItem) }
                else { $keepIdx = $script:Results.IndexOf($items[0]) }
            }
            "Keep Largest" {
                $sorted = $items | Sort-Object Size -Descending
                $keepIdx = $script:Results.IndexOf($sorted[0])
            }
            "Keep Shortest Path" {
                $sorted = $items | Sort-Object { $_.FullPath.Length }
                $keepIdx = $script:Results.IndexOf($sorted[0])
            }
        }

        # Select all except the keep target
        foreach ($i in $items) {
            if ($i.IsRef) { $i.Selected = $false; continue }
            if ($script:Results.IndexOf($i) -ne $keepIdx) {
                $i.Selected = $true
            }
        }
    }
    $controls.dgResults.Items.Refresh()
    $selectedCount = ($script:Results | Where-Object { $_.Selected }).Count
    $controls.txtStatus.Text = "$selectedCount files selected for deletion"
})

# --- Select All Duplicates ---
$controls.btnSelectAll.Add_Click({
    foreach ($r in $script:Results) {
        if ($r.Status -eq "Duplicate") { $r.Selected = $true }
    }
    $controls.dgResults.Items.Refresh()
    $selectedCount = ($script:Results | Where-Object { $_.Selected }).Count
    $controls.txtStatus.Text = "$selectedCount files selected"
})

# --- Deselect All ---
$controls.btnDeselectAll.Add_Click({
    foreach ($r in $script:Results) { $r.Selected = $false }
    $controls.dgResults.Items.Refresh()
    $controls.txtStatus.Text = "Selection cleared"
})

# --- Invert Selection ---
$controls.btnInvertSel.Add_Click({
    foreach ($r in $script:Results) {
        if (-not $r.IsRef) { $r.Selected = -not $r.Selected }
    }
    $controls.dgResults.Items.Refresh()
    $selectedCount = ($script:Results | Where-Object { $_.Selected }).Count
    $controls.txtStatus.Text = "$selectedCount files selected"
})

# --- Rehearse Delete (Dry Run Preview) ---
$controls.btnRehearse.Add_Click({
    $selected = @($script:Results | Where-Object { $_.Selected -and -not $_.IsRef })
    if ($selected.Count -eq 0) {
        $controls.txtStatus.Text = "No files selected - nothing to rehearse"
        return
    }

    $mode = ($controls.cmbDeleteMode.SelectedItem).Content
    $modeVerb = switch ($mode) {
        "Move to Recycle Bin"     { "Recycle" }
        "Permanent Delete"        { "DELETE" }
        "Replace with Hardlinks"  { "Hardlink" }
    }

    $totalSize = ($selected | Measure-Object -Property Size -Sum).Sum
    $sb = [System.Text.StringBuilder]::new()
    $sb.AppendLine("=== REHEARSAL (no files will be modified) ===") | Out-Null
    $sb.AppendLine("Mode: $mode") | Out-Null
    $sb.AppendLine("Files: $($selected.Count) | Space: $(Format-FileSize $totalSize)") | Out-Null
    $sb.AppendLine("") | Out-Null

    $locked = 0
    $crossVol = 0
    $missing = 0
    foreach ($item in $selected) {
        $issues = @()
        if (-not [System.IO.File]::Exists($item.FullPath)) {
            $issues += "MISSING"
            $missing++
        } else {
            if (Test-FileLocked $item.FullPath) {
                $issues += "LOCKED"
                $locked++
            }
            if ($mode -eq "Replace with Hardlinks") {
                $original = $script:Results | Where-Object { $_.Group -eq $item.Group -and -not $_.Selected -and $_.FullPath -ne $item.FullPath } | Select-Object -First 1
                if ($original) {
                    $srcVol = Get-VolumeRoot $item.FullPath
                    $dstVol = Get-VolumeRoot $original.FullPath
                    if ($srcVol -ne $dstVol) {
                        $issues += "CROSS-VOLUME"
                        $crossVol++
                    }
                }
            }
        }
        $tag = if ($issues.Count -gt 0) { " [" + ($issues -join ', ') + "]" } else { "" }
        $sb.AppendLine("  [$modeVerb] $($item.FullPath)$tag") | Out-Null
    }

    $sb.AppendLine("") | Out-Null
    $sb.AppendLine("--- Summary ---") | Out-Null
    $sb.AppendLine("Would process: $($selected.Count - $missing) files") | Out-Null
    if ($locked -gt 0) { $sb.AppendLine("Locked files (will be skipped): $locked") | Out-Null }
    if ($crossVol -gt 0) { $sb.AppendLine("Cross-volume hardlinks (impossible, will be skipped): $crossVol") | Out-Null }
    if ($missing -gt 0) { $sb.AppendLine("Missing files: $missing") | Out-Null }

    [System.Windows.MessageBox]::Show($sb.ToString(), "DuplicateFF - Rehearse Delete", 'OK', 'Information') | Out-Null
    $controls.txtStatus.Text = "Rehearsal complete - no files were modified"
})

# --- Delete Selected ---
$controls.btnDeleteSelected.Add_Click({
    $selected = @($script:Results | Where-Object { $_.Selected -and -not $_.IsRef })
    if ($selected.Count -eq 0) {
        $controls.txtStatus.Text = "No files selected for deletion"
        return
    }

    $mode = ($controls.cmbDeleteMode.SelectedItem).Content
    $modeDesc = switch ($mode) {
        "Move to Recycle Bin"     { "move to the Recycle Bin" }
        "Permanent Delete"        { "PERMANENTLY DELETE" }
        "Replace with Hardlinks"  { "replace with hardlinks to the original" }
    }

    $totalSize = ($selected | Measure-Object -Property Size -Sum).Sum
    $msg = "$($selected.Count) files ($(Format-FileSize $totalSize)) will be $modeDesc.`n`nContinue?"
    $result = [System.Windows.MessageBox]::Show($msg, "DuplicateFF - Confirm", 'YesNo', 'Warning')
    if ($result -ne 'Yes') { return }

    # Build operation list on UI thread (fast), execute I/O on background thread
    $ops = [System.Collections.ArrayList]::new()
    foreach ($item in $selected) {
        $op = @{ Path = $item.FullPath; Size = $item.Size; Hash = $item.Hash; Group = $item.Group; Mode = $mode; OriginalPath = $null }
        if ($mode -eq "Replace with Hardlinks") {
            $original = $script:Results | Where-Object { $_.Group -eq $item.Group -and -not $_.Selected -and $_.FullPath -ne $item.FullPath } | Select-Object -First 1
            if ($original) { $op.OriginalPath = $original.FullPath }
        }
        $ops.Add($op) | Out-Null
    }

    $controls.btnDeleteSelected.IsEnabled = $false
    $controls.prgScan.Visibility = 'Visible'
    $controls.prgScan.IsIndeterminate = $false
    $controls.prgScan.Maximum = $ops.Count
    $controls.prgScan.Value = 0
    $controls.txtStatus.Text = "Deleting 0/$($ops.Count)..."

    $delSync = [hashtable]::Synchronized(@{
        Deleted = 0; Errors = 0; SkippedLocked = 0; SkippedCrossVol = 0
        Processed = 0; Total = $ops.Count; TotalSize = $totalSize
        ActionLog = [System.Collections.ArrayList]::new()
        LogPath = $null; Done = $false
    })

    $delPs = [PowerShell]::Create()
    $delPs.AddScript({
        param($ops, $delSync)
        Add-Type -AssemblyName Microsoft.VisualBasic
        foreach ($op in $ops) {
            try {
                if (-not [System.IO.File]::Exists($op.Path)) { $delSync.Processed++; continue }
                try {
                    $lockTest = [System.IO.File]::Open($op.Path, 'Open', 'ReadWrite', 'None')
                    $lockTest.Dispose()
                } catch {
                    $delSync.SkippedLocked++
                    $delSync.ActionLog.Add(@{ Action = "Skipped"; Reason = "Locked"; Path = $op.Path }) | Out-Null
                    $delSync.Processed++
                    continue
                }
                switch ($op.Mode) {
                    "Move to Recycle Bin" {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($op.Path,
                            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
                        $delSync.ActionLog.Add(@{ Action = "RecycleBin"; Path = $op.Path; Size = $op.Size; Hash = $op.Hash }) | Out-Null
                    }
                    "Permanent Delete" {
                        [System.IO.File]::Delete($op.Path)
                        $delSync.ActionLog.Add(@{ Action = "Deleted"; Path = $op.Path; Size = $op.Size; Hash = $op.Hash }) | Out-Null
                    }
                    "Replace with Hardlinks" {
                        if ($op.OriginalPath -and [System.IO.File]::Exists($op.OriginalPath)) {
                            $srcVol = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($op.Path))
                            $dstVol = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($op.OriginalPath))
                            if ($srcVol -ne $dstVol) {
                                $delSync.SkippedCrossVol++
                                $delSync.ActionLog.Add(@{ Action = "Skipped"; Reason = "CrossVolume"; Path = $op.Path }) | Out-Null
                                $delSync.Processed++
                                continue
                            }
                            $tempLink = $op.Path + ".dff_hardlink_tmp"
                            $hlResult = [Win32]::CreateHardLink($tempLink, $op.OriginalPath, [IntPtr]::Zero)
                            if (-not $hlResult) {
                                $delSync.Errors++
                                $delSync.ActionLog.Add(@{ Action = "Failed"; Reason = "HardlinkFailed"; Path = $op.Path }) | Out-Null
                                $delSync.Processed++
                                continue
                            }
                            [System.IO.File]::Delete($op.Path)
                            [System.IO.File]::Move($tempLink, $op.Path)
                            $delSync.ActionLog.Add(@{ Action = "Hardlinked"; Path = $op.Path; Target = $op.OriginalPath; Size = $op.Size }) | Out-Null
                        } else {
                            [System.IO.File]::Delete($op.Path)
                            $delSync.ActionLog.Add(@{ Action = "Deleted"; Path = $op.Path; Size = $op.Size }) | Out-Null
                        }
                    }
                }
                $delSync.Deleted++
            } catch {
                $delSync.Errors++
                $delSync.ActionLog.Add(@{ Action = "Error"; Path = $op.Path; Error = $_.Exception.Message }) | Out-Null
            }
            $delSync.Processed++
        }
        if ($delSync.ActionLog.Count -gt 0) {
            try {
                $delSync.LogPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(),
                    "DuplicateFF_Actions_$(Get-Date -Format 'yyyyMMdd_HHmmss').json")
                $delSync.ActionLog | ConvertTo-Json -Depth 3 | Set-Content -Path $delSync.LogPath -Encoding UTF8
            } catch { }
        }
        $delSync.Done = $true
    }).AddArgument($ops).AddArgument($delSync)

    $delHandle = $delPs.BeginInvoke()

    $delTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $delTimer.Interval = [TimeSpan]::FromMilliseconds(100)
    $delTimer.Tag = @{ PS = $delPs; Handle = $delHandle; Sync = $delSync }
    $delTimer.Add_Tick({
        $ctx = $this.Tag
        $ds = $ctx.Sync
        $controls.prgScan.Value = $ds.Processed
        $controls.txtStatus.Text = "Deleting $($ds.Processed)/$($ds.Total)..."
        if ($ds.Done) {
            $this.Stop()
            $ctx.PS.EndInvoke($ctx.Handle)
            $ctx.PS.Dispose()

            $toRemove = @($script:Results | Where-Object { $_.Selected -and -not [System.IO.File]::Exists($_.FullPath) })
            foreach ($r in $toRemove) { $script:Results.Remove($r) | Out-Null }
            $groupCounts = @{}
            foreach ($r in $script:Results) {
                if (-not $groupCounts.ContainsKey($r.Group)) { $groupCounts[$r.Group] = 0 }
                $groupCounts[$r.Group]++
            }
            $singles = @($script:Results | Where-Object { $groupCounts[$_.Group] -lt 2 })
            foreach ($s in $singles) { $script:Results.Remove($s) | Out-Null }

            $controls.prgScan.Visibility = 'Collapsed'
            $controls.btnDeleteSelected.IsEnabled = $true
            $statusParts = @("$($ds.Deleted) files deleted")
            if ($ds.SkippedLocked -gt 0) { $statusParts += "$($ds.SkippedLocked) locked (skipped)" }
            if ($ds.SkippedCrossVol -gt 0) { $statusParts += "$($ds.SkippedCrossVol) cross-volume (skipped)" }
            if ($ds.Errors -gt 0) { $statusParts += "$($ds.Errors) errors" }
            $statusParts += "$(Format-FileSize $ds.TotalSize) reclaimed"
            if ($ds.LogPath) { $statusParts += "Log: $($ds.LogPath)" }
            $controls.txtStatus.Text = $statusParts -join ' | '
        }
    })
    $delTimer.Start()
})

# --- Export CSV ---
$controls.btnExport.Add_Click({
    if ($script:Results.Count -eq 0) {
        $controls.txtStatus.Text = "No results to export"
        return
    }
    $dlg = [System.Windows.Forms.SaveFileDialog]@{
        Filter = "CSV Files (*.csv)|*.csv"
        DefaultExt = ".csv"
        FileName = "DuplicateFF_Results_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    }
    if ($dlg.ShowDialog() -eq 'OK') {
        $sb = [System.Text.StringBuilder]::new()
        $sb.AppendLine('"Group","Selected","Status","FileName","Size","SizeBytes","Modified","FolderPath","FullPath","Hash"') | Out-Null
        foreach ($r in $script:Results) {
            $fn = $r.FileName -replace '"','""'
            $fp = $r.FolderPath -replace '"','""'
            $full = $r.FullPath -replace '"','""'
            $sd = $r.SizeDisplay -replace '"','""'
            $sb.AppendLine("`"$($r.Group)`",`"$($r.Selected)`",`"$($r.Status)`",`"$fn`",`"$sd`",`"$($r.Size)`",`"$($r.Modified)`",`"$fp`",`"$full`",`"$($r.Hash)`"") | Out-Null
        }
        $utf8Bom = [System.Text.UTF8Encoding]::new($true)
        [System.IO.File]::WriteAllText($dlg.FileName, $sb.ToString(), $utf8Bom)
        $controls.txtStatus.Text = "Exported $($script:Results.Count) results to $($dlg.FileName)"
    }
})

# --- Show Window ---
$window.ShowDialog() | Out-Null

} # end GUI MODE
# ===================================================================
# CLI MODE
# ===================================================================
else {

    # Map CLI filter param to internal label
    $filterLabel = switch ($Filter) {
        'Images'    { "Images Only" }
        'Videos'    { "Videos Only" }
        'Audio'     { "Audio Only" }
        'Documents' { "Documents" }
        default     { "All Files" }
    }

    $recurse = -not $NoSubfolders
    $skipZero = -not $IncludeZeroByte
    $minSizeBytes = Get-MinSizeBytes $MinSize
    $maxSizeBytes = Get-MaxSizeBytes $MaxSize
    $cliExcludePatterns = if ($Exclude) { $Exclude } else { $script:DefaultExcludePatterns }

    # Build folder list
    $refPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($Reference) {
        foreach ($rp in $Reference) {
            $resolved = (Resolve-Path $rp -ErrorAction SilentlyContinue).Path
            if ($resolved) { $refPaths.Add($resolved) | Out-Null }
            else {
                Write-Error "Reference folder not found: $rp"
                exit 3
            }
        }
    }

    $allScanPaths = @()
    foreach ($sp in $Scan) {
        $resolved = (Resolve-Path $sp -ErrorAction SilentlyContinue).Path
        if ($resolved) { $allScanPaths += $resolved }
        else { Write-Error "Scan folder not found: $sp"; exit 3 }
    }

    if ($Delete -and -not $AutoSelect) {
        Write-Error "The -Delete parameter requires -AutoSelect to determine which files to keep. Example: -AutoSelect KeepNewest -Delete RecycleBin"
        exit 1
    }

    if (-not $Silent) { Write-Host "DuplicateFF v1.1.0 - CLI Mode" }
    if (-not $Silent) { Write-Host "Scanning: $($allScanPaths -join ', ')" }
    if ($refPaths.Count -gt 0 -and -not $Silent) { Write-Host "Reference: $($refPaths -join ', ')" }

    $cliStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Phase 1: Enumerate
    if (-not $Silent) { Write-Host "Phase 1: Enumerating files..." }
    $allFiles = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($scanPath in $allScanPaths) {
        $enumOpts = [System.IO.EnumerationOptions]@{
            RecurseSubdirectories = $recurse
            IgnoreInaccessible = $true
            AttributesToSkip = 'ReparsePoint'
        }
        $di = [System.IO.DirectoryInfo]::new($scanPath)
        foreach ($fi in $di.EnumerateFiles('*', $enumOpts)) {
            if ($skipZero -and $fi.Length -eq 0) { continue }
            if ($fi.Length -lt $minSizeBytes) { continue }
            if ($fi.Length -gt $maxSizeBytes) { continue }
            $ext = $fi.Extension.ToLowerInvariant()
            if (-not (Test-FileFilter $ext $filterLabel)) { continue }
            $skipFile = $false
            foreach ($ep in $cliExcludePatterns) {
                if ($fi.FullName.IndexOf("\$ep\", [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $skipFile = $true; break
                }
            }
            if ($skipFile) { continue }
            if ($IncludePattern -and $fi.Name -notmatch $IncludePattern) { continue }
            if ($ExcludePattern -and $fi.Name -match $ExcludePattern) { continue }
            if ($MinDate -and $fi.LastWriteTime -lt $MinDate) { continue }
            if ($MaxDate -and $fi.LastWriteTime -gt $MaxDate) { continue }
            $isRef = $false
            foreach ($rp in $refPaths) {
                if ($fi.FullName.StartsWith($rp, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $isRef = $true; break
                }
            }
            $allFiles.Add([PSCustomObject]@{
                FullPath = $fi.FullName; FileName = $fi.Name
                Size = $fi.Length; Modified = $fi.LastWriteTime; IsRef = $isRef
            })
        }
    }
    # Also enumerate reference folders
    foreach ($rp in $refPaths) {
        if ($rp -notin $allScanPaths) {
            $enumOpts = [System.IO.EnumerationOptions]@{
                RecurseSubdirectories = $recurse
                IgnoreInaccessible = $true
                AttributesToSkip = 'ReparsePoint'
            }
            $di = [System.IO.DirectoryInfo]::new($rp)
            foreach ($fi in $di.EnumerateFiles('*', $enumOpts)) {
                if ($skipZero -and $fi.Length -eq 0) { continue }
                if ($fi.Length -lt $minSizeBytes) { continue }
                if ($fi.Length -gt $maxSizeBytes) { continue }
                $ext = $fi.Extension.ToLowerInvariant()
                if (-not (Test-FileFilter $ext $filterLabel)) { continue }
                $skipFile = $false
                foreach ($ep in $cliExcludePatterns) {
                    if ($fi.FullName.IndexOf("\$ep\", [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $skipFile = $true; break
                    }
                }
                if ($skipFile) { continue }
                if ($IncludePattern -and $fi.Name -notmatch $IncludePattern) { continue }
                if ($ExcludePattern -and $fi.Name -match $ExcludePattern) { continue }
                if ($MinDate -and $fi.LastWriteTime -lt $MinDate) { continue }
                if ($MaxDate -and $fi.LastWriteTime -gt $MaxDate) { continue }
                $allFiles.Add([PSCustomObject]@{
                    FullPath = $fi.FullName; FileName = $fi.Name
                    Size = $fi.Length; Modified = $fi.LastWriteTime; IsRef = $true
                })
            }
        }
    }
    if (-not $Silent) { Write-Host "  Found $($allFiles.Count) files" }

    # Phase 1b: Exclude existing NTFS hardlinks
    $fileIdMap = @{}
    $hardlinkExcluded = 0
    $dedupedFiles = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($f in $allFiles) {
        $fid = Get-NtfsFileId $f.FullPath
        if ($null -ne $fid) {
            if ($fileIdMap.ContainsKey($fid)) {
                $hardlinkExcluded++
                continue
            }
            $fileIdMap[$fid] = $true
        }
        $dedupedFiles.Add($f)
    }
    $allFiles = $dedupedFiles
    $fileIdMap = $null
    if ($hardlinkExcluded -gt 0 -and -not $Silent) {
        Write-Host "  Excluded $hardlinkExcluded hardlinked files"
    }

    # Phase 2: Size grouping
    if (-not $Silent) { Write-Host "Phase 2: Grouping by size..." }
    $sizeGroups = @{}
    foreach ($f in $allFiles) {
        if (-not $sizeGroups.ContainsKey($f.Size)) {
            $sizeGroups[$f.Size] = [System.Collections.Generic.List[PSCustomObject]]::new()
        }
        $sizeGroups[$f.Size].Add($f)
    }
    $candidates = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($kv in $sizeGroups.GetEnumerator()) {
        if ($kv.Value.Count -gt 1) { foreach ($f in $kv.Value) { $candidates.Add($f) } }
    }
    if (-not $Silent) { Write-Host "  $($candidates.Count) candidates ($($allFiles.Count - $candidates.Count) eliminated)" }
    if ($candidates.Count -eq 0) {
        if (-not $Silent) { Write-Host "No duplicates found." }
        if ($Json) { Write-Output "[]" }
        exit 0
    }

    # Phase 3: Prefix hash
    if (-not $Silent) { Write-Host "Phase 3: Prefix hashing..." }
    $prefixGroups = @{}
    foreach ($f in $candidates) {
        $key = "$($f.Size)|$(Get-PartialHash $f.FullPath 0 4096)"
        if ($null -eq $key -or $key -match '\|$') { continue }
        if (-not $prefixGroups.ContainsKey($key)) {
            $prefixGroups[$key] = [System.Collections.Generic.List[PSCustomObject]]::new()
        }
        $prefixGroups[$key].Add($f)
    }
    $prefixCandidates = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($kv in $prefixGroups.GetEnumerator()) {
        if ($kv.Value.Count -gt 1) { foreach ($f in $kv.Value) { $prefixCandidates.Add($f) } }
    }
    if (-not $Silent) { Write-Host "  $($prefixCandidates.Count) candidates remain" }
    if ($prefixCandidates.Count -eq 0) {
        if (-not $Silent) { Write-Host "No duplicates found." }
        if ($Json) { Write-Output "[]" }
        exit 0
    }

    # Phase 4: Suffix hash
    if (-not $Silent) { Write-Host "Phase 4: Suffix hashing..." }
    $suffixGroups = @{}
    foreach ($f in $prefixCandidates) {
        $suffixOffset = [Math]::Max(0, $f.Size - 4096)
        $key = "$($f.Size)|$(Get-PartialHash $f.FullPath $suffixOffset 4096)"
        if ($null -eq $key -or $key -match '\|$') { continue }
        if (-not $suffixGroups.ContainsKey($key)) {
            $suffixGroups[$key] = [System.Collections.Generic.List[PSCustomObject]]::new()
        }
        $suffixGroups[$key].Add($f)
    }
    $suffixCandidates = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($kv in $suffixGroups.GetEnumerator()) {
        if ($kv.Value.Count -gt 1) { foreach ($f in $kv.Value) { $suffixCandidates.Add($f) } }
    }
    if (-not $Silent) { Write-Host "  $($suffixCandidates.Count) candidates remain" }
    if ($suffixCandidates.Count -eq 0) {
        if (-not $Silent) { Write-Host "No duplicates found." }
        if ($Json) { Write-Output "[]" }
        exit 0
    }

    # Phase 5: Full hash
    if (-not $Silent) { Write-Host "Phase 5: Full hashing..." }
    $fullGroups = @{}
    foreach ($f in $suffixCandidates) {
        $hash = Get-FileHashValue $f.FullPath
        if ($null -eq $hash) { continue }
        if (-not $fullGroups.ContainsKey($hash)) {
            $fullGroups[$hash] = [System.Collections.Generic.List[PSCustomObject]]::new()
        }
        $fullGroups[$hash].Add($f)
    }

    # Phase 6: Byte-compare verification
    if (-not $Silent) { Write-Host "Phase 6: Byte verification..." }
    $verifiedGroups = @{}
    foreach ($kv in $fullGroups.GetEnumerator()) {
        if ($kv.Value.Count -lt 2) { continue }
        $anchor = $kv.Value[0]
        $verified = [System.Collections.Generic.List[PSCustomObject]]::new()
        $verified.Add($anchor)
        for ($vi = 1; $vi -lt $kv.Value.Count; $vi++) {
            if (Test-ByteIdentical $anchor.FullPath $kv.Value[$vi].FullPath) {
                $verified.Add($kv.Value[$vi])
            }
        }
        if ($verified.Count -ge 2) { $verifiedGroups[$kv.Key] = $verified }
    }

    # Build results
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $groupNum = 0
    $dupFiles = 0
    $wastedBytes = 0L
    foreach ($kv in $verifiedGroups.GetEnumerator()) {
        $groupNum++
        $groupCount = $kv.Value.Count
        $groupReclaimable = ($groupCount - 1) * $kv.Value[0].Size
        $groupInfo = "$groupCount files, $(Format-FileSize $groupReclaimable) reclaimable"
        $first = $true
        foreach ($f in ($kv.Value | Sort-Object Modified -Descending)) {
            $status = if ($f.IsRef) { "REF" } elseif ($first) { "Original" } else { "Duplicate" }
            $results.Add([PSCustomObject]@{
                Group      = $groupNum
                GroupInfo  = $groupInfo
                FileName   = $f.FileName
                FullPath   = $f.FullPath
                FolderPath = [System.IO.Path]::GetDirectoryName($f.FullPath)
                Size       = $f.Size
                SizeDisplay = Format-FileSize $f.Size
                Modified   = $f.Modified.ToString("yyyy-MM-dd HH:mm")
                ModifiedDt = $f.Modified
                IsRef      = $f.IsRef
                Status     = $status
                Selected   = $false
                Hash       = $kv.Key
            })
            if (-not $first) { $dupFiles++; $wastedBytes += $f.Size }
            $first = $false
        }
    }

    $cliStopwatch.Stop()
    $cliElapsed = $cliStopwatch.Elapsed
    $cliElapsedStr = if ($cliElapsed.TotalMinutes -ge 1) { "{0}m {1:D2}s" -f [int]$cliElapsed.TotalMinutes, $cliElapsed.Seconds } else { "{0:N1}s" -f $cliElapsed.TotalSeconds }
    if (-not $Silent) {
        Write-Host "Found $groupNum duplicate groups ($dupFiles duplicate files, $(Format-FileSize $wastedBytes) wasted) in $cliElapsedStr"
    }

    if ($results.Count -eq 0) {
        if ($Json) { Write-Output "[]" }
        exit 0
    }

    # Apply auto-select if specified
    if ($AutoSelect) {
        $groups = @{}
        foreach ($r in $results) {
            if (-not $groups.ContainsKey($r.Group)) {
                $groups[$r.Group] = [System.Collections.Generic.List[PSCustomObject]]::new()
            }
            $groups[$r.Group].Add($r)
        }
        foreach ($kv in $groups.GetEnumerator()) {
            $items = $kv.Value
            $keepItem = switch ($AutoSelect) {
                'KeepNewest'       { ($items | Sort-Object ModifiedDt -Descending)[0] }
                'KeepOldest'       { ($items | Sort-Object ModifiedDt)[0] }
                'KeepReference'    { $ref = $items | Where-Object { $_.IsRef } | Select-Object -First 1; if ($ref) { $ref } else { $items[0] } }
                'KeepLargest'      { ($items | Sort-Object Size -Descending)[0] }
                'KeepShortestPath' { ($items | Sort-Object { $_.FullPath.Length })[0] }
            }
            foreach ($i in $items) {
                if ($i.IsRef) { $i.Selected = $false; continue }
                $i.Selected = ($i -ne $keepItem)
            }
        }
    }

    # DryRun mode: just report what would happen
    if ($DryRun -and $Delete) {
        $selected = @($results | Where-Object { $_.Selected -and -not $_.IsRef })
        if (-not $Silent) {
            Write-Host "`n=== DRY RUN (no files will be modified) ==="
            Write-Host "Delete mode: $Delete"
            foreach ($item in $selected) {
                $issues = @()
                if (Test-FileLocked $item.FullPath) { $issues += "LOCKED" }
                if ($Delete -eq 'Hardlink') {
                    $original = $results | Where-Object { $_.Group -eq $item.Group -and -not $_.Selected } | Select-Object -First 1
                    if ($original) {
                        $srcVol = Get-VolumeRoot $item.FullPath
                        $dstVol = Get-VolumeRoot $original.FullPath
                        if ($srcVol -ne $dstVol) { $issues += "CROSS-VOLUME" }
                    }
                }
                $tag = if ($issues.Count -gt 0) { " [" + ($issues -join ', ') + "]" } else { "" }
                Write-Host "  [Would delete] $($item.FullPath)$tag"
            }
            $totalSize = ($selected | Measure-Object -Property Size -Sum).Sum
            Write-Host "Total: $($selected.Count) files, $(Format-FileSize $totalSize)"
        }
        exit 0
    }

    # Execute delete if requested
    if ($Delete -and $AutoSelect) {
        $selected = @($results | Where-Object { $_.Selected -and -not $_.IsRef })
        $deleted = 0
        $errors = 0
        $skippedLocked = 0
        $skippedCrossVol = 0
        foreach ($item in $selected) {
            if (-not [System.IO.File]::Exists($item.FullPath)) { continue }
            if (Test-FileLocked $item.FullPath) { $skippedLocked++; continue }
            try {
                switch ($Delete) {
                    'RecycleBin' { Remove-ToRecycleBin $item.FullPath }
                    'Permanent'  { [System.IO.File]::Delete($item.FullPath) }
                    'Hardlink'   {
                        $original = $results | Where-Object { $_.Group -eq $item.Group -and -not $_.Selected } | Select-Object -First 1
                        if ($original -and [System.IO.File]::Exists($original.FullPath)) {
                            $srcVol = Get-VolumeRoot $item.FullPath
                            $dstVol = Get-VolumeRoot $original.FullPath
                            if ($srcVol -ne $dstVol) { $skippedCrossVol++; continue }
                            $tempLink = $item.FullPath + ".dff_hardlink_tmp"
                            $hlResult = [Win32]::CreateHardLink($tempLink, $original.FullPath, [IntPtr]::Zero)
                            if (-not $hlResult) { $errors++; continue }
                            [System.IO.File]::Delete($item.FullPath)
                            [System.IO.File]::Move($tempLink, $item.FullPath)
                        }
                    }
                }
                $deleted++
            } catch { $errors++ }
        }
        if (-not $Silent) {
            $totalSize = ($selected | Measure-Object -Property Size -Sum).Sum
            $parts = @("$deleted files deleted")
            if ($skippedLocked -gt 0) { $parts += "$skippedLocked locked (skipped)" }
            if ($skippedCrossVol -gt 0) { $parts += "$skippedCrossVol cross-volume (skipped)" }
            if ($errors -gt 0) { $parts += "$errors errors" }
            $parts += "$(Format-FileSize $totalSize) reclaimed"
            Write-Host ($parts -join ' | ')
        }
    }

    # Output results
    if ($Json) {
        $output = $results | Select-Object Group, Status, FileName, FullPath, FolderPath, SizeDisplay, Size, Modified, IsRef, Hash, Selected
        $output | ConvertTo-Json -Depth 5
    } elseif ($ReportPath) {
        $sb = [System.Text.StringBuilder]::new()
        $sb.AppendLine('"Group","Selected","Status","FileName","Size","SizeBytes","Modified","FolderPath","FullPath","Hash"') | Out-Null
        foreach ($r in $results) {
            $fn = $r.FileName -replace '"','""'
            $fp = $r.FolderPath -replace '"','""'
            $full = $r.FullPath -replace '"','""'
            $sd = $r.SizeDisplay -replace '"','""'
            $sb.AppendLine("`"$($r.Group)`",`"$($r.Selected)`",`"$($r.Status)`",`"$fn`",`"$sd`",`"$($r.Size)`",`"$($r.Modified)`",`"$fp`",`"$full`",`"$($r.Hash)`"") | Out-Null
        }
        $utf8Bom = [System.Text.UTF8Encoding]::new($true)
        [System.IO.File]::WriteAllText($ReportPath, $sb.ToString(), $utf8Bom)
        if (-not $Silent) { Write-Host "Report saved to $ReportPath" }
    } elseif (-not $Silent -and -not $Delete) {
        # Default text output
        $lastGroup = 0
        foreach ($r in $results) {
            if ($r.Group -ne $lastGroup) {
                if ($lastGroup -gt 0) { Write-Host "" }
                Write-Host "--- Group $($r.Group) ($($r.SizeDisplay) each) ---" -ForegroundColor Cyan
                $lastGroup = $r.Group
            }
            $prefix = switch ($r.Status) {
                "REF"       { "[REF]  " }
                "Original"  { "[KEEP] " }
                "Duplicate" { "[DUP]  " }
            }
            $color = switch ($r.Status) {
                "REF"       { "Green" }
                "Original"  { "White" }
                "Duplicate" { "Yellow" }
            }
            Write-Host "  $prefix$($r.FullPath)" -ForegroundColor $color
        }
    }

    # Exit codes: 0 success, 1 partial (had errors), 2 user-cancelled (N/A in CLI batch), 3 ref folder unreadable
    if ($errors -gt 0 -and $deleted -gt 0) { exit 1 }
    exit 0

} # end CLI MODE
