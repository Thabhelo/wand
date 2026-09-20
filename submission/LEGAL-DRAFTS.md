# Privacy policy draft — requires operator identity and legal review

MacBridge connects your account to devices you own or are authorized to control. We process your hosted authentication subject, device name/type/version, connection timestamps, command action/status/timestamps, OAuth client identity, and source IP in audit records. The relay processes command parameters in transit but stores them redacted. Read-only device state is held in memory for up to 60 seconds for result retrieval. Your Mac retains full validated command parameters locally for your incident investigation, with a 90-day or 10-MiB limit. Do not include secrets in Shortcut names or URLs.

Application command/audit records are purged after 90 days. Deleting your MacBridge data revokes linked devices and removes active application records, including audit records, sooner. Device registry and token hashes remain while a device is registered. Expired enrollment records are removed. Hosted Auth0 identity records and hosting-provider backups follow their own policies; this build does not automatically delete them. The service operator must publish backup retention and a contact for deletion requests before launch. No production service is currently offered by this draft.

TLS protects transport. The relay sees plaintext command contents; end-to-end payload encryption is planned but not implemented. We do not collect screenshots, camera/microphone feeds, keystrokes or window titles. Device state includes only the documented minimized fields. Third parties include the selected hosting provider, Auth0 and the assistant platform; list actual entities and links before release.

# Terms draft — requires jurisdiction and legal review

Use MacBridge only with devices and accounts you are authorized to control. You remain responsible for Shortcut contents you explicitly allow. Remote commands can interrupt work, close applications or affect unsaved data. Read confirmations carefully. There is intentionally no remote unlock.

Connectivity, OS permissions and operating-system changes can prevent actions. An accepted or timed-out command is not proof of success. Do not rely on this development product for emergency, life-safety, security-critical or guaranteed-availability operations. Applicable statutory rights are not excluded by this draft.

Before publication, the operator must supply legal identity, contact address, jurisdiction, dispute terms, age restrictions, acceptable-use rules, support policy, warranty/liability terms compliant with local law, and effective date. No commercial warranty or contractual service commitment is made by this unfinished draft.
