#!/usr/bin/perl
use warnings;
use strict;
use Data::Dumper;
use Net::SNMP;

use constant STACKENABLED_OID => '1.3.6.1.4.1.1991.1.1.3.31.1.1.0';
use constant UNITPRIORITY_OID => '1.3.6.1.4.1.1991.1.1.3.31.2.1.1.2';
use constant UNITTYPE_OID     => '1.3.6.1.4.1.1991.1.1.3.31.2.1.1.5';
use constant UNITSTATE_OID    => '1.3.6.1.4.1.1991.1.1.3.31.2.1.1.6';
use constant SWIMG_OID        => '1.3.6.1.4.1.1991.1.1.3.31.2.2.1.13';
use constant SWBUILD_OID      => '1.3.6.1.4.1.1991.1.1.3.31.2.2.1.14';

use constant STACKOID => '1.3.6.1.4.1.1991.1.1.3.31.2.2.1.5';
use constant SNMPPORT => 161;

my ($host, $community) = @ARGV;

my $return = 3;
my $msg = "UNKNOWN: There is a problem with the check script.";
my $info = "";

# snStackingConfigUnitState per
# https://www.brocade.com/content/dam/common/documents/content-types/mib-reference-guide/ipmib-may2015-reference.pdf
my %unitstates = (1 => 'local', 2 => 'remote', 3 => 'reserved', 4 => 'empty');

my %stack;
my $unitPriority = unitPriority();
my $unitType = unitType();
my $unitState = unitState();
my $swImage = swImage();
my $swBuild = swBuild();

my @badstate = ();
my @badversion = ();

while(my($oid, $value) = each(%$unitPriority)) {  $stack{(split('\.',$oid))[-1]}{'priority'} = $value;  }
while(my($oid, $value) = each(%$unitType))     {  $stack{(split('\.',$oid))[-1]}{'type'} = $value;  }
while(my($oid, $value) = each(%$unitState))    {  $stack{(split('\.',$oid))[-1]}{'state'} = $value;  }
while(my($oid, $value) = each(%$swImage))      {  $stack{(split('\.',$oid))[-1]}{'image'} = $value;  }
while(my($oid, $value) = each(%$swBuild))      {  $stack{(split('\.',$oid))[-1]}{'build'} = $value;  }

foreach my $swid (sort(keys(%stack)))
{
	my $sw = $stack{$swid};
	my $img = '(Unknown)';

	if($sw->{'image'})
	{
		$img = $sw->{'image'};
	}
	else
	{
		push(@badversion, $swid);
	}

	$info .= sprintf("Member %s is a %s in state %s running FastIron %s with stack priority %s\n",$swid, $sw->{'type'}, $unitstates{$sw->{'state'}}, $img, $sw->{'priority'});

	if($sw->{'state'} > 2)
	{
		push(@badstate, $swid);
	}
}

chomp($info);


if(scalar(@badstate) > 0)
{
	printf("CRITICAL: Stack member(s) %s is/are in an undesirable state.\n", join(', ',@badstate));
	$return = 2;
}
else
{
	if(scalar(@badversion) > 0)
	{
		printf("WARNING: Unable to determine image version for stack member(s) %s\n", join(', ',@badversion));
		$return = 1;
	}
	else
	{
		print "OK: Stack is OK\n";
		$return = 0;
	}
}

print("$info\n");
exit($return);

sub swBuild      { return walk($host, $community, SNMPPORT, SWBUILD_OID);      }
sub swImage      { return walk($host, $community, SNMPPORT, SWIMG_OID);        }
sub unitState    { return walk($host, $community, SNMPPORT, UNITSTATE_OID);    }
sub unitType     { return walk($host, $community, SNMPPORT, UNITTYPE_OID);     }
sub unitPriority { return walk($host, $community, SNMPPORT, UNITPRIORITY_OID); }
sub stackEnabled { return walk($host, $community, SNMPPORT, STACKENABLED_OID); }

sub walk
{
        my $host = shift;
        my $community = shift;
        my $port = shift;
        my $oid = shift;

        my ($session, $error) = Net::SNMP->session(Hostname => $host,
                                                   Community => $community,
                                                   port => $port,
                                                   timeout => 5) or die "Session: $!";

        my %out = ();

        my $lastOid = $oid;

        while($lastOid =~ /^$oid/)
        {
                my @oids = ($lastOid);
                my %res = ();
                my $getnext_res = $session->get_next_request(-varbindlist => \@oids);
                if($getnext_res)
                {
                        %res = %{$getnext_res};
                        my @returnedOids = keys(%res);

                        $lastOid = $returnedOids[0];
                        if($lastOid =~ /^$oid/)
                        {
                                $out{$lastOid} = $res{$lastOid};
                        }
                }
                else
                {
                        last;
                }
        }

        $session->close();

        return \%out;
}
