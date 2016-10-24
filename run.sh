#!/bin/sh

set -ex

if [[ ! -f "$DIT4C_IMAGE" ]]; then
  echo "Unable to find DIT4C_IMAGE: $DIT4C_IMAGE"
  exit 1
fi

if [[ "$DIT4C_IMAGE_ID" == "" ]]; then
  echo "Must specify DIT4C_IMAGE_ID for image"
  exit 1
fi

if [[ "$DIT4C_IMAGE_SERVER" == "" ]]; then
  echo "Must specify DIT4C_IMAGE_SERVER to upload image"
  exit 1
fi

if [[ "$DIT4C_IMAGE_UPLOAD_NOTIFICATION_URL" == "" ]]; then
  echo "Must specify DIT4C_IMAGE_UPLOAD_NOTIFICATION_URL"
  exit 1
fi

if [[ ! -f "$DIT4C_INSTANCE_PRIVATE_KEY_PKCS1" ]]; then
  echo "Unable to find DIT4C_INSTANCE_PRIVATE_KEY_PKCS1: $DIT4C_INSTANCE_PRIVATE_KEY_PKCS1"
  exit 1
fi

if [[ ! -f "$DIT4C_INSTANCE_PRIVATE_KEY_OPENPGP" ]]; then
  echo "Unable to find DIT4C_INSTANCE_PRIVATE_KEY_OPENPGP: $DIT4C_INSTANCE_PRIVATE_KEY_OPENPGP"
  exit 1
fi
gpg2 --batch --yes --import $DIT4C_INSTANCE_PRIVATE_KEY_OPENPGP

if [[ "$DIT4C_INSTANCE_PRIVATE_KEY_OPENPGP_PASSPHRASE" == "" ]]; then
  echo "Must specify DIT4C_INSTANCE_PRIVATE_KEY_OPENPGP_PASSPHRASE to decrypt key"
  exit 1
fi

if [[ "$DIT4C_INSTANCE_JWT_ISS" == "" ]]; then
  echo "Must specify DIT4C_INSTANCE_JWT_ISS for JWT auth token"
  exit 1
fi

if [[ "$DIT4C_INSTANCE_JWT_KID" == "" ]]; then
  echo "Must specify DIT4C_INSTANCE_JWT_KID for JWT auth token"
  exit 1
fi

TOKEN=$(jwt -k $DIT4C_INSTANCE_PRIVATE_KEY_PKCS1 \
  -alg RS512 \
  -enc \
  iss=$DIT4C_INSTANCE_JWT_ISS \
  kid=$DIT4C_INSTANCE_JWT_KID)

WORKDIR=$(mktemp -d)
pushd $WORKDIR
WORKING_IMAGE=$(basename "$DIT4C_IMAGE")
ln -s "$DIT4C_IMAGE" "$WORKING_IMAGE"

echo "$DIT4C_INSTANCE_PRIVATE_KEY_OPENPGP_PASSPHRASE" | \
  gpg2 --batch --yes --passphrase-fd 0 --pinentry-mode loopback \
    --armor --detach-sign "$WORKING_IMAGE"

for f in "$WORKING_IMAGE" "$WORKING_IMAGE.asc"
do
  curl -v -X PUT --retry 1000 \
    -H "Authorization: Bearer $TOKEN" \
    --data-raw @"$f" \
    "$DIT4C_IMAGE_SERVER/$DIT4C_IMAGE_ID/$f"
done

curl -v -X PUT --retry 1000 \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: text/plain; charset=UTF-8" \
  -d "$IMAGE_URL" \
  "$DIT4C_IMAGE_UPLOAD_NOTIFICATION_URL"
