package STDF::Parser;

use 5.10.0;
use strict;
use warnings;


use Scalar::Util qw(openhandle);
use Carp;


use constant {
    FAR   =>   0 <<8 | 10,
    ATR   =>   0 <<8 | 20,
    MIR   =>   1 <<8 | 10,
    MRR   =>   1 <<8 | 20,
    PCR   =>   1 <<8 | 30,
    HBR   =>   1 <<8 | 40,
    SBR   =>   1 <<8 | 50,
    PMR   =>   1 <<8 | 60,
    PGR   =>   1 <<8 | 62,
    PLR   =>   1 <<8 | 63,
    RDR   =>   1 <<8 | 70,
    SDR   =>   1 <<8 | 80,
    
    WIR   =>   2 <<8 | 10,
    WRR   =>   2 <<8 | 20,
    WCR   =>   2 <<8 | 30,
    
    PIR   =>   5 <<8 | 10,
    PRR   =>   5 <<8 | 20,

    TSR   =>  10<<8 | 30,

    PTR   =>  15 <<8 | 10,
    MPR   =>  15 <<8 | 15,
    FTR   =>  15 <<8 | 20,

    BPS   =>  20<<8 | 10,
    EPS   =>  20<<8 | 20,

    GDR   =>  50<<8 | 10,
    DTR   =>  50<<8 | 30,
    
    
    UNK   =>  65536,
};
my %REC_NAMES = (
    FAR()   =>  'FAR',
    ATR()   =>  'ATR',
    MIR()   =>  'MIR',
    MRR()   =>  'MRR',
    PCR()   =>  'PCR',
    HBR()   =>  'HBR',
    SBR()   =>  'SBR',
    PMR()   =>  'PMR',
    PGR()   =>  'PGR',
    PLR()   =>  'PLR',
    RDR()   =>  'RDR',
    SDR()   =>  'SDR',
    WIR()   =>  'WIR',
    WRR()   =>  'WRR',
    WCR()   =>  'WCR',
    PIR()   =>  'PIR',
    PRR()   =>  'PRR',
    TSR()   =>  'TSR',
    PTR()   =>  'PTR',
    MPR()   =>  'MPR',
    FTR()   =>  'FTR',
    BPS()   =>  'BPS',
    EPS()   =>  'EPS',
    GDR()   =>  'GDR',
    DTR()   =>  'DTR',
    
);

=head1 NAME

STDF::Parser -   STDF::Parser to parse STDF Version 4 in pure Perl!

=head1 VERSION

Version 0.02

=cut

our $VERSION = '0.02';


=head1 SYNOPSIS

Quick summary of what the module does.

 a little code snippet.

    use STDF::Parser;

    my $p = STDF::Parser->new(stdf => $stdf_path);
    printf "CPU " , $p->cpu_type, "\n";
    # iterate over records

    while( my $rec = $p->get_next_record()) {
      # $rec holds STDF record information
        my ($rec_name,@fields) = @$rec;
        if($rec_name eq "MIR") {
          ## @fields contain MIR fields 
        }
    }
    ...


=head1 SUBROUTINES/METHODS

=head2 new (%hash)

     stdf  - STDF file path or open file handle
             open file handle can be any IO::Handle object

     exclude_records   - array ref of record names or comma separated record names to exclude 
              any of the record in STDF in exclude_records will not be returned by parser
      
    omit_optional_fields - boolean if set, parser will not return optional fields of PTR

                to quote from STDF v4 spec
                All data following the OPT_FLAG field has a special function in the STDF file. The first
                PTR for each test will have these fields filled in. These values will be the default for each
                subsequent PTR with the same test number: if a subsequent PTR has a value for one of
                these fields, it will be used instead of the default, for that one record only; if the field is
                blank, the default will be used.  

     my $p = STDF::Parser->new( stdf => $fh, exclude_records => 'PTR,FTR,MPR');
     my $rec_stream = $p->stream;

     while( my $r = $rec_stream->()) {
      ## this loop will not see excluded records PTR,FTR,MPR
     }
=cut

sub new {

    my ($class,%args)  = @_; 

    unless(exists($args{stdf})) {
      die "Missing required argument stdf \n";
    }
    my @exclude;
    my $omit_optional_field = 0;
    if(exists($args{exclude_records})) {

      my $ex_rec = $args{exclude_records};
      if(ref($ex_rec) eq "ARRAY") {
        @exclude = @$ex_rec;
      } 
      elsif(ref($ex_rec) eq "") {
        @exclude = map { uc($_) } split /\s*,\s*/,$ex_rec;
      }
    }

    if(exists($args{omit_optional_fields})) {
        $omit_optional_field = $args{omit_optional_fields};
    }
    my $file = $args{stdf};
    my %exclude_records = map { $_ =>1} @exclude;
    my $fh;
    my $own_fh = 0;  # true if file handle is owned by me
    if( openhandle($file) ) {
        $fh = $file;

    }
    else {
        open( $fh,'<',$file) or croak "Cannot open $file:$!";
        $own_fh = 1;
    }
    binmode($fh) or die "Cannot change binmode:$!";
    my $buf;
    my $nread = read($fh,$buf,6);
    if(!defined($nread)) { die "Reading from file failed:$!"; }
    if($nread != 6) { die "Error in reading FAR record";}
    

    my ($typ,$sub,$cpu,$stdf_ver) = unpack("xxCCCC",$buf);
    die "Invalid STDF file: expect FAR as first record. ($typ,$sub,$cpu,$stdf_ver)" if($typ != 0 && $sub != 10);
    die "Parser unable to parse STDF VERSION:$stdf_ver" if($stdf_ver != 4);
    my $HEADER_TMPL; 
    my $UNSIGN_SHORT;
    my ($SIGN_SHORT,$SIGN_LONG);
    my $UNSIGN_LONG;
    my $REAL;
    my $R8;  # double float 8 byte Real
    my $endian_fmt;
    if($cpu == 1) {
       $HEADER_TMPL = "nCC";
       $UNSIGN_SHORT = "n";
       $SIGN_SHORT   = "s>";
       $SIGN_LONG    = "l>";
       $UNSIGN_LONG = "N";
       $REAL        = "f>";
       $R8          = "d>";
       $endian_fmt  = ">";
    }else {
       $HEADER_TMPL = "vCC";
       $UNSIGN_SHORT = "v";
       $SIGN_SHORT   = "s<";
       $SIGN_LONG    = "l<";
       $UNSIGN_LONG = "V";
       $REAL        = "f<";
       $R8          = "d<";
       $endian_fmt  = "<";
    }
    if( (my $far_len = unpack("$UNSIGN_SHORT",$buf))!= 2) 
    {
        die "Error in parsing FAR record: wrong FAR record length ($far_len) ";
    }
    my $BIT = "B";
    my %gdr_type_table = (
        1 => "C",
        2 => $UNSIGN_SHORT,
        3 => $UNSIGN_LONG,
        4 => "c",
        5 => $SIGN_SHORT,
        6 => $SIGN_LONG,
        7 => $REAL,
        8 => $R8,
        10=> "C/a",
    );
    my %size_table = (
            "C/a" => 'str',
            "B8"  => 1,
            "b8"  => 1,
            "c"   => 1,
            $REAL => 4,
            "C" => 1,
            "c" => 1,
            $UNSIGN_SHORT => 2,
            $UNSIGN_LONG  => 4,
            $SIGN_SHORT   => 2,
            $SIGN_LONG    => 2,
            $R8           => 8,
            );
    my $done = 0;
    my $num_bytes_read = 6;  # FAR 6 bytes
    my $rec_num        = 1; # FAR count as one
    my $ptr_fixed_template = "(L C2 C C )${endian_fmt}";
    my $ptr_opt_template   = "(C c3 f f)${endian_fmt}";
    my $prr_fixed_template = "CC C${UNSIGN_SHORT}2 ";
    my %ptr_opt_data;  # per test num
    my %ptr_default; 
    my $obj;
    my $parser = sub {
        
        my $buf;
        my ($len,$typ,$sub);
        my $data;
        my $n;

        if($done) {
            # user request to close explicitly or EOF reach
            return undef;

        }
    LOOP : while( $n = read($fh,$buf,4) ) {
        if($n != 4) {
            die "Parser error reading record header, get $n bytes expecting 4\n";
        }
        ($len,$typ,$sub) = unpack($HEADER_TMPL,$buf);
        $num_bytes_read += 4;
        my $actual_read = read($fh,$data,$len);
        
        if(!defined($actual_read) || $actual_read != $len)
        {
            die "Parsing typ($typ), sub($sub): expects to read $len at record #$rec_num";
        }
        $num_bytes_read += $len;
        $rec_num += 1;
        my $cardinal = $typ << 8| $sub;
        my $name = exists($REC_NAMES{$cardinal}) ? $REC_NAMES{$cardinal} :"NA";
        if(exists $exclude_records{$name} ) {
            # un-supported record or exclude
            next LOOP; 
        }      
        my @a;
        my $consumed = 0;
        if($cardinal == PTR)
        {
            push @a, unpack($ptr_fixed_template,$data);
            if($len > 8) {
                push @a, unpack("x8 $REAL",$data);
            }
            $consumed = 12;
           
            my $val;
            if($consumed < $len )
            {
               # TEST_TXT
                $val = unpack("x${consumed} C/a",$data);
                $consumed += length($val) + 1;
                push @a,$val;
            }
            if($consumed >= $len) { goto RETURN;}
             if($consumed < $len )
            {
                $val = unpack("x${consumed} C/a",$data);
                $consumed += length($val) + 1;
                push @a,$val;
            }
            my $remain_len = $len - $consumed;
            ## OPT_FLG to end
            if($remain_len != 0) {
                my $tnum=$a[0];
                my $remain_data = substr($data,$consumed);
                ## if caller requests not to return option part of PTR for subsequent PTR
                ## after default is returned; and current opt part of PTR,if present, is same as default
                ## some STDF PTR contains optional part for every part
                if($omit_optional_field) {
                    if(exists($ptr_opt_data{$tnum})) {
                        if($remain_data eq $ptr_opt_data{$tnum}) {
                            $consumed += length($remain_data);
                            #print "PTR cache for $tnum hit!\n";
                            goto RETURN;
                        }
                        my $curlen=length($remain_data);
                        my $def_len = length($ptr_opt_data{$tnum});
                    # my $fs = $ptr_default{$tnum};
                        #my $s = join "|",@$fs;
                        #print "not same as cache miss for $tnum Curr $curlen $def_len\n";
                        #print "default ptr:$s\n";
                    } else {
                        $ptr_opt_data{$a[0]} = substr($data,$consumed);
                        ## must use \@a not [@a] so we can see updated @a 
                        $ptr_default{$tnum} = \@a;
                        #print "PTR first tnum $tnum\n";
                    }
                }
            
            if($remain_len >= 12) {
                push @a,unpack($ptr_opt_template,substr($data,$consumed));
                $consumed += 12;
            }
            elsif($remain_len == 8) {
                push @a,unpack("x${consumed} C c3 $REAL",$data);
                $consumed += 8;
            }
            elsif($remain_len == 4) {
                push @a,unpack("x${consumed} C c3",$data);
                $consumed += 4;
            }
            elsif($remain_len != 0) {
                my @items = qw( C c c c);
                my $str = join "",@items[0..($remain_len-1)];
                push @a, unpack("x${consumed} $str",$data);
                $consumed += $remain_len;
            }
            for(1..4) {
               if($consumed < $len )
               {
                    $val = unpack("x${consumed} C/a",$data);
                    $consumed += length($val) + 1;
                    push @a,$val;
                }
                else { last; }
            }
            $remain_len = $len - $consumed;
            if($remain_len == 8) {
                push @a,unpack("x${consumed} $REAL $REAL",$data);
                $consumed += 8;
            }
            elsif($remain_len == 4) {
                push @a, unpack("x${consumed} $REAL",$data);
                $consumed += 4;
            }
                  
         }
        }
        # FTR
        elsif($cardinal == FTR ) {
            @a = unpack("$UNSIGN_LONG C2 C",$data);
        
            $consumed = 7;
            if($consumed >= $len) { goto RETURN; }
            ## OPT_FLAG
            push @a,unpack("x${consumed}C",$data);
            $consumed++;

            for(1..4) {
                ## 4 U4
                if($consumed >= $len){goto RETURN;}
                push @a,unpack("x${consumed} $UNSIGN_LONG",$data);
                $consumed += 4;
            }

            for(1..2) {
                ## 2x I4
                if($consumed >= $len) { goto RETURN;}
                push @a,unpack("x${consumed} $SIGN_LONG",$data);
                $consumed += 4;
            }
            ## VECT_OFF
            if($consumed >= $len) { goto RETURN;}
            push @a,unpack("x${consumed} $SIGN_SHORT",$data);
            $consumed += 2;

            ### 
            my ($rtn_icnt,$pgm_icnt);
            if($consumed >= $len) { goto RETURN; }
            $rtn_icnt = unpack("x${consumed} $UNSIGN_SHORT",$data);
            push @a,$rtn_icnt;
            $consumed += 2;
            
            if($consumed >= $len) { goto RETURN;}
            $pgm_icnt = unpack("x${consumed} $UNSIGN_SHORT",$data);
            push @a,$pgm_icnt;
            $consumed += 2;
            
            if($consumed >= $len) { goto RETURN;}
            ## RTN_INDX jxU2
            push @a, [unpack("x${consumed} ${UNSIGN_SHORT}$rtn_icnt",$data) ];
            $consumed += 2 * $rtn_icnt;
            #print "j = $rtn_icnt k = $pgm_icnt  read so far $consumed\n";
            if($consumed >= $len) { goto RETURN;}
            ## RTN_STAT 
            ## j x N*1 nibble 
            if($rtn_icnt) {
            my $nibble_cnt = int($rtn_icnt /2) + ($rtn_icnt%2);
            push @a , [unpack("x${consumed} C${nibble_cnt}",$data)] ;
            $consumed += $nibble_cnt;
            }
            ### PGM_INDX
            if($consumed >= $len) { goto RETURN;}
            push @a , [unpack("x${consumed} ${UNSIGN_SHORT}$pgm_icnt",$data)];
            $consumed += 2 * $pgm_icnt;

            if($consumed >= $len) { goto RETURN;}
            ### PGM_STAT
            if($pgm_icnt) {
            my $pgm_nibble_cnt = int($pgm_icnt/2) + ($pgm_icnt%2);
            push @a, [ unpack("x${consumed} C${pgm_nibble_cnt}",$data)];
            $consumed += $pgm_nibble_cnt;
            }
            if($consumed >= $len) { goto RETURN;}
            ## fail pin D*n
            my $bit_length = unpack("x${consumed} $UNSIGN_SHORT",$data);
            $consumed +=2;
            #print "fail pin DN = $bit_length $consumed\n";
            if($bit_length) {
                my $byte_cnt = int($bit_length/8) ;
                if( $bit_length %8 ) { $byte_cnt++;}
                my @fail_pin_vec = unpack("x${consumed} C${byte_cnt}",$data);
                push @a, [@fail_pin_vec];
                $consumed +=  scalar(@fail_pin_vec);
            }
            ## VECT_NAM TIME_SET etc 7 C*n
            for(1..7) { 
                if($consumed >= $len) { goto RETURN;}
                my $s = unpack("x${consumed} C/a",$data);
                push @a,$s;
                $consumed += length($s)+ 1;
            }
            ## PATG_NUM
            if($consumed < $len) {
                push @a,unpack("x${consumed} C",$data);
                $consumed += 1;
            }
            ## SPIN_MAP D*n
            if($consumed < $len) {
                my $bit_length = unpack("x${consumed} ${UNSIGN_SHORT}",$data);
                $consumed += 2;
                if($bit_length) {
                my $bcount = int($bit_length/8);
                if( $bit_length %8) { $bcount++;}
                my @dn = unpack("x${consumed} C${bcount}",$data);
                push @a,[@dn];
                $consumed +=scalar(@dn);
                }
            }
            
        }
        elsif($cardinal == MPR) {
            @a = unpack("${UNSIGN_LONG}CCCC",$data);
            $consumed = 8;
            my $v;
            my ($rtnt_icnt,$rslt_cnt);
            if($consumed >= $len) {
                goto MPR_DONE;
            }
            
            $v = unpack("x${consumed} $UNSIGN_SHORT",$data);
            push @a,$v;
            $consumed += 2;
            $rtnt_icnt = $v;
            
            if($consumed >= $len) { goto MPR_DONE;}
            $v = unpack("x${consumed} $UNSIGN_SHORT",$data);
            push @a,$v;
            $consumed += 2;
            $rslt_cnt = $v;
           # print "MPR j = $rtnt_icnt k = $rslt_cnt\n";
            if($consumed >= $len) { goto MPR_DONE; }
            ## N*1  nibble= 4 bits of byte 
            ## only whoe byte can be written to STDF
            if($rtnt_icnt) {
            my $nibble_cnt = int($rtnt_icnt /2) + ($rtnt_icnt %2);
            ## ie. nibble count 5 -> 3 
            push @a, [unpack("x${consumed} C${rtnt_icnt}",$data)];
            $consumed += $nibble_cnt;
            }
            if($consumed >= $len) { goto MPR_DONE;}
            push @a, [unpack("x${consumed} (${REAL})${rslt_cnt}",$data)];
            $consumed += 4 * $rslt_cnt;  # REAL 4 bytes
            #print "consumed so far before TEST_TXT $consumed\n";
            if($consumed >= $len) { goto MPR_DONE ; }
            ## TEST_TXT C*n
            $v = unpack("x${consumed} C/a",$data);
            $consumed += length($v) + 1;
            push @a,$v;
            ## ALARM_ID C*n
            if($consumed >= $len) { goto MPR_DONE; }
            $v = unpack("x${consumed} C/a",$data);
            $consumed += length($v) + 1;
            push @a,$v;

            if($consumed >= $len) { goto MPR_DONE; }
            ## OPT_FLAG to INCR_IN
            my $template = "C ccc $REAL $REAL $REAL $REAL";
            my $remaining = $len - $consumed;
            if($remaining >= 20) {
                push @a, unpack("x${consumed} $template",$data);
                $consumed += 20;
            }
            elsif($remaining >= 16) {
                push @a , unpack("x${consumed} C ccc $REAL $REAL $REAL",$data);
                $consumed += 16;
            }
            elsif($remaining >= 12) {
                push @a, unpack("x${consumed} C ccc $REAL $REAL ",$data);
                $consumed += 12;
            }
            elsif($remaining >= 8 ) {
                push @a , unpack("x${consumed} C ccc $REAL",$data);
                $consumed += 8;
            }
            elsif($remaining >= 4) {
                push @a, unpack("x${consumed} C ccc",$data);
                $consumed += 4;
            }
            else {
                for(1..3) {
                    push @a, unpack("x{$consumed} c",$data);
                    $consumed++;
                }
            }

            if($consumed >= $len) { goto MPR_DONE; }
            ### RTN_INDX jxU2
            push @a, [unpack("x${consumed} ${UNSIGN_SHORT}${rtnt_icnt}",$data)];
            $consumed += 2*$rtnt_icnt;

            for(1..5) {
                if($len > $consumed) {
                    $v = unpack("x${consumed} C/a",$data);
                    $consumed += length($v) + 1;
                    push @a,$v;
                } else {
                    last;
                }
            }
            if($len > $consumed) {
                push @a, unpack("x${consumed} $REAL",$data);
                $consumed += 4;
            }
            if($len > $consumed) {
                push @a, unpack("x${consumed} $REAL",$data);
                $consumed += 4;

            }
            MPR_DONE:
            
        }
        # PIR
        elsif($cardinal == PIR) {
             @a = unpack("CC",$data);
             $consumed = 2;
        }
        # PRR
        elsif($cardinal == PRR) {
            @a = unpack($prr_fixed_template,$data);
            
          $consumed = 7;
          my $val;
          if($consumed < $len) 
          {
              ## softbin
              $val = unpack("x${consumed} $UNSIGN_SHORT",$data);
              push @a,$val;
              $consumed += 2;
          }
          if($consumed < $len)
          {
            # X_COORD
            $val = unpack("x${consumed} $SIGN_SHORT",$data);
             push @a,$val;
             $consumed += 2;
          }
          if($consumed < $len)
          {
             $val = unpack("x${consumed} $SIGN_SHORT",$data);
             push @a,$val;
             $consumed += 2;


          }
          if($consumed < $len)
          {
              $val = unpack("x${consumed} $UNSIGN_LONG",$data);
              push @a,$val;
              $consumed += 4;
          }
          if($consumed < $len )
          {
              #part_id
                $val = unpack("x${consumed} C/a",$data);
                $consumed += length($val) + 1;
                push @a,$val;
          }
          if($consumed < $len )
          {
                # part_txt
                $val = unpack("x${consumed} C/a",$data);
                $consumed += length($val) + 1;
                push @a,$val;
          }
         
          if($consumed < $len) {
                 my $count = unpack("x${consumed} C",$data);
                 $consumed++;
                if($count) {
                my $bit_vector = substr($data,$consumed+1,$count);
                if(length($bit_vector) != $count) {
                    die "Error in parsing PRR record: PART_FIX field.\n";
                }

                push @a, $bit_vector if($count);
                $consumed += $count;
                } 

            }

        }
        # BPS
        elsif($cardinal == BPS ) {
            if(length($data)) {
                @a = unpack("C/a",$data);
                $consumed = length($a[-1])+1;
            }
        }
        # EPS
        elsif($cardinal == EPS) {
            unless(length($data) == 0) {
                die "Error in parsing EPS.\n";
            }
        }
        # GDR
        elsif($cardinal == GDR) {
            my $fld_cnt = unpack($UNSIGN_SHORT,$data);
            $consumed += 2;
            # V* n
            ## data type is in 1st byte
            for(1..$fld_cnt) {
                my $type = unpack("x${consumed} C",$data);
                $consumed += 1;
                if($type == 0) {
                    #push @a,$type; # dun return padding
                    next; 
                }
               # unless( exists($gdr_type_table{$type})) {
                #    die "Error parsing GDR: wrong GEN_DATA type $type\n";
               # }
			   my $v;
			    if(exists($gdr_type_table{$type}) ) {
					my $type_fmt = $gdr_type_table{$type};
					$v = unpack("x${consumed} $type_fmt",$data);
					my $s;
					if($type ==10 ) {
						$s = length($v) +1;
					} 
					else {
						$s = $size_table{$type_fmt};
					}
					$consumed += $s;
				}
				elsif($type == 11) {
					### B*n variable length bit encoded field
					## 1st byte unsigned count of BYTES to follow
					my $cnt = unpack("x${consumed}C",$data);
					$consumed += 1 + $cnt;
					$v = substr($data,$consumed,$cnt);
					
				}
				elsif($type == 12) {
					## D*n bit encoded data  
					## fist 2 bytes of strings are length in *bits*
					my $bit_length = unpack("x${consumed} $UNSIGN_SHORT",$data);
					$consumed +=2;
					if($bit_length) {
					my $byte_cnt = int($bit_length/8) ;
					if( $bit_length %8 ) { $byte_cnt++;}
					my @array = unpack("x${consumed} C${byte_cnt}",$data);
					$v = [@array];
					$consumed +=  scalar(@array);
					}
				}
				elsif($type == 13) {
					## N*1 unsigned nibble 
					## only whole byte can be written to STDF
					$v = unpack("x{$consumed} C",$data);
					$consumed++;

				}
				else {
					die "Error parsing GDR: Invallid GEN_DATA type $type at rec # $rec_num\n";
				}
                push @a,$type,$v;
				
            
            }
        }
         # DTR 
        elsif($cardinal == DTR) {
            push @a,unpack("C/a",$data);
            $consumed = length($a[-1])+1;
        }
        #MIR 
        elsif($cardinal == MIR) {
            @a = unpack("${UNSIGN_LONG}2 C4 $UNSIGN_SHORT C (C/a)5",$data);
            $a[3] = chr($a[3]);
            $a[4] = chr($a[4]);
            $a[5] = chr($a[5]);
            $a[7] = chr($a[7]);
            #print "mir len:$len\n";
            $consumed = 15;
            for(8..12) {
              $consumed += 1 + length($a[$_]);
            }
            #print "Consumed: $consumed\n";
            my $remain_data = substr($data,$consumed);
            for(1..25) {
                if(length($remain_data) ==0) { last; }
                my $str= unpack("C/a",$remain_data);
                push @a,$str;
                $consumed += length($str)+ 1;
                $remain_data = substr($remain_data,length($str)+1);
            }
            
        }
        # ATR
        elsif($cardinal == ATR) {
            push @a,unpack("$UNSIGN_LONG C/a",$data);
            $consumed = 5 + length($a[-1]);
        }
        # WIR
        elsif($cardinal == WIR) {
        
            @a = unpack("CC$UNSIGN_LONG",$data);
            $consumed = 6;
            if($len > 6)
            {
                push @a, unpack("x6C/a",$data);
                $consumed += length($a[-1])+1; 
            }
        }
        # WRR
        elsif($cardinal == WRR) {
            @a = unpack("C2 ${UNSIGN_LONG}2",$data);
            $consumed = 10;
            ## 4 R4
            for(1..4) {
                if($consumed >= $len) { goto RETURN;}
                push @a,unpack("x${consumed} $UNSIGN_LONG",$data);
                $consumed += 4;
            }
            for(1..6) {
                if($consumed >= $len) { goto RETURN;}
                my $str = unpack("x${consumed} C/a",$data);
                $consumed += 1 + length($str);
                push @a,$str;
            }
           
        }
        # WCR
        elsif($cardinal == WCR) {
            #@a = unpack("${REAL}3 CC ${SIGN_SHORT}2 CC",$data);
            #@a[4,7,8] = map { chr($_) } @a[4,7,8];
            if($len >= 20) {
                @a = unpack("${REAL}3 CC ${SIGN_SHORT}2 CC",$data);
                $consumed = 20;
            }
            else {
                for(1..3) {
                    if($len > $consumed) {
                        push @a,unpack("x${consumed} $REAL",$data);
                        $consumed += 4;
                    }
                }
                ## WF_UNITS
                if($len>$consumed) {
                    my $wf_unit= unpack("x${consumed} C",$data);
                    push @a,$wf_unit;
                    $consumed++;
                }
                if($len > $consumed) {
                    my $wf_flat = unpack("x${consumed} C",$data);
                    push @a,chr($wf_flat);
                    $consumed++;
                }
                if($len > $consumed) {
                    my $v = unpack("x${consumed} $SIGN_SHORT",$data);
                    push @a,$v;
                    $consumed += 2;
                }
                if($len > $consumed) {
                    my $v = unpack("x${consumed} $SIGN_SHORT",$data);
                    push @a,$v;
                    $consumed += 2;
                }
                if($len > $consumed) {
                    my $pos_x = unpack("x${consumed} C",$data);
                    push @a,chr($pos_x);
                    $consumed++;
                }
                if($len > $consumed) {
                    my $pos_y = unpack("x${consumed} C",$data);
                    push @a,chr($pos_y);
                    $consumed++;
                }

            }
        
        }
        # MRR
        elsif($cardinal == MRR) {
            @a = unpack($UNSIGN_LONG,$data);
            $consumed = 4;
            if($len > 4) {
                 my $val = unpack("x4 C",$data);
                 $val = chr($val);
                 push @a,$val;
                 $consumed += 1;
            }
            if($len > 5) {
                my $remain_data = substr($data,5); 
                for(1..2) {
                     if(length($remain_data)==0) { last;}
                     my $str = unpack("C/a",$remain_data);
                     push @a, $str;
                     $consumed += length($str)+1;
                     $remain_data = substr($remain_data,1+length($str) );
                }
            }
        }
         # SDR
        elsif($cardinal == SDR) {
            @a = unpack("C2 ",$data);
            my @sites = unpack("xxC/C",$data);
            push @a,[@sites];
            $consumed = 3 + scalar(@sites);
            my $remain_data = substr($data,$consumed);
            for(1..16) {
                if(length($remain_data) == 0) { last;}
                my $str = unpack("C/a",$remain_data);
                push @a,$str;
                $remain_data = substr($remain_data,1+length($str));
                $consumed += 1+length($str);
            }           
            
        }
        elsif($cardinal == RDR) {
            my $num_bins = unpack($UNSIGN_SHORT,$data);
            push @a, [unpack("x2 ${UNSIGN_SHORT}[$num_bins]",$data)];
            $consumed += 2 + 2 * $num_bins;


        }
        #HBR or SBR
        elsif($cardinal == HBR || $cardinal == SBR) {
            @a = unpack("C2 $UNSIGN_SHORT $UNSIGN_LONG",$data);
            $consumed = 8;
            if($len > 8) { 
                my $pf = unpack("x8 C",$data); 
                $pf = chr($pf);
                push @a,$pf;
                $consumed++;
            }
            if($len> 9) { my $name = unpack("x9 C/a",$data); push @a,$name; 
                $consumed += length($name) + 1;
            }
            
        }
        # PCR
        elsif($cardinal == PCR) {
            @a = unpack("CC ${UNSIGN_LONG}",$data);
            $consumed = 6;
            for(1..4) {
                if($consumed >= $len ) { goto RETURN;}
                my $v = unpack("x${consumed} $UNSIGN_LONG",$data);
                push @a,$v;
                $consumed += 4;
            }
            
        }
        # PMR
        elsif($cardinal == PMR) {
            @a = unpack($UNSIGN_SHORT,$data);
            if($len > 2) {
                push @a,unpack("x2 $UNSIGN_SHORT",$data);

            }
            $consumed = 4;
            if($len > $consumed) {
                my $str = unpack("x${consumed} C/a",$data);
                $consumed += length($str)+1;
                push @a,$str;
            }
            if($len > $consumed) {
                my $str = unpack("x${consumed} C/a",$data);
                $consumed += length($str)+1;
                push @a,$str;
            }
            if($len > $consumed) {
                my $str = unpack("x${consumed} C/a",$data);
                $consumed += length($str)+1;
                push @a,$str;            }
            if($len > $consumed) {
                push @a,unpack("x${consumed} C",$data);
                $consumed += 1;
            }
             if($len > $consumed) {
                push @a,unpack("x${consumed} C",$data);
                $consumed++;
            }
        }
        # PGR
        elsif($cardinal == PGR) {
            @a = unpack("${UNSIGN_SHORT} C/a",$data);
            $consumed = length($a[1])+1 + 2;
            my @pmr_indx = unpack("x${consumed} $UNSIGN_SHORT /$UNSIGN_SHORT ",$data);
            push @a,[@pmr_indx];
            $consumed += 2 + scalar(@pmr_indx) * 2;
        }
        ## PLR
        elsif($cardinal == PLR) {
            my $grp_cnt  = unpack($UNSIGN_SHORT,$data);
            $consumed = 2;
            push @a,$grp_cnt;
            if($grp_cnt > 0 && $len > $consumed) {
                push @a, unpack("x${consumed} ${UNSIGN_SHORT}${grp_cnt} ${UNSIGN_SHORT}${grp_cnt} C${grp_cnt}",$data);
                $consumed += 5 * $grp_cnt;  # 2*U2 + 1 U1

            }
            for(1..4) {
                if($consumed >= $len) { last; }
               my @array_cn = unpack("x${consumed} (C/a)$grp_cnt",$data);
                for(@array_cn) {
                    $consumed += 1 + length($_);
                }
                push @a, [@array_cn]; ## PGM_CHAR, RTN_CHAR, PGM_CHAL, RTN_CHAL
            }
        }
        # TSR
        elsif($cardinal == TSR) {
            @a = unpack("C3 ${UNSIGN_LONG}",$data);
            $a[2] = chr($a[2]);
            $consumed = 7;
            ## 3 U4
            for(1..3) {
                push @a, unpack("x${consumed} $UNSIGN_LONG",$data);
                $consumed += 4;
            }
            my $val;
            if($consumed < $len )
            {
                $val = unpack("x${consumed} C/a",$data);
                $consumed += length($val) + 1;
                push @a,$val;
            }
            if($consumed < $len )
            {
                $val = unpack("x${consumed} C/a",$data);
                $consumed += length($val) + 1;
                push @a,$val;
            }
            if($consumed < $len )
            {
                $val = unpack("x${consumed} C/a",$data);
                $consumed += length($val) + 1;
                push @a,$val;
            }
            for my $item ( "C",$REAL,$REAL,$REAL,$REAL,$REAL) {
                if($consumed >= $len) { last; }
                $val = unpack("x${consumed} $item",$data);
                push @a,$val;
                $consumed += $size_table{$item};
            }
        }
      # records not implemented yet..
     else {
           # return [$name,$typ,$sub,$data];
            return $obj->handle_unk_record($typ,$sub,$data);
       }
       RETURN:
       if($len != $consumed) {
            die "Error parsing record $name rec num $rec_num at $num_bytes_read position : rec len ($len) parsed record ($consumed)\n";
       }
       unshift @a,$name;
        return [@a];
       
    }
    close($fh) if($own_fh);
    $done = 1;
    if(!defined($n)) {
        die "Read Error in parsing\n";
    }
    return undef;
    };
    $obj = {
        CPU_TYPE   => $cpu,
        STDF_VER   => $stdf_ver,
        _PARSER    => $parser,
        BYTES_READ => \$num_bytes_read,
        REC_NUM    => \$rec_num,
        _FileHandle => $fh,
        _Own_FileHandle => $own_fh,
        _done_flag    => \$done,
    };
    bless($obj,$class);
    return $obj;
}


=head2 close

close underlying file handle.
This method will not close if handle is not opened by this module

=cut

sub close
{
    my $self = shift;
    $self->{_done_flag} = 1;  # mark done

    if($self->{_Own_FileHandle}) {
        if(openhandle($self->{_FileHandle})) {
        close($self->{_FileHandle}) or die "Fail to close:$!";
        }
    }
}

=head2 bytes_read
  
  return current number of bytes from beginning of file

=cut

sub bytes_read
{
    my $self = shift;
    my $ref_num_bytes = $self->{BYTES_READ};
    return $$ref_num_bytes;
}

=head2 current_record_num

  return current record number

=cut
sub current_record_num
{
    my $self = shift;
    my $ref_rec_num = $self->{REC_NUM};
    return $$ref_rec_num;
}

=head2 cpu_type

  return CPU type of STDF. Refer to STDF V4 spec
=cut

sub cpu_type
{
    my $self = shift;
    return $self->{CPU_TYPE};
}
=head2 stdf_ver

  return STDF version.
=cut

sub stdf_ver
{
    my $self = shift;
    return $self->{STDF_VER};
}

=head2 stream

  return underlying STDF record stream which is a code ref.
  Call this code ref to retrieve next record.

  $stream = $p->stream;
  while( my $r = $stream->() ) {
  
  }
=cut
sub stream
{
    my $self = shift;
    $self->{_PARSER};
}

=head2 get_next_record

  return next STDF record, undef for EOF
  return data type is array ref 
     [ REC_NAME, Field1,field2, ... fieldn]
  atomic value like U1,U2,I1,I2,I4,R4 occupy as one element of type Perl SCALAR in array
  C*n data type  translates to perl string
  array field value are encoded to array ref of respective type
  Unknown record type REC_NAME is 'NA', follow by rec_typ,rec_sub, rec_body


=cut

sub get_next_record
{
  my ($self)=@_;
  &{ $self->stream};

}

=head2 handle_unk_record
  This method is place holder for subclasses to override parser behavior for unknown record
  default implementation is to return ["NA",rec_typ,rec_sub,rec_body]

=cut

sub handle_unk_record
{
  my ($self,$typ,$sub,$record_body) = @_;
  # default method just return
  ["NA",$typ,$sub,$record_body];

}

=head1 AUTHOR

Nyan, C<< <nyanhtootin at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-stdf-parser at rt.cpan.org>, or through
the web interface at L<https://rt.cpan.org/NoAuth/ReportBug.html?Queue=STDF-Parser>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc STDF::Parser


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<https://rt.cpan.org/NoAuth/Bugs.html?Dist=STDF-Parser>

=item * CPAN Ratings

L<https://cpanratings.perl.org/d/STDF-Parser>

=item * Search CPAN

L<https://metacpan.org/release/STDF-Parser>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2024 by Nyan.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)


=cut

1; # End of STDF::Parser
