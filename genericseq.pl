#!perl
use strict;
use warnings;

=head1 NAME

genericseq.pl - generates xml sequence diagrams from various inputs

=head1 USAGE

    genericseq.pl -t 'Title' SeqModule [args_for_SeqModule...]

=head1 DESCRIPTION

Currently there are three sequencing modules you can use for SeqModule
above.  They are

    UML::Sequence::SimpleSeq
    UML::Sequence::PerlSeq
    UML::Sequence::JavaSeq

See the documentation in these modules for details on their arguments.
To write your own sequence helper, see UML::Sequence::SimpleSeq and
implement the same API.

=cut

use UML::Sequence;
use Getopt::Std;

my $usage =
    "usage: $0 [-t 'Title for Diagram'] outline_style [outline_args...]\n";

die $usage if (@ARGV < 1);

getopt('t');
use vars qw($opt_t);

my $style       = shift;
my $outline;
my $methods;
my $parse_method;
my $grab_methods;

{
    no      strict;
    my      $style_file = $style;
    $style_file         =~ s!::!/!g;
    require "$style_file.pm";

    $outline      = $style->grab_outline_text(@ARGV);
    $methods      = $style->grab_methods($outline);
    $parse_method = $style->can(parse_signature);
    $grab_methods = $style->can(grab_methods);
}

my $tree = UML::Sequence->new($methods, $outline, $parse_method, $grab_methods);

print($tree->build_xml_sequence($opt_t));

