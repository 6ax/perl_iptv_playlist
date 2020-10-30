#!/usr/bin/perl

use Data::Dumper;
use strict;	
use warnings;
use utf8;
use Encode qw( encode decode );
use open ':std', ':locale';
use XML::LibXML;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use DateTime::Format::XMLTV;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );

# my $tmpdir = '/opt/iptv_playlist/jtv/tmp';
# my $workdir = '/opt/iptv_playlist/jtv';
# my $xmlgz = "$workdir/ott.xml.gz";
# my $ottxml = "$workdir/ott.xml";
# my $zipfile = "$workdir/jtv.zip";
# my @removedfiles = ($ottxml);

my $epgwebdir = '/var/www/html/iptv';
my $workdir = '/opt/iptv_playlist/epg';
my $tmpdir = '/tmp';
my $xmlgz = "$epgwebdir/edem.xml.gz";
my $zipfile = "$epgwebdir/edem.jtv.zip";
my $xml = "$workdir/edem.xml";
my @removedfiles = ($xml);

gunzip $xmlgz => $xml  or die "gunzip failed: $GunzipError\n";
my $ottloadxml = XML::LibXML->load_xml(location => $xml, no_blanks => 1);

my %seen;
foreach my $programm ( $ottloadxml->documentElement->findnodes('//programme')){
	my $channel = $programm->getAttributeNode('channel')->value;
	#$channel =~ s/\s*$//;
	my $expr = "//programme[\@channel=\"$channel\"]";
	#print "$channel\n";
	if (!$seen{$channel}++){
		my $count;
		foreach ($ottloadxml->documentElement->findnodes($expr)){
			$count ++;
		}
		#print Dumper $count;
		open my $ndx, '>:raw', "$tmpdir/$channel".'.ndx' or die;
		syswrite ($ndx, pack("v", $count), 2); #количество телепередач (2 байт)
		open my $pdt, '>:raw', "$tmpdir/$channel".'.pdt' or die;
		syswrite($pdt, "JTV 3.x TV Program Data\x0A\x0A\x0A", 26); # заголовок файла (26 байт)
		my $offset = 26;
		foreach my $currenchan ($ottloadxml->documentElement->findnodes($expr)){
			syswrite($ndx, "\x00\x00", 2); #заголовок записи (2 байт)
			my $title = $currenchan->findvalue('./title');
			#print "$title\n";
			my $starttime = $currenchan->getAttributeNode('start')->value;
			my $dt = DateTime::Format::XMLTV->parse_datetime("$starttime");
			$dt->set_time_zone('floating');
			my $epoch_time  = $dt->epoch;
			my $win_filetime = int (($epoch_time + '11644473600') * '10000000'); # Win32 FILETIME
			#print "$win_filetime\n";
			for (my $i = 0; $i < 8; $i++) {
				my $byte = int($win_filetime % 256);
				#print "$byte\n";
				syswrite($ndx, pack("C", $byte), 1);
				$win_filetime = int($win_filetime/256);
			}
			syswrite($ndx, pack("v", $offset), 2);
			my $len = length($title);
			syswrite($pdt, pack("v", $len), 2); # длина названия телепередачи (2 байт)
			$title = Encode::encode("Windows-1251", $title);
			syswrite($pdt, $title, $len); # название телепередачи
			#print "$len\n";
			#print "$title\n";
			$offset += $len + 2;
			#print "$offset\n";
		}
		close $ndx;
		close $pdt;
	}
}

my $zip = Archive::Zip->new();

opendir my $dh, $tmpdir or die $!;
while (readdir $dh) {
	next if !(/\.pdt$/ | /\.ndx$/);
	push @removedfiles, "$tmpdir/$_";
	$zip->addFile(File::Spec->catfile($tmpdir, $_), $_);
}
closedir $dh;

# Save the Zip file
unless ( $zip->writeToFileNamed($zipfile) == AZ_OK ) {
	die 'write error';
}
unlink @removedfiles;
