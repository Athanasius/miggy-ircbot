A generic IRC bot, originally for running ^Lumi^ in #starcitizen on
QuakeNet.  As such some of the older features may seem esoteric.

It has various functions, including:

  * Keep an eye on the crowdfund level, reporting milestones.
  * Report new RSS feed entries.
  * Reminders about things like Wingman's Hangar shows.

All code is provided as-is under the GPL Version 2.

---

# Getting The Bot Running

1. Copy docs/bot-config.txt-example to just bot-config.txt in the bot's
root directory.  Edit to suit.

2. If you're using the RSS module then you'll need to run this command
to initialise the SQLite database it uses:

```sqlite3 -echo rss.db < docs/rss-sqlite-schema.db
