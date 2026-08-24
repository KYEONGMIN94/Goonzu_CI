# Release boundary

CI produces evidence; release changes external state. Keep them as separate jobs and permissions.

## Client release

1. Select an archived `Client\Goonzu_Client.exe` by Jenkins build number and commit SHA.
2. Compare its SHA-256 with `artifacts\meta\artifact-manifest.tsv`.
3. Assemble an isolated runtime copy. Do not replace the normal local client yet.
4. Have the user perform the final login, world-entry, and feature-specific acceptance checks.
5. After approval, run the separate publish script with the expected hash:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Publish-Client.ps1 `
     -ArtifactPath <archived-client-exe> `
     -Destination <approved-release-share> `
     -ExpectedSha256 <manifest-sha256> `
     -Approved
   ```

## Server release

Server release automation is intentionally not enabled by this repository. Before enabling it, provide:

- a versioned deployment manifest mapping every process to its runtime destination;
- baseline and post-copy SHA-256 collection;
- atomic backup/rollback for all selected executables;
- an explicit human approval gate;
- a rule that the user runs `start.bat` and owns runtime verification;
- readiness evidence for all seven processes, DB initialization `select=0..4, step=2`, and port `4010`.

Do not infer deployment approval from a successful build or merge.
