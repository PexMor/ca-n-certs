#!/usr/bin/env python3
"""
OCSP Responder for demo-cfssl
Built with FastAPI and cryptography library
"""

import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, Request, Response, HTTPException
from fastapi.responses import PlainTextResponse
from cryptography import x509
from cryptography.x509 import ocsp
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, ec
from cryptography.hazmat.backends import default_backend
import uvicorn

# Configuration
BD = os.environ.get('DEMO_CFSSL_DIR', os.path.expanduser('~/.config/demo-cfssl'))
CA_CERT_PATH = os.path.join(BD, 'ca.pem')
CA_KEY_PATH = os.path.join(BD, 'ca-key.pem')
ICA_CERT_PATH = os.path.join(BD, 'ica-ca.pem')
ICA_KEY_PATH = os.path.join(BD, 'ica-key.pem')
CRL_DIR = os.path.join(BD, 'crl')

# Initialize FastAPI app
app = FastAPI(
    title="OCSP Responder",
    description="OCSP Responder for demo-cfssl Certificate Authority",
    version="1.0.0"
)


class OCSPResponder:
    """OCSP Responder handling certificate status checks"""
    
    def __init__(self):
        self.ca_cert = None
        self.ca_key = None
        self.ica_cert = None
        self.ica_key = None
        self.revoked_certs = {}
        self.load_certificates()
        self.load_revocation_database()
    
    def load_certificates(self):
        """Load CA and ICA certificates and private keys"""
        try:
            # Load Root CA
            with open(CA_CERT_PATH, 'rb') as f:
                self.ca_cert = x509.load_pem_x509_certificate(f.read(), default_backend())
            with open(CA_KEY_PATH, 'rb') as f:
                self.ca_key = serialization.load_pem_private_key(
                    f.read(), password=None, backend=default_backend()
                )
            
            # Load Intermediate CA
            with open(ICA_CERT_PATH, 'rb') as f:
                self.ica_cert = x509.load_pem_x509_certificate(f.read(), default_backend())
            with open(ICA_KEY_PATH, 'rb') as f:
                self.ica_key = serialization.load_pem_private_key(
                    f.read(), password=None, backend=default_backend()
                )
            
            print(f"✓ Loaded CA certificates from {BD}")
        except Exception as e:
            print(f"✗ Error loading certificates: {e}", file=sys.stderr)
            sys.exit(1)
    
    def load_revocation_database(self):
        """Load revocation database from CRL directory"""
        self.revoked_certs = {
            'ca': {},
            'ica': {}
        }
        
        for ca_type in ['ca', 'ica']:
            db_dir = os.path.join(CRL_DIR, ca_type)
            if not os.path.exists(db_dir):
                continue
            
            # Load from database.txt if it exists
            db_file = os.path.join(db_dir, 'database.txt')
            if os.path.exists(db_file):
                with open(db_file, 'r') as f:
                    for line in f:
                        line = line.strip()
                        if not line or line.startswith('#'):
                            continue
                        
                        # Format: R|serial|revocation_date|reason|CN
                        parts = line.split('|')
                        if len(parts) >= 4 and parts[0] == 'R':
                            serial = int(parts[1], 16)
                            revocation_date = datetime.fromisoformat(parts[2])
                            reason = parts[3]
                            
                            # Map reason text to OCSP reason code
                            reason_map = {
                                'unspecified': x509.ReasonFlags.unspecified,
                                'keyCompromise': x509.ReasonFlags.key_compromise,
                                'CACompromise': x509.ReasonFlags.ca_compromise,
                                'affiliationChanged': x509.ReasonFlags.affiliation_changed,
                                'superseded': x509.ReasonFlags.superseded,
                                'cessationOfOperation': x509.ReasonFlags.cessation_of_operation,
                                'certificateHold': x509.ReasonFlags.certificate_hold,
                            }
                            
                            self.revoked_certs[ca_type][serial] = {
                                'revocation_time': revocation_date,
                                'reason': reason_map.get(reason, x509.ReasonFlags.unspecified)
                            }
        
        total_revoked = sum(len(v) for v in self.revoked_certs.values())
        print(f"✓ Loaded {total_revoked} revoked certificates from database")
    
    def get_issuer_and_key(self, cert_serial: int) -> tuple:
        """Determine which CA issued the certificate"""
        # For simplicity, check if serial is in ICA revocation list first
        # In practice, you'd check the issuer from the OCSP request
        if cert_serial in self.revoked_certs['ica']:
            return self.ica_cert, self.ica_key, 'ica'
        
        # Default to ICA for certificates (most common case)
        return self.ica_cert, self.ica_key, 'ica'
    
    def check_certificate_status(self, serial_number: int, ca_type: str):
        """Check if certificate is revoked"""
        if serial_number in self.revoked_certs[ca_type]:
            revoked_info = self.revoked_certs[ca_type][serial_number]
            return 'revoked', revoked_info
        return 'good', None
    
    def create_ocsp_response(self, ocsp_request_der: bytes) -> bytes:
        """Create OCSP response for the given request"""
        try:
            # Parse OCSP request
            ocsp_req = ocsp.load_der_ocsp_request(ocsp_request_der)
            
            # Get the certificate serial number from the request
            cert_serial = ocsp_req.serial_number
            
            # Determine issuer
            issuer_cert, issuer_key, ca_type = self.get_issuer_and_key(cert_serial)
            
            # Check certificate status
            cert_status, revoked_info = self.check_certificate_status(cert_serial, ca_type)
            
            # Create response builder
            builder = ocsp.OCSPResponseBuilder()
            
            # Current time
            this_update = datetime.now(timezone.utc)
            next_update = this_update + timedelta(hours=24)
            
            if cert_status == 'revoked':
                # Certificate is revoked
                builder = builder.add_response(
                    cert=x509.CertificateBuilder().subject_name(
                        x509.Name([])
                    ).issuer_name(
                        issuer_cert.subject
                    ).public_key(
                        issuer_cert.public_key()
                    ).serial_number(
                        cert_serial
                    ).not_valid_before(
                        datetime.now(timezone.utc)
                    ).not_valid_after(
                        datetime.now(timezone.utc) + timedelta(days=1)
                    ).sign(issuer_key, hashes.SHA256(), default_backend()),
                    issuer=issuer_cert,
                    algorithm=hashes.SHA256(),
                    cert_status=ocsp.OCSPCertStatus.REVOKED,
                    this_update=this_update,
                    next_update=next_update,
                    revocation_time=revoked_info['revocation_time'],
                    revocation_reason=revoked_info['reason']
                ).responder_id(
                    ocsp.OCSPResponderEncoding.HASH, issuer_cert
                )
            else:
                # Certificate is good
                builder = builder.add_response(
                    cert=x509.CertificateBuilder().subject_name(
                        x509.Name([])
                    ).issuer_name(
                        issuer_cert.subject
                    ).public_key(
                        issuer_cert.public_key()
                    ).serial_number(
                        cert_serial
                    ).not_valid_before(
                        datetime.now(timezone.utc)
                    ).not_valid_after(
                        datetime.now(timezone.utc) + timedelta(days=1)
                    ).sign(issuer_key, hashes.SHA256(), default_backend()),
                    issuer=issuer_cert,
                    algorithm=hashes.SHA256(),
                    cert_status=ocsp.OCSPCertStatus.GOOD,
                    this_update=this_update,
                    next_update=next_update
                ).responder_id(
                    ocsp.OCSPResponderEncoding.HASH, issuer_cert
                )
            
            # Sign and build response
            response = builder.sign(issuer_key, hashes.SHA256())
            return response.public_bytes(serialization.Encoding.DER)
            
        except Exception as e:
            print(f"Error creating OCSP response: {e}", file=sys.stderr)
            # Return "internal error" response
            builder = ocsp.OCSPResponseBuilder()
            response = builder.build_unsuccessful(
                ocsp.OCSPResponseStatus.INTERNAL_ERROR
            )
            return response.public_bytes(serialization.Encoding.DER)


# Initialize OCSP responder
responder = OCSPResponder()


@app.get("/")
async def root():
    """Root endpoint with service information"""
    return {
        "service": "OCSP Responder",
        "version": "1.0.0",
        "ca_base_dir": BD,
        "endpoints": {
            "ocsp": "/ocsp (POST with OCSP request)",
            "health": "/health",
            "status": "/status"
        }
    }


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "timestamp": datetime.now(timezone.utc).isoformat()
    }


@app.get("/status")
async def status():
    """Status endpoint showing revoked certificates count"""
    total_revoked = sum(len(v) for v in responder.revoked_certs.values())
    return {
        "ca_loaded": responder.ca_cert is not None,
        "ica_loaded": responder.ica_cert is not None,
        "revoked_certificates": {
            "ca": len(responder.revoked_certs['ca']),
            "ica": len(responder.revoked_certs['ica']),
            "total": total_revoked
        },
        "timestamp": datetime.now(timezone.utc).isoformat()
    }


@app.post("/ocsp")
async def ocsp_endpoint(request: Request):
    """
    OCSP endpoint handling certificate status requests
    Accepts POST requests with DER-encoded OCSP requests
    """
    try:
        # Read request body (DER-encoded OCSP request)
        ocsp_request_der = await request.body()
        
        if not ocsp_request_der:
            raise HTTPException(status_code=400, detail="Empty OCSP request")
        
        # Process OCSP request and create response
        ocsp_response_der = responder.create_ocsp_response(ocsp_request_der)
        
        # Return DER-encoded OCSP response
        return Response(
            content=ocsp_response_der,
            media_type="application/ocsp-response"
        )
    
    except Exception as e:
        print(f"Error processing OCSP request: {e}", file=sys.stderr)
        raise HTTPException(status_code=500, detail="Internal server error")


@app.get("/ocsp")
async def ocsp_get_info():
    """
    GET endpoint for OCSP (informational only)
    OCSP requests should use POST
    """
    return {
        "message": "OCSP endpoint - use POST with application/ocsp-request",
        "info": "This endpoint validates certificate status via OCSP protocol"
    }


if __name__ == "__main__":
    # Check if certificates exist
    if not os.path.exists(CA_CERT_PATH):
        print(f"Error: CA certificate not found at {CA_CERT_PATH}", file=sys.stderr)
        print("Please run the certificate generation scripts first.", file=sys.stderr)
        sys.exit(1)
    
    # Run server
    print("\n" + "="*70)
    print("Starting OCSP Responder")
    print("="*70)
    print(f"Certificate Directory: {BD}")
    print(f"Root CA: {CA_CERT_PATH}")
    print(f"Intermediate CA: {ICA_CERT_PATH}")
    print(f"CRL Database: {CRL_DIR}")
    print("="*70 + "\n")
    
    uvicorn.run(
        app,
        host=os.environ.get('OCSP_HOST', '0.0.0.0'),
        port=int(os.environ.get('OCSP_PORT', 8080)),
        log_level="info"
    )

