use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'WWW::Search::Tv::German::Tvtoday',
    'VERSION_FROM'	=> 'Tvtoday.pm', # finds $VERSION
	# these modules are needed for mine:
    'PREREQ_PM'		=> {
	'HTML::TableContentParser' => '0', # or a minimum workable version
	'URI::Escape' => 0,
	'LWP::UserAgent' => 0,
	'File::Basename' => 0,
	}, 
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'Tvtoday.pm', # retrieve abstract from module
       AUTHOR     => 'Richard Lippmann <horshack@lisa.franken.de>') : ()),
);
