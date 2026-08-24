# Goonzu CI working rules

- Use GPT-5.6 Terra with `low` reasoning by default. Project config sets only new-task defaults; an explicit active-chat selection takes precedence.
- Keep all scripts compatible with Windows PowerShell 2.0 and .NET available on the legacy build worker unless the documented worker baseline changes.
- CI may read source, rewrite only its disposable checkout, build, hash, and archive artifacts.
- CI must never launch or control the Goonzu client, start or stop the server VM, deploy to a live path, or publish by default.
- Every build output, intermediate directory, linker output, and PDB path must resolve under the Jenkins staging root before `devenv.com` runs.
- Treat `C:\GoonZuWorld`, `C:\GoonzuWorld`, `C:\ServerAgent`, `C:\GoonZuWorldServer`, and `D:\GoonZuWorld` as prohibited build-output roots.
- Keep releases separate and require explicit human approval plus an expected SHA-256.
- Do not claim the seven-process server suite is built unless all entries in `config/build-targets.csv` for `ServerSuite` succeeded.
