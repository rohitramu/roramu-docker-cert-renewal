#
# +---------------------+
# | Usage of this image |
# +---------------------+
# - The ENTRYPOINT or CMD commands SHOULD NOT be overridden in child images.
# - The following environment variables MUST be provided:
#       - $ACME_SERVER: The ACME server that will be used.  If this is not set, it will default to the
#         "Let's Encrypt" staging URL.  Any ACME server URL may be provided, but for reference, the
#         "Let's Encrypt" v2 certificate authority URLs are:
#             - Staging:    https://acme-staging-v02.api.letsencrypt.org/directory
#             - Production: https://acme-v02.api.letsencrypt.org/directory
#       - $DOMAIN: Domain name for which a certificate should be generated/renewed.
#       - $AUTH_DOMAIN: Authentication domain, where the DNS challenge will take place (i.e. TXT records
#         are created here).
#       - $CERT_EMAIL: The email address to be included in the certificate.
# - The following environment variables SHOULD be provided:
#       - $DEPLOY_HOOK: The deploy-hook command.  In most cases, this should be a script which can deploy
#         the generated certificate given the location of required files.  The file locations will be
#         provided as arguments to the command in the following order:
#            1. The domain name on the certificate
#            2. Path to key file (privkey.pem)
#            3. Path to cert file (cert.pem)
#            4. Path to the full chain file (fullchain.pem)
#            5. Path to the chain file (chain.pem)
# - Files generated by this image SHOULD be saved and re-loaded between runs.  There are two ways this
#   can be done:
#      1. Mounting a volume (or some other form of persistent storage) to $CERT_WORKING_DIR.  The
#         location of $CERT_WORKING_DIR can be found in the first ENV statement of this Dockerfile.
#      2. Providing both the $SAVE_HOOK and $LOAD_HOOK commands.  Both hooks MUST be provided in order
#         for this image to work correctly.  Both hooks will be provided 1 argument:
#             - $SAVE_HOOK: the path of the folder whose content needs to be saved.
#             - $LOAD_HOOK: the path of the folder that the content from previous runs should be to be
#               loaded into.
# - Inbound ports that need to be open to the internet:
#       - 53/udp
#       - 53/tcp (optional)
# - Outbound ports that need to be open to the internet:
#       - 80/tcp
#       - 443/tcp
# - The following DNS records should be placed in the DNS zone specified by $DOMAIN in order for the
#   ACME challenge to work:
#      1. CNAME record that points from "$CERT_CHALLENGE_SUBDOMAIN.$DOMAIN" to
#         "$CERT_CHALLENGE_SUBDOMAIN.$AUTH_DOMAIN"
#      2. NS record that points to the server that this image is running on.
#
FROM alpine:latest

# WARNING: These environment variables MUST NOT be overridden.
ENV \
    # The main working directory
    WORKING_DIR="/usr/local/bin/acme-cert-renewal" \
    # The certificate working directory, where certs will be stored between runs of this image.
    CERT_WORKING_DIR="/usr/local/etc/acme-cert-renewal"

# Environment variables that MAY be modified by users to alter the runtime configuration
ENV \
    # Set $DEBUG to "true" to turn on debug mode
    DEBUG="false" \
    # Default subdomain that will contain the challenge TXT records
    CERT_CHALLENGE_SUBDOMAIN="_acme-challenge"

# Setup environment
RUN echo "" && \
    # Install build tools
    echo "" && \
    echo "+----------------------------+" && \
    echo "| Install build dependencies |" && \
    echo "+----------------------------+" && \
    apk add --update -t deps jq && \
    echo "" && \
    echo "" && \
    # Install runtime tools
    echo "+--------------+" && \
    echo "| Install bash |" && \
    echo "+--------------+" && \
    apk add bash && \
    echo "" && \
    echo "" && \
    echo "+--------------+" && \
    echo "| Install perl |" && \
    echo "+--------------+" && \
    apk add perl && \
    echo "" && \
    echo "" && \
    echo "+-------------------+" && \
    echo "| Install findutils |" && \
    echo "+-------------------+" && \
    apk add findutils && \
    echo "" && \
    echo "" && \
    echo "+-------------------+" && \
    echo "| Install coreutils |" && \
    echo "+-------------------+" && \
    apk add coreutils && \
    echo "" && \
    echo "" && \
    echo "+--------------+" && \
    echo "| Install curl |" && \
    echo "+--------------+" && \
    apk add curl && \
    echo "" && \
    echo "" && \
    echo "+-----------------+" && \
    echo "| Install openssl |" && \
    echo "+-----------------+" && \
    apk add openssl && \
    echo "" && \
    echo "" && \
    echo "+--------------------+" && \
    echo "| Install dehydrated |" && \
    echo "+--------------------+" && \
    mkdir dehydrated && \
    curl -L $(curl -L https://api.github.com/repos/lukas2511/dehydrated/releases/latest | jq -r ".assets[] | select(.name | endswith(\"tar.gz\")) | .browser_download_url") -o dehydrated/dehydrated.tar.gz && \
    tar -xvzf dehydrated/dehydrated.tar.gz -C dehydrated/ && \
    find /dehydrated -type f -name dehydrated -exec mv {} /usr/local/bin/ \; && \
    chmod +x /usr/local/bin/dehydrated && \
    rm -rf /dehydrated/ && \
    echo "+------------------+" && \
    echo "| Install PowerDNS |" && \
    echo "+------------------+" && \
    apk add pdns && \
    apk add pdns-backend-pipe && \
    echo "" && \
    echo "" && \
    # Clean up
    echo "+--------------------------+" && \
    echo "| Clean build dependencies |" && \
    echo "+--------------------------+" && \
    apk del --purge deps && \
    echo "" && \
    echo "" && \
    echo "+---------------------+" && \
    echo "| Clean package cache |" && \
    echo "+---------------------+" && \
    rm /var/cache/apk/* && \
    echo "" && \
    echo "" && \
    echo "+------------------------------+" && \
    echo "| Finished installing packages |" && \
    echo "+------------------------------+" && \
    echo ""

# Environment variables that SHOULD be set by users at runtime
ENV \
    # The ACME server.  For reference, "Let's Encrypt" v2 certificate authority URLs are:
    #   Staging:    https://acme-staging-v02.api.letsencrypt.org/directory
    #   Production: https://acme-v02.api.letsencrypt.org/directory
    ACME_SERVER="https://acme-staging-v02.api.letsencrypt.org/directory" \
    # The domain that is/will be on the certificate.
    # A wildcard certificate will be generated, meaning all subdomains are also included.
    DOMAIN="" \
    #
    # Authentication domain (this is where the TXT records will be created).
    # The authentication domain does not need to be a subdomain of the certificate domain.
    AUTH_DOMAIN="" \
    #
    # The email address that will be used to register with the ACME server
    CERT_EMAIL="" \
    #
    # The deploy-hook command which can be used to deploy certificate files.
    # Remember to use RUN commands to install necessary packages.
    # The given command will be passed arguments in the following order:
    #   1. The domain name on the certificate
    #   2. Path to key file (privkey.pem)
    #   3. Path to cert file (cert.pem)
    #   4. Path to the full chain file (fullchain.pem)
    #   5. Path to the chain file (chain.pem)
    DEPLOY_HOOK="" \
    #
    # The load-hook command which can be used to load files from previous runs.
    # This command should load the files that were saved using the save-hook.
    # This command will be called with 1 argument: the directory that files
    # should be copied into.
    LOAD_HOOK="" \
    #
    # The save-hook command which can be used to save files from a run.  This
    # command should save the files so that they can be restored by the load-hook
    # in subsequent runs.  This command will be called with 1 argument: the directory
    # that contains the files to be saved.
    SAVE_HOOK=""

# Set working directory
WORKDIR $WORKING_DIR

# Copy files
COPY include/ .

# Make included files executable
RUN find ./ -type f -exec chmod +x {} \;

# Expose the DNS port
EXPOSE 53/tcp 53/udp

# Start the entrypoint script
ENTRYPOINT $WORKING_DIR/entrypoint.sh