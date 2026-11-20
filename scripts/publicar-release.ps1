<#
.SYNOPSIS
    Empacota bancos SQLite (.db) em .db.gz, atualiza o catalog-index.json mantendo
    apenas o mes vigente e os ultimos 6 meses, e opcionalmente publica na Release do GitHub.

.EXAMPLE
    .\scripts\publicar-release.ps1 -Source sinapi -Period 2026-10
    .\scripts\publicar-release.ps1 -Source sinapi -Period 2026-10 -Publish
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d{4}-\d{2}$')]
    [string]$Period,

    [string]$InputDir = "",
    [switch]$Publish
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$RepoSlug = "alecrimheitor-del/KAIROS-BASES"
$SourceUpper = $Source.Trim().ToUpper()
$SourceLower = $Source.Trim().ToLower()
$TagName = "$SourceLower-$Period"

if ([string]::IsNullOrWhiteSpace($InputDir)) {
    $Docs = [Environment]::GetFolderPath("MyDocuments")
    $InputDir = Join-Path $Docs "Kairos\Bases_de_Dados\$SourceUpper"
}

if (-not (Test-Path $InputDir)) {
    throw "Pasta de entrada nao encontrada: $InputDir"
}

# Calcular janela movel: mes vigente + 6 meses anteriores (total de 7 competencias)
$Now = Get-Date
$CurrentMonthStart = Get-Date -Year $Now.Year -Month $Now.Month -Day 1
$ActiveWindow = @()
for ($i = 6; $i -ge 0; $i--) {
    $ActiveWindow += $CurrentMonthStart.AddMonths(-$i).ToString("yyyy-MM")
}

if ($ActiveWindow -notcontains $Period) {
    Write-Warning "A competencia $Period esta fora da janela padrao ($($ActiveWindow[0]) a $($ActiveWindow[-1]))."
}

$OutDir = Join-Path $RepoRoot "dist_releases\$TagName"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# Compactar arquivos .db correspondentes para .db.gz usando .NET nativo
$Pattern = "${SourceUpper}_*_${Period}_*.db"
$DbFiles = Get-ChildItem -Path $InputDir -Filter $Pattern -File

if ($DbFiles.Count -eq 0) {
    throw "Nenhum arquivo correspondente a '$Pattern' encontrado em $InputDir"
}

$AssetsMeta = @()

foreach ($DbFile in $DbFiles) {
    $GzName = "$($DbFile.Name).gz"
    $GzPath = Join-Path $OutDir $GzName

    $InStream = [System.IO.File]::OpenRead($DbFile.FullName)
    try {
        $OutStream = [System.IO.File]::Create($GzPath)
        try {
            $GzipStream = New-Object System.IO.Compression.GzipStream($OutStream, [System.IO.Compression.CompressionLevel]::Optimal)
            try {
                $InStream.CopyTo($GzipStream)
            }
            finally {
                $GzipStream.Dispose()
            }
        }
        finally {
            $OutStream.Dispose()
        }
    }
    finally {
        $InStream.Dispose()
    }

    $GzItem = Get-Item $GzPath
    $Sha256 = (Get-FileHash -Path $GzPath -Algorithm SHA256).Hash.ToLower()

    # Extrair UF e Regime do padrao SOURCE_UF_YYYY-MM_REGIME.db
    $BaseParts = $DbFile.BaseName.Split('_')
    $Uf = if ($BaseParts.Length -ge 2) { $BaseParts[1] } else { "SP" }
    $RegimeCode = if ($BaseParts.Length -ge 4) { $BaseParts[3] } else { "SD" }
    $TaxRegime = if ($RegimeCode -eq "CD") { "desonerado" } else { "nao-desonerado" }

    $AssetsMeta += [ordered]@{
        uf                = $Uf
        regimeCode        = $RegimeCode
        taxRegime         = $TaxRegime
        fileName          = $GzName
        downloadUrl       = "https://github.com/$RepoSlug/releases/download/$TagName/$GzName"
        compressedBytes   = $GzItem.Length
        uncompressedBytes = $DbFile.Length
        sha256            = $Sha256
    }

    $Ratio = [math]::Round((1 - ($GzItem.Length / [math]::Max(1, $DbFile.Length))) * 100, 1)
    Write-Host "Compactado: $GzName ($([math]::Round($GzItem.Length / 1MB, 2)) MB, reducao de $Ratio%)" -ForegroundColor Green
}

# Atualizar catalog-index.json aplicando janela dos ultimos 6 meses + mes vigente
$IndexPath = Join-Path $RepoRoot "catalog-index.json"
$IndexData = Get-Content -Path $IndexPath -Raw -Encoding UTF8 | ConvertFrom-Json

$RemainingReleases = @()
$ExpiredTags = @()

foreach ($Rel in $IndexData.releases) {
    if ($Rel.tag -eq $TagName) {
        continue
    }
    if ($ActiveWindow -contains $Rel.period) {
        $RemainingReleases += $Rel
    }
    else {
        $ExpiredTags += $Rel.tag
    }
}

$NewReleaseEntry = [ordered]@{
    tag         = $TagName
    source      = $SourceLower
    period      = $Period
    publishedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    assets      = @($AssetsMeta)
}

[object[]]$AllReleases = @((@($NewReleaseEntry) + @($RemainingReleases)) | Sort-Object -Property period, source -Descending)

$UpdatedIndex = [ordered]@{
    schemaVersion      = "1.0"
    repository         = $RepoSlug
    updatedAt          = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    retentionPolicy    = [ordered]@{
        currentMonthPlusPreviousMonths = 6
        maxActiveMonths                = 7
        activeWindow                   = @($ActiveWindow)
        fallbackRule                   = "Competencias anteriores a janela de 6 meses devem ser importadas localmente no Kairos via Pasta Monitorada ou Importar Arquivo."
    }
    namingConvention   = $IndexData.namingConvention
    releases           = @($AllReleases)
}

$JsonText = $UpdatedIndex | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($IndexPath, $JsonText + "`n", (New-Object System.Text.UTF8Encoding($false)))

Write-Host "`ncatalog-index.json atualizado com sucesso!" -ForegroundColor Cyan
Write-Host "Pasta pronta para upload na Release '$TagName': $OutDir" -ForegroundColor Yellow

if ($ExpiredTags.Count -gt 0) {
    Write-Host "Releases expiradas (> 6 meses) removidas do indice: $($ExpiredTags -join ', ')" -ForegroundColor DarkYellow
}

if ($Publish) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI ('gh') nao encontrado. Instale com 'winget install GitHub.cli' ou suba os arquivos manualmente pela interface web."
    }

    $GzFilesToUpload = (Get-ChildItem -Path $OutDir -Filter "*.db.gz").FullName

    # Verifica se release ja existe
    $Exists = $false
    try {
        gh release view $TagName --repo $RepoSlug *> $null
        if ($LASTEXITCODE -eq 0) { $Exists = $true }
    }
    catch { $Exists = $false }

    if ($Exists) {
        Write-Host "Atualizando assets da release existente $TagName..."
        gh release upload $TagName @GzFilesToUpload --repo $RepoSlug --clobber
    }
    else {
        Write-Host "Criando release $TagName..."
        gh release create $TagName @GzFilesToUpload --repo $RepoSlug --title "$SourceUpper $Period" --notes "Base $SourceUpper competencia $Period empacotada para o Kairos."
    }

    foreach ($OldTag in $ExpiredTags) {
        Write-Host "Removendo release expirada (> 6 meses): $OldTag"
        gh release delete $OldTag --repo $RepoSlug --yes --cleanup-tag
    }

    Push-Location $RepoRoot
    try {
        git add catalog-index.json
        git commit -m "chore(catalog): publica $TagName e aplica retencao de 6 meses"
        git push
    }
    finally {
        Pop-Location
    }
}
