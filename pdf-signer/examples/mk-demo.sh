#!/bin/bash
#
# mk-demo.sh - Create a simple 3-page demo PDF and signature image for signing tests
#
# This script creates:
# 1. A sample PDF document that can be used to test PDF signing functionality
#    The document contains 3 pages with text, tables, and spaces reserved for signatures.
# 2. A signature image (signature-demo.png) for visible PDF signatures
#

# Set output files
SCRIPT_DIR="$(dirname "$0")"
OUTPUT_PDF="$SCRIPT_DIR/demo3page.pdf"
OUTPUT_SIG="$SCRIPT_DIR/signature-demo.png"

echo "=== Creating Demo Files for PDF Signing ==="
echo ""
echo "Output PDF:       $OUTPUT_PDF"
echo "Output Signature: $OUTPUT_SIG"
echo ""

# Create the PDF using Python and reportlab
# Use uv to ensure we're using the project's virtual environment
cd "$(dirname "$0")/.."
uv run python << 'PYTHON_SCRIPT'
import sys
from datetime import datetime
from reportlab.lib.pagesizes import letter, A4
from reportlab.lib import colors
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_RIGHT, TA_JUSTIFY
from reportlab.pdfgen import canvas

# Output file (passed from shell script)
output_file = "examples/demo3page.pdf"

# Page size
PAGE_SIZE = letter  # or A4

# Create PDF
doc = SimpleDocTemplate(
    output_file,
    pagesize=PAGE_SIZE,
    rightMargin=72,
    leftMargin=72,
    topMargin=72,
    bottomMargin=72,
)

# Container for the 'Flowable' objects
elements = []

# Get styles
styles = getSampleStyleSheet()
title_style = styles['Title']
heading_style = styles['Heading1']
normal_style = styles['Normal']
centered_style = ParagraphStyle(
    'Centered',
    parent=styles['Normal'],
    alignment=TA_CENTER,
)
right_style = ParagraphStyle(
    'Right',
    parent=styles['Normal'],
    alignment=TA_RIGHT,
)

# ============================================================================
# PAGE 1 - Title Page / Contract Cover
# ============================================================================

elements.append(Spacer(1, 2*inch))

elements.append(Paragraph("SAMPLE CONTRACT AGREEMENT", title_style))
elements.append(Spacer(1, 0.5*inch))

elements.append(Paragraph("Between", centered_style))
elements.append(Spacer(1, 0.25*inch))

elements.append(Paragraph("<b>COMPANY A</b>", centered_style))
elements.append(Paragraph("123 Business Street", centered_style))
elements.append(Paragraph("Prague, Czech Republic", centered_style))
elements.append(Spacer(1, 0.25*inch))

elements.append(Paragraph("and", centered_style))
elements.append(Spacer(1, 0.25*inch))

elements.append(Paragraph("<b>COMPANY B</b>", centered_style))
elements.append(Paragraph("456 Commerce Avenue", centered_style))
elements.append(Paragraph("Prague, Czech Republic", centered_style))

elements.append(Spacer(1, 1*inch))

current_date = datetime.now().strftime("%B %d, %Y")
elements.append(Paragraph(f"<i>Date: {current_date}</i>", centered_style))

elements.append(Spacer(1, 0.5*inch))
elements.append(Paragraph("Document Number: DOC-2025-001", centered_style))

# Page break
elements.append(PageBreak())

# ============================================================================
# PAGE 2 - Terms and Conditions
# ============================================================================

elements.append(Paragraph("Terms and Conditions", heading_style))
elements.append(Spacer(1, 0.25*inch))

# Article 1
elements.append(Paragraph("<b>Article 1: Purpose</b>", styles['Heading2']))
elements.append(Spacer(1, 0.1*inch))
elements.append(Paragraph(
    "This agreement establishes the terms and conditions under which Company A "
    "and Company B agree to collaborate on mutual business activities. Both parties "
    "acknowledge that this is a demonstration document for testing digital signature "
    "functionality.",
    normal_style
))
elements.append(Spacer(1, 0.2*inch))

# Article 2
elements.append(Paragraph("<b>Article 2: Duration</b>", styles['Heading2']))
elements.append(Spacer(1, 0.1*inch))
elements.append(Paragraph(
    "The term of this agreement shall commence on the date of signing and shall "
    "continue for a period of one (1) year, unless terminated earlier in accordance "
    "with the provisions herein.",
    normal_style
))
elements.append(Spacer(1, 0.2*inch))

# Article 3
elements.append(Paragraph("<b>Article 3: Obligations</b>", styles['Heading2']))
elements.append(Spacer(1, 0.1*inch))
elements.append(Paragraph(
    "Each party agrees to:",
    normal_style
))
elements.append(Spacer(1, 0.1*inch))

# Bullet points
obligations = [
    "Maintain confidentiality of proprietary information",
    "Perform duties in a professional and timely manner",
    "Comply with all applicable laws and regulations",
    "Notify the other party of any material changes",
]
for obligation in obligations:
    elements.append(Paragraph(f"• {obligation}", normal_style))
    elements.append(Spacer(1, 0.05*inch))

elements.append(Spacer(1, 0.2*inch))

# Article 4
elements.append(Paragraph("<b>Article 4: Financial Terms</b>", styles['Heading2']))
elements.append(Spacer(1, 0.1*inch))

# Create a simple table
financial_data = [
    ['Description', 'Amount (CZK)', 'Due Date'],
    ['Initial Payment', '50,000', '2025-11-01'],
    ['Monthly Fee', '10,000', 'Monthly'],
    ['Final Payment', '40,000', '2026-10-31'],
]

financial_table = Table(financial_data, colWidths=[3*inch, 1.5*inch, 1.5*inch])
financial_table.setStyle(TableStyle([
    ('BACKGROUND', (0, 0), (-1, 0), colors.grey),
    ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
    ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
    ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
    ('FONTSIZE', (0, 0), (-1, 0), 12),
    ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
    ('BACKGROUND', (0, 1), (-1, -1), colors.beige),
    ('GRID', (0, 0), (-1, -1), 1, colors.black),
]))

elements.append(financial_table)

# Page break
elements.append(PageBreak())

# ============================================================================
# PAGE 3 - Signature Page
# ============================================================================

elements.append(Paragraph("Signatures", heading_style))
elements.append(Spacer(1, 0.25*inch))

elements.append(Paragraph(
    "By signing below, both parties agree to the terms and conditions outlined "
    "in this agreement and acknowledge that this document has legal binding effect.",
    normal_style
))

elements.append(Spacer(1, 0.5*inch))

# Signature blocks
signature_data = [
    ['', ''],
    ['<b>COMPANY A</b>', '<b>COMPANY B</b>'],
    ['', ''],
    ['', ''],
    ['', ''],
    ['_' * 30, '_' * 30],
    ['Authorized Signature', 'Authorized Signature'],
    ['', ''],
    ['Name: ___________________', 'Name: ___________________'],
    ['', ''],
    ['Date: ___________________', 'Date: ___________________'],
]

signature_table = Table(signature_data, colWidths=[3*inch, 3*inch])
signature_table.setStyle(TableStyle([
    ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
    ('VALIGN', (0, 0), (-1, -1), 'TOP'),
    ('FONTNAME', (0, 1), (-1, 1), 'Helvetica-Bold'),
    ('FONTSIZE', (0, 1), (-1, 1), 12),
]))

elements.append(signature_table)

elements.append(Spacer(1, 1*inch))

# Notice about digital signature
elements.append(Paragraph(
    "<i>Note: This document is designed for digital signature testing. "
    "A digital signature can be placed at the bottom-right corner of this page "
    "or any other page. The signature will be visible and verifiable in PDF readers "
    "such as Adobe Acrobat.</i>",
    normal_style
))

elements.append(Spacer(1, 0.5*inch))

# Add footer
elements.append(Paragraph("=" * 80, centered_style))
elements.append(Paragraph(
    f"<i>Document generated on {current_date} for demonstration purposes</i>",
    centered_style
))

# Build PDF
doc.build(elements)

print(f"✓ Created 3-page PDF: examples/demo3page.pdf")
print("")
print("Pages:")
print("  1. Title/Cover Page")
print("  2. Terms and Conditions")
print("  3. Signature Page")

# ============================================================================
# Create Signature Image
# ============================================================================

print("")
print("Creating signature image...")

from PIL import Image, ImageDraw, ImageFont

# Image dimensions
img_width = 500
img_height = 200

# Create a new image with white background
img = Image.new('RGB', (img_width, img_height), color='white')
draw = ImageDraw.Draw(img)

# Try to use a nice font, fall back to default if not available
try:
    # Try common font paths for different systems
    font_paths = [
        "/System/Library/Fonts/Supplemental/Arial.ttf",  # macOS
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",  # Linux
        "C:\\Windows\\Fonts\\arial.ttf",  # Windows
        "/System/Library/Fonts/Helvetica.ttc",  # macOS alternative
    ]
    
    font_large = None
    font_medium = None
    font_small = None
    
    for font_path in font_paths:
        try:
            font_large = ImageFont.truetype(font_path, 36)
            font_medium = ImageFont.truetype(font_path, 24)
            font_small = ImageFont.truetype(font_path, 16)
            break
        except:
            continue
    
    if font_large is None:
        # Fallback to default font
        font_large = ImageFont.load_default()
        font_medium = ImageFont.load_default()
        font_small = ImageFont.load_default()
        
except Exception as e:
    # Use default font if all else fails
    font_large = ImageFont.load_default()
    font_medium = ImageFont.load_default()
    font_small = ImageFont.load_default()

# Draw border
border_color = (25, 25, 112)  # Midnight blue
border_width = 3
draw.rectangle(
    [(border_width, border_width), 
     (img_width - border_width, img_height - border_width)],
    outline=border_color,
    width=border_width
)

# Draw inner decorative line
inner_margin = 8
draw.rectangle(
    [(inner_margin, inner_margin), 
     (img_width - inner_margin, img_height - inner_margin)],
    outline=border_color,
    width=1
)

# Text content
text_color = (0, 0, 0)  # Black
accent_color = (25, 25, 112)  # Midnight blue

# "Digitally Signed" text at top
text1 = "Digitally Signed"
bbox1 = draw.textbbox((0, 0), text1, font=font_large)
text1_width = bbox1[2] - bbox1[0]
text1_x = (img_width - text1_width) // 2
text1_y = 40
draw.text((text1_x, text1_y), text1, fill=accent_color, font=font_large)

# Horizontal line under main text
line_y = text1_y + 50
line_margin = 50
draw.line(
    [(line_margin, line_y), (img_width - line_margin, line_y)],
    fill=accent_color,
    width=2
)

# "By: [Name]" text
text2 = "By: John Extended"
bbox2 = draw.textbbox((0, 0), text2, font=font_medium)
text2_width = bbox2[2] - bbox2[0]
text2_x = (img_width - text2_width) // 2
text2_y = line_y + 20
draw.text((text2_x, text2_y), text2, fill=text_color, font=font_medium)

# Date
date_text = f"Date: {current_date}"
bbox3 = draw.textbbox((0, 0), date_text, font=font_small)
text3_width = bbox3[2] - bbox3[0]
text3_x = (img_width - text3_width) // 2
text3_y = text2_y + 40
draw.text((text3_x, text3_y), date_text, fill=text_color, font=font_small)

# Add small decorative elements in corners
corner_size = 15
corner_color = accent_color

# Top-left corner
draw.line([(15, 15), (15 + corner_size, 15)], fill=corner_color, width=2)
draw.line([(15, 15), (15, 15 + corner_size)], fill=corner_color, width=2)

# Top-right corner
draw.line([(img_width - 15, 15), (img_width - 15 - corner_size, 15)], fill=corner_color, width=2)
draw.line([(img_width - 15, 15), (img_width - 15, 15 + corner_size)], fill=corner_color, width=2)

# Bottom-left corner
draw.line([(15, img_height - 15), (15 + corner_size, img_height - 15)], fill=corner_color, width=2)
draw.line([(15, img_height - 15), (15, img_height - 15 - corner_size)], fill=corner_color, width=2)

# Bottom-right corner
draw.line([(img_width - 15, img_height - 15), (img_width - 15 - corner_size, img_height - 15)], fill=corner_color, width=2)
draw.line([(img_width - 15, img_height - 15), (img_width - 15, img_height - 15 - corner_size)], fill=corner_color, width=2)

# Save the image
img.save("examples/signature-demo.png", "PNG")

print("✓ Created signature image: examples/signature-demo.png")
print("")
print("Dimensions: 500x200 pixels")
print("Format: PNG with professional styling")

print("")
print("=" * 60)
print("You can now sign this PDF using:")
print("  uv run python -m pdf_signer.sign sign \\")
print("      examples/demo3page.pdf \\")
print("      examples/demo3page-signed.pdf \\")
print("      --p12 certificate.p12 \\")
print("      --image examples/signature-demo.png \\")
print("      --position bottom-right \\")
print("      --page 3")

PYTHON_SCRIPT

# Check if files were created successfully
echo ""
echo "=== Results ==="
echo ""

SUCCESS=true

if [ -f "$OUTPUT_PDF" ]; then
    echo "✓ PDF created successfully:"
    ls -lh "$OUTPUT_PDF"
else
    echo "✗ Error: Failed to create PDF"
    SUCCESS=false
fi

echo ""

if [ -f "$OUTPUT_SIG" ]; then
    echo "✓ Signature image created successfully:"
    ls -lh "$OUTPUT_SIG"
else
    echo "✗ Error: Failed to create signature image"
    SUCCESS=false
fi

echo ""

if [ "$SUCCESS" = true ]; then
    echo "✅ All files created successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. View the PDF: open $OUTPUT_PDF"
    echo "  2. View the signature: open $OUTPUT_SIG"
    echo "  3. Sign the PDF using the example in the output above"
else
    echo "❌ Some files failed to create"
    exit 1
fi


