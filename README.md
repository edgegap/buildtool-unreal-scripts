# Edgegap Unreal Engine Build Utilities

## Motivation

Building Linux Servers with Unreal Engine no longer requires building Unreal Engine from source!
- faster builds: down from 2.5 hours to 8.5 minutes,
- smaller builds: only includes critical files,
- less bugs: same build environment regardless of your dev machine.

[Refer to our Unreal Engine Getting Started guide for details.](https://docs.edgegap.com/unreal-engine/more-build-methods#scripts-configure-game-builds)

## Faster builds

The first build compiles and cooks everything. Later builds reuse the compiled code, cooked content and derived data cache kept by Docker between builds, so they only redo what changed. Run `docker builder prune` only when you want a clean build.

Settings at the top of `BuildUploadServer.ps1` / `BuildUploadServer.sh`:
- `server_maps`: the maps your server loads, separated by `+` (for example `/Game/Maps/Arena+/Game/Maps/Lobby`). Leave it empty to cook every map; listing only server maps can cut cook time a lot. On Windows, use `BuildUploadServer.ps1` or run the `.sh` script from WSL: Git Bash rewrites arguments starting with `/` into Windows paths.
- `ddc_args`: derived data cache options. The default keeps a local cache in Docker. See [Share a cache with your team](#share-a-cache-with-your-team).

### Windows: give Docker enough memory and CPU

Docker Desktop runs builds in a WSL 2 virtual machine, which gets half of your RAM by default. Unreal runs fewer compile jobs in parallel when memory is low, so builds use fewer cores than you have. Create `%UserProfile%\.wslconfig` with, for example on a 32 GB / 16-core PC:

```ini
[wsl2]
memory=26GB
processors=16
```

Then run `wsl --shutdown` and restart Docker Desktop.

Builds are also faster when the project lives on the WSL file system (for example `\\wsl$\Ubuntu\home\<you>\MyGame`) and you run `BuildUploadServer.sh` from a WSL terminal, because Docker reads Windows drives much more slowly.

### Keep the build context small

Docker sends your project folder to the build on every run. `Dockerfile.dockerignore` already leaves out `.git`, `Saved`, `Intermediate`, `Binaries`, `DerivedDataCache` and `Packaged`. Add any other large folders your server build doesn't need (raw art, recordings, other platforms' builds).

### Share a cache with your team

Studios with several developers or a CI machine can point every build at one shared derived data cache, so shaders and cooked data built once are reused everywhere. Configure an [Unreal Cloud DDC](https://dev.epicgames.com/documentation/en-us/unreal-engine/how-to-set-up-a-cloud-type-derived-data-cache-for-unreal-engine) or Zen server in your project's `DefaultEngine.ini`, then set `ddc_args` to select that cache. The build runs inside Docker, so the cache must be reachable over the network (a mapped Windows drive won't be).
