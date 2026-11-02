#!/bin/bash

# edit these values
github_pat='<GITHUB_PERSONAL_ACCESS_TOKEN>';
github_username='<GITHUB_USERNAME>';

ue_image_tag='dev-slim-5.5.4';
server_config='Development';
project_file_name='LyraStarterGame';
target_file_name='LyraServer';
# server maps to cook, separated by '+' (e.g. '/Game/Maps/Arena+/Game/Maps/Lobby'); empty cooks all maps
server_maps='';
# derived data cache options; replace to use your studio's shared DDC
ddc_args='-NoSharedDDC -ddc=noshared';

registry='registry.edgegap.com';
project='<REGISTRY_PROJECT>';
username='robot$<REGISTRY_ORGANIZATION_ID>+client-push';
token='<REGISTRY_TOKEN>';

# leave the rest of the script unchanged
if ! command -v jq >/dev/null 2>&1; then
    echo "'jq' is not installed. Installing with apt-get...";
    sudo apt-get update;
    sudo apt-get install -y jq;
    if [ $? -ne 0 ]; then
        echo "Failed to install jq. Please install jq manually and rerun the script.";
        read -p "Press Enter to exit";
        exit 1;
    fi
fi

build_utils_path=$(pwd);
cd ..

if docker ps 2>&1 | grep -Eq "not recognized|could not be found"; then
    echo "Docker not installed or not running, visit https://www.docker.com";
    read -p "Press Enter to exit";
    exit 1;
fi

metadata_file_path="$build_utils_path/package.json"

if [ ! -f "$metadata_file_path" ]; then
    echo "Couldn't find package.json, re-download latest version from https://github.com/edgegap/edgegap-unreal-buildutils";
    read -p "Press Enter to exit";
    exit 1;
fi

local_version=$(jq -r '.version // empty' "$metadata_file_path");

if [ -z "$local_version" ]; then
    echo "Error reading or parsing local package.json: Version not found.";
    read -p "Press Enter to exit";
    exit 1;
fi

response=$( \
    curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -H "User-Agent: Bash" \
        --max-time 30 \
        "https://api.github.com/repos/edgegap/edgegap-unreal-buildutils/releases/latest"
);

latest_version=$(echo "$response" | jq -r '.name // empty');

if [ -z "$latest_version" ]; then
    echo "Error fetching release information or latest version not found.";
    read -p "Press Enter to exit";
    exit 1;
fi

if [ "$local_version" != "$latest_version" ] \
   && [ "$(printf '%s\n' "$local_version" "$latest_version" | sort -V | head -n1)" = "$local_version" ]; then
    echo "Update now - new buildutils version is available at https://github.com/edgegap/edgegap-unreal-buildutils"
fi

login_output=$(echo "$github_pat" | docker login ghcr.io -u "$github_username" --password-stdin 2>&1);

if echo "$login_output" | grep -q "unauthorized"; then
    echo "Docker GHCR login failed: unauthorized. Please verify your PAT.";
    read -p "Press Enter to exit";
    exit 1;
fi

if [ $? -ne 0 ]; then
    echo "Docker GHCR login failed: $login_output";
    read -p "Press Enter to exit";
    exit $?;
fi

echo "Docker GHCR login succeeded!";

docker pull "ghcr.io/epicgames/unreal-engine:$ue_image_tag";

image=$(basename "$PWD" | tr -d '\n' | sed 's/[[:space:]]\+/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g');
tag=$(date +%y.%m.%d-%H.%M.%S-%Z | sed -E 's/[^a-zA-Z0-9.-]+/-/g');

login_output=$(echo "$token" | docker login "$registry" -u "$username" --password-stdin 2>&1);

if echo "$login_output" | grep -q "unauthorized"; then
    echo "Docker $registry login failed: unauthorized. Please verify your docker credentials.";
    read -p "Press Enter to exit";
    exit 1;
fi

if [ $? -ne 0 ]; then
    echo "Docker $registry login failed: $login_output";
    read -p "Press Enter to exit";
    exit $?;
fi

echo "Docker $registry login succeeded!";

arch=$(uname -m)
docker_build_platform_option=""
if [[ "$arch" =~ ^aarch64$|^arm ]]; then
    docker_build_platform_option="--platform linux/amd64"
fi

docker build . \
    -f "$build_utils_path/Dockerfile" \
    -t "${registry}/${project}/${image}:${tag}" \
    --build-arg BUILDUTILS_FOLDER=$(basename "$build_utils_path") \
    --build-arg UE_IMAGE_TAG=$ue_image_tag \
    --build-arg SERVER_CONFIG=$server_config \
    --build-arg PROJECT_FILE_NAME=$project_file_name \
    --build-arg TARGET_FILE_NAME=$target_file_name \
    --build-arg "SERVER_MAPS=$server_maps" \
    --build-arg "DDC_ARGS=$ddc_args" \
    $docker_build_platform_option;

if [ $? -ne 0 ]; then
    echo "Docker build failed.";
    read -p "Press Enter to exit";
    exit $?;
fi

docker push "${registry}/${project}/${image}:${tag}";

if [ $? -ne 0 ]; then
    echo "Docker push failed.";
    read -p "Press Enter to exit";
    exit $?;
fi

app_version_url="https://app.edgegap.com/application-management/applications/${image}/versions/create?name=${tag}&imageRepo=${project}/${image}&dockerTag=${tag}&vCPU=1&memory=1&utm_source=ue_buildutils&utm_medium=servers_quickstart_script&utm_content=create_version_link";

if [[ $arch == "Darwin" ]]; then
    open "$app_version_url";
elif grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null ; then
    powershell.exe -NoProfile -Command "Start-Process '$app_version_url'"
else
    xdg-open "$app_version_url";
fi

read -p "Press Enter to exit";
