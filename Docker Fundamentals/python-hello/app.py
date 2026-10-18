import platform
import socket

from flask import Flask

app = Flask(__name__)


@app.get("/")
def index():
    return (
        f"<h1>Hello World from the Bookshelf (Python {platform.python_version()})</h1>"
        f"<p>Served by container {socket.gethostname()}</p>\n"
    )


@app.get("/health")
def health():
    return "ok\n"


if __name__ == "__main__":
    # 0.0.0.0 so the port is reachable from outside the container
    app.run(host="0.0.0.0", port=5000)
