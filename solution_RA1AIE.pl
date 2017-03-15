#!/usr/bin/perl 

# COPYRIGHT RA1AIE

use IO::Socket::Telnet;
use strict;
use Switch;
use WebSphere::MQTT::Client;
use DBI;
use POSIX qw(strftime);
use Time::Piece;
use Proc::Daemon;
use File::Pid;
use Email::Sender::Simple qw(sendmail);
use Email::Sender::Transport::SMTP ();
use Email::Simple ();
use Email::Simple::Creator ();

my $logfile="/var/log/clusterd.log";
open(my $log, '>', $logfile) or die "Can't access '$logfile' $!";
$log->autoflush(1);
        
my $pidfile = File::Pid->new({file => '/var/run/clusterd.pid',});
$pidfile->write;

my $continue = 1;
$SIG{TERM} = sub { $continue = 0 };

sub ParseSpot {
        my ($DX, $DB, $mqtt, $qos, $topic)=@_;
        my $now = strftime "%Y-%m-%d %H:%M:%S", localtime();
        
        my $sql = $DB->prepare("SELECT * FROM `paging_dxcluster`");
        my $result=$sql->execute;    
        my $ret=0;
             
        if ($result ne "0E0") {
              print $log "$now Received: '$DX', parsing...\n";
              my $spot=substr($DX,index($DX,":")+2);

              my $freq=substr($spot,0,index($spot, " "));
              my $freqmhz=sprintf("%.0f",$freq/1000);
              #print $log "Freq: $freq\n";
              $spot=substr($spot,index($spot, " ")+1);
              my $band;
              
              switch ($freqmhz) {
                  case 0 {$band="LF/MF";}
                  case [1..2] {$band="160m";}
                  case [3..4] {$band="80m";}
                  case 7 {$band="40m";}
                  case 10 {$band="30m";}
                  case 14 {$band="20m";}
                  case 18 {$band="17m";}
                  case 21 {$band="15m";}
                  case 28 {$band="10m";}
		  case 29 {$band="10m";}
                  case 50 {$band="6m";}
                  case 70 {$band="4m";}
                  case [144..146] {$band="2m";}
                  case [430..440] {$band="70cm";}
                  case 1296 {$band="23cm";}
                  else {$band="$freqmhz MHz: unknown band";}                       
              }

              my $call=substr($spot,0,index($spot, " "));
              #print $log "Call: $call\n";
              $spot=substr($spot,index($spot, " ")+1);

              my $dxcc=qx(/usr/bin/dxcc "$call");

              $dxcc=~ s/(^|\n)[\n\s]*/$1/g;
              $dxcc=~ s/\h+/ /g;
              my @lines = split /\n/, $dxcc;
              my $country=substr($lines[2],index($lines[2],":")+1);
              my $continent=substr($lines[5],index($lines[5],":")+1);

              #print $log "Country: $country\n";
              
              $now = strftime "%Y-%m-%d %H:%M:%S", localtime();
              print $log "$now Band: $band, continent:$continent\n";

              #my $comment=substr($spot,0,rindex($spot, " "));
              #my $time=substr($spot,rindex($spot, " "));
              #print $log "Comment: $comment\n";
              #print $log "Time: $time\n";
              my $dateformat = "%Y-%m-%d %H:%M:%S";
              
              while (my $ref = $sql->fetchrow_arrayref) {
                my $subcap=$$ref[0]; 
                my $subband=$$ref[1];
                my $subcont=$$ref[2];
                my $submode=$$ref[3];
                my $subexpire=Time::Piece->strptime($$ref[4],$dateformat);
                my $dxfilter=$$ref[5];
                my $commfilter=$$ref[6];
                
                my $now=strftime "%Y-%m-%d %H:%M:%S", localtime();
                $now=Time::Piece->strptime($now,,$dateformat);;
                my $diff = $subexpire - $now;
                $now = strftime "%Y-%m-%d %H:%M:%S", localtime();
                if ($diff lt 0) {
                    print $log "$now DX Cluster subscription for CAP $subcap has expired $subexpire, removing from database...\n";
                    my $delquery = $DB->prepare("DELETE from `paging_dxcluster` WHERE capcode = $subcap");
                    $delquery->execute; 
                    print $log "$now Subscription has been removed.";
                    SendMail($DB,$subcap);
                } else {
                      print $log "$now Active subscription for CAP $subcap - bands:$subband, continents:$subcont, modes:$submode, expiration: $subexpire.\n";
                      if ((index($subband, $band) != -1) and  (index($subcont, $continent) != -1)) { 
                          print $log "$now Spot match subscription for CAP $subcap, checking filters...\n";
                          my $dxmatch=0;
                          my $commmatch=0;
                          if ($dxfilter) {
                            if (index($call, $dxfilter) != -1) {
                              print $log "$now DX callsign $call match DX filter: '$dxfilter'!\n";
                              $dxmatch=1;
                            } else {
                              print $log "$now DX callsign $call doesn't match DX filter: '$dxfilter'.\n";
                              $dxmatch=0;                              
                            }
                          } else {
                            print $log "$now DX filter is blank.\n";
                            $dxmatch=1;
                          }

                          if ($commfilter) {
                            if (index($spot, $commfilter) != -1) {
                              print $log "$now Spot match comment filter: '$commfilter'!\n";
                              $commmatch=1;
                            } else {
                              print $log "$now Spot doesn't match comment filter: '$commfilter'.\n";
                              $commmatch=0;                              
                            }
                          } else {
                            print $log "$now Spot comment filter is blank.\n";
                            $commmatch=1;
                          }
                                                    
                          if (($dxmatch eq 1) and ($commmatch eq 1)) {
                              print $log "$now Spot match filters for CAP $subcap, sending...\n";
                              chomp($DX);
                              my $topic="Express/$subcap";
                              my $res = $mqtt->publish($DX, $topic, $qos);
                              if ($res) {
                                  print $log "Failed to publish: $res";
                                  $ret=1;
                              } else {print $log "Page sent to $subcap.\n";};
                          }  else {{print $log "$now Spot doesn't match filters, ignoring...\n";};}            
                      } else {
                          print $log "$now Spot doesn't match subscription for CAP $subcap, ignoring...\n"#:\nSpot band - $band, subscription bands -$subband,\nSpot continent - $continent, subscription continents -$subcont.\n";
                      }
                }
                
              }   
              print $log "\n";
        } #else {print $log "$now No subscriptions found, ignoring spot...\n";}
        return $ret;
}

sub ConnectMQTT {
      my $mqtt=new WebSphere::MQTT::Client(
        Hostname => 'express.dstar.su',
        Port => 1883,
        Debug => 0,
        Clientid => 'qthspb-server',
        keep_alive => 600,
      );
      my $res = $mqtt->connect();
      my $now = strftime "%Y-%m-%d %H:%M:%S", localtime();
      if ($res) {
        die "$now Failed to connect: $res\n" 
      } else {
        print $log "$now MQTT connected!\n";
      }
      return $mqtt;
}

sub ConnectCluster {
  my $socket = IO::Socket::Telnet->new(PeerAddr => '62.183.34.131');
  my $flag=1;
  while ($flag) {
    defined $socket->recv(my $saw, 4096) or die $!;
    if (index($saw, "Please enter your call") != -1) {$flag=0;}
  } 

  my $now = strftime "%Y-%m-%d %H:%M:%S", localtime();
  print $log "$now Port opened, sending callsign...\n";

  $socket->send("RA1AIE-10\n");
  my $flag=1;
  while ($flag) {
    defined $socket->recv(my $saw, 4096) or die $!;
    if (index($saw, "arc >") != -1) {$flag=0;}
  } 

  $now = strftime "%Y-%m-%d %H:%M:%S", localtime();
  print $log "$now Connect success!\n";
  return $socket;
}

sub SendMail {
      my $smtpserver = '127.0.0.1';
      my $smtpport = 25;
      
      my ($DB,$cap)=@_;
      my $sql = $DB->prepare("SELECT * FROM `qthbb_profile_fields_data` WHERE pf_capcode = $cap");
      my $result=$sql->execute;         
      my $ref = $sql->fetchrow_arrayref;
      my $userid=$$ref[0];
      
      if (!($userid)) {return 0;}
      
      $sql = $DB->prepare("SELECT user_email FROM qthbb_users WHERE user_id = $userid");
      $result=$sql->execute; 
      $ref = $sql->fetchrow_arrayref;
      
      my $email=$$ref[0];
      
      if (!($email)) {return 0;}
      
      my $transport = Email::Sender::Transport::SMTP->new({
        host => $smtpserver,
        port => $smtpport,
      });
      
      my $email = Email::Simple->create(
        header => [
          To      => $email,
          From    => 'www-data@qth.spb.ru',
          Subject => '[qth.spb.ru] »стечение срока действи¤ подписки на DX кластер',
        ],
        body => "—рок действи¤ подписки на пейджинговую рассылку DX кластера дл¤ пейджера $cap истек.\n",
      );

      sendmail($email, { transport => $transport });
      return 1;
}

my $now = strftime "%Y-%m-%d %H:%M:%S", localtime();

print $log "$now Connecting to database...\n";

my $host = "localhost";
my $port = "3306"; 
my $user = "dxcluster";
my $pass = "dxcluster"; 
my $database = "paging"; 

my $DB = DBI->connect("DBI:mysql:$database:$host:$port",$user,$pass);

my $now = strftime "%Y-%m-%d %H:%M:%S", localtime();

print $log "$now Connect success!\n";

print $log "$now Connecting to DX cluster...\n";
my $socket=ConnectCluster();

print $log "$now Connecting to MQTT...\n";

my $mqtt = ConnectMQTT();

$now = strftime "%Y-%m-%d %H:%M:%S", localtime();
print $log "$now Starting main loop...\n\n";

my $DX="";

while ($continue) {

  defined $socket->recv(my $saw, 4096) or die $!;
  
  $DX=$saw;
  $DX=~ s/\h+/ /g;
  $DX=~ s/[\r\n]//g;
  $DX= uc $DX;
  my $ret=ParseSpot($DX, $DB, $mqtt, 0);
  if ($ret) {
      $now = strftime "%Y-%m-%d %H:%M:%S", localtime();
      print $log "$now MQTT connection error, reconnecting...\n";
      $mqtt = ConnectMQTT();
  }
}
