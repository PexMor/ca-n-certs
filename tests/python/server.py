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
SRV_CERT = os.getenv("SRV_CERT", os.path.join(BD, "localhost-server.pem"))
SRV_BUNDLE = os.getenv("SRV_BUNDLE", os.path.join(BD, "localhost-server-bundle.pem"))
SRV_KEY = os.getenv("SRV_KEY", os.path.join(BD, "localhost-server-key.pem"))
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
    # create server SSL context
    context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)  # cafile=CA_CERT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    context.load_cert_chain(certfile=SRV_BUNDLE, keyfile=SRV_KEY)
    # create SSL server
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind((HOST, PORT))
    server.listen(1)
    print(f"Listening on {HOST}:{PORT}...")
    while True:
        print("Waiting for connection...")
        # accept one connection
        conn, addr = server.accept()
        with conn:
            try:
                conn.settimeout(5)
                conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                conn.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
                with context.wrap_socket(conn, server_side=True) as ssock:
                    print(f"Connected by {addr}")
                    data = ssock.recv(1024)
                    print(data.decode())
                    body = "Hello, world!\r\n"
                    len_body = len(body)
                    http_response = (
                        f"HTTP/1.1 200 OK\r\nContent-Length: {len_body}\r\n\r\n{body}"
                    )
                    ssock.sendall(http_response.encode())
            except ssl.SSLError as err:
                print(f"SSL error: {err}")
        print("Connection closed")


if __name__ == "__main__":
    main()
