# awsmfa
Handy script to set multiple aws mfa profiles

Note that this script does NOT "switch" any profile upon successful MFA.

User is still expected to explicitly use `--profile <mfa'ed profile>` when making aws cli call

Requirements: jq , aws-cli, bash (not sure if fully posix-compliance), a computer or 2

*** USE AT YOUR OWN RISK ***
