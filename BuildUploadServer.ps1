# edit these values
$github_pat = '<GITHUB_PERSONAL_ACCESS_TOKEN>'
$github_username = '<GITHUB_USERNAME>'

$ue_image_tag='dev-slim-5.5.4'
$server_config='Development'
$project_file_name='LyraStarterGame'
$target_file_name='LyraServer'
# server maps to cook, separated by '+' (e.g. '/Game/Maps/Arena+/Game/Maps/Lobby'); empty cooks all maps
$server_maps=''
# derived data cache options; replace to use your studio's shared DDC
$ddc_args='-NoSharedDDC -ddc=noshared'

$registry = 'registry.edgegap.com'
$project = '<REGISTRY_PROJECT>'
$username = 'robot$<REGISTRY_ORGANIZATION_ID>+client-push'
$token = '<REGISTRY_TOKEN>'

# leave the rest of the script unchanged
$buildUtilsPath = Get-Location
Set-Location -Path $(Split-Path $PSScriptRoot -Parent)

$dockerVersion = docker --version 2>&1

if ($dockerVersion -match 'not recognized') {
    Write-Error "Docker not installed, visit https://www.docker.com"
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

$dockerContainers = docker ps 2>&1

if ($dockerContainers -match 'error during connect') {
    Write-Error "Docker is not running. Please start Docker and try again."
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

$metadataFilePath = "$buildUtilsPath\package.json"

if (-not (Test-Path -Path $metadataFilePath)) {
    Write-Error "Couldn't find package.json, re-download latest version from https://github.com/edgegap/edgegap-unreal-buildutils"
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

try {
    $localVersion = (Get-Content -Path $metadataFilePath -Raw | ConvertFrom-Json).version

    # Access and print the 'version' property
    if (-not $localVersion) {
        throw 'Version not found.'
    }
} catch {
    Write-Error "Error reading or parsing local package.json: $_"
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

try {
    $response = Invoke-RestMethod `
        -Uri 'https://api.github.com/repos/edgegap/edgegap-unreal-buildutils/releases/latest' `
        -Headers @{
            'Accept'              = 'application/vnd.github+json'
            'X-GitHub-Api-Version'= '2022-11-28'
            'User-Agent'          = 'Powershell'
        } `
        -TimeoutSec 30

    $latestVersion = $response.name

    if (-not $latestVersion) {
        throw 'Version not found.'
    }
} catch {
    Write-Error "Error fetching release information: $_"
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

if ([version]$localVersion -lt [version]$latestVersion) {
    Write-Warning "Update now - new buildutils version is available at https://github.com/edgegap/edgegap-unreal-buildutils"
}

$loginResult = echo "$github_pat" | docker login ghcr.io -u "$github_username" --password-stdin 2>&1

if ($loginResult -match 'unauthorized') {
    Write-Error "Docker GHCR login failed: unauthorized. Please verify your PAT."
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker GHCR login failed: $login_output"
    Read-Host -Prompt "Press Enter to exit"
    exit $LASTEXITCODE
}

Write-Host "Docker GHCR login succeeded!"

docker pull "ghcr.io/epicgames/unreal-engine:$ue_image_tag"

$image = (Split-Path -Leaf $(Get-Location)).ToLower() -replace '\s+','-' -replace '[^a-z0-9-]',''
$tag = (Get-Date -UFormat "%y.%m.%d-%H.%M.%S%Z") -replace '[^a-z0-9-.]+','-'

$loginResult = echo "$token" | docker login $registry -u "$username" --password-stdin 2>&1

if ($loginResult -match 'unauthorized') {
    Write-Error "Docker login failed: unauthorized. Please verify your docker credentials."
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}

if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker login failed: $login_output"
    Read-Host -Prompt "Press Enter to exit"
    exit $LASTEXITCODE
}

Write-Host "Docker $registry login succeeded!"

$arch = & uname -m
$dockerBuildPlatformOption = ""
if ($arch -match '^aarch64$|^arm') {
    $dockerBuildPlatformOption = "--platform linux/amd64"
}

docker build . `
    -f "${buildUtilsPath}\Dockerfile" `
    -t "${registry}/${project}/${image}:${tag}" `
    --build-arg BUILDUTILS_FOLDER=$(Split-Path -Leaf $buildUtilsPath) `
    --build-arg UE_IMAGE_TAG=$ue_image_tag `
    --build-arg SERVER_CONFIG=$server_config `
    --build-arg PROJECT_FILE_NAME=$project_file_name `
    --build-arg TARGET_FILE_NAME=$target_file_name `
    --build-arg "SERVER_MAPS=$server_maps" `
    --build-arg "DDC_ARGS=$ddc_args" `
    $dockerBuildPlatformOption

if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker build failed."
    Read-Host -Prompt "Press Enter to exit"
    exit $LASTEXITCODE
}

docker push "${registry}/${project}/${image}:${tag}"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker push failed."
    Read-Host -Prompt "Press Enter to exit"
    exit $LASTEXITCODE
}

Start-Process "https://app.edgegap.com/application-management/applications/${image}/versions/create?name=${tag}&imageRepo=${project}/${image}&dockerTag=${tag}&vCPU=1&memory=1&utm_source=ue_buildutils&utm_medium=servers_quickstart_script&utm_content=create_version_link"

Read-Host -Prompt "Press Enter to exit"
