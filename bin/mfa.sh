#! /bin/bash 

# Handy script to set multiple aws mfa profiles
# Note that this script does NOT "switch" any profile upon successful MFA.
# Note also this script ASSUME your mfa profile = "<non mfa profile name>-mfa"
# User is still expected to explicitly use `--profile <profile_name>-mfa` when making aws cli call
#
# Create your favorite list in ~/.mfacfg with below format, and use -f <list name> option: 
#       list1=( profile1 profile2 ... )
#       list2=( profile3 profile4 ... )

# Requirements: jq , aws-cli, bash (not sure if fully posix-compliance), a computer or 2
# * USE AT YOUR OWN RISK *

readarray -t all_non_mfa_profiles_unsort < <(cat ~/.aws/credentials | grep -o '\[[^]]*\]' | grep -v "\-mfa" | tr -d '[]')
IFS=$'\n' all_non_mfa_profiles=($(sort <<<"${all_non_mfa_profiles_unsort[*]}")); unset IFS

declare -A cred_keyname=(
    [SecretAccessKey]="aws_secret_access_key"
    [AccessKeyId]="aws_access_key_id"
    [SessionToken]="aws_session_token"
)

declare -a profiles

function getMFADevice() {
    # TODO: is it a correct assumption that all mfa ARN is like the caller identity ARN with just replacing 'user' with 'mfa'? 
    # ANS ^: not correct. there could be path. see https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_identifiers.html
    # update sed to eagerly look up to /
    local mfa=`aws --profile "$1" sts get-caller-identity | jq '.Arn' -r | sed -e 's|user.*\/|mfa\/|'`
    echo "$mfa"
}

usage() {
    echo "usage:    $(basename $0) [-h] [-l] [-a] [-f list] [-p profile1,profile2,...]"
    echo "          no argument = -p default" 
    echo "" 
    echo "      -h                          :   Print help usage."
    echo "      -l                          :   Print supported profiles."
    echo "      -a                          :   Run the script for ALL supported profiles."
    echo "      -f list                     :   Run the script for a predefined list of profiles."
    echo "                                      The list name and profiles should be defined in ~/.mfacfg, with the following format:"
    echo "                                          list1=( profile1 profile2 ... )"
    echo "                                          list2=( profile1 profile2 ... )"
    echo '      -p "profile1,profile2,..."  :   Run the script of specific profile(s), double quote and comma separated'
}

listProfiles() {
    echo "supported profiles: ${all_non_mfa_profiles[@]}"
}

# Make a cleanup function
cleanup() {
    rm --force -- "${cred_out}"
}

trap cleanup EXIT

# Main start
while getopts "af:p:lh" opt; do
    case $opt in
        a)  profiles=("${all_non_mfa_profiles[@]}") ;;
        f)
            # TODO validation of favorite list input available in ~/.mfacfg?
            # TODO need another option to list favorite list?
            . ~/.mfacfg
            fav="$OPTARG"
            # eval evil, but how do i do https://unix.stackexchange.com/questions/222487/bash-dynamic-variable-variable-names for array?
            for p in $(eval echo "\${$fav[@]}"); do
               profiles+=("${p}")
            done
            ;; 
        p)  
            set -f 
            OIFS=$IFS
            IFS=,
            profiles=($OPTARG)
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

if [ "${#profiles[@]}" -eq 0 ]; then
    profiles=("default")
fi

for profile_no_mfa in "${profiles[@]}" ; do
    mfa="$(getMFADevice $profile_no_mfa)"
    read -e -p "Enter AWS Profile [$profile_no_mfa] MFA token: " token
    cred_out=`mktemp`
    # TODO: what if it fails for whatever reason? Do we want to retry? And how many times to retry? Currently it'd just fail that 1 profile and move on to the next
    aws --profile "$profile_no_mfa" sts get-session-token --serial-number $mfa --token-code $token > "$cred_out"
    for k in "${!cred_keyname[@]}"; do
        cred=`cat "$cred_out" | jq ".Credentials.$k" -r`
        profile_mfa="$profile_no_mfa"-mfa
        aws configure set "${cred_keyname[$k]}" "$cred" --profile "$profile_mfa"
    done
    # set region to the mfa profile if not set already
    region=$(aws configure get region --profile "${profile_no_mfa}")
    aws configure set region "${region}" --profile "${profile_mfa}"
done

