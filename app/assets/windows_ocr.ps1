param([Parameter(Mandatory=$true)][string]$ImagePath)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime]
$null = [Windows.Globalization.Language, Windows.Globalization, ContentType=WindowsRuntime]
$script:AwaitMethod = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetGenericArguments().Count -eq 1 -and $_.GetParameters().Count -eq 1 } | Select-Object -First 1
function Await($Operation, $ResultType) {
  $Task = $script:AwaitMethod.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
  $Task.Wait()
  return $Task.Result
}
try {
  $File = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($ImagePath)) ([Windows.Storage.StorageFile])
  $Stream = Await ($File.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  $Decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($Stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $Bitmap = Await ($Decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $Converted = [Windows.Graphics.Imaging.SoftwareBitmap]::Convert($Bitmap, [Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8, [Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied)
  $Language = [Windows.Globalization.Language]::new('ru-RU')
  $Engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($Language)
  if (!$Engine) { throw 'Для русского OCR установите русский языковой пакет распознавания текста в настройках Windows.' }
  $Result = Await ($Engine.RecognizeAsync($Converted)) ([Windows.Media.Ocr.OcrResult])
  $Result.Lines | ForEach-Object { $_.Text }
  $Converted.Dispose()
  $Bitmap.Dispose()
  $Stream.Dispose()
} catch {
  [Console]::Error.WriteLine('Не удалось распознать текст. Для Windows требуется русский языковой пакет OCR. Попробуйте более чёткий снимок или ручное заполнение.')
  exit 1
}
