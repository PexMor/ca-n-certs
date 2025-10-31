"""CLI entry point for mytsa TSA server."""

import argparse
import sys

import uvicorn


def main():
    """Main entry point for mytsa CLI."""
    parser = argparse.ArgumentParser(
        description="mytsa - Pure-Python RFC 3161 Time Stamp Authority server"
    )
    parser.add_argument(
        "--host",
        default="0.0.0.0",
        help="Host to bind to (default: 0.0.0.0)"
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8080,
        help="Port to bind to (default: 8080)"
    )
    parser.add_argument(
        "--reload",
        action="store_true",
        help="Enable auto-reload for development"
    )
    parser.add_argument(
        "--log-level",
        default="info",
        choices=["critical", "error", "warning", "info", "debug"],
        help="Log level (default: info)"
    )
    
    args = parser.parse_args()
    
    print(f"Starting mytsa TSA server on {args.host}:{args.port}")
    print("Press CTRL+C to stop")
    
    try:
        uvicorn.run(
            "mytsa.app:app",
            host=args.host,
            port=args.port,
            reload=args.reload,
            log_level=args.log_level,
        )
    except KeyboardInterrupt:
        print("\nShutting down...")
        sys.exit(0)


if __name__ == "__main__":
    main()

