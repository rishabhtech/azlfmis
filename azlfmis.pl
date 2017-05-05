#!/usr/bin/perl
#
###############################################################################################################
#  Copyright (c), 2017 Rishabh Tech, Greater Atlanta, US
#  This utility usage is under licence terms, contact Ravi Tripathi <ravitripathi@rishabhtech.com> for details
###############################################################################################################
# Alpha Release 
# Analyze WebSphere log files and provide Management Information System (MIS) and operational Reports to business team.
# This script is portable and can be run on UNIX or WINDOWS
#
# Features: 
# 1. Browse through WAS installation or WAS profile directories and process the log files 
# 2. Accept zip file from command line or from a directory 
# 3. Accept log file(s) from command line or from a directory 
# 4. Accept non-standard log file names
# 4. Generates sequence diagrams as simple SVG files for the stack traces 
# 5. Generates simple HTML with basic MIS report for the same
#
# PRE-REQUISITE
# PERL Strawbery Installation
# perl5 (revision 5 version 24 subversion 1); Strawberry-perl 5.24.1.1
#
# Short Falls/Limitations
# 1. Tool does not access WebSphere MBEAN to get hostname and has to be passed in command line. 
#    This means, only one host installations are processed in Alpha Release. - TODO
# 2. Configuration file and execution through webserver is not included in Alpha Release. - TODO
# 3. Performance time - takes more time to create the files, need better way of working (should be quite fast)
# 4. To be tested on a ND deployment on this box, download WAS and webserver (later)
#
# ISSUES
#  1. Error count > 0 must be highlighted
#  2. Font size - responsive
#  3. 
#
=TODO 
1. Implement search as below
  Search by hostname, by server, by log file, by exceptions, message id, period
2. Add more options to refine as below
    Refine by exceptions, period
3. Add nodejs, expressjs to serve the information
    Provide search page
    Based on search page, get data and serve.
    Options : See if report existing then serve, else generate report using data available, if data not available then prompt for SWEEP
5. install.bat and install.sh
6. UCD Plugin
7. Use GITHUB for source code

4. Change the reporting to AngularJS (both index.html and gzlfmis)
7. alerts and audience
8. Run SWEEP jobs and schedule over main page
9. Add control panel
10. We could add a DB to enable enterprise architecture and service
11. Use wsadmin to get more details on the live servers
12. Work on webservers
13. USE NPM for installation

=cut        
use strict;
use warnings;
use 5.010;
use Getopt::Long qw(GetOptions);
use Data::Dumper qw(Dumper); 
#use File::Tempdir;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use DateTime;
use Cpanel::JSON::XS qw(encode_json decode_json);

my $help;
my $hostname;
my @nsfiles;
my @logfiles;
my @profiledirs;
my @zipfiles;
my @filesdirs;
my $lfservers;


usage() if scalar @ARGV < 1;

GetOptions (
            "h=s" => \$hostname,
            "help=s" => \$help,
            "nsf=s" => \@nsfiles,
            "f=s" => \@logfiles,
            "p=s" => \@profiledirs,
            "z=s" => \@zipfiles,
            "s=s" => \$lfservers,
            "d=s" => \@filesdirs
        );
die "\nOption --h hostname mandatory not specified.\n" unless $hostname;
die "\nAtlease one option --f or --p or --z or --d mandatory not specified.\n" unless (@logfiles or @profiledirs or @zipfiles or @filesdirs);
if ((scalar @filesdirs > 0) or (scalar @zipfiles > 0) or (scalar @logfiles > 0)) {
    die "\nOption --s servername mandatory not specified.\n" unless $lfservers;
}

usage() if $help;

sub usage {
    say "\n  1. Passing log files names in command line";
    say "       azlfmis.pl --f <WebSphere Log File Name>   --nsf <Non standard log file name> --h <hostname> --s <servername>";
    say "       e.g. azlfmis.pl --f C:\\work\\IBM\\WebSphere\\AppServer\\profiles\\AppSrv01\\logs\\nodeagent\\SystemOut.log --h Australia01 --s server1\n" ;
    say "       Note : Server name mandatory for the logs to be processed\n";
    say "\n  2. Passing zip file(s) containing log files in command line ";
    say "       azlfmis.pl --z <zip File Name> --nsf <Non standard log file name> --h <hostname> --s <servername>";
    say "       e.g. azlfmis.pl --z p1.zip  --h Australia01 --s server1\n";
    say "       Note : Server name mandatory for the logs to be processed\n";
    say "\n  3. Passing WAS Profile dir in command line ";
    say "       azlfmis.pl --p <WebSphere AppServer or Profiles directory>   --nsf <Non standard log file name> --h <hostname>";
    say "       e.g azlfmis.pl --p C:\\work\\IBM\\WebSphere\\AppServer\\profiles  --h Australia01\n";
    say "       e.g azlfmis.pl --p C:\\work\\IBM\\WebSphere\\AppServer  --h Australia01\n";
    say "\n  4. Passing directory name containing log files";
    say "       azlfmis.pl  --nsf <Non standard log file name> --d <Folder containing WebSphere Log File Names>  --h Australia01 --s <servername>";
    say "       e.g azlfmis.pl --d C:\\WebSphereLogs --h Australia01 --s serverName\n";
    say "       Note : Server name mandatory for the logs to be processed\n";
    say "       azlfmis.pl --nsf <Non standard log file name> --d C:\\WebSphereLogs --h Australia01 --s serverName\n";
    say "       e.g azlfmis.pl --nsf sq.log --d c:\\TEMP  --h Australia01 -s server1\n";
    exit
}

# MIS index page requirements
my $htlist={};
my $snlist={};
my $exlist={};
my $milist={};
my $rpinfo={};

if (scalar @zipfiles > 0) {
    my $dir = File::Spec->catfile(File::Spec->tmpdir(),"AZLFMIS");
    
    foreach my $zipFile ( @zipfiles ) {
       
        unless(-e $dir or mkdir $dir) {
            die "\nUnable to create $dir\n";
        }        
        my $zip = Archive::Zip->new();
        unless ( $zip->read( $zipFile ) == AZ_OK ) { 
            die "\nread error ".$zipFile ;
        }
        $zip->extractTree( '', $dir);

        opendir my $dh, $dir or die;
        while (my $sub = readdir $dh) {
            next if $sub eq '.' or $sub eq '..';     
            my $filename = File::Spec->catfile($dir,$sub);
            addlogs($filename);
        }
        close $dh;            
    }
    if (not @logfiles) {
        die "\nNo log files found in zip\n\n";
    }
}

if (scalar @filesdirs > 0) {
    foreach my $dir ( @filesdirs ) {
        opendir my $dh, $dir or die;
        while (my $sub = readdir $dh) {
            next if $sub eq '.' or $sub eq '..';     
            next if -d $sub;
            my $filename = File::Spec->catfile($dir,$sub);
            addlogs($filename);
        }
        close $dh;            
    }
}

foreach my $md (@profiledirs) { 
    cltlfiles($md);
}

parseLF4MIS();
#parseLF4MIS(\@logfiles);

createMIS();


sub escape_xml ($) {
  my $text = shift;
  $text =~ s/</&lt;/g;
  $text =~ s/ < >/&gt;/g;
  return $text;
}

sub createMIS {
    #
    # This is a temporary process
    # The generation of the MIS will be through request/response (NODE.JS)
    #
    my $htstr =""; #HOSTNAMES#
    my $srstr=""; #SERVERNAMES#
    my $apstr=""; #APPLICATIONS# -  TO BE PICKED UP FROM WebSphere installedApps DIRECTORY; 
    my $exstr=""; #EXCEPTIONS#
    my $mistr=""; #MESSAGEIDS#
    
    my $servernames='';
    my $logfilenames=""; #LOGFILES#
    my $chstr="";
    
    my $ststrr = "";
    my $ii=0;
    
    # to get the keys
    foreach my $prkeys (keys %$rpinfo) {
       my $len = scalar @{ $rpinfo->{$prkeys} };
       my $svgstrr="";
       my $tbl="<table class='table'>
                    <thead><tr><td>Message ID</td><td>Stack Trace</td><td>Sequence Diagram</td></tr></thead>
                    <tbody>";
       for (my $i=0;$i<$len;$i++) {
            my @farr = @{ $rpinfo->{$prkeys} }[$i];    
            my $ll= scalar @farr;
            for (my $j=0;$j<$ll;$j++) {
                if(ref($farr[$j]) eq 'ARRAY') {
                    $mistr = $mistr."<option value='1'>".$farr[$j][0]."</option>";
                }               
                
                my $stname = substr($farr[$j][3],index($farr[$j][3],"stsq"));
                my $svgname = substr($farr[$j][3],index($farr[$j][2],"stsq")); # Mahesh check why file name is .txt here - TODO
                $svgstrr=$svgstrr."<tr><td>".$farr[$j][0]."</td><td><a href='".$farr[$j][3]."' target='_blank'>".$stname."</a></td><td><a href='".$farr[$j][2]."' target='_blank'>".$svgname."</a></td></tr>";
            }
       }
       if ($svgstrr) {
           $tbl = $tbl.$svgstrr."</tbody></table>";
       } else {
           $tbl = "";
       }
       my @tokens = split(/\+\+/, $prkeys);       
       $tokens[0]=~ s/^\s+|\s+$//g;
       $tokens[1]=~ s/^\s+|\s+$//g;
       $tokens[2]=~ s/^\s+|\s+$//g;
       $htstr = $htstr."<option>".$tokens[0]."</option>";
       $srstr = $srstr."<option>".$tokens[1]."</option>";

       my $lt = rindex($tokens[2],"/");
       my $fulllogpath = $tokens[2];
       if ($lt == -1) {
           $lt = rindex($tokens[2],"\\");
           $fulllogpath =~ s/\\/\\\\/;
           $fulllogpath="file:///".$fulllogpath;
       }
       my $lff = substr($tokens[2],$lt+1);
=NOT Required
       if ($tokens[1] eq "") {
            if ($lfservers) {
                $tokens[1] = $lfservers;
            }
       }
=cut       
       $servernames = $servernames."<option>".$tokens[1]."</option>";
       $logfilenames = $logfilenames."<option>".$tokens[1]." ".$lff."</option>";
       
       $ii++;
       #TODO - Mahesh the presentation here is a mess, must be taken care latter.
       $chstr=$chstr."<div class='col-sm-4 col-lg-4 col-md-4' servername='".$tokens[1]."' hostname='".$tokens[0]."' logfile='".$lff."'>
                        <div class='thumbnail'>
                            <div class='row'>
                                <div class='col-md-6'>
                                    Hostname: ".$tokens[0]." 
                                </div>
                                <div class='col-md-6'>
                                    Server Name: ".$tokens[1]." 
                                </div>
                            </div>
                            <div class='row'>
                                <div class='form-group col-md-4'>
                                    Logfile :<a href='".$fulllogpath."'  target='_blank'>".$lff."</a>
                                </div>
                                <div class='form-group col-md-4'>
                                    <p>Message Count:".$len."</p>
                                </div>
                                <div class='form-group col-md-4'>
                                    <a href='#' data-toggle='collapse' data-target='#stacktrace$ii'>View Stack Traces</a>
                                </div>
                            </div>  
                            <div id='stacktrace$ii' class='collapse col-sm-4 col-lg-4 col-md-4'>".$tbl."</div>
                        </div>
                     </div>";
                     
    }

    #Create index.html (Main Refine Page)
    open (my $out, '>',"index.html") or die "\nUnable to open index";
    open (my $in, '<', "index.template") or die "\nUnable to open index.template";
    
    while (my $row = <$in>) {
        if (index($row,"#HOSTNAMES#") > -1) {
            $row =~ s/#HOSTNAMES#/$htstr/g;
        }
        if (index($row,"#SERVERNAMES#") > -1) {
            $row =~ s/#SERVERNAMES#/$srstr/g;
        }
        if (index($row,"#MESSAGEIDS#") > -1) {
            $row =~ s/#MESSAGEIDS#/$mistr/g;
        }
        print $out $row;        
    }
    close $in;
    close $out;
    my $dt=DateTime->now;
    #one log sweep per hour - this may be high on production server
    my $misdir = $dt->dmy('_')."_".$dt->hour."_".$dt->minute;

    $servernames = "<select name='servers' id='servers'>".$servernames."</select>";
    $logfilenames = "<select name='logfiles' id='logfiles'>".$logfilenames."</select>";
    #Create Report page here
    my $sum = "<table class='table'>
                <thead><tr><td colspan='2' class='h4'>Sumary Information</td></tr></thead>
                <tbody>
                    <tr><td>Hostname:</td><td>".$hostname."</td></tr>
                    <tr><td>Server Name:</td><td>".$servernames."</td></tr>
                    <tr><td>Log File:</td><td>".$logfilenames."</td></tr>
                    <tr><td>Report Date:</td><td>". $dt->dmy('/')." ".$dt->hour.":".$dt->minute."</td></tr>
                </tbody>
            </table>";

    open (my $azo, '>',"azlfmis.html") or die "\nUnable to open azlfmis";
    open (my $azi, '<', "azlfmis.template") or die "\nUnable to open azlfmis.template";
    while (my $row = <$azi>) {
        if (index($row,"#SUMMARYSECTION#") > -1) {
            $row =~ s/#SUMMARYSECTION#/$sum/g;
        }
        if (index($row,"#LOGDTLS#") > -1) {
            $row =~ s/#LOGDTLS#/$chstr/g;
        }

        print $azo $row;        
    }
    close $azi;
    close $azo;      
    system("azlfmis.html");
}

sub addlogs {
    my ($lgrec) = @_;	
    if ($lgrec =~ /(?:SystemErr.log)$|(?:SystemOut.log)$/) {
        push @logfiles, $lgrec;
    } 
    if (scalar @nsfiles > 0) {
        foreach my $nsf (@nsfiles) {
            if ($lgrec =~ /(?:\$nsf)$/) {
                push @logfiles, $nsf;
            }                
        }
    }
}

sub getlfs {
    my ($lgrec) = @_;	
    if (-d $lgrec) {
        opendir my $dh, $lgrec or die;
        while (my $sub = readdir $dh) {
            next if $sub eq '.' or $sub eq '..';     
            getlfs("$lgrec/$sub");
        }
        close $dh;
    } else {
        addlogs($lgrec);
    }
    return;
}
 
sub cltlfiles {
    my ($location) = @_;
        
    if (not -d $location) {
        return;
    } else {
        if (index($location,"profiles") == -1) {
            #AppServer - one level higher directory
            $location = File::Spec->catfile($location, "profiles");
        }
        opendir my $dh, $location or return;
        while (my $sub = readdir $dh) {
            next if $sub eq '.' or $sub eq '..';
            my $prdir = File::Spec->catfile($location, $sub, "logs");
            getlfs($prdir);
        }
        close $dh;
    }
    return;
}

sub genMIS {
    my ($rarr, $prkey) = @_;
    my @sttr = @{ $rarr };    
    
    my $dt=DateTime->now;
    #one log sweep per hour - this may be high on production server
    my $misdir = $dt->dmy('_')."_".$dt->hour."_".$dt->minute;
    
    #on running the sweep again with in the hour will update the directory
    unless(-e $misdir or mkdir $misdir) {
        die "\nUnable to create $misdir\n";
    }
    my $xmlfile=File::Spec->catfile($misdir, "stsq.xml");

    my @md;
    
    if (scalar @sttr != 0) {
    # Create output html file for all stack traces 
    # options - one file per trace or all in one; for now all stack traces in same output file     
        my $len = scalar @sttr;
        for my $i ( 0 .. $#sttr) {           
            my @strws=();
            for my $j ( 0 .. $#{ $sttr[$i] } ) {
                my $line = $sttr[$i][$j];
                #ignore Caused By and any other lines not starting with 'at'
                if ( index($line,'at ')==0 ) {
                    my @sprw = split(/at /, $line);
                    my $rw = $sprw[1];
                    $rw =~ s/^\s+|\s+$//g;
                    push @strws, $rw;
                }
=todo                
1. Caused by is a separate stack trace and must take precedence in the order of sequence. 
2. for now handled as part of a single sequence 
                if ( index($n,' Caused ')==0 ) {
                    #Caused By to be handled                    
                }
=cut                
            }
            my @sdrw = reverse @strws;        
            my $sqstr='At ';
            my $origclass='';            

            my @tokens = split(/  /, $sttr[$i][0]);
            my @strex = ();
            if (index($tokens[1],':') > 0) {
                @strex = split(/: /, $tokens[1]);
            } elsif (($tokens[2]) and (index($tokens[2],':') > 0)) {
                @strex = split(/: /, $tokens[2]);
            }
            my $rstr = $strex[0];
            my $messageid ='';
            if ($rstr) {
                $rstr =~ s/^\s+|\s+$//g;
                $messageid = $rstr;
            }
            
            for my $j ( 0 .. $#sdrw ) {                             
                my $lsdt = rindex($sdrw[$j], '.', rindex($sdrw[$j], '.')-1);
                my $ClassStr = substr($sdrw[$j],0,$lsdt);		
                my $ts = $lsdt+1;
                my $te = index($sdrw[$j], '(');
                my $MethodStr = substr($sdrw[$j], $ts, ($te-$ts));
                if (index($sdrw[$j], ':') > -1) {
                    $ts = index($sdrw[$j], ':') + 1;
                    $te = index($sdrw[$j], ')');
                } else {
                    $ts = index($sdrw[$j], '(') + 1;
                    $te = index($sdrw[$j], ')');
                }
                my $descStr = substr($sdrw[$j],$ts,($te-$ts));
                       
                my $esp="";
                if ($origclass eq $ClassStr) {
                    $esp="    ";
                } 
                if ($sqstr eq "At ") {
                    $sqstr = $sqstr.$ClassStr.".".$MethodStr.' Line '.$descStr."\n";
                } else {
                    $sqstr = $sqstr."    ".$esp.$ClassStr.".".$MethodStr.' Line '.$descStr."\n";
                }
                $origclass = $ClassStr;
            }           
            my $strcfile = File::Spec->catfile($misdir, "stsq".$i.".txt");
            open(my $fh, '>', $strcfile);
            print $fh $sqstr;
            close $fh;

            system('genericseq.pl UML::Sequence::SimpleSeq '.$strcfile.' > '.$xmlfile);            
            my $svgfile=File::Spec->catfile($misdir, "stsq".$i.".svg");
            system('seq2svg.pl '.$xmlfile.' > '.$svgfile);
            unlink glob $xmlfile;
            push @md, [$messageid,$sttr[$i],$svgfile,$strcfile];
        }
    }   
    push @{ $rpinfo->{ $prkey } }, @md;
    
    open (my $jso, '>',File::Spec->catfile($misdir, "misrp.json")) or die "\nUnable to open misrp.json";   
    my $jsstr = encode_json $rpinfo;
    print $jso Dumper $jsstr;
    close $jso;
    
}

var @exlist=();

sub parseLF4MIS {
#    my ($args) = @_;
 #   my @logfiles = @{ $args };

    foreach my $myfile (@logfiles) {
        if (-e $myfile) {
            
            my $servername='';
            my $serverstatus='';
            open (my $inn, '<', $myfile) or die "\nUnable to open '$myfile'";
            while (my $str = <$inn>) {
                chomp $str;
                # if this line is not found then the server may have not started or crased or killed before starting up
                if (index($str,"open for e-business") > -1) {
                    my $ssloc = index ($str,"Server ") + 7;
                    my $ssop =  index ($str,"open ");
                    $servername = substr($str, $ssloc, $ssop-$ssloc);
                    #Not necesserily running unless the process is checked on the server for the respective process ID
                    $serverstatus='RUNNING'; 
                } 
                if ((index($str,"WSVR0024I: Server") > -1) && (index($str,"stopped") > -1)) {
                    #note server name can be retreived from this line
                    $serverstatus='STOPPED';                    
                }
            }
            close $inn;            
            if ($servername eq '') {
                # possible state if the log is not having start-up/stopped messages
                # add lfservers here
                if (@logfiles or @zipfiles or @filesdirs) {
                    $servername=$lfservers;
                }
                if (@profiledirs) {
                   my $lfix = index($myfile,"logs")-1;
                   my $flen = length $myfile;
                   my $pp = substr($myfile,0,$flen-$lfix);
                   $lfix = index($pp,"/");
                   if ($lfix < 0) {
                       $lfix = rindex($pp,"\\");
                   }
                   $servername = substr($pp,$lfix+1,(length $pp)-$lfix);
                }
            }
=WILL USE LATER IF REQUIRED            
            my $logfile;
            my $li;
            if (index ($myfile,"/") > -1) {
                $li = rindex($myfile,"/");
            } else {
                $li = rindex($myfile,"\\");
            }
            $logfile = substr($myfile,$li+1);            
=cut
            my $prkey=$hostname."++".$servername."++".$myfile."++".$serverstatus;
            # check for pid and check if server is started.
            # This is possible only if we are having access to the installed profile directories
            # if we are analyszing the logs from a zip file or from a local directory, then we can only infer from the logs supplied
=TODO            
            if (@profiledirs) {
                $li = index($row,"logs")+4;               
                my $ld = substr($row,0,length($row) - $li);
                my $pid = File::Spec->catfile($ld, $servername.".pid");
                if ( -e $pid ) {
                    # pid file is existing, check if process is running - TODO
                    $serverstatus='RUNNING';
                }
            }
=cut

            # first sweep to collect the stack traces from log files      
            open (my $in, '<', $myfile) or die "\nUnable to open '$myfile'";
            my $stfnd=0;
            my @sttr = ();
            my @tmp = ();
            my $chkflg=0;            
            
            SWEEP:while (my $row = <$in>) {
                chomp $row;
                # found stack trace
                if ($stfnd==1) {
                    # check if timestamp, then set stfnd=0;
                    $row =~ s/^\s+|\s+$//g;
                    my $rowlen = length $row;
                    if (index($row,'[')==0 or ($rowlen == 0) ) {
                        $stfnd=0; #check further                
                        # check if it was a stack trace, else clear the array entry
                        if ($chkflg==1) {
                            @tmp = ();
                        } else {
                            foreach my $n (@tmp) {
                                my $isat=index($n,'at ');
                                my $isCausedBy=index($n,'Caused by: ');
                                if ( ($isat==0) or ($isCausedBy==0)  ) {
                                    #we are in the stack trace
                                    push @sttr, [ @tmp ];
                                    @tmp = ();
                                    last;
                                }
                            }
                        }
                    } else {
                        $chkflg=0;
                        push @tmp, $row;
                    }
                } elsif ( (index($row,' W  ') > 0) or (index($row,' E  ') > 0) ) {
                    my @tokens = split(/  /, $row);
                    my @strex = ();
                    if (index($tokens[1],':') > 0) {
                        @strex = split(/: /, $tokens[1]);
                    } elsif (($tokens[2]) and (index($tokens[2],':') > 0)) {
                        @strex = split(/: /, $tokens[2]);
                    }
                    
                    for (my $e=1;$e < scalar @strex; $e++) {
                        # should we add a log file for this or just add this to the list
                        $exlist[$e-1] = $strex[$e];
                        $exlist[$e-1] =~ s/^\s+|\s+$//g;
                    }
                                        
                    my $rstr = $strex[0];
                    if ($rstr) {
                        $rstr =~ s/^\s+|\s+$//g;
                        my $messageid = $rstr;
                        if ($messageid) {
                            my $len = length $messageid;
                            if ($len != 9) {
                                next SWEEP;
                            }
                            #Check for message ID with W and E only
                            if ($messageid =~ /^[A-Z]{4}[0-9]{4}[W|E]/) {
                                $stfnd=1;
                                #push the complete exception into store
                                push @tmp, $row;
                                $chkflg=1;
                            } else {
                                next SWEEP;
                            }
                        }
                    }
                }
            }
            # check if it was a stack trace, else clear the array entry
            if ($chkflg==1) {
                @tmp = ();
            } else {
                foreach my $n (@tmp) {
                    my $isat=index($n,'at ');
                    my $isCausedBy=index($n,'Caused by: ');
                    if ( ($isat==0) or ($isCausedBy==0)  ) {
                        #we are in the stack trace
                        push @sttr, [ @tmp ];
                        @tmp = ();
                        last;
                    }
                }
            }              
            genMIS(\@sttr, $prkey);                
        }
    }
}
=Stage1 

Alpha Release - Scheduled for Wednesday 26th April (maybe even before)
1. Browse through installation profiles and process the log files - DONE
2. Accept zip file from command line or from a directory - DONE
3. Accept log file(s) from command line or from a directory - DONE
4. Generates simple SVG files for the stack traces - DONE

--- Testing to be done here

5. Generates simple HTML with basic MIS report for the same

MIS Report
Refine Table
By IP 
By Hostname
By Server Instance
By Application Name
By Critical Errors
By Running
By Stopped


1. Host name
2. Instances
3. IP Address
4. Applications
5. Log Report

Search by 
1. View Log Files
2. View Errors
3. View Exceptions
4. 



6. Release comes as a zip file with a readme

Use node.js for local server with simple html form for 


Beeta Release (TO BE DISCUSSED AFTER ALPHA RELEASE) - May 10th
1. Process webserver files including plugin files
2. Access remote server installations and processes logs on remote servers, requires a simple light weight server process running.
3. Single Administration control panel
4. Can be run as a cronjob/windows job/service on any machine for automated 
5. Enhanced MIS reporting
6. Alerts for business audience where necessary
7. Configurable using Administration control panel
8. Comes as zip/gz 

Version 1 Release - Release Date to be based on features
#TODO
1. Security with SSL
2. API to profide JSON/XML version (HTTP/SOAP), if SOAP, we provide WSDL - Question - Is this necessary? we can discuss on this later after Alpha release.
3. More to be discussed.

[hostname#servername#logfile#status][0] = [{messageids,exception},{messageids,exception},{messageids,exception}...]
[hostname#servername#logfile#status][1] = [zipfile,logfile,profiledir,filedir]]

my @arr = [["messageid1","exception1","st1","svg1"],["messageid2","exception2","st2","svg2"],["messageid3","exception3","st3","svg3"]];
my @meta = ["zp","lf","pd","fd"];
my $invoices = {};
my $key="localhost#Server1#SystemOut.log#RUNNING";

push @{ $invoices->{$key} }, @arr;
push @{ $invoices->{$key} }, @meta;


What can be done as of now
1. Message ID A
2. Message Type A
3. Server name A
4. Status A


Each Log File will have a keyfile
zipfile= A
logfile= A
profiledir= A
filedir= A
hostname= 
servername= A
IP Address= 
Running= A
Starttime= A
stoppedtime= A
Applications installed=

messageids=mid1=svgfile##mid2=svgfile##mid3=svgfile##mid4=svgfile....
mid1=[stacktrace]
mid2=[stacktrace]
....
....
....

html file name = servername+hostname

=cut