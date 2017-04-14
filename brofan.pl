#!/usr/bin/perl
use warnings;
use strict;
use Data::Dumper;
use Net::SNMP;

use constant FANSTATUS_OID => '1.3.6.1.4.1.1991.1.1.1.3.2.1.4';
use constant FANDESC_OID   => '1.3.6.1.4.1.1991.1.1.1.3.2.1.3';
use constant SNMPPORT => 161;

my ($host, $community) = @ARGV;

my $return = 3;
my $msg = "UNKNOWN: There is a problem with the check script.";
my $info = "";

# snChasFan2OperStatus per page 154 of
# https://www.brocade.com/content/dam/common/documents/content-types/mib-reference-guide/ipmib-may2015-reference.pdf
my %fanstates_enum = (1 => 'other', 2 => 'normal', 3 => 'FAILED');

my %fanname;
my $fannames   = snmp_fanNames();
my $statusdata = snmp_fanStatus();

my @badfan;

while(my($oid, $value) = each(%$fannames))
{
	# Last value in the OID will be the fan unit number
	# Next-to-last value in the OID will be the stack-unit number
	my @splitoid = split('\.',$oid);
	$fanname{$splitoid[-2]}{$splitoid[-1]} = $value;
}

while(my($oid, $value) = each(%$statusdata))
{
	# Last value in the OID will be the fan unit number
	# Next-to-last value in the OID will be the stack-unit number
	my @splitoid = split('\.',$oid);
	my $stackunit = $splitoid[-2];
	my $fannum = $splitoid[-1];
	my $fan_name = $fanname{$stackunit}{$fannum};
	my $fan_statustext = $fanstates_enum{$value};

	if($value != 2)
	{
		push(@badfan,"Unit $stackunit $fan_name is $fan_statustext");
		$return = 1;
	}
}

if($return == 1)
{
	$msg = "WARNING: One or more fans are not functioning properly.";
	$info = join("\n",@badfan);
}
else
{
	$msg = "OK: All fans normal";
	$return = 0;
}

chomp($info);
print("$msg\n$info");
exit($return);

sub snmp_fanStatus { return walk($host, $community, SNMPPORT, FANSTATUS_OID); }
sub snmp_fanNames  { return walk($host, $community, SNMPPORT, FANDESC_OID);   }

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
