# This imports the CA into the current user's certificate store
# you need to copy the ~/.config/demo-cfssl/ca.pem to the current user's certificate store
Import-Certificate `
    -FilePath "ca.pem" `
    -CertStoreLocation "Cert:\CurrentUser\Root"

# This requires admin privileges
# Import-Certificate `
#     -FilePath "ca.pem" `
#     -CertStoreLocation "Cert:\LocalMachine\Root"