# WikiKategorienGraph

This program allows to explore the Wikipedia-categories and their relation of the articles you read with Firefox.

For example, the article "Linux" contains the category "Software" and references to Linus Torvalds, which contains the
categories "Man". So "Software" connects to "Man".

This script searches for all of these categories of all the websites you visited and links them together.

## Setup

Please install MySQL or PerconaDB and load the 

> db.sql

in it (e.g. with source db.sql).

Then install all the needed modules:

> cpan -i Path::Tiny
> cpan -i List::MoreUtils
> cpan -i Digest::MD5
> cpan -i Encode
> cpan -i LWP::Simple
> cpan -i Data::Dumper
> cpan -i DBIx::Simple
> cpan -i Term::ANSIColor
> cpan -i URI::Encode
> cpan -i String::ShellQuote
> cpan -i DBI

# Set environment variables

> DBUSER=...
> DBPASS=...
> PLACESSQLITEPATH=~/.mozilla/firefox/RANDOMSTRING.default_RANDOMNUMBER/places.sqlite

# Run it

You can then run it with

> perl categories.pl $DBUSER $DBPASS $PLACESSQLITEPATH

This downloads all the websites (right now, only from the german Wikipedia, but feel free to edit it accordingly!), puts
them into a cache folder and then parses them and puts their metainformation into the database.

With

> perl plot.sh $DBUSER $DBPASS

You'll get a file called `autoplot.dot'. You can then use this file and plot it with GraphViz (if your graph is small),
or Gephi (if your graph is huge).

You'll get a graph like this:

![WikiStar](wikistern.png?raw=true "WikiStar")

# Get the most common categories

Simply use

> SELECT * FROM common_categories LIMIT 10;

in the DB.
