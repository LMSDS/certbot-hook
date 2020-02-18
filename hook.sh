#!/usr/bin/env bash

# This script does not need to be changed for certbots DNS challenge.
# Please see the .dedynauth file for authentication information.

(

DEDYNAUTH=$(pwd)/.dedynauth

if [ ! -f "$DEDYNAUTH" ]; then
    >&2 echo "File $DEDYNAUTH not found. Please place .dedynauth file in appropriate location."
    exit 1
fi

source "$DEDYNAUTH"

if [ -z "$DEDYN_TOKEN" ]; then
    >&2 echo "Variable \$DEDYN_TOKEN not found. Please set DEDYN_TOKEN=(your dedyn.io token) to your dedyn.io access token in $DEDYNAUTH, e.g."
    >&2 echo ""
    >&2 echo "DEDYN_TOKEN=d41d8cd98f00b204e9800998ecf8427e"
    exit 2
fi

if [ -z "$DEDYN_NAME" ]; then
    >&2 echo "Variable \$DEDYN_NAME not found. Please set DEDYN_NAME=(your dedyn.io name) to your dedyn.io name in $DEDYNAUTH, e.g."
    >&2 echo ""
    >&2 echo "DEDYN_NAME=foobar.dedyn.io"
    exit 3
fi

if [ -z "$CERTBOT_DOMAIN" ]; then
    >&2 echo "It appears that you are not running this script through certbot (\$CERTBOT_DOMAIN is unset). Please call with: certbot --manual-auth-hook=$0"
    exit 4
fi

if [ ! "$(type -P curl)" ]; then
    >&2 echo "Please install curl to use certbot with dedyn.io."
    exit 5
fi

echo "Setting challenge to ${CERTBOT_VALIDATION} ..."

# Figure out subdomain infix by removing zone name and trailing dot
# foobar.dedyn.io gives "" while a.foobar.dedyn.io gives ".a"
domain=.$CERTBOT_DOMAIN
infix=${domain%.$DEDYN_NAME}

# Remove leading wildcard from infix, if present
# *.foobar.dedyn.io gives "" while *.a.foobar.dedyn.io gives ".a"
infix=${infix#.\*}

args=( \
    '-sSLf' \
    '-H' "Authorization: Token $DEDYN_TOKEN" \
    '-H' 'Accept: application/json' \
    '-H' 'Content-Type: application/json' \
)

# For wildcard certificates, we'll need multiple _acme-challenge records in the
# same rrset. If the current rrset is empty, we simply publish the new
# challenge. If the current rrset contains records and we have a new challenge,
# we append the new challenge to the current rrset. If for some reason the new
# challenge is already in the rrset, we re-publish the current rrset as-is.
# Consider using the included cleanup hook with certbot's --manual-cleanup-hook
# to prevent challenges from accumulating.
acme_records=$(curl "${args[@]}" -X GET "https://desec.io/api/v1/domains/$DEDYN_NAME/rrsets/?subname=_acme-challenge$infix&type=TXT" \
    | tr -d '\n' | grep -o '"records"[[:space:]]*:[[:space:]]*\[[^]]*\]' | grep -o '"\\".*\\""')

if [ -z "$acme_records" ]; then
    acme_records='"\"'"$CERTBOT_VALIDATION"'\""'
elif [[ ! $acme_records =~ "$CERTBOT_VALIDATION" ]]; then
    acme_records+=',"\"'"$CERTBOT_VALIDATION"'\""'
fi

# set ACME challenge (overwrite if possible, create otherwise)
curl "${args[@]}" -X PUT -o /dev/null "https://desec.io/api/v1/domains/$DEDYN_NAME/rrsets/" \
    '-d' '[{"subname":"_acme-challenge'"$infix"'", "type":"TXT", "records":['"$acme_records"'], "ttl":60}]'

echo "Verifying challenge is set correctly. This can take up to 2 minutes."
echo "Current Time: $(date)"

for ((i = 0; i < 60; i++)); do
    CURRENT=$(host -t TXT "_acme-challenge$infix.$DEDYN_NAME" ns1.desec.io | grep -- "$CERTBOT_VALIDATION")
    if [ -n "$CURRENT" ]; then
	break
    fi
    sleep 2
done

if [ -z "$CURRENT" ]; then
    >&2 echo "Token could not be published. Please check your dedyn credentials."
    exit 6
fi

echo -e '\e[32mToken published. Returning to certbot.\e[0m'

)
