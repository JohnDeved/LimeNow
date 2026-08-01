# GitHub CLI persistence and security

LimeNow installs the official Windows AMD64 GitHub CLI release beneath
`I:\Apps\LimeNow\GitHubCLI`. The release URL and SHA-256 digest are pinned in
`setup.ps1`; LimeNow verifies the archive before extracting or executing it.

## Persistent layout

- executable: `I:\Apps\LimeNow\GitHubCLI\bin\gh.exe`
- managed command wrapper: `I:\Apps\LimeNow\GitHubCLI\gh.cmd`
- sign-in launcher: `I:\Apps\LimeNow\GitHubCLI\GitHub-CLI-Sign-In.cmd`
- sign-in flow: `I:\Apps\LimeNow\GitHubCLI\GitHub-CLI-Sign-In.ps1`
- configuration and authentication: `I:\Apps\LimeNow\GitHubCLI\Config`
- reusable OAuth token: `I:\Apps\LimeNow\GitHubCLI\Config\hosts.yml`

The managed wrapper sets [`GH_CONFIG_DIR`](https://cli.github.com/manual/gh_help_environment)
before every command. LimeNow also
sets that variable for the current process and user environment and configures
Git for Windows to use `gh auth git-credential` with the same explicit
persistent directory. This avoids relying on the temporary GFN profile.

## Sign in from a phone or local computer

The **GitHub CLI Sign In** shortcut opens a terminal window, not a GeForce NOW
browser. It renders an offline QR that contains only GitHub's public device URL,
`https://github.com/login/device`. Scan it with a phone, or open the displayed
URL in a browser on the local computer. GitHub CLI then displays its
8-character, one-time device code in the GFN terminal; enter that code on the
other device and authorize the GitHub CLI application there.

New sign-ins request GitHub's `workflow` OAuth scope in addition to GitHub
CLI's standard scopes. This is required when Git pushes a commit that creates
or changes a file under `.github/workflows`. If an existing persistent sign-in
lacks that scope, the shortcut detects the non-secret scope metadata and starts
the same QR device flow with `gh auth refresh` to request it.

LimeNow redirects standard input for the pinned `gh auth login --web` command.
That selects GitHub CLI's non-interactive device-flow branch, which prints the
code and begins polling without opening a browser or waiting for another Enter
key. A no-op `GH_BROWSER` override is also set as a safeguard. The QR is stored
in the launcher and rendered locally, so sign-in does not depend on or disclose
data to a third-party QR service. The one-time code is generated and handled by
GitHub CLI and GitHub's documented
[OAuth device flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow).

## Why sign-in uses plaintext storage

By default, GitHub CLI prefers the Windows credential store. That store belongs
to the temporary GFN machine and does not follow the SalsaNOW persistent drive
to a replacement machine. The **GitHub CLI Sign In** shortcut therefore uses:

```text
'' | gh auth login --hostname github.com --git-protocol https --web --scopes workflow --clipboard --insecure-storage
```

GitHub CLI's [`--insecure-storage`](https://cli.github.com/manual/gh_auth_login)
option writes the OAuth token into its config file instead of the Windows
credential store. This is required for the requested cross-machine persistence,
but it makes `hosts.yml` a reusable secret.

## Protections and trust boundary

LimeNow never reads, parses, prints, or copies the token. It points GitHub CLI
directly at the persistent config directory. On every setup run, LimeNow applies
a current-user-and-SYSTEM-only ACL to the directory and its existing contents.
New authentication files inherit that restriction where the SalsaNOW storage
filesystem supports Windows ACLs. Setup logs only whether authentication could
be verified, never credential content.

The SalsaNOW persistent store remains the outer trust boundary. Anyone who can
read or replace that storage may be able to steal the token, modify the `gh`
binary or wrapper, or act with the token's GitHub permissions. Do not enable
persistent sign-in on storage you do not trust.

## Sign-out and revocation

Run `gh auth logout --hostname github.com` through LimeNow's managed `gh`
command to remove the persistent local authentication entry. GitHub CLI logout
does not revoke the OAuth token at GitHub. To invalidate it fully, revoke the
**GitHub CLI** authorization from GitHub's application settings:

<https://github.com/settings/applications>

After revocation, use the desktop sign-in shortcut if you want to authorize a
new persistent token.
