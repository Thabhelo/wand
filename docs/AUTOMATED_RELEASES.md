# Set up Wand releases

This setup lets GitHub sign, notarize, and publish Wand to **getwand.app**. It does not submit to the Mac App Store. Releases are started manually; pushing to `main` alone does not publish an app.

## 1. Ebuka: export the signing certificate

On the Mac used to sign build 32:

1. Open **Keychain Access → My Certificates**.
2. Find the **Developer ID Application** certificate for team **AX35NK3J3A**. Expand it and confirm its private key is present.
3. Export the certificate **with its private key** as `Wand-signing.p12`. Set an export password and keep it for step 3.

Use the same signing identity as build 32, not an Apple Development or Developer ID Installer certificate. This avoids another unnecessary identity change for existing users.

## 2. Ebuka: prepare the notarization key

In [App Store Connect](https://appstoreconnect.apple.com/), open **Users and Access → Integrations → App Store Connect API → Team Keys**.

Use a team key authorized for notarization, or create a dedicated one for Wand. Download its `.p8` file and record the **Key ID** and **Issuer ID**. Apple only lets you download the private key once. This workflow requires a team key and its issuer ID.

Adding these credentials lets Wand’s release workflow sign software under your developer identity. Team API keys are not restricted to one app. Proceed only if you agree to that access; no Apple account password is needed.

## 3. Ebuka: add five GitHub secrets

Open [Wand’s Actions secrets](https://github.com/Thabhelo/wand/settings/secrets/actions). Select **New repository secret** for each entry below. As a repository collaborator, you can add secrets; if the page is unavailable, ask Thabhelo to check your access.

| Name | What to paste |
|---|---|
| `WAND_CERTIFICATE_BASE64` | Base64 of `Wand-signing.p12` |
| `WAND_CERTIFICATE_PASSWORD` | The export password from step 1 |
| `WAND_NOTARY_KEY_BASE64` | Base64 of the `.p8` file |
| `WAND_NOTARY_KEY_ID` | Apple’s Key ID |
| `WAND_NOTARY_ISSUER_ID` | Apple’s Issuer ID |

For each file, run the matching command in Terminal on your Mac, replacing the path with its actual location. It copies the value directly to your clipboard, without printing it. Paste into the matching GitHub secret before running the next command.

```sh
base64 -i "/full/path/Wand-signing.p12" | tr -d '\n' | pbcopy
```

```sh
base64 -i "/full/path/AuthKey_YOUR_KEY_ID.p8" | tr -d '\n' | pbcopy
```

Keep Base64 on one line. Paste credentials only into GitHub secrets, never into chat or the repository. Once both are saved, clear the clipboard with `pbcopy < /dev/null`. Keep original keys in secure storage.

## 4. Thabhelo: add two deployment secrets

Use the same GitHub secrets page.

| Name | Required access |
|---|---|
| `GH_RELEASE_TOKEN` | Fine-grained token owned by **Thabhelo**, limited to **Thabhelo/wand**, with **Contents: Read and write** |
| `CLOUDFLARE_API_TOKEN` | Wand’s Cloudflare account: **Workers Scripts: Edit**; `getwand.app` zone: **Zone: Read** and **Workers Routes: Edit** |

Ebuka does not need to sign in to Cloudflare. Replace expired or revoked credentials here before the next release.

## 5. Publish a release

1. Open [Actions → Mac release](https://github.com/Thabhelo/wand/actions/workflows/mac-release.yml) and click **Run workflow**.
2. Select `main`. Enter a version such as `0.12.1` and a build number higher than the one on [the download page](https://getwand.app/download/). The version cannot go backwards.
3. Leave **Publish** unchecked to test only. Check it to sign, notarize, and publish. All seven secrets must be set before publishing.
4. Wait for the run to finish successfully. Avoid pushing changes to `main` while it runs.
5. Download the published app. Test both a fresh installation and an update: connect, quit, reopen, and confirm it reconnects without repeated Keychain prompts.

The workflow updates the download page and checks the public file. If deployment fails after the release commit, deploy that committed version; do not overwrite the build number. A green test-only run does not mean the app was published or that macOS permissions were tested.

Reference: [Apple API keys](https://developer.apple.com/documentation/AppStoreConnectAPI/creating-api-keys-for-app-store-connect-api) · [GitHub secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets).
