# DuplicateFF v1.0.0 - Professional Duplicate File Finder
# PowerShell WPF | Catppuccin Mocha | Progressive Hashing Pipeline
# MIT License - github.com/SysAdminDoc/DuplicateFF

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, Microsoft.VisualBasic
Add-Type -AssemblyName System.Drawing

# --- P/Invoke for console hiding ---
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
[Win32]::ShowWindow([Win32]::GetConsoleWindow(), 0) | Out-Null

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
        Title="DuplicateFF v1.0.0" Width="1280" Height="820" MinWidth="900" MinHeight="650"
        WindowStartupLocation="CenterScreen" Background="$($Colors.Base)">
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
                    <Button x:Name="btnAddFolder" Grid.Column="2" Content="Add Folder" Style="{StaticResource BtnStyle}" Margin="8,0,0,0"/>
                    <Button x:Name="btnAddRef" Grid.Column="3" Content="Add Reference" Style="{StaticResource BtnStyle}" Margin="4,0,0,0"
                            ToolTip="Reference folders are protected - duplicates will never be selected from these"/>
                    <Button x:Name="btnRemoveFolder" Grid.Column="4" Content="Remove" Style="{StaticResource BtnStyle}" Margin="4,0,0,0"/>
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
                    <TextBlock Grid.Column="2" Text="  Filter:" VerticalAlignment="Center" Margin="10,0,6,0" FontSize="13"/>
                    <ComboBox x:Name="cmbFilter" Grid.Column="3" Width="130" Style="{StaticResource ComboStyle}">
                        <ComboBoxItem Content="All Files" IsSelected="True"/>
                        <ComboBoxItem Content="Images Only"/>
                        <ComboBoxItem Content="Videos Only"/>
                        <ComboBoxItem Content="Audio Only"/>
                        <ComboBoxItem Content="Documents"/>
                    </ComboBox>
                    <CheckBox x:Name="chkSubfolders" Grid.Column="4" Content="Include Subfolders" IsChecked="True"
                              Margin="16,0,0,0" VerticalAlignment="Center" FontSize="13"/>
                    <CheckBox x:Name="chkZeroByte" Grid.Column="5" Content="Skip 0-byte" IsChecked="True"
                              Margin="16,0,0,0" VerticalAlignment="Center" FontSize="13"/>
                    <Button x:Name="btnScan" Grid.Column="7" Content="Scan for Duplicates" Style="{StaticResource AccentBtn}"
                            Padding="20,7" FontSize="14"/>
                    <Button x:Name="btnCancel" Grid.Column="8" Content="Cancel" Style="{StaticResource BtnStyle}"
                            Margin="6,0,0,0" IsEnabled="False"/>
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
                <DataGrid x:Name="dgResults" AutoGenerateColumns="False" IsReadOnly="False"
                          Background="$($Colors.Mantle)" Foreground="$($Colors.Text)"
                          BorderThickness="0" GridLinesVisibility="Horizontal"
                          HorizontalGridLinesBrush="$($Colors.Surface0)"
                          RowBackground="$($Colors.Mantle)" AlternatingRowBackground="$($Colors.Base)"
                          HeadersVisibility="Column" CanUserSortColumns="True"
                          SelectionMode="Extended" SelectionUnit="FullRow"
                          CanUserResizeColumns="True" FontSize="12.5">
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
                    <DataGrid.Columns>
                        <DataGridCheckBoxColumn Binding="{Binding Selected, UpdateSourceTrigger=PropertyChanged}" Width="35"
                                                Header="" ElementStyle="{x:Null}"/>
                        <DataGridTextColumn Binding="{Binding Group}" Header="Group" Width="55"/>
                        <DataGridTextColumn Binding="{Binding FileName}" Header="File Name" Width="*" MinWidth="150"/>
                        <DataGridTextColumn Binding="{Binding SizeDisplay}" Header="Size" Width="85"/>
                        <DataGridTextColumn Binding="{Binding Modified}" Header="Modified" Width="130"/>
                        <DataGridTextColumn Binding="{Binding FolderPath}" Header="Folder" Width="250"/>
                        <DataGridTextColumn Binding="{Binding Status}" Header="Status" Width="75"/>
                    </DataGrid.Columns>
                </DataGrid>
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
                        <Button x:Name="btnDeleteSelected" Content="Delete Selected" Style="{StaticResource DangerBtn}"
                                HorizontalAlignment="Stretch" Margin="0,0,0,4"/>
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
                           FontSize="12" Foreground="$($Colors.Subtext0)" VerticalAlignment="Center"/>
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
@('lstFolders','btnAddFolder','btnAddRef','btnRemoveFolder','cmbMinSize','cmbFilter',
  'chkSubfolders','chkZeroByte','btnScan','btnCancel','dgResults','imgPreview',
  'txtPreviewName','txtPreviewInfo','cmbAutoSelect','btnAutoSelect','btnSelectAll',
  'btnDeselectAll','btnInvertSel','cmbDeleteMode','btnDeleteSelected','btnExport',
  'txtStatus','txtStats','prgScan') | ForEach-Object {
    $controls[$_] = $window.FindName($_)
}

# --- State ---
$script:ScanFolders = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:Results = [System.Collections.ObjectModel.ObservableCollection[PSCustomObject]]::new()
$script:CancelSource = $null
$script:IsScanning = $false
$script:ImageExts = @('.jpg','.jpeg','.png','.gif','.bmp','.tiff','.tif','.webp','.ico','.svg','.heic','.heif','.avif')
$script:VideoExts = @('.mp4','.mkv','.avi','.mov','.wmv','.flv','.webm','.m4v','.mpg','.mpeg','.3gp','.ts')
$script:AudioExts = @('.mp3','.flac','.wav','.aac','.ogg','.wma','.m4a','.opus','.aiff','.alac')
$script:DocExts = @('.pdf','.doc','.docx','.xls','.xlsx','.ppt','.pptx','.txt','.rtf','.odt','.ods','.csv')

$controls.dgResults.ItemsSource = $script:Results

# --- Helper: Format Size ---
function Format-FileSize([long]$bytes) {
    if ($bytes -lt 1KB) { return "$bytes B" }
    if ($bytes -lt 1MB) { return "{0:N1} KB" -f ($bytes / 1KB) }
    if ($bytes -lt 1GB) { return "{0:N1} MB" -f ($bytes / 1MB) }
    return "{0:N2} GB" -f ($bytes / 1GB)
}

# --- Helper: Parse Min Size ---
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

# --- Helper: File Extension Filter ---
function Test-FileFilter([string]$ext, [string]$filter) {
    switch ($filter) {
        "Images Only"  { return $ext -in $script:ImageExts }
        "Videos Only"  { return $ext -in $script:VideoExts }
        "Audio Only"   { return $ext -in $script:AudioExts }
        "Documents"    { return $ext -in $script:DocExts }
        default        { return $true }
    }
}

# --- Helper: SHA256 of byte range ---
function Get-PartialHash([string]$path, [long]$offset, [long]$count) {
    try {
        $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        try {
            $sha = [System.Security.Cryptography.SHA256]::Create()
            $buf = [byte[]]::new([Math]::Min($count, $fs.Length - $offset))
            $fs.Position = $offset
            $read = $fs.Read($buf, 0, $buf.Length)
            if ($read -gt 0) {
                return [BitConverter]::ToString($sha.ComputeHash($buf, 0, $read)).Replace('-','')
            }
        } finally { $fs.Dispose() }
    } catch { return $null }
    return $null
}

# --- Helper: Full file SHA256 ---
function Get-FileHashValue([string]$path) {
    try {
        $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        try {
            $sha = [System.Security.Cryptography.SHA256]::Create()
            return [BitConverter]::ToString($sha.ComputeHash($fs)).Replace('-','')
        } finally { $fs.Dispose() }
    } catch { return $null }
}

# --- Helper: Send to Recycle Bin ---
function Remove-ToRecycleBin([string]$path) {
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
        $path,
        [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
        [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
    )
}

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

# --- SCAN ---
$controls.btnScan.Add_Click({
    if ($script:ScanFolders.Count -eq 0) {
        $controls.txtStatus.Text = "Add at least one folder to scan"
        return
    }
    if ($script:IsScanning) { return }

    $script:IsScanning = $true
    $script:Results.Clear()
    $controls.btnScan.IsEnabled = $false
    $controls.btnCancel.IsEnabled = $true
    $controls.prgScan.Visibility = 'Visible'
    $controls.prgScan.IsIndeterminate = $true
    $controls.txtStatus.Text = "Scanning..."
    $controls.txtStats.Text = ""

    $script:CancelSource = [System.Threading.CancellationTokenSource]::new()
    $token = $script:CancelSource.Token

    $folders = $script:ScanFolders | ForEach-Object { [PSCustomObject]@{ Path = $_.Path; IsReference = $_.IsReference } }
    $recurse = $controls.chkSubfolders.IsChecked
    $skipZero = $controls.chkZeroByte.IsChecked
    $minSizeLabel = ($controls.cmbMinSize.SelectedItem).Content
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
        Done = $false
        Error = $null
    })

    # Background worker
    $ps = [PowerShell]::Create()
    $ps.AddScript({
        param($folders, $recurse, $skipZero, $minSizeLabel, $filterLabel, $token, $sync,
              $imageExts, $videoExts, $audioExts, $docExts)

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
                    $len = [Math]::Min($count, $fs.Length - $offset)
                    if ($len -le 0) { return "" }
                    $buf = [byte[]]::new($len)
                    $fs.Position = $offset
                    $read = $fs.Read($buf, 0, $buf.Length)
                    if ($read -gt 0) {
                        return [BitConverter]::ToString($sha.ComputeHash($buf, 0, $read)).Replace('-','')
                    }
                } finally { $fs.Dispose() }
            } catch { return $null }
            return $null
        }
        function Get-FileHashValue([string]$path) {
            try {
                $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
                try {
                    $sha = [System.Security.Cryptography.SHA256]::Create()
                    return [BitConverter]::ToString($sha.ComputeHash($fs)).Replace('-','')
                } finally { $fs.Dispose() }
            } catch { return $null }
        }

        try {
            $minSize = Get-MinSizeBytes $minSizeLabel

            # Phase 1: Enumerate files
            $sync.Status = "Enumerating files..."
            $sync.Phase = "enum"
            $allFiles = [System.Collections.Generic.List[PSCustomObject]]::new()

            # Build reference path set
            $refPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($f in $folders) {
                if ($f.IsReference) { $refPaths.Add($f.Path) | Out-Null }
            }

            foreach ($folder in $folders) {
                if ($token.IsCancellationRequested) { return }
                $searchOpt = if ($recurse) { 'AllDirectories' } else { 'TopDirectoryOnly' }
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
                        $ext = $fi.Extension.ToLowerInvariant()
                        if (-not (Test-FileFilter $ext $filterLabel)) { continue }

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
                } catch { continue }
            }

            if ($token.IsCancellationRequested) { return }
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

            # Build results
            $sync.Phase = "results"
            $groupNum = 0
            $dupFiles = 0
            $wastedBytes = 0L
            foreach ($kv in $fullGroups.GetEnumerator()) {
                if ($kv.Value.Count -lt 2) { continue }
                $groupNum++
                $first = $true
                foreach ($f in ($kv.Value | Sort-Object Modified -Descending)) {
                    $status = if ($f.IsRef) { "REF" } elseif ($first) { "Original" } else { "Duplicate" }
                    $sync.Results.Add([PSCustomObject]@{
                        Group     = $groupNum
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
    ).AddArgument($filterLabel).AddArgument($token).AddArgument($sync
    ).AddArgument($script:ImageExts).AddArgument($script:VideoExts).AddArgument($script:AudioExts).AddArgument($script:DocExts)

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

            if ($s.Error) {
                $controls.txtStatus.Text = "Error: $($s.Error)"
            } else {
                $controls.txtStats.Text = "$($s.DuplicateGroups) groups | $($s.DuplicateFiles) duplicates | $(Format-FileSize $s.WastedSpace) wasted"
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

    $deleted = 0
    $errors = 0
    foreach ($item in $selected) {
        try {
            if (-not [System.IO.File]::Exists($item.FullPath)) { continue }
            switch ($mode) {
                "Move to Recycle Bin" {
                    Remove-ToRecycleBin $item.FullPath
                }
                "Permanent Delete" {
                    [System.IO.File]::Delete($item.FullPath)
                }
                "Replace with Hardlinks" {
                    # Find the original in the same group
                    $original = $script:Results | Where-Object { $_.Group -eq $item.Group -and -not $_.Selected -and $_.FullPath -ne $item.FullPath } | Select-Object -First 1
                    if ($original -and [System.IO.File]::Exists($original.FullPath)) {
                        [System.IO.File]::Delete($item.FullPath)
                        cmd /c mklink /H "`"$($item.FullPath)`"" "`"$($original.FullPath)`"" 2>$null | Out-Null
                    } else {
                        [System.IO.File]::Delete($item.FullPath)
                    }
                }
            }
            $deleted++
        } catch {
            $errors++
        }
    }

    # Remove deleted items from results
    $toRemove = @($script:Results | Where-Object { $_.Selected -and -not [System.IO.File]::Exists($_.FullPath) })
    foreach ($r in $toRemove) { $script:Results.Remove($r) | Out-Null }

    # Clean up groups with only 1 remaining
    $groupCounts = @{}
    foreach ($r in $script:Results) {
        if (-not $groupCounts.ContainsKey($r.Group)) { $groupCounts[$r.Group] = 0 }
        $groupCounts[$r.Group]++
    }
    $singles = @($script:Results | Where-Object { $groupCounts[$_.Group] -lt 2 })
    foreach ($s in $singles) { $script:Results.Remove($s) | Out-Null }

    $errMsg = if ($errors -gt 0) { " ($errors errors)" } else { "" }
    $controls.txtStatus.Text = "$deleted files deleted$errMsg - $(Format-FileSize $totalSize) reclaimed"
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
        $sb.AppendLine("Group,Selected,Status,FileName,Size,SizeBytes,Modified,FolderPath,FullPath,Hash") | Out-Null
        foreach ($r in $script:Results) {
            $fn = $r.FileName -replace '"','""'
            $fp = $r.FolderPath -replace '"','""'
            $full = $r.FullPath -replace '"','""'
            $sb.AppendLine("$($r.Group),$($r.Selected),$($r.Status),`"$fn`",$($r.SizeDisplay),$($r.Size),$($r.Modified),`"$fp`",`"$full`",$($r.Hash)") | Out-Null
        }
        [System.IO.File]::WriteAllText($dlg.FileName, $sb.ToString(), [System.Text.Encoding]::UTF8)
        $controls.txtStatus.Text = "Exported $($script:Results.Count) results to $($dlg.FileName)"
    }
})

# --- Show Window ---
$window.ShowDialog() | Out-Null
