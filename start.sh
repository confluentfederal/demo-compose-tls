#!/bin/bash

# set -x

CERT_ADMIN_CN=${CERT_ADMIN_CN:-admin}
CERT_ADMIN_LOC=${CERT_ADMIN_LOC:-Whitehall}
CERT_ADMIN_ORG=${CERT_ADMIN_ORG:-Confluent}
CERT_ADMIN_STATE=${CERT_ADMIN_STATE:-PA}

CLIENT_USERNAME=${CLIENT_USERNAME:-client}

export EXTERNAL_HOSTNAME=${EXTERNAL_HOSTNAME:-localhost}

if [ -z "${EXTERNAL_HOSTNAME}" ]; then
    echo "Environment variable EXTERNAL_HOSTNAME is not set. This needs to be set so external clients can connect to the platform."
    exit 1
else
    echo
    echo "Using an external hostname of \"${EXTERNAL_HOSTNAME}\""
    echo
fi

for cmd in docker openssl keytool curl; do
    if ! command -v $cmd &> /dev/null; then
        echo "$cmd could not be found. Please install it before running this script."
        exit 1
    fi
done

echo
echo "Ensuring a clean environment..."
echo
docker compose down -v

rm -fr ./certs
mkdir -p ./certs

echo
echo "Creating certificates..."
echo
# Create CA
openssl genrsa -aes256 -out ./certs/ca.key -passout pass:password 4096
openssl req -x509 -new -nodes -key ./certs/ca.key -passin pass:password -sha256 -days 3650 -out ./certs/ca.crt \
    -subj "/CN=Demo Root CA/C=US/ST=${CERT_ADMIN_STATE}/L=${CERT_ADMIN_LOC}/O=${CERT_ADMIN_ORG}"

# Create one cert to rule them all
# Create the extensions file for the SANs (supports openssl <3.0)
cat > ./certs/openssl_ext.cnf <<- EOF
[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = kraftcontroller-0
DNS.2 = broker-0
DNS.3 = schema-registry
DNS.4 = control-center
DNS.5 = connect
DNS.6 = restproxy
DNS.7 = localhost
DNS.8 = ${EXTERNAL_HOSTNAME}
EOF

openssl genrsa -out ./certs/admin.key 4096
# These commands only work with OpenSSL 3.0+ due to the `-copy_extensions` flag
# openssl req -new -nodes -out ./certs/admin.csr -key ./certs/admin.key \
#     -subj "/CN=${CERT_ADMIN_CN}/C=US/ST=${CERT_ADMIN_STATE}/L=${CERT_ADMIN_LOC}/O=${CERT_ADMIN_ORG}" \
#     -addext "subjectAltName = DNS:docker-controller-1, DNS:broker-0, DNS:schema-registry, DNS:control-center, DNS:connect, DNS:restproxy, DNS:localhost"
# openssl x509 -req -in ./certs/admin.csr -CA ./certs/ca.crt -CAkey ./certs/ca.key -passin pass:password -CAcreateserial \
#     -out ./certs/admin.crt -days 3650 -sha256 -copy_extensions copyall
openssl req -new -nodes -out ./certs/admin.csr -key ./certs/admin.key \
    -subj "/CN=${CERT_ADMIN_CN}/C=US/ST=${CERT_ADMIN_STATE}/L=${CERT_ADMIN_LOC}/O=${CERT_ADMIN_ORG}"
openssl x509 -req -in ./certs/admin.csr -CA ./certs/ca.crt -CAkey ./certs/ca.key -passin pass:password -CAcreateserial \
    -out ./certs/admin.crt -days 3650 -sha256 -extfile ./certs/openssl_ext.cnf -extensions v3_req
echo password > ./certs/admin.credentials

# Create truststore
keytool -import -v -trustcacerts -file ./certs/ca.crt -keystore ./certs/ca.jks -storepass password -noprompt -storetype PKCS12

# Create keystore
openssl pkcs12 -export -inkey ./certs/admin.key -in ./certs/admin.crt -passout pass:password -out ./certs/admin.p12
keytool -importkeystore -deststorepass password -destkeypass password -destkeystore ./certs/admin.jks -srckeystore ./certs/admin.p12 -srcstoretype PKCS12 -srcstorepass password

# Create a client certificate for client user that cannot log into Control Center
# openssl genrsa -out ./certs/client.key 4096
# openssl req -new -nodes -out ./certs/client.csr -key ./certs/client.key \
#     -subj "/CN=${CLIENT_USERNAME}/C=US/ST=${CERT_ADMIN_STATE}/L=${CERT_ADMIN_LOC}/O=${CERT_ADMIN_ORG}"
# openssl x509 -req -in ./certs/client.csr -CA ./certs/ca.crt -CAkey ./certs/ca.key -passin pass:password -CAcreateserial \
#     -out ./certs/client.crt -days 3650 -sha256
# echo password > ./certs/client.credentials

echo
echo "Deploying the platform..."
echo
# Deploy the platform
# docker compose up -d broker-0 control-center schema-registry connect restproxy
docker compose up -d broker-0 control-center schema-registry
if [ $? -ne 0 ]; then
    echo "Failed to deploy the platform."
    exit 1
fi

# Wait for control center to be ready
echo
echo "Waiting for Control Center to be ready..."
echo
until $(curl --output /dev/null --silent --head --fail --cacert ./certs/ca.crt https://localhost:9021); do
    printf '.'
    sleep 5
done

echo
echo "Control Center is ready and available at https://localhost:9021"
echo "External clients can connect to the platform at ${EXTERNAL_HOSTNAME}:9092 using the Certificate Authority ./certs/ca.crt"
echo
