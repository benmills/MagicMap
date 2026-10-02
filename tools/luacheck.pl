#!/usr/bin/env perl
# Lua 5.1 syntax checker (the dialect WoW uses), for machines without Lua.
# Tokenizes and parses with a recursive-descent parser; reports the first
# syntax error per file as file:line: message. No semantics, no globals check.
#
#   perl tools/luacheck.pl *.lua
#   perl tools/luacheck.pl --globals Core.lua   # list globals used (typo hunting)
use strict;
use warnings;


my (@tok, $pos);
my (@scopes, %globals); # scope tracking for --globals

sub declare { $scopes[-1]{$_} = 1 for @_ }
sub is_local { my ($n) = @_; for my $s (reverse @scopes) { return 1 if $s->{$n} } return 0 }
sub use_name {
    my ($n, $line) = @_;
    push @{ $globals{$n} }, $line unless is_local($n);
}

sub tokenize {
    my ($s) = @_;
    my @t;
    my $line = 1;
    pos($s) = 0;
    my %kw = map { $_ => 1 } qw(and break do else elseif end false for function if in
        local nil not or repeat return then true until while);
    while (pos($s) < length $s) {
        if ($s =~ /\G(\n)/gc) { $line++; next }
        if ($s =~ /\G[ \t\r\f\v]+/gc) { next }
        if ($s =~ /\G--\[(=*)\[/gc) {
            my $eq = $1;
            $s =~ /\G(.*?)\]$eq\]/gcs or die "$line: unfinished long comment\n";
            $line += ($1 =~ tr/\n//);
            next;
        }
        if ($s =~ /\G--[^\n]*/gc) { next }
        if ($s =~ /\G\[(=*)\[/gc) {
            my $eq = $1;
            $s =~ /\G(.*?)\]$eq\]/gcs or die "$line: unfinished long string\n";
            push @t, ["string", "[[...]]", $line];
            $line += ($1 =~ tr/\n//);
            next;
        }
        if ($s =~ /\G(["'])/gc) {
            my $q = $1;
            my $str = "";
            while (1) {
                if ($s =~ /\G\\(\n)/gc) { $line++; next }
                if ($s =~ /\G\\./gcs) { next }
                if ($s =~ /\G\Q$q\E/gc) { last }
                if ($s =~ /\G\n/gc) { die "$line: unfinished string\n" }
                if ($s =~ /\G[^\\\n$q]+/gc) { next }
                die "$line: unfinished string\n";
            }
            push @t, ["string", "\"...\"", $line];
            next;
        }
        if ($s =~ /\G(0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)/gc) {
            push @t, ["number", $1, $line];
            next;
        }
        if ($s =~ /\G([A-Za-z_][A-Za-z0-9_]*)/gc) {
            push @t, [$kw{$1} ? $1 : "name", $1, $line];
            next;
        }
        if ($s =~ /\G(\.\.\.|\.\.|==|~=|<=|>=|[-+*\/%^#<>=(){}\[\];:,.])/gc) {
            push @t, [$1, $1, $line];
            next;
        }
        my $c = substr($s, pos($s), 1);
        die "$line: unexpected character '$c'\n";
    }
    push @t, ["<eof>", "<eof>", $line];
    return @t;
}

sub peek { $tok[$pos][0] }
sub line { $tok[$pos][2] }
sub next_tok { $tok[$pos++] }
sub opt { my ($t) = @_; if (peek() eq $t) { $pos++; return 1 } return 0 }
sub expect {
    my ($t, $what) = @_;
    return next_tok() if peek() eq $t;
    my $got = $tok[$pos][1];
    die line() . ": '$t' expected" . ($what ? " ($what)" : "") . " near '$got'\n";
}

sub check {
    my ($src) = @_;
    my $err;
    eval {
        @tok = tokenize($src);
        $pos = 0;
        @scopes = ({});
        %globals = ();
        block();
        expect("<eof>", "end of file");
        1;
    } or $err = $@;
    chomp $err if $err;
    return $err;
}

sub block_follow { my $t = peek(); return $t =~ /^(else|elseif|end|until|<eof>)$/ }

sub block {
    push @scopes, {};
    my $ret = eval { block_inner(); 1 };
    pop @scopes;
    die $@ unless $ret;
}

sub block_inner {
    while (!block_follow()) {
        if (peek() eq "return") {
            next_tok();
            explist() unless block_follow() || peek() eq ";";
            opt(";");
            return;
        }
        if (peek() eq "break") { next_tok(); opt(";"); next }
        statement();
        opt(";");
    }
}

sub statement {
    my $t = peek();
    if ($t eq "if") {
        next_tok(); expr(); expect("then"); block();
        while (opt("elseif")) { expr(); expect("then"); block() }
        block() if opt("else");
        expect("end", "to close 'if'");
    } elsif ($t eq "while") {
        next_tok(); expr(); expect("do"); block(); expect("end", "to close 'while'");
    } elsif ($t eq "do") {
        next_tok(); block(); expect("end", "to close 'do'");
    } elsif ($t eq "for") {
        next_tok(); my @vars = (expect("name")->[1]);
        if (opt("=")) {
            expr(); expect(","); expr(); expr() if opt(",");
        } else {
            while (opt(",")) { push @vars, expect("name")->[1] }
            expect("in"); explist();
        }
        expect("do");
        push @scopes, { map { $_ => 1 } @vars };
        my $ok = eval { block(); 1 };
        pop @scopes;
        die $@ unless $ok;
        expect("end", "to close 'for'");
    } elsif ($t eq "repeat") {
        next_tok(); block(); expect("until"); expr();
    } elsif ($t eq "function") {
        next_tok(); my $n = expect("name"); use_name($n->[1], $n->[2]);
        while (opt(".")) { expect("name") }
        my $method = opt(":");
        expect("name") if $method;
        funcbody($method);
    } elsif ($t eq "local") {
        next_tok();
        if (opt("function")) { declare(expect("name")->[1]); funcbody() }
        else {
            my @names = (expect("name")->[1]);
            while (opt(",")) { push @names, expect("name")->[1] }
            explist() if opt("=");
            declare(@names);
        }
    } else {
        my $kind = suffixedexp();
        if (peek() eq "=" || peek() eq ",") {
            die line() . ": cannot assign to this expression\n" unless $kind eq "var";
            while (opt(",")) {
                my $k = suffixedexp();
                die line() . ": cannot assign to this expression\n" unless $k eq "var";
            }
            expect("=");
            explist();
        } else {
            die line() . ": syntax error (statement is not a call or assignment) near '$tok[$pos][1]'\n"
                unless $kind eq "call";
        }
    }
}

sub funcbody {
    my ($method) = @_;
    my @params = $method ? ("self") : ();
    expect("(");
    if (peek() ne ")") {
        while (1) {
            if (opt("...")) { push @params, "..."; last }
            push @params, expect("name")->[1];
            last unless opt(",");
        }
    }
    expect(")");
    push @scopes, { map { $_ => 1 } @params };
    my $ok = eval { block(); 1 };
    pop @scopes;
    die $@ unless $ok;
    expect("end", "to close 'function'");
}

sub explist { expr(); while (opt(",")) { expr() } }

sub primaryexp {
    my $t = peek();
    if ($t eq "name") { my $n = next_tok(); use_name($n->[1], $n->[2]); return "var" }
    if ($t eq "(") { next_tok(); expr(); expect(")"); return "paren" }
    die line() . ": unexpected symbol near '$tok[$pos][1]'\n";
}

sub args {
    my $t = peek();
    if ($t eq "string") { next_tok(); return }
    if ($t eq "{") { table(); return }
    if ($t eq "(") {
        next_tok();
        explist() unless peek() eq ")";
        expect(")");
        return;
    }
    die line() . ": function arguments expected near '$tok[$pos][1]'\n";
}

sub suffixedexp {
    my $kind = primaryexp();
    while (1) {
        my $t = peek();
        if ($t eq ".") { next_tok(); expect("name"); $kind = "var" }
        elsif ($t eq "[") { next_tok(); expr(); expect("]"); $kind = "var" }
        elsif ($t eq ":") { next_tok(); expect("name"); args(); $kind = "call" }
        elsif ($t eq "(" || $t eq "string" || $t eq "{") { args(); $kind = "call" }
        else { return $kind }
    }
}

sub table {
    expect("{");
    while (peek() ne "}") {
        if (peek() eq "[") { next_tok(); expr(); expect("]"); expect("="); expr() }
        elsif (peek() eq "name" && $tok[$pos + 1][0] eq "=") { next_tok(); next_tok(); expr() }
        else { expr() }
        last unless opt(",") || opt(";");
    }
    expect("}", "to close table");
}

my %binop = map { $_ => 1 } qw(+ - * / % ^ .. == ~= < <= > >= and or);

sub simpleexp {
    my $t = peek();
    if ($t =~ /^(number|string|nil|true|false|\.\.\.)$/) { next_tok(); return }
    if ($t eq "{") { table(); return }
    if ($t eq "function") { next_tok(); funcbody(); return }
    suffixedexp();
}

sub expr {
    while (peek() eq "not" || peek() eq "-" || peek() eq "#") { next_tok() }
    simpleexp();
    while ($binop{peek()}) {
        next_tok();
        while (peek() eq "not" || peek() eq "-" || peek() eq "#") { next_tok() }
        simpleexp();
    }
}

my $failed = 0;
my $listGlobals = @ARGV && $ARGV[0] eq "--globals" ? shift @ARGV : 0;
for my $file (@ARGV) {
    my $src = do { open my $fh, "<", $file or die "$file: $!\n"; local $/; <$fh> };
    my $err = check($src);
    if ($err) { print "$file:$err\n"; $failed = 1 } else { print "$file: ok\n" }
    if ($listGlobals && !$err) {
        # Every name used without a local declaration, with the lines it appears on.
        for my $n (sort keys %globals) {
            my %seen; my @lines = grep { !$seen{$_}++ } @{ $globals{$n} };
            printf "  %-32s %s\n", $n, join(",", @lines[0 .. ($#lines < 5 ? $#lines : 5)]);
        }
    }
}
exit $failed;
