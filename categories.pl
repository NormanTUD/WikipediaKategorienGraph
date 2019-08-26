#!/usr/bin/perl

sub debug (@);

use strict;
use warnings;

use Path::Tiny;
use Data::Dumper;
use DBIx::Simple;
use Term::ANSIColor;
use List::MoreUtils qw(uniq);
use URI::Encode qw(uri_encode uri_decode);
use List::MoreUtils qw(any);
use Digest::MD5 qw/md5_hex/;
use Encode;
use LWP::Simple;
use DBI;

my ($dbuser, $dbpw, $places_sqlite) = @_;
my $tmp = './.myget_cache/';

my $places_dbh = get_places_dbh($places_sqlite);

my $db = DBIx::Simple->connect(
	'DBI:mysql:database=wikicategories',     # DBI source specification
	$dbuser, $dbpw,                # Username and password
	{ mysql_enable_utf8 => 1, RaiseError => 1 }            # Additional options
);

crawl_pages();

sub crawl_pages {
	my @pages = get_wiki_from_dbh();
	
	my $i = 1;

	#foreach my $this_page (sort { $a cmp $b } @pages) {
	#	my $url = "https://de.wikipedia.org/wiki/".$this_page;
	#	my $wiki = myget($url);	
	#}

	foreach my $this_page (@pages) {
		print "$i of ".scalar(@pages)."\n";
		debug "crawling $this_page";
		crawl_page($this_page, \@pages);
		$i++;
	}
}

sub crawl_page {
	my $title = shift;
	my $pages = shift;
	debug "crawl_page($title, ...)";
	my $url = "https://de.wikipedia.org/wiki/".$title;
	my $wiki = myget($url);

	my @categories = get_categories_from_sources($wiki);
	if(@categories) {
		foreach my $category (@categories) {
			debug "$title belongs to $category";
			insert_page_to_category($title, $category);
		}
	}

	my @related = get_related_from_code($wiki); 
	if(@related) {
		foreach my $related (@related) {
			if (any { $_ eq $related } @$pages ) {
				#my $url = "https://de.wikipedia.org/wiki/".$related;
				#myget($url);
				debug "$title links to visited page $related";
				insert_page_references_to_page($title, $related);
			} else {
				warn color("blue").
					"$title links to $related, but $related has not yet been opened.".
					color("reset")."\n";
			}
		}
	}
}

sub get_related_from_code {
	my $code = shift;
	
	my @related = ();
	# <a href="/wiki/Ignaz_Paul_Vitalis_Troxler" class="mw-redirect" title="Ignaz Paul Vitalis Troxler">
	while ($code =~ m#<a href="/wiki/([^"]+)"[^>]+>[^<]+</a>#gi) {
		my $rel = $1;
		if($rel !~ m#^\w+:#) {
			$rel =~ s#_# #g;
			$rel =~ s!#.*!!g;
			push @related, uri_decode($rel);
		}
	}
	return uniq @related;
}

sub get_categories_from_sources {
	my $code = shift;

	my @categories = ();

	while ($code =~ m#<li><a\s*href="/wiki/Kategorie:[^"]+" title="Kategorie:[^"]+">([^<]*)</a></li>#gi) {
		my $category = $1;
		if($category !~ /^Wikipedia:/) {
			push @categories, $1;
		}
	}

	return @categories;
}

### PAGE TO CATEGORY

sub insert_page_to_category {
	my ($page, $category) = @_;
	debug "insert_page_to_category($page, $category)";
	my $pageid = get_or_create_page_id($page);
	my $categoryid = get_or_create_category_id($category);
	eval {
		$db->insert('page_to_category', { page_id => $pageid, category_id => $categoryid });
	};
}

### PAGE TO PAGE

sub insert_page_references_to_page {
	my ($name1, $name2) = @_;
	return if $name1 eq $name2;
	debug "insert_page_references_to_page($name1, $name2)";
	my ($id1, $id2) = (get_or_create_page_id($name1), get_or_create_page_id($name2));
	eval {
		$db->insert('page_references_to_page', { page_from_id => $id1 , page_to_id => $id2 });
	};
}

### PAGE

sub get_or_create_page_id {
	my $name = shift;
	debug "get_or_create_page_id($name)";
	my $id = get_page_id($name);
	if(defined $id) {
		return $id;
	} else {
		eval {
			$db->insert('page', { title => $name });
		};
		my $id = get_page_id($name);
		return $id;
	}
}

sub get_page_id {
	my $name = shift;
	debug "get_page_id($name)";
	eval {
		return $db->select('page', 'id', { title => $name })->flat->[0];
	}
}


### CATEGORY

sub get_or_create_category_id {
	my $name = shift;
	debug "get_or_create_category_id($name)";
	my $id = get_category_id($name);
	if(defined $id) {
		return $id;
	} else {
		$db->insert('category', { title => $name });
		my $id = get_category_id($name);
		return $id;
	}
}

sub get_category_id {
	my $name = shift;
	debug "get_category_id($name)";
	return $db->select('category', 'id', { title => $name })->flat->[0];
}

### DBH for PLACES.SQLITE

sub get_places_dbh {
	my $places_sqlite = shift;
	debug "get_places_dbh($places_sqlite)";
	my $driver   = "SQLite";
	my $database = $places_sqlite;
	my $dsn = "DBI:$driver:dbname=$database";
	my $userid = "";
	my $password = "";
	my $dbh = DBI->connect($dsn, $userid, $password, { RaiseError => 1 }) or die $DBI::errstr;
	return $dbh;
}

sub get_wiki_from_dbh {
	debug "get_wiki_from_dbh()";
	#my $stmt = qq(select url from moz_places where url like "http%://de.wikipedia.org/wiki/%" limit 54, 1);
	my $stmt = qq(select url from moz_places where url like "http%://de.wikipedia.org/wiki/%");
	my $sth = $places_dbh->prepare( $stmt );
	my $rv = $sth->execute() or die $DBI::errstr;

	if($rv < 0) {
		print $DBI::errstr;
	}

	my @urls = ();
	while(my @row = $sth->fetchrow_array()) {
		my $url = $row[0];
		$url =~ s#\Qhttp\Es?\Q://de.wikipedia.org/wiki/\E##;
		$url =~ s!\#.*!!g;
		$url =~ s!_! !g;
		if($url !~ /^(Datei|Kategorie|File|Diskussion|Spezial|Wikipedia):/) {
			$url = uri_decode($url);
			push @urls, $url;
		}
	}
	@urls = uniq @urls;
	return sort { rand() <=> rand() } @urls;
}

sub debug (@) {
	foreach (@_) {
		warn color("on_green black").$_.color("reset")."\n";
		#my $mess = longmess();
		#print Dumper( $mess );
	}
}

sub myget {
	my $url = shift;
	debug "myget($url)";
	unless (-d $tmp) {
		mkdir $tmp or die("$!");
	}

	my $cache_file = $tmp.md5_hex(Encode::encode_utf8($url));

	my $page = undef;

	if(-e $cache_file) {
		debug "`$cache_file` exists. Returning it.";
		$page = path($cache_file)->slurp;
	} else {
		debug "`$cache_file` Did not exist. Getting it...";
		$page = get($url);
		if($page) {
			open my $fh, '>', $cache_file;
			binmode($fh, ":utf8");
			print $fh $page;
			close $fh;
			debug "`$url` successfully downloaded.";
		} else {
			debug "`$url` could not be downloaded.";
		}
	}

	return $page;
}

# select pc.page_id, p.title as page_title, pc.category_id, c.title from page_to_category pc left join page p on p.id = pc.page_id left join category c on c.id = pc.category_id limit 10
