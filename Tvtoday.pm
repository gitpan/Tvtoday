package WWW::Search::Tv::German::Tvtoday;

use 5.006;
use strict;
use warnings;
use URI::Escape;
use LWP::UserAgent;
use HTML::TableContentParser;
use File::Basename;

require Exporter;
use AutoLoader qw(AUTOLOAD);

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use WWW::Search::Tv::German::Tvtoday ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);
our $VERSION = '1.04';
our $DEBUG = 0;


# Preloaded methods go here.

# Autoload methods go after =cut, and are processed by the autosplit program.
sub new {
	my ($class, %args) = @_;
	my $self = bless {}, ref($class) || $class;
	# Set default-values
	$self->_populate_with_defaults();
	# Override values with given values from constructor
	%{$self} = (%{$self}, %args);

	# set modulewide debugflag evtentually
	if ( $self->{debug} ==1 ) {
		print "DEBUG-flag set.\n";
		$DEBUG=1;
	} else {
		$DEBUG=0;
	}

	return $self;
}

sub _populate_with_defaults {
	my $self = shift;
	$self->{today}=1;
	$self->{tomorrow}=1;
	$self->{proxy} = undef;
	$self->{proxy_user} = undef;
	$self->{proxy_pass} = undef;
	$self->{searchfor} = [];
	$self->{debug} = 0;
	$self->{found} = [];
	$self->{dontcareforstations} = [];
}

sub get_today {
	my $self = shift;
	return $self->{today};
}

sub get_searchvalues {
	my $self = shift;
	return @{$self->{searchfor}};
}

sub searchfor {
	my ($self,@searchvalues) = @_;
	push @{$self->{searchfor}},@searchvalues;
}

sub search {
	my $self = shift;
	my @found;
	foreach ( $self->get_searchvalues() ) {
		&debug("Searching for $_");
		$self->_gettvtoday(search=>$_);
		push @{$self->{found}}, $self->_extract_broadcast_from_html_raw();
	}
	# it could be that the same broadcast is found more 
	# than one time -> unify it
	$self->_unify_resultset();
	$self->_sort_resultset_by_date();
	# drop stations which the use does not like
	$self->_dropstations();
}

sub get_resultset {
	my $self = shift;
	return @{$self->{found}};
}

sub dontcareforstation {
	my ($self,@stations) = @_;
	push @{$self->{dontcareforstations}}, @stations;
	
}

sub _dropstations {
	my $self = shift;
	foreach my $notthis ( @{$self->{dontcareforstations}} ) {
		@{$self->{found}} = grep { $_->{where} !~ /^${notthis}/i } @{$self->{found}};
	}
}


sub _gettvtoday {
	my ($self,%args) = @_;
	my $searchthisone = $args{search};
	unless ($searchthisone) {
		print "You called _gettvtoday wrong, use it like this:\n";
		print '$obj->_gettvtoday{search=>"police"}' , "\n";
		exit;
	}

	# this is the URL which searches the german TV-program
	# for example if you look for "das liebe vieh" (which
	# is "all creatures great and small" in English):
	# http://www.tvtoday.de/tv/programm/programm.php?ztag=0&uhrzeit=Ax00&sparte=alle&sender=HR&suchbegriff=das+liebe+vieh
	my $url = "http://www.tvtoday.de/tv/programm/programm.php";

	# Parameters for the search
	my %param;
	# which kind of program? series, movies, children...
	$param{kindofprogram} = "sparte=alle";
	# search from today on -> ztag=0
	# but search is not restrictable to one day!
	$param{whichdayfrom} = "ztag=0";
	# Which is the earliest time to get a broadcast?
	# 0:00 hours
	$param{hours} = "uhrzeit=Ax00";
	# which kind of tv-stations?
	# HR means major-broadcast stations and regional ones
	# (german HR = Haupt- und Regionalsender)
	$param{tvstations} = "sender=HR";
	# What to search for?
	$param{lookfor} = "suchbegriff=" . uri_escape($searchthisone);

	$url = $url . "?" . join('&', values %param);
	&debug("URL is $url");
	$self->{html_raw} = $self->_fetchwww(url=>$url);
}

sub _fetchwww {
	# call me like this: $obj->fetchwww(url=>$url);
	my ($self,%args) = @_;
	my ($url) = $args{url};

	my $content;
	my $ua = LWP::UserAgent->new;
	if ($self->{proxy}) {
		# set Proxyserver if there is one to use
		$ua->proxy("http",$self->{proxy});
	}
	my $request = HTTP::Request->new('GET', $url);
	# in case that proxy-authentication is needed:
	if ($self->{proxy_user}) {
		$request->proxy_authorization_basic(
			$self->{proxy_user},
			$self->{proxy_pass});
	}

	my $response = $ua->request($request); 
	if ($response->is_error()) {
		$content=sprintf ("Error requesting URL $url: %s\n",$response->status_line);
	} else {
		$content=$response->content();
	}
	return $content;

}

sub _extract_broadcast_from_html_raw {
	my $self = shift;
	# nur Sendungen von Heute raussuchen
	# Rueckgabe ist eine Liste von Hashs
	# { what => 
	#   where => 
	#   when => 
	# }
	my $html= $self->{html_raw};
	my $sendung;
	my $heute = &_today;
	my $morgen = &_tomorrow;
	my @found;

	# is a broadcast found for this search-value?
	# always believe: yes

	# the table where the search-result exists is marked like this
	# I only need the stuff between these tags
	$html =~ s/^.*(<!--LISTING ANFANG-->)/$1/s;
	$html =~ s/(<!--LISTING ENDE-->).*$/$1/s;

	# the rest is an HTML-table;
	my $p = HTML::TableContentParser->new();

	my $tables = $p->parse($html);
	for my $t (@$tables) {
LINE:
		for my $r (@{$t->{rows}}) {
			my ($when,$where,$what)=();
			my $spalte_nr=0;
			&debug("*** new line in table ");				
			for my $c (@{$r->{cells}}) {
				$spalte_nr++;
				&debug("[$c->{data}] ");				
				my $inhalt = $c->{data};
				$inhalt = &_trim_table_cell($inhalt);	
				
				if ($spalte_nr == 2) {
					$when = &_check_for_date($inhalt);
					if ($when) {
						$when = $inhalt;
					} else {
						# Date is not the way we expected it. Don't care for this line, it's not a broadcast descripted here
						next LINE;
					}
				}

				if ($spalte_nr == 3) {
					($where,$sendung) = &_analyze_descriptionline($inhalt);	
					# trim newline at end of desc.
					$sendung =~ s/\n+$//;
				}
			}				

			# nur Sendungen von Heute aufbereiten
			my $takethis=0;
			$takethis=1 if ($self->{today} and ($when =~ /$heute/));
			$takethis=1 if ($self->{tomorrow} and ($when =~ /$morgen/));
			push @found, {
				when => $when,
				where => $where,
				what => $sendung
			} if $takethis;

		}
	}

	return @found;
}

sub _trim_table_cell {
	# kill HTML-whitespace, <br>, Showview-lines, VPS-lines
	# kill all HTML-tags
	my ($inh) = @_;
	$inh =~ s/\&nbsp;/ /ig;
	# neue Zeile -> Leerzeichen
	$inh =~ s/<br>/ /ig;
	# Showview entfernen
	$inh =~ s/ShowView [\d\-]+//ig;
	$inh =~ s/VPS [\d\-]+//ig;
	# Alle Tags entfernen
	$inh =~ s/<[^>]+?>//ig;
	return $inh;
}

sub _today {
	# das heutedatum dd.mm.yy
	# weil das im Fernsehprogramm so aufbereitet ist
	my ($sek,$min,$std,$mtag,$mon,$jahr,$wtag,$jtag,$isdt)=localtime(time);
	# +1900 also whererks in 2000+x
	$jahr = 1900+$jahr;
	# ich brauche aber nur ein zweistelliges jahr
	$jahr = $jahr - (int($jahr/100) * 100);
		
	return sprintf ("%02s.%02s.%02s",$mtag,$mon+1, $jahr );
	
}

sub _tomorrow {
	# das morgendatum dd.mm.yy
	# weil das im Fernsehprogramm so aufbereitet ist
	my ($sek,$min,$std,$mtag,$mon,$jahr,$wtag,$jtag,$isdt)=localtime(time + (24*60*60));
	# +1900 also whererks in 2000+x
	$jahr = 1900+$jahr;
	# ich brauche aber nur ein zweistelliges jahr
	$jahr = $jahr - (int($jahr/100) * 100);
		
	return sprintf ("%02s.%02s.%02s",$mtag,$mon+1, $jahr );
	
}

sub _check_for_date {
	my ($line)=@_;
	# Datum umformatieren: xx.xx.xx xx.xx Uhr
	if ( $line =~ /^(\d+)\.(\d+)\.(\d+)\s+(\d+).(\d+) Uhr/ ) {
		$line = sprintf "%02d.%02d.%02d, %02d:%02d Uhr", $1,$2,$3+2000,$4,$5;
	} else {
		$line = undef;
	}
	return $line;
}


sub _analyze_descriptionline {
	# Get title and tv-station
	my ($content) = @_;
	my ($where,$title) = ();

	# A descriptionline looks like this
	#    Der Doktor und das liebe Vieh (Teil 60) (WEST)
	# or like this:
	#    Der Doktor (West)
	#    In dieser Sendung...
	
	my @lines = split(/\n/,$content);
	if ( $lines[0] =~ /^(.+) \((.+?)\)\s*$/ ) {
		($title,$where)=($1,$2);
		if ($#lines > -1) {
			foreach my $i (@lines[1.. $#lines]) {
				$i =~ s/^(\s+)//;
				$i =~ s/(\s+)$//;
				$title .= "\n" . $i;
			}
		}
	} else {
		# Could not find out in which tv-program this runs
		$where="???";
		$title = $content;
	}
	return ($where,$title);
}


sub debug {
	print "DEBUG: @_\n" if $DEBUG;
}
	
sub _unify_resultset {
	my $self = shift;

	# it could be that some broadcast are found more than one
	# time -> unify that. I take the whole resultset as key
	# in a hash.
	my %einheit;
	foreach my $zeile ( @{$self->{found}} ) {
		my $h = join "",$zeile->{what},$zeile->{when},$zeile->{where};
		$einheit{$h} = { %$zeile };
	}
	
	# refill resultset with unified values
	my @unified;
	foreach (keys %einheit) {
		push @unified, $einheit{$_};
	}
	@{$self->{found}} = @unified;
	# end of unifying
}

sub _sort_resultset_by_date {
	my $self = shift;
	# sort broadcast by day/time
	@{$self->{found}} = sort { $a->{when} cmp $b->{when} } 
		@{$self->{found}};
}


1;
__END__

=head1 NAME

WWW::Search::Tv::German::Tvtoday - checking a directory for bad letters in filenames

=head1 PLATFORMS

Tested with

=over 4 

=item *

Win32

=item *

Linux

=back

=head1 SYNOPSIS

	#!/usr/bin/perl
	use strict;
	use WWW::Search::Tv::German::Tvtoday 1.02;

	my $tv = WWW::Search::Tv::German::Tvtoday->new(
		today=>1,
		tomorrow=>1,
		proxy => 'http://gatekeeper.rosi13.de:3128');
	$tv->searchfor("Maus");
	$tv->searchfor("Sendung mit");
	$tv->searchfor("Tagesschau","news");
	$tv->dontcareforstation('ORF','VIVA');

	printf "Get results for %s\n", join(" * ",$tv->get_searchvalues());
	print "This takes a while to get, please wait...\n";
	my @found = $tv->search();
	foreach my $f ($tv->get_resultset()) {
		printf "*** what : %s\n",$f->{what};
		printf "    where: %s\n",$f->{where};
		printf "    when : %s\n",$f->{when};
	}

=head1 DESCRIPTION

Get television-program from german www.tvtoday.de and search for special 
broadcasts. The result could be input for a notice-mail or a webpage.

=head1 METHODS


=head2 new()

Create object for fetching the information from tvtoday.de. Needed to work 
with this module. 

Alle Parameters are optional: 

today =>1|0	Get tv-programm from today (default is 1)
tomorrow =>1|0	Get tv-programm from today (default is 1)
proxy, proxy_user, proxy_pass	If you can access the internet only through a WWW-proxyserver.

Return value:
The object in which the program lives.


=head2 searchfor($keyword)

The words to search for. You can use simple words, phrases with spaces in it.
Also umlauts are allowed. Can be called multiple times.

	$tv->searchfor("pink");
	$tv->searchfor("panther");
	$tv->searchfor("alf");
	$tv->searchfor("the quest");
	$tv->searchfor("the quest","adventures of");


=head2 dontcareforstation

Maybe you cannot get or don't like stations which are in the result of
the query. You can filter them out from the resultset with this command.

	$tv->dontcareforstation("VIVA");
	$tv->dontcareforstation("ARD","SAT1");


=head2 search

Here begins the work for the programm. For every search-keyword a request 
is sent to the webserver and the answer-pages are interpreted. All results
will be unified (you could find the same broadcast with different words,
like "pink" and "panther").

	$tv->search();

You can access the resultset via get_resultset()

Return value:
Nothing.

=head2 get_resultset

Get back the result after calling "search". You get back a list
of hashes where every element contains the hashkeys "what", "where"
and "when". The list is sorted by date/time.

	my @found = $tv->search();
	foreach my $f ($tv->get_resultset()) {
		printf "*** what : %s\n",$f->{what};
		printf "    where: %s\n",$f->{where};
		printf "    when : %s\n",$f->{when};
	}


=head2 get_searchvalues 

Get a list of values which are searched for at tvtoday.

	my @searchingfor = $tv->get_searchvalues();

=head2 BUGS

Does not 

	* recognize or check more than the first page of the resultset from tvtoday.de
	* take care about VPS or Showview

=head2 EXPORT

None.

=head1 AUTHOR

Richard Lippmann <horshack@lisa.franken.de>

=head1 HISTORY

V1.02 - Initial release
V1.03 - Problems in distribution files at CPAN
V1.04 - Problems in Makefile.PL distribution file at CPAN

=cut
