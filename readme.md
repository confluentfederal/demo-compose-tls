# Single Node TLS

This is a demonstration of using TLS in a Docker Compose environment with a single broker node.

To start the demonstration run the `start.sh` command. This script will

1. Create the certificates needed
1. Start the core components
1. Wait for the broker to be ready
1. Start the rest of the components

Note: The environment variable `EXTERNAL_HOSTNAME` needs to be defined. This is used for communications outside of a docker network. If the host this docker composition is running on is named `server.mydomain.com` then the broker is addressable at server.mydomain.com:9092 using the certificate authority `./certs/ca.crt`.

From an external host you could run the command

```sh
kafka-topics \
    --bootstrap-server server.mydomain.com:9092 \
    --config security.mechanism=SSL \
    --config ssl.truststore.location=./certs/ca.jks \
    --config ssl.truststore.password=password \
    --list
```
