# Quick Start Guide

Get started with PDF signing in 5 minutes!

## Prerequisites

- Python 3.13+ installed
- `uv` package manager ([install here](https://github.com/astral-sh/uv))
- A PKCS#12 (.p12) certificate file

## Create Demo Files

First, create a sample 3-page PDF and signature image for testing:

```bash
cd examples
./mk-demo.sh
```

This generates:

- `demo3page.pdf` - A 3-page sample contract ready for signing
- `signature-demo.png` - A professional signature image (500x200 pixels)

Both files are created automatically using pure Python - no external tools required!

## Installation

```bash
cd pdf-signer
uv sync
```

## Basic Usage

### 1. Sign a PDF (simplest form)

```bash
uv run python -m pdf_signer.sign sign input.pdf output.pdf --p12 certificate.p12
```

You'll be prompted for the certificate password.

### 2. Sign with a visible signature image

```bash
uv run python -m pdf_signer.sign sign input.pdf output.pdf \
    --p12 certificate.p12 \
    --image signature.png
```

### 3. Sign with password from file

```bash
echo "your-password" > password.txt
uv run python -m pdf_signer.sign sign input.pdf output.pdf \
    --p12 certificate.p12 \
    --password-file password.txt \
    --image signature.png
```

### 4. Verify a signed PDF

```bash
uv run python -m pdf_signer.sign verify signed-output.pdf --verbose
```

## Using with demo-cfssl Certificates

If you've generated certificates using the demo-cfssl project:

```bash
# Sign with your S/MIME certificate
uv run python -m pdf_signer.sign sign document.pdf signed.pdf \
    --p12 ~/.config/demo-cfssl/smime-openssl/john_extended/email.p12 \
    --image signature.png \
    --reason "Document Approval"
```

## Creating a Signature Image

### Option 1: Use the Demo Generator (Recommended)

The `mk-demo.sh` script automatically creates a professional signature image:

```bash
cd examples
./mk-demo.sh  # Creates signature-demo.png
```

The generated image has professional styling with borders, decorative elements, and proper dimensions. You can customize the signer name by editing the Python code in the script.

### Option 2: Use any image editor

- Create a PNG image (recommended: 500x200 pixels)
- Add your signature or company logo
- Save as `signature.png`

### Option 3: Use ImageMagick (if installed)

```bash
convert -size 500x200 xc:white \
    -font Arial -pointsize 24 \
    -fill black \
    -gravity center \
    -annotate +0+0 "Your Name\nYour Title" \
    -bordercolor black -border 2 \
    signature.png
```

## Common Options

```bash
# Sign on a specific page
--page 2

# Position the signature
--position bottom-right  # or top-left, top-right, bottom-left

# Custom position
--position custom --x 100 --y 100

# Add metadata
--reason "Contract Approval" \
--location "Prague, CZ" \
--contact "admin@example.com"

# Add timestamp
--timestamp-url http://timestamp.digicert.com
```

## Troubleshooting

### "No such file or directory: pdf-signer"

Run the tool using:

```bash
uv run python -m pdf_signer.sign sign ...
```

instead of just `pdf-signer`.

### "Failed to load PKCS#12 file"

- Check your password
- Ensure the .p12 file is not corrupted
- Try exporting a new certificate

### Signature not visible

- Try opening in Adobe Acrobat Reader (best support)
- Check if `--visible` flag is set (it's default)
- Verify the signature position is on the correct page

## Next Steps

- Read the full [README.md](README.md) for all options
- Check [ALTERNATIVES.md](ALTERNATIVES.md) for tool comparisons
- See [examples/sign-example.sh](examples/sign-example.sh) for automation

## Support

- pyHanko Documentation: https://pyhanko.readthedocs.io/
- Demo CFSSL Project: ../README.md
