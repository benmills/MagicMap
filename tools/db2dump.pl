#!/usr/bin/env perl
# Minimal WDC5 (.db2) reader: prints one TSV line per record:
#   id <tab> field0 <tab> field1 ...
# Array fields are joined with ','. Fields whose values look like string
# offsets are printed as "s:<text>" when --strings lists their indices.
#
#   perl tools/db2dump.pl map.db2 [--strings 0,1]
# Supports storage types: none(0), bitpacked(1), common(2),
# bitpacked-indexed(3), bitpacked-indexed-array(4), bitpacked-signed(5).
use strict;
use warnings;

my ($file, @opt) = @ARGV;
my %strField;
for (my $i = 0; $i < @opt; $i++) {
    if ($opt[$i] eq "--strings") { $strField{$_} = 1 for split /,/, $opt[++$i] }
}
open my $fh, "<:raw", $file or die "$file: $!\n";
my $b = do { local $/; <$fh> };

my ($magic) = unpack "a4", $b;
die "not WDC5 ($magic)\n" unless $magic eq "WDC5";
my $p = 4 + 4 + 128;
my ($recCount, $fieldCount, $recSize, $strSize, $tableHash, $layoutHash, $minId, $maxId, $locale,
    $flags, $idIndex, $totalFields, $bitpackedOffset, $lookupCols, $fsiSize, $commonSize, $palletSize, $sectionCount)
    = unpack "V9 v v V7", substr($b, $p, 4 * 9 + 2 + 2 + 4 * 7);
$p += 4 * 9 + 4 + 4 * 7;

my @sections;
for (1 .. $sectionCount) {
    my ($keyLo, $keyHi, $off, $rc, $ss, $recEnd, $idListSize, $relSize, $offMapCount, $copyCount)
        = unpack "V V V V V V V V V V", substr($b, $p, 40);
    # Encrypted sections (TACT key set) aren't readable without the key; skip them.
    push @sections, { encrypted => ($keyLo || $keyHi) ? 1 : 0, off => $off, rc => $rc, ss => $ss, idListSize => $idListSize,
        relSize => $relSize, offMapCount => $offMapCount, copyCount => $copyCount };
    $p += 40;
}
my @fields; # { size, position }
for (1 .. $fieldCount) {
    my ($size, $pos) = unpack "s< v", substr($b, $p, 4);
    push @fields, { size => $size, pos => $pos };
    $p += 4;
}
my @fsi;
for (1 .. $fieldCount) {
    my ($offBits, $sizeBits, $addSize, $type, $v1, $v2, $v3) = unpack "v v V V V V V", substr($b, $p, 24);
    push @fsi, { offBits => $offBits, sizeBits => $sizeBits, addSize => $addSize, type => $type,
        v1 => $v1, v2 => $v2, v3 => $v3 };
    $p += 24;
}
my $palletStart = $p;
my $commonStart = $palletStart + $palletSize;
my $dataStart = $commonStart + $commonSize;

# Per-field offsets into pallet / common blocks.
my ($palOff, $comOff) = (0, 0);
for my $f (@fsi) {
    if ($f->{type} == 3 || $f->{type} == 4) { $f->{palletBase} = $palletStart + $palOff; $palOff += $f->{addSize} }
    if ($f->{type} == 2) {
        # common data: (id, value) pairs, sorted by id
        my %map;
        my $n = $f->{addSize} / 8;
        for my $k (0 .. $n - 1) {
            my ($id, $val) = unpack "V V", substr($b, $commonStart + $comOff + $k * 8, 8);
            $map{$id} = $val;
        }
        $f->{common} = \%map;
        $comOff += $f->{addSize};
    }
}

sub bits {
    my ($rec, $bitOff, $nbits) = @_;
    my $v = 0;
    for my $i (0 .. $nbits - 1) {
        my $bit = $bitOff + $i;
        my $byte = ord(substr($rec, $bit >> 3, 1));
        $v |= (($byte >> ($bit & 7)) & 1) << $i;
    }
    return $v;
}

my $isSparse = $flags & 1; # offset map (variable-size records): not supported
die "sparse db2 not supported\n" if $isSparse;

# WDC3+ string offsets are relative to a field's position within the records of
# *all* sections laid end to end (encrypted ones included). Each section's string
# table covers the next slice of "keys" after all record data.
{
    my ($firstRec, $keyBase) = (0, $recCount * $recSize);
    for my $s (@sections) {
        $s->{firstRec} = $firstRec;
        $s->{strKeyBase} = $keyBase;
        $s->{strStart} = $s->{off} + $s->{rc} * $recSize;
        $firstRec += $s->{rc};
        $keyBase += $s->{ss};
    }
}
sub string_at {
    my ($key) = @_;
    for my $s (@sections) {
        next if $s->{encrypted} || $key < $s->{strKeyBase} || $key >= $s->{strKeyBase} + $s->{ss};
        my $abs = $s->{strStart} + $key - $s->{strKeyBase};
        my $end = index($b, "\0", $abs);
        return substr($b, $abs, $end - $abs);
    }
    return undef;
}
my $recordsSeen = 0;
for my $s (@sections) {
    next unless $s->{rc} && !$s->{encrypted} && $s->{off} < length $b;
    my $recStart = $s->{off};
    my $strStart = $recStart + $s->{rc} * $recSize;
    my $idListStart = $strStart + $s->{ss};
    my @ids = unpack "V*", substr($b, $idListStart, $s->{idListSize});
    for my $r (0 .. $s->{rc} - 1) {
        my $recOff = $recStart + $r * $recSize;
        my $rec = substr($b, $recOff, $recSize);
        my @vals;
        for my $fi (0 .. $fieldCount - 1) {
            my $f = $fsi[$fi];
            my $t = $f->{type};
            my $val;
            if ($t == 0) {
                my $bytes = $f->{sizeBits} / 8;
                my $count = $bytes / 4 || 1;
                if ($f->{sizeBits} % 32 == 0 && $f->{sizeBits} > 32) {
                    $val = join ",", unpack "V$count", substr($rec, $f->{offBits} / 8, $bytes);
                } else {
                    $val = bits($rec, $f->{offBits}, $f->{sizeBits});
                }
                if ($strField{$fi} && $val) {
                    my $key = ($s->{firstRec} + $r) * $recSize + $f->{offBits} / 8 + $val;
                    my $str = string_at($key);
                    $val = "s:" . $str if defined $str;
                }
            } elsif ($t == 1 || $t == 5) {
                $val = bits($rec, $f->{offBits}, $f->{v2}); # v2 = bit width
                if ($t == 5 && $val & (1 << ($f->{v2} - 1))) { $val -= 1 << $f->{v2} }
            } elsif ($t == 2) {
                $val = undef; # filled after we know the id
            } elsif ($t == 3) {
                my $idx = bits($rec, $f->{offBits}, $f->{v2});
                $val = unpack "V", substr($b, $f->{palletBase} + $idx * 4, 4);
            } elsif ($t == 4) {
                my $idx = bits($rec, $f->{offBits}, $f->{v2});
                my $n = $f->{v3};
                $val = join ",", unpack "V$n", substr($b, $f->{palletBase} + $idx * 4 * $n, 4 * $n);
            } else {
                $val = "?";
            }
            push @vals, $val;
        }
        my $id = @ids ? $ids[$r] : ($flags & 4 ? $vals[$idIndex] : $minId + $recordsSeen);
        for my $fi (0 .. $fieldCount - 1) {
            next unless $fsi[$fi]{type} == 2;
            $vals[$fi] = exists $fsi[$fi]{common}{$id} ? $fsi[$fi]{common}{$id} : $fsi[$fi]{v1};
        }
        print join("\t", $id, map { defined $_ ? $_ : "" } @vals), "\n";
        $recordsSeen++;
    }
}
