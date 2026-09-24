# Set up Wand releases

GitHub can sign and notarize a downloadable Wand artifact, or also publish it to **getwand.app**, using Thabhelo’s Apple Developer account. This workflow does not submit to the Mac App Store. Pushing to `main` alone does not publish an app.

## 1. Choose the signing team

After Apple activates the membership:

1. Find the **Team ID** in [Apple Developer → Membership details](https://developer.apple.com/account).
2. Open [Wand’s Actions variables](https://github.com/Thabhelo/wand/settings/variables/actions).
3. Add `WAND_SIGNING_TEAM_ID` with that exact 10-character Team ID. This is a public identifier, not a secret.

The workflow accepts only a Developer ID Application certificate from this team. If the variable is absent or empty, it keeps build 32’s existing team, `AX35NK3J3A`; it never chooses another available identity automatically.

**Moving from Ebuka’s team to Thabhelo’s is a signing-identity change.** Existing installations may need a one-time Keychain or macOS permission approval. Test that update before publishing. Keep the bundle identifier and the new team stable for later releases; do not reset everyone’s permissions or promise that macOS will never ask again.

## 2. Export the signing certificate

1. [Create a Developer ID Application certificate](https://developer.apple.com/help/account/certificates/create-developer-id-certificates) under the team from step 1, if it does not exist yet. Do not use Apple Development or Developer ID Installer.
2. On the Mac holding its private key, open **Keychain Access → My Certificates**. Expand the certificate and confirm its private key is present.
3. Export the certificate **with its private key** as `Wand-signing.p12`. Set an export password.

If deliberately continuing with Ebuka’s identity, he supplies the build 32 team’s certificate instead. Do not mix one team’s certificate with another team’s configured ID or notarization credentials.

## 3. Create a notarization key

In [App Store Connect](https://appstoreconnect.apple.com/), open **Users and Access → Integrations → App Store Connect API → Team Keys** for the same Apple team.

Create a key authorized for notarization. Download its `.p8` file and record the **Key ID** and **Issuer ID**. Apple allows one download of the private key. This workflow uses a team key with an issuer ID, not an individual API key.

## 4. Save the release credentials

Thabhelo opens [Wand’s Actions secrets](https://github.com/Thabhelo/wand/settings/secrets/actions) and adds:

| Secret | Value |
|---|---|
| `WAND_CERTIFICATE_BASE64` | Base64 of `Wand-signing.p12` |
| `WAND_CERTIFICATE_PASSWORD` | Its export password |
| `WAND_NOTARY_KEY_BASE64` | Base64 of the `.p8` key |
| `WAND_NOTARY_KEY_ID` | Apple’s Key ID |
| `WAND_NOTARY_ISSUER_ID` | Apple’s Issuer ID |
| `GH_RELEASE_TOKEN` | Thabhelo’s fine-grained token for **Thabhelo/wand**, with **Contents: Read and write** |
| `CLOUDFLARE_API_TOKEN` | Wand account: **Workers Scripts: Edit**; `getwand.app` zone: **Zone: Read** and **Workers Routes: Edit** |

Only the first five Apple secrets are required to produce a signed, notarized artifact. The last two are required for automatic publication and deployment. A publication run checks that all seven are present before building or submitting anything to Apple; this presence check does not prove the tokens are valid.

Copy each file’s Base64 directly to the clipboard, replacing the path:

```sh
base64 -i "/full/path/Wand-signing.p12" | tr -d '\n' | pbcopy
```

```sh
base64 -i "/full/path/AuthKey_YOUR_KEY_ID.p8" | tr -d '\n' | pbcopy
```

Paste each value into its GitHub secret before copying the next. Then clear the clipboard with `pbcopy < /dev/null`. Keep the original keys secure; never put them in chat or the repository. These credentials authorize signing and notarization under their Apple team, and team API keys are not restricted to one app. No Apple account password is needed in GitHub.

## 5. Run checks, prepare an artifact, or publish

1. Open [Actions → Mac release](https://github.com/Thabhelo/wand/actions/workflows/mac-release.yml), choose **Run workflow**, and select `main`.
2. Enter a version such as `0.13.1` and a build number higher than [the published build](https://getwand.app/download/). Versions cannot decrease.
3. Choose the mode below. The default runs checks only.
4. Wait for success. Avoid pushing to `main` during a publication run.
5. For an artifact run, download `Wand-<version>-build<build>` from the run’s **Artifacts** section. It contains the signed, notarized, stapled DMG and its SHA-256 file; artifacts are retained for 14 days.
6. Test a fresh installation and an update: connect, quit, reopen, and check desktop permissions and Keychain behavior. Keep the existing bundle identifier and signing team when testing an ordinary update.

| `package` | `publish` | Result |
|---|---|---|
| Unchecked | Unchecked | Validate version/build and run checks; no signing or notarization |
| Checked | Unchecked | Sign, notarize, verify and save the artifact using the five Apple secrets; no commit, push or deployment |
| Either | Checked | Prepare the artifact, commit the release to `main`, deploy and verify the public download; all seven secrets required |

Packaging verifies both the notarized app and DMG, and prepares release files and the download-page change only inside the runner checkout. Publication records and deploys those changes, then checks the public file. An artifact-only run does not change the public website or repository. If deployment fails after the release commit, deploy that committed version instead of reusing the build number. A green checks-only or artifact-only run does not mean the app was published or its permissions were tested.
