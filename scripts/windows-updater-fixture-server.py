# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

"""Serve local updater fixtures and log when full response bodies finish."""

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


COPY_BUFFER_BYTES = 4 * 1024 * 1024


class FixtureHandler(SimpleHTTPRequestHandler):
    def copyfile(self, source, outputfile):
        transferred = 0
        completed = False
        try:
            while chunk := source.read(COPY_BUFFER_BYTES):
                outputfile.write(chunk)
                transferred += len(chunk)
            completed = True
        finally:
            status = "complete" if completed else "interrupted"
            self.log_message("TRANSFER %s %s bytes=%d", self.path, status, transferred)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--directory", required=True)
    args = parser.parse_args()

    handler = partial(FixtureHandler, directory=args.directory)
    with ThreadingHTTPServer((args.bind, args.port), handler) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
