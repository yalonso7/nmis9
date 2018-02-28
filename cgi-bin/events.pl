#!/usr/bin/perl
#
## $Id: events.pl,v 8.9 2012/10/02 03:38:06 keiths Exp $
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
# Auto configure to the <nmis-base>/lib
use FindBin;
use lib "$FindBin::Bin/../lib";

# 
use strict;
use Compat::NMIS;
use NMISNG::Sys;
use NMISNG::Util;

use Data::Dumper;
$Data::Dumper::Indent = 1;

use URI::Escape;

use CGI qw(:standard *table *Tr *td *form *Select *div);

my $q = new CGI; # This processes all parameters passed via GET and POST
my $Q = $q->Vars; # values in hash
my $C;

if (!($C = NMISNG::Util::loadConfTable(conf=>$Q->{conf},debug=>$Q->{debug}))) { exit 1; };

# Before going any further, check to see if we must handle
# an authentication login or logout request

# NMIS Authentication module
use NMISNG::Auth;

# variables used for the security mods
my $headeropts = {type=>'text/html',expires=>'now'};
my $AU = NMISNG::Auth->new(conf => $C);

if ($AU->Require) {
	exit 0 unless $AU->loginout(type=>$Q->{auth_type},username=>$Q->{auth_username},
					password=>$Q->{auth_password},headeropts=>$headeropts) ;
}

# $AU->CheckAccess, will send header and display message denying access if fails.
$AU->CheckAccess("tls_event_db","header");

# check for remote request
if ($Q->{server} ne "") { exit if Compat::NMIS::requestServer(headeropts=>$headeropts); }

# this cgi script defaults to widget mode ON
my $widget = NMISNG::Util::getbool($Q->{widget},"invert")? 'false' : 'true';
my $wantwidget = $widget eq 'true';
#======================================================================

# select function

if ($Q->{act} eq 'event_table_view') 
{	
	viewEvent();
} elsif ($Q->{act} eq 'event_table_list') 
{		
	listEvent();
} 
elsif ($Q->{act} eq 'event_table_update') 
{
	updateEvent(); listEvent();
} 
else 
{ 
	print header($headeropts);
	print "Tables: ERROR, act=$Q->{act}, node=$Q->{node}, intf=$Q->{intf}\n";
	print "Requested data not found!\n";
}

exit 1;

#==================================================================
#
#

sub viewEvent 
{
	my $node = $Q->{node};
	
	#start of page
	print header($headeropts);
	Compat::NMIS::pageStartJscript(title => "NMIS View Event $node",refresh => 86400) 
			if (!$wantwidget);

	my $S = NMISNG::Sys->new;
	$S->init(name=>$node,snmp=>'false');

	print Compat::NMIS::createHrButtons(node=>$node, system => $S, refresh=>$Q->{refresh},widget=>$widget, conf => $Q->{conf}, AU => $AU);

	print start_table;

	print start_Tr,start_td,start_table({class=>'table'});
	#print header
	print Tr( eval { my $line; my $colspan = 0;
			for my $item ( 'Node','Outage','Start','Event','Level','Element','Details','Escalate','State') {
				$line .= td({class=>'header',align=>'center'},$item);
				$colspan++;
			}
			return Tr(td({class=>'header',colspan=>$colspan},"Events of node $node")).$line;
		});

	# print data
	my %nodeevents = Compat::NMIS::loadAllEvents(node => $node);
	my $cnt = keys %nodeevents;
	for my $eventkey (NMISNG::Util::sorthash(\%nodeevents,['startdate'],'fwd')) 
	{
		my $thisevent = $nodeevents{$eventkey};

		my $state = NMISNG::Util::getbool($thisevent->{ack},"invert") ? 'active' : 'inactive';
		print Tr( eval { my $line;
										 $line .= td({class=>'info Plain'},
																 a({href=>"network.pl?conf=$Q->{conf}&act=network_node_view&widget=$widget&node=".uri_escape($node)},$node));
										 my $outage = NMISNG::Util::convertSecsHours(time() - $thisevent->{startdate});
										 $line .= td({class=>'info Plain'},$outage);
										 $line .= td({class=>'info Plain'}, NMISNG::Util::returnDateStamp($thisevent->{startdate}));
										 $line .= td({class=>'info Plain'}, $thisevent->{event});
										 $line .= td({class=>'info Plain'}, $thisevent->{level});
										 $line .= td({class=>'info Plain'}, $thisevent->{element});
										 $line .= td({class=>'info Plain'}, $thisevent->{details});
										 $line .= td({class=>'info Plain',align=>'center'}, $thisevent->{escalate});
										 $line .= td({class=>'info Plain',align=>'center'}, $state);
										 return $line;
							});
	}
	
	if (!$cnt) 
	{
		print Tr(td({class=>'info Plain',colspan=>'4'},"No events current for Node $node"));
	}
	print end_table,end_td,end_Tr;
	print end_table;
	Compat::NMIS::pageEnd() if (!$wantwidget);
}

###
sub listEvent 
{
	print header($headeropts);
	Compat::NMIS::pageStartJscript(title => "NMIS List Events") if (!$wantwidget);

	# verify access to this command/tool bar/button
	#
#	if ( $AU->Require ) {
#		# CheckAccess will throw up a web page and stop if access is not allowed
#		$AU>CheckAccess("eventcur") or die "Attempted unauthorized access";
#	}

	# start of form
	print start_form(-id=>"src_events_form",-href=>url(-absolute=>1)."?")
			.	hidden(-override => 1, -name => "conf", -value => $Q->{conf})
			. hidden(-override => 1, -name => "act", -value => "event_table_update")
			. hidden(-override => 1, -name => "widget", -value => $widget);

	print start_table;

	# fixme9: needs adjustment; remote events may be a/v in the db with opHA 3.
	my %localevents = Compat::NMIS::loadAllEvents;
	displayEvents(\%localevents, $C->{'server_name'}); #single server

	print end_table;
	print end_form;

	Compat::NMIS::pageEnd() if (!$wantwidget);

}

# this receives one of two flavours of event hash:
# new-style, eventfilename => event data, or old-style, eventhash => event data
sub displayEvents 
{
	my ($eventdata, $server) = @_;

	my $style;
	my $button;
	my $color;
	my $start;
	my $last;
	my $outage;
 	my $tempnode;
	my $nodehash;
	my $tempnodeack; 
	my %eventackcount;
	my %eventnoackcount;
	my %eventcount;
	my $cleanedSysLocation;
	my $node_cnt;

	my $node = $Q->{node};

	my $C = NMISNG::Util::loadConfTable();
	my $NT = Compat::NMIS::loadNodeTable();
	my $GT = Compat::NMIS::loadGroupTable();

	# header
	print Tr(th({class=>'title',colspan=>'10'},"$server Event List"));
       
	# only display the table if there are any events.
	if (not keys %{$eventdata}) {
		print Tr(td({class=>'info Plain'},"No Events Current"));
		return; # ready
	}

	# rip thru the table once and count all the events by node....helps heaps later.
	for my $eventkey ( keys %{$eventdata})  
	{
		my $thisevent = $eventdata->{$eventkey};
		
		if ( NMISNG::Util::getbool($thisevent->{ack}) ) 
		{
			++$eventackcount{$thisevent->{node}};
		}
		else 
		{
			++$eventnoackcount{$thisevent->{node}};
		}
		++$eventcount{$thisevent->{node}};
	}

	# always print the active event table header
	$tempnode='';
	$tempnodeack = '';
	my $display = '';
	my $tmpack = '';
	my $match = 'false';

	my $event_cnt = 0; # index for update routine Compat::NMIS::eventAck()

	for my $eventkey ( sort { $eventdata->{$a}{ack} cmp  $eventdata->{$b}{ack} 
														 or $eventdata->{$a}{node} cmp $eventdata->{$b}{node} 
														 or $eventdata->{$b}{startdate} cmp $eventdata->{$a}{startdate} 
														 or $eventdata->{$a}{escalate} cmp $eventdata->{$b}{escalate}
											} keys %{$eventdata})  
	{
		my $thisevent = $eventdata->{$eventkey};
		next if (!$thisevent->{node}); # should not ever be hit
		# check auth
		next unless $AU->InGroup($NT->{$thisevent->{node}}{group});

		# print all events

		# print header if ack changed
		if ($tempnodeack ne $thisevent->{ack}) {
			$tempnodeack = $thisevent->{ack};
			typeHeader();
		}

		if (!NMISNG::Util::getbool($tmpack,"invert") and NMISNG::Util::getbool($thisevent->{ack},"invert")) {
			$tmpack = 'false';
			print Tr(td({class=>'heading3',colspan=>'10'},"Active Events. (Set All Events Inactive",
						checkbox(-name=>'checkbox_name',-label=>'',-onClick=>"checkBoxes(this,'false$server')",-checked=>'',override=>'1'),
					")"));
		}

		if (!NMISNG::Util::getbool($tmpack) and NMISNG::Util::getbool($thisevent->{ack})) {
			$tmpack = 'true';
			$display ='none';
			$node_cnt = 0;
			print Tr(td({class=>'heading3',colspan=>'10'},"Inactive Events. (Set All Events Active ",
						checkbox(-name=>'checkbox_name',-label=>'',-onClick=>"checkBoxes(this,'true$server')",-checked=>'',override=>'1'),
					")"));
		}

		if ( $tempnode ne $thisevent->{node} ) {
			$tempnode = $thisevent->{node};
			$node_cnt = 0;

			active($server,$tempnode,$tempnodeack,\%eventnoackcount) 
					if (NMISNG::Util::getbool($thisevent->{ack},"invert"));
			inactive($server,$tempnode,$tempnodeack,\%eventackcount) 
					if (NMISNG::Util::getbool($thisevent->{ack}));

		}

		# now write the events, hidden or not hidden
		if ( NMISNG::Util::getbool($thisevent->{ack},"invert") ) {
			$color = NMISNG::Util::eventColor($thisevent->{level});
		}
		else {
			$color = "white";
		}
		$start = NMISNG::Util::returnDateStamp($thisevent->{startdate});
		$last = NMISNG::Util::returnDateStamp($thisevent->{lastchange});
		$outage = NMISNG::Util::convertSecsHours(time() - $thisevent->{startdate});
		# User logic, hmmmm how will users interpret this!
		if ( NMISNG::Util::getbool($thisevent->{ack},"invert") ) {
			$button = "true";
		}
		else {
			$button = "false";	
		}
		# print row , Tr with id for set hidden
		### 2012-10-02 keiths, changed color to be done by CSS
		print Tr({id=>"$thisevent->{ack}$tempnode$node_cnt",style=>"display:$display;"},
			td({class=>"info $thisevent->{level}"},
				eval {
					return $AU->CheckAccess("src_events","check")
						? a({href=>"logs.pl?&conf=$Q->{conf}&act=log_file_view&logname=Event_Log&search=$thisevent->{node}&sort=descending&widget=$widget"},$thisevent->{node})
							: "$thisevent->{node}";
					}),
			td({class=>"info $thisevent->{level}"},$outage),
			td({class=>"info $thisevent->{level}"},$start),
			td({class=>"info $thisevent->{level}"},$thisevent->{event}),
			td({class=>"info $thisevent->{level}"},$thisevent->{level}),
			td({class=>"info $thisevent->{level}"},$thisevent->{element}),
			td({class=>"info $thisevent->{level}"},$thisevent->{details}),
			td({class=>"info $thisevent->{level}",align=>'center'},
				checkbox(-name=>"$thisevent->{ack}$server$tempnode",-value=>"$event_cnt",-label=>'',override=>'1')),
			td({class=>"info $thisevent->{level}",align=>'right'},$thisevent->{escalate}),
			td({class=>"info $thisevent->{level}"},$thisevent->{user})
			);

		print hidden(-name=>"node",-default=>"$thisevent->{node}",override=>'1');
		print hidden(-name=>"event",-default=>"$thisevent->{event}",override=>'1');
		print hidden(-name=>"element",-default=>"$thisevent->{element}",override=>'1');
		print hidden(-name=>"ack",-default=>"$button",override=>'1');

		$event_cnt++;
		$node_cnt++;
	} # foreach $event_hash

	print Tr(td({class=>'info Plain',colspan=>'8',align=>'right'},
				button(-name=>'button',onclick=> ($wantwidget? "get('src_events_form');" : "submit()"),
							 -value=>"Submit Changes")),
					td({class=>'info Plain',colspan=>'2'}, '&nbsp'));
} # sub displayEvents

# java - ack=false event=active
sub active {
	my $server =shift;
	my $tempnode = shift;
	my $tempnodeack = shift;
	my $eventnoackcount = shift;
	print Tr(td({class=>'header'},
							a({href=>"network.pl?conf=$Q->{conf}&act=network_node_view&node=".uri_escape($tempnode)."&widget=$widget",onClick=>"ExpandCollapse(\"false$tempnode\"); return false;"},$tempnode)),
					 td({class=>'info Plain',colspan=>'9'},
							img({src=>"$C->{'<menu_url_base>'}/img/sumup.gif",id=>"false${tempnode}img",border=>'0'}),
							"&nbsp;$eventnoackcount->{$tempnode} Event(s)",
							"&nbsp;(Set Events Inactive for $tempnode ",
							checkbox(-name=>'checkbox_name',-label=>'',-onClick=>"checkBoxes(this,'$tempnodeack$server$tempnode')",-checked=>'',override=>'1'),
							")"));
} # sub active

# java - ack=true event=inactive
sub inactive {
	my $server =shift;
	my $tempnode = shift;
	my $tempnodeack = shift;
	my $eventackcount = shift;
	print Tr(td({class=>'header'},
							a({href=>"network.pl?conf=$Q->{conf}&act=network_node_view&node=".uri_escape($tempnode)."&widget=$widget",onClick=>"ExpandCollapse(\"true$tempnode\"); return false;"},$tempnode)),
					 td({class=>'info Plain',colspan=>'9'},
							img({src=>"$C->{'<menu_url_base>'}/img/sumdown.gif",id=>"true${tempnode}img",border=>'0'}),
							"&nbsp;$eventackcount->{$tempnode} Event(s)",
							"&nbsp;(Set Events Active for $tempnode ",
							checkbox(-name=>'checkbox_name',-label=>'',-onClick=>"checkBoxes(this,'$tempnodeack$server$tempnode')",-checked=>'',override=>'1'),
							")"));
} # sub inactive

sub typeHeader {
	print Tr(
		td({class=>'header',align=>'center'},'Name'),
		td({class=>'header',align=>'center'},'Outage'),
		td({class=>'header',align=>'center'},'Start'),
		td({class=>'header',align=>'center'},'Event'),
		td({class=>'header',align=>'center'},'Level'),
		td({class=>'header',align=>'center'},'Element'),
		td({class=>'header',align=>'center'},'Details'),
		td({class=>'header',align=>'center'},'Ack.'),
		td({class=>'header',align=>'center'},'Esc.'),
		td({class=>'header',align=>'center'},'User')
			);
}

# change ack for the matching events
sub updateEvent 
{
	my @par = $q->param(); # parameter names
	my @nm = $q->param('node'); # node names
	my @elmnt = $q->param('element'); # event details
	my @ack = $q->param('ack'); # event ack status
	my @evnt = $q->param('event'); # event type

	# the value of the checkbox is equal to the index of arrays
	my $i = 0;
	# the value of the checkbox is equal to the index of arrays
	for my $par (@par) 
	{
		if ($par =~ /false|true/) 
		{ 		# false|true is part of the checkbox name
			my @a = $q->param($par);		# get the values (numbers) of the checkboxes
			foreach my $i (@a) 
			{
				# check for change of event
				if ($i ne "" and ((NMISNG::Util::getbool($ack[$i]) and $par =~ /false/) 
													or (NMISNG::Util::getbool($ack[$i],"invert") and $par =~ /true/))) 
				{
					# event changes
					Compat::NMIS::eventAck( ack=>$ack[$i], 
										node=>$nm[$i],
										event=>$evnt[$i],
										element=>$elmnt[$i],
										user=>$AU->User() );
				}
			}
		}
	}
}
