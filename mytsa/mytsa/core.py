"""Core TSA (Time Stamp Authority) implementation for RFC 3161."""

import hashlib
from datetime import datetime, timezone
from asn1crypto import algos, cms, core, tsp
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec, padding, rsa

from .config import Config
from .utils import get_next_serial, load_certificate_chain, load_private_key


class TimeStampAuthority:
    """
    RFC 3161 Time Stamp Authority implementation.
    
    This class handles:
    - Parsing TimeStampReq (TSQ) requests
    - Generating TSTInfo structures
    - Creating CMS SignedData wrappers
    - Building TimeStampResp (TSR) responses
    """
    
    def __init__(self, config: Config):
        """
        Initialize TSA with configuration.
        
        Args:
            config: TSA configuration
            
        Raises:
            RuntimeError: If configuration is invalid or certificates cannot be loaded
        """
        self.config = config
        
        # Validate configuration
        errors = config.validate()
        if errors:
            raise RuntimeError(f"Invalid configuration: {'; '.join(errors)}")
        
        # Load certificate chain
        self.tsa_cert, self.chain_certs = load_certificate_chain(config.chain_path)
        
        # Load private key
        self.private_key = load_private_key(config.key_path, config.key_password)
    
    def process_request(self, tsq_data: bytes) -> bytes:
        """
        Process a TimeStampReq and generate TimeStampResp.
        
        Args:
            tsq_data: DER-encoded TimeStampReq
            
        Returns:
            DER-encoded TimeStampResp
            
        Raises:
            ValueError: If request is invalid
            RuntimeError: If timestamp generation fails
        """
        # Parse TSQ
        try:
            tsq = tsp.TimeStampReq.load(tsq_data)
        except Exception as e:
            return self._error_response("bad_data_format", f"Invalid TSQ: {e}")
        
        # Validate message imprint
        mi: tsp.MessageImprint = tsq['message_imprint']
        digest_oid = mi['hash_algorithm']['algorithm'].dotted
        
        # Check supported algorithms (SHA-256 and SHA-384)
        if digest_oid not in ('2.16.840.1.101.3.4.2.1', '2.16.840.1.101.3.4.2.2'):
            return self._error_response('bad_alg', f"Unsupported hash algorithm: {digest_oid}")
        
        # Get next serial number
        try:
            serial = get_next_serial(self.config.serial_path)
        except Exception as e:
            return self._error_response('system_failure', f"Failed to get serial: {e}")
        
        # Build TSTInfo
        now = datetime.now(timezone.utc)
        tst_info = tsp.TSTInfo({
            'version': 'v1',
            'policy': self.config.policy_oid,
            'message_imprint': mi,
            'serial_number': serial,
            'gen_time': core.GeneralizedTime(now),
            'accuracy': tsp.Accuracy({'seconds': self.config.accuracy_seconds}),
            'ordering': False,
        })
        
        # Add nonce if present in request
        if 'nonce' in tsq and tsq['nonce'].native is not None:
            tst_info['nonce'] = tsq['nonce']
        
        # Create CMS SignedData
        try:
            signed_data = self._create_signed_data(tst_info)
        except Exception as e:
            import traceback
            traceback.print_exc()
            return self._error_response('system_failure', f"Failed to create signed data: {e}")
        
        # Wrap in ContentInfo
        try:
            token = cms.ContentInfo({
                'content_type': 'signed_data',
                'content': signed_data
            })
        except Exception as e:
            import traceback
            traceback.print_exc()
            return self._error_response('system_failure', f"Failed to create content info: {e}")
        
        # Build TimeStampResp with granted status
        try:
            # Note: asn1crypto might use different field names
            # Try both snake_case and the actual ASN.1 field name
            status_info = tsp.PKIStatusInfo({'status': 'granted'})
            
            tsr = tsp.TimeStampResp()
            tsr['status'] = status_info
            tsr['time_stamp_token'] = token  # asn1crypto uses snake_case for Python
            
            return tsr.dump()
        except Exception as e:
            import traceback
            traceback.print_exc()
            return self._error_response('system_failure', f"Failed to create TSR: {e}")
    
    def _create_signed_data(self, tst_info: tsp.TSTInfo) -> cms.SignedData:
        """
        Create CMS SignedData for TSTInfo.
        
        Args:
            tst_info: TSTInfo structure to sign
            
        Returns:
            CMS SignedData structure
        """
        # Encapsulate TSTInfo as eContent with contentType 'tst_info'
        # Build EncapsulatedContentInfo first to ensure the correct [0] EXPLICIT tag
        encapsulated = cms.EncapsulatedContentInfo({
            'content_type': cms.ContentType('tst_info'),  # 1.2.840.113549.1.9.16.1.4
            'content': tst_info
        })

        # asn1crypto's SignedData expects a cms.ContentInfo instance, so we reload
        # the encoded structure as ContentInfo to preserve the tagging produced above.
        econtent = cms.ContentInfo.load(encapsulated.dump())
        
        # Determine hash algorithm
        hash_algo = 'sha256'
        hash_func = hashes.SHA256()
        
        # Prepare signed attributes (must be in canonical order by OID)
        digest_value = hashlib.sha256(tst_info.dump()).digest()

        signed_attrs = cms.CMSAttributes([
            cms.CMSAttribute({
                'type': cms.CMSAttributeType('content_type'),
                'values': [cms.ContentType('tst_info')]
            }),
            cms.CMSAttribute({
                'type': cms.CMSAttributeType('message_digest'),
                'values': [core.OctetString(digest_value)]
            }),
            cms.CMSAttribute({
                'type': cms.CMSAttributeType('signing_time'),
                'values': [cms.Time({'generalized_time': core.GeneralizedTime(datetime.now(timezone.utc))})]
            }),
            # Optional ESS signing-certificate-v2 attribute could be added here
        ])

        signed_attr_bytes = signed_attrs.dump()
        
        # Sign the DER of signed attributes
        signature = self._sign_data(signed_attr_bytes, hash_func)
        
        # Determine signature algorithm
        if isinstance(self.private_key, rsa.RSAPrivateKey):
            sig_algo = algos.SignedDigestAlgorithm({'algorithm': 'rsassa_pkcs1v15'})
        elif isinstance(self.private_key, ec.EllipticCurvePrivateKey):
            sig_algo = algos.SignedDigestAlgorithm({'algorithm': 'sha256_ecdsa'})
        else:
            raise RuntimeError(f"Unsupported key type: {type(self.private_key)}")
        
        # Create SignerInfo
        signer_info = cms.SignerInfo({
            'version': 'v1',
            'sid': cms.SignerIdentifier({
                'issuer_and_serial_number': cms.IssuerAndSerialNumber({
                    'issuer': self.tsa_cert.issuer,
                    'serial_number': self.tsa_cert.serial_number
                })
            }),
            'digest_algorithm': algos.DigestAlgorithm({'algorithm': hash_algo}),
            'signed_attrs': signed_attrs,
            'signature_algorithm': sig_algo,
            'signature': core.OctetString(signature),
        })
        
        # Build SignedData
        signed_data = cms.SignedData()
        signed_data['version'] = 'v1'
        signed_data['digest_algorithms'] = [algos.DigestAlgorithm({'algorithm': hash_algo})]
        signed_data['encap_content_info'] = econtent  # ContentInfo with ParsableOctetString
        signed_data['certificates'] = [self.tsa_cert] + self.chain_certs
        signed_data['signer_infos'] = [signer_info]
        
        return signed_data
    
    def _sign_data(self, data: bytes, hash_func) -> bytes:
        """
        Sign data with private key.
        
        Args:
            data: Data to sign
            hash_func: Hash function to use
            
        Returns:
            Signature bytes
        """
        if isinstance(self.private_key, rsa.RSAPrivateKey):
            return self.private_key.sign(
                data,
                padding.PKCS1v15(),
                hash_func
            )
        elif isinstance(self.private_key, ec.EllipticCurvePrivateKey):
            return self.private_key.sign(
                data,
                ec.ECDSA(hash_func)
            )
        else:
            raise RuntimeError(f"Unsupported key type: {type(self.private_key)}")
    
    
    def _error_response(self, fail_code: str, message: str) -> bytes:
        """
        Build error TimeStampResp.
        
        Args:
            fail_code: RFC 3161 failure code
            message: Error message
            
        Returns:
            DER-encoded TimeStampResp with rejection status
        """
        # PKIFailureInfo expects a set of strings, not a dict
        resp = tsp.TimeStampResp({
            'status': tsp.PKIStatusInfo({
                'status': 'rejection',
                'status_string': [message],
                'fail_info': tsp.PKIFailureInfo(set([fail_code]))
            })
        })
        return resp.dump()

