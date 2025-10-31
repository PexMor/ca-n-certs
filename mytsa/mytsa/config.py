"""Configuration management for mytsa TSA server."""

import os
from pathlib import Path
from typing import Optional


class Config:
    """Configuration class for TSA server using environment variables."""
    
    def __init__(self):
        """Initialize configuration from environment variables."""
        # Default base directory for certificates
        default_base = Path.home() / ".config" / "demo-cfssl" / "tsa" / "mytsa"
        
        # TSA certificate and key paths
        self.cert_path = Path(os.getenv(
            "TSA_CERT_PATH",
            str(default_base / "cert.pem")
        ))
        
        self.key_path = Path(os.getenv(
            "TSA_KEY_PATH",
            str(default_base / "key.pem")
        ))
        
        self.chain_path = Path(os.getenv(
            "TSA_CHAIN_PATH",
            str(default_base / "bundle-3.pem")
        ))
        
        # Serial number file path
        self.serial_path = Path(os.getenv(
            "TSA_SERIAL_PATH",
            str(default_base / "tsaserial.txt")
        ))
        
        # TSA policy OID (default is an example OID)
        self.policy_oid = os.getenv(
            "TSA_POLICY_OID",
            "1.3.6.1.4.1.13762.3"
        )
        
        # Timestamp accuracy in seconds
        self.accuracy_seconds = int(os.getenv(
            "TSA_ACCURACY_SECONDS",
            "1"
        ))
        
        # Optional key password
        self.key_password: Optional[bytes] = None
        key_pass_str = os.getenv("TSA_KEY_PASSWORD")
        if key_pass_str:
            self.key_password = key_pass_str.encode()
    
    def validate(self) -> list[str]:
        """
        Validate configuration.
        
        Returns:
            List of validation errors (empty if valid)
        """
        errors = []
        
        if not self.cert_path.exists():
            errors.append(f"TSA certificate not found: {self.cert_path}")
        
        if not self.key_path.exists():
            errors.append(f"TSA private key not found: {self.key_path}")
        
        if not self.chain_path.exists():
            errors.append(f"TSA certificate chain not found: {self.chain_path}")
        
        if self.accuracy_seconds < 0:
            errors.append(f"Accuracy seconds must be non-negative: {self.accuracy_seconds}")
        
        return errors
    
    def __repr__(self) -> str:
        """Return string representation of config (without sensitive data)."""
        return (
            f"Config("
            f"cert_path={self.cert_path}, "
            f"key_path={self.key_path}, "
            f"chain_path={self.chain_path}, "
            f"serial_path={self.serial_path}, "
            f"policy_oid={self.policy_oid}, "
            f"accuracy_seconds={self.accuracy_seconds}, "
            f"key_password={'***' if self.key_password else 'None'}"
            f")"
        )

