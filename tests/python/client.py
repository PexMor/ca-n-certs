#!/usr/bin/env -S python3
"""Simple test SSL connection to server with custom ca cert"""

import ssl
import socket
import os
import sys
from glob import glob

# get default base directory
DEF_BD = os.path.join(os.getenv("HOME", "/tmp"), ".config", "demo-ssl")
BD = os.getenv("BD", DEF_BD)
# print all files in base directory
print(f"--- Files in base directory {BD}:")
for fn in glob(os.path.join(BD, "*")):
    print(os.path.basename(fn))
# CA cert file name
CA_CERT = os.getenv("CA_CERT", os.path.join(BD, "ca.pem"))
# test server host and port
HOST = os.getenv("HOST", "localhost")
PORT_STR = os.getenv("PORT", "8443")
# Convert port to integer
try:
    PORT = int(PORT_STR)
except ValueError:
    print(f"Invalid port number: {PORT_STR}")
    sys.exit(1)
# Print configuration
print("--- Configuration:")
print(f" CA_CERT = {CA_CERT}")
print(f"    HOST = {HOST}")
print(f"    PORT = {PORT}")
input("--- Press Enter to continue...")


def main():
    """Main function"""
    # Create SSL context
    if CA_CERT != "":
        context = ssl.create_default_context(cafile=CA_CERT)
    else:
        context = ssl.create_default_context()
    context.check_hostname = True
    context.verify_mode = ssl.CERT_REQUIRED
    # context.load_verify_locations(cafile=CA_CERT)
    # Connect to server
    try:
        print(f"Connecting to {HOST}:{PORT}...")
        with socket.create_connection((HOST, PORT)) as sock:
            with context.wrap_socket(sock, server_hostname=HOST) as ssock:
                # Perform SSL handshake and send/receive data
                http_request = f"GET / HTTP/1.1\r\nHost: {HOST}\r\n\r\n"
                ssock.sendall(http_request.encode())
                data = ssock.recv(1024)
                print(data.decode())
    except ssl.SSLError as err:
        print(f"SSL error: {err}")


if __name__ == "__main__":
    main()
