# Some notes:
#
# The usual HTTPS POST query:
#
# curl -d '{"page":"1"}' https://robertsspaceindustries.com/api/hub/getTrackedPosts > rsi-devposts-1.html
# NB: that's 0-based, 0 for the latest
#
#  Returns JSON data:
#
#   {"success":1,"data":"<a href=\"https:\...
#
# Each entry is a <a href...></a>, all / are \-escaped
#
# href is the URL (duh)
# div poster.handle/title for author
# div details.trans-03s for text
# div bottom.title.trans-03s for title
