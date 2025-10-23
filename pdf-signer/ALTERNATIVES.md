# PDF Signing Tools - Alternatives Comparison

This document compares various tools and libraries available for PDF signing with visible signatures.

## Python Libraries

### 1. **pyHanko** ⭐ (Used by this project)

**Pros:**

- ✅ Most comprehensive Python PDF signing library
- ✅ Full PAdES support (PDF Advanced Electronic Signatures)
- ✅ Visible signatures with custom images and text
- ✅ Timestamp support (TSA/RFC 3161)
- ✅ Long-term validation (LTV)
- ✅ Active development
- ✅ Pure Python (cross-platform)
- ✅ Well-documented

**Cons:**

- ⚠️ Larger dependency footprint
- ⚠️ Can be complex for simple use cases

**Installation:**

```bash
pip install pyhanko
# or with uv
uv add pyhanko
```

**Basic Example:**

```python
from pyhanko.sign import signers
from pyhanko.pdf_utils.incremental_writer import IncrementalPdfFileWriter

# Load P12
with open('cert.p12', 'rb') as p12:
    signer = signers.SimpleSigner.load_pkcs12(p12, passphrase=b'password')

# Sign
with open('input.pdf', 'rb') as inf:
    w = IncrementalPdfFileWriter(inf)
    with open('output.pdf', 'wb') as outf:
        signers.PdfSigner(
            signers.PdfSignatureMetadata(field_name='Signature1'),
            signer=signer
        ).sign_pdf(w, output=outf)
```

---

### 2. **endesive**

**Pros:**

- ✅ Simpler API than pyHanko
- ✅ Supports PKCS#12
- ✅ Can add visible signatures
- ✅ Supports HSM/smart cards

**Cons:**

- ⚠️ Less active development
- ⚠️ Limited documentation
- ⚠️ Fewer advanced features

**Installation:**

```bash
pip install endesive
```

**Basic Example:**

```python
from endesive import pdf

# Sign PDF
with open('input.pdf', 'rb') as f:
    datau = f.read()

# Sign with P12
datas = pdf.cms.sign(
    datau,
    'cert.p12',
    'password',
    'signature reason'
)

with open('output.pdf', 'wb') as f:
    f.write(datas)
```

---

### 3. **PyPDF2 / pypdf**

**Pros:**

- ✅ Lightweight
- ✅ Good for PDF manipulation

**Cons:**

- ❌ No built-in PDF signing support
- ❌ Would need to implement signing from scratch

**Not recommended for signing.**

---

## Command-Line Tools

### 4. **pdfsig** (from poppler-utils)

**Pros:**

- ✅ Available on most Linux distributions
- ✅ Simple command-line interface
- ✅ Free and open-source

**Cons:**

- ❌ **Verification only** - cannot sign PDFs
- ❌ No visible signature support
- ❌ Limited to verification use case

**Installation:**

```bash
# Ubuntu/Debian
sudo apt-get install poppler-utils

# macOS
brew install poppler

# Windows
choco install poppler
```

**Usage:**

```bash
# Verify only
pdfsig signed.pdf
```

---

### 5. **PortableSigner** (Java-based)

**Pros:**

- ✅ GUI and command-line modes
- ✅ Visible signatures
- ✅ Cross-platform (Java)
- ✅ Timestamp support

**Cons:**

- ⚠️ Requires Java Runtime
- ⚠️ Primarily GUI-focused
- ⚠️ Command-line interface less documented

**Website:** https://sourceforge.net/projects/portablesigner/

---

### 6. **SignPDF** (Various implementations)

Multiple tools exist with this name, mostly Linux-focused shell scripts wrapping OpenSSL and other tools.

**Cons:**

- ⚠️ Not standardized
- ⚠️ Often Linux-only
- ⚠️ Variable quality and maintenance

---

### 7. **jPDFSign** (Commercial)

**Pros:**

- ✅ Professional solution
- ✅ Comprehensive features
- ✅ Good support

**Cons:**

- ❌ Commercial license required
- ❌ Java-based

**Website:** https://www.qoppa.com/pdfsign/

---

## JavaScript/Node.js Libraries

### 8. **node-signpdf**

**Pros:**

- ✅ JavaScript/TypeScript support
- ✅ Works with Node.js
- ✅ Can integrate with web applications

**Cons:**

- ⚠️ Limited visible signature support
- ⚠️ Requires additional dependencies for full features

**Installation:**

```bash
npm install node-signpdf
```

---

### 9. **pdf-lib** + **node-forge**

**Pros:**

- ✅ Popular PDF manipulation library
- ✅ Can be combined with node-forge for signing

**Cons:**

- ⚠️ Need to implement signing logic yourself
- ⚠️ Complex setup

---

## Desktop Applications

### 10. **Adobe Acrobat** (Commercial)

**Pros:**

- ✅ Industry standard
- ✅ Full featured
- ✅ Best visual signature support
- ✅ Excellent verification

**Cons:**

- ❌ Commercial license required
- ❌ Not scriptable/CLI
- ❌ Windows/macOS only

---

### 11. **LibreOffice Draw**

**Pros:**

- ✅ Free and open-source
- ✅ Can sign PDFs
- ✅ Cross-platform

**Cons:**

- ❌ Not command-line
- ⚠️ Limited signature appearance options
- ⚠️ Primarily a GUI tool

---

## Comparison Summary

| Tool               | Language   | CLI | Visible Sig | Timestamp | Cross-Platform | License    | Recommended For         |
| ------------------ | ---------- | --- | ----------- | --------- | -------------- | ---------- | ----------------------- |
| **pyHanko**        | Python     | ✅  | ✅          | ✅        | ✅             | FOSS       | **Best overall choice** |
| **endesive**       | Python     | ✅  | ✅          | ⚠️        | ✅             | FOSS       | Simple use cases        |
| **pdfsig**         | C          | ✅  | ❌          | ❌        | ✅             | FOSS       | Verification only       |
| **PortableSigner** | Java       | ⚠️  | ✅          | ✅        | ✅             | FOSS       | GUI users               |
| **node-signpdf**   | JavaScript | ✅  | ⚠️          | ⚠️        | ✅             | FOSS       | Node.js projects        |
| **Adobe Acrobat**  | -          | ❌  | ✅          | ✅        | ⚠️             | Commercial | Professional use        |

---

## Why We Chose pyHanko

For this project, we chose **pyHanko** because:

1. **Comprehensive Features**: Full support for visible signatures, timestamps, and PAdES
2. **Pure Python**: No system dependencies, easy cross-platform deployment
3. **Active Development**: Regular updates and good community support
4. **Standards Compliant**: Follows ISO 32000 and PAdES specifications
5. **Excellent Documentation**: Well-documented API and examples
6. **CLI-Friendly**: Easy to wrap in a command-line tool
7. **Integration**: Works well with demo-cfssl certificates

---

## Alternative Approaches

### Using OpenSSL Directly

You could theoretically use OpenSSL to create PKCS#7 signatures and attach them to PDFs, but:

- ❌ Very complex to implement correctly
- ❌ No visible signature support out-of-the-box
- ❌ Would need deep PDF format knowledge
- ❌ Not recommended unless you're building a PDF library

### Using System APIs

- **Windows**: CryptoAPI can sign PDFs but requires Windows-specific code
- **macOS**: PDFKit has signing capabilities but Swift/Objective-C only
- **Linux**: No native PDF signing API

---

## Conclusion

**For cross-platform CLI PDF signing with visible signatures:**

- ✅ **Use pyHanko** (our choice)
- ⚠️ Consider **endesive** if you need simpler API
- ⚠️ Consider **PortableSigner** if Java ecosystem is preferred

**For verification only:**

- ✅ **Use pdfsig** from poppler-utils

**For GUI applications:**

- ✅ **Use Adobe Acrobat** (commercial)
- ⚠️ **Use PortableSigner** (FOSS)

---

## Resources

- **pyHanko Documentation**: https://pyhanko.readthedocs.io/
- **PDF Signature Standards**: ISO 32000-2, PAdES (ETSI EN 319 142)
- **Timestamp Protocol**: RFC 3161
- **PKCS#12**: RFC 7292
