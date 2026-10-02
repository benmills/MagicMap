#!/usr/bin/env perl
# Generate Data/Tiles_<product>.lua from a game version's own data.
#
# Each map's WDT (MAID chunk) lists the exact minimap FileDataID for every
# tile *that version* uses, so we never guess IDs or rely on the retail
# listfile (which includes tiles other versions never reference).
#
#   local: reads the install's own Map.db2 and includes every open-world map
#          that has minimap tiles (continents, islands, custom zones...).
#   wago:  downloads the four classic continents' WDTs from wago.tools.
#
#   perl tools/gen_tiles.pl local "/Applications/World of Warcraft" wow_classic_beta
#   perl tools/gen_tiles.pl wago wow_classic_era
#
# Local mode can also write terrain heights (one byte per 33-yard chunk):
#   perl tools/gen_tiles.pl local "/Applications/World of Warcraft" wow_classic_beta \
#       --heights Data/Heights_wow_classic_beta.lua > Data/Tiles_wow_classic_beta.lua
use strict;
use warnings;
use File::Temp qw(tempdir);
use FindBin;

my $MAP_DB2 = 1349477; # dbfilesclient/map.db2
my $AZEROTH_WDT = 775971;

# For wago mode: instanceID, WDT FileDataID, name
my @classicContinents = (
    [0,   775971, "Eastern Kingdoms"],
    [1,   782779, "Kalimdor"],
    [530, 828395, "Outland"],
    [571, 822688, "Northrend"],
);

my $mode = shift // "";
my $tmp = tempdir(CLEANUP => 1);
my ($product, $version, @maps, %wdtFile, $fetch, $heightsFile, $install); # $fetch->(fdids) -> (fdid => path) # @maps: [instanceID, wdtFDID, name]

sub slurp { open my $fh, "<:raw", $_[0] or die "$_[0]: $!\n"; local $/; <$fh> }

sub casc_extract {
    my ($install, $product, @ids) = @_;
    # casc_extract reports progress on stdout; keep it out of the generated Lua.
    open(my $saved, ">&", \*STDOUT) or die;
    open(STDOUT, ">&", \*STDERR) or die;
    my $rc = system($^X, "$FindBin::Bin/casc_extract.pl", $install, $product, $tmp, @ids);
    open(STDOUT, ">&", $saved) or die;
    $rc == 0 or die "casc_extract failed\n";
}

if ($mode eq "local") {
    $install = shift or die "usage: $0 local INSTALL PRODUCT [--heights FILE]\n";
    $product = shift or die "usage: $0 local INSTALL PRODUCT [--heights FILE]\n";
    if (($ARGV[0] // "") eq "--heights") { shift; $heightsFile = shift or die "--heights needs a file\n" }
    open my $bi, "<", "$install/.build.info" or die "$install/.build.info: $!\n";
    my @cols = map { (split /!/)[0] } split /\|/, scalar <$bi>;
    while (<$bi>) {
        chomp; my %row; @row{@cols} = split /\|/;
        $version = $row{Version} if ($row{Product} // "") eq $product;
    }
    die "product $product not installed\n" unless $version;

    # Map.db2 -> every open-world map, dungeon and raid, and its WDT.
    casc_extract($install, $product, $MAP_DB2);
    my @rows = map { [split /\t/, $_, -1] } split /\n/,
        `"$^X" "$FindBin::Bin/db2dump.pl" "$tmp/$MAP_DB2.bin" --strings 0,1`;
    # Find the columns by content (layouts shift between builds): the WDT
    # column holds Azeroth's known WDT on map 0; InstanceType follows MapType,
    # which follows the first array field (Corpse x,y). CorpseMapID - the
    # continent an instance's entrance is on - is 0 for Deadmines (36) and 1
    # for Razorfen Kraul (47) and Zul'Farrak (209).
    my ($azeroth) = grep { $_->[0] eq "0" } @rows or die "map 0 missing from Map.db2\n";
    my ($wdtCol) = grep { $azeroth->[$_] eq $AZEROTH_WDT } 0 .. $#$azeroth or die "WDT column not found\n";
    my ($arrayCol) = grep { $azeroth->[$_] =~ /,/ } 1 .. $#$azeroth or die "Corpse column not found\n";
    my $instCol = $arrayCol + 2;
    my %byId = map { $_->[0] => $_ } @rows;
    my ($corpseMapCol) = grep {
        my $c = $_;
        ($byId{36}[$c] // "") eq "0" && ($byId{47}[$c] // "") eq "1" && ($byId{209}[$c] // "") eq "1"
    } $instCol + 1 .. $#$azeroth;
    my %kinds = (0 => undef, 1 => "dungeon", 2 => "raid");
    for my $r (@rows) {
        next unless exists $kinds{$r->[$instCol]} && $r->[$wdtCol] =~ /^\d+$/ && $r->[$wdtCol] > 0;
        (my $name = $r->[2] // "") =~ s/^s://;
        $name = "Map $r->[0]" if $name eq "";
        my $kind = $kinds{$r->[$instCol]};
        # An unset corpse point (0,0) means the entrance's continent is unknown.
        my $continent = $kind && defined $corpseMapCol && $r->[$arrayCol] ne "0,0" ? $r->[$corpseMapCol] : undef;
        push @maps, [$r->[0], $r->[$wdtCol], $name, $kind, $continent];
    }
    casc_extract($install, $product, map { $_->[1] } @maps);
    for (@maps) { $wdtFile{$_->[1]} = "$tmp/$_->[1].bin" if -e "$tmp/$_->[1].bin" }
    $fetch = sub { casc_extract($install, $product, @_); return map { $_ => "$tmp/$_.bin" } grep { -e "$tmp/$_.bin" } @_ };
} elsif ($mode eq "wago") {
    $product = shift or die "usage: $0 wago PRODUCT\n";
    my $builds = `curl -fsSL https://wago.tools/api/builds`;
    ($version) = $builds =~ /"\Q$product\E":\[\{"product":"\Q$product\E","version":"([^"]+)"/
        or die "product $product not on wago.tools\n";
    @maps = @classicContinents;
    $fetch = sub {
        my %got;
        for my $id (@_) {
            my $out = "$tmp/$id.bin";
            system("curl", "-fsSL", "-o", $out, "https://wago.tools/api/casc/$id?version=$version") == 0 and -s $out and $got{$id} = $out;
        }
        return %got;
    };
    for (@maps) {
        my $out = "$tmp/$_->[1].bin";
        system("curl", "-fsSL", "-o", $out, "https://wago.tools/api/casc/$_->[1]?version=$version") == 0
            and -s $out and substr(slurp($out), 0, 4) eq "REVM" and $wdtFile{$_->[1]} = $out;
    }
} else {
    die "usage: $0 local INSTALL PRODUCT | wago PRODUCT\n";
}

# MAID: 64*64 entries of 8 uint32, stored [row][col]; the 1st is the root ADT,
# the 8th the minimap texture. Returns ({ key => minimap }, { key => root ADT }).
sub wdt_tiles {
    my $buf = slurp($_[0]);
    my (%tiles, %adts);
    for (my $pos = 0; $pos + 8 <= length $buf;) {
        my ($magic, $size) = unpack "a4 V", substr($buf, $pos, 8);
        if (reverse($magic) eq "MAID") {
            my @ids = unpack "V*", substr($buf, $pos + 8, $size);
            for my $i (0 .. 4095) {
                my $key = ($i % 64) * 64 + int($i / 64); # col*64 + row
                $adts{$key} = $ids[$i * 8] if $ids[$i * 8];
                my $fdid = $ids[$i * 8 + 7] or next;
                $tiles{$key} = $fdid;
            }
            last;
        }
        $pos += 8 + $size;
    }
    return (\%tiles, \%adts);
}

# Mean height of each of a root ADT's 16x16 chunks (MCNK position z plus its
# 145 MCVT offsets). Returns { iy * 16 + ix => height in yards }.
sub adt_heights {
    my ($b) = @_;
    my %h;
    for (my $p = 0; $p + 8 <= length $b;) {
        my ($magic, $size) = unpack "a4 V", substr($b, $p, 8);
        if (reverse($magic) eq "MCNK" && $size >= 0x80) {
            my $d = substr($b, $p + 8, $size);
            my ($ix, $iy) = unpack "x4 V V", $d;
            my $z = unpack "f<", substr($d, 0x70, 4);
            my $mcvt = index($d, "TVCM", 0x80);
            if ($mcvt >= 0 && $ix < 16 && $iy < 16) {
                my $sum = 0;
                $sum += $_ for unpack "f<145", substr($d, $mcvt + 8, 580);
                $h{$iy * 16 + $ix} = $z + $sum / 145;
            }
        }
        $p += 8 + $size;
    }
    return \%h;
}

# Average colour of the DXT1 blocks along the sides of a tile that face empty
# space (no neighbouring tile): i.e. the water right where the map meets the
# background. Returns a list of [r,g,b] samples (0..1).
sub edge_colors {
    my ($blp, $sides) = @_;
    my ($enc, $alphaDepth, $alphaType, undef, $w, $h) = unpack "x8 C C C C V V", $blp;
    return () unless $enc == 2 && $w >= 16 && $h >= 16;
    my $off = unpack "V", substr($blp, 20, 4);
    my $blockBytes = ($alphaType == 0 || $alphaType == 1) ? 8 : 16; # DXT1 vs DXT3/5
    my $colorAt = $blockBytes == 8 ? 0 : 8;
    my ($bw, $bh) = ($w / 4, $h / 4);
    my @out;
    my $sample = sub {
        my ($bx, $by) = @_;
        my ($c0, $c1) = unpack "v v", substr($blp, $off + ($by * $bw + $bx) * $blockBytes + $colorAt, 4);
        my @rgb;
        for my $c ($c0, $c1) { push @rgb, [(($c >> 11) & 31) / 31, (($c >> 5) & 63) / 63, ($c & 31) / 31] }
        push @out, [map { ($rgb[0][$_] + $rgb[1][$_]) / 2 } 0 .. 2];
    };
    for my $i (0 .. $bw - 1) {
        next if $i % 4; # every 4th block along the edge is plenty
        $sample->(0, $i) if $sides->{left};
        $sample->($bw - 1, $i) if $sides->{right};
        $sample->($i, 0) if $sides->{top};
        $sample->($i, $bh - 1) if $sides->{bottom};
    }
    return @out;
}

sub median { my @s = sort { $a <=> $b } @_; return $s[int(@s / 2)] }

sub lua_str { my ($s) = @_; $s =~ s/(["\\])/\\$1/g; return "\"$s\"" }

# Tiles per map, and the edge tiles to sample for a background colour.
my (%tilesOf, %adtsOf, %samples, @wanted);
for my $m (@maps) {
    my ($inst, $wdt) = @$m;
    next unless $wdtFile{$wdt};
    my ($tiles, $adts) = wdt_tiles($wdtFile{$wdt});
    $adtsOf{$inst} = $adts;
    next unless %$tiles;
    $tilesOf{$inst} = $tiles;
    my @edge;
    for my $key (sort { $a <=> $b } keys %$tiles) {
        my %sides = (
            left => !$tiles->{$key - 64}, right => !$tiles->{$key + 64},
            top => !$tiles->{$key - 1}, bottom => !$tiles->{$key + 1},
        );
        push @edge, [$tiles->{$key}, \%sides] if grep { $_ } values %sides;
    }
    my $step = @edge > 24 ? @edge / 24 : 1;
    for (my $i = 0; $i < @edge; $i += $step) {
        push @{ $samples{$inst} }, $edge[int $i];
        push @wanted, $edge[int $i][0];
    }
}
my %files = @wanted ? $fetch->(@wanted) : ();

print "-- GENERATED by tools/gen_tiles.pl from the $product $version WDT files. Do not edit.\n";
print "-- tiles[col * 64 + row] = minimap FileDataID for map<col>_<row>\n";
print "-- bg = median colour of the water along the map's outer edge (for the backdrop)\n";
print "-- kind = \"dungeon\" | \"raid\" for instances (nil: open world); continent = instanceID of the entrance's continent\n";
print "if not MagicMap_WantTileSet(\"$product\", \"$version\") then return end\n";
print "MagicMap_ActiveProduct = \"$product\"\n";
print "MagicMap_TileSets = MagicMap_TileSets or {}\n";
print "MagicMap_TileSets[\"$product\"] = { version = \"$version\", maps = {\n";
for my $m (sort { $a->[0] <=> $b->[0] } @maps) {
    my ($inst, undef, $name, $kind, $continent) = @$m;
    my $tiles = $tilesOf{$inst} or next;
    my @colors;
    for my $s (@{ $samples{$inst} || [] }) {
        my $file = $files{$s->[0]} or next;
        push @colors, edge_colors(slurp($file), $s->[1]);
    }
    my $bg = @colors
        ? sprintf("{ %.3f, %.3f, %.3f }", map { my $c = $_; median(map { $_->[$c] } @colors) } 0 .. 2)
        : "nil";
    my @keys = sort { $a <=> $b } keys %$tiles;
    my $instance = $kind ? ", kind = \"$kind\"" . (defined $continent ? ", continent = $continent" : "") : "";
    print "  [$inst] = { name = ", lua_str($name), ", bg = $bg$instance, tiles = {\n";
    while (my @chunk = splice(@keys, 0, 8)) {
        print "    ", join(" ", map { "[$_]=$tiles->{$_}," } @chunk), "\n";
    }
    print "  } },\n";
    printf STDERR "%s %s: [%d] %s %d tiles, bg %s\n", $product, $version, $inst, $name, scalar keys %$tiles, $bg;
}
print "} }\n";

# --- terrain heights (local mode, --heights FILE) ---------------------------
# One byte per 33-yard chunk (16x16 per tile), quantized per map as
# height = min + level * scale. A tile is a 256-byte string, row by row
# (byte iy*16 + ix + 1), or a single byte when the whole tile is one level
# (open sea). Bytes are raw except those a Lua string literal can't hold; each
# map rotates its levels by `shift` so as few as possible need escaping.
exit 0 unless $heightsFile;
die "--heights needs local mode\n" unless $install;

sub lua_bytes {
    my ($s) = @_;
    $s =~ s/([\x00-\x1f"\\\x7f])/sprintf "\\%03d", ord $1/ge;
    return "\"$s\"";
}

open my $out, ">:raw", $heightsFile or die "$heightsFile: $!\n";
print $out "-- GENERATED by tools/gen_tiles.pl from the $product $version terrain (ADT chunk heights). Do not edit.\n";
print $out "-- tiles[col * 64 + row] = 256 bytes (or 1 for a flat tile), chunk (ix, iy) at byte iy * 16 + ix + 1;\n";
print $out "-- height in yards = min + ((byte - shift) % 256) * scale\n";
print $out "if not MagicMap_WantHeights(\"$product\", \"$version\") then return end\n";
print $out "MagicMap_Heights = {\n";
for my $m (sort { $a->[0] <=> $b->[0] } @maps) {
    my ($inst, undef, $name, $kind) = @$m;
    next if $kind; # open world only: keeps the file small
    my $adts = $adtsOf{$inst} or next;
    next unless $tilesOf{$inst};
    my @keys = sort { $a <=> $b } grep { $tilesOf{$inst}{$_} } keys %$adts;
    next unless @keys;
    casc_extract($install, $product, map { $adts->{$_} } @keys);
    my (%h, $lo, $hi);
    for my $key (@keys) {
        my $file = "$tmp/$adts->{$key}.bin";
        next unless -e $file;
        my $t = adt_heights(slurp($file));
        unlink $file;
        next unless %$t;
        $h{$key} = $t;
        for (values %$t) { $lo = $_ if !defined $lo || $_ < $lo; $hi = $_ if !defined $hi || $_ > $hi }
    }
    next unless %h;
    my $scale = ($hi - $lo) / 255 || 1;
    my (%levels, %hist);
    for my $key (keys %h) {
        my $t = $h{$key};
        my $mean = 0;
        $mean += $_ for values %$t;
        $mean /= scalar keys %$t;
        my @q = map { int((($t->{$_} // $mean) - $lo) / $scale + 0.5) } 0 .. 255;
        @q = ($q[0]) unless grep { $_ != $q[0] } @q;
        $levels{$key} = \@q;
        $hist{$_}++ for @q;
    }
    my ($shift, $best);
    for my $k (0 .. 255) {
        my $cost = 0;
        for my $q (keys %hist) {
            my $b = ($q + $k) % 256;
            $cost += $hist{$q} if $b < 32 || $b == 34 || $b == 92 || $b == 127;
        }
        ($shift, $best) = ($k, $cost) if !defined $best || $cost < $best;
    }
    printf $out "  [%d] = { min = %.2f, scale = %.4f, shift = %d, tiles = { -- %s\n", $inst, $lo, $scale, $shift, $name =~ s/\n/ /gr;
    my $bytes = 0;
    for my $key (sort { $a <=> $b } keys %h) {
        my $s = join "", map { chr(($_ + $shift) % 256) } @{ $levels{$key} };
        $bytes += length $s;
        print $out "    [$key]=", lua_bytes($s), ",\n";
    }
    print $out "  } },\n";
    printf STDERR "%s %s: [%d] %s heights: %d tiles, %.1f..%.1f yd, %d KB\n", $product, $version, $inst, $name,
        scalar keys %h, $lo, $hi, $bytes / 1024;
}
print $out "}\n";
close $out;
