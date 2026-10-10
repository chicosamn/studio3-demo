$ErrorActionPreference = "Stop"
$key = [Environment]::GetEnvironmentVariable("APIMART_KEY","User")
if(-not $key){ Write-Output "SIN_CLAVE"; exit 1 }
$submitUrl = "https://api.apimart.ai/v1/images/generations"
$taskUrl   = "https://api.apimart.ai/v1/tasks/"
$headers   = @{ Authorization = "Bearer $key" }
$root = $PSScriptRoot
$assets = Join-Path $root "assets"
$raw = Join-Path $root "_raw"
if(-not(Test-Path $raw)){ New-Item -ItemType Directory -Path $raw | Out-Null }

$style = "candid editorial photograph, natural realistic hair texture, soft natural salon light, 50mm lens, photorealistic. No text, no watermark, no logos."

$jobs = @(
  @{ out="ba-color-before"; prompt="Back view of a Latin American woman's long hair that looks dull and faded with visible grown-out dark roots and dry damaged ends, before salon color, plain neutral salon background, centered framing." },
  @{ out="ba-color-after";  prompt="Back view of a Latin American woman's long hair with glossy caramel balayage highlights, healthy shiny freshly colored hair, after salon color, plain neutral salon background, centered framing." },
  @{ out="ba-liso-before";  prompt="Back view of a Latin American woman's frizzy dry voluminous wavy hair before a keratin smoothing treatment, plain neutral salon background, centered framing." },
  @{ out="ba-liso-after";   prompt="Back view of a Latin American woman's sleek glossy perfectly straight smooth hair after keratin treatment, plain neutral salon background, centered framing." }
)

foreach($j in $jobs){
  $body = @{ model="gpt-image-2"; prompt=($j.prompt+" "+$style); size="1536x1024"; n=1 } | ConvertTo-Json
  try{
    $sub = Invoke-RestMethod -Uri $submitUrl -Method Post -Headers $headers -ContentType "application/json" -Body $body
    $j.task = $sub.data[0].task_id
    Write-Output ("SUBMIT " + $j.out + " -> " + $j.task)
  } catch { Write-Output ("SUBMIT_FAIL " + $j.out + " " + $_.Exception.Message); $j.task=$null }
  Start-Sleep -Milliseconds 400
}

Add-Type -AssemblyName System.Drawing
function Save-Jpg($srcPath,$dstPath,$targetW){
  $img=[System.Drawing.Image]::FromFile($srcPath)
  $w=$img.Width;$h=$img.Height
  if($w -gt $targetW){ $nh=[int]($h*($targetW/$w)); $nw=$targetW } else { $nw=$w;$nh=$h }
  $bmp=New-Object System.Drawing.Bitmap $nw,$nh
  $g=[System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($img,0,0,$nw,$nh)
  $enc=[System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()|?{$_.MimeType -eq "image/jpeg"}
  $p=New-Object System.Drawing.Imaging.EncoderParameters 1
  $p.Param[0]=New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality,[long]82)
  $bmp.Save($dstPath,$enc,$p);$g.Dispose();$bmp.Dispose();$img.Dispose()
}

foreach($j in $jobs){
  if(-not $j.task){ continue }
  $done=$false
  for($n=0;$n -lt 90 -and -not $done;$n++){
    Start-Sleep -Seconds 4
    try{
      $t=Invoke-RestMethod -Uri ($taskUrl+$j.task) -Method Get -Headers $headers
      $st=$t.data.status; if(-not $st){ $st=$t.status }
      if($st -eq "completed" -or $st -eq "succeeded"){
        $res=$t.data.result; if(-not $res){ $res=$t.result }
        $u=$res.images[0].url; if($u -is [array]){ $u=$u[0] }
        $rawPath=Join-Path $raw ($j.out+".png")
        Invoke-WebRequest -Uri $u -OutFile $rawPath
        Save-Jpg $rawPath (Join-Path $assets ($j.out+".jpg")) 900
        Write-Output ("DONE " + $j.out); $done=$true
      } elseif($st -eq "failed" -or $st -eq "error"){ Write-Output ("FAILED " + $j.out); $done=$true }
    } catch { }
  }
  if(-not $done){ Write-Output ("TIMEOUT " + $j.out) }
}
Write-Output "ALL_DONE"
