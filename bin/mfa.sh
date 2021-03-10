#! /bin/bash 

# Handy script to set multiple aws mfa profiles
# Note that this script does NOT "switch" any profile upon successful MFA.
# User is still expected to explicitly use `--profile <mfa'ed profile>` when making aws cli call
#
# Requirements: jq , aws-cli, bash (not sure if fully posix-compliance), a computer or 2
# * USE AT YOUR OWN RISK *

# TODO: read from a config file?
declare -A mfa_map=(
    # Key=IAM user profile, Value=tempoary session profile with MFA
    [default]=jackson-mfa
    [sfdc-security]=sfdc-security-mfa
    [sfdc-siq-prod]=sfdc-siq-prod-mfa
    [siq-dev]=siq-dev-mfa
    [sfdc-siq-build]=sfdc-siq-build-mfa
)

declare -A cred_keyname=(
    [SecretAccessKey]="aws_secret_access_key"
    [AccessKeyId]="aws_access_key_id"
    [SessionToken]="aws_session_token"
)

declare -A run_map
declare -a keys

function getMFADevice() {
    # TODO: is it a correct assumption that all mfa ARN is like the caller identity ARN with just replacing 'user' with 'mfa'? 
    local mfa=`aws --profile "$1" sts get-caller-identity | jq '.Arn' -r | sed -e 's/user/mfa/'`
    echo "$mfa"
}

usage() {
    echo -e "usage: $(basename $0) [-h] [-l] [-a] [-p profile1,profile2,...]\n\tno argument = -p default" 1>&2
}

listProfiles() {
    echo "supported profiles: ${!mfa_map[@]}"
}

# Make a cleanup function
cleanup() {
    rm --force -- "${cred_out}"
}

trap cleanup EXIT
while getopts "ap:lh" opt; do
    case $opt in
        a)  keys=("${!mfa_map[@]}") ;;
        p)  
            set -f 
            OIFS=$IFS
            IFS=,
            keys=($OPTARG)
            IFS=$OIFS
            set +f
            ;;  
        l)  listProfiles
            exit 0 ;;
        h)  
            usage
            exit 0 ;;
        *)  
            usage
            exit 1
    esac
done

if [ "${#keys[@]}" -eq 0 ]; then
    keys=("default")
fi

for k in "${keys[@]}"; do
    run_map+=( ["$k"]="${mfa_map["$k"]}" )
done

for profile_no_mfa in "${!run_map[@]}" ; do
    mfa="$(getMFADevice $profile_no_mfa)"
    read -p "Enter AWS Profile [$profile_no_mfa] MFA token: " token
    cred_out=`mktemp`
    # TODO: what if it fails for whatever reason? Do we want to retry? And how many times to retry? Currently it'd just fail that 1 profile and move on to the next
    aws --profile "$profile_no_mfa" sts get-session-token --serial-number $mfa --token-code $token > "$cred_out"
    for k in "${!cred_keyname[@]}"; do
        cred=`cat "$cred_out" | jq ".Credentials.$k" -r`
        aws configure set "${cred_keyname[$k]}" "$cred" --profile "${run_map[$profile_no_mfa]}"
    done
done

