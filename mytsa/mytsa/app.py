"""FastAPI application for mytsa TSA server."""

import logging
from pathlib import Path

from fastapi import FastAPI, Request, Response, HTTPException
from fastapi.responses import FileResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware

from .config import Config
from .core import TimeStampAuthority

__version__ = "0.1.0"

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Create FastAPI app
app = FastAPI(
    title="mytsa - RFC 3161 Time Stamp Authority",
    description="Pure-Python RFC 3161 Time Stamp Authority server",
    version=__version__,
)

# Add CORS middleware for web client access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize TSA
config = None
tsa = None


@app.on_event("startup")
async def startup_event():
    """Initialize TSA on startup."""
    global config, tsa
    
    logger.info("Starting mytsa TSA server...")
    
    # Load configuration
    try:
        config = Config()
        logger.info(f"Configuration loaded: {config}")
    except Exception as e:
        logger.error(f"Failed to load configuration: {e}")
        raise
    
    # Validate configuration
    errors = config.validate()
    if errors:
        logger.error(f"Configuration validation failed: {'; '.join(errors)}")
        logger.error("Please ensure TSA certificates exist. Run 'steps.sh' with step_tsa() to generate them.")
        raise RuntimeError(f"Invalid configuration: {'; '.join(errors)}")
    
    # Initialize TSA
    try:
        tsa = TimeStampAuthority(config)
        logger.info("TSA initialized successfully")
        logger.info(f"TSA certificate: {config.cert_path}")
        logger.info(f"Policy OID: {config.policy_oid}")
    except Exception as e:
        logger.error(f"Failed to initialize TSA: {e}")
        raise


@app.get("/")
async def root():
    """Root endpoint with API information."""
    return {
        "name": "mytsa - RFC 3161 Time Stamp Authority",
        "version": __version__,
        "description": "Pure-Python Time Stamp Authority server",
        "endpoints": {
            "POST /tsa": "RFC 3161 timestamp endpoint (Content-Type: application/timestamp-query)",
            "GET /tsa/certs": "Download TSA certificate chain",
            "GET /health": "Health check endpoint",
            "GET /": "This information page"
        },
        "status": "ready" if tsa else "initializing",
        "policy_oid": config.policy_oid if config else None,
    }


@app.get("/health")
async def health():
    """Health check endpoint."""
    if tsa is None:
        raise HTTPException(status_code=503, detail="TSA not initialized")
    
    return {
        "status": "healthy",
        "version": __version__,
        "tsa_ready": True,
    }


@app.get("/tsa/certs")
async def get_tsa_certs():
    """
    Serve TSA certificate chain.
    
    Returns the certificate chain (TSA cert + intermediates + root) as a downloadable PEM file.
    """
    if config is None:
        raise HTTPException(status_code=503, detail="TSA not initialized")
    
    chain_path = config.chain_path
    
    if not chain_path.exists():
        raise HTTPException(status_code=404, detail="Certificate chain not found")
    
    return FileResponse(
        path=chain_path,
        media_type="application/x-pem-file",
        filename="tsa-chain.pem",
        headers={
            "Content-Disposition": "attachment; filename=tsa-chain.pem"
        }
    )


@app.post("/tsa")
async def timestamp(request: Request):
    """
    RFC 3161 Time-Stamp Protocol endpoint.
    
    Accepts a DER-encoded TimeStampReq (TSQ) in the body and returns a DER-encoded TimeStampResp (TSR).
    Content-Type MUST be application/timestamp-query per RFC 3161.
    """
    if tsa is None:
        raise HTTPException(status_code=503, detail="TSA not initialized")
    
    # Validate Content-Type
    content_type = request.headers.get("content-type", "").lower().split(";")[0].strip()
    if content_type != "application/timestamp-query":
        logger.warning(f"Invalid Content-Type: {content_type}")
        raise HTTPException(
            status_code=415,
            detail="Content-Type must be application/timestamp-query"
        )
    
    # Read request body
    try:
        tsq_data = await request.body()
    except Exception as e:
        logger.error(f"Failed to read request body: {e}")
        raise HTTPException(status_code=400, detail="Failed to read request body")
    
    if not tsq_data:
        logger.warning("Empty request body")
        raise HTTPException(status_code=400, detail="Empty request body")
    
    logger.info(f"Received TSQ request ({len(tsq_data)} bytes)")
    
    # Process TSQ and generate TSR
    try:
        tsr_data = tsa.process_request(tsq_data)
        logger.info(f"Generated TSR response ({len(tsr_data)} bytes)")
    except Exception as e:
        logger.error(f"Failed to process TSQ: {e}")
        # Return a proper RFC 3161 error response if possible
        # In practice, process_request handles errors internally
        raise HTTPException(status_code=500, detail=f"Failed to process request: {e}")
    
    # Return TSR with proper Content-Type
    return Response(
        content=tsr_data,
        media_type="application/timestamp-reply",
        headers={
            "Content-Disposition": "attachment; filename=response.tsr",
            "Content-Transfer-Encoding": "binary"
        }
    )


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Global exception handler."""
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"}
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)

