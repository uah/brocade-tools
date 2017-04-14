#!/usr/bin/perl
use warnings;
use strict;
use Data::Dumper;
use Net::SNMP;

use constant PSUSTATUS_OID => '1.3.6.1.4.1.1991.1.1.1.2.2.1.4';
use constant PSUDESC_OID   => '1.3.6.1.4.1.1991.1.1.1.2.2.1.3';
use constant SNMPPORT => 161;

my ($host, $community) = @ARGV;

my $return = 3;
my $msg = "UNKNOWN: There is a problem with the check script.";
my $info = "";

# snChasPwrSupply2OperStatus per page 153 of
# https://www.brocade.com/content/dam/common/documents/content-types/mib-reference-guide/ipmib-may2015-reference.pdf
my %psustates_enum = (1 => 'other', 2 => 'normal', 3 => 'FAILED');

my %psuname;
my $psunames   = snmp_psuNames();
my $statusdata = snmp_psuStatus();

my @badpsu;

while(my($oid, $value) = each(%$psunames))
{
	# Last value in the OID will be the power supply number
	# Next-to-last value in the OID will be the stack-unit number
	my @splitoid = split('\.',$oid);
	$psuname{$splitoid[-2]}{$splitoid[-1]} = $value;
}

while(my($oid, $value) = each(%$statusdata))
{
	# Last value in the OID will be the power supply number
	# Next-to-last value in the OID will be the stack-unit number
	my @splitoid = split('\.',$oid);
	my $stackunit = $splitoid[-2];
	my $psunum = $splitoid[-1];
	my $psu_name = $psuname{$stackunit}{$psunum};
	my $psu_statustext = $psustates_enum{$value};

	if($value != 2)
	{
		push(@badpsu,"Unit $stackunit $psu_name is $psu_statustext");
		$return = 1;
	}
}

if($return == 1)
{
	$msg = "WARNING: One or more power supplies are not functioning properly.";
	$info = join("\n",@badpsu);
}
else
{
	$msg = "OK: All power supplies normal";
	$return = 0;
}

chomp($info);
print("$msg\n$info");
exit($return);

sub snmp_psuStatus { return walk($host, $community, SNMPPORT, PSUSTATUS_OID); }
sub snmp_psuNames  { return walk($host, $community, SNMPPORT, PSUDESC_OID);   }

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
