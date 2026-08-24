# Jenkins Freestyle transition

The current Jenkins 2.60.1 installation does not provide the Pipeline runtime required by `Jenkinsfile`. Until a maintained controller is available, a Freestyle job can call the same reviewed scripts without changing the build contract.

## Job inputs

- `SOURCE_BRANCH`, default `master`
- `BASE_REVISION`, default `origin/master`
- `BUILD_TARGET`, default `Auto`; the temporary override may be `All`

## Workspace layout

The job workspace must contain the checked-out `Goonzu_CI` repository at its root and a clean `Goonzu_Build` checkout at `src`. Generated files are limited to `build` and `artifacts`.

Do not place the workspace under any of these roots:

- `C:\GoonZuWorld`
- `C:\GoonzuWorld`
- `C:\ServerAgent`
- `C:\GoonZuWorldServer`
- `D:\GoonZuWorld`

## Build steps

1. Clean only the job's `src`, `build`, and `artifacts` directories.
2. Clone or fetch `https://github.com/KYEONGMIN94/Goonzu_Build.git` into `src`, then checkout the requested branch.
3. Run environment validation:

   ```bat
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WORKSPACE%\scripts\Test-BuildEnvironment.ps1" -SourceRoot "%WORKSPACE%\src" -DevenvPath "C:\Program Files (x86)\Microsoft Visual Studio .NET 2003\Common7\IDE\devenv.com"
   ```

4. Run preflight:

   ```bat
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WORKSPACE%\scripts\Invoke-Preflight.ps1" -SourceRoot "%WORKSPACE%\src" -BaseRevision "%BASE_REVISION%" -OutputDirectory "%WORKSPACE%\artifacts\meta" -RequireClean
   ```

5. Read `artifacts\meta\impact.properties`. Use its `BuildTarget` unless the approved job parameter forces `All`. If it is `None`, archive metadata and finish successfully.
6. Prepare isolation with `Prepare-IsolatedBuild.ps1`.
7. Build with `Invoke-GoonzuBuild.ps1`.
8. Archive `artifacts\**\*` with fingerprints.

The Freestyle job must not call `Publish-Client.ps1`, copy to a runtime share, control VMware, or launch the game client.

## Migration completion

The Pipeline migration is complete only after a test job proves:

- exact source commit recording;
- clean checkout enforcement;
- all eight configured build rows can produce artifacts;
- isolation audit contains only workspace paths;
- archived hashes match downloaded artifacts;
- no live runtime file timestamp or hash changed.
