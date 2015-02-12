#
#  Copyright Opmantek Limited (www.opmantek.com)
#  
#  ALL CODE MODIFICATIONS MUST BE SENT TO CODE@OPMANTEK.COM
#  
#  This file is part of Network Management Information System ("NMIS").
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
#
# To make sense of Cisco VLAN Bridge information.

package ciscoVlan;
our $VERSION = "1.0.0";

use strict;

use func;												# for the conf table extras
use NMIS;
use Data::Dumper;

use Net::SNMP;									# for the fixme removable local snmp session stuff

sub update_plugin
{
	my (%args) = @_;
	my ($node,$S,$C) = @args{qw(node sys config)};

	my $LNT = loadLocalNodeTable();
	
	my $NI = $S->ndinfo;
	my $IF = $S->ifinfo;
	# anything to do?

	my $status = {
		'1' => 'other',
		'2' => 'invalid',
		'3' => 'learned',
		'4' => 'self',
		'5' => 'mgmt',
	};

	return (0,undef) if (ref($NI->{vtpVlan}) ne "HASH");
	
	#dot1dBase
	#vtpVlan
	
	info("Working on $node vtpVlan");

	my $changesweremade = 0;

	for my $key (keys %{$NI->{vtpVlan}})
	{
		my $entry = $NI->{vtpVlan}->{$key};
	
		# get the VLAN ID Number from the index
		if ( my @parts = split(/\./,$entry->{index}) ) {
			shift(@parts); # dummy
			$entry->{vtpVlanIndex} = shift(@parts);
			$changesweremade = 1;
		}
				
		# Get the devices ifDescr and give it a link.
		my $ifIndex = $entry->{vtpVlanIfIndex};				
		if ( defined $IF->{$ifIndex}{ifDescr} ) {
			$changesweremade = 1;
			$entry->{ifDescr} = $IF->{$ifIndex}{ifDescr};
			$entry->{ifDescr_url} = "/cgi-nmis8/network.pl?conf=$C->{conf}&act=network_interface_view&intf=$ifIndex&node=$node";
			$entry->{ifDescr_id} = "node_view_$node";
		}
		
		# Get the connected devices if the VLAN is operational
		if ( $entry->{vtpVlanState} eq "operational" ) {
			#The community string is 
			my $community = "$LNT->{$node}{community}\@$entry->{vtpVlanIndex}";
			my $session = mysnmpsession( $LNT->{$node}{host}, $community, $LNT->{$node}{version}, $LNT->{$node}{port}, $C);
			
			my $addresses;
			my $ports;
			my $addressStatus;

			my $gotAddresses = 0;
			my $dot1dTpFdbAddress = "1.3.6.1.2.1.17.4.3.1.1"; #dot1dTpFdbAddress
			if ( $addresses = mygettable($session,$dot1dTpFdbAddress) ) {
				$gotAddresses = 1;
			}

			my $gotPorts = 0;
			my $dot1dTpFdbPort = "1.3.6.1.2.1.17.4.3.1.2"; #dot1dTpFdbPort
			if ( $ports = mygettable($session,$dot1dTpFdbPort) ) {
				$gotPorts = 1;
			}
			
			my $gotStatus = 1;
			my $dot1dTpFdbStatus = "1.3.6.1.2.1.17.4.3.1.3"; #dot1dTpFdbStatus
			if ( $addressStatus = mygettable($session,$dot1dTpFdbStatus) ) {
				$gotStatus = 1;
			}
			
			if ( $gotAddresses and $gotPorts ) {
				$changesweremade = 1;
				#print Dumper $addresses;
				
				#print Dumper $ports;

				#print Dumper $addressStatus;
				
				foreach my $key (keys %$addresses) {
					my $macAddress = $addresses->{$key};
					
					# got to use a different OID for the different queries.
					my $portKey = $key;
					my $statusKey = $key;
					$portKey =~ s/17.4.3.1.1/17.4.3.1.2/;
					$statusKey =~ s/17.4.3.1.1/17.4.3.1.3/;

					$NI->{dot1dMacTable}->{$macAddress}{dot1dTpFdbAddress} = $macAddress;
					$NI->{dot1dMacTable}->{$macAddress}{dot1dTpFdbPort} = $ports->{$portKey};
					$NI->{dot1dMacTable}->{$macAddress}{dot1dTpFdbStatus} = $status->{$addressStatus->{$statusKey}};
					$NI->{dot1dMacTable}->{$macAddress}{vlan} = $entry->{vtpVlanIndex};
					
					my $addressIfIndex = $NI->{dot1dBase}->{$ports->{$portKey}}{dot1dBasePortIfIndex};
					
					$NI->{dot1dMacTable}->{$macAddress}{ifDescr} = $IF->{$addressIfIndex}{ifDescr};
					#dot1dTpFdbAddress
					#dot1dTpFdbPort
					#dot1dTpFdbStatus
					#vlan
					#status					
					
				}
			}			
		}

	}
	return ($changesweremade,undef); # report if we changed anything
}

sub collect_plugin_monkey
{
	my (%args) = @_;
	my ($node,$S,$C) = @args{qw(node sys config)};

	my $NI = $S->ndinfo;
	my $changesweremade = 0;
	
	my $connState = {
		'1' => 'closed',
		'2' => 'listen',
		'3' => 'synSent',
		'4' => 'synReceived',
		'5' => 'established',
		'6' => 'finWait1',
		'7' => 'finWait2',
		'8' => 'closeWait',
		'9' => 'lastAck',
		'10' => 'closing',
		'11' => 'timeWait',
		'12' => 'deleteTCB'
	};

	my $addressType = {
		'0' => 'unknown',
		'1' => 'ipv4',
		'2' => 'ipv6',
		'3' => 'ipv4z',
		'4' => 'ipv6z',
		'16' => 'dns',
	};

	if (ref($NI->{tcpConn}) eq "HASH" or ref($NI->{tcpConnection}) eq "HASH") {
		
		if (ref($NI->{tcpConn}) eq "HASH" and $NI->{system}{nodedown} ne "true") {
			
			my $NC = $S->ndcfg;
			my $LNT = loadLocalNodeTable();
			
			dbg("SNMP tcpConnState for $node $LNT->{$node}{version}");
		
			my $session = mysnmpsession( $LNT->{$node}{host}, $LNT->{$node}{community}, $LNT->{$node}{version}, $LNT->{$node}{port}, $C);
			if (!$session)
			{
				return (2,"Could not open SNMP session to node $node");
			}           
		
			#tcpConnLocalAddress 
			#tcpConnLocalPort    
			#tcpConnRemAddress   
		  #tcpConnRemPort
		
		  #tcpConnState
	
	    #"192.168.1.42.3306.192.168.1.7.47883" : {
	    #   "tcpConnLocalAddress" : "192.168.1.42",
	    #   "tcpConnRemPort" : 47883,
	    #   "index" : "192.168.1.42.3306.192.168.1.7.47883",
	    #   "tcpConnLocalPort" : 3306,
	    #   "tcpConnState" : "established",
	    #   "tcpConnRemAddress" : "192.168.1.7"
	    #},
		
			my $oid = "1.3.6.1.2.1.6.13.1.1";
			
			if ( my $tcpConn = mygettable($session,$oid) ) {
			
				### OK we have data, lets get rid of the old one.
				delete $NI->{tcpConn};
				
				my $date = returnDateStamp();
				foreach my $key (keys %$tcpConn) {
					my $tcpKey = $key;
					$tcpKey =~ s/$oid\.//;
					$NI->{tcpConn}->{$tcpKey}{tcpConnState} = $connState->{$tcpConn->{$key}};
					if ( $tcpKey =~ /(\d+\.\d+\.\d+\.\d+)\.(\d+)\.(\d+\.\d+\.\d+\.\d+)\.(\d+)/ ) {
						$NI->{tcpConn}->{$tcpKey}{tcpConnLocalAddress} = $1;
						$NI->{tcpConn}->{$tcpKey}{tcpConnLocalPort} = $2;
						$NI->{tcpConn}->{$tcpKey}{tcpConnRemAddress} = $3;
						$NI->{tcpConn}->{$tcpKey}{tcpConnRemPort} = $4;
						$NI->{tcpConn}->{$tcpKey}{date} = $date;
					}	
					$changesweremade = 1;
				}
			}
		}
		
		if (ref($NI->{tcpConnection}) eq "HASH" and $NI->{system}{nodedown} ne "true") {
			my $NC = $S->ndcfg;
			my $LNT = loadLocalNodeTable();
			
			dbg("SNMP tcpConnState for $node $LNT->{$node}{version}");
		
			my $session = mysnmpsession( $LNT->{$node}{host}, $LNT->{$node}{community}, $LNT->{$node}{version}, $LNT->{$node}{port}, $C);
			if (!$session)
			{
				return (2,"Could not open SNMP session to node $node");
			}       
			
	    #  "1.4.192.168.1.42.3306.1.4.192.168.1.7.47883" : {
	    #     "tcpConnectionState" : "established",
	    #     "index" : "1.4.192.168.1.42.3306.1.4.192.168.1.7.47883"
	    #  },
      #"2.16.0.0.0.0.0.0.0.0.0.0.255.255.192.168.1.7.80.2.16.0.0.0.0.0.0.0.0.0.0.255.255.192.168.1.7.34089" : {
      #   "tcpConnectionState" : "timeWait",
      #   "index" : "2.16.0.0.0.0.0.0.0.0.0.0.255.255.192.168.1.7.80.2.16.0.0.0.0.0.0.0.0.0.0.255.255.192.168.1.7.34089"
      #},
			    
			my $oid = "1.3.6.1.2.1.6.19.1.7";
			
			if ( my $tcpConn = mygettable($session,$oid) ) {
			
				### OK we have data, lets get rid of the old one.
				delete $NI->{tcpConnection};
				
				my $date = returnDateStamp();
				foreach my $key (keys %$tcpConn) {
					my $tcpKey = $key;
					$tcpKey =~ s/$oid\.//;
					$NI->{tcpConnection}->{$tcpKey}{tcpConnectionState} = $connState->{$tcpConn->{$key}};
					if ( $tcpKey =~ /1\.4\.(\d+\.\d+\.\d+\.\d+)\.(\d+)\.1\.4\.(\d+\.\d+\.\d+\.\d+)\.(\d+)$/ ) {
						$NI->{tcpConnection}->{$tcpKey}{tcpConnectionLocalAddress} = $1;
						$NI->{tcpConnection}->{$tcpKey}{tcpConnectionLocalPort} = $2;
						$NI->{tcpConnection}->{$tcpKey}{tcpConnectionRemAddress} = $3;
						$NI->{tcpConnection}->{$tcpKey}{tcpConnectionRemPort} = $4;
						$NI->{tcpConnection}->{$tcpKey}{date} = $date;
					}	
					elsif ( $tcpKey =~ /2\.16\.([\d+\.]+)\.(\d+)\.2\.16\.([\d+\.]+)\.(\d+)$/ ) {
						$NI->{tcpConnection}->{$tcpKey}{tcpConnectionLocalAddress} = $1;
						$NI->{tcpConnection}->{$tcpKey}{tcpConnectionLocalPort} = $2;
						$NI->{tcpConnection}->{$tcpKey}{tcpConnectionRemAddress} = $3;
						$NI->{tcpConnection}->{$tcpKey}{tcpConnectionRemPort} = $4;
						$NI->{tcpConnection}->{$tcpKey}{date} = $date;
					}	
					$changesweremade = 1;
				}
			}
		
		}
	}
	else {	
		return (0,undef) ;
	}	
	return ($changesweremade,undef); # report if we changed anything
}

sub mysnmpsession {
	my $node = shift;
	my $community = shift;
	my $version = shift;
	my $port = shift;
	my $C = shift;

	my ($session, $error) = Net::SNMP->session(                   
		-hostname => $node,                  
		-community => $community,                
		-version	=> $version,
		-timeout  => $C->{snmp_timeout},                  
		-port => $port
	);  

	if (!defined($session)) {       
		logMsg("ERROR ($node) SNMP Session Error: $error");
		$session = undef;
	}
	
	if ( $session ) {
		# lets test the session!
		my $oid = "1.3.6.1.2.1.1.2.0";	
		my $result = mysnmpget($session,$oid);
		if ( $result->{$oid} =~ /^SNMP ERROR/ ) {	
			logMsg("ERROR ($node) SNMP Session Error, bad host or community wrong");
			$session = undef;
		}
	}	
	return $session; 
}

sub mysnmpget {
	my $session = shift;
	my $oid = shift;
	
	my %pdesc;
		
	my $response = $session->get_request($oid); 
	if ( defined $response ) {
		%pdesc = %{$response};  
		my $err = $session->error; 
		
		if ($err){
			$pdesc{$oid} = "SNMP ERROR"; 
		} 
	}
	else {
		$pdesc{$oid} = "SNMP ERROR: empty value $oid"; 
	}

	return \%pdesc;
}

sub mygettable {                                                                                         
	my $session = shift;
	my $oid = shift;

	my $result = $session->get_table( -baseoid => $oid );                                         
                                                                                                       
	my $cnt = scalar keys %{$result};                                                                    
	dbg("result: $cnt values for table $oid",1);                                                        
	return $result;                                                                                      
}                                                                                                      

1;