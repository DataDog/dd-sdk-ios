#!/bin/bash

function usage() {
  cat << EOF
OVERVIEW: Install Apple certificate and provisioning profile to build and sign.

EXAMPLE: $(basename "${BASH_SOURCE[0]}") -- make export

USAGE: $(basename "${BASH_SOURCE[0]}") [--p12 </path/to/cert.p12>] [--p12-password <password>] [--provisioning-profile</path/to/profile.mobileprovision>] -- <build command>

OPTIONS:

-h, --help              Print this help and exit.
--p12                   Path to Apple signing 'p12' certificate. env P12_PATH
--p12-password          The password for yotheur Apple signing certificate. env P12_PASSWORD
--provisioning-profile  Path to Apple provisioning profile. env PP_PATH

EOF
  exit
}

# read cmd arguments
while :; do
    case $1 in
        --p12) P12_PATH=$2
        shift
        ;;
        --p12-password) P12_PASSWORD=$2
        shift
        ;;
        --provisioning-profile) PP_PATH=$2
        shift
        ;;
        -h|--help) usage
        shift
        ;;
        --) shift
        CMD=$@
        break
        ;;
        *) break
    esac
    shift
done

if [ -z "$P12_PATH" ] || [ -z "$P12_PASSWORD" ] || [ -z "$PP_PATH" ] || [ -z "$CMD" ]; then usage; fi

# Ensure we do not leak any secrets
set +x

KEYCHAIN=datadog.keychain
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
PROFILE=datadog.mobileprovision

# apply provisioning profile
mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
cp $PP_PATH ~/Library/MobileDevice/Provisioning\ Profiles/$PROFILE

# create temporary keychain
security delete-keychain $KEYCHAIN || :
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN
security set-keychain-settings -lut 21600 $KEYCHAIN
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN

# import certificate to keychain
security import $P12_PATH -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k $KEYCHAIN
security list-keychain -d user -s $KEYCHAIN "login.keychain" "System.keychain"
security set-key-partition-list -S apple-tool:,apple: -s -k $KEYCHAIN_PASSWORD $KEYCHAIN >/dev/null 2>&1

# run command with certificate and provisioning profile available
exec $CMD

# clean up keychain and provisioning profile
security delete-keychain $KEYCHAIN
rm ~/Library/MobileDevice/Provisioning\ Profiles/$PROFILE
