#!/usr/bin/env perl
# Minimal read-only CASC reader: extract files by FileDataID from a local
# WoW install, for a specific product (e.g. wow_classic_beta = WoW Forever).
#
#   perl tools/casc_extract.pl "/Applications/World of Warcraft" wow_classic_beta OUTDIR fdid [fdid...]
#
# Writes OUTDIR/<fdid>.bin for each file found. Encrypted chunks are zeroed.
use strict;
use warnings;
use Compress::Zlib qw(uncompress);

my ($install, $product, $outDir, @fdids) = @ARGV;
die "usage: $0 INSTALL PRODUCT OUTDIR FDID...\n" unless @fdids;
my $data = "$install/Data";

# --- .build.info -> build config -> root / encoding keys -------------------
sub read_file { my ($p) = @_; open my $fh, "<:raw", $p or die "$p: $!\n"; local $/; <$fh> }

my ($buildKey);
{
	my @lines = split /\r?\n/, read_file("$install/.build.info");
	my @cols = map { (split /!/)[0] } split /\|/, shift @lines;
	for (@lines) {
		my %row; @row{@cols} = split /\|/;
		$buildKey = $row{"Build Key"} if ($row{Product} // "") eq $product;
	}
	die "product $product not in .build.info\n" unless $buildKey;
}
my %config = map { /^(\S+) = (.*)$/ ? ($1, $2) : () }
	split /\n/, read_file(sprintf "%s/config/%s/%s/%s", $data, substr($buildKey, 0, 2), substr($buildKey, 2, 2), $buildKey);
my $rootCKey = $config{root};
my (undef, $encodingEKey) = split / /, $config{encoding};
print STDERR "build: $config{'build-name'}\n";

# --- local indices: first 9 bytes of EKey -> (archive, offset, size) --------
my %index;
{
	my %latest;
	opendir my $dh, "$data/data" or die "$data/data: $!\n";
	for my $f (map { "$data/data/$_" } grep { /\.idx$/ } readdir $dh) {
		my ($bucket, $ver) = $f =~ m{/([0-9a-f]{2})([0-9a-f]{8})\.idx$}i or next;
		$latest{$bucket} = $f if !$latest{$bucket} || hex($ver) > hex(($latest{$bucket} =~ m{([0-9a-f]{8})\.idx$}i)[0]);
	}
	for my $f (values %latest) {
		my $buf = read_file($f);
		my $headerHashSize = unpack "V", $buf;
		my $pos = (8 + $headerHashSize + 0x0F) & ~0x0F;
		my $entriesSize = unpack "V", substr($buf, $pos, 4);
		$pos += 8;
		for (my $i = 0; $i < $entriesSize; $i += 18) {
			my $e = substr($buf, $pos + $i, 18);
			my $key = substr($e, 0, 9);
			my ($hi, $lo) = unpack "C N", substr($e, 9, 5);
			my $loc = $hi * 2**32 + $lo;
			my $archive = int($loc / 2**30);
			my $offset = $loc % 2**30;
			my $size = unpack "V", substr($e, 14, 4);
			$index{$key} //= [$archive, $offset, $size];
		}
	}
}

sub blte_decode {
	my ($blte) = @_;
	die "not BLTE\n" unless substr($blte, 0, 4) eq "BLTE";
	my $headerSize = unpack "N", substr($blte, 4, 4);
	my @chunks;
	if ($headerSize == 0) {
		@chunks = (substr($blte, 8));
	} else {
		my $count = unpack "N", "\0" . substr($blte, 9, 3);
		my $pos = $headerSize;
		for my $i (0 .. $count - 1) {
			my $compSize = unpack "N", substr($blte, 12 + $i * 24, 4);
			push @chunks, substr($blte, $pos, $compSize);
			$pos += $compSize;
		}
	}
	my $out = "";
	for my $c (@chunks) {
		my $mode = substr($c, 0, 1);
		my $body = substr($c, 1);
		if ($mode eq "N") { $out .= $body }
		elsif ($mode eq "Z") { my $u = uncompress($body); die "zlib failed\n" unless defined $u; $out .= $u }
		elsif ($mode eq "F") { $out .= blte_decode($body) }
		elsif ($mode eq "E") { warn "encrypted chunk (zeroed)\n"; $out .= "\0" x 0 }
		else { die "unsupported BLTE mode '$mode'\n" }
	}
	return $out;
}

sub read_ekey {
	my ($ekeyHex) = @_;
	my $loc = $index{substr(pack("H*", $ekeyHex), 0, 9)} or return undef;
	my ($archive, $offset, $size) = @$loc;
	my $path = sprintf "%s/data/data.%03d", $data, $archive;
	open my $fh, "<:raw", $path or die "$path: $!\n";
	seek $fh, $offset + 30, 0;
	read $fh, my $blte, $size - 30;
	return blte_decode($blte);
}

# --- encoding: CKey -> EKey (binary search the page table) ------------------
my $enc = read_ekey($encodingEKey) // die "encoding file not in local storage\n";
my ($ckSize, $ekSize, $cePageKB, undef, $cePages, undef, undef, $especSize) =
	unpack "x2 x C C n n N N C N", $enc;
my $pageTable = 22 + $especSize;
my $pagesStart = $pageTable + $cePages * 32;

sub ckey_to_ekey {
	my ($ckeyHex) = @_;
	my $ckey = pack "H*", $ckeyHex;
	my ($lo, $hi) = (0, $cePages - 1);
	while ($lo < $hi) {
		my $mid = int(($lo + $hi + 1) / 2);
		if (substr($enc, $pageTable + $mid * 32, 16) le $ckey) { $lo = $mid } else { $hi = $mid - 1 }
	}
	my $p = $pagesStart + $lo * $cePageKB * 1024;
	my $end = $p + $cePageKB * 1024;
	while ($p < $end) {
		my $keyCount = unpack "C", substr($enc, $p, 1);
		last if $keyCount == 0;
		my $ck = substr($enc, $p + 6, $ckSize);
		return unpack "H*", substr($enc, $p + 6 + $ckSize, $ekSize) if $ck eq $ckey;
		$p += 6 + $ckSize + $keyCount * $ekSize;
	}
	return undef;
}

# --- root (MFST): FileDataID -> CKey -----------------------------------------
my $root = read_ekey(ckey_to_ekey($rootCKey) // die "root ckey not in encoding\n") // die "root not local\n";
die "unsupported root format\n" unless substr($root, 0, 4) eq "TSFM";
my %want = map { $_ => 1 } @fdids;
my %found;
{
	my ($headerSize, $version) = unpack "x4 V V", $root;
	my $pos = 12;
	if ($headerSize == 0x18) { $pos = $headerSize } else { $version = 0 }
	while ($pos < length $root) {
		my ($n, $contentFlags, $localeFlags);
		if ($version >= 2) {
			my ($f1, $f2, $f3);
			($n, $localeFlags, $f1, $f2, $f3) = unpack "V V V V C", substr($root, $pos, 17);
			$contentFlags = $f1 | $f2 | ($f3 << 17);
			$pos += 17;
		} else {
			($n, $contentFlags, $localeFlags) = unpack "V V V", substr($root, $pos, 12);
			$pos += 12;
		}
		my @deltas = unpack "l<$n", substr($root, $pos, 4 * $n);
		$pos += 4 * $n;
		my $ckeyBase = $pos;
		$pos += 16 * $n;
		my $named = !($contentFlags & 0x10000000);
		$pos += 8 * $n if $named;
		next unless $localeFlags & 0x2; # enUS
		my $fdid = -1;
		for my $i (0 .. $n - 1) {
			$fdid += 1 + $deltas[$i];
			if ($want{$fdid} && !$found{$fdid}) {
				$found{$fdid} = { ckey => unpack("H*", substr($root, $ckeyBase + 16 * $i, 16)), named => $named };
			}
		}
	}
}

if ($ENV{CKEYS_ONLY}) {
	print "$_\t", ($found{$_} ? $found{$_}{ckey} : "-"), "\n" for @fdids;
	exit 0;
}

mkdir $outDir;
for my $fdid (@fdids) {
	my $f = $found{$fdid};
	unless ($f) { print "$fdid\tnot in root\n"; next }
	my $ekey = ckey_to_ekey($f->{ckey});
	my $bytes = $ekey ? read_ekey($ekey) : undef;
	unless (defined $bytes) { print "$fdid\tnot in local storage\n"; next }
	open my $out, ">:raw", "$outDir/$fdid.bin" or die $!;
	print $out $bytes;
	printf "%d\t%d bytes\tckey %s\tnamehash %s\n", $fdid, length $bytes, $f->{ckey}, $f->{named} ? "yes" : "no";
}
