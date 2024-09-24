

=head1 stdf_read

This perl application is simple example that uses STDF::Parser functionality
It reads STDF records and dump in text, displaying record count at the end

=head1 AUTHOR

Nyan, C<< <nyanhtootin at gmail.com> >>


=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2024 by Nyan.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)


=cut
use strict;
use warnings;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;

use Data::Dumper;
use STDF::Parser;

my $stdf = $ARGV[0];
if(@ARGV != 1) {

print "$0 <STDF path> \n";
print "STDF can be in .gz or uncompressed\n";
exit;
}
my $z;
if($stdf =~ /\.gz$/) {
  $z = IO::Uncompress::Gunzip->new( $stdf )
    or die "gunzip failed: $GunzipError\n";

} else {
  open($z,"<",$stdf) or die "Fail to read $stdf:$!\n";
  binmode($z) or die "fail to change to binary:$!\n";

}
my $p = STDF::Parser->new( stdf => $z );

my $stream = $p->stream;
print "File " , $stdf ,"\n";
print "CPU " , $p->cpu_type ,"\n";
print "STDF ver ", $p->stdf_ver, "\n";
my %count;
$Data::Dumper::Terse = 1;        # don't output names where feasible
$Data::Dumper::Indent = 0;       # turn off all pretty print
while(defined(my $r = $p->get_next_record ) ) {
        my $rec_name = $r->[0];
        $count{$rec_name}++; 
        print Dumper($r),"\n";
       
}
my $size = $p->bytes_read;
my $num_rec = $p->current_record_num;
printf "total byte size : %5d\n",$size;
printf "total record    : %7d\n",$num_rec;
$p->close;

print "Records count\n";
printf "Record Count\n";
for my $k(sort(keys(%count))) {
  printf "%6s %5d\n",$k,$count{$k};
}