# Shared modern (WPF) window for the Daily Board setup and uninstaller: rounded card, the board's green accent,
# follows the Windows light/dark setting. Dot-source this file; it is not used by the quiet install.
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

function Get-UiTheme {
  $dark = $false
  try { $dark = (Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop) -eq 0 } catch { }
  if ($dark) {
    return @{
      Dark = $true; Card = '#1a1f25'; Text = '#e6e9ee'; Muted = '#a3adba'; Border = '#2b323b'; Input = '#111418'; Hover = '#232a32'
      Accent = '#3fae6a'; Primary = '#1e7d45'; PrimaryHover = '#23904f'; Danger = '#ff9aa0'; DangerFill = '#b3261e'; DangerHover = '#c9372c'; SoftAccent = '#1a2a20'; SoftDanger = '#3a1d1f'
      Colors = [ordered]@{ amber = '#fbbf24', '#2a2114'; blue = '#7cb4ff', '#15202f'; violet = '#c9a2ff', '#221a30'; pink = '#f9a8d4', '#2e1826'; cyan = '#67e8f9', '#102a30'; slate = '#cbd5e1', '#222932' }
    }
  }
  return @{
    Dark = $false; Card = '#ffffff'; Text = '#1b1f24'; Muted = '#5f6b7a'; Border = '#dfe3e8'; Input = '#f7f8fa'; Hover = '#f1f3f5'
    Accent = '#166534'; Primary = '#15803d'; PrimaryHover = '#166534'; Danger = '#a4262c'; DangerFill = '#b3261e'; DangerHover = '#9b1f18'; SoftAccent = '#e8f5ec'; SoftDanger = '#fdecec'
    Colors = [ordered]@{ amber = '#b45309', '#fff7ed'; blue = '#1d4ed8', '#eff6ff'; violet = '#7e22ce', '#faf5ff'; pink = '#be185d', '#fdf2f8'; cyan = '#0e7490', '#ecfeff'; slate = '#475569', '#f1f5f9' }
  }
}

function ConvertTo-Brush([string]$hex) { New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex)) }

function New-SetupWindow([string]$caption, [string]$iconPath) {
  $t = Get-UiTheme
  $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="NoResize"
        SizeToContent="Height" Width="580" WindowStartupLocation="CenterScreen" ShowInTaskbar="True"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13" Foreground="@@TEXT@@" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Padding" Value="18,8"/><Setter Property="MinWidth" Value="100"/>
      <Setter Property="Margin" Value="10,0,0,0"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Background" Value="@@CARD@@"/><Setter Property="Foreground" Value="@@TEXT@@"/><Setter Property="BorderBrush" Value="@@BORDER@@"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="b" CornerRadius="6" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" Padding="{TemplateBinding Padding}">
          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="@@HOVER@@"/></Trigger>
          <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="@@ACCENT@@"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger>
        </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Foreground" Value="#ffffff"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="b" CornerRadius="6" Background="@@PRIMARY@@" Padding="{TemplateBinding Padding}">
          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="@@PRIMARYHOVER@@"/></Trigger>
          <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="Background" Value="@@PRIMARYHOVER@@"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger>
        </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Danger" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Foreground" Value="#ffffff"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="b" CornerRadius="6" Background="@@DANGERFILL@@" Padding="{TemplateBinding Padding}">
          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="@@DANGERHOVER@@"/></Trigger>
          <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="Background" Value="@@DANGERHOVER@@"/></Trigger>
        </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Close" TargetType="Button">
      <Setter Property="Width" Value="46"/><Setter Property="Height" Value="36"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Foreground" Value="@@MUTED@@"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="b" CornerRadius="0,12,0,0" Background="Transparent">
          <TextBlock Text="&#xE8BB;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="10" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="{TemplateBinding Foreground}"/></Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#c42b1c"/><Setter Property="Foreground" Value="#ffffff"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.3"/></Trigger>
        </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="FontSize" Value="14"/><Setter Property="Foreground" Value="@@TEXT@@"/><Setter Property="Background" Value="@@INPUT@@"/>
      <Setter Property="CaretBrush" Value="@@TEXT@@"/><Setter Property="SelectionBrush" Value="@@ACCENT@@"/><Setter Property="BorderBrush" Value="@@BORDER@@"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox">
        <Border x:Name="b" CornerRadius="6" BorderThickness="1" BorderBrush="{TemplateBinding BorderBrush}" Background="{TemplateBinding Background}">
          <ScrollViewer x:Name="PART_ContentHost" Margin="10,7" VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="@@ACCENT@@"/><Setter TargetName="b" Property="BorderThickness" Value="2"/></Trigger>
        </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Swatch" TargetType="RadioButton">
      <Setter Property="Width" Value="26"/><Setter Property="Height" Value="26"/><Setter Property="Margin" Value="2,0"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton">
        <Grid Background="Transparent">
          <Ellipse x:Name="ring" Stroke="{TemplateBinding Background}" StrokeThickness="2" Opacity="0"/>
          <Ellipse Margin="5" Fill="{TemplateBinding Background}"/></Grid>
        <ControlTemplate.Triggers>
          <Trigger Property="IsChecked" Value="True"><Setter TargetName="ring" Property="Opacity" Value="1"/></Trigger>
          <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="ring" Property="Opacity" Value="0.6"/><Setter TargetName="ring" Property="StrokeDashArray" Value="2 1"/></Trigger>
        </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style TargetType="ProgressBar">
      <Setter Property="Height" Value="6"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ProgressBar">
        <Grid><Border x:Name="PART_Track" CornerRadius="3" Background="@@BORDER@@"/>
          <Border x:Name="PART_Indicator" CornerRadius="3" Background="@@PRIMARY@@" HorizontalAlignment="Left"/></Grid>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Border Margin="18" CornerRadius="12" Background="@@CARD@@" BorderBrush="@@BORDER@@" BorderThickness="1">
    <Border.Effect><DropShadowEffect BlurRadius="24" ShadowDepth="4" Opacity="@@SHADOW@@" Color="#000000"/></Border.Effect>
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <Grid x:Name="TitleBar" Background="Transparent" Height="36">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="16,0,0,0">
          <Image x:Name="Logo" Width="16" Height="16" Margin="0,0,8,0"/>
          <TextBlock x:Name="Caption" Foreground="@@MUTED@@" FontSize="12"/>
        </StackPanel>
        <Button x:Name="CloseButton" Style="{StaticResource Close}" HorizontalAlignment="Right" VerticalAlignment="Top" AutomationProperties.Name="Close" IsCancel="False"/>
      </Grid>
      <StackPanel Grid.Row="1" Margin="32,8,32,0">
        <TextBlock x:Name="Heading" FontSize="24" FontWeight="SemiBold" Foreground="@@ACCENT@@" TextWrapping="Wrap"/>
        <TextBlock x:Name="Subtitle" Margin="0,6,0,0" Foreground="@@MUTED@@" TextWrapping="Wrap" LineHeight="19"/>
      </StackPanel>
      <ContentControl x:Name="Body" Grid.Row="2" Margin="32,20,32,0" Focusable="False"/>
      <Grid Grid.Row="3" Margin="32,22,32,26">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <TextBlock x:Name="ErrorText" Foreground="@@DANGER@@" TextWrapping="Wrap" VerticalAlignment="Center" Margin="0,0,12,0"/>
        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button x:Name="SecondaryButton" Style="{StaticResource Btn}" IsCancel="True"/>
          <Button x:Name="PrimaryButton" Style="{StaticResource Primary}" IsDefault="True"/>
        </StackPanel>
      </Grid>
    </Grid>
  </Border>
</Window>
'@
  $map = @{ TEXT = $t.Text; MUTED = $t.Muted; CARD = $t.Card; BORDER = $t.Border; INPUT = $t.Input; HOVER = $t.Hover; ACCENT = $t.Accent
    PRIMARY = $t.Primary; PRIMARYHOVER = $t.PrimaryHover; DANGER = $t.Danger; DANGERFILL = $t.DangerFill; DANGERHOVER = $t.DangerHover
    SHADOW = $(if ($t.Dark) { '0.55' } else { '0.22' }) }
  foreach ($k in $map.Keys) { $xaml = $xaml.Replace("@@$k@@", $map[$k]) }
  $w = [System.Windows.Markup.XamlReader]::Parse($xaml)
  $ui = @{ Window = $w; Theme = $t }
  foreach ($n in 'TitleBar', 'Logo', 'Caption', 'CloseButton', 'Heading', 'Subtitle', 'Body', 'ErrorText', 'SecondaryButton', 'PrimaryButton') { $ui[$n] = $w.FindName($n) }
  $ui.Caption.Text = $caption
  $w.Title = $caption
  if ($iconPath -and (Test-Path $iconPath)) {
    try {
      # Read the icon into memory, so the file is never locked (the uninstaller deletes it while the window is open).
      $ms = New-Object System.IO.MemoryStream (, [System.IO.File]::ReadAllBytes($iconPath))
      $img = [System.Windows.Media.Imaging.BitmapFrame]::Create($ms, 'None', 'OnLoad')
      $w.Icon = $img; $ui.Logo.Source = $img
    } catch { }
  }
  $ui.TitleBar.Add_MouseLeftButtonDown({ try { [System.Windows.Window]::GetWindow($this).DragMove() } catch { } })
  $ui.CloseButton.Add_Click({ [System.Windows.Window]::GetWindow($this).Close() })
  $w.Add_ContentRendered({ [void]$this.Activate() })
  return $ui
}

# Shows one page: heading, subtitle, body and up to two buttons (an empty text hides a button).
function Set-UiPage($ui, [string]$Heading, [string]$Subtitle, $Body, [string]$Primary, [string]$Secondary, [string]$PrimaryStyle = 'Primary', [switch]$IsError) {
  $ui.Heading.Text = $Heading
  $ui.Heading.Foreground = ConvertTo-Brush $(if ($IsError) { $ui.Theme.Danger } else { $ui.Theme.Accent })
  $ui.Subtitle.Text = $Subtitle
  $ui.Subtitle.Visibility = $(if ($Subtitle) { 'Visible' } else { 'Collapsed' })
  $ui.Body.Content = $Body
  $ui.Body.Visibility = $(if ($Body) { 'Visible' } else { 'Collapsed' })
  $ui.ErrorText.Text = ''
  $ui.PrimaryButton.Content = $Primary
  $ui.PrimaryButton.Visibility = $(if ($Primary) { 'Visible' } else { 'Collapsed' })
  $ui.PrimaryButton.Style = $ui.Window.FindResource($PrimaryStyle)
  $ui.SecondaryButton.Content = $Secondary
  $ui.SecondaryButton.Visibility = $(if ($Secondary) { 'Visible' } else { 'Collapsed' })
  $ui.PrimaryButton.IsEnabled = $true; $ui.SecondaryButton.IsEnabled = $true; $ui.CloseButton.IsEnabled = $true
}

function New-UiText([string]$text, [string]$color, [double]$size = 13, [string]$weight = 'Normal', [string]$margin = '0') {
  $tb = New-Object System.Windows.Controls.TextBlock
  $tb.Text = $text; $tb.TextWrapping = 'Wrap'; $tb.FontSize = $size; $tb.FontWeight = [System.Windows.FontWeights]::$weight
  $tb.Margin = [System.Windows.ThicknessConverter]::new().ConvertFromString($margin)
  if ($color) { $tb.Foreground = ConvertTo-Brush $color }
  return $tb
}

# Progress page body: a thin bar and the current step. Returns @{ Panel; Bar; Step }.
function New-UiProgress($ui) {
  $panel = New-Object System.Windows.Controls.StackPanel
  $bar = New-Object System.Windows.Controls.ProgressBar
  $bar.Minimum = 0; $bar.Maximum = 100; $bar.Value = 2
  $step = New-UiText 'Starting...' $ui.Theme.Muted 13 'Normal' '0,12,0,0'
  [void]$panel.Children.Add($bar); [void]$panel.Children.Add($step)
  return @{ Panel = $panel; Bar = $bar; Step = $step }
}

# Result body: a round icon (check or exclamation mark) next to a message.
function New-UiResult($ui, [bool]$ok, [string]$message) {
  $t = $ui.Theme
  $grid = New-Object System.Windows.Controls.Grid
  $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::Auto
  [void]$grid.ColumnDefinitions.Add($c1)
  [void]$grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
  $badge = New-Object System.Windows.Controls.Grid
  $badge.Width = 44; $badge.Height = 44; $badge.VerticalAlignment = 'Top'; $badge.Margin = New-Object System.Windows.Thickness(0, 0, 16, 0)
  $circle = New-Object System.Windows.Shapes.Ellipse
  $circle.Fill = ConvertTo-Brush $(if ($ok) { $t.SoftAccent } else { $t.SoftDanger })
  [void]$badge.Children.Add($circle)
  $glyph = New-Object System.Windows.Controls.TextBlock
  $glyph.Text = $(if ($ok) { [string][char]0xE73E } else { [string][char]0xE783 })
  $glyph.FontFamily = 'Segoe Fluent Icons, Segoe MDL2 Assets'; $glyph.FontSize = 20
  $glyph.Foreground = ConvertTo-Brush $(if ($ok) { $t.Accent } else { $t.Danger })
  $glyph.HorizontalAlignment = 'Center'; $glyph.VerticalAlignment = 'Center'
  [void]$badge.Children.Add($glyph)
  [void]$grid.Children.Add($badge)
  $text = New-UiText $message $t.Text 13 'Normal' '0,2,0,0'
  $text.LineHeight = 20
  [System.Windows.Controls.Grid]::SetColumn($text, 1)
  [void]$grid.Children.Add($text)
  return $grid
}

# Lets the window repaint between install steps (the work runs on the window's own thread).
function Update-Ui {
  $frame = New-Object System.Windows.Threading.DispatcherFrame
  $cb = [System.Windows.Threading.DispatcherOperationCallback] { param($f) $f.Continue = $false; $null }
  [void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, $cb, $frame)
  [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

# A simple modern message (used for problems before the main window can open).
function Show-UiMessage([string]$heading, [string]$text, [bool]$ok, [string]$caption = 'Daily Board setup', [string]$iconPath) {
  $ui = New-SetupWindow $caption $iconPath
  Set-UiPage $ui $heading '' (New-UiResult $ui $ok $text) 'Close' '' -IsError:(-not $ok)
  $ui.PrimaryButton.Add_Click({ $ui.Window.Close() })
  [void]$ui.Window.ShowDialog()
}
