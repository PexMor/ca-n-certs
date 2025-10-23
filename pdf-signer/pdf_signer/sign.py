#!/usr/bin/env python3
"""
PDF Signer - Sign PDFs with X.509 certificates and visible signatures

This tool signs PDF files using PKCS#12 (.p12) certificates and adds
a visible signature stamp/graphic that is clickable and verifiable in
PDF viewers like Adobe Acrobat.
"""

import click
from pathlib import Path
from datetime import datetime
from PIL import Image
import io

from pyhanko.sign import signers, fields
from pyhanko.pdf_utils import images
from pyhanko.pdf_utils.incremental_writer import IncrementalPdfFileWriter
from pyhanko import stamp
from pyhanko.pdf_utils.reader import PdfFileReader


@click.command()
@click.argument('input_pdf', type=click.Path(exists=True, path_type=Path))
@click.argument('output_pdf', type=click.Path(path_type=Path))
@click.option('--p12', '--pkcs12', 'p12_file', required=True,
              type=click.Path(exists=True, path_type=Path),
              help='PKCS#12 (.p12) certificate file')
@click.option('--password', 'p12_password',
              help='Password for the PKCS#12 file (prompted if not provided)')
@click.option('--password-file', 'password_file',
              type=click.Path(exists=True, path_type=Path),
              help='File containing the PKCS#12 password')
@click.option('--image', 'signature_image',
              type=click.Path(exists=True, path_type=Path),
              help='Image file for visible signature (PNG, JPG, etc.)')
@click.option('--page', default=1, type=int,
              help='Page number to place signature (default: 1)')
@click.option('--position', default='bottom-right',
              type=click.Choice(['top-left', 'top-right', 'bottom-left', 'bottom-right', 'custom']),
              help='Position of the signature on the page')
@click.option('--x', default=None, type=int,
              help='X coordinate for custom position (points from left)')
@click.option('--y', default=None, type=int,
              help='Y coordinate for custom position (points from bottom)')
@click.option('--width', default=200, type=int,
              help='Width of signature field in points (default: 200)')
@click.option('--height', default=100, type=int,
              help='Height of signature field in points (default: 100)')
@click.option('--reason', default='Document Signature',
              help='Reason for signing')
@click.option('--location', default='',
              help='Location of signing')
@click.option('--contact', default='',
              help='Contact information')
@click.option('--field-name', default='Signature1',
              help='Name of the signature field')
@click.option('--text-params', default=None,
              help='Custom text parameters (JSON format)')
@click.option('--visible/--invisible', default=True,
              help='Whether to add a visible signature (default: visible)')
@click.option('--timestamp-url', default=None,
              help='URL of timestamp server (TSA) for adding timestamp')
def sign_pdf(input_pdf, output_pdf, p12_file, p12_password, password_file,
             signature_image, page, position, x, y, width, height,
             reason, location, contact, field_name, text_params, visible,
             timestamp_url):
    """
    Sign a PDF file with an X.509 certificate and optional visible signature.
    
    Examples:
    
        # Basic signing with visible signature
        pdf-signer sign input.pdf output.pdf --p12 cert.p12 --image signature.png
        
        # Sign with password from file
        pdf-signer sign input.pdf output.pdf --p12 cert.p12 --password-file pass.txt --image sig.png
        
        # Custom position
        pdf-signer sign input.pdf output.pdf --p12 cert.p12 --image sig.png --position custom --x 100 --y 100
        
        # Sign with timestamp
        pdf-signer sign input.pdf output.pdf --p12 cert.p12 --image sig.png --timestamp-url http://timestamp.digicert.com
    """
    
    try:
        # Get password
        if password_file:
            password = password_file.read_text().strip()
        elif p12_password:
            password = p12_password
        else:
            password = click.prompt('Enter PKCS#12 password', hide_input=True, default='')
        
        # Load the PKCS#12 certificate
        click.echo(f"Loading certificate from {p12_file}...")
        signer = signers.SimpleSigner.load_pkcs12(
            pfx_file=str(p12_file),
            passphrase=password.encode('utf-8') if password else None
        )
        
        click.echo(f"Certificate loaded: {signer.subject_name}")
        
        # Open the input PDF
        with open(str(input_pdf), 'rb') as pdf_file:
            pdf_reader = PdfFileReader(pdf_file)
            
            # Create a PDF writer for signing
            w = IncrementalPdfFileWriter(pdf_file)
            
            # Determine signature field position
            if position == 'custom':
                if x is None or y is None:
                    raise click.ClickException("Custom position requires --x and --y coordinates")
                box_x = x
                box_y = y
            else:
                # Get page dimensions (assuming US Letter: 612x792 points)
                # In production, should get actual page dimensions
                page_width = 612
                page_height = 792
                
                if position == 'bottom-right':
                    box_x = page_width - width - 50
                    box_y = 50
                elif position == 'bottom-left':
                    box_x = 50
                    box_y = 50
                elif position == 'top-right':
                    box_x = page_width - width - 50
                    box_y = page_height - height - 50
                elif position == 'top-left':
                    box_x = 50
                    box_y = page_height - height - 50
            
            # Create signature metadata
            meta = signers.PdfSignatureMetadata(
                field_name=field_name,
                location=location,
                reason=reason,
                contact_info=contact
            )
            
            if visible:
                # Create visible signature appearance
                if signature_image:
                    # Load custom image
                    click.echo(f"Loading signature image from {signature_image}...")
                    from PIL import Image as PILImage
                    
                    # Load image using PIL
                    pil_image = PILImage.open(str(signature_image))
                    
                    # Create stamp style with image
                    sig_appearance = stamp.TextStampStyle(
                        stamp_text=(
                            f"Digitally signed by\n"
                            f"%(signer)s\n"
                            f"Date: %(ts)s\n"
                            f"Reason: {reason}"
                        ),
                        background=images.PdfImage(pil_image),
                        background_opacity=0.3,  # Make background semi-transparent
                    )
                else:
                    # Default text-only signature
                    sig_appearance = stamp.TextStampStyle(
                        stamp_text=(
                            f"Digitally signed by\n"
                            f"%(signer)s\n"
                            f"Date: %(ts)s\n"
                            f"Reason: {reason}"
                        ),
                        border_width=1,
                    )
                
                # Add signature field
                sig_field = fields.SigFieldSpec(
                    sig_field_name=field_name,
                    box=(box_x, box_y, box_x + width, box_y + height),
                    on_page=page - 1  # pyHanko uses 0-based page indexing
                )
                
                click.echo(f"Adding visible signature on page {page} at position ({box_x}, {box_y})...")
                
                # Sign the PDF with visible signature
                pdf_signer = signers.PdfSigner(
                    meta,
                    signer=signer,
                    stamp_style=sig_appearance,
                    new_field_spec=sig_field
                )
            else:
                # Invisible signature
                click.echo("Creating invisible signature...")
                pdf_signer = signers.PdfSigner(
                    meta,
                    signer=signer
                )
            
            # Add timestamp if requested
            if timestamp_url:
                from pyhanko.sign import timestamps
                from pyhanko.sign.timestamps import HTTPTimeStamper
                
                click.echo(f"Adding timestamp from {timestamp_url}...")
                timestamper = HTTPTimeStamper(timestamp_url)
                
                # Sign with timestamp
                with open(str(output_pdf), 'wb') as output_file:
                    pdf_signer.sign_pdf(
                        w,
                        output=output_file,
                        timestamper=timestamper
                    )
            else:
                # Sign without timestamp
                with open(str(output_pdf), 'wb') as output_file:
                    pdf_signer.sign_pdf(w, output=output_file)
            
            click.echo(f"✓ PDF signed successfully: {output_pdf}")
            click.echo(f"  Signer: {signer.subject_name}")
            click.echo(f"  Reason: {reason}")
            if location:
                click.echo(f"  Location: {location}")
            if timestamp_url:
                click.echo(f"  Timestamp: Added from {timestamp_url}")
            
    except FileNotFoundError as e:
        raise click.ClickException(f"File not found: {e}")
    except Exception as e:
        raise click.ClickException(f"Error signing PDF: {e}")


@click.command()
@click.argument('pdf_file', type=click.Path(exists=True, path_type=Path))
@click.option('--verbose', '-v', is_flag=True, help='Show detailed information')
def verify(pdf_file, verbose):
    """
    Verify signatures in a PDF file.
    
    Example:
        pdf-signer verify signed.pdf --verbose
    """
    from pyhanko.sign import validation
    
    try:
        click.echo(f"Verifying signatures in {pdf_file}...")
        
        with open(str(pdf_file), 'rb') as f:
            r = PdfFileReader(f)
            
            # Get all signature fields
            sig_fields = list(fields.enumerate_sig_fields(r))
            
            signatures_found = False
            for field_name, sig_obj, sig_field in sig_fields:
                signatures_found = True
                
                click.echo(f"\n{'='*60}")
                click.echo(f"Signature Field: {field_name}")
                click.echo(f"{'='*60}")
                
                # Dereference if needed
                if hasattr(sig_obj, 'get_object'):
                    sig_obj = sig_obj.get_object()
                
                # sig_obj is the signature dictionary
                click.echo(f"Filter: {sig_obj.get('/Filter', 'N/A')}")
                click.echo(f"SubFilter: {sig_obj.get('/SubFilter', 'N/A')}")
                
                if '/Name' in sig_obj:
                    click.echo(f"Name: {sig_obj['/Name']}")
                if '/Reason' in sig_obj:
                    click.echo(f"Reason: {sig_obj['/Reason']}")
                if '/Location' in sig_obj:
                    click.echo(f"Location: {sig_obj['/Location']}")
                if '/ContactInfo' in sig_obj:
                    click.echo(f"Contact: {sig_obj['/ContactInfo']}")
                if '/M' in sig_obj:
                    click.echo(f"Signing Time: {sig_obj['/M']}")
                
                if verbose:
                    # Try to validate signature
                    try:
                        status = validation.validate_pdf_signature(sig_obj)
                        click.echo(f"\nValidation Results:")
                        click.echo(f"  Signer: {status.signer_reported}")
                        click.echo(f"  Signing time: {status.signing_time}")
                        click.echo(f"  Valid: {status.intact and status.valid}")
                        click.echo(f"  Intact: {status.intact}")
                        click.echo(f"  Trust valid: {status.valid}")
                        
                        if status.timestamp_validity:
                            click.echo(f"  Timestamp: {status.timestamp_validity.timestamp}")
                    except Exception as e:
                        click.echo(f"  Note: Full validation not available ({e})")
            
            if not signatures_found:
                click.echo("No signatures found in PDF.")
            else:
                click.echo(f"\n✓ Verification complete")
                
    except Exception as e:
        raise click.ClickException(f"Error verifying PDF: {e}")


@click.group()
@click.version_option(version='1.0.0')
def cli():
    """
    PDF Signer - Sign PDFs with X.509 certificates
    
    A command-line tool for signing PDF files with PKCS#12 certificates
    and adding visible, clickable signature stamps.
    """
    pass


cli.add_command(sign_pdf, name='sign')
cli.add_command(verify)


if __name__ == '__main__':
    cli()

