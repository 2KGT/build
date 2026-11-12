# .github/scripts/modules/twitter_handler.py
import header_tools as ht

# Khớp mọi bundle ID Twitter/X: com.atebits.Tweetie2, com.atebits.Tweetie2.ios, ...
IDENTIFIER = "tweetie"
TAG = "TW-HANDLER"
HEADER_DIRS = ["TwitterHeader", "XHeader", "TweetieHeader"]

CLASS_KEYWORDS = ["Ad", "Promoted", "Timeline", "Feed", "Video", "Player",
                  "Tweet", "Status", "Analytics", "Block", "Filter", "Ranking"]
SELECTOR_KEYWORDS = ["ad", "promoted", "sponsored", "quality", "video",
                     "download", "watermark", "block", "hide", "timeline", "rank"]


def setup(proj_dir, config):
    ht.link_dump(proj_dir, HEADER_DIRS, TAG, CLASS_KEYWORDS, SELECTOR_KEYWORDS)
