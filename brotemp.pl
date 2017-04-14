#!/usr/bin/perl
use warnings;
use strict;
use Data::Dumper;
use Net::SNMP;

use constant UNITSERIAL_OID   => '1.3.6.1.4.1.1991.1.1.1.4.1.1.2';
use constant ACTUALTEMP_OID   => '1.3.6.1.4.1.1991.1.1.1.4.1.1.4';
use constant WARNINGTEMP_OID  => '1.3.6.1.4.1.1991.1.1.1.4.1.1.5';
use constant SHUTDOWNTEMP_OID => '1.3.6.1.4.1.1991.1.1.1.4.1.1.6';

use constant SNMPPORT => 161;

my ($host, $community) = @ARGV;

my $return = 3;
my $msg = "UNKNOWN: There is a problem with the check script.";
my $info = "Yep, the check is definitely broken.";

# snChasUnitActualTemperature and friends per page 155 of
# https://www.brocade.com/content/dam/common/documents/content-types/mib-reference-guide/ipmib-may2015-reference.pdf

my $snmp_serials = snmp_unitSerial();
my $snmp_actualTemps = snmp_actualTemp();
my $snmp_warningTemps = snmp_warningTemp();
my $snmp_shutdownTemps = snmp_shutdownTemp();

my @badtemp;

my %stackunits;

# Build everything into a hash
while(my($oid, $value) = each(%$snmp_serials))
{
	my @splitoid = split('\.',$oid);
	$stackunits{$splitoid[-1]}{'serial'} = $value;
}

while(my($oid, $value) = each(%$snmp_warningTemps))
{
	my @splitoid = split('\.',$oid);
	$stackunits{$splitoid[-1]}{'warningtemp'} = $value;
}

while(my($oid, $value) = each(%$snmp_shutdownTemps))
{
	my @splitoid = split('\.',$oid);
	$stackunits{$splitoid[-1]}{'shutdowntemp'} = $value;
}

while(my($oid, $value) = each(%$snmp_actualTemps))
{
	my @splitoid = split('\.',$oid);
	$stackunits{$splitoid[-1]}{'actualtemp'} = $value;
}

# Iterate the hash looking for anomalies
while(my($unitnum, $member_ref) = each(%stackunits))
{
	# Check actual temp against warning and shutdown temp here
	my %member = %{$member_ref};

	my $serial = $member{'serial'};
	my $actualtemp = $member{'actualtemp'};
	my $warningtemp = $member{'warningtemp'};
	my $shutdowntemp = $member{'shutdowntemp'};

	if($actualtemp > $shutdowntemp)
	{
		# A unit past shutdown temperature is always critical.
		$return = 2;
		push(@badtemp, "Unit $unitnum ($serial) has exceeded shutdown temperature: $actualtemp > $shutdowntemp");
	}
	elsif($actualtemp > $warningtemp)
	{
		# Don't override critical to set warning
		if($return != 2) { $return = 1; }
		push(@badtemp, "Unit $unitnum ($serial) has exceeded warning temperature: $actualtemp > $warningtemp");
	}
}

if($return == 2)
{
	$msg = "CRITICAL: One or more stack members have exceeded shutdown temperature.";
}
elsif($return == 1)
{
	$msg = "WARNING: One or more stack members have exceeded warning temperature.";
}
else
{
	$msg = "OK: Temperatures within acceptable range.";
	$return = 0;
}

$info = join("\n",@badtemp);
chomp($info);
print("$msg\n$info");
exit($return);

sub snmp_unitSerial    { return walk($host, $community, SNMPPORT, UNITSERIAL_OID); }
sub snmp_actualTemp    { return walk($host, $community, SNMPPORT, ACTUALTEMP_OID);   }
sub snmp_warningTemp   { return walk($host, $community, SNMPPORT, WARNINGTEMP_OID);   }
sub snmp_shutdownTemp  { return walk($host, $community, SNMPPORT, SHUTDOWNTEMP_OID);   }

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
