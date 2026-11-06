# Estoki kiosk releases

Releases of the Estoki kiosk, the Raspberry Pi app that sits on the wall beside a household's
shelves. Every kiosk installs the newest release here by itself, within the hour. Nothing here
needs to be downloaded by hand.

Each release carries:

| File | What |
|---|---|
| `estoki_pi-<n>-py3-none-any.whl` | the kiosk app |
| `requirements.lock` | its dependencies, pinned with hashes |
| `manifest.json` | the release's tag, version and both files' SHA-256 |
| `manifest.json.sig` | the manifest's signature |

A kiosk installs a release only when the signature checks out against the key below and both files
match the manifest. To check one yourself:

```bash
echo 'estoki-kiosk-release ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwxkHASpI9NwXmnuGJk6MZxhxuy5ew1ihRcddakcSgm' > allowed_signers
ssh-keygen -Y verify -f allowed_signers -I estoki-kiosk-release -n estoki-kiosk-release \
  -s manifest.json.sig < manifest.json
sha256sum estoki_pi-*.whl requirements.lock   # compare with manifest.json
```

The source is private. Estoki is made by 4Freedom Hub: https://estokiapp.com.
