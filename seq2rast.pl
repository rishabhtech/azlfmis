#!perl
use strict;
use warnings;

=head1 NAME

seq2rast.pl - a script to convert xml sequence diagrams to raster images via GD

=head1 USAGE

    seq2rast.pl [ options ] [input_file_name]

=cut

use UML::Sequence::Raster;

seq2raster(@ARGV);
