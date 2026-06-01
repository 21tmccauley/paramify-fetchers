#!/usr/bin/env python3
"""
<KSI or control reference>: <short title>

<One paragraph: what this fetcher collects and why.>
"""

import json
import logging
import os
import sys
from pathlib import Path

from dotenv import load_dotenv

# If this fetcher relies on a category-shared module, uncomment:
# SCRIPT_DIR = Path(__file__).resolve().parent
# sys.path.insert(0, str(SCRIPT_DIR.parent / "_shared"))
# from <shared_module> import <EntryClass>

logger = logging.getLogger("<category>_<short_name>")


def main():
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    # Interim v0.x: fetcher loads .env itself and reads env directly.
    # Runner + secret resolver will replace this when the framework lands.
    load_dotenv()

    output_dir = Path(os.environ.get("EVIDENCE_DIR", "./evidence"))
    output_dir.mkdir(parents=True, exist_ok=True)

    # Replace with the actual data-collection call.
    evidence: dict = {}

    output_path = output_dir / "<category>_<short_name>.json"
    with open(output_path, "w") as f:
        json.dump(evidence, f, indent=2)

    logger.info("Evidence saved to %s", output_path)


if __name__ == "__main__":
    main()
