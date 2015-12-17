#
#  Copyright (C) Opmantek Limited (www.opmantek.com)
#  
#  ALL CODE MODIFICATIONS MUST BE SENT TO CODE@OPMANTEK.COM
#  
#  This file is part of Network Management Information System (“NMIS”).
#  
#  NMIS is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#  
#  NMIS is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#  
#  You should have received a copy of the GNU General Public License
#  along with NMIS (most likely in a file named LICENSE).  
#  If not, see <http://www.gnu.org/licenses/>
#  
#  For further information on NMIS or for a license other than GPL please see
#  www.opmantek.com or email contact@opmantek.com 
#  
#  User group details:
#  http://support.opmantek.com/users/
#  
# *****************************************************************************

package Notify::opmonitor;

require 5;

use strict;

use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION);

use Exporter;
use Data::Dumper;
use File::Path;

$VERSION = 1.00;

@ISA = qw(Exporter);

@EXPORT = qw(
	sendNotification
	);

@EXPORT_OK = qw(	);

my $omklog = "/usr/local/nmis8/logs/opmonitor.log";

my $debug = 1;

sub sendNotification {
	my %arg = @_;
	my $contact = $arg{contact};
	my $event = $arg{event};
	my $message = $arg{message};
			
	# Sample Contact
	#$contact = {
	#  'Contact' => 'keiths',
	#  'DutyTime' => '06:24:MonTueWedThuFri',
	#  'Email' => 'keiths@opmantek.com',
	#  'Location' => 'default',
	#  'Mobile' => '0433355840',
	#  'Pager' => '',
	#  'Phone' => '',
	#  'TimeZone' => 0
	#};
	
	# Sample Event
	#$event = {
	#  'ack' => 'false',
	#  'businessPriority' => undef,
	#  'businessService' => undef,
	#  'cmdbType' => undef,
	#  'current' => 'true',
	#  'customer' => 'PACK',
	#  'details' => 'SNMP error',
	#  'element' => '',
	#  'email' => 'keiths@opmantek.com',
	#  'escalate' => 0,
	#  'event' => 'SNMP Down',
	#  'geocode' => 'St Louis Misouri',
	#  'level' => 'Warning',
	#  'location' => 'Cloud',
	#  'mobile' => '0433355840',
	#  'nmis_server' => 'nmisdev64',
	#  'node' => 'branch1',
	#  'notify' => 'syslog:server,json:server,mylog:keiths,mylog:keith2',
	#  'serviceStatus' => 'Dev-Test',
	#  'startdate' => 1366603124,
	#  'statusPriority' => '3',
	#  'supportGroup' => undef,
	#  'time' => 1366603126,
	#  'uuid' => '59A29034-8D41-11E2-A990-F38D7588D2EB'
	#};
	
	# is this critical.
	if ( $event->{level} =~ /./ ) {
	#if ( $event->{level} =~ /Major|Critical|Fatal/ ) {
		my $date = dateString($event->{time});
		
		my $state = "";
		my $stateful = "";
		if ( $event->{event} =~ /^(\w+) (Up|Down)/ ) {	
			$stateful = $1;
			$state = lc($2);
		}
		elsif ( $event->{event} =~ /(Proactive .+) Closed/ ) {	
			$stateful = $1;
			$state = "closed";
		}
		elsif ( $event->{event} =~ /(Proactive .+)/ ) {	
			$stateful = $1;
			$state = "open";
		}
		elsif ( $event->{event} =~ /(Alert: .+) Closed/ ) {	
			$stateful = $1;
			$state = "closed";
		}
		elsif ( $event->{event} =~ /(Alert: .+)/ ) {	
			$stateful = $1;
			$state = "open";
		}	
		
		my $exec = qq|/usr/local/omk/bin/create_remote_event.pl -s https://var.opmantek.com/omk -u hearst -p "TheAP1isG00d\#\#" authority=het001stropk001 location="http://het001stropk001.companynet.org/cgi-nmis8/network.pl?conf=Config.nmis&act=network_node_view&refresh=180&widget=false&node=$event->{node}" node=$event->{node} host=$event->{node} event="$event->{event}" details="$event->{details}" time=$event->{time} element="$event->{element}" level="$event->{level}" state="$state" stateful="$stateful" tag_source="nmis"|;
		
		my $out = `$exec 2>&1`;

		my $msgstr = "$event->{node} $event->{level} $event->{event} $event->{element} $event->{details}";
		
		my $error = 0;
		if ( $out =~ /Bad Request/ ) {
			$error = 1;
		}
	
		open(LOG,">>$omklog") or logMsg("ERROR, can not write to $omklog");
		print LOG qq|$date $msgstr $out|;
		print LOG qq|DEBUG: $exec\n| if $debug or $error;
		print LOG qq|DEBUG: $out\n| if $debug or $error;
		close LOG;
		# good to set permissions on file.....
	}
}


#Function which returns the time
sub dateString {
	my $time = shift;
	if ( $time == 0 ) { $time = time; }
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($time);
	if ($year > 70) { $year=$year+1900; }
	        else { $year=$year+2000; }
	if ($hour<10) {$hour = "0$hour";}
	if ($min<10) {$min = "0$min";}
	if ($sec<10) {$sec = "0$sec";}
	# Do some sums to calculate the time date etc 2 days ago
	$wday=('Sun','Mon','Tue','Wed','Thu','Fri','Sat')[$wday];
	$mon=('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec')[$mon];
	return "$mday-$mon-$year $hour:$min:$sec";
}

1;
