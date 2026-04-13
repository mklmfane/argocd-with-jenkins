$ErrorActionPreference = "Stop"

# Replace with your real Windows IPv4 address from ipconfig
$HarborEndpoint = "127.0.0.1:8085"

$HarborProject  = "library"
$HarborUser     = "admin"
$HarborPassword = "Harbor12345"

$WorkDir = $PWD.Path
$TarDir  = Join-Path $WorkDir "harbor-transfer"

New-Item -ItemType Directory -Force -Path $TarDir | Out-Null

# Keep this running in another terminal:
# kubectl port-forward -n harbor --address 0.0.0.0 svc/harbor 8085:8085

$ExcludePatterns = @(
  '^<none>:<none>$',
  '^docker/desktop-',
  '^docker/desktop',
  '^docker\.io/docker/desktop',
  '^kindest/node:',
  '^mcp/',
  '^hubproxy\.docker\.internal',
  '^registry\.k8s\.io/',
  '^quay\.io/prometheus-operator/',
  '^quay\.io/prometheus/',
  '^yonahdissen/kor:',
  '^127\.0\.0\.1:8085/',
  '^host\.docker\.internal:8085/'
)

function Get-BasicAuthHeader {
  param(
    [string]$User,
    [string]$Password
  )

  $pair    = "${User}:${Password}"
  $bytes   = [System.Text.Encoding]::ASCII.GetBytes($pair)
  $encoded = [Convert]::ToBase64String($bytes)

  return @{ Authorization = "Basic $encoded" }
}

function Test-HarborApi {
  param(
    [string]$Endpoint,
    [hashtable]$Headers
  )

  try {
    $null = Invoke-RestMethod `
      -Method Get `
      -Uri "http://$Endpoint/api/v2.0/projects?page=1&page_size=1" `
      -Headers $Headers `
      -TimeoutSec 20
    return $true
  }
  catch {
    return $false
  }
}

function Ensure-HarborProject {
  param(
    [string]$Endpoint,
    [string]$Project,
    [hashtable]$Headers
  )

  $encodedProject = [System.Uri]::EscapeDataString($Project)
  $projectUri     = "http://$Endpoint/api/v2.0/projects/$encodedProject"

  try {
    $null = Invoke-RestMethod `
      -Method Get `
      -Uri $projectUri `
      -Headers $Headers `
      -TimeoutSec 20

    Write-Host "Harbor project already exists: $Project"
    return
  }
  catch {
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode.Value__ -ne 404) {
      throw
    }
  }

  Write-Host "Creating Harbor project: $Project"

  $body = @{
    project_name = $Project
    public       = $true
  } | ConvertTo-Json

  Invoke-RestMethod `
    -Method Post `
    -Uri "http://$Endpoint/api/v2.0/projects" `
    -Headers $Headers `
    -ContentType "application/json" `
    -Body $body `
    -TimeoutSec 20 | Out-Null
}

function Test-LocalImage {
  param(
    [string]$ImageRef
  )

  $oldPreference = $ErrorActionPreference
  try {
    $script:ErrorActionPreference = "Continue"
    cmd /c "docker image inspect ""$ImageRef"" >nul 2>nul"
    return ($LASTEXITCODE -eq 0)
  }
  finally {
    $script:ErrorActionPreference = $oldPreference
  }
}

function Should-ExcludeImage {
  param(
    [string]$ImageRef,
    [string[]]$Patterns
  )

  if ([string]::IsNullOrWhiteSpace($ImageRef)) {
    return $true
  }

  foreach ($pattern in $Patterns) {
    if ($ImageRef -match $pattern) {
      return $true
    }
  }

  return $false
}

function Normalize-RepoName {
  param(
    [string]$ImageRef,
    [string]$Project
  )

  $namePart = $ImageRef
  $tagPart  = "latest"

  if ($ImageRef -match '^(.*):([^/:]+)$') {
    $namePart = $matches[1]
    $tagPart  = $matches[2]
  }

  $parts = $namePart.Split('/')

  # Remove registry hostname prefix if present
  if ($parts.Count -ge 2 -and ($parts[0] -match '\.' -or $parts[0] -match ':')) {
    $namePart = ($parts[1..($parts.Count - 1)] -join '/')
  }

  $namePart = $namePart.ToLowerInvariant()
  $tagPart  = $tagPart.ToLowerInvariant()

  return @{
    RepoTag = "$Project/$namePart`:$tagPart"
  }
}

function Save-ImageArchive {
  param(
    [string]$SourceImage,
    [string]$TarPath
  )

  if (Test-Path $TarPath) {
    Remove-Item -Force $TarPath
  }

  Write-Host "Saving    : $SourceImage -> $TarPath"
  & docker save $SourceImage -o $TarPath

  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $TarPath)) {
    throw "docker save failed for $SourceImage"
  }
}

function Copy-ArchiveToHarbor {
  param(
    [string]$TarDirOnHost,
    [string]$SafeTarName,
    [string]$Endpoint,
    [string]$DestinationRepo,
    [string]$User,
    [string]$Password
  )

  Write-Host "Importing : $SafeTarName -> $Endpoint/$DestinationRepo"

  $output = & docker run --rm `
    -v "${TarDirOnHost}:/work/harbor-transfer" `
    quay.io/skopeo/stable:latest `
    copy `
    --retry-times 3 `
    --dest-tls-verify=false `
    --dest-creds "${User}:${Password}" `
    "docker-archive:/work/harbor-transfer/$SafeTarName" `
    "docker://$Endpoint/$DestinationRepo" 2>&1

  $rc = $LASTEXITCODE

  if ($output) {
    $output | ForEach-Object { Write-Host $_ }
  }

  return $rc
}

$headers = Get-BasicAuthHeader -User $HarborUser -Password $HarborPassword

if (-not (Test-HarborApi -Endpoint $HarborEndpoint -Headers $headers)) {
  Write-Error "Harbor API is not reachable at http://$HarborEndpoint . Keep this running in another terminal: kubectl port-forward -n harbor --address 0.0.0.0 svc/harbor 8085:8085"
  exit 1
}

Ensure-HarborProject -Endpoint $HarborEndpoint -Project $HarborProject -Headers $headers

$rawImages = docker image ls --format "{{.Repository}}:{{.Tag}}" |
  ForEach-Object { $_.Trim() } |
  Sort-Object -Unique

$images = @()

foreach ($img in $rawImages) {
  if (Should-ExcludeImage -ImageRef $img -Patterns $ExcludePatterns) {
    continue
  }

  if (-not (Test-LocalImage -ImageRef $img)) {
    Write-Warning "Skipping missing local image: $img"
    continue
  }

  $images += $img
}

if (-not $images -or $images.Count -eq 0) {
  Write-Error "No valid local Docker images found to import."
  exit 1
}

Write-Host ""
Write-Host "Images selected for import:"
$images | ForEach-Object { Write-Host " - $_" }

$results = @()

foreach ($src in $images) {
  Write-Host ""
  Write-Host "Processing: $src"

  if (-not (Test-LocalImage -ImageRef $src)) {
    Write-Warning "Skipping missing local image: $src"
    continue
  }

  try {
    $repoInfo = Normalize-RepoName -ImageRef $src -Project $HarborProject
    $destRepo = $repoInfo.RepoTag

    $safeName = ($src -replace '[/:@]', '_') + ".tar"
    $tarPath  = Join-Path $TarDir $safeName

    Save-ImageArchive -SourceImage $src -TarPath $tarPath

    $rc = Copy-ArchiveToHarbor `
      -TarDirOnHost $TarDir `
      -SafeTarName $safeName `
      -Endpoint $HarborEndpoint `
      -DestinationRepo $destRepo `
      -User $HarborUser `
      -Password $HarborPassword

    if ($rc -eq 0) {
      Write-Host "OK: $src"
      $results += [PSCustomObject]@{
        Image  = $src
        Status = "OK"
        Reason = ""
      }
    }
    else {
      Write-Warning "FAILED: $src"
      $results += [PSCustomObject]@{
        Image  = $src
        Status = "FAILED"
        Reason = "skopeo copy exit code $rc"
      }
    }
  }
  catch {
    Write-Warning "FAILED: $src"
    Write-Warning $_.Exception.Message
    $results += [PSCustomObject]@{
      Image  = $src
      Status = "FAILED"
      Reason = $_.Exception.Message
    }
  }
}

Write-Host ""
Write-Host "Import summary:"
$results | Format-Table -AutoSize

$failed = $results | Where-Object { $_.Status -eq "FAILED" }
if ($failed) {
  exit 1
}