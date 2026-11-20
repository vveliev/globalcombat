# deploy/oci

Server-side files for the Oracle Cloud deployment:

- `cloud-init.yaml`: first-boot setup for the VM.
- `backup.sh`: nightly Postgres dump, run by the timer that cloud-init installs.

How to use them: [docs/deploy/oracle-kamal.md](../../docs/deploy/oracle-kamal.md).
