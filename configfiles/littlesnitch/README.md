# Little Snitch — unattended install and template configuration

## What is automated, and what is not

| Prompt | Handled by | Fully unattended? |
|---|---|---|
| Licence agreement, "install now" | `defaults write at.obdev.littlesnitch …` in `setup-user.sh` | Yes |
| Welcome tour on first run | `LastShownWelcomeWindowVersion` | Yes |
| Network extension + content filter approval | `LittleSnitch.mobileconfig` pushed from **MDM** | Only on a supervised, MDM-enrolled Mac |
| Licence key, rules, settings | `LittleSnitchMassDeploymentConfiguration.json` (LS 6) or `littlesnitch restore-model` (LS 5 and 6) | Yes on a clean LS 6 machine |

The extension approval is the hard limit. macOS will not let a script approve a
network system extension on its own — that is Apple's policy, not Little
Snitch's. Without MDM, someone clicks through System Settings once per machine
and everything else still runs unattended.

## Producing the template

1. Install Little Snitch by hand on one Mac and configure it the way you want
   the fleet to look.
2. Turn on **Little Snitch > Settings > Security > Allow access via Terminal**
   so later changes can be scripted.
3. **File > Create Backup…** — this writes a `.lsbackup` file, which despite
   the extension is plain JSON. Review it in an editor.

Then use it in one or both of these ways:

### A. Mass deployment (Little Snitch 6, macOS 14+) — preferred

Add two top-level keys to the exported JSON and save it as
`LittleSnitchMassDeploymentConfiguration.json` in this directory:

```json
"massDeploymentLicenseKey":   "36123456789-715P8-0123456789",
"massDeploymentLicenseOwner": "Your Organisation"
```

`setup-system.sh` stages it to `/var/root/` during the root phase.
Little Snitch reads it on its very first launch, applies it as a restore, and
then **deletes** it (it holds the licence key).

See `LittleSnitchMassDeploymentConfiguration.json.example` for a minimal shape.
The file is gitignored because of the licence key — if this repo is private and
you want it in the deployment payload, commit it deliberately:

```
git add -f configfiles/littlesnitch/LittleSnitchMassDeploymentConfiguration.json
```

This mechanism only works on a machine where Little Snitch has never run.
Little Snitch ignores the file if the network extension is already active or if
`/Library/Application Support/Objective Development/Little Snitch` exists —
deliberate anti-tampering. To retest, drag the app to the Trash via **Finder**
(that is what removes the extension — `rm` does not), then
`sudo rm -rf '/Library/Application Support/Objective Development/Little Snitch'`.

### B. restore-model (works on Little Snitch 5 and 6)

Drop the exported backup here as `template.lsbackup`. `setup-user.sh` applies it
with `littlesnitch restore-model` after installing the app. This is the path
used on macOS 11–13 (`little-snitch@5`, which has no mass deployment support),
on re-runs, and on any machine where the mass deployment window had closed.

It requires Terminal access to be enabled — which the mass deployment config
sets via `"allowCommandLineAccess": 1`, but which has to be switched on by hand
once on a machine that never got one.

Note that `restore-model` carries user-specific settings keyed by numeric UID.
Strip `"users"` to `[]` in the template so everyone gets the defaults, or map
them explicitly with `restore-model --map-users "501 > 502"`.

## Updating rules later

Rules are baked into the template and shipped with the repo — there is no
server in the loop. To change them:

1. Edit the rules on your reference Mac.
2. **File > Create Backup…** again.
3. Replace `template.lsbackup` here (and regenerate the mass deployment JSON
   if the change should reach machines being built from scratch).
4. Re-run `setup-user.sh` on the existing machines, or just:
   `sudo littlesnitch restore-model --preserve-terminal-access template.lsbackup`

Be aware that `restore-model` replaces the **whole** configuration, not just
the rules — any rules a user added locally are discarded. That is usually what
you want for fleet consistency, but it means a redeploy is destructive to local
changes, so it is not something to run casually.

Keep `"users": []` in the template so everyone gets the defaults. User-specific
settings are keyed by numeric UID and will not match across machines otherwise.

If this ever grows past the point where hand-shipping a file is comfortable,
Little Snitch also supports **remote rule groups** — a `.lsrules` file on an
HTTPS server with a publicly trusted certificate, re-fetched on an interval.
Worth knowing the trade-off before reaching for it: there is no authentication
on those URLs, so whoever can write to that file can push allow-rules to every
Mac subscribed to it.

## MDM profile

`LittleSnitch.mobileconfig` is Objective Development's example profile
(from <https://help.obdev.at/littlesnitch6/adv-enterprise-deployment>),
vendored here unmodified. It carries three payloads that pre-approve the
extension for Obdev's team ID `MLZF7K7B5R`:

- `com.apple.webcontent-filter` — the content filter
- `com.apple.networkextension.managed` — the network extension config
- `com.apple.system-extension-policy` — allows the extension to load

Change the display names and `PayloadIdentifier`s to suit, then sign it before
uploading to your MDM:

```
security cms -S -N "My Certificate Name" \
  -i LittleSnitch.mobileconfig \
  -o LittleSnitch-signed.mobileconfig
```

It has to arrive via MDM on a supervised device. `profiles install` from the
command line no longer works for this on modern macOS.

## Changing settings after deployment

```
sudo littlesnitch list-preferences --global-only
sudo littlesnitch read-preference <key>
sudo littlesnitch --user <uid|name> write-preference <key> <value>
```

To lock users down, set these in the template under Security:
Allow Rule Editing, Allow Profile Switching, Allow Settings Editing,
Allow Global Rule Editing.

Reference: <https://help.obdev.at/littlesnitch6/adv-enterprise-deployment>
