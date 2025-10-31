"""Utility functions for mytsa TSA server."""

import threading
from pathlib import Path
from typing import Optional

from asn1crypto import x509
from cryptography.hazmat.primitives import serialization


# Global lock for serial number file access
_serial_lock = threading.Lock()


def get_next_serial(serial_path: Path) -> int:
    """
    Get next serial number from file (thread-safe).
    
    Args:
        serial_path: Path to serial number file
        
    Returns:
        Next serial number
        
    Note:
        - Auto-initializes file if missing (starting at 1000)
        - Increments atomically with file locking
    """
    with _serial_lock:
        # Create directory if it doesn't exist
        serial_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Initialize if file doesn't exist
        if not serial_path.exists():
            serial_path.write_text("1000\n")
        
        # Read current serial
        try:
            serial = int(serial_path.read_text().strip())
        except (ValueError, OSError) as e:
            raise RuntimeError(f"Failed to read serial number from {serial_path}: {e}")
        
        # Write next serial
        try:
            serial_path.write_text(f"{serial + 1}\n")
        except OSError as e:
            raise RuntimeError(f"Failed to write serial number to {serial_path}: {e}")
        
        return serial


def load_certificate_chain(chain_path: Path) -> tuple[x509.Certificate, list[x509.Certificate]]:
    """
    Load certificate chain from PEM file.
    
    Args:
        chain_path: Path to PEM file containing certificate chain
        
    Returns:
        Tuple of (tsa_cert, other_certs)
        First certificate is assumed to be the TSA cert,
        remaining certificates are intermediates and root
        
    Raises:
        RuntimeError: If file cannot be read or parsed
    """
    try:
        pem_data = chain_path.read_text()
    except OSError as e:
        raise RuntimeError(f"Failed to read certificate chain from {chain_path}: {e}")
    
    # Parse all certificates from PEM data
    # Split by BEGIN CERTIFICATE markers
    cert_blocks = []
    current_block = []
    in_cert = False
    
    for line in pem_data.splitlines():
        if "BEGIN CERTIFICATE" in line:
            in_cert = True
            current_block = [line]
        elif "END CERTIFICATE" in line:
            current_block.append(line)
            cert_blocks.append("\n".join(current_block) + "\n")
            current_block = []
            in_cert = False
        elif in_cert:
            current_block.append(line)
    
    if not cert_blocks:
        raise RuntimeError(f"No certificates found in {chain_path}")
    
    # Parse each PEM block
    certs = []
    for cert_pem in cert_blocks:
        try:
            # asn1crypto can parse PEM directly
            cert = x509.Certificate.load(cert_pem.encode())
            certs.append(cert)
        except Exception as e:
            # If PEM parsing fails, try to extract base64 and decode
            try:
                import base64
                # Extract base64 content between BEGIN and END
                lines = [l for l in cert_pem.split('\n') 
                        if l and not l.startswith('-----')]
                b64_data = ''.join(lines)
                der_data = base64.b64decode(b64_data)
                cert = x509.Certificate.load(der_data)
                certs.append(cert)
            except Exception as e2:
                raise RuntimeError(f"Failed to parse certificate from {chain_path}: {e2}")
    
    # First cert is TSA cert, rest are chain
    return certs[0], certs[1:]


def load_private_key(key_path: Path, password: Optional[bytes] = None):
    """
    Load private key from PEM file.
    
    Args:
        key_path: Path to PEM file containing private key
        password: Optional password for encrypted key
        
    Returns:
        Private key object (RSA or ECDSA)
        
    Raises:
        RuntimeError: If file cannot be read or parsed
    """
    try:
        key_data = key_path.read_bytes()
    except OSError as e:
        raise RuntimeError(f"Failed to read private key from {key_path}: {e}")
    
    try:
        key = serialization.load_pem_private_key(key_data, password=password)
    except Exception as e:
        raise RuntimeError(f"Failed to parse private key from {key_path}: {e}")
    
    return key

