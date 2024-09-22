#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'STDF::Parser' ) || print "Bail out!\n";
}

diag( "Testing STDF::Parser $STDF::Parser::VERSION, Perl $], $^X" );
