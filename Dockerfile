# syntax=docker/dockerfile:1
ARG UE_IMAGE_TAG=dev-slim-5.5.4
# First image is used to build your project inside a container
FROM ghcr.io/epicgames/unreal-engine:${UE_IMAGE_TAG} AS builder

# Expose UDP port (still need to publish!)
EXPOSE 7777/udp

# Copy source code
COPY --chown=ue4:ue4 .. /tmp/project

ARG SERVER_CONFIG
ARG PROJECT_FILE_NAME
ARG UE_BUILD_ARGS

# Build dedicated server for Linux, then drop the Vulkan debug layers (~780 MB) a headless server never loads.
# Cache mounts keep compiled objects and derived data between builds, so later builds only redo what changed.
# UE-LocalDataCachePath is set inline because Docker drops ENV names containing a hyphen.
RUN --mount=type=cache,target=/tmp/project/Intermediate,uid=1000,gid=1000 \
    --mount=type=cache,target=/tmp/project/Binaries,uid=1000,gid=1000 \
    --mount=type=cache,target=/tmp/project/DerivedDataCache,uid=1000,gid=1000 \
    --mount=type=cache,target=/home/ue4/ddc,uid=1000,gid=1000 \
    env UE-LocalDataCachePath=/home/ue4/ddc \
    /home/ue4/UnrealEngine/Engine/Build/BatchFiles/RunUAT.sh BuildCookRun \
    -project=/tmp/project/${PROJECT_FILE_NAME}.uproject \
    -configuration=${SERVER_CONFIG} \
    -build -cook -stage -prereqs -pak -package -archive \
    -utf8output -nodebuginfo -allmaps -noP4 -NoSharedDDC -ddc=noshared -archivedirectory=/tmp/project/Packaged \
    -platform=Linux -server -noclient -SkipCookingEditorContent -FastCook \
    ${UE_BUILD_ARGS} && \
    rm -rf /tmp/project/Packaged/LinuxServer/Engine/Binaries/ThirdParty/Vulkan

# Second image is used to run the project build
FROM ubuntu:22.04 AS runtime

ARG TARGET_FILE_NAME
ENV TARGET_FILE_NAME=${TARGET_FILE_NAME}

# Specify container command for later (main process)
CMD ["/home/ue4/project/StartServer.sh"]

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends jq curl ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create user
RUN useradd ue4
USER ue4

ARG BUILDUTILS_FOLDER
# Copy build and runtime files in the runtime container
COPY --chown=ue4:ue4 ./${BUILDUTILS_FOLDER}/StartServer.sh /home/ue4/project/StartServer.sh
RUN sed -i 's/\r$//' /home/ue4/project/StartServer.sh
COPY --from=builder --chown=ue4:ue4 /tmp/project/Packaged/LinuxServer /home/ue4/project
