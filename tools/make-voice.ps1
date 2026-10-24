# Generates the cheer voice clips (Mole Carnival) voice/<lang>/<group>-<index>.mp3 with Azure text-to-speech.
# The lines come from the VOICE table (one set per language) between "// VOICE-BEGIN" and "// VOICE-END"
# in index.html; after editing a line, rerun with -Force (or delete that mp3) so it is regenerated.
# The key file is never committed: line 1 = key, line 2 = region (e.g. eastasia).
param(
  [string]$KeyFile = "$env:USERPROFILE\.secrets\azure-key.txt",
  [string[]]$Lang = @('zh', 'en'),
  [switch]$Force
)
$ErrorActionPreference = 'Stop'

# Voice per language: Chinese = lively young girl, English = Jenny "cheerful" at natural pitch.
# (Jenny "excited" with a raised pitch made short words mushy: speech recognition heard "Ready? Go!" as "Ready. Dull".)
$Voices = @{
  zh = @{ Voice = 'zh-CN-XiaoyiNeural'; Locale = 'zh-CN'; Style = 'cheerful'; Rate = '+6%'; Pitch = '+8%' }
  en = @{ Voice = 'en-US-JennyNeural';  Locale = 'en-US'; Style = 'cheerful'; Rate = '0%';  Pitch = '0%' }
}

$root = Split-Path -Parent $PSScriptRoot
$html = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'index.html')
if ($html -notmatch '(?s)// VOICE-BEGIN\s*const VOICE = (\{.*?\});\s*// VOICE-END') { throw 'VOICE table not found in index.html' }
$table = $Matches[1] | ConvertFrom-Json

$lines = Get-Content $KeyFile | Where-Object { $_.Trim() -ne '' }
$key = $lines[0].Trim()
$region = $lines[1].Trim().ToLower().Replace(' ', '')
$url = "https://$region.tts.speech.microsoft.com/cognitiveservices/v1"
$headers = @{
  'Ocp-Apim-Subscription-Key' = $key
  'X-Microsoft-OutputFormat'  = 'audio-24khz-48kbitrate-mono-mp3'
  'User-Agent'                = 'mole-carnival'
}

$made = 0
foreach ($l in $Lang) {
  $v = $Voices[$l]
  if (-not $v -or -not $table.$l) { Write-Host "  skip unknown language: $l" -ForegroundColor Yellow; continue }
  $outDir = Join-Path $root "voice\$l"
  New-Item -ItemType Directory -Force $outDir | Out-Null
  foreach ($p in $table.$l.PSObject.Properties) {
    $i = 0
    foreach ($text in $p.Value) {
      $file = Join-Path $outDir ('{0}-{1}.mp3' -f $p.Name, $i)
      $i++
      if ((Test-Path $file) -and -not $Force) { continue }
      $t = [Security.SecurityElement]::Escape($text)
      $ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xmlns:mstts='https://www.w3.org/2001/mstts' xml:lang='$($v.Locale)'>" +
        "<voice name='$($v.Voice)'><mstts:express-as style='$($v.Style)' styledegree='2'><prosody rate='$($v.Rate)' pitch='$($v.Pitch)'>$t</prosody></mstts:express-as></voice></speak>"
      for ($try = 1; $try -le 6; $try++) {
        try {
          Invoke-WebRequest -UseBasicParsing -Method Post -Uri $url -Headers $headers -ContentType 'application/ssml+xml' `
            -Body ([Text.Encoding]::UTF8.GetBytes($ssml)) -OutFile $file -TimeoutSec 30
          $made++
          Write-Host ('  {0}/{1}' -f $l, (Split-Path -Leaf $file))
          break
        } catch {
          $code = 0; if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
          if ($code -eq 429 -or $code -ge 500 -or $code -eq 0) { Start-Sleep -Seconds (5 * $try); continue }
          Write-Host "  failed ($code): $l/$($p.Name)-$($i - 1)" -ForegroundColor Red
          break
        }
      }
    }
  }
}
Write-Host "Done, $made new clip(s)."
