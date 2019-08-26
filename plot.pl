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
use String::ShellQuote 'shell_quote';
binmode(STDOUT, ":utf8");

my ($dbuser, $dbpw) = @_;

my $db = DBIx::Simple->connect(
	'DBI:mysql:database=wikicategories',     # DBI source specification
	$dbuser, $dbpw,                # Username and password
	{ mysql_enable_utf8 => 1, RaiseError => 1 }            # Additional options
);

print plot();

sub plot {
	my $query = 'select c1.title as category_from_title, c2.title as category_to_title from page_references_to_page prp join page_to_category pc1 on pc1.page_id = prp.page_from_id join page_to_category pc2 on prp.page_to_id = pc2.page_id join category c1 on c1.id = pc1.category_id join category c2 on c2.id = pc2.category_id group by category_from_title, category_to_title';
	print "$query\n";
	my $result = $db->query($query);
	my @res = @{$result->arrays};
	open my $fh, '>', 'autoplot.dot' or die $!;
	my $start_string = "digraph a {\n";
	print $fh $start_string;
	print "Starting going through data\n";
	foreach my $this_res (@res) {
		my ($from, $to) = (quote($this_res->[0]), quote($this_res->[1]));
		my $this_string = qq#\t"$from" -> "$to";\n#;
		print $fh $this_string;
	}
	my $end_string .= "}\n";
	print $fh $end_string;
	close $fh;
}

sub quote {
	my $text = shift;
	$text =~ s#"#'#g;
	return $text;
}
