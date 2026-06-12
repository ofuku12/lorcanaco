
$ErrorActionPreference = "Stop"
$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$pages = @(
  "https://www.lorhappy.com/view/category/ct8?page=1&sort=price_high",
  "https://www.lorhappy.com/view/category/ct8?page=2&sort=price_high"
)
$imgDir = Join-Path $base "images\promo"
New-Item -ItemType Directory -Force -Path $imgDir | Out-Null
$cards = Get-Content (Join-Path $base "promo_cards.json") -Raw -Encoding UTF8 | ConvertFrom-Json
function Normalize([string]$s){
  if($null -eq $s){ return "" }
  $s = [System.Net.WebUtility]::HtmlDecode($s)
  $s = $s -replace "[\s　\-－―ー・/／:：,，\[\]（）()【】『』「」'`"’“”！!？?]", ""
  $s = $s.ToLowerInvariant()
  return $s
}
function SafeName([string]$s){ return ($s -replace '[\\/:*?"<>|]', '_') }
function AbsUrl([string]$u){
  if([string]::IsNullOrWhiteSpace($u)){ return "" }
  $u = [System.Net.WebUtility]::HtmlDecode($u)
  if($u.StartsWith("//")){ return "https:" + $u }
  if($u.StartsWith("/")){ return "https://www.lorhappy.com" + $u }
  return $u
}
$products = @()
foreach($url in $pages){
  Write-Host "取得中: $url"
  $html = (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
  $html = $html -replace "`r|`n", " "
  $blocks = [regex]::Matches($html, '<a[^>]+href=["''](?<href>[^"'']+)["''][^>]*>.*?</a>', 'IgnoreCase')
  foreach($b in $blocks){
    $chunk = $b.Value
    if($chunk -notmatch '<img'){ continue }
    $href = AbsUrl $b.Groups['href'].Value
    $img = ""
    $m = [regex]::Match($chunk, '<img[^>]+(?:data-original|data-src|src)=["''](?<src>[^"'']+)["''][^>]*>', 'IgnoreCase')
    if($m.Success){ $img = AbsUrl $m.Groups['src'].Value }
    $text = [regex]::Replace($chunk, '<[^>]+>', ' ')
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    if($img -and $href){ $products += [pscustomobject]@{ text=$text; href=$href; img=$img } }
  }
}
# remove duplicate products
$products = $products | Sort-Object href,img -Unique
Write-Host "商品候補: $($products.Count) 件"
$map = @{}
$matched = 0
foreach($card in $cards){
  $cn = Normalize $card.name
  $code = Normalize $card.code
  $best = $null; $bestScore = 0
  foreach($p in $products){
    $tn = Normalize $p.text
    $score = 0
    if($tn.Contains($cn) -or $cn.Contains($tn)){ $score += 100 }
    # split name around hyphen-like separators from original card name
    $parts = ($card.name -split '[-－―ー–—]') | Where-Object { $_.Trim().Length -ge 2 }
    foreach($part in $parts){ if($tn.Contains((Normalize $part))){ $score += 35 } }
    if($code -and $tn.Contains($code)){ $score += 80 }
    if($score -gt $bestScore){ $bestScore=$score; $best=$p }
  }
  if($best -and $bestScore -ge 35){
    $ext = [IO.Path]::GetExtension(($best.img -split '\?')[0])
    if([string]::IsNullOrWhiteSpace($ext)){ $ext = ".jpg" }
    $file = (SafeName $card.id) + $ext
    $path = Join-Path $imgDir $file
    try{
      Invoke-WebRequest -Uri $best.img -OutFile $path -UseBasicParsing
      $map[$card.id] = "images/promo/$file"
      $matched++
      Write-Host "OK: $($card.name)"
    } catch { Write-Host "画像保存失敗: $($card.name)" }
  } else {
    Write-Host "未一致: $($card.name)"
  }
}
$json = ($map | ConvertTo-Json -Depth 5 -Compress)
if([string]::IsNullOrWhiteSpace($json)){ $json = "{}" }
Set-Content -Path (Join-Path $base "promo_images.js") -Value ("const PROMO_IMAGES=" + $json + ";") -Encoding UTF8
Write-Host "完了: $matched / $($cards.Count) 枚のプロモ画像を設定しました。"
Write-Host "index.html を開き直してください。"
