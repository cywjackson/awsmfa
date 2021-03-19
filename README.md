# awsmfa

Handy script to set multiple aws mfa profiles

Note that this script does NOT "switch" any profile upon successful MFA.

Note also this script ASSUME your mfa profile = "<non mfa profile name>-mfa"

User is still expected to explicitly use `--profile <profile_name>-mfa` when making aws cli call

Create your favorite list in ~/.mfacfg with below format, and use -f <list name> option:

       list1=( profile1 profile2 ... )

       list2=( profile3 profile4 ... )

Requirements: jq , aws-cli, bash (not sure if fully posix-compliance), a computer or 2

*** USE AT YOUR OWN RISK ***
