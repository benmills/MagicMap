# Shared helpers for the generator scripts (require "tools/lib.pl").
use strict;
use warnings;
use FindBin;

our $MAP_DB2 = 1349477;       # dbfilesclient/map.db2
our $AREATABLE_DB2 = 1353545; # dbfilesclient/areatable.db2
our $AZEROTH_WDT = 775971;

sub slurp { open my $fh, "<:raw", $_[0] or die "$_[0]: $!\n"; local $/; <$fh> }

sub lua_str { my ($s) = @_; $s =~ s/(["\\])/\\$1/g; return "\"$s\"" }

# Version string of an installed product, from .build.info.
sub product_version {
    my ($install, $product) = @_;
    open my $bi, "<", "$install/.build.info" or die "$install/.build.info: $!\n";
    my @cols = map { (split /!/)[0] } split /\|/, scalar <$bi>;
    my $version;
    while (<$bi>) {
        chomp; my %row; @row{@cols} = split /\|/;
        $version = $row{Version} if ($row{Product} // "") eq $product;
    }
    die "product $product not installed\n" unless $version;
    return $version;
}

# Extract FileDataIDs from a local install into $dir as <fdid>.bin.
# casc_extract reports progress on stdout; keep it off ours.
sub casc_extract {
    my ($install, $product, $dir, @ids) = @_;
    return unless @ids;
    open(my $saved, ">&", \*STDOUT) or die;
    open(STDOUT, ">", "/dev/null") or die;
    my $rc = system($^X, "$FindBin::Bin/casc_extract.pl", $install, $product, $dir, @ids);
    open(STDOUT, ">&", $saved) or die;
    $rc == 0 or die "casc_extract failed\n";
}

# Dump a .db2 with db2dump.pl; returns rows as array refs [id, field0, ...].
sub db2_rows {
    my ($file, $strings) = @_;
    my $out = `"$^X" "$FindBin::Bin/db2dump.pl" "$file" --strings $strings 2>/dev/null`;
    return map { [split /\t/, $_, -1] } split /\n/, $out;
}

# Every open-world map (InstanceType 0) with a WDT: [instanceID, wdtFDID, name].
# Columns are found by content since layouts shift between builds: the WDT
# column holds Azeroth's known WDT on map 0; InstanceType follows MapType,
# which follows the first array field (Corpse x,y).
sub world_maps {
    my ($mapDb2File) = @_;
    my @rows = db2_rows($mapDb2File, "0,1");
    my ($azeroth) = grep { $_->[0] eq "0" } @rows or die "map 0 missing from Map.db2\n";
    my ($wdtCol) = grep { $azeroth->[$_] eq $AZEROTH_WDT } 0 .. $#$azeroth or die "WDT column not found\n";
    my ($arrayCol) = grep { $azeroth->[$_] =~ /,/ } 1 .. $#$azeroth or die "Corpse column not found\n";
    my $instCol = $arrayCol + 2;
    my @maps;
    for my $r (@rows) {
        next unless $r->[$instCol] eq "0" && $r->[$wdtCol] =~ /^\d+$/ && $r->[$wdtCol] > 0;
        (my $name = $r->[2] // "") =~ s/^s://;
        push @maps, [$r->[0], $r->[$wdtCol], $name eq "" ? "Map $r->[0]" : $name];
    }
    return @maps;
}

# WDT MAID chunk: 64*64 entries of 8 uint32 stored [row][col]:
# rootADT, obj0, obj1, tex0, lod, mapTexture, mapTextureN, minimapTexture.
# Returns { col*64+row => [the 8 ids] } for tiles that exist.
sub wdt_maid {
    my ($buf) = @_;
    my %tiles;
    for (my $pos = 0; $pos + 8 <= length $buf;) {
        my ($magic, $size) = unpack "a4 V", substr($buf, $pos, 8);
        if (reverse($magic) eq "MAID") {
            my @ids = unpack "V*", substr($buf, $pos + 8, $size);
            for my $i (0 .. 4095) {
                my @e = @ids[$i * 8 .. $i * 8 + 7];
                next unless $e[0] || $e[7];
                $tiles{($i % 64) * 64 + int($i / 64)} = \@e;
            }
            last;
        }
        $pos += 8 + $size;
    }
    return \%tiles;
}

1;
