# .github/scripts/modules/spotify_handler.py
import header_tools as ht

IDENTIFIER = "com.spotify.client"
TAG = "SPT-HANDLER"
HEADER_DIRS = ["SpotifyHeader"]


def setup(proj_dir, config):
    ht.link_dump(proj_dir, HEADER_DIRS, TAG)
