# GitHub Support cleanup checklist

This source revision removes hard-coded direct download URLs for ZIP/executable/DLL payloads and executable scripts from repository text files. Project-owned release assets are resolved through the GitHub release API instead of literal asset URLs, while prerequisites that should not be rehosted are selected locally by the user.

## Repository changes

- ReShade: repository/installer links only to the ReShade GitHub project page; the user follows the project website shown in GitHub's About box and selects the official 6.8.0 full add-on-support setup locally.
- FusionFix: when missing, the user downloads the official 5.0.1 ZIP from the project's GitHub Releases UI; our installer validates/extracts it and asks for one normal GTA IV first run.
- LumeniteFX: user obtains the official pinned source archive from the author's repository and selects it locally.
- Neural Rendering: no direct download link is provided. The installer opens only `RankFTW/rhi-repo` on GitHub, tells users to click Releases and navigate older pages with Next until the pinned tag is found, then validates the selected ZIP and extracted DLL by GPU-specific SHA256; RTX 50 also requires a valid NVIDIA signature.
- DLSS 4.5 / DLAA: `nvngx_dlss.dll` 310.9.1 is sourced from NVIDIA's official DLSS SDK for the project-owned runtime payload.
- Redistributable/open-source runtime pieces are assembled into the project-owned runtime payload by the cleaned runtime workflow.

## Local verification

Run from PowerShell at the repository root:

```powershell
.\tools\Verify-No-External-Binary-Links.ps1
.\tools\Verify-GitHub-Only-Links.ps1
```

Expected result:

```text
PASS: no hard-coded direct ZIP/EXE/DLL/archive/executable-script download URLs were found in repository text files.
PASS: every HTTP/HTTPS hyperlink in repository text points to GitHub/GitHub-owned content hosts.
```

## Items outside the Git tree

GitHub Support also asked that the same type of link be removed from GitHub-hosted metadata that is not present in a source archive. Before replying to Support, manually check:

- current release notes;
- repository About/description fields;
- open and closed issues;
- pull requests and comments;
- profile README/bio if applicable.

Only GitHub-hosted navigation/documentation links are retained. No repository hyperlink points to a non-GitHub site, and no third-party direct binary/archive asset URL is stored.

## Existing v1.0.0 tag / release source snapshot

The existing `v1.0.0` tag was created before this cleanup. If that tag still points to the old commit, GitHub's automatically generated **Source code (zip)** and **Source code (tar.gz)** for that release will still contain the old repository files.

Before confirming cleanup to GitHub Support, make sure the old tagged source is no longer an exposed copy of the pre-cleanup repository. The cleanest choices are to delete/recreate the release/tag at the cleaned commit or otherwise replace the old release/tag according to your release policy. Recheck the release notes and generated source downloads afterward.

## Release rebuild requirement

The cleaned DLAA installer expects an expanded `GTAIV-DLSS-Full-Runtime.zip` containing the redistributable components listed in `manifests/versions.json`. The existing pre-cleanup runtime asset does not contain all of those files. Rebuild and replace the project-owned runtime asset before publishing the rebuilt setup executable.
