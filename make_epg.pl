#!/usr/bin/perl

use strict;	
use warnings;
use Encode;
use utf8;
use open ':std', ':locale';
use Data::Dumper;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Compress::Gzip qw(gzip $GzipError) ;
use LWP::UserAgent;
use LWP::Protocol::https;
use Text::CSV;
use XML::LibXML;
use feature qw(say);

### DUMPER ###
$Data::Dumper::Useperl = 1;
$Data::Dumper::Useqq = 1;
{	no warnings 'redefine';
 no warnings 'utf8';
	sub Data::Dumper::qquote {
		my $s = shift;
		return "'$s'";
	}
}

sub get_array_from_csv($){
	my $db = shift;
	my $csv = Text::CSV->new ({ sep_char => ";" });
	open my $fn, "<", "$db"  or die "$db: $!";
	my @cols = @{$csv->getline ($fn)};
	$csv->column_names (@cols);
	my @array;
	while (my $row = $csv->getline_hr ($fn)) {
			push @array, { %{$row} };
	}
	close $fn;
	return @array;
}

sub get_epg($$$){
	my ($url,$gzfile,$xmlfile) = (shift, shift, shift);
	my $ua = LWP::UserAgent->new;
	my $response = $ua->get( $url );
	if ($response->is_success) {
		open my $outFile, '>:raw', $gzfile or die "Failed opening $gzfile: $!";
		print $outFile $response->content;
		close $outFile;
		gunzip $gzfile => $xmlfile or die "gunzip failed: $GunzipError\n";
	}
	else {
		die $response->status_line;
	}
}

sub make_epg {
	my $openxml = $_[0];
	my @array = @{$_[1]};
	my $key = $_[2];
	my $savexml = $_[3];
	my $savexmlgz = $_[4];
	my @unique;
	my %seen;
	foreach my $value (@array) {
		if(! $seen{$value->{$key}}++ ) {
			push @unique, $value;
		}
	}
	my $createxml = XML::LibXML::Document->new('1.0', 'UTF-8');
	my $tv = $createxml->createElement('tv');
	my $loadxml = XML::LibXML->load_xml(location => $openxml, no_blanks => 1);
	foreach my $nodes ( $loadxml->documentElement->findnodes('./channel')){
		my $id = $nodes->getAttributeNode('id')->value;
		foreach my $tmp (@unique){
			if ($id eq $tmp->{$key}){
				$tv->addChild ($nodes);
			}
		}
	}
	foreach my $nodes ( $loadxml->documentElement->findnodes('./programme')){
		my $channel = $nodes->getAttributeNode('channel')->value;
		foreach my $tmp (@unique){
			if ($channel eq $tmp->{$key}){
				$tv->addChild ($nodes);
			}
		}
	}
	$createxml->setDocumentElement($tv);
	open my $fn, ">:raw", "$savexml" or die "$savexml: $!";
	print $fn $createxml->toString(1);
	close $fn;
	open $fn, "<:raw", $savexml;
	gzip $fn => $savexmlgz or die "gzip failed: $GzipError\n";
	close $fn;
}

my $workdir = '/opt/iptv_playlist/epg';
my $webdir = "/var/www/html/iptv";
my $iptvxxml = "$workdir/iptvx.xml";
my $iptvxgz = "$workdir/iptvx.xml.gz";
my $teleguidexml = "$workdir/teleguide.xml";
my $teleguidegz =  "$workdir/teleguide.xml.gz";
my $ottcsv = "$workdir/ottdb_v4.0.csv";
my $edemcsv = "$workdir/edem.csv";
my $ottepg = "$workdir/ott.xml";
my $edemepg = "$workdir/edem.xml";
my $ottepggz = "$webdir/ott.xml.gz";
my $edemepggz = "$webdir/edem.xml.gz";
my $iptvxurl = 'https://iptvx.one/epg/epg.xml.gz';
my $teleguideurl = 'https://www.teleguide.info/download/new3/xmltv.xml.gz';
my @delfiles = ($iptvxxml, $iptvxgz, $teleguidexml, $teleguidegz, $ottepg, $edemepg);

my @ottdb = get_array_from_csv ($ottcsv);
#print Dumper @ottdb;
my @edemdb = get_array_from_csv ($edemcsv);
#print Dumper @edemdb;
#get_epg($teleguideurl,$teleguidegz,$teleguidexml);
get_epg($iptvxurl,$iptvxgz,$iptvxxml);
make_epg ($iptvxxml,\@ottdb,'Iptvx_tvg-id',$ottepg,$ottepggz);
make_epg ($iptvxxml,\@edemdb,'Tvg-id',$edemepg,$edemepggz);
unlink @delfiles;