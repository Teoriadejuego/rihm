"""Serve the built site locally with a queue suitable for concurrent delivery checks."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse

class ClassroomServer(ThreadingHTTPServer):
    request_queue_size = 512
    daemon_threads = True

class Handler(SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8000)
    args = parser.parse_args()
    site = Path(__file__).resolve().parents[1] / 'student' / '_site'
    if not (site / 'index.html').is_file():
        parser.error('Build the student site first with npm run build.')
    server = ClassroomServer(('127.0.0.1', args.port), partial(Handler, directory=str(site)))
    print(f'Serving built student site at http://127.0.0.1:{args.port}/', flush=True)
    server.serve_forever()
